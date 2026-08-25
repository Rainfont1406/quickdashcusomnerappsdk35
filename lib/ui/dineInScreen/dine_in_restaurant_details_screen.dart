import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/model/BookingSlotModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/topupTranHistory.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_counters.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/rozorpayConroller.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/dineInScreen/booking_confirmation_screen.dart';
import 'package:emartconsumer/ui/wallet/walletScreen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class DineInRestaurantDetailsScreen extends StatefulWidget {
  final VendorModel vendorModel;

  const DineInRestaurantDetailsScreen({Key? key, required this.vendorModel})
      : super(key: key);

  @override
  State<DineInRestaurantDetailsScreen> createState() =>
      _DineInRestaurantDetailsScreenState();
}

class _DineInRestaurantDetailsScreenState
    extends State<DineInRestaurantDetailsScreen> {
  // ── State ──────────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  String _selectedTime = '';          // for flexible
  String _selectedSlotId = '';        // for slot-based
  String _selectedSlotStart = '';
  String _selectedSlotEnd = '';
  int _guestCount = 2;

  // Header image carousel (vendorMenuPhotos uploaded via AddDineIn)
  late PageController _headerCtrl;
  Timer? _headerTimer;
  int _headerPage = 0;

  // vendorMenuPhotos[0..n] = menu/ambience photos set by vendor in AddDineIn.
  // Entries may be a legacy URL string or a {original, cover} map.
  List<String> get _menuPhotos =>
      widget.vendorModel.vendorMenuPhotos
          .map((e) => VendorModel.coverPhotoUrl(e))
          .where((s) => s.isNotEmpty && s != 'null')
          .toList();

  // Slot booking count cache: slotId → count
  Map<String, int> _slotBookingCounts = {};
  bool _loadingSlotCounts = false;
  String? _slotLoadError;

  // Wallet balance
  double _walletBalance = 0.0;
  bool _walletLoaded = false;

  // Retry-safety for _confirmBooking (2026-08-24 fix): a pre-generated id
  // and a flag for whether its deposit has already been charged, kept as
  // STATE rather than locals so a second tap of Confirm after a failure
  // reuses both instead of generating a fresh bookingId and re-charging.
  // createVerifiedTableBookingPayment's own replay-guard (paymentIntents.js)
  // rejects a second real charge for the same bookingId anyway, but reusing
  // it here means a retry after the booking write itself fails goes
  // straight to retrying just that write - no confusing "already_paid"
  // round-trip. Cleared only once a booking actually succeeds.
  String? _pendingBookingId;
  bool _paymentAlreadyConsumed = false;

  // Orange — used only for price/offer emphasis (rating, total, pricing chip)
  static const Color _accent = AppThemeData.accent500;

  // Purple — used for all interactive/brand elements (AppBar, selected states,
  // action buttons, section icons, stepper controls)
  static const Color _primary = AppThemeData.primary500;
  static const LinearGradient _primaryGrad = LinearGradient(
    colors: [AppThemeData.primary500, AppThemeData.primary400],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Interest-duration signal, mirroring newVendorProductsScreen.dart's
  // dwell timer — single bounded Timer, fires once, cancelled in dispose()
  // if left early. Never a repeating/continuous timer.
  Timer? _dwellTimer;

  // Restaurant Engagement session (Phase 2, 2026-07-24, collection-only) -
  // a lighter version of NewVendorProductsScreen's own: this screen is a
  // dine-in booking flow (date/slot/guest picker), not a product menu, so
  // there is no product-view/add-to-cart signal to collect here - only
  // entry source + how long the customer spent on this screen. See
  // newVendorProductsScreen.dart's _trackRestaurantSessionEnded for the
  // full-featured sibling.
  String _restaurantSessionId = '';
  String _sessionEntrySource = 'Direct';
  DateTime? _sessionStartedAt;
  bool _sessionEndFired = false;

  @override
  void initState() {
    super.initState();
    _guestCount = widget.vendorModel.minGuests.clamp(1, 100);
    if (widget.vendorModel.bookingType == 'slot_based') {
      _loadSlotCounts();
    }
    _fetchWalletBalance();
    _headerCtrl = PageController();
    final photos = _menuPhotos;
    if (photos.length > 1) {
      _headerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        final next = (_headerPage + 1) % photos.length;
        _headerCtrl.animateToPage(next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      });
    }

    _sessionStartedAt = DateTime.now();
    final session = BehaviorTracker.startRestaurantSession(widget.vendorModel.id);
    _restaurantSessionId = session.sessionId;
    _sessionEntrySource = session.entrySource;

    // ignore: unawaited_futures
    _trackRestaurantOpened();
    _dwellTimer = Timer(const Duration(seconds: kDwellThresholdSeconds), () {
      BehaviorTracker.track(
          kEvtRestaurantInterest, {'vendorId': widget.vendorModel.id});
    });
  }

  Future<void> _trackRestaurantOpened() async {
    final visitCount =
        await BehaviorCounters.increment('restaurant_visit', widget.vendorModel.id);
    BehaviorTracker.track(kEvtRestaurantOpened, {
      'vendorId': widget.vendorModel.id,
      'cuisineIds': widget.vendorModel.cuisineIds,
      'visitCount': visitCount,
      'orderMode': 'Dining',
    });
  }

  void _trackRestaurantSessionEnded() {
    if (_sessionEndFired || _restaurantSessionId.isEmpty) return;
    _sessionEndFired = true;
    final startedAt = _sessionStartedAt ?? DateTime.now();
    BehaviorTracker.track(kEvtRestaurantSessionEnded, {
      'vendorId': widget.vendorModel.id,
      'sessionId': _restaurantSessionId,
      'entrySource': _sessionEntrySource,
      'searchKeyword': '',
      'searchType': '',
      'startedAt': startedAt.toIso8601String(),
      'menuDurationSeconds': DateTime.now().difference(startedAt).inSeconds,
      'productViewCount': 0,
      'categoriesBrowsedCount': 0,
      'addToCartCount': 0,
    });
  }

  @override
  void dispose() {
    _trackRestaurantSessionEnded();
    _headerTimer?.cancel();
    _headerCtrl.dispose();
    _dwellTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWalletBalance() async {
    if (MyAppState.currentUser == null) return;
    try {
      final user = await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID);
      if (mounted && user != null) {
        setState(() {
          _walletBalance = double.tryParse(user.wallet_amount.toString()) ?? 0.0;
          _walletLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _walletLoaded = true);
    }
  }

  // ── Slot Availability ──────────────────────────────────────────
  Future<void> _loadSlotCounts() async {
    if (!mounted) return;
    setState(() {
      _loadingSlotCounts = true;
      _slotLoadError = null;
    });
    try {
      final slots = widget.vendorModel.bookingSlots;
      // Fetch all slot counts in parallel — much faster than sequential awaits
      // and a single failure won't silently block the rest.
      final results = await Future.wait(
        slots.map(
          (slot) => FireStoreUtils.getBookingCountForDate(
            vendorId: widget.vendorModel.id,
            slotId: slot.id,
            date: _selectedDate,
          ).timeout(
            const Duration(seconds: 15),
            // Fail CLOSED (2026-08-24 fix): a timeout used to be treated as
            // "0 bookings," silently showing a possibly-full slot as
            // available. This is now display-only anyway - the real gate is
            // reserveBookingCapacity's transaction at confirm time - but a
            // stale "open" display is still bad UX, so a timeout now reads
            // as "assume full" instead, same as this slot really being full.
            onTimeout: () => slot.maxCapacity,
          ),
        ),
      );
      if (!mounted) return;
      final counts = <String, int>{};
      for (var i = 0; i < slots.length; i++) {
        counts[slots[i].id] = results[i];
      }
      setState(() {
        _slotBookingCounts = counts;
        _loadingSlotCounts = false;
        _slotLoadError = null;
        // Auto-deselect a slot that became unavailable
        if (_selectedSlotId.isNotEmpty) {
          final slot = widget.vendorModel.bookingSlots
              .where((s) => s.id == _selectedSlotId)
              .firstOrNull;
          if (slot == null || !_isSlotAvailable(slot)) {
            _selectedSlotId = '';
            _selectedSlotStart = '';
            _selectedSlotEnd = '';
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSlotCounts = false;
        _slotLoadError = 'Could not load time slots. Please check your connection and try again.'.tr();
      });
    }
  }

  bool _isSlotAvailable(BookingSlotModel slot) {
    if (!slot.isEnabled) return false;
    final count = _slotBookingCounts[slot.id] ?? 0;
    return count < slot.maxCapacity;
  }

  // ── Price calculation ──────────────────────────────────────────
  num get _totalCharge {
    final vendor = widget.vendorModel;
    switch (vendor.bookingPricingModel) {
      case 'per_person':
      case 'cover_charge':
        return vendor.bookingCharge * _guestCount;
      case 'table_charge':
        return vendor.bookingCharge;
      default:
        return 0;
    }
  }

  double _getKm() {
    if (MyAppState.selectedPosotion.location == null) return 0;
    return Geolocator.distanceBetween(
          widget.vendorModel.latitude,
          widget.vendorModel.longitude,
          MyAppState.selectedPosotion.location!.latitude,
          MyAppState.selectedPosotion.location!.longitude,
        ) /
        1000;
  }

  bool get _canConfirm {
    if (widget.vendorModel.bookingType == 'slot_based') {
      return _selectedSlotId.isNotEmpty;
    }
    return _selectedTime.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildSliverHeader(dark),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildRestaurantInfo(dark),
                    const SizedBox(height: 8),
                    _buildDateSelector(dark),
                    const SizedBox(height: 8),
                    if (widget.vendorModel.bookingType == 'slot_based')
                      _buildSlotGrid(dark)
                    else
                      _buildTimePicker(dark),
                    const SizedBox(height: 8),
                    _buildGuestStepper(dark),
                    const SizedBox(height: 8),
                    _buildPriceSummary(dark),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
          _buildConfirmButton(dark),
        ],
      ),
    );
  }

  // ─── Sliver Header ────────────────────────────────────────────
  Widget _buildSliverHeader(bool dark) {
    final photos = _menuPhotos;
    final fallback = getImageVAlidUrl(widget.vendorModel.photo);
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Menu photo carousel (vendorMenuPhotos from AddDineIn),
            // falls back to restaurant logo if none uploaded yet.
            photos.isEmpty
                ? CachedNetworkImage(
                    imageUrl: fallback,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: Colors.grey.shade300),
                    errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.restaurant,
                            size: 40, color: Colors.grey)),
                  )
                : PageView.builder(
                    controller: _headerCtrl,
                    itemCount: photos.length,
                    onPageChanged: (i) =>
                        setState(() => _headerPage = i),
                    itemBuilder: (_, i) => CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(photos[i]),
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade300),
                      errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.restaurant,
                              size: 40, color: Colors.grey)),
                    ),
                  ),
            // Dark gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 100,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            // Dot indicators
            if (photos.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(photos.length, (i) {
                    final active = i == _headerPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Restaurant Info ──────────────────────────────────────────
  Widget _buildRestaurantInfo(bool dark) {
    final vendor = widget.vendorModel;
    final rating = vendor.reviewsCount > 0
        ? vendor.reviewsSum / vendor.reviewsCount
        : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(vendor.title,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (vendor.cuisineNames.isNotEmpty) ...[
                Icon(Icons.restaurant_menu, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(vendor.cuisineNames.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: dark ? Colors.white60 : Colors.grey.shade600)),
                ),
                const SizedBox(width: 12),
              ],
              Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${_getKm().toStringAsFixed(1)} km',
                  style: TextStyle(
                      fontSize: 13, color: dark ? Colors.white60 : Colors.grey.shade600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                        width: 1)),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFF16A34A)),
                    const SizedBox(width: 3),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF15803D))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Booking type chip
          Row(
            children: [
              _chip(
                  vendor.bookingType == 'slot_based'
                      ? 'Slot Booking'.tr()
                      : 'Flexible Booking'.tr(),
                  vendor.bookingType == 'slot_based'
                      ? const Color(0xFF4CAF50)
                      : AppThemeData.primary500),
              const SizedBox(width: 8),
              if (vendor.bookingPricingModel != 'free')
                _chip(_pricingLabel(vendor), _accent),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Date Selector ────────────────────────────────────────────
  Widget _buildDateSelector(bool dark) {
    // Hard cap: a table can only be booked for today or tomorrow, regardless
    // of whatever the vendor has configured for maxAdvanceBookingDays -
    // clamp's upper bound is the actual enforcement point (2026-08-24).
    final maxDays = widget.vendorModel.maxAdvanceBookingDays.clamp(1, 2);
    final today = DateTime.now();
    final dates = List.generate(maxDays, (i) => today.add(Duration(days: i)));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(dark, Icons.calendar_today_rounded, 'Select Date'.tr()),
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: dates.length,
              itemBuilder: (_, i) {
                final date = dates[i];
                final isSelected = _selectedDate.year == date.year &&
                    _selectedDate.month == date.month &&
                    _selectedDate.day == date.day;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedSlotId = '';
                      _selectedSlotStart = '';
                      _selectedSlotEnd = '';
                    });
                    if (widget.vendorModel.bookingType == 'slot_based') _loadSlotCounts();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      gradient: isSelected ? _primaryGrad : null,
                      color: isSelected ? null : (dark ? Colors.grey.shade800 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('EEE').format(date),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.grey.shade500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : (dark ? Colors.white : Colors.black87)),
                        ),
                        Text(
                          DateFormat('MMM').format(date),
                          style: TextStyle(
                              fontSize: 10,
                              color: isSelected ? Colors.white70 : Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Slot Grid ────────────────────────────────────────────────
  Widget _buildSlotGrid(bool dark) {
    final enabledSlots = widget.vendorModel.bookingSlots.where((s) => s.isEnabled).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(dark, Icons.grid_view_rounded, 'Select Time Slot'.tr()),
          const SizedBox(height: 14),
          if (_loadingSlotCounts)
            _SlotGridSkeleton(dark: dark)
          else if (_slotLoadError != null)
            _buildSlotError(dark)
          else if (enabledSlots.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                child: Column(
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 36,
                        color: dark ? Colors.white30 : Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(
                      'No slots available for this date'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: dark ? Colors.white54 : Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try selecting a different date'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          color: dark ? Colors.white38 : Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: enabledSlots.map((slot) {
                final available = _isSlotAvailable(slot);
                final selected = _selectedSlotId == slot.id;
                final count = _slotBookingCounts[slot.id] ?? 0;
                final remaining = (slot.maxCapacity - count).clamp(0, slot.maxCapacity);

                return GestureDetector(
                  onTap: available
                      ? () => setState(() {
                            _selectedSlotId = slot.id;
                            _selectedSlotStart = slot.startTime;
                            _selectedSlotEnd = slot.endTime;
                          })
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: (MediaQuery.of(context).size.width - 72) / 2,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: selected ? _primaryGrad : null,
                      color: selected
                          ? null
                          : available
                              ? (dark ? Colors.grey.shade800 : Colors.grey.shade100)
                              : (dark ? Colors.grey.shade900 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : available
                                ? (dark ? Colors.grey.shade700 : Colors.grey.shade300)
                                : Colors.grey.shade400,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${slot.startTime}',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : available
                                      ? (dark ? Colors.white : Colors.black87)
                                      : Colors.grey),
                        ),
                        Text(
                          '${slot.endTime}',
                          style: TextStyle(
                              fontSize: 12,
                              color: selected ? Colors.white70 : Colors.grey.shade500),
                        ),
                        const SizedBox(height: 6),
                        if (!available)
                          Text('Fully Booked'.tr(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600))
                        else
                          Text('$remaining spots left'.tr(),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: selected ? Colors.white70 : Colors.grey.shade500)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ─── Time Picker (Flexible) ───────────────────────────────────
  Widget _buildTimePicker(bool dark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(dark, Icons.access_time_rounded, 'Select Time'.tr()),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () async {
              final minNotice = widget.vendorModel.minBookingNoticeMinutes;
              final earliest = DateTime.now().add(Duration(minutes: minNotice));
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(earliest),
                builder: (context, child) => Theme(
                  data: ThemeData.light().copyWith(
                      colorScheme: const ColorScheme.light(primary: _primary)),
                  child: child!,
                ),
              );
              if (t != null) setState(() => _selectedTime = t.format(context));
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedTime.isNotEmpty
                    ? _primary.withValues(alpha: 0.08)
                    : (dark ? Colors.grey.shade800 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedTime.isNotEmpty ? _primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      color: _selectedTime.isNotEmpty ? _primary : Colors.grey.shade400, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedTime.isEmpty ? 'Tap to select time'.tr() : _selectedTime,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: _selectedTime.isNotEmpty ? FontWeight.w700 : FontWeight.normal,
                        color: _selectedTime.isNotEmpty
                            ? _primary
                            : (dark ? Colors.white38 : Colors.grey.shade400),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: dark ? Colors.white38 : Colors.grey.shade400),
                ],
              ),
            ),
          ),
          if (widget.vendorModel.minBookingNoticeMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Min ${widget.vendorModel.minBookingNoticeMinutes} min advance notice required'.tr(),
                style: TextStyle(fontSize: 11, color: dark ? Colors.white38 : Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Guest Stepper ────────────────────────────────────────────
  Widget _buildGuestStepper(bool dark) {
    final vendor = widget.vendorModel;
    final canDecrement = _guestCount > vendor.minGuests;
    final canIncrement = _guestCount < vendor.maxGuests;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(dark, Icons.people_alt_outlined, 'Number of Guests'.tr()),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperBtn(
                icon: Icons.remove_rounded,
                enabled: canDecrement,
                onTap: () => setState(() => _guestCount--),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 80,
                child: Text(
                  '$_guestCount',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              _stepperBtn(
                icon: Icons.add_rounded,
                enabled: canIncrement,
                onTap: () => setState(() => _guestCount++),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '${vendor.minGuests}–${vendor.maxGuests} guests allowed'.tr(),
              style: TextStyle(
                  fontSize: 12, color: dark ? Colors.white38 : Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: enabled ? _primaryGrad : null,
          color: enabled ? null : Colors.grey.shade300,
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [BoxShadow(color: _primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Icon(icon, color: enabled ? Colors.white : Colors.grey.shade500, size: 22),
      ),
    );
  }

  // ─── Price Summary ────────────────────────────────────────────
  Widget _buildPriceSummary(bool dark) {
    final vendor = widget.vendorModel;
    final isFree = vendor.bookingPricingModel == 'free';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(dark, Icons.receipt_outlined, 'Price Summary'.tr()),
          const SizedBox(height: 14),
          if (isFree)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 20),
                  const SizedBox(width: 10),
                  Text('No booking charge — Completely free!'.tr(),
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else ...[
            _priceRow(dark, _priceLineLabel(vendor), amountShow(amount: vendor.bookingCharge.toString(), decimals: 0)),
            if (vendor.bookingPricingModel == 'per_person' ||
                vendor.bookingPricingModel == 'cover_charge') ...[
              const SizedBox(height: 6),
              _priceRow(dark, 'Guests'.tr(), '× $_guestCount'),
            ],
            Divider(height: 20, color: dark ? Colors.white12 : Colors.grey.shade200),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total'.tr(),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : Colors.black87)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    amountShow(amount: _totalCharge.toString(), decimals: 0),
                    key: ValueKey(_totalCharge),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _accent),
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: dark ? Colors.white12 : Colors.grey.shade200),
            // ── Payment method ──────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, size: 16, color: _primary),
                ),
                const SizedBox(width: 10),
                Text('Payment Method'.tr(),
                    style: TextStyle(fontSize: 13, color: dark ? Colors.white60 : Colors.grey.shade600)),
                const Spacer(),
                Text('Wallet'.tr(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white : Colors.black87)),
              ],
            ),
            const SizedBox(height: 12),
            // ── Wallet balance indicator ────────────────────────────
            _buildWalletBalanceRow(dark),
          ],
        ],
      ),
    );
  }

  String _priceLineLabel(VendorModel vendor) {
    switch (vendor.bookingPricingModel) {
      case 'per_person':
        return 'Per person'.tr();
      case 'table_charge':
        return 'Table reservation charge'.tr();
      case 'cover_charge':
        return 'Cover charge / person'.tr();
      default:
        return '';
    }
  }

  Widget _priceRow(bool dark, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: dark ? Colors.white60 : Colors.grey.shade600)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildWalletBalanceRow(bool dark) {
    if (!_walletLoaded) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final bool sufficient = _walletBalance >= _totalCharge;
    final Color statusColor = sufficient ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final Color bgColor = sufficient
        ? const Color(0xFFE8F5E9)
        : (dark ? const Color(0xFF3E1A1A) : const Color(0xFFFFEBEE));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(
                sufficient ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                size: 16,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                amountShow(amount: _walletBalance.toStringAsFixed(2)),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sufficient ? '· ${"Sufficient balance".tr()}' : '· ${"Insufficient balance".tr()}',
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
              ),
            ],
          ),
        ),
        if (!sufficient) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => push(context, const WalletScreen(showAppBar: true)).then((_) => _fetchWalletBalance()),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(color: _primary, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline_rounded, size: 16, color: _primary),
                  const SizedBox(width: 6),
                  Text(
                    'Add Wallet Balance'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Confirm Button ───────────────────────────────────────────
  Widget _buildConfirmButton(bool dark) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xff1a1a1a) : Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -4)),
          ],
        ),
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _canConfirm ? _confirmBooking : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _canConfirm ? null : Colors.grey.shade300,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: _canConfirm ? 6 : 0,
              shadowColor: _primary.withValues(alpha: 0.4),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: _canConfirm ? _primaryGrad : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_seat_rounded,
                        color: _canConfirm ? Colors.white : Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Confirm Booking'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _canConfirm ? Colors.white : Colors.grey,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Confirm Logic ────────────────────────────────────────────
  Future<void> _confirmBooking() async {
    if (MyAppState.currentUser == null) {
      push(context, const LoginScreen());
      return;
    }

    _showSkeletonLoader();

    final vendor = widget.vendorModel;
    final user = MyAppState.currentUser!;
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final bool isSlotBased = vendor.bookingType == 'slot_based';

    // ── Atomic capacity reservation (2026-08-24 fix) ────────────────
    // Reserved BEFORE payment, for BOTH slot-based and flexible bookings -
    // closes the read-then-write race two concurrent bookers could
    // otherwise both pass, and gives a 'flexible' vendor a real capacity
    // ceiling against vendor.guestCapacity for the first time (previously
    // flexible bookings had zero capacity enforcement at all).
    bool capacityReserved = false;
    try {
      final slot = isSlotBased
          ? vendor.bookingSlots.firstWhere((s) => s.id == _selectedSlotId)
          : null;
      final maxCapacity = isSlotBased ? slot!.maxCapacity : vendor.guestCapacity;
      await FireStoreUtils.reserveBookingCapacity(
        vendorId: vendor.id,
        bookingType: vendor.bookingType,
        slotId: isSlotBased ? _selectedSlotId : '',
        dateKey: dateKey,
        guestCount: _guestCount,
        maxCapacity: maxCapacity,
      );
      capacityReserved = true;
    } on SlotCapacityExceededException catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message.tr()), backgroundColor: Colors.red),
      );
      if (isSlotBased) await _loadSlotCounts();
      return;
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed. Please try again.'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Reused across retries (2026-08-24 fix) - a second Confirm tap after
      // a failure below must not mint a new bookingId and re-charge.
      _pendingBookingId ??= FireStoreUtils.firestore.collection(ORDERS_TABLE).doc().id;
      final bookingId = _pendingBookingId!;

      // ── Wallet check + deduction (when charge applies) ───────
      // Server-verified and atomic: the charge is re-derived from the
      // vendor's own bookingPricingModel/bookingCharge config, and the
      // balance check + deduction + ledger write all happen inside one
      // Firestore transaction server-side (see
      // createVerifiedTableBookingPayment) — no client-side wallet write.
      // Skipped on a retry that already paid (_paymentAlreadyConsumed) -
      // that function's own replay-guard would reject a second real charge
      // for the same bookingId anyway, but skipping avoids the round-trip.
      if (_totalCharge > 0 && !_paymentAlreadyConsumed) {
        final result = await RazorPayController().createVerifiedTableBookingPayment(
          vendorID: vendor.id,
          guestCount: _guestCount,
          bookingId: bookingId,
        );

        if (!result.success) {
          Navigator.pop(context);
          await FireStoreUtils.releaseBookingCapacity(
            vendorId: vendor.id,
            bookingType: vendor.bookingType,
            slotId: isSlotBased ? _selectedSlotId : '',
            dateKey: dateKey,
            guestCount: _guestCount,
          );
          // Payment never went through, so there's nothing to preserve for
          // a retry - a fresh bookingId next attempt is fine.
          _pendingBookingId = null;
          if (result.deviceSuperseded) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.errorMessage!), backgroundColor: Colors.red),
            );
            push(context, const LoginScreen());
            return;
          }
          if (result.insufficientBalance) {
            _fetchWalletBalance();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Booking not completed. Please try again.'.tr()),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }

        _paymentAlreadyConsumed = true;
        // Keep local cache in sync with the server-verified deduction.
        final newBalance = _walletBalance - result.amount;
        MyAppState.currentUser!.wallet_amount = newBalance;
        if (mounted) setState(() => _walletBalance = newBalance);
      }

      // ── Create booking ───────────────────────────────────────
      final bookingDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      final booking = BookTableModel(
        id: bookingId,
        author: user,
        authorID: user.userID,
        createdAt: Timestamp.now(),
        date: Timestamp.fromDate(bookingDateTime),
        vendorID: vendor.id,
        vendor: vendor,
        section_id: sectionConstantModel?.id ?? '',
        status: vendor.approvalMode == 'auto' ? ORDER_STATUS_ACCEPTED : ORDER_STATUS_PLACED,
        guestFirstName: user.firstName,
        guestLastName: user.lastName,
        guestEmail: user.email,
        guestPhone: user.phoneNumber,
        totalGuest: _guestCount,
        bookingType: vendor.bookingType,
        slotId: _selectedSlotId,
        selectedTime: vendor.bookingType == 'slot_based' ? _selectedSlotStart : _selectedTime,
        selectedEndTime: vendor.bookingType == 'slot_based' ? _selectedSlotEnd : '',
        bookingDate: DateFormat('EEE, MMM d yyyy').format(_selectedDate),
        bookingDateKey: dateKey,
        pricingModel: vendor.bookingPricingModel,
        bookingCharge: vendor.bookingCharge,
        totalCharge: _totalCharge,
        approvalMode: vendor.approvalMode,
      );

      final saved = await FireStoreUtils().bookTable(booking);

      // Vendor push notification (best-effort)
      try {
        await FireStoreUtils.firestore.collection('notifications').add({
          'to': vendor.fcmToken,
          'title': 'New Table Booking',
          'body': '${user.firstName} ${user.lastName} booked a table for $_guestCount guests on ${booking.bookingDate}',
          'createdAt': Timestamp.now(),
        });
      } catch (_) {}

      // Fresh state for the next booking - this one succeeded.
      _pendingBookingId = null;
      _paymentAlreadyConsumed = false;

      Navigator.pop(context);
      push(context, BookingConfirmationScreen(booking: saved));
    } catch (e) {
      // The booking write (or something after a successful charge) failed.
      // Release the reservation - a retry will re-reserve it - but keep
      // _pendingBookingId/_paymentAlreadyConsumed intact when a real charge
      // already went through (2026-08-24 fix): the next Confirm tap reuses
      // the same already-paid intent and retries only the booking write,
      // instead of minting a new id and charging a second time. This is
      // also what closes the "charged with no booking to show for it" gap -
      // the customer isn't stuck; retrying finishes the same paid booking.
      if (capacityReserved) {
        try {
          await FireStoreUtils.releaseBookingCapacity(
            vendorId: vendor.id,
            bookingType: vendor.bookingType,
            slotId: isSlotBased ? _selectedSlotId : '',
            dateKey: dateKey,
            guestCount: _guestCount,
          );
        } catch (_) {}
      }
      if (!_paymentAlreadyConsumed) {
        _pendingBookingId = null;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _paymentAlreadyConsumed
                ? 'Payment received, but your booking couldn\'t be saved. Please tap Confirm again to finish - you won\'t be charged twice.'.tr()
                : 'Booking failed. Please try again.'.tr(),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: _paymentAlreadyConsumed ? 6 : 4),
        ),
      );
    }
  }

  void _showSkeletonLoader() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BookingSkeletonLoader(),
    );
  }

  // ─── Slot error state (retry button) ─────────────────────────
  Widget _buildSlotError(bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_off_rounded,
                size: 32, color: AppThemeData.primary500),
          ),
          const SizedBox(height: 10),
          Text(
            _slotLoadError ?? 'Failed to load slots'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: dark ? Colors.white60 : Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _loadSlotCounts,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppThemeData.primary500, AppThemeData.primary400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppThemeData.primary500.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Retry'.tr(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared helpers ───────────────────────────────────────────
  BoxDecoration _cardDeco(bool dark) => BoxDecoration(
        color: dark ? const Color(0xff1e1e1e) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      );

  Widget _sectionTitle(bool dark, IconData icon, String title) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(gradient: _primaryGrad, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : Colors.black87)),
        ],
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.9))),
      );

  String _pricingLabel(VendorModel vendor) {
    final String amt = amountShow(amount: vendor.bookingCharge.toString(), decimals: 0);
    switch (vendor.bookingPricingModel) {
      case 'per_person':
        return '$amt/person';
      case 'table_charge':
        return '$amt table';
      case 'cover_charge':
        return '$amt cover';
      default:
        return 'Free'.tr();
    }
  }
}

