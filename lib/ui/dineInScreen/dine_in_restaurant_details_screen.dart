import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/model/BookingSlotModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/dineInScreen/booking_confirmation_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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

  // Slot booking count cache: slotId → count
  Map<String, int> _slotBookingCounts = {};
  bool _loadingSlotCounts = false;
  String? _slotLoadError;

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

  @override
  void initState() {
    super.initState();
    // Clamp guest count to vendor's limits
    _guestCount = widget.vendorModel.minGuests.clamp(1, 100);
    if (widget.vendorModel.bookingType == 'slot_based') {
      _loadSlotCounts();
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
          (slot) => FireStoreUtils.getSlotBookingCount(
            vendorId: widget.vendorModel.id,
            slotId: slot.id,
            date: _selectedDate,
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () => 0, // treat timeout as 0 bookings so slot stays selectable
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
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: getImageVAlidUrl(widget.vendorModel.photo),
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: Colors.grey.shade300),
              errorWidget: (_, __, ___) =>
                  Container(color: Colors.grey.shade300,
                      child: const Icon(Icons.restaurant, size: 40, color: Colors.grey)),
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
              if (vendor.cuisineType.isNotEmpty) ...[
                Icon(Icons.restaurant_menu, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(vendor.cuisineType,
                    style: TextStyle(
                        fontSize: 13, color: dark ? Colors.white60 : Colors.grey.shade600)),
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
                    color: AppThemeData.accent50, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppThemeData.accent500),
                    const SizedBox(width: 3),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppThemeData.accent600)),
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
    final maxDays = widget.vendorModel.maxAdvanceBookingDays.clamp(1, 60);
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
          const SizedBox(height: 6),
          Text('30-minute dining sessions'.tr(),
              style: TextStyle(fontSize: 12, color: dark ? Colors.white54 : Colors.grey.shade500)),
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
    final sym = currencyData?.symbol ?? '₹';
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
            _priceRow(dark, _priceLineLabel(vendor), '$sym${vendor.bookingCharge.toStringAsFixed(0)}'),
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
                    '$sym${_totalCharge.toStringAsFixed(0)}',
                    key: ValueKey(_totalCharge),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _accent),
                  ),
                ),
              ],
            ),
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

    // Show skeleton loading overlay
    _showSkeletonLoader();

    try {
      final vendor = widget.vendorModel;
      final user = MyAppState.currentUser!;

      // Validate slot availability (real-time check)
      if (vendor.bookingType == 'slot_based') {
        final count = await FireStoreUtils.getSlotBookingCount(
          vendorId: vendor.id,
          slotId: _selectedSlotId,
          date: _selectedDate,
        );
        final slot = vendor.bookingSlots.firstWhere((s) => s.id == _selectedSlotId);
        if (count >= slot.maxCapacity) {
          Navigator.pop(context); // close loader
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sorry, this slot is fully booked. Please choose another.'.tr()),
              backgroundColor: Colors.red,
            ),
          );
          await _loadSlotCounts();
          return;
        }
      }

      // Build booking date timestamp
      final bookingDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      final booking = BookTableModel(
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
        pricingModel: vendor.bookingPricingModel,
        bookingCharge: vendor.bookingCharge,
        totalCharge: _totalCharge,
        approvalMode: vendor.approvalMode,
      );

      final saved = await FireStoreUtils().bookTable(booking);

      // Write notification to Firestore for vendor push notification
      try {
        await FireStoreUtils.firestore.collection('notifications').add({
          'to': vendor.fcmToken,
          'title': 'New Table Booking',
          'body': '${user.firstName} ${user.lastName} booked a table for $_guestCount guests on ${booking.bookingDate}',
          'createdAt': Timestamp.now(),
        });
      } catch (_) {}

      Navigator.pop(context); // close loader
      push(context, BookingConfirmationScreen(booking: saved));
    } catch (e) {
      Navigator.pop(context); // close loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed. Please try again.'.tr()),
          backgroundColor: Colors.red,
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
    final sym = currencyData?.symbol ?? '₹';
    switch (vendor.bookingPricingModel) {
      case 'per_person':
        return '$sym${vendor.bookingCharge.toStringAsFixed(0)}/person';
      case 'table_charge':
        return '$sym${vendor.bookingCharge.toStringAsFixed(0)} table';
      case 'cover_charge':
        return '$sym${vendor.bookingCharge.toStringAsFixed(0)} cover';
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
