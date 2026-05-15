import 'dart:async';
import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/send_notification.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/dineInScreen/my_booking_screen.dart';
import 'package:emartconsumer/ui/fullScreenImageViewer/FullScreenImageViewer.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/photos.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../vendorProductsScreen/newVendorProductsScreen.dart';

class DineInRestaurantDetailsScreen extends StatefulWidget {
  final VendorModel vendorModel;

  const DineInRestaurantDetailsScreen({Key? key, required this.vendorModel}) : super(key: key);

  @override
  State<DineInRestaurantDetailsScreen> createState() => _DineInRestaurantDetailsScreenState();
}

class _DineInRestaurantDetailsScreenState extends State<DineInRestaurantDetailsScreen> {
  final fireStoreUtils = FireStoreUtils();

  String _selectedOccasion = '';
  bool _isFirstTime = false;
  int _guestCount = 2;
  final TextEditingController _reqController = TextEditingController();

  String _userFName = '', _userLName = '', _userPhone = '', _userEmail = '';

  var position = const LatLng(23.12, 70.22);
  late Future<List<RatingModel>> ratingFuture;

  var tags = [];
  late List<String> occasionList;
  List<Timestamp> dateList = [];
  List<DateTime> timeSlotList = [];

  Timestamp? _selectedDate;
  String _selectedTimeSlot = '';

  void _getUserLocation() {
    setState(() {
      position = LatLng(
        MyAppState.selectedPosotion.location!.latitude,
        MyAppState.selectedPosotion.location!.longitude,
      );
    });
  }

  DateTime _stringToDate(String time) {
    return DateFormat('HH:mm').parse(
      DateFormat('HH:mm').format(
        DateFormat('hh:mm a').parse(
          (Intl.getCurrentLocale() == 'en_US') ? time : time.toLowerCase(),
        ),
      ),
    );
  }