// ─── Skeleton Loader ────────────────────────────────────────────────
class _BookingSkeletonLoader extends StatefulWidget {
  const _BookingSkeletonLoader();

  @override
  State<_BookingSkeletonLoader> createState() => _BookingSkeletonLoaderState();
}

class _BookingSkeletonLoaderState extends State<_BookingSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Column(
                children: [
                  _shimmer(200, 16),
                  const SizedBox(height: 10),
                  _shimmer(150, 12),
                  const SizedBox(height: 16),
                  _shimmer(double.infinity, 12),
                  const SizedBox(height: 8),
                  _shimmer(double.infinity, 12),
                  const SizedBox(height: 8),
                  _shimmer(double.infinity, 12),
                  const SizedBox(height: 20),
                  _shimmer(160, 44),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Validating & Confirming Booking...'.tr(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeData.primary500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmer(double width, double height) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Color.lerp(Colors.grey.shade200, Colors.grey.shade100, _anim.value),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ─── Slot Grid Shimmer Skeleton ─────────────────────────────────────────
// Shown while slot counts are being fetched from Firestore.
class _SlotGridSkeleton extends StatefulWidget {
  final bool dark;
  const _SlotGridSkeleton({required this.dark});

  @override
  State<_SlotGridSkeleton> createState() => _SlotGridSkeletonState();
}

class _SlotGridSkeletonState extends State<_SlotGridSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, double t) {
    final base = widget.dark ? const Color(0xFF2C2C2C) : const Color(0xFFECECEC);
    final hi = widget.dark ? const Color(0xFF424242) : const Color(0xFFF8F8F8);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [base, hi, base],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-2.0 + 2.6 * t, 0),
          end: Alignment(-0.4 + 2.6 * t, 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final w = (MediaQuery.of(context).size.width - 72) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(4, (i) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(w, 80, t),
              ],
            );
          }),
        );
      },
    );
  }
}
