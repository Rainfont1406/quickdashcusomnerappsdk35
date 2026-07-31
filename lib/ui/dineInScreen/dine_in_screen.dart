import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/dine_in_restaurant_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

// Auto-sliding card image carousel for dine-in restaurant cards.
// photos[0] = logo, photos[1..n] = card gallery images (set via add_store).
class _DineInCardImage extends StatefulWidget {
  final VendorModel vendor;
  const _DineInCardImage({required this.vendor});
  @override
  State<_DineInCardImage> createState() => _DineInCardImageState();
}

class _DineInCardImageState extends State<_DineInCardImage> {
  late PageController _ctrl;
  Timer? _timer;
  int _page = 0;

  List<String> get _cardPhotos {
    final all = widget.vendor.photos
        .map((e) => VendorModel.coverPhotoUrl(e))
        .where((s) => s.isNotEmpty && s != 'null')
        .toList();
    return all.length > 1 ? all.sublist(1) : <String>[];
  }

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    if (_cardPhotos.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        final next = (_page + 1) % _cardPhotos.length;
        _ctrl.animateToPage(next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imgs = _cardPhotos;
    final fallback = getImageVAlidUrl(widget.vendor.photo);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: imgs.isEmpty
                ? CachedNetworkImage(
                    imageUrl: fallback,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                        height: 160, color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator())),
                    errorWidget: (_, __, ___) => Container(
                        height: 160, color: Colors.grey.shade200,
                        child: const Icon(Icons.restaurant, size: 40, color: Colors.grey)),
                  )
                : PageView.builder(
                    controller: _ctrl,
                    itemCount: imgs.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(imgs[i]),
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.restaurant,
                              size: 40, color: Colors.grey)),
                    ),
                  ),
          ),
        ),
        if (imgs.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(imgs.length, (i) {
                final active = i == _page;
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
    );
  }
}

class DineInScreen extends StatefulWidget {
  final User? user;

  const DineInScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<DineInScreen> createState() => _DineInScreenState();
}

class _DineInScreenState extends State<DineInScreen> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  Stream<List<VendorModel>>? _restaurantStream;
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadRestaurants() {
    _restaurantStream = _fireStoreUtils.getAllDineInRestaurants().asBroadcastStream();
    setState(() => _isLoading = false);
  }

  double _getKm(VendorModel v) {
    if (MyAppState.selectedPosotion.location == null) return 0;
    return Geolocator.distanceBetween(
          v.latitude,
          v.longitude,
          MyAppState.selectedPosotion.location!.latitude,
          MyAppState.selectedPosotion.location!.longitude,
        ) /
        1000;
  }

  double _rating(VendorModel v) =>
      v.reviewsCount > 0 ? v.reviewsSum / v.reviewsCount : 0;

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF5F5F5),
      body: Column(
        children: [
          _buildHeader(dark),
          _buildSearchBar(dark),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<VendorModel>>(
                    stream: _restaurantStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return _buildEmptyState(dark);
                      }
                      final all = snapshot.data!;
                      final filtered = _searchQuery.isEmpty
                          ? all
                          : all.where((v) =>
                              v.title.toLowerCase().contains(_searchQuery) ||
                              v.cuisineNames.join(' ').toLowerCase().contains(_searchQuery) ||
                              v.location.toLowerCase().contains(_searchQuery)).toList();
                      if (filtered.isEmpty) return _buildEmptyState(dark);
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _buildRestaurantCard(dark, filtered[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool dark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppThemeData.primary600, AppThemeData.primary400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Book a Table'.tr(),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Reserve your perfect dining experience'.tr(),
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.88),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool dark) {
    return Container(
      color: dark ? AppThemeData.surfaceDark : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(color: dark ? Colors.white : Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search restaurants, cuisine...'.tr(),
          hintStyle: TextStyle(color: dark ? Colors.white38 : Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: AppThemeData.primary500, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          filled: true,
          fillColor: dark ? const Color(0xff2a2a2a) : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(bool dark, VendorModel vendor) {
    final double km = _getKm(vendor);
    final double rating = _rating(vendor);
    final bool isSlotBased = vendor.bookingType == 'slot_based';
    final String pricingInfo = _pricingLabel(vendor);

    return GestureDetector(
      onTap: () => push(context, DineInRestaurantDetailsScreen(vendorModel: vendor)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xff1e1e1e) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.3 : 0.07),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Restaurant Image carousel (photos[1..n]) ───────────
            _DineInCardImage(vendor: vendor),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + Booking Type Badge ──────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          vendor.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: dark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSlotBased
                              ? const Color(0xFF4CAF50).withOpacity(0.12)
                              : AppThemeData.primary500.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isSlotBased ? 'Slot Booking'.tr() : 'Flexible'.tr(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isSlotBased
                                ? const Color(0xFF388E3C)
                                : AppThemeData.primary600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  // ── Cuisine + Distance ────────────────────────
                  Row(
                    children: [
                      if (vendor.cuisineNames.isNotEmpty) ...[
                        Icon(Icons.restaurant_menu, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            vendor.cuisineNames.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: dark ? Colors.white54 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text(
                        '${km.toStringAsFixed(1)} km'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: dark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // ── Rating + Pricing + CTA ─────────────────────
                  Row(
                    children: [
                      // Rating
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFF16A34A).withValues(alpha: 0.35),
                              width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 13, color: Color(0xFF16A34A)),
                            const SizedBox(width: 3),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Pricing
                      if (pricingInfo.isNotEmpty)
                        Text(
                          pricingInfo,
                          style: TextStyle(
                            fontSize: 12,
                            color: dark ? Colors.white60 : Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                      const Spacer(),

                      // Book Table CTA
                      GestureDetector(
                        onTap: () => push(context, DineInRestaurantDetailsScreen(vendorModel: vendor)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppThemeData.primary500, AppThemeData.primary400],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Book Table'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _pricingLabel(VendorModel vendor) {
    final String amt = amountShow(amount: vendor.bookingCharge.toString(), decimals: 0);
    switch (vendor.bookingPricingModel) {
      case 'per_person':
        return '$amt/person';
      case 'table_charge':
        return '$amt table charge';
      case 'cover_charge':
        return '$amt cover/person';
      default:
        return 'Free Booking'.tr();
    }
  }

  Widget _buildEmptyState(bool dark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_restaurant_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No restaurants available for booking'.tr(),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white70 : Colors.black54)),
          const SizedBox(height: 8),
          Text('Check back later for table reservations'.tr(),
              style: TextStyle(
                  fontSize: 13, color: dark ? Colors.white38 : Colors.grey.shade500)),
        ],
      ),
    );
  }
}