  int _calculateDifference(DateTime date) {
    final now = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  List<DateTime> get _availableTimeSlots {
    if (_selectedDate == null || timeSlotList.isEmpty) return timeSlotList;
    final now = DateTime.now();
    final selected = _selectedDate!.toDate();
    final isToday = selected.year == now.year &&
        selected.month == now.month &&
        selected.day == now.day;
    if (!isToday) return timeSlotList;
    final cutoff = now.add(const Duration(minutes: 30));
    return timeSlotList.where((slot) {
      final slotToday = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
      return slotToday.isAfter(cutoff);
    }).toList();
  }

  void _onDateSelected(Timestamp ts) {
    setState(() {
      _selectedDate = ts;
      final available = _availableTimeSlots;
      if (available.isNotEmpty) {
        _selectedTimeSlot = DateFormat('hh:mm a').format(available.first);
      } else {
        _selectedTimeSlot = '';
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    occasionList = ['Birthday'.tr(), 'Anniversary'.tr()];

    for (int i = 0; i < 10; i++) {
      dateList.add(Timestamp.fromDate(DateTime.now().add(Duration(days: i))));
    }

    DateTime startTime = DateTime.now().add(const Duration(hours: 9));
    DateTime endTime = DateTime.now().add(const Duration(hours: 21));

    if (widget.vendorModel.openDineTime.isNotEmpty) {
      startTime = _stringToDate(widget.vendorModel.openDineTime);
    }
    if (widget.vendorModel.closeDineTime.isNotEmpty) {
      endTime = _stringToDate(widget.vendorModel.closeDineTime);
    }

    for (DateTime t = startTime; t.isBefore(endTime); t = t.add(const Duration(minutes: 30))) {
      timeSlotList.add(t);
    }

    // Auto-select today and first available slot
    _selectedDate = dateList.isNotEmpty ? dateList[0] : null;
    final available = _availableTimeSlots;
    _selectedTimeSlot = available.isNotEmpty ? DateFormat('hh:mm a').format(available.first) : '';

    ratingFuture = fireStoreUtils.getReviewsbyVendorID(widget.vendorModel.id);
    fireStoreUtils.getVendorCusions(widget.vendorModel.id).then((value) {
      tags.addAll(value);
      if (mounted) setState(() {});
    });

    if (MyAppState.currentUser != null) {
      _userFName = MyAppState.currentUser!.firstName;
      _userLName = MyAppState.currentUser!.lastName;
      _userEmail = MyAppState.currentUser!.email;
      _userPhone = MyAppState.currentUser!.phoneNumber;
    }
  }

  @override
  void dispose() {
    _reqController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    double distanceInMeters = Geolocator.distanceBetween(
        widget.vendorModel.latitude, widget.vendorModel.longitude,
        position.latitude, position.longitude);
    double kilometer = distanceInMeters / 1000;
    double minutes = 1.2;
    double value = minutes * kilometer;
    final int hour = value ~/ 60;
    final double minute = value % 60;

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: SingleChildScrollView(
        child: Container(
          color: dark ? Colors.black : const Color(0xffFFFFFF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(children: [
                Container(
                  height: MediaQuery.of(context).size.height * 0.3,
                  width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: getImageVAlidUrl(widget.vendorModel.photo),
                    imageBuilder: (context, imageProvider) => Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
                      ),
                    ),
                    placeholder: (context, url) => Container(
                      color: AppThemeData.grey100,
                      child: Center(child: CircularProgressIndicator.adaptive(
                        valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                      )),
                    ),
                    errorWidget: (context, url, error) => Image.network(
                      placeholderImage,
                      fit: BoxFit.cover,
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 20,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 12,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => push(context, StorePhotos(vendorModel: widget.vendorModel)),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(children: [
                          Icon(Icons.photo_library_outlined, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Photos', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ]),
              // Title + open/closed
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.vendorModel.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontFamily: AppThemeData.semiBold,
                          color: dark ? Colors.white : const Color(0xff2A2A2A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildOpenClosedBadge(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(children: [
                  Icon(Icons.location_on_outlined, size: 16, color: AppThemeData.grey400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.vendorModel.location,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13, color: AppThemeData.grey400),
                    ),
                  ),
                ]),
              ),
              // Info row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF1A1A2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: dark
                        ? []
                        : [BoxShadow(color: Colors.grey.shade200, blurRadius: 8, spreadRadius: 1)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _infoColumn(
                        icon: Icons.straighten,
                        label: '${kilometer.toStringAsFixed(currencyData?.decimal ?? 1)} km',
                      ),
                      _verticalDivider(),
                      _infoColumn(
                        icon: Icons.payments_outlined,
                        label: widget.vendorModel.vendorCost == 0
                            ? 'Free'.tr()
                            : amountShow(amount: widget.vendorModel.vendorCost.toString()) + ' for 2',
                      ),
                      _verticalDivider(),
                      _infoColumn(
                        icon: Icons.star_rounded,
                        label: widget.vendorModel.reviewsCount == 0
                            ? '0.0'
                            : (widget.vendorModel.reviewsSum / widget.vendorModel.reviewsCount)
                                .toStringAsFixed(1),
                      ),
                      _verticalDivider(),
                      GestureDetector(
                        onTap: () async {
                          await Share.share(
                            '${widget.vendorModel.location}\n${widget.vendorModel.photo}',
                            subject: widget.vendorModel.title,
                          );
                        },
                        child: _infoColumn(icon: Icons.share_outlined, label: 'Share'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
              // Delivery card
              _actionCard(
                context: context,
                icon: 'assets/images/food_delivery.png',
                title: 'Available food delivery'.tr(),
                subtitle:
                    '${hour.toString().padLeft(2, '0')}h ${minute.toStringAsFixed(0).padLeft(2, '0')} ${'min'.tr()}',
                onTap: () => push(context, NewVendorProductsScreen(vendorModel: widget.vendorModel)),
              ),
              // Book a table card
              _actionCard(
                context: context,
                icon: 'assets/images/book_table.png',
                title: 'Book a Table'.tr(),
                subtitle: 'Get instant confirmation'.tr(),
                onTap: () {
                  if (MyAppState.currentUser == null) {
                    push(context, const LoginScreen());
                  } else {
                    _bookTableSheet();
                  }
                },
                highlight: true,
              ),
              // Menu photos
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Menus'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: AppThemeData.semiBold,
                          color: dark ? Colors.white : Colors.black,
                        )),
                    if (widget.vendorModel.vendorMenuPhotos.isNotEmpty)
                      GestureDetector(
                        onTap: () => push(context,
                            StoreMenuPhoto(vendorMenuPhotos: widget.vendorModel.vendorMenuPhotos)),
                        child: Text('View All'.tr(),
                            style: TextStyle(color: AppThemeData.primary500, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              widget.vendorModel.vendorMenuPhotos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: showEmptyState('No Menu Photos'.tr(), context),
                    )
                  : SizedBox(
                      height: 100,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.vendorModel.vendorMenuPhotos.length,
                        itemBuilder: (context, index) {
                          return InkWell(
                            onTap: () => push(context,
                                FullScreenImageViewer(
                                    imageUrl: widget.vendorModel.vendorMenuPhotos[index])),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CachedNetworkImage(
                                  height: 80,
                                  width: 80,
                                  imageUrl: getImageVAlidUrl(
                                      widget.vendorModel.vendorMenuPhotos[index]),
                                  fit: BoxFit.cover,
                                  placeholder: (c, u) => Container(color: AppThemeData.grey100),
                                  errorWidget: (c, u, e) =>
                                      Image.network(placeholderImage, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: Colors.black12),
              ),
              // Info section
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  _infoRow(
                    iconAsset: 'assets/images/time.png',
                    title: 'Timings'.tr(),
                    value:
                        '${widget.vendorModel.openDineTime.isEmpty ? "10:00 AM" : widget.vendorModel.openDineTime}'
                        ' — '
                        '${widget.vendorModel.closeDineTime.isEmpty ? "10:00 PM" : widget.vendorModel.closeDineTime}',
                    dark: dark,
                  ),
                  const SizedBox(height: 14),
                  _infoRow(
                    iconAsset: 'assets/images/price.png',
                    title: 'Cost'.tr(),
                    value: widget.vendorModel.vendorCost == 0
                        ? 'Approx cost is not added'.tr()
                        : '${'Cost for two'.tr()} ${amountShow(amount: widget.vendorModel.vendorCost.toString())} (${'Approx'.tr()})',
                    dark: dark,
                  ),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Image(
                        image: const AssetImage('assets/images/location.png'),
                        color: AppThemeData.primary500,
                        height: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Location'.tr(),
                            style: TextStyle(
                              fontFamily: AppThemeData.semiBold,
                              color: dark ? Colors.white : Colors.black,
                            )),
                        const SizedBox(height: 2),
                        Text(widget.vendorModel.location,
                            style: TextStyle(
                                color: dark ? AppThemeData.grey300 : AppThemeData.grey600)),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () => launchUrl(createCoordinatesUrl(
                          widget.vendorModel.latitude, widget.vendorModel.longitude,
                          widget.vendorModel.title)),
                      child: Text('Direction'.tr(),
                          style: TextStyle(color: AppThemeData.primary500, fontSize: 13)),
                    ),
                  ]),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Divider(color: Colors.black12),
              ),
              // Cuisines
              if (tags.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('Cuisines'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: AppThemeData.semiBold,
                        color: dark ? Colors.white : Colors.black,
                      )),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: tags
                        .map((tag) => Chip(
                              label: Text('$tag',
                                  style: TextStyle(color: AppThemeData.primary500, fontSize: 12)),
                              backgroundColor: AppThemeData.primary500.withOpacity(0.08),
                              side: BorderSide(color: AppThemeData.primary500.withOpacity(0.3)),
                              padding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpenClosedBadge() {
    final bool open = widget.vendorModel.reststatus == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: open ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: open ? const Color(0xFF2E7D32) : AppThemeData.error500),
        const SizedBox(width: 5),
        Text(
          open ? 'Open'.tr() : 'Closed'.tr(),
          style: TextStyle(
            fontSize: 12,
            fontFamily: AppThemeData.semiBold,
            color: open ? const Color(0xFF2E7D32) : AppThemeData.error500,
          ),
        ),
      ]),
    );
  }

  Widget _infoColumn({required IconData icon, required String label}) {
    final bool dark = isDarkMode(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppThemeData.primary500, size: 22),
      const SizedBox(height: 6),
      Text(label,
          style: TextStyle(
            fontSize: 11,
            color: dark ? AppThemeData.grey300 : AppThemeData.grey600,
          ),
          textAlign: TextAlign.center),
    ]);
  }

  Widget _verticalDivider() {
    return Container(height: 32, width: 1, color: AppThemeData.grey200);
  }

  Widget _actionCard({
    required BuildContext context,
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    final bool dark = isDarkMode(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: highlight
              ? Border.all(color: AppThemeData.primary500.withOpacity(0.4), width: 1.2)
              : Border.all(color: Colors.black12, width: 0.8),
          boxShadow: dark
              ? []
              : [BoxShadow(color: Colors.grey.shade200, blurRadius: 8, spreadRadius: 1)],
        ),
        child: Row(children: [
          Image(image: AssetImage(icon), height: 32, color: AppThemeData.primary500),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    fontSize: 14,
                    color: dark ? Colors.white : Colors.black,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                  )),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: highlight ? AppThemeData.primary500 : Colors.black26,
                width: 1,
              ),
            ),
            child: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: highlight ? AppThemeData.primary500 : (dark ? Colors.white54 : Colors.black54),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoRow({
    required String iconAsset,
    required String title,
    required String value,
    required bool dark,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Image(image: AssetImage(iconAsset), color: AppThemeData.primary500, height: 22),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                fontFamily: AppThemeData.semiBold,
                color: dark ? Colors.white : Colors.black,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: dark ? AppThemeData.grey300 : AppThemeData.grey600, fontSize: 13)),
        ]),
      ),
    ]);
  }

  // ─── Booking Sheet ──────────────────────────────────────────────────────────

  void _bookTableSheet() {
    // Reset per-session state
    _selectedOccasion = '';
    _isFirstTime = false;
    _guestCount = 2;
    _reqController.clear();
    _selectedDate = dateList.isNotEmpty ? dateList[0] : null;
    final available = _availableTimeSlots;
    _selectedTimeSlot = available.isNotEmpty ? DateFormat('hh:mm a').format(available.first) : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bool dark = isDarkMode(context);
          final available = _availableTimeSlots;
          final double sheetH = (MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - 32)
              .clamp(400.0, MediaQuery.of(context).size.height * 0.92);
          return Container(
            height: sheetH,
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgSecondary : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Book a Table'.tr(),
                              style: TextStyle(
                                fontSize: 18,
                                fontFamily: AppThemeData.semiBold,
                                color: dark ? Colors.white : Colors.black,
                              )),
                          Text(widget.vendorModel.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                              )),
                        ]),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close,
                            color: dark ? Colors.white54 : Colors.black45, size: 22),
                      ),
                    ],
                  ),
                ),
                Divider(color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey200,
                    height: 1),
                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // DATE
                        _sheetSection(
                          label: 'Select Date'.tr(),
                          dark: dark,
                          child: SizedBox(
                            height: (MediaQuery.of(context).size.height * 0.11).clamp(72.0, 100.0),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemCount: dateList.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, index) {
                                final ts = dateList[index];
                                final isSelected = _selectedDate == ts;
                                final diff = _calculateDifference(ts.toDate());
                                return GestureDetector(
                                  onTap: () => setSheetState(() => _onDateSelected(ts)),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 70,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppThemeData.primary500
                                          : (dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100),
                                      borderRadius: BorderRadius.circular(12),
                                      border: isSelected
                                          ? null
                                          : Border.all(
                                              color: dark
                                                  ? AppThemeData.darkBorderPrimary
                                                  : AppThemeData.grey200),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          diff == 0
                                              ? 'Today'.tr()
                                              : diff == 1
                                                  ? 'Tmrw'.tr()
                                                  : DateFormat('EEE', 'en_US').format(ts.toDate()),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: AppThemeData.medium,
                                            color: isSelected ? Colors.white70 : AppThemeData.grey500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat('d').format(ts.toDate()),
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontFamily: AppThemeData.semiBold,
                                            color: isSelected ? Colors.white : (dark ? Colors.white : Colors.black),
                                          ),
                                        ),
                                        Text(
                                          DateFormat('MMM').format(ts.toDate()),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isSelected ? Colors.white70 : AppThemeData.grey500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        // TIME SLOTS
                        _sheetSection(
                          label: 'Select Time'.tr(),
                          dark: dark,
                          child: available.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppThemeData.danger50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(children: [
                                      Icon(Icons.info_outline, color: AppThemeData.error500, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'No time slots available for today. Please select another date.'.tr(),
                                          style: const TextStyle(
                                            fontSize: 12, color: AppThemeData.error500,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ),
                                )
                              : SizedBox(
                                  height: (MediaQuery.of(context).size.height * 0.075).clamp(48.0, 70.0),
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    scrollDirection: Axis.horizontal,
                                    itemCount: available.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                                    itemBuilder: (_, index) {
                                      final slot = available[index];
                                      final label = DateFormat('hh:mm a').format(slot);
                                      final isSelected = _selectedTimeSlot == label;
                                      return GestureDetector(
                                        onTap: () => setSheetState(() => _selectedTimeSlot = label),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 180),
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppThemeData.primary500
                                                : (dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100),
                                            borderRadius: BorderRadius.circular(10),
                                            border: isSelected
                                                ? null
                                                : Border.all(
                                                    color: dark
                                                        ? AppThemeData.darkBorderPrimary
                                                        : AppThemeData.grey200),
                                          ),
                                          child: Center(
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontFamily: AppThemeData.medium,
                                                color: isSelected
                                                    ? Colors.white
                                                    : (dark ? Colors.white70 : Colors.black87),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        // GUEST COUNT
                        _sheetSection(
                          label: 'Number of Guests'.tr(),
                          dark: dark,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              _guestButton(
                                icon: Icons.remove,
                                onTap: _guestCount > 1
                                    ? () => setSheetState(() => _guestCount--)
                                    : null,
                                dark: dark,
                              ),
                              Expanded(
                                child: Column(children: [
                                  Text(
                                    '$_guestCount',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontFamily: AppThemeData.semiBold,
                                      color: dark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    _guestCount == 1 ? 'Person'.tr() : 'People'.tr(),
                                    style: const TextStyle(
                                        fontSize: 12, color: AppThemeData.grey500),
                                  ),
                                ]),
                              ),
                              _guestButton(
                                icon: Icons.add,
                                onTap: _guestCount < 20
                                    ? () => setSheetState(() => _guestCount++)
                                    : null,
                                dark: dark,
                              ),
                            ]),
                          ),
                        ),
                        // PERSONAL DETAILS
                        _sheetSection(
                          label: 'Personal Details'.tr(),
                          dark: dark,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppThemeData.primary500.withOpacity(0.12),
                                    child: Icon(Icons.person_outline,
                                        color: AppThemeData.primary500, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('$_userFName $_userLName',
                                          style: TextStyle(
                                            fontFamily: AppThemeData.semiBold,
                                            fontSize: 14,
                                            color: dark ? Colors.white : Colors.black,
                                          )),
                                      Text(_userPhone,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                                          )),
                                      Text(_userEmail,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                                          )),
                                    ]),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _showPersonalDetailsDialog(context, () {
                                        setSheetState(() {});
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppThemeData.primary500,
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text('Edit'.tr(),
                                        style: const TextStyle(
                                            fontSize: 12, fontFamily: AppThemeData.semiBold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // SPECIAL OCCASION
                        _sheetSection(
                          label: 'Special Occasion (Optional)'.tr(),
                          dark: dark,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Wrap(
                              spacing: 8,
                              children: occasionList.map((occ) {
                                final selected = _selectedOccasion == occ;
                                return ChoiceChip(
                                  label: Text(occ),
                                  selected: selected,
                                  onSelected: (_) => setSheetState(() {
                                    _selectedOccasion = selected ? '' : occ;
                                  }),
                                  selectedColor: AppThemeData.primary500,
                                  labelStyle: TextStyle(
                                    color: selected ? Colors.white : (dark ? Colors.white70 : Colors.black87),
                                    fontSize: 13,
                                  ),
                                  backgroundColor:
                                      dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                                  side: BorderSide(
                                    color: selected
                                        ? AppThemeData.primary500
                                        : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey300),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        // FIRST VISIT
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                          child: Row(children: [
                            Checkbox(
                              value: _isFirstTime,
                              onChanged: (v) => setSheetState(() => _isFirstTime = v ?? false),
                              activeColor: AppThemeData.primary500,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            Text('Is this your first visit?'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: dark ? Colors.white70 : Colors.black87,
                                )),
                          ]),
                        ),
                        // ADDITIONAL REQUESTS
                        _sheetSection(
                          label: 'Additional Requests (Optional)'.tr(),
                          dark: dark,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TextFormField(
                                controller: _reqController,
                                maxLines: 3,
                                style: TextStyle(
                                  color: dark ? Colors.white : Colors.black,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.all(14),
                                  border: InputBorder.none,
                                  hintText:
                                      'Any special requests, allergies, seating preferences...'.tr(),
                                  hintStyle: const TextStyle(
                                      color: AppThemeData.grey400, fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                // BOOK NOW CTA
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
                  decoration: BoxDecoration(
                    color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                    border: Border(
                      top: BorderSide(
                          color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey200),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: available.isEmpty
                          ? null
                          : () => _submitBooking(ctx, setSheetState),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeData.primary500,
                        disabledBackgroundColor: AppThemeData.grey300,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Confirm Reservation'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontFamily: AppThemeData.semiBold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sheetSection({
    required String label,
    required Widget child,
    required bool dark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontFamily: AppThemeData.semiBold,
              color: dark ? AppThemeData.grey400 : AppThemeData.grey600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        child,
      ]),
    );
  }

  Widget _guestButton({required IconData icon, required VoidCallback? onTap, required bool dark}) {
    return Material(
      color: onTap == null
          ? (dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100)
          : AppThemeData.primary500.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon,
              color: onTap == null ? AppThemeData.grey400 : AppThemeData.primary500, size: 22),
        ),
      ),
    );
  }

  Future<void> _submitBooking(BuildContext sheetCtx, StateSetter setSheetState) async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please select a date'.tr()),
        backgroundColor: AppThemeData.primary500,
      ));
      return;
    }
    if (_selectedTimeSlot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No time slots available for the selected date'.tr()),
        backgroundColor: AppThemeData.error500,
      ));
      return;
    }

    // Build the final datetime
    DateTime dt = _selectedDate!.toDate();
    String hhmm = DateFormat('HH:mm').format(
      DateFormat('hh:mm a').parse(
        (Intl.getCurrentLocale() == 'en_US') ? _selectedTimeSlot : _selectedTimeSlot.toLowerCase(),
      ),
    );
    dt = DateTime(dt.year, dt.month, dt.day,
        int.parse(hhmm.split(':')[0]), int.parse(hhmm.split(':')[1]));
    final bookingTimestamp = Timestamp.fromDate(dt);

    // Block past bookings (safety check)
    if (bookingTimestamp.toDate().isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Selected time is in the past. Please choose another slot.'.tr()),
        backgroundColor: AppThemeData.error500,
      ));
      return;
    }

    await showProgress('Please wait...'.tr(), false);
    try {
      final fireStore = FireStoreUtils();
      final VendorModel vendorModel =
          await fireStore.getVendorByVendorID(widget.vendorModel.id);

      final BookTableModel booking = BookTableModel(
        author: MyAppState.currentUser,
        authorID: MyAppState.currentUser!.userID,
        createdAt: Timestamp.now(),
        date: bookingTimestamp,
        status: ORDER_STATUS_PLACED,
        vendor: vendorModel,
        section_id: sectionConstantModel!.id,
        specialRequest: _reqController.text.trim(),
        vendorID: widget.vendorModel.id,
        guestEmail: _userEmail,
        guestFirstName: _userFName,
        guestLastName: _userLName,
        guestPhone: _userPhone,
        occasion: _selectedOccasion,
        totalGuest: _guestCount,
        firstVisit: _isFirstTime,
      );

      await fireStore.bookTable(booking);

      final Map<String, dynamic> payload = {'type': 'dine_in', 'orderId': booking.id};
      await SendNotification.sendFcmMessage(
          dineInPlaced, widget.vendorModel.fcmToken, payload);
      log('Booking created: ${booking.toJson()}');

      hideProgress();
      Navigator.pop(sheetCtx); // close sheet

      // Success feedback
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Reservation placed! The restaurant will confirm shortly.'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ]),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View'.tr(),
          textColor: Colors.white,
          onPressed: () => push(context, const MyBookingScreen()),
        ),
      ));
    } catch (e) {
      hideProgress();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to place reservation. Please try again.'.tr()),
        backgroundColor: AppThemeData.error500,
      ));
    }
  }

  void _showPersonalDetailsDialog(BuildContext parentCtx, VoidCallback onSaved) {
    final formKey = GlobalKey<FormState>();
    AutovalidateMode validateMode = AutovalidateMode.disabled;
    String tempFName = _userFName;
    String tempLName = _userLName;
    String tempEmail = _userEmail;
    String tempPhone = _userPhone;
    final bool dark = isDarkMode(context);

    showDialog(
      context: parentCtx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Details'.tr(),
              style: TextStyle(
                  fontFamily: AppThemeData.semiBold,
                  color: dark ? Colors.white : Colors.black)),
          content: Form(
            key: formKey,
            autovalidateMode: validateMode,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _detailField(
                label: 'First Name'.tr(),
                initial: tempFName,
                onSaved: (v) => tempFName = v!,
                validator: validateName,
                dark: dark,
              ),
              const SizedBox(height: 10),
              _detailField(
                label: 'Last Name'.tr(),
                initial: tempLName,
                onSaved: (v) => tempLName = v!,
                validator: validateName,
                dark: dark,
              ),
              const SizedBox(height: 10),
              _detailField(
                label: 'Email'.tr(),
                initial: tempEmail,
                onSaved: (v) => tempEmail = v!,
                validator: validateEmail,
                keyboardType: TextInputType.emailAddress,
                dark: dark,
              ),
              const SizedBox(height: 10),
              _detailField(
                label: 'Phone'.tr(),
                initial: tempPhone,
                onSaved: (v) => tempPhone = v!,
                validator: validateMobile,
                keyboardType: TextInputType.phone,
                dark: dark,
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Cancel'.tr(),
                  style: TextStyle(color: dark ? Colors.white54 : Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  formKey.currentState!.save();
                  _userFName = tempFName;
                  _userLName = tempLName;
                  _userEmail = tempEmail;
                  _userPhone = tempPhone;
                  onSaved();
                  Navigator.pop(dialogCtx);
                } else {
                  setDialogState(() {
                    validateMode = AutovalidateMode.onUserInteraction;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeData.primary500,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save'.tr(), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailField({
    required String label,
    required String initial,
    required FormFieldSetter<String> onSaved,
    required FormFieldValidator<String> validator,
    TextInputType keyboardType = TextInputType.text,
    required bool dark,
  }) {
    return TextFormField(
      initialValue: initial,
      onSaved: onSaved,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: keyboardType == TextInputType.text
          ? TextCapitalization.words
          : TextCapitalization.none,
      style: TextStyle(color: dark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: dark ? AppThemeData.grey400 : AppThemeData.grey500, fontSize: 13),
        filled: true,
        fillColor: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppThemeData.error500),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
