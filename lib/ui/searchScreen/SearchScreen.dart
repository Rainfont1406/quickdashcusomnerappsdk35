import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _query = '';
  List<String> _recentSearches = [];
  List<VendorModel> _results = [];
  List<VendorModel> _recommended = [];
  List<String> _trending = [];

  // Lowercase title cache for fast prefix/substring search
  late final List<String> _titleCache;
  late final List<String> _categoryCache;
  late final List<String> _locationCache;

  static const String _recentKey = 'search_recent_queries';
  static const int _maxRecent = 8;

  @override
  void initState() {
    super.initState();
    _titleCache =
        allstoreList.map((v) => v.title.toLowerCase()).toList();
    _categoryCache =
        allstoreList.map((v) => v.categoryTitle.toLowerCase()).toList();
    _locationCache =
        allstoreList.map((v) => v.location.toLowerCase()).toList();
    _buildRecommended();
    _buildTrending();
    _loadRecent();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Data preparation ──────────────────────────────────────────────────────

  void _buildRecommended() {
    final open = allstoreList
        .where((v) => v.isAcceptingOrders)
        .toList();
    open.sort((a, b) => _score(b).compareTo(_score(a)));
    _recommended = open.take(10).toList();
  }

  void _buildTrending() {
    final seen = <String>{};
    _trending = [];
    for (final v in allstoreList) {
      final t = v.categoryTitle.trim();
      if (t.isNotEmpty && seen.add(t.toLowerCase())) {
        _trending.add(t);
        if (_trending.length >= 10) break;
      }
    }
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentKey) ?? [];
    if (mounted) setState(() => _recentSearches = raw);
  }

  Future<void> _addRecent(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = [trimmed, ..._recentSearches.where((s) => s != trimmed)]
        .take(_maxRecent)
        .toList();
    await prefs.setStringList(_recentKey, updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _removeRecent(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _recentSearches.where((s) => s != q).toList();
    await prefs.setStringList(_recentKey, updated);
    if (mounted) setState(() => _recentSearches = updated);
  }

  Future<void> _clearAllRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentKey);
    if (mounted) setState(() => _recentSearches = []);
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onChanged(String value) {
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _runSearch(value);
  }

  void _runSearch(String text) {
    final lower = text.toLowerCase().trim();
    final matched = <VendorModel>[];
    for (int i = 0; i < allstoreList.length; i++) {
      final hitTitle = _titleCache.length > i && _titleCache[i].contains(lower);
      final hitCategory =
          _categoryCache.length > i && _categoryCache[i].contains(lower);
      final hitLocation =
          _locationCache.length > i && _locationCache[i].contains(lower);
      if (hitTitle || hitCategory || hitLocation) {
        matched.add(allstoreList[i]);
      }
    }
    // Open first, then ranked by score; closed appear at the bottom
    matched.sort((a, b) {
      final aOpen = a.isAcceptingOrders;
      final bOpen = b.isAcceptingOrders;
      if (aOpen != bOpen) return aOpen ? -1 : 1;
      return _score(b).compareTo(_score(a));
    });
    setState(() => _results = matched);
  }

  void _applyQuery(String text) {
    _queryCtrl.text = text;
    setState(() => _query = text);
    _addRecent(text);
    _runSearch(text);
    _focusNode.unfocus();
  }

  void _onSubmit(String text) {
    if (text.trim().isEmpty) return;
    _addRecent(text.trim());
    _runSearch(text.trim());
    _focusNode.unfocus();
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  double _score(VendorModel v) {
    final rating = v.reviewsCount > 0 ? v.reviewsSum / v.reviewsCount : 0.0;
    final popularity = v.reviewsCount.toDouble().clamp(0, 500) / 500;
    final nearness = 1.0 / (_distanceKm(v) + 0.1);
    return rating * 40 + popularity * 30 + nearness.clamp(0.0, 30.0);
  }

  double _distanceKm(VendorModel v) {
    final loc = MyAppState.selectedPosotion.location;
    if (loc == null) return 9999.0;
    return Geolocator.distanceBetween(
          loc.latitude, loc.longitude, v.latitude, v.longitude) /
        1000;
  }

  String _distanceLabel(VendorModel v) {
    final km = _distanceKm(v);
    if (km >= 9000) return '';
    if (km < 1) return '${(km * 1000).toStringAsFixed(0)} m';
    return '${km.toStringAsFixed(1)} km';
  }

  // ── Next-opening label ────────────────────────────────────────────────────

  String _nextOpeningLabel(VendorModel v) {
    if (v.workingHours.isEmpty) return 'Temporarily unavailable';

    final now = DateTime.now();
    final todayDate = DateFormat('dd-MM-yyyy').format(now);
    final todayName = DateFormat('EEEE', 'en_US').format(now);

    // Remaining slots today
    for (final wh in v.workingHours) {
      if (wh.day == todayName && wh.timeslot != null) {
        for (final slot in wh.timeslot!) {
          if (slot.from == null) continue;
          try {
            final start = DateFormat('dd-MM-yyyy HH:mm')
                .parse('$todayDate ${slot.from}');
            if (start.isAfter(now)) {
              return 'Opens today at ${_fmtTime(slot.from!)}';
            }
          } catch (_) {}
        }
      }
    }

    // Next 7 days
    for (int d = 1; d <= 7; d++) {
      final next = now.add(Duration(days: d));
      final nextName = DateFormat('EEEE', 'en_US').format(next);
      for (final wh in v.workingHours) {
        if (wh.day == nextName &&
            wh.timeslot != null &&
            wh.timeslot!.isNotEmpty) {
          String? earliest;
          for (final slot in wh.timeslot!) {
            if (slot.from == null) continue;
            if (earliest == null) {
              earliest = slot.from;
            } else {
              try {
                final a = DateFormat('HH:mm').parse(earliest);
                final b = DateFormat('HH:mm').parse(slot.from!);
                if (b.isBefore(a)) earliest = slot.from;
              } catch (_) {}
            }
          }
          if (earliest != null) {
            if (d == 1) return 'Opens tomorrow at ${_fmtTime(earliest)}';
            return 'Opens ${DateFormat('EEEE').format(next)} at ${_fmtTime(earliest)}';
          }
        }
      }
    }

    return 'Temporarily unavailable';
  }

  String _fmtTime(String hhmm) {
    try {
      return DateFormat('h:mm a').format(DateFormat('HH:mm').parse(hhmm));
    } catch (_) {
      return hhmm;
    }
  }

  String _rating(VendorModel v) => calculateReview(
        reviewCount: v.reviewsCount.toString(),
        reviewSum: v.reviewsSum.toString(),
      );

  // photos[0] is the square restaurant logo; photo is the wide banner.
  String _logoUrl(VendorModel v) {
    if (v.photos.isNotEmpty) {
      final first = v.photos.first.toString().trim();
      if (first.isNotEmpty && first != 'null') return first;
    }
    return v.photo;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDeliveryActiveNotifier,
      builder: (context, deliveryActive, _) {
        if (currentOrderTypeGlobal == 'Delivery'.tr() && !deliveryActive) {
          return ComingSoonScreen(message: deliveryOffMessageNotifier.value);
        }
        return _buildSearchScreen(context);
      },
    );
  }

  Widget _buildSearchScreen(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : AppThemeData.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(dark),
            Divider(
              height: 1,
              thickness: 1,
              color: dark ? AppThemeData.grey800 : AppThemeData.grey200,
            ),
            Expanded(
              child: _query.trim().isEmpty
                  ? _buildEmptyState(dark)
                  : _buildResults(dark),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _circleButton(
            icon: Icons.arrow_back_rounded,
            dark: dark,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: dark ? AppThemeData.grey800 : AppThemeData.grey100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search_rounded,
                      size: 20,
                      color: dark
                          ? AppThemeData.grey400
                          : AppThemeData.grey500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: AppThemeData.regular,
                        color: dark
                            ? AppThemeData.grey50
                            : AppThemeData.grey900,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Restaurants, cuisines, dishes...'.tr(),
                        hintStyle: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.regular,
                          color: dark
                              ? AppThemeData.grey500
                              : AppThemeData.grey400,
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: _onChanged,
                      onSubmitted: _onSubmit,
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _queryCtrl.clear();
                        _onChanged('');
                        _focusNode.requestFocus();
                      },
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.close_rounded,
                            size: 18,
                            color: dark
                                ? AppThemeData.grey400
                                : AppThemeData.grey500),
                      ),
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool dark) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Recent searches ─────────────────────────────────────────────
          if (_recentSearches.isNotEmpty) ...[
            _sectionHeader(
              dark,
              'Recent',
              action: GestureDetector(
                onTap: _clearAllRecent,
                child: Text(
                  'Clear all',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppThemeData.medium,
                    color: AppThemeData.primary500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children:
                    _recentSearches.map((q) => _recentTile(q, dark)).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Trending chips ──────────────────────────────────────────────
          if (_trending.isNotEmpty) ...[
            _sectionHeader(dark, 'Trending'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _trending.map((t) => _trendingChip(t, dark)).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Recommended open restaurants ────────────────────────────────
          if (_recommended.isNotEmpty) ...[
            _sectionHeader(dark, 'Recommended for You'),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 0),
              itemCount: _recommended.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _vendorCard(_recommended[i], dark),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildResults(bool dark) {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: dark ? AppThemeData.grey700 : AppThemeData.grey300,
            ),
            const SizedBox(height: 16),
            Text(
              'No results for "$_query"',
              style: TextStyle(
                fontSize: 16,
                fontFamily: AppThemeData.medium,
                color: dark ? AppThemeData.grey400 : AppThemeData.grey600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different keyword or cuisine',
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.regular,
                color: dark ? AppThemeData.grey600 : AppThemeData.grey400,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _results.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_results.length} result${_results.length == 1 ? '' : 's'}'
              ' for "$_query"',
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.medium,
                color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
              ),
            ),
          );
        }
        final v = _results[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _vendorCard(v, dark),
        );
      },
    );
  }

  // ── Shared components ─────────────────────────────────────────────────────

  Widget _sectionHeader(bool dark, String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.tr(),
              style: TextStyle(
                fontSize: 17,
                fontFamily: AppThemeData.bold,
                color: dark ? AppThemeData.grey50 : AppThemeData.grey900,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _recentTile(String q, bool dark) {
    return InkWell(
      onTap: () => _applyQuery(q),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(Icons.history_rounded,
                size: 18,
                color:
                    dark ? AppThemeData.grey500 : AppThemeData.grey400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                q,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppThemeData.regular,
                  color: dark
                      ? AppThemeData.grey200
                      : AppThemeData.grey700,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _removeRecent(q),
              child: Icon(Icons.close_rounded,
                  size: 16,
                  color: dark
                      ? AppThemeData.grey600
                      : AppThemeData.grey400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendingChip(String label, bool dark) {
    return GestureDetector(
      onTap: () => _applyQuery(label),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.grey800 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: dark ? AppThemeData.grey700 : AppThemeData.grey200,
          ),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up_rounded,
                size: 14, color: AppThemeData.primary500),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppThemeData.medium,
                color: dark
                    ? AppThemeData.grey200
                    : AppThemeData.grey700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vendorCard(VendorModel v, bool dark) {
    final isOpen = v.isAcceptingOrders;
    final rating = _rating(v);
    final dist = _distanceLabel(v);
    final statusLabel = isOpen ? 'Open' : _nextOpeningLabel(v);

    return GestureDetector(
      onTap: () {
        final q = _query.trim().isNotEmpty ? _query.trim() : v.title;
        _addRecent(q);
        push(context, NewVendorProductsScreen(vendorModel: v));
      },
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppThemeData.grey900 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo ──────────────────────────────────────────────────────
            // photos[0] is the square logo — use BoxFit.contain so it is
            // never cropped, with a neutral background behind any whitespace.
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  isOpen
                      ? Colors.transparent
                      : Colors.grey.withValues(alpha: 0.4),
                  BlendMode.saturation,
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  color: dark ? AppThemeData.grey800 : AppThemeData.grey100,
                  child: CachedNetworkImage(
                    imageUrl: _logoUrl(v),
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Center(
                      child: Icon(Icons.store_rounded,
                          size: 40, color: AppThemeData.grey400),
                    ),
                  ),
                ),
              ),
            ),
            // ── Info ──────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontFamily: AppThemeData.bold,
                        color: dark
                            ? AppThemeData.grey50
                            : const Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Cuisine tag
                    if (v.categoryTitle.isNotEmpty)
                      Text(
                        v.categoryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.regular,
                          color: dark
                              ? AppThemeData.grey400
                              : AppThemeData.grey500,
                        ),
                      ),
                    const SizedBox(height: 6),
                    // Rating · reviews · distance
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBC05), size: 13),
                        const SizedBox(width: 3),
                        Text(
                          rating,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppThemeData.semiBold,
                            color: dark
                                ? AppThemeData.grey300
                                : const Color(0xFF333333),
                          ),
                        ),
                        Text(
                          ' · ${v.reviewsCount} reviews',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppThemeData.regular,
                            color: dark
                                ? AppThemeData.grey500
                                : AppThemeData.grey400,
                          ),
                        ),
                        if (dist.isNotEmpty) ...[
                          Text(
                            ' · $dist',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: AppThemeData.regular,
                              color: dark
                                  ? AppThemeData.grey500
                                  : AppThemeData.grey400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    // Status badge
                    _statusBadge(isOpen, statusLabel, dark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(bool isOpen, String label, bool dark) {
    final Color bg;
    final Color fg;
    final Widget icon;

    if (isOpen) {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF16A34A);
      icon = Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFF16A34A),
          shape: BoxShape.circle,
        ),
      );
    } else if (label == 'Temporarily unavailable') {
      bg = dark ? AppThemeData.grey800 : AppThemeData.grey100;
      fg = dark ? AppThemeData.grey400 : AppThemeData.grey500;
      icon = Icon(Icons.pause_circle_outline_rounded, size: 12, color: fg);
    } else {
      // "Opens today/tomorrow/X at HH:MM"
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFD97706);
      icon = Icon(Icons.access_time_rounded, size: 12, color: fg);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontFamily: AppThemeData.semiBold,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool dark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? AppThemeData.grey700 : AppThemeData.grey100,
        ),
        child: Icon(icon,
            size: 20,
            color: dark ? AppThemeData.grey200 : AppThemeData.grey700),
      ),
    );
  }
}
