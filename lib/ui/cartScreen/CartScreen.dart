import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
// Prefixed second import of the same file, solely to reach the GLOBAL
// `taxList` (constants.dart) unambiguously — this screen's own `taxList`
// field below shadows the unprefixed one, so `globalTaxList.taxList` is the
// only way to actually read/write ContainerScreen's already-fetched copy.
import 'package:emartconsumer/constants.dart' as globalTaxList;
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/utils/network_image_widget.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_event_types.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';
import 'package:emartconsumer/widget/coming_soon_view.dart';
import 'package:emartconsumer/widget/delivery_type_selector.dart';
import 'package:emartconsumer/widget/place_picker_osm.dart';
import 'package:uuid/uuid.dart';

import 'package:emartconsumer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:emartconsumer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:emartconsumer/widget/product_options_dialog.dart';
import 'package:emartconsumer/widget/savings_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/typography.dart';
import '../../model/DeliveryChargeModel.dart';
import '../payment/PaymentScreen.dart';
import 'package:emartconsumer/model/ItemAttributes.dart';
import 'package:emartconsumer/ui/cartScreen/cart_skeleton.dart';
import 'package:emartconsumer/model/OrderModel.dart';

class CartScreen extends StatefulWidget {
  final bool fromStoreSelection;
  final OrderModel? reOrderModel;

  // Vendor-initiated Bill Pay accept flow: the customer's cart is replaced
  // wholesale with the vendor's exact bill (no re-pricing, no dialogs) and
  // locked from further edits. Paying then creates a brand-new, completely
  // normal order — see billPayRequestId on OrderModel for how it links back
  // to this original request.
  final OrderModel? billPayRequestModel;

  const CartScreen({Key? key, this.fromStoreSelection = false, this.reOrderModel, this.billPayRequestModel})
      : super(key: key);

  @override
  _CartScreenState createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Future<List<CartProduct>> cartFuture;
  late List<CartProduct> cartProducts = [];
  TextEditingController noteController = TextEditingController(text: '');

  double subTotal = 0.0;
  late CartDatabase cartDatabase;
  double grandtotal = 0.0;
  var per = 0.0;
  late Future<List<OfferModel>> coupon;
  TextEditingController txt = TextEditingController(text: '');
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  var percentage, type = 0.0;
  var amount = 0.00;
  late String couponId = '';
  // Minimum order amount required by the currently-applied coupon (0 = no
  // minimum). Set whenever a coupon is applied; used every build to detect
  // the subtotal dropping below it (e.g. an item was removed) so the coupon
  // gets auto-removed instead of silently staying "applied" with a total the
  // customer would never actually be charged (server already rejects it).
  double _appliedCouponMinAmount = 0.0;
  String vendorID = "";
  late List<AddAddonsDemo> lstExtras = [];
  late List<String> commaSepratedAddOns = [];
  String? commaSepratedAddOnsString = "";
  bool? deliverExec = false;
  var deliveryCharges = "0.0";
  VendorModel? vendorModel;
  String? selctedOrderTypeValue = "Delivery".tr();
  bool isDeliverFound = false;
  var tipValue = 0.0;

  // Dineaway section variables
  String? selectedDineawayType; // "Takeaway" or "Dining"
  bool isDineawaySelected = false;
  // Phase 1 real-time seat availability - only asked when the vendor has
  // opted in (vendorModel?.seatCapacity != null). Feeds OrderModel below,
  // which lets streamCurrentSeatAvailability sum actual party sizes instead
  // of just counting active orders - see
  // TABLE_BOOKING_CAPACITY_AND_DEPOSIT_PLAN.html.
  int _diningGuestCount = 1;
  bool _allowDelivery = true;
  bool _allowDineaway = true;
  bool _allowDineIn = true;
  bool _allowDineAwayTakeaway = true;
  bool isTipSelected = false,
      isTipSelected1 = false,
      isTipSelected2 = false,
      isTipSelected3 = false;
  final TextEditingController _textFieldController = TextEditingController();

  double specialDiscount = 0.0;
  double specialDiscountAmount = 0.0;
  String specialType = "";

  // Resolved-after-conflict-rules amounts that `grandtotal` is actually
  // computed from (see the combined-discount-ceiling block in build()) — the
  // Place Order button must read these, not the raw coupon/special-discount
  // fields above, so the order it creates always matches what the customer
  // was actually charged. Fields (not build()-local) because the button's
  // onPressed closure is constructed textually earlier in build() than the
  // block that resolves them; being fields, the closure reads them fresh at
  // tap-time from whichever build() last ran, same as `grandtotal` itself.
  double effectiveDiscountVal = 0.0;
  double effectiveSpecialDiscountAmount = 0.0;

  Timestamp? scheduleTime;
  bool specialDiscountEnable = false;
  bool _isBillExpanded = false;
  AddressModel addressModel = AddressModel();

  // Delivery house/flat + landmark — inline fields in the address card,
  // mutated directly into addressModel as the user types.
  final TextEditingController _houseCtrl = TextEditingController();
  final TextEditingController _landmarkCtrl = TextEditingController();
  bool _houseFieldError = false;

  bool get _deliveryAddressComplete =>
      (addressModel.locality?.isNotEmpty ?? false) &&
      (addressModel.address?.isNotEmpty ?? false);

  List<TaxModel>? taxList = []; // Initialize as empty list

  // Stable stream reference — must not change between rebuilds to prevent scroll resets
  Stream<List<CartProduct>>? _cartStream;

  // Performance optimization: Cache product models
  final Map<String, ProductModel> _productCache = {};

  // Guards the low-stock live re-check in the "+" stepper (2026-08-05):
  // that button's onTap is async only for the <10-stock path, which a
  // synchronous handler never needed to worry about - without this, two
  // rapid taps before the first fetch resolves could both pass the same
  // stale maxQty check and double-increment past the real limit. Keyed by
  // product id so a check in flight for one cart line never blocks taps on
  // a different line.
  final Set<String> _stockCheckInFlight = {};

  // Cart skeleton: shows until first validation completes (or empty-cart confirmed)
  bool _isCartInitialized = false;
  // [CART-PERF] race-condition audit only: records whether the initState
  // getTaxData() call has already resolved by the time getDeliveyData()
  // reaches its own getTaxData() call. Read-only instrumentation, no
  // behavior change.
  bool _firstTaxDataCallDone = false;

  // Re-order flow: true while background validation + cart population is in progress
  bool _reOrderPending = false;
  bool _reOrderStarted = false;

  // Bill Pay accept flow: true while the vendor's exact bill is being
  // dropped into the (cleared) cart. No re-pricing, no validation — see
  // _populateFromBillPay().
  bool _billPayPending = false;
  bool _billPayStarted = false;

  bool get _isBillPayMode => widget.billPayRequestModel != null;

  // Cart validation state
  bool _isValidating = false;
  bool _canCheckout = true;
  Map<String, String> _itemIssues = {};
  Map<String, bool> _itemBlocking = {};
  String? _cartGlobalWarning;

  OverlayEntry? _notificationOverlay;

  // Notifications queued while the skeleton is active; flushed after transition.
  final List<Map<String, dynamic>> _pendingNotifications = [];

  // Variant items whose price changed — dialog shown after skeleton clears.
  final List<MapEntry<CartProduct, ProductModel>> _pendingVariantDialogs = [];

  // True while _flushVariantDialogs is showing dialogs — suppresses hash-change
  // re-validation so the banner doesn't flash when the user re-adds an item.
  bool _dialogsFlushInProgress = false;

  // Offset between device clock and Firestore server clock.
  // Fetched once on init; used to prevent device-clock manipulation of
  // time-limited special discounts.
  Duration _serverTimeOffset = Duration.zero;

  DateTime get _serverAdjustedNow => DateTime.now().add(_serverTimeOffset);

  Future<void> _fetchServerTimeOffset() async {
    final sw = Stopwatch()..start();
    // source=Firestore('_serverPing/ping' doc) — NOT a plain read: this is a
    // WRITE (.set with FieldValue.serverTimestamp()) immediately followed by
    // a READ of the same doc, two sequential round trips, not one. Also has
    // an existing 5-minute in-memory cache (see FireStoreUtils._serverTimeTtl)
    // — this whole body only actually reaches Firestore once per 5 minutes
    // per app session; a cache-hit here returns near-instantly and this log
    // line's own elapsed time reflects that when it happens.
    debugPrint('[CART-PERF][_fetchServerTimeOffset] request START at ${DateTime.now().toIso8601String()}');
    final deviceBefore = DateTime.now();
    final serverTime = await FireStoreUtils.getServerTime();
    debugPrint('[CART-PERF][_fetchServerTimeOffset] Firestore Future resolved (write+read, or cache-hit) — ${sw.elapsedMilliseconds}ms');
    final elapsed = DateTime.now().difference(deviceBefore);
    // Compensate for round-trip latency using the midpoint of the request window.
    final deviceMidpoint = deviceBefore.add(elapsed ~/ 2);
    if (mounted) {
      setState(() {
        _serverTimeOffset = serverTime.difference(deviceMidpoint);
      });
      debugPrint('[CART-PERF][_fetchServerTimeOffset] setState called — ${sw.elapsedMilliseconds}ms');
      WidgetsBinding.instance.addPostFrameCallback((_) => debugPrint(
          '[CART-PERF][_fetchServerTimeOffset] next frame rendered — ${sw.elapsedMilliseconds}ms'));
    }
  }

  @override
  void initState() {
    super.initState();
    final initSw = Stopwatch()..start();
    debugPrint('[CART-PERF] CartScreen.initState START at ${DateTime.now().toIso8601String()}');
    addressModel = MyAppState.selectedPosotion;
    _houseCtrl.text = addressModel.address ?? '';
    _landmarkCtrl.text = addressModel.landmark ?? '';
    _reOrderPending = widget.reOrderModel != null;
    _billPayPending = _isBillPayMode;

    coupon = _fireStoreUtils.getAllCoupons().then((value) {
      debugPrint('[CART-PERF] getAllCoupons END — ${initSw.elapsedMilliseconds}ms since initState');
      return value;
    });
    // Deliberately NOT preloading payment gateway settings here. Many users
    // open the cart and never proceed to checkout — PaymentScreen is the
    // single point that calls FireStoreUtils.ensurePaymentGatewaySettingsLoaded()
    // (see its doc comment), awaited, right when it actually needs the data.
    debugPrint('[CART-PERF] getFoodType START — ${initSw.elapsedMilliseconds}ms since initState');
    getFoodType().then((_) => debugPrint(
        '[CART-PERF] getFoodType END — ${initSw.elapsedMilliseconds}ms since initState'));
    debugPrint('[CART-PERF] getTaxData START — ${initSw.elapsedMilliseconds}ms since initState at ${DateTime.now().toIso8601String()}');
    getTaxData().then((_) {
      _firstTaxDataCallDone = true;
      debugPrint(
          '[CART-PERF] getTaxData END (1st/initState call) — ${initSw.elapsedMilliseconds}ms since initState, wall-clock ${DateTime.now().toIso8601String()}');
    });
    debugPrint('[CART-PERF] _fetchServerTimeOffset START — ${initSw.elapsedMilliseconds}ms since initState');
    _fetchServerTimeOffset().then((_) => debugPrint(
        '[CART-PERF] _fetchServerTimeOffset END — ${initSw.elapsedMilliseconds}ms since initState'));

    // Initialize Dineaway state
    if (_isBillPayMode) {
      // Bill Pay is always Dineaway; the vendor already decided this is a
      // bill settlement, not a fresh Takeaway/Dining choice — so there is
      // no sub-type picker to show, unlike a normal Dineaway order.
      selctedOrderTypeValue = 'Dineaway';
      selectedDineawayType = 'Bill Pay';
      isDineawaySelected = true;
    } else {
      selectedDineawayType = null;
      isDineawaySelected = false;
    }
  }

  @override
  void dispose() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
    _houseCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  void _showTopNotification({
    required String message,
    required Color color,
    required IconData icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    _notificationOverlay?.remove();
    _notificationOverlay = null;

    final entry = OverlayEntry(
      builder: (_) {
        final dark = isDarkMode(context);
        return Positioned(
          // Place below the AppBar so it never overlaps the "Your Cart" title
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.40 : 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Colored left accent stripe
                      Container(width: 4, color: color),
                      const SizedBox(width: 12),
                      // Icon badge
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: color, size: 16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Message text
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Text(
                            message,
                            style: AppTypography.labelSmall.copyWith(
                              color: dark
                                  ? Colors.white
                                  : AppThemeData.neutral900,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _notificationOverlay = entry;
    Overlay.of(context).insert(entry);

    Future.delayed(duration, () {
      _notificationOverlay?.remove();
      _notificationOverlay = null;
    });
  }

  // Queue a notification to show after the skeleton → real-UI transition.
  // If the cart is already initialised, shows immediately instead.
  void _queueOrShowNotification({
    required String message,
    required Color color,
    required IconData icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!_isCartInitialized) {
      _pendingNotifications.add(
          {'message': message, 'color': color, 'icon': icon, 'duration': duration});
    } else {
      _showTopNotification(message: message, color: color, icon: icon, duration: duration);
    }
  }

  void _flushPendingNotifications() {
    if (!mounted || _pendingNotifications.isEmpty) return;
    final toShow = List<Map<String, dynamic>>.from(_pendingNotifications);
    _pendingNotifications.clear();
    for (final n in toShow) {
      _showTopNotification(
        message: n['message'] as String,
        color: n['color'] as Color,
        icon: n['icon'] as IconData,
        duration: n['duration'] as Duration,
      );
    }
  }

  // Fetches tax data for the active section (not country-scoped - single-country deployment).
  // TEMPORARY [CART-PERF] fine-grained staging. Firestore's Dart SDK does
  // not expose true network-level TTFB (first-byte) — .get()/.set() resolve
  // as a single opaque Future covering channel + server + native-SDK
  // deserialize, with no hook in between. These stages are the finest grain
  // actually observable from Dart: request-issued -> Firestore Future
  // resolves (network+server, opaque) -> local model-mapping -> setState
  // called -> next frame actually rendered (via addPostFrameCallback).
  // Data source for both functions below: Firestore only — no Laravel API,
  // Cloud Function, or SharedPreferences/local cache involved in the
  // network path itself (getFoodType's one SharedPreferences read is a
  // separate, unrelated local value, not a cache of the Firestore call).
  Future<void> getTaxData() async {
    // This screen's own `taxList` field (above) shadows the GLOBAL `taxList`
    // in constants.dart that ContainerScreen.getTaxList() already populates
    // once per session, before CartScreen ever mounts — unqualified
    // `taxList` inside this class always meant the local field, so the
    // previous version of this guard never actually reused Container's
    // fetch, only CartScreen's own repeat calls (getDeliveyData,
    // _populateFromBillPay). Checking `globalTaxList.taxList` explicitly
    // (via the prefixed import above) is what actually closes that gap.
    // getTaxList()'s query is section-wide, not order-type-scoped (confirmed
    // against TaxModel.isTakeaway — the flag exists for consumers to filter
    // by afterward, not something the fetch itself branches on), so the
    // same global list is valid to reuse regardless of Delivery/Takeaway/
    // Dineaway mode. Falls through to a real fetch if the global is still
    // empty (nothing has populated it yet, or a section genuinely has zero
    // enabled tax rates) or on a caught error below, so correctness never
    // depends on call order — and a fresh fetch here also writes back to
    // the global, so whichever screen fetches first benefits the other.
    if (globalTaxList.taxList != null && globalTaxList.taxList!.isNotEmpty) {
      taxList = globalTaxList.taxList;
      debugPrint('[CART-PERF][getTaxData] skipped — reused ContainerScreen.getTaxList() (${taxList!.length} rates)');
      return;
    }
    final sw = Stopwatch()..start();
    debugPrint('[CART-PERF][getTaxData] source=Firestore(tax collection, '
        'compound where sectionId+enable) request START at ${DateTime.now().toIso8601String()}');
    try {
      final taxes = await FireStoreUtils().getTaxList(sectionConstantModel?.id);
      debugPrint('[CART-PERF][getTaxData] Firestore Future resolved — ${sw.elapsedMilliseconds}ms');
      taxList = taxes ?? [];
      globalTaxList.taxList = taxList;
      debugPrint('[CART-PERF][getTaxData] model mapping done — ${sw.elapsedMilliseconds}ms');
      setState(() {});
      debugPrint('[CART-PERF][getTaxData] setState called — ${sw.elapsedMilliseconds}ms');
      WidgetsBinding.instance.addPostFrameCallback((_) => debugPrint(
          '[CART-PERF][getTaxData] next frame rendered — ${sw.elapsedMilliseconds}ms'));
    } catch (e) {
      print('Error fetching tax data: $e');
      taxList = [];
    }
  }

  getFoodType() async {
    final sw = Stopwatch()..start();
    debugPrint('[CART-PERF][getFoodType] source=Firestore(Setting/specialDiscountOffer doc) '
        'request START at ${DateTime.now().toIso8601String()}');
    SharedPreferences sp = await SharedPreferences.getInstance();
    // Re-orders and Bill Pay both restore/force their own service type — skip here.
    if (widget.reOrderModel == null && !_isBillPayMode) {
      setState(() {
        selctedOrderTypeValue =
            sp.getString("foodType") == "" || sp.getString("foodType") == null
                ? "Delivery"
                : sp.getString("foodType");
      });
    }
    await FireStoreUtils.firestore
        .collection(Setting)
        .doc('specialDiscountOffer')
        .get()
        .then((value) {
      debugPrint('[CART-PERF][getFoodType] Firestore Future resolved — ${sw.elapsedMilliseconds}ms');
      specialDiscountEnable = value.data()?['isEnable'] ?? false;
      debugPrint('[CART-PERF][getFoodType] model mapping done — ${sw.elapsedMilliseconds}ms');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => debugPrint(
        '[CART-PERF][getFoodType] next frame rendered — ${sw.elapsedMilliseconds}ms'));
  }

  // ── Service type switcher (used by inline DeliveryTypeSelector in cart) ───────
  Future<void> _onOrderTypeChanged(String newValue) async {
    if (selctedOrderTypeValue == newValue) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('foodType', newValue);
    setState(() {
      selctedOrderTypeValue = newValue;
      selectedDineawayType = null;
      isDineawaySelected = false;
      deliveryCharges = '0.0';
    });
    if (newValue == 'Delivery' && vendorModel != null && addressModel.location != null) {
      final kmStr = await getRoadDistanceKm(
        addressModel.location!,
        UserLocation(
          latitude: vendorModel!.latitude,
          longitude: vendorModel!.longitude,
        ),
      );
      getDeliveryCharges(num.parse(kmStr));
    }
    _validateCart();
  }

  // ── Themed dialog for service-type mismatch / blocked options ────────────────
  void _showServiceMismatchDialog(String title, String message) {
    AppDialog.showWarning(context, title: title, message: message);
  }

  String _lastPermCartHash = '';

  Future<void> _computeServicePermissions(List<CartProduct> products) async {
    if (products.isEmpty) {
      if (mounted) setState(() {
        _allowDelivery = true;
        _allowDineaway = true;
        _allowDineIn = true;
        _allowDineAwayTakeaway = true;
      });
      return;
    }
    final sp = await SharedPreferences.getInstance();
    bool allowDelivery = true;
    bool allowDineaway = true;
    bool allowDineIn = true;
    bool allowTakeaway = true;
    bool anyConstrained = false;

    for (final cp in products) {
      final productId = cp.id.split('~').first;
      // Try new schema first, fall back to old dineaway-only schema
      final raw = sp.getString('service_perm_$productId') ?? sp.getString('dineaway_perm_$productId');
      if (raw == null) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final hasFullSchema = map.containsKey('delivery') || map.containsKey('dineaway');

        if (hasFullSchema) {
          final delivery = map['delivery'] as bool? ?? true;
          final dineaway = map['dineaway'] as bool? ?? false;
          // Both false = legacy unconfigured product — skip to avoid false restrictions
          if (!delivery && !dineaway) continue;
          anyConstrained = true;
          if (!delivery) allowDelivery = false;
          if (!dineaway) allowDineaway = false;
          // Only constrain DineAway sub-types if the product supports DineAway
          if (dineaway) {
            final dineIn = map['dineIn'] as bool? ?? false;
            final takeaway = map['takeaway'] as bool? ?? false;
            // Only restrict if at least one sub-type is explicitly configured
            if (dineIn || takeaway) {
              if (!dineIn) allowDineIn = false;
              if (!takeaway) allowTakeaway = false;
            }
          }
        } else {
          // Old dineaway_perm schema: only dineIn/takeaway sub-option data
          final dineIn = map['dineIn'] as bool? ?? false;
          final takeaway = map['takeaway'] as bool? ?? false;
          if (!dineIn && !takeaway) continue;
          anyConstrained = true;
          if (!dineIn) allowDineIn = false;
          if (!takeaway) allowTakeaway = false;
        }
      } catch (_) {}
    }

    if (!anyConstrained) return;
    if (!mounted) return;
    setState(() {
      _allowDelivery = allowDelivery;
      _allowDineaway = allowDineaway;
      _allowDineIn = allowDineIn;
      _allowDineAwayTakeaway = allowTakeaway;
      if (selectedDineawayType == 'Dining' && !allowDineIn) { selectedDineawayType = null; isDineawaySelected = false; }
      if (selectedDineawayType == 'Takeaway' && !allowTakeaway) { selectedDineawayType = null; isDineawaySelected = false; }
    });
  }

  // ── Helper: resolve current variant price from fresh Firestore product ───────
  // Returns the commission-adjusted price string, or null if the variant cannot
  // be matched (conservative — we only act when we can confirm a real change).
  String? _computeFreshVariantPrice(CartProduct cp, ProductModel fresh) {
    VariantInfo? vi;
    try {
      final raw = cp.variant_info;
      if (raw is VariantInfo) {
        vi = raw;
      } else if (raw is Map<String, dynamic>) {
        vi = VariantInfo.fromJson(raw);
      } else if (raw is String && raw.isNotEmpty && raw != 'null') {
        vi = VariantInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      return null;
    }
    if (vi == null) return null;

    // Derive SKU; fall back to joining option values when sku is absent.
    String sku = vi.variant_sku ?? '';
    if (sku.isEmpty && (vi.variant_options?.isNotEmpty ?? false)) {
      sku = vi.variant_options!.values.join('-');
    }

    // Old itemAttributes/variants system — match by SKU.
    if (sku.isNotEmpty && fresh.itemAttributes?.variants != null) {
      final match = fresh.itemAttributes!.variants!
          .where((v) => v.variant_sku == sku)
          .firstOrNull;
      if (match != null) {
        return productCommissionPrice(match.variant_price ?? '0');
      }
    }

    // New productAttributes system — sum effectivePrice for stored selections.
    if (fresh.productAttributes.isNotEmpty &&
        (vi.variant_options?.isNotEmpty ?? false)) {
      double total = 0;
      bool allFound = true;
      for (final cfg in fresh.productAttributes) {
        final selName = vi.variant_options![cfg.attributeTitle];
        if (selName == null) {
          allFound = false;
          break;
        }
        final enabledOpts = cfg.options.where((o) => o.enabled).toList();
        if (cfg.type == 'SS') {
          final opt = enabledOpts.where((o) => o.name == selName).firstOrNull;
          if (opt == null) {
            allFound = false;
            break;
          }
          total += opt.effectivePrice;
        } else {
          // MS options are stored as comma-joined names.
          final names = selName.split(', ').map((s) => s.trim()).toSet();
          for (final name in names) {
            final opt = enabledOpts.where((o) => o.name == name).firstOrNull;
            if (opt != null) total += opt.effectivePrice;
          }
        }
      }
      if (allFound && total > 0) {
        return productCommissionPrice(total.toStringAsFixed(2));
      }
    }

    return null;
  }

  // ── Re-order: validate products in parallel, populate cart ───────────────────
  Future<void> _populateFromReOrder() async {
    final orderModel = widget.reOrderModel!;

    // Restore the original order's service type BEFORE any await so that
    // getDeliveyData() / _validateCart() later use the correct mode.
    final bool wasDineaway = orderModel.takeAway == true;
    final String restoredOrderType = wasDineaway ? 'Dineaway' : 'Delivery';
    final String? restoredDineawayType = wasDineaway ? orderModel.orderType : null;
    if (mounted) {
      setState(() {
        selctedOrderTypeValue = restoredOrderType;
        selectedDineawayType = restoredDineawayType;
        isDineawaySelected = wasDineaway && restoredDineawayType != null;
      });
      SharedPreferences.getInstance()
          .then((sp) => sp.setString('foodType', restoredOrderType));
    }

    // Fetch fresh product data in one batched query (2026-08-05) - see
    // fetchProductsByIds' own doc comment; same fix as _validateCart's
    // identical pattern below.
    final reorderBaseIds =
        orderModel.products.map((cp) => cp.id.split('~').first).toList();
    final reorderProductsById =
        await _fireStoreUtils.fetchProductsByIds(reorderBaseIds);
    final freshList =
        reorderBaseIds.map((id) => reorderProductsById[id]).toList();

    int skipped = 0;
    for (var i = 0; i < orderModel.products.length; i++) {
      final cp = orderModel.products[i];
      final fresh = freshList[i];

      if (fresh == null || !fresh.publish) {
        skipped++;
        continue;
      }

      // Determine if this product needs variant/add-on selection.
      final hasVariant = cp.variant_info != null;
      final hasAddOns = (double.tryParse(cp.extras_price ?? '0') ?? 0) > 0;

      if (hasVariant || hasAddOns) {
        // ── Variant / add-on product ──────────────────────────────────────────
        // Parse the old variant_info so we can pre-populate the dialog.
        VariantInfo? oldVariantInfo;
        try {
          final raw = cp.variant_info;
          if (raw is VariantInfo) {
            oldVariantInfo = raw;
          } else if (raw is Map<String, dynamic>) {
            oldVariantInfo = VariantInfo.fromJson(raw);
          } else if (raw is String && raw.isNotEmpty && raw != 'null') {
            oldVariantInfo = VariantInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          }
        } catch (_) {}

        if (!mounted) continue;

        // Show ProductOptionsDialog with the FRESH product (current Firestore prices)
        // and pre-populated with the previously chosen variant/add-ons.
        // The dialog reads prices directly from the fresh ProductModel — no manual
        // price calculation needed.
        // Pass the chosen product back via Navigator.pop so addProduct is
        // awaited after the modal closes — ensuring all items are in the DB
        // before _reOrderPending = false triggers validation.
        final reOrderResult = await showModalBottomSheet<ProductModel>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useSafeArea: true,
          builder: (ctx) => ProductOptionsDialog(
            productModel: fresh,
            initialVariantInfo: oldVariantInfo,
            onAddToCart: (ProductModel updatedProduct, double totalPrice, int quantity) async {
              Navigator.of(ctx).pop(updatedProduct);
            },
          ),
        );
        if (reOrderResult != null && mounted) {
          final qty = cp.quantity > 0 ? cp.quantity : 1;
          for (int q = 0; q < qty; q++) {
            await cartDatabase.addProduct(reOrderResult, cartDatabase, true);
          }
        }
      } else {
        // ── Plain product — add directly with fresh base price ────────────────
        final freshPrice = productCommissionPrice(
          fresh.disPrice != null &&
                  fresh.disPrice!.isNotEmpty &&
                  (double.tryParse(fresh.disPrice!) ?? 0) != 0
              ? fresh.disPrice!
              : fresh.price,
        );
        final cartProduct = CartProduct(
          id: cp.id,
          category_id: cp.category_id,
          name: cp.name,
          photo: cp.photo,
          price: freshPrice,
          discountPrice: fresh.disPrice ?? '',
          vendorID: cp.vendorID,
          quantity: cp.quantity,
          extras_price: cp.extras_price,
          extras: cp.extras,
          variant_info: cp.variant_info,
        );
        try {
          await cartDatabase.reAddProduct(cartProduct);
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() => _reOrderPending = false);

    if (skipped > 0) {
      _queueOrShowNotification(
        message: skipped == 1
            ? 'An item from your previous order is no longer available.'.tr()
            : '$skipped items from your previous order are no longer available.'.tr(),
        color: const Color(0xFFF59E0B),
        icon: Icons.info_outline_rounded,
      );
    }
  }

  // ── Bill Pay accept: drop the vendor's exact bill into a cleared cart ────────
  // Deliberately does NOT re-fetch/re-price items like _populateFromReOrder —
  // the whole point is the customer pays exactly what the vendor billed, not
  // today's catalog price. Items are inserted byte-for-byte from the vendor's
  // request and the UI locks them from edits (see _isBillPayMode gates in
  // _modernCartItem/_buildItemsContainer). Skips _validateCart() entirely for
  // the same reason — no price/stock reconciliation against catalog data.
  Future<void> _populateFromBillPay() async {
    final order = widget.billPayRequestModel!;
    try {
      await cartDatabase.deleteAllProducts();
      for (final cp in order.products) {
        try {
          await cartDatabase.reAddProduct(cp);
        } catch (_) {}
      }
      vendorModel = await _fireStoreUtils.getVendorByVendorID(order.vendorID);
      vendorID = order.vendorID;
      // getTaxData() already ran unconditionally from initState — no need
      // to call it again here; it's also now internally guarded against
      // re-fetching once taxList is populated (see its own doc comment).
    } catch (_) {
      // Fall back to whatever partial state was populated — the item list
      // itself (already written above) is what matters for the locked UI.
    } finally {
      if (mounted) {
        setState(() {
          _billPayPending = false;
          isDeliverFound = true; // skip getDeliveyData()/_validateCart() — no re-pricing for a locked bill
          _isCartInitialized = true;
        });
      }
    }
  }

  Future<void> getDeliveyData() async {
    isDeliverFound = true;
    // getVendorByVendorID() and getTaxData() have no dependency on each
    // other — getTaxData() only needs the app-wide sectionConstantModel,
    // not vendorModel — so run them concurrently instead of sequentially.
    // Only getRoadDistanceKm further down is a genuine dependency (needs
    // vendorModel.latitude/longitude) and must stay sequential after it.
    final deliverySw = Stopwatch()..start();
    debugPrint('[CART-PERF][getDeliveyData] getVendorByVendorID + getTaxData START (parallel) at ${DateTime.now().toIso8601String()}');
    try {
      await Future.wait([
        _fireStoreUtils
            .getVendorByVendorID(cartProducts.first.vendorID)
            .then((value) {
          vendorModel = value;
          vendorID = cartProducts.first.vendorID;
        }),
        getTaxData(),
      ]);
      debugPrint('[CART-PERF][getDeliveyData] getVendorByVendorID + getTaxData END — ${deliverySw.elapsedMilliseconds}ms');

      if (selctedOrderTypeValue == "Delivery" && addressModel.location != null) {
        final kmStr = await getRoadDistanceKm(
            addressModel.location!,
            UserLocation(
                latitude: vendorModel!.latitude,
                longitude: vendorModel!.longitude));
        getDeliveryCharges(num.parse(kmStr));
      }

      await _validateCart();
    } catch (e) {
      // Vendor or validation fetch failed — exit skeleton so the user isn't stuck.
      if (mounted && !_isCartInitialized) {
        setState(() => _isCartInitialized = true);
      }
    }
  }

  Future<void> _validateCart() async {
    if (!mounted || cartProducts.isEmpty || _isValidating) return;
    // TEMPORARY [CART-PERF] - timing instrumentation for the loading-speed
    // investigation. Remove once done.
    final validateSw = Stopwatch()..start();
    debugPrint('[CART-PERF] _validateCart START — ${cartProducts.length} item(s)');
    // Stamp the hash now so the StreamBuilder doesn't schedule a redundant
    // re-validation when it rebuilds after _isCartInitialized becomes true.
    _lastPermCartHash = cartProducts.map((p) => p.id).join(',');
    setState(() {
      _isValidating = true;
      _itemIssues = {};
      _itemBlocking = {};
      _cartGlobalWarning = null;
      _canCheckout = true;
    });

    try {
    // Vendor status check (data already available from getDeliveyData).
    // Consistent with home-screen badge and restaurant-detail badge via the
    // shared VendorModel.isAcceptingOrders getter.
    if (vendorModel != null) {
      if (!vendorModel!.isAcceptingOrders) {
        setState(() {
          _cartGlobalWarning =
              "Restaurant is currently closed. You cannot place orders right now."
                  .tr();
          _canCheckout = false;
        });
      }
    }

    // ── Fetch all products in one batched query ───────────────────────────────
    // Snapshot the list so mutations during async work don't cause issues.
    // 2026-08-05: was one getProductByID() call per cart line (N round-trips,
    // plus a redundant duplicate read for every extra variant line sharing
    // the same base product) - now a single fetchProductsByIds() call,
    // deduplicated internally and chunked into ceil(distinct/30)
    // whereIn queries (Firestore's per-query limit), instead of N.
    final cartSnapshot = List<CartProduct>.from(cartProducts);
    final baseProductIds =
        cartSnapshot.map((cp) => cp.id.split('~').first).toList();
    final fetchProductsSw = Stopwatch()..start();
    final productsById = await _fireStoreUtils.fetchProductsByIds(baseProductIds);
    final freshProducts =
        baseProductIds.map((id) => productsById[id]).toList();
    debugPrint('[CART-PERF] fetchProductsByIds x${baseProductIds.toSet().length} distinct '
        '(${cartSnapshot.length} line item(s)) — ${fetchProductsSw.elapsedMilliseconds}ms');

    // ── Process results (no more async Firestore calls inside this loop) ──────
    final List<String> idsToRemove = [];
    final List<Map<String, String>> priceChanges = [];
    final List<MapEntry<CartProduct, String>> priceUpdates = [];
    final List<MapEntry<CartProduct, ProductModel>> variantPriceChanged = [];
    final List<String> variantPriceChangedIds = [];

    bool _freshAllowDelivery = true;
    bool _freshAllowDineaway = true;
    bool _freshAllowDineIn = true;
    bool _freshAllowTakeaway = true;
    bool _anyServiceConfigured = false;

    for (var i = 0; i < cartSnapshot.length; i++) {
      final cartProduct = cartSnapshot[i];
      final product = freshProducts[i];

      if (product == null || !product.publish) {
        idsToRemove.add(cartProduct.id);
        continue;
      }

      // ── Aggregate permission flags ──────────────────────────────────────────
      // dineAway is not a standalone service — it is the parent of Dining and Takeaway.
      // A product supports dineaway only when it supports at least one child sub-type.
      final bool productSupportsDineaway = product.dineIn || product.takeaway;
      if (product.deliveryOption || productSupportsDineaway) {
        _anyServiceConfigured = true;
        if (!product.deliveryOption) _freshAllowDelivery = false;
        if (!productSupportsDineaway) _freshAllowDineaway = false;
        if (!product.dineIn) _freshAllowDineIn = false;
        if (!product.takeaway) _freshAllowTakeaway = false;
      }

      // ── Service type compatibility ──────────────────────────────────────────
      if (product.deliveryOption || productSupportsDineaway) {
        final isDineaway = selctedOrderTypeValue == 'Dineaway';
        bool serviceBlocked = false;
        String serviceMsg = '';
        if (!isDineaway && !product.deliveryOption) {
          serviceMsg = 'Delivery order is not available for this item.'.tr();
          serviceBlocked = true;
        } else if (isDineaway && !productSupportsDineaway) {
          serviceMsg = 'DineAway order is not available for this item.'.tr();
          serviceBlocked = true;
        } else if (isDineaway) {
          if (selectedDineawayType == 'Takeaway' && !product.takeaway) {
            serviceMsg = 'TakeAway order is not available for this item.'.tr();
            serviceBlocked = true;
          } else if (selectedDineawayType == 'Dining' && !product.dineIn) {
            serviceMsg = 'Dine-In order is not available for this item.'.tr();
            serviceBlocked = true;
          }
        }
        if (serviceBlocked) {
          if (mounted)
            setState(() {
              _itemIssues[cartProduct.id] = serviceMsg;
              _itemBlocking[cartProduct.id] = true;
              _canCheckout = false;
            });
          continue;
        }
      }

      // ── Out of stock ────────────────────────────────────────────────────────
      if (product.quantity == 0) {
        if (mounted)
          setState(() {
            _itemIssues[cartProduct.id] =
                "Out of stock — remove to proceed".tr();
            _itemBlocking[cartProduct.id] = true;
            _canCheckout = false;
          });
        continue;
      }

      // ── Price change — collect for batched DB write ─────────────────────────
      // Skip price override for items with a variant: the cart price reflects
      // the user's variant selection, which is intentionally different from
      // the base product price in Firestore.
      if (cartProduct.variant_info == null) {
        final freshPrice = productCommissionPrice(
          product.disPrice != null &&
                  product.disPrice!.isNotEmpty &&
                  double.parse(product.disPrice!) != 0
              ? product.disPrice!
              : product.price,
        );
        final freshPriceDouble = double.tryParse(freshPrice) ?? 0.0;
        final cartPriceDouble = double.tryParse(cartProduct.price) ?? 0.0;
        if ((freshPriceDouble - cartPriceDouble).abs() > 0.001) {
          priceChanges.add({
            'name': cartProduct.name,
            'old': cartProduct.price,
            'new': freshPrice,
          });
          priceUpdates.add(MapEntry(cartProduct, freshPrice));
        }
      }

      // ── Variant price change — remove stale item; re-add via dialog ──────────
      if (cartProduct.variant_info != null &&
          !variantPriceChangedIds.contains(cartProduct.id)) {
        final freshVariantPrice = _computeFreshVariantPrice(cartProduct, product);
        if (freshVariantPrice != null) {
          final freshDouble = double.tryParse(freshVariantPrice) ?? 0;
          final cartDouble = double.tryParse(cartProduct.price) ?? 0;
          if ((freshDouble - cartDouble).abs() > 0.001) {
            variantPriceChanged.add(MapEntry(cartProduct, product));
            variantPriceChangedIds.add(cartProduct.id);
          }
        }
      }

      // ── Add-on price change — remove stale item; re-add via dialog ──────────
      if (!variantPriceChangedIds.contains(cartProduct.id)) {
        final extrasPrice = double.tryParse(cartProduct.extras_price ?? '0') ?? 0;
        if (extrasPrice > 0 &&
            cartProduct.extras != null &&
            cartProduct.extras!.isNotEmpty) {
          final addOnNames = cartProduct.extras!
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          double freshExtrasTotal = 0;
          bool allFound = true;
          for (final name in addOnNames) {
            final idx = product.addOnsTitle.indexWhere((t) => t.toString() == name);
            if (idx >= 0 && idx < product.addOnsPrice.length) {
              freshExtrasTotal += double.tryParse(
                    productCommissionPrice(product.addOnsPrice[idx].toString())) ?? 0;
            } else {
              allFound = false;
              break;
            }
          }
          if (allFound && (freshExtrasTotal - extrasPrice).abs() > 0.001) {
            variantPriceChanged.add(MapEntry(cartProduct, product));
            variantPriceChangedIds.add(cartProduct.id);
          }
        }
      }

      // ── Variant removed ─────────────────────────────────────────────────────
      if (cartProduct.variant_info != null &&
          product.itemAttributes != null &&
          product.itemAttributes!.variants != null) {
        VariantInfo? variantInfo;
        try {
          final decoded = jsonDecode(cartProduct.variant_info.toString());
          if (decoded is Map<String, dynamic>) {
            variantInfo = VariantInfo.fromJson(decoded);
          }
        } catch (_) {}
        if (variantInfo != null) {
          final variantExists = product.itemAttributes!.variants!.any(
            (v) => v.variant_sku == variantInfo!.variant_sku,
          );
          if (!variantExists && mounted) {
            setState(() {
              _itemIssues[cartProduct.id] =
                  "Selected variant no longer available".tr();
              _itemBlocking[cartProduct.id] = true;
              _canCheckout = false;
            });
          }
        }
      }
    }

    // ── Apply vendor-level feature gates ─────────────────────────────────────
    if (vendorModel != null) {
      // Layer 1: admin-controlled master switches
      if (!vendorModel!.deliveryEnabled) _freshAllowDelivery = false;
      if (!vendorModel!.dineAwayEnabled) _freshAllowDineaway = false;
      if (!vendorModel!.takeawayEnabled) _freshAllowTakeaway = false;
      if (!vendorModel!.diningEnabled)   _freshAllowDineIn   = false;
      // Layer 2: vendor-controlled temporary pause
      if (!vendorModel!.vendorDeliveryOpen) _freshAllowDelivery = false;
      if (!vendorModel!.vendorDineawayOpen) _freshAllowDineaway = false;
    }

    // ── Refresh top-level permission flags ────────────────────────────────────
    if (mounted) {
      setState(() {
        _allowDelivery = _freshAllowDelivery;
        _allowDineaway = _freshAllowDineaway;
        _allowDineIn = _freshAllowDineIn;
        _allowDineAwayTakeaway = _freshAllowTakeaway;
      });
    }

    // ── Batched DB writes (parallel — each targets a different row) ───────────
    try {
      await Future.wait([
        ...idsToRemove.map((id) => cartDatabase.removeProduct(id)),
        ...variantPriceChangedIds.map((id) => cartDatabase.removeProduct(id)),
        ...priceUpdates.map((u) => cartDatabase.updateProduct(CartProduct(
              id: u.key.id,
              category_id: u.key.category_id,
              name: u.key.name,
              photo: u.key.photo,
              price: u.value,
              vendorID: u.key.vendorID,
              quantity: u.key.quantity,
              extras: u.key.extras,
              extras_price: u.key.extras_price,
              variant_info: u.key.variant_info,
              discountPrice: u.key.discountPrice,
            ))),
      ]);
    } catch (e) {
      debugPrint('[ValidateCart] DB write error: $e');
    }

    // ── Notifications ─────────────────────────────────────────────────────────
    // Use _queueOrShowNotification so these appear AFTER the skeleton has
    // transitioned to the real cart UI (not while the skeleton is still visible).
    if (idsToRemove.isNotEmpty && mounted) {
      _queueOrShowNotification(
        message: "Some items were removed — no longer available.".tr(),
        color: AppThemeData.error500,
        icon: Icons.remove_shopping_cart_outlined,
      );
    }
    if (priceChanges.isNotEmpty && mounted) {
      final String message = priceChanges.length == 1
          ? "${'Price updated from'.tr()} ${amountShow(amount: priceChanges.first['old']!)} ${'to'.tr()} ${amountShow(amount: priceChanges.first['new']!)}"
          : "${priceChanges.length} ${'items price updated to latest'.tr()}";
      _queueOrShowNotification(
        message: message,
        color: const Color(0xFFF59E0B),
        icon: Icons.price_change_outlined,
      );
    }

    // Stamp the post-removal hash BEFORE setting _isCartInitialized so the
    // StreamBuilder's hash check doesn't see a changed cart and schedule a
    // redundant second _validateCart() call right after the skeleton ends.
    final postRemovalHash = cartSnapshot
        .where((cp) =>
            !idsToRemove.contains(cp.id) &&
            !variantPriceChangedIds.contains(cp.id))
        .map((cp) => cp.id)
        .join(',');

    if (mounted) {
      // Clear _isValidating immediately so the skeleton stops "loading",
      // but defer _isCartInitialized by one frame so the SQLite stream can
      // deliver post-write emissions before the hash-check runs in the real
      // cart UI — preventing a spurious second validation trigger.
      setState(() {
        _lastPermCartHash = postRemovalHash;
        _isValidating = false;
      });
      debugPrint('[CART-PERF][_validateCart] setState (skeleton->real UI) called — ${validateSw.elapsedMilliseconds}ms');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[CART-PERF][_validateCart] next frame rendered — ${validateSw.elapsedMilliseconds}ms');
        if (mounted && !_isCartInitialized) {
          setState(() => _isCartInitialized = true);
        }
      });
    }

    // Queue variant-price dialogs to show after the cart UI is visible.
    if (variantPriceChanged.isNotEmpty) {
      _pendingVariantDialogs.addAll(variantPriceChanged);
    }

    // Flush any notifications that were queued during the skeleton phase.
    // addPostFrameCallback ensures the real cart is rendered before they appear.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingNotifications();
      _flushVariantDialogs();
    });
    } catch (e, st) {
      debugPrint('[ValidateCart] unhandled error: $e\n$st');
    } finally {
      // Guarantee _isValidating is always cleared — even when an exception
      // escapes (e.g. vendorModel.isOpen() throws on malformed timeslot data).
      if (mounted && _isValidating) {
        setState(() {
          _isValidating = false;
          if (!_isCartInitialized) _isCartInitialized = true;
        });
      }
      debugPrint('[CART-PERF] _validateCart TOTAL — ${validateSw.elapsedMilliseconds}ms');
    }
  }

  // ── Show ProductOptionsDialog for each variant whose price changed ─────────
  Future<void> _flushVariantDialogs() async {
    if (!mounted || _pendingVariantDialogs.isEmpty) return;
    final toShow = List<MapEntry<CartProduct, ProductModel>>.from(_pendingVariantDialogs);
    _pendingVariantDialogs.clear();
    _dialogsFlushInProgress = true;

    _showTopNotification(
      message: toShow.length == 1
          ? 'A variant item price has changed — please confirm your selection.'.tr()
          : '${toShow.length} ${'variant item prices changed — please re-confirm your selections.'.tr()}',
      color: const Color(0xFFF59E0B),
      icon: Icons.price_change_outlined,
      duration: const Duration(seconds: 5),
    );

    for (final entry in toShow) {
      if (!mounted) break;
      final cp = entry.key;
      final fresh = entry.value;
      VariantInfo? vi;
      try {
        final raw = cp.variant_info;
        if (raw is VariantInfo) {
          vi = raw;
        } else if (raw is Map<String, dynamic>) {
          vi = VariantInfo.fromJson(raw);
        } else if (raw is String && raw.isNotEmpty && raw != 'null') {
          vi = VariantInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        }
      } catch (_) {}

      // Pass the chosen product back via Navigator.pop so addProduct is
      // awaited here — after the modal closes — not fire-and-forget inside
      // the callback.  This guarantees the stream has emitted before we stamp
      // _lastPermCartHash, avoiding a spurious hash-mismatch revalidation.
      final result = await showModalBottomSheet<ProductModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => ProductOptionsDialog(
          productModel: fresh,
          initialVariantInfo: vi,
          onAddToCart: (ProductModel updatedProduct, double totalPrice, int quantity) async {
            Navigator.of(ctx).pop(updatedProduct);
          },
        ),
      );
      if (result != null && mounted) {
        final qty = cp.quantity > 0 ? cp.quantity : 1;
        for (int q = 0; q < qty; q++) {
          await cartDatabase.addProduct(result, cartDatabase, true);
        }
      }
    }

    // Defer by one frame so the SQLite stream delivers the just-written items
    // into cartProducts before we stamp _lastPermCartHash — eliminating the
    // race that caused a spurious second _validateCart() after dialogs.
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _dialogsFlushInProgress = false;
            _lastPermCartHash = cartProducts.map((p) => p.id).join(',');
          });
        }
      });
    }
  }

  getDeliveryCharges(num km) async {
    deliverExec = true;
    String newDeliveryCharges = "0.0";

    if (sectionConstantModel?.serviceTypeFlag == "ecommerce-service") {
      newDeliveryCharges = sectionConstantModel?.delivery_charge ?? "0.0";
    } else {
      DeliveryChargeModel? deliveryChargeModel =
          await _fireStoreUtils.getDeliveryCharges();

      if (deliveryChargeModel != null) {
        if (!deliveryChargeModel.vendorCanModify) {
          if (km > deliveryChargeModel.minimumDeliveryChargesWithinKm) {
            newDeliveryCharges = (km * deliveryChargeModel.deliveryChargesPerKm)
                .toDouble()
                .toStringAsFixed(
                    (currencyData != null) ? currencyData!.decimal : 2);
          } else {
            newDeliveryCharges = deliveryChargeModel.minimumDeliveryCharges
                .toDouble()
                .toStringAsFixed(
                    (currencyData != null) ? currencyData!.decimal : 2);
          }
        } else {
          if (vendorModel != null && vendorModel!.deliveryCharge != null) {
            if (km >
                vendorModel!.deliveryCharge!.minimumDeliveryChargesWithinKm) {
              newDeliveryCharges =
                  (km * vendorModel!.deliveryCharge!.deliveryChargesPerKm)
                      .toDouble()
                      .toStringAsFixed(
                          (currencyData != null) ? currencyData!.decimal : 2);
            } else {
              newDeliveryCharges = vendorModel!
                  .deliveryCharge!.minimumDeliveryCharges
                  .toDouble()
                  .toStringAsFixed(
                      (currencyData != null) ? currencyData!.decimal : 2);
            }
          } else {
            if (km > deliveryChargeModel.minimumDeliveryChargesWithinKm) {
              newDeliveryCharges = (km * deliveryChargeModel.deliveryChargesPerKm)
                  .toDouble()
                  .toStringAsFixed(
                      (currencyData != null) ? currencyData!.decimal : 2);
            } else {
              newDeliveryCharges = deliveryChargeModel.minimumDeliveryCharges
                  .toDouble()
                  .toStringAsFixed(
                      (currencyData != null) ? currencyData!.decimal : 2);
            }
          }
        }
      }
    }

    // Single setState call instead of multiple
    if (mounted) {
      setState(() {
        deliveryCharges = newDeliveryCharges;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    cartDatabase = Provider.of<CartDatabase>(context, listen: true);
    // Create the stream once — reusing the same instance prevents StreamBuilder
    // from resetting (and the scroll position from jumping) on every setState.
    _cartStream ??= cartDatabase.watchProducts;
    cartFuture = cartDatabase.allCartProducts;
    getPrefData();

    // Kick off re-order population once cartDatabase is available
    if (widget.reOrderModel != null && !_reOrderStarted) {
      _reOrderStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _populateFromReOrder();
      });
    }

    // Kick off Bill Pay population once cartDatabase is available
    if (_isBillPayMode && !_billPayStarted) {
      _billPayStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _populateFromBillPay();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDeliveryActiveNotifier,
      builder: (context, deliveryActive, _) {
        if (selctedOrderTypeValue == 'Delivery'.tr() && !deliveryActive) {
          return ComingSoonScreen(message: deliveryOffMessageNotifier.value);
        }
        return _buildScreen(context);
      },
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : const Color(0xFFF2F0F8),
      body: SafeArea(
        child: StreamBuilder<List<CartProduct>>(
          stream: _cartStream ?? cartDatabase.watchProducts,
          initialData: const [],
          builder: (context, snapshot) {
            // ── Skeleton phase: show until first validation completes ──────────
            if (!_isCartInitialized) {
              final data = snapshot.data;
              if (data != null) {
                // Only treat as empty once the stream has emitted real data.
                // initialData: const [] triggers connectionState == waiting on the
                // very first build, which would instantly skip validation before
                // the stream has a chance to deliver the actual cart contents.
                if (data.isEmpty &&
                    !_reOrderPending &&
                    !_billPayPending &&
                    snapshot.connectionState != ConnectionState.waiting) {
                  // Real empty cart confirmed — skip validation, show real UI immediately
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _isCartInitialized = true);
                  });
                } else if (data.isNotEmpty && !_reOrderPending && !_billPayPending) {
                  // Keep the skeleton visible while validation runs.
                  // _validateCart() sets _isCartInitialized = true when it
                  // finishes, so the cart only appears fully checked.
                  cartProducts = data;
                  if (!isDeliverFound) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || isDeliverFound) return;
                      getDeliveyData();
                    });
                  }
                }
              }
              return const CartSkeletonLoader();
            }

            if (!snapshot.hasData || (snapshot.data?.isEmpty ?? true)) {
              // Cart was just cleared (e.g. section switch) — reset all billing state.
              // Skip when _pendingVariantDialogs is non-empty: the cart is temporarily
              // empty because validation just removed stale-price items that are about
              // to be re-added via ProductOptionsDialog — resetting vendor state here
              // would trigger unnecessary re-validation cycles.
              if (cartProducts.isNotEmpty && _pendingVariantDialogs.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      couponId = '';
                      percentage = 0.0;
                      type = 0.0;
                      txt.clear();
                      _appliedCouponMinAmount = 0.0;
                      specialDiscount = 0.0;
                      specialDiscountAmount = 0.0;
                      specialType = '';
                      tipValue = 0.0;
                      deliveryCharges = '0.0';
                      isDeliverFound = false;
                      vendorID = '';
                      vendorModel = null;
                      selectedDineawayType = null;
                      isDineawaySelected = false;
                      _allowDelivery = true;
                      _allowDineaway = true;
                      _allowDineIn = true;
                      _allowDineAwayTakeaway = true;
                    });
                  }
                });
              }
              return SizedBox(
                width: MediaQuery.of(context).size.width * 1,
                child: Center(
                  child: showEmptyState('Empty Cart'.tr(), context),
                ),
              );
            } else {
              cartProducts = snapshot.data!;
              // Recompute service permissions whenever cart composition changes
              final cartHash = cartProducts.map((p) => p.id).join(',');
              if (_lastPermCartHash != cartHash) {
                _lastPermCartHash = cartHash;
                if (_isBillPayMode) {
                  // Locked bill — no fresh-price/stock reconciliation against
                  // catalog data; the customer pays exactly what was billed.
                } else if (_isCartInitialized && !_isValidating && !_dialogsFlushInProgress) {
                  // Cart items changed after initial load — re-validate from Firestore
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_isValidating && !_dialogsFlushInProgress) _validateCart();
                  });
                } else {
                  // Still initialising — use cached SharedPreferences permissions
                  _computeServicePermissions(cartProducts);
                }
              }
              if (!isDeliverFound && !_isValidating) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !isDeliverFound && !_isValidating) getDeliveyData();
                });
              }
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Cart validation status (always first) ──
                            if (_isValidating) ...[
                              _buildValidatingBanner(),
                              const SizedBox(height: 12),
                            ] else if (_cartGlobalWarning != null ||
                                _itemIssues.isNotEmpty) ...[
                              _buildIssuesSummaryCard(),
                              const SizedBox(height: 12),
                            ],

                            // ── Global items container ──
                            _buildItemsContainer(),
                            const SizedBox(height: 14),

                            // ── Service restriction banner ──
                            if (_serviceRestrictionMessage != null) ...[
                              _buildServiceRestrictionBanner(_serviceRestrictionMessage!),
                              const SizedBox(height: 12),
                            ],

                            // ── Coupon ──
                            _sectionCard(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    _iconBadge(Icons.local_offer_rounded),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            couponId.isNotEmpty
                                                ? txt.text
                                                : "View Coupons".tr(),
                                            style: AppTypography.labelLarge
                                                .copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.1,
                                              color: isDarkMode(context)
                                                  ? AppThemeData.darkTextPrimary
                                                  : AppThemeData.neutral900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            couponId.isNotEmpty
                                                ? "Coupon applied!".tr()
                                                : "Tap to view & apply coupons"
                                                    .tr(),
                                            style: AppTypography.labelSmall
                                                .copyWith(
                                              fontWeight: FontWeight.w500,
                                              color: couponId.isNotEmpty
                                                  ? AppThemeData.primary500
                                                  : (isDarkMode(context)
                                                      ? AppThemeData
                                                          .darkTextTertiary
                                                      : AppThemeData
                                                          .neutral500),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (couponId.isNotEmpty) ...[
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            couponId = '';
                                            percentage = 0.0;
                                            type = 0.0;
                                            txt.clear();
                                            _appliedCouponMinAmount = 0.0;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppThemeData.error500
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            "Remove".tr(),
                                            style: AppTypography.labelSmall
                                                .copyWith(
                                              color: AppThemeData.error500,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    GestureDetector(
                                      onTap: () {
                                        // Refresh coupons each open so newly
                                        // added/removed vendor coupons and
                                        // changed cart totals are reflected.
                                        setState(() {
                                          coupon = _fireStoreUtils
                                              .getAllCoupons();
                                        });
                                        showModalBottomSheet(
                                          isScrollControlled: true,
                                          isDismissible: true,
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          enableDrag: true,
                                          builder: (BuildContext ctx) =>
                                              sheet(ctx),
                                        );
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppThemeData.primary500,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(
                                          couponId.isNotEmpty
                                              ? Icons.check
                                              : Icons.add,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Address ──
                            if (selctedOrderTypeValue == "Delivery") ...[
                              _modernAddressSection(),
                              const SizedBox(height: 12),
                            ],

                            // ── Schedule (not offered for Bill Pay — you're paying for what
                            // was already served, not scheduling a future order) ──
                            if ((sectionConstantModel?.serviceTypeFlag ?? '') !=
                                    "ecommerce-service" &&
                                !_isBillPayMode) ...[
                              _modernScheduleSection(),
                              const SizedBox(height: 12),
                            ],

                            // ── Dineaway sub-type picker (skipped for Bill Pay — the vendor
                            // already decided this is a bill settlement, not a fresh
                            // Takeaway/Dining choice) ──
                            if (selctedOrderTypeValue == "Dineaway" && !_isBillPayMode) ...[
                              _modernDineawaySection(),
                              const SizedBox(height: 12),
                            ],

                            // ── Bill Details ──
                            _modernSummarySection(
                                snapshot.data!, lstExtras, vendorID),
                            const SizedBox(height: 12),

                            // ── Tip ──
                            if (selctedOrderTypeValue == "Delivery") ...[
                              _modernTipSection(),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ── Place Order Bar ────────────────────────────────────
                  Builder(builder: (context) {
                    final isDark = isDarkMode(context);
                    final canAct = !_isValidating && _canCheckout && _serviceRestrictionMessage == null;
                    void _handleTap() {
                      if (_isValidating) {
                        _showTopNotification(
                          message: "Validating cart, please wait...".tr(),
                          color: AppThemeData.primary500,
                          icon: Icons.hourglass_top_rounded,
                          duration: const Duration(seconds: 2),
                        );
                        return;
                      }
                      if (!_canCheckout) {
                        _showTopNotification(
                          message: _cartGlobalWarning ??
                              "Please resolve cart issues before placing order.".tr(),
                          color: AppThemeData.error500,
                          icon: Icons.warning_amber_rounded,
                        );
                        return;
                      }
                      final serviceMsg = _serviceRestrictionMessage;
                      if (serviceMsg != null) {
                        _showServiceMismatchDialog(
                          'Order Cannot Be Placed'.tr(),
                          serviceMsg,
                        );
                        return;
                      }
                      if (selctedOrderTypeValue == "Dineaway" &&
                          (!isDineawaySelected || selectedDineawayType == null)) {
                        _showTopNotification(
                          message: "Please select order type.".tr(),
                          color: AppThemeData.primary500,
                          icon: Icons.info_outline_rounded,
                          duration: const Duration(seconds: 3),
                        );
                        return;
                      }
                      if (selctedOrderTypeValue == "Delivery" && !_deliveryAddressComplete) {
                        setState(() => _houseFieldError = true);
                        _showTopNotification(
                          message: (addressModel.locality?.isEmpty ?? true)
                              ? "Please pick your delivery location.".tr()
                              : "Please enter your house / flat details.".tr(),
                          color: AppThemeData.error500,
                          icon: Icons.warning_amber_rounded,
                        );
                        return;
                      }
                      if (couponId.isEmpty) txt.text = "";

                      // Use the resolved (post-conflict-rules, post-ceiling)
                      // amounts here, not the raw fields — grandtotal above
                      // was computed from these, and the order document must
                      // match what was actually charged (see their
                      // declaration for why they're safe to read here).
                      final specialDiscountMap = {
                        'special_discount': effectiveSpecialDiscountAmount,
                        'special_discount_label': specialDiscount,
                        'specialType': specialType,
                      };
                      final isDelivery = selctedOrderTypeValue == "Delivery";
                      final isTakeaway = selctedOrderTypeValue == "Dineaway";
                      final String? orderTypeToStore =
                          selctedOrderTypeValue == "Dineaway" ? selectedDineawayType : null;
                      push(
                        context,
                        PaymentScreen(
                          total: grandtotal,
                          products: cartProducts,
                          discount: effectiveDiscountVal,
                          couponCode: txt.text,
                          couponId: couponId,
                          notes: noteController.text,
                          extra_addons: commaSepratedAddOns,
                          tipValue: isDelivery ? tipValue.toString() : "0",
                          take_away: isTakeaway,
                          deliveryCharge: isDelivery ? deliveryCharges : "0",
                          taxModel: taxList,
                          specialDiscountMap: specialDiscountMap,
                          scheduleTime: scheduleTime,
                          addressModel: addressModel,
                          orderType: orderTypeToStore,
                          // Phase 1 real-time seat availability - only
                          // meaningful for a Dining order at a vendor that
                          // opted in (the picker above is only ever shown
                          // in that case).
                          diningGuestCount: orderTypeToStore == 'Dining' ? _diningGuestCount : null,
                          billPayRequestId: widget.billPayRequestModel?.id,
                          expectedBillVersion:
                              widget.billPayRequestModel?.billPayExpiresAt?.millisecondsSinceEpoch,
                        ),
                      );
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppThemeData.darkBgSecondary
                            : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.10),
                            blurRadius: 20,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                          child: Row(
                            children: [
                              // ── Left: item count + total price ────────────
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    cartProducts.length == 1
                                        ? "1 item".tr()
                                        : "${cartProducts.length} ${"items".tr()}",
                                    style: AppTypography.caption.copyWith(
                                      color: isDark
                                          ? AppThemeData.neutral400
                                          : AppThemeData.neutral500,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    amountShow(amount: grandtotal.toString()),
                                    style: AppTypography.h5.copyWith(
                                      color: isDark
                                          ? AppThemeData.darkTextPrimary
                                          : AppThemeData.neutral900,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(width: 16),

                              // ── Right: Place Order / Select Address button ──
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _handleTap,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 220),
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: canAct
                                            ? const LinearGradient(
                                                colors: [
                                                  AppThemeData.primary500,
                                                  AppThemeData.primary600,
                                                ],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              )
                                            : LinearGradient(
                                                colors: [
                                                  AppThemeData.neutral300,
                                                  AppThemeData.neutral400,
                                                ],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: canAct
                                            ? [
                                                BoxShadow(
                                                  color: AppThemeData.primary500
                                                      .withValues(alpha: 0.35),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ]
                                            : [],
                                      ),
                                      child: Center(
                                        child: _isValidating
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                                ),
                                              )
                                            : Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    _serviceRestrictionMessage != null
                                                        ? "Service Paused".tr()
                                                        : !_canCheckout
                                                            ? "Issues Found".tr()
                                                            : "Place Order".tr(),
                                                    style: AppTypography.labelLarge.copyWith(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Icon(
                                                    _serviceRestrictionMessage != null
                                                        ? Icons.pause_circle_outline_rounded
                                                        : !_canCheckout
                                                            ? Icons.warning_amber_rounded
                                                            : Icons.arrow_forward_rounded,
                                                    color: Colors.white,
                                                    size: 18,
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  // ──────────────────────────────────────────────────────────
                ],
              );
            }
          },
        ),
      ),
    );
  }

  // Shared card wrapper used by all sections
  Widget _sectionCard({required Widget child}) {
    final dark = isDarkMode(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark
              ? AppThemeData.darkBorderSecondary
              : const Color(0xFFE5E1FF),
          width: 1.0,
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: AppThemeData.primary500.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }

  // Shared icon badge for section leading icons
  Widget _iconBadge(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeData.primary500.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(9),
      child: Icon(icon, color: AppThemeData.primary500, size: 22),
    );
  }

  // Delivery location section — locality picker + inline house/flat + landmark
  Widget _modernAddressSection() {
    final dark = isDarkMode(context);
    final hasArea = addressModel.locality != null &&
        addressModel.locality!.isNotEmpty;
    final areaText = hasArea
        ? addressModel.locality!
        : 'Tap to pick your location'.tr();

    Future<void> pickAddress() async {
      final result = await Navigator.of(context).push<AddressModel>(
        MaterialPageRoute(builder: (_) => const DeliveryAddressScreen()),
      );
      if (result != null && mounted) {
        // A new location means the old house/flat + landmark no longer
        // apply — clear both so the user re-enters them for this address.
        result.address = '';
        result.landmark = '';
        _houseCtrl.clear();
        _landmarkCtrl.clear();
        clearRoadDistanceCache();
        setState(() {
          addressModel = result;
          MyAppState.selectedPosotion = result;
        });
        getDeliveyData();
      }
    }

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: _iconBadge(Icons.location_on_rounded),
            title: Text(
              'Select Location'.tr(),
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                color: dark
                    ? AppThemeData.darkTextPrimary
                    : AppThemeData.neutral900,
              ),
            ),
            subtitle: Text(
              areaText.length > 50
                  ? '${areaText.substring(0, 50)}...'
                  : areaText,
              style: AppTypography.bodySmall.copyWith(
                color: dark
                    ? AppThemeData.darkTextSecondary
                    : AppThemeData.neutral600,
              ),
            ),
            trailing: GestureDetector(
              onTap: pickAddress,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppThemeData.primary500.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  hasArea ? 'Change'.tr() : 'Pick'.tr(),
                  style: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppThemeData.primary500,
                  ),
                ),
              ),
            ),
          ),
          if (hasArea) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _houseCtrl,
                textCapitalization: TextCapitalization.words,
                maxLength: 250,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: TextStyle(
                  color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                  fontSize: 14,
                ),
                onChanged: (value) {
                  addressModel.address = value.trim();
                  if (_houseFieldError && value.trim().isNotEmpty) {
                    setState(() => _houseFieldError = false);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'House / Flat / Floor / Building (required)'.tr(),
                  hintStyle: TextStyle(
                    color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(Icons.home_work_rounded, size: 18, color: AppThemeData.primary500),
                  filled: true,
                  fillColor: dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _houseFieldError
                          ? AppThemeData.error500
                          : (dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _houseFieldError
                          ? AppThemeData.error500
                          : (dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _houseFieldError ? AppThemeData.error500 : AppThemeData.primary500,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _landmarkCtrl,
                textCapitalization: TextCapitalization.words,
                maxLength: 250,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: TextStyle(
                  color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                  fontSize: 14,
                ),
                onChanged: (value) => addressModel.landmark = value.trim(),
                decoration: InputDecoration(
                  hintText: 'Landmark (optional)'.tr(),
                  hintStyle: TextStyle(
                    color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(Icons.place_rounded, size: 18, color: AppThemeData.neutral400),
                  filled: true,
                  fillColor: dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppThemeData.primary500, width: 1.5),
                  ),
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 13,
                      color: dark
                          ? AppThemeData.darkTextTertiary
                          : AppThemeData.neutral400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pick your location first to enter house / flat details'.tr(),
                      style: AppTypography.caption.copyWith(
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Dineaway area picker card ──────────────────────────────────────────────
  Widget _dineawayLocationSection() {
    final dark = isDarkMode(context);
    final area = (addressModel.locality != null && addressModel.locality!.isNotEmpty)
        ? addressModel.locality!
        : 'Tap to set your area'.tr();

    return _sectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _iconBadge(Icons.my_location_rounded),
        title: Text(
          'Your Area'.tr(),
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        subtitle: GestureDetector(
          onTap: () => _showDineawayAreaSheet(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                area.length > 45 ? '${area.substring(0, 45)}...' : area,
                style: AppTypography.bodySmall.copyWith(
                  color: dark
                      ? AppThemeData.darkTextSecondary
                      : AppThemeData.neutral600,
                ),
              ),
              Text(
                'Tap to pick area'.tr(),
                style: AppTypography.labelSmall.copyWith(
                  color: AppThemeData.primary500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        trailing: GestureDetector(
          onTap: () => _showDineawayAreaSheet(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Change'.tr(),
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppThemeData.primary500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDineawayAreaSheet() {
    final dark = isDarkMode(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dark
                      ? AppThemeData.darkBorderPrimary
                      : AppThemeData.neutral300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _iconBadge(Icons.my_location_rounded),
                const SizedBox(width: 12),
                Text(
                  'Your Area'.tr(),
                  style: AppTypography.h5.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Only your area is needed — no house or flat number required for dine-away orders.'
                  .tr(),
              style: AppTypography.bodySmall.copyWith(
                color: dark
                    ? AppThemeData.darkTextTertiary
                    : AppThemeData.neutral500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            // Current area display
            if (addressModel.locality != null &&
                addressModel.locality!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark
                      ? AppThemeData.darkBgTertiary
                      : AppThemeData.neutral50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: dark
                        ? AppThemeData.darkBorderSecondary
                        : AppThemeData.neutral200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.pin_drop_rounded,
                        size: 16, color: AppThemeData.primary500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        addressModel.locality!,
                        style: AppTypography.bodyMedium.copyWith(
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral800,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            // Pick on Map button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeData.primary500,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.map_rounded,
                    size: 18, color: Colors.white),
                label: Text(
                  'Pick on Map'.tr(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  final result = await Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => const LocationPicker()));
                  if (result != null && mounted) {
                    clearRoadDistanceCache();
                    setState(() {
                      addressModel.locality = result.displayName.toString();
                      addressModel.location = UserLocation(
                        latitude: result.lat,
                        longitude: result.lon,
                      );
                    });
                    getDeliveyData();
                  }
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetCtx),
              child: Center(
                child: Text(
                  'Close'.tr(),
                  style: AppTypography.labelMedium.copyWith(
                    color: dark
                        ? AppThemeData.darkTextSecondary
                        : AppThemeData.neutral500,
                  ),
                ),
              ),
            ),
            SafeArea(top: false, child: const SizedBox(height: 4)),
          ],
        ),
      ),
    );
  }

  // Modern Schedule Section
  Widget _modernScheduleSection() {
    return _sectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _iconBadge(Icons.schedule_rounded),
        title: Text(
          "Schedule Order".tr(),
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: isDarkMode(context)
                ? AppThemeData.darkTextPrimary
                : AppThemeData.neutral900,
          ),
        ),
        subtitle: Text(
          scheduleTime == null
              ? (selctedOrderTypeValue == "Delivery"
                  ? "Delivery as soon as possible".tr()
                  : selectedDineawayType == "Takeaway"
                      ? "Takeaway as soon as possible".tr()
                      : selectedDineawayType == "Dining"
                          ? "Dine-in as soon as possible".tr()
                          : "Ready as soon as possible".tr())
              : DateFormat("EEE, d MMM 'at' hh:mm a").format(scheduleTime!.toDate()),
          style: AppTypography.bodySmall.copyWith(
            color: isDarkMode(context)
                ? AppThemeData.darkTextSecondary
                : AppThemeData.neutral600,
          ),
        ),
        trailing: GestureDetector(
          onTap: () {
            if (vendorModel != null && !vendorModel!.reststatus) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                SnackBar(
                  content: Text(
                    "This restaurant is currently closed. Scheduled booking is not available right now."
                        .tr(),
                  ),
                  backgroundColor: AppThemeData.error500,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
              return;
            }
            _showSchedulePicker();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              scheduleTime == null ? "Select".tr() : "Change".tr(),
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppThemeData.primary500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Parses "HH:mm" into total minutes since midnight. Returns -1 on error.
  int _parseHHMM(String t) {
    final p = t.split(':');
    if (p.length != 2) return -1;
    final h = int.tryParse(p[0]) ?? -1;
    final m = int.tryParse(p[1]) ?? -1;
    return (h < 0 || m < 0) ? -1 : h * 60 + m;
  }

  // Generates 30-minute time slots for the given day offset (0=today, 1=tomorrow).
  // Slot range is derived from vendor's working hours for that day; falls back to
  // 08:00–23:00 when no working-hours entry is configured.
  // For today, only slots at least 30 min from now are included.
  List<DateTime> _generateTimeSlots(int dateIndex) {
    final now = DateTime.now();
    final base = dateIndex == 0 ? now : now.add(const Duration(days: 1));
    final date = DateTime(base.year, base.month, base.day);
    final dayName = DateFormat('EEEE', 'en_US').format(date);

    // Determine slot window from vendor working hours for this day
    int startMinutes = 8 * 60;   // fallback: 08:00
    int endMinutes   = 23 * 60;  // fallback: 23:00
    if (vendorModel != null && vendorModel!.workingHours.isNotEmpty) {
      for (final wh in vendorModel!.workingHours) {
        if (wh.day == dayName && wh.timeslot?.isNotEmpty == true) {
          int minStart = 24 * 60;
          int maxEnd   = 0;
          for (final ts in wh.timeslot!) {
            if (ts.from?.isNotEmpty == true && ts.to?.isNotEmpty == true) {
              final f = _parseHHMM(ts.from!);
              final t = _parseHHMM(ts.to!);
              if (f >= 0 && f < minStart) minStart = f;
              if (t >= 0 && t > maxEnd)  maxEnd   = t;
            }
          }
          if (minStart < 24 * 60 && maxEnd >= 0) {
            startMinutes = minStart;
            endMinutes   = maxEnd;
            // Midnight-crossing slot (e.g. 22:00→02:00): end < start in raw minutes
            if (endMinutes <= startMinutes) endMinutes += 1440;
          }
          break;
        }
      }
    }

    final List<DateTime> slots = [];
    for (int m = startMinutes; m <= endMinutes; m += 30) {
      slots.add(date.add(Duration(hours: m ~/ 60, minutes: m % 60)));
    }

    if (dateIndex == 0) {
      final cutoff = now.add(const Duration(minutes: 30));
      return slots.where((s) => s.isAfter(cutoff)).toList();
    }
    return slots;
  }

  void _showSchedulePicker() {
    int selectedDateIndex = 0;
    if (scheduleTime != null) {
      final today = DateTime.now();
      final s = scheduleTime!.toDate();
      if (s.year == today.year &&
          s.month == today.month &&
          s.day == today.day) {
        selectedDateIndex = 0;
      } else {
        selectedDateIndex = 1;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final dark = isDarkMode(context);
            final slots = _generateTimeSlots(selectedDateIndex);

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              decoration: BoxDecoration(
                color: dark ? AppThemeData.darkBgSecondary : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.neutral300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Schedule Order".tr(),
                            style: AppTypography.h5.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selctedOrderTypeValue == "Delivery"
                                ? "Choose a delivery date and time".tr()
                                : selectedDineawayType == "Takeaway"
                                    ? "Choose a pickup date and time".tr()
                                    : selectedDineawayType == "Dining"
                                        ? "Choose a dining date and time".tr()
                                        : "Choose a date and time".tr(),
                            style: AppTypography.bodySmall.copyWith(
                              color: dark
                                  ? AppThemeData.darkTextSecondary
                                  : AppThemeData.neutral500,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Date selection ──
                          Text(
                            "Select Date".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _schedDatePill(
                                label: "Today".tr(),
                                date: DateFormat("d MMM").format(DateTime.now()),
                                isSelected: selectedDateIndex == 0,
                                dark: dark,
                                onTap: () =>
                                    setSheetState(() => selectedDateIndex = 0),
                              ),
                              const SizedBox(width: 12),
                              _schedDatePill(
                                label: "Tomorrow".tr(),
                                date: DateFormat("d MMM").format(
                                    DateTime.now()
                                        .add(const Duration(days: 1))),
                                isSelected: selectedDateIndex == 1,
                                dark: dark,
                                onTap: () =>
                                    setSheetState(() => selectedDateIndex = 1),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Time slot selection ──
                          Text(
                            "Select Time".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral800,
                            ),
                          ),
                          const SizedBox(height: 10),

                          if (slots.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  "No available slots for today.\nTry selecting Tomorrow."
                                      .tr(),
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: dark
                                        ? AppThemeData.darkTextSecondary
                                        : AppThemeData.neutral500,
                                  ),
                                ),
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: slots.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 2.4,
                              ),
                              itemBuilder: (context, index) {
                                final slot = slots[index];
                                final bool sel = scheduleTime != null &&
                                    scheduleTime!.toDate().year == slot.year &&
                                    scheduleTime!.toDate().month ==
                                        slot.month &&
                                    scheduleTime!.toDate().day == slot.day &&
                                    scheduleTime!.toDate().hour == slot.hour &&
                                    scheduleTime!.toDate().minute ==
                                        slot.minute;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      scheduleTime = Timestamp.fromDate(slot);
                                      if (selectedDineawayType == "Bill Pay") {
                                        selectedDineawayType = null;
                                        isDineawaySelected = false;
                                      }
                                    });
                                    setSheetState(() {});
                                  },
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? AppThemeData.primary500
                                          : (dark
                                              ? AppThemeData.darkBgTertiary
                                              : AppThemeData.neutral100),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                        color: sel
                                            ? AppThemeData.primary500
                                            : (dark
                                                ? AppThemeData
                                                    .darkBorderSecondary
                                                : AppThemeData.neutral200),
                                      ),
                                    ),
                                    child: Text(
                                      DateFormat("hh:mm a").format(slot),
                                      style:
                                          AppTypography.labelSmall.copyWith(
                                        color: sel
                                            ? Colors.white
                                            : (dark
                                                ? AppThemeData
                                                    .darkTextSecondary
                                                : AppThemeData.neutral700),
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Action buttons ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemeData.primary500,
                              disabledBackgroundColor:
                                  AppThemeData.neutral300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: scheduleTime == null
                                ? null
                                : () {
                                    final cutoff = DateTime.now().add(const Duration(minutes: 30));
                                    if (scheduleTime!.toDate().isBefore(cutoff)) {
                                      // Slot became stale while the picker was open
                                      setState(() => scheduleTime = null);
                                      setSheetState(() {});
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(SnackBar(
                                        content: Text('Selected time is no longer available. Please choose a new slot.'.tr()),
                                        backgroundColor: AppThemeData.warning400,
                                        behavior: SnackBarBehavior.floating,
                                      ));
                                    } else {
                                      Navigator.pop(ctx);
                                    }
                                  },
                            child: Text(
                              "Confirm Schedule".tr(),
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => scheduleTime = null);
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            selctedOrderTypeValue == "Delivery"
                                ? "Clear & Deliver ASAP".tr()
                                : selectedDineawayType == "Takeaway"
                                    ? "Clear & Pickup ASAP".tr()
                                    : selectedDineawayType == "Dining"
                                        ? "Clear & Dine-in ASAP".tr()
                                        : "Clear & Order ASAP".tr(),
                            style: AppTypography.labelMedium.copyWith(
                              color: dark
                                  ? AppThemeData.darkTextSecondary
                                  : AppThemeData.neutral500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _schedDatePill({
    required String label,
    required String date,
    required bool isSelected,
    required VoidCallback onTap,
    required bool dark,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppThemeData.primary500
                : (dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppThemeData.primary500
                  : (dark
                      ? AppThemeData.darkBorderPrimary
                      : AppThemeData.neutral200),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected
                      ? Colors.white
                      : (dark
                          ? AppThemeData.darkTextSecondary
                          : AppThemeData.neutral700),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: AppTypography.caption.copyWith(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.80)
                      : (dark
                          ? AppThemeData.darkTextTertiary
                          : AppThemeData.neutral400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modern Summary Section
  Widget _modernSummarySection(
      List<CartProduct> data, List<AddAddonsDemo> lstExtras, String vendorID) {
    // Use the logic from buildTotalRow, but with a modern card UI, icons, and color highlights
    var _font = 16.00;
    subTotal = 0.00;
    grandtotal = 0;
    double discountVal = 0;

    for (int a = 0; a < data.length; a++) {
      CartProduct e = data[a];
      bool isAddOnApplied = false;
      double AddOnVal = 0;
      for (int i = 0; i < lstExtras.length; i++) {
        AddAddonsDemo addAddonsDemo = lstExtras[i];
        if (addAddonsDemo.categoryID == e.id) {
          isAddOnApplied = true;
          AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
        }
      }
      if (e.extras_price != null &&
          e.extras_price != "" &&
          double.parse(e.extras_price!) != 0.0) {
        subTotal += double.parse(e.extras_price!) * e.quantity;
      }
      subTotal += double.parse(e.price) * e.quantity;
      grandtotal = subTotal + double.parse(deliveryCharges) + tipValue;
    }

    // Re-validate the applied coupon's minimum-order condition against the
    // *current* subtotal on every build. Previously this was only checked
    // once at apply-time (_doApplyCoupon/_applyManualCoupon) — removing an
    // item afterwards dropped subTotal below the coupon's applicableAmount
    // but the coupon stayed visually "applied" and kept discounting the
    // displayed total indefinitely (server-side verifyCoupon() already
    // rejects it at checkout regardless, but the cart showed a total the
    // customer would never actually be charged).
    if (couponId.isNotEmpty &&
        _appliedCouponMinAmount > 0 &&
        subTotal < _appliedCouponMinAmount) {
      final removedMinAmount = _appliedCouponMinAmount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || couponId.isEmpty) return;
        setState(() {
          couponId = '';
          percentage = 0.0;
          type = 0.0;
          txt.clear();
          _appliedCouponMinAmount = 0.0;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
          content: Text(
            'Coupon removed — order total is now below its minimum of ${amountShow(amount: removedMinAmount.toStringAsFixed(2))}.'
                .tr(),
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      });
      // Don't let this build still show the stale discount in the total.
      percentage = 0.0;
      type = 0.0;
    }

    if (percentage != null) {
      amount = 0;
      amount = subTotal * percentage / 100;
      discountVal = subTotal * percentage / 100;
      grandtotal = grandtotal - amount;
      per = amount.toDouble();
    }
    amount = grandtotal - type;
    grandtotal = amount;
    if (type != 0) {
      discountVal = type;
    }

    if (vendorModel != null && specialDiscountEnable) {
      if (vendorModel!.specialDiscountEnable) {
        // Reset special discount amount at the beginning
        specialDiscountAmount = 0.0;
        final now = _serverAdjustedNow;
        var day = DateFormat('EEEE', 'en_US').format(now);
        var date = DateFormat('dd-MM-yyyy').format(now);
        
        print('🔍 Special Discount Evaluation Started');
        print('📅 Current day: $day, Date: $date');
        print('🛒 Cart subtotal: ₹$subTotal, Order type: $selctedOrderTypeValue');
        
        // Collect all eligible discounts for maximum selection
        List<Map<String, dynamic>> eligibleDiscounts = [];
        
        vendorModel!.specialDiscount.forEach((dayDiscount) {
          if (day == dayDiscount.day.toString()) {
            print('✅ Found discount rules for $day');
            
            if (dayDiscount.timeslot?.isNotEmpty == true) {
              for (final timeSlot in dayDiscount.timeslot!) {
                // Skip incomplete slots (BUG-2 guard: timeslot can be null in old data)
                if ((timeSlot.from?.isEmpty ?? true) || (timeSlot.to?.isEmpty ?? true)) continue;
                var start = DateFormat("dd-MM-yyyy HH:mm")
                    .parse(date + " " + timeSlot.from!);
                var end = DateFormat("dd-MM-yyyy HH:mm")
                    .parse(date + " " + timeSlot.to!);
                // Midnight-crossing slot: if end ≤ start the window spans into
                // the next calendar day (e.g. 22:00 → 02:00).
                if (!end.isAfter(start)) {
                  end = end.add(const Duration(days: 1));
                }

                print('⏰ Checking timeslot: ${timeSlot.from} - ${timeSlot.to}');

                if (isCurrentDateInRange(start, end)) {
                  print('✅ Time condition met');

                  // Check if subtotal meets the applicable amount condition
                  bool subtotalCondition = true;
                  if (timeSlot.applicableAmount != null && timeSlot.applicableAmount!.isNotEmpty) {
                    double applicableAmount = double.parse(timeSlot.applicableAmount!);
                    subtotalCondition = subTotal >= applicableAmount;
                    print('💰 Min amount: ₹$applicableAmount, Condition: ${subtotalCondition ? "✅ Met" : "❌ Not met"}');
                  }

                  // Check if order type matches
                  bool orderTypeCondition = true;
                  if (timeSlot.orderType != null && timeSlot.orderType!.isNotEmpty) {
                    String currentOrderType = selctedOrderTypeValue == "Delivery" ? "Delivery" : "Takeaway";
                    orderTypeCondition = timeSlot.orderType == currentOrderType;
                    print('🚚 Order type: ${timeSlot.orderType}, Condition: ${orderTypeCondition ? "✅ Met" : "❌ Not met"}');
                  }

                  // Add to eligible list if both conditions are met
                  if (subtotalCondition && orderTypeCondition) {
                    double discountValue = double.parse(timeSlot.discount.toString());
                    String discountType = timeSlot.type.toString();

                    // Calculate actual discount amount for comparison
                    double actualDiscountAmount;
                    if (discountType == "percentage") {
                      actualDiscountAmount = subTotal * discountValue / 100;
                    } else {
                      actualDiscountAmount = discountValue;
                    }

                    eligibleDiscounts.add({
                      'discountValue': discountValue,
                      'discountType': discountType,
                      'actualAmount': actualDiscountAmount,
                      'description': discountType == "percentage"
                          ? '${discountValue.toStringAsFixed(0)}% off (${amountShow(amount: actualDiscountAmount.toStringAsFixed(2))})'
                          : 'Flat ${amountShow(amount: discountValue.toStringAsFixed(2))} off'
                    });

                    print('✅ Eligible discount found: ${eligibleDiscounts.last['description']}');
                  } else {
                    print('❌ Discount not eligible - conditions not met');
                  }
                } else {
                  print('❌ Time condition not met');
                }
              }
            }
          }
        });
        
        // Select the maximum discount from eligible discounts
        if (eligibleDiscounts.isNotEmpty) {
          print('\n🏆 Selecting maximum discount from ${eligibleDiscounts.length} eligible discount(s):');
          
          // Find the discount with maximum actual amount
          var maxDiscount = eligibleDiscounts.reduce((current, next) => 
            current['actualAmount'] > next['actualAmount'] ? current : next);
          
          specialDiscount = maxDiscount['discountValue'];
          specialType = maxDiscount['discountType'];
          // Percentage is already bounded to <=100% vendor-side (so it can
          // never exceed subtotal), but a flat-amount special discount has
          // no such guarantee if the vendor left "Minimum Order Amount" at
          // 0 — cap it here as a cart-side backstop.
          final double rawSpecialAmount = maxDiscount['actualAmount'];
          specialDiscountAmount =
              rawSpecialAmount > subTotal ? subTotal : rawSpecialAmount;

          print('🎯 Selected: ${maxDiscount['description']} - Final amount: ₹${specialDiscountAmount.toStringAsFixed(2)}');
          
          // Apply the maximum discount to grand total
          grandtotal = grandtotal - specialDiscountAmount;
          
          print('💸 Grand total after discount: ₹${grandtotal.toStringAsFixed(2)}');
        } else {
          print('❌ No eligible discounts found');
          specialDiscount = 0.0;
          specialType = "amount";
          specialDiscountAmount = 0.0;
        }
        
        print('🔚 Special Discount Evaluation Complete\n');
        
      } else {
        specialDiscount = double.parse("0");
        specialType = "amount";
        specialDiscountAmount = 0.0;
      }
    } else {
      // Reset special discount when not enabled
      specialDiscountAmount = 0.0;
    }

    // Conflict resolution: coupon and special discount are allowed to stack
    // freely up to the combined-discount ceiling below, which is the single
    // source of truth for how much of each actually applies — it re-runs on
    // every build and is the exact same coupon-preserved-first algorithm
    // verifyOrder.js uses server-side, so the client never has to guess which
    // discount the server will end up favouring.
    //
    // effectiveDiscountVal / effectiveSpecialDiscountAmount are fields (see
    // their declaration above) — reassigned fresh every build, never `final`.
    effectiveDiscountVal = discountVal;
    effectiveSpecialDiscountAmount = specialDiscountAmount;
    String? _discountConflictWarning;
    // Combined-discount ceiling: coupon + special discount together can't
    // discount more than maxCombinedDiscountPercent% of the order (default 70, admin-configurable
    // via settings/globalSettings — see constants.dart). The coupon is
    // trusted first (it's the user's deliberate choice, and the one
    // independently re-verified server-side in verifyOrderOnCreate) — the
    // special discount is trimmed to whatever room is left, then the coupon
    // itself as a last-resort backstop.
    final double maxCombinedDiscount = subTotal * maxCombinedDiscountPercent / 100;
    if (effectiveDiscountVal + effectiveSpecialDiscountAmount > maxCombinedDiscount) {
      final double cappedDiscountVal = effectiveDiscountVal > maxCombinedDiscount
          ? maxCombinedDiscount
          : effectiveDiscountVal;
      final double remaining =
          (maxCombinedDiscount - cappedDiscountVal).clamp(0.0, double.infinity);
      final double cappedSpecialDiscountAmount =
          effectiveSpecialDiscountAmount > remaining
              ? remaining
              : effectiveSpecialDiscountAmount;
      grandtotal += (effectiveDiscountVal - cappedDiscountVal) +
          (effectiveSpecialDiscountAmount - cappedSpecialDiscountAmount);
      effectiveDiscountVal = cappedDiscountVal;
      effectiveSpecialDiscountAmount = cappedSpecialDiscountAmount;
      _discountConflictWarning =
          'Combined discount is capped at ${maxCombinedDiscountPercent.toStringAsFixed(0)}% of your order total.'
              .tr();
    }
    grandtotal = grandtotal.clamp(0.0, double.infinity);

    // Tax base: net product cost after the discounts that were actually applied.
    // Clamped to 0 so a very large discount never produces negative tax.
    final double taxBase =
        (subTotal - effectiveDiscountVal - effectiveSpecialDiscountAmount)
            .clamp(0.0, double.infinity);

    // Calculate all applicable taxes regardless of visibility
    double totalTaxAmount = 0.0;
    // Track taxes to display in the UI
    List<TaxModel> taxesToDisplay = [];

    if (taxList != null) {
      for (var element in taxList!) {
        // Check if the tax applies to the current order type
        bool shouldApplyTax = (selctedOrderTypeValue == "Delivery" &&
                (element.isTakeaway == false || element.isTakeaway == null)) ||
            (selctedOrderTypeValue == "Dineaway" && element.isTakeaway == true);

        print('Tax check - Tax: ${element.title}, shouldApplyTax: $shouldApplyTax, isTakeaway: ${element.isTakeaway}, orderType: $selctedOrderTypeValue');

        if (shouldApplyTax) {
          double taxAmount = getTaxValue(
              amount: taxBase.toString(),
              taxModel: element);
          totalTaxAmount += taxAmount;

          print('Tax applied - ${element.title}: $taxAmount');

          // Add this tax to the display list
          taxesToDisplay.add(element);
        }
      }
    }

    // Add the total tax amount to grand total
    grandtotal += totalTaxAmount;

    print('Summary: ${taxesToDisplay.length} taxes to display, totalTaxAmount: $totalTaxAmount, orderType: $selctedOrderTypeValue');

    final bool dark = isDarkMode(context);
    final Color labelColor =
        dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600;
    final Color valueColor =
        dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral800;
    final Color dividerColor =
        dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral100;

    final String discountDisplay = percentage != 0.0
        ? percentage != null
            ? "(-${amountShow(amount: per.toDouble().toString())})"
            : "(-${amountShow(amount: '0.0')})"
        : type != null
            ? "(-${amountShow(amount: type.toDouble().toString())})"
            : "(-${amountShow(amount: '0.0')})";

    final double totalSavings = effectiveDiscountVal + effectiveSpecialDiscountAmount;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Discount conflict warning banner ──
          if (_discountConflictWarning != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _discountConflictWarning!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                        fontFamily: AppThemeData.medium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ── Grand Total header (accordion trigger) ──
          InkWell(
            onTap: () => setState(() => _isBillExpanded = !_isBillExpanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grand Total'.tr(),
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: dark
                                ? AppThemeData.darkTextSecondary
                                : AppThemeData.neutral600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isBillExpanded
                                  ? 'Hide bill details'.tr()
                                  : 'View bill details'.tr(),
                              style: AppTypography.caption.copyWith(
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400,
                              ),
                            ),
                            const SizedBox(width: 3),
                            AnimatedRotation(
                              turns: _isBillExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    amountShow(amount: grandtotal.toString()),
                    style: AppTypography.h5.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: -0.5,
                      color: AppThemeData.primary500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Animated breakdown ──
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isBillExpanded
                ? Column(
                    children: [
                      Divider(height: 1, color: dividerColor),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                        child: Column(
                          children: [
                            _billRow('Subtotal'.tr(),
                                amountShow(amount: subTotal.toString()),
                                labelColor, valueColor),
                            if (effectiveDiscountVal > 0)
                              _billRow('Discount'.tr(), discountDisplay,
                                  labelColor, AppThemeData.primary500),
                            if (vendorModel != null &&
                                specialDiscountEnable &&
                                vendorModel!.specialDiscountEnable &&
                                effectiveSpecialDiscountAmount > 0.0)
                              _billRow(
                                  'Special Discount'.tr(),
                                  '(-${amountShow(amount: effectiveSpecialDiscountAmount.toString())})',
                                  labelColor,
                                  AppThemeData.primary500),
                            if (selctedOrderTypeValue == 'Delivery' &&
                                (double.tryParse(deliveryCharges) ?? 0) > 0)
                              _billRow(
                                  'Delivery Charges'.tr(),
                                  amountShow(amount: deliveryCharges.toString()),
                                  labelColor,
                                  valueColor),
                            ...taxesToDisplay.map((taxModel) => _billRow(
                                  taxModel.title.toString(),
                                  amountShow(
                                      amount: getTaxValue(
                                    amount: taxBase.toString(),
                                    taxModel: taxModel,
                                  ).toString()),
                                  labelColor,
                                  valueColor,
                                )),
                            if (tipValue > 0)
                              _billRow('Tip amount'.tr(),
                                  amountShow(amount: tipValue.toString()),
                                  labelColor, const Color(0xFFF59E0B)),
                            const SizedBox(height: 10),
                            Divider(height: 1, color: dividerColor),
                            const SizedBox(height: 10),
                            _billRow(
                                'Grand Total'.tr(),
                                amountShow(amount: grandtotal.toString()),
                                AppThemeData.primary500,
                                AppThemeData.primary500,
                                isBold: true),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          // ── Savings banner (always visible when discount is applied) ──
          // Animated (not static) on purpose — a light "shine" sweeps across
          // it on a loop and it gently breathes, so it keeps drawing the
          // eye to the savings rather than sitting there as flat text.
          if (totalSavings > 0) ...[
            Divider(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SavingsBanner(totalSavings: totalSavings, dark: dark),
            ),
          ],
        ],
      ),
    );
  }

  Widget _billRow(String label, String value, Color labelColor, Color valueColor,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: isBold
                  ? AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    )
                  : AppTypography.bodyMedium.copyWith(color: labelColor),
            ),
          ),
          Text(
            value,
            style: isBold
                ? AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                    fontSize: 17,
                  )
                : AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
          ),
        ],
      ),
    );
  }

  // Modern Dineaway Section
  String? get _serviceRestrictionMessage {
    if (selctedOrderTypeValue == 'Delivery' && !_allowDelivery) {
      final vendorPaused = vendorModel != null && !vendorModel!.vendorDeliveryOpen;
      return vendorPaused
          ? 'Delivery is currently paused by the store. Try Dineaway or check back later.'.tr()
          : 'Delivery order is not available.'.tr();
    }
    if (selctedOrderTypeValue == 'Dineaway') {
      if (!_allowDineaway) {
        final vendorPaused = vendorModel != null && !vendorModel!.vendorDineawayOpen;
        return vendorPaused
            ? 'Dineaway is currently paused by the store. Try Delivery or check back later.'.tr()
            : 'DineAway order is not available.'.tr();
      }
      if (selectedDineawayType == 'Takeaway' && !_allowDineAwayTakeaway) {
        return 'TakeAway order is not available.'.tr();
      }
      if (selectedDineawayType == 'Dining' && !_allowDineIn) {
        return 'Dine-In order is not available.'.tr();
      }
    }
    return null;
  }

  Widget _buildServiceRestrictionBanner(String message) {
    final isDark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? AppThemeData.error500.withValues(alpha: 0.12)
            : AppThemeData.error500.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppThemeData.error500.withValues(alpha: 0.30),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppThemeData.error500.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.block_rounded, color: AppThemeData.error500, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppThemeData.error500,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'One or more items in your cart cannot be ordered with this service type.'.tr(),
                  style: AppTypography.caption.copyWith(
                    color: isDark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernDineawaySection() {
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconBadge(Icons.restaurant_menu_rounded),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Dineaway".tr(),
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDarkMode(context)
                            ? AppThemeData.darkTextPrimary
                            : AppThemeData.neutral900,
                      ),
                    ),
                    Text(
                      "Select order type".tr(),
                      style: AppTypography.bodySmall.copyWith(
                        color: isDarkMode(context)
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _dineawayOption(
                    "Takeaway",
                    "Pack the food for takeout",
                    Icons.shopping_bag_rounded,
                    selectedDineawayType == "Takeaway",
                    enabled: _allowDineAwayTakeaway,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dineawayOption(
                    "Dining",
                    "Eat inside the restaurant",
                    Icons.restaurant_rounded,
                    selectedDineawayType == "Dining",
                    enabled: _allowDineIn,
                  ),
                ),
              ],
            ),
            // Phase 1 real-time seat availability - only asked when this
            // vendor has actually set up seatCapacity (opted in). Restaurants
            // that haven't don't get this prompt at all.
            if (selectedDineawayType == "Dining" &&
                vendorModel?.seatCapacity != null) ...[
              const SizedBox(height: 12),
              _diningGuestCountPicker(context),
            ],
            if (vendorModel?.billPayEnabled == true) ...[
              const SizedBox(height: 12),
              _dineawayOption(
                "Bill Pay",
                "Pay your bill at the restaurant",
                Icons.receipt_long_rounded,
                selectedDineawayType == "Bill Pay",
                enabled: scheduleTime == null,
                disabledSubtitle: "Not available for scheduled orders".tr(),
                disabledDialogTitle: "Bill Pay Unavailable".tr(),
                disabledDialogMessage:
                    "Bill Pay is for immediate in-restaurant payments only. Remove the scheduled time to use Bill Pay.".tr(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Phase 1 real-time seat availability - lets streamCurrentSeatAvailability
  // sum actual party sizes against the vendor's seatCapacity instead of just
  // counting active orders (which would show "not full" even with only 2
  // seats left for a party of 4 asking to be seated). Only rendered when the
  // caller already checked vendorModel?.seatCapacity != null.
  Widget _diningGuestCountPicker(BuildContext context) {
    final isDark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.people_outline,
              size: 18,
              color: isDark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "How many people?".tr(),
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppThemeData.darkTextPrimary
                    : AppThemeData.neutral900,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_diningGuestCount <= 1) return;
                    setState(() => _diningGuestCount--);
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                    child: const Icon(Icons.remove, color: Colors.white, size: 14),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Center(
                    child: Text(
                      '$_diningGuestCount',
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppThemeData.darkTextPrimary
                            : AppThemeData.neutral900,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  // Loose sanity cap, not a real venue limit - the server
                  // never trusts this number for anything beyond the
                  // informational seat-availability display.
                  onTap: () {
                    if (_diningGuestCount >= 30) return;
                    setState(() => _diningGuestCount++);
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dineawayOption(
    String title,
    String subtitle,
    IconData icon,
    bool isSelected, {
    bool enabled = true,
    String? disabledSubtitle,
    String? disabledDialogTitle,
    String? disabledDialogMessage,
  }) {
    final isDark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        if (!enabled) {
          if (disabledDialogTitle != null) {
            _showServiceMismatchDialog(
              disabledDialogTitle,
              disabledDialogMessage ?? '',
            );
          } else {
            final isDineIn = title == 'Dining';
            _showServiceMismatchDialog(
              isDineIn ? 'Dine-In Unavailable'.tr() : 'Takeaway Unavailable'.tr(),
              isDineIn
                  ? 'One or more items in your cart are not available for Dine-In. Please choose Takeaway or remove those items.'.tr()
                  : 'One or more items in your cart are not available for Takeaway. Please choose Dining or remove those items.'.tr(),
            );
          }
          return;
        }
        setState(() {
          selectedDineawayType = title;
          isDineawaySelected = true;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: !enabled
              ? (isDark ? AppThemeData.darkBgPrimary.withValues(alpha: 0.5) : AppThemeData.neutral100)
              : isSelected
                  ? AppThemeData.primary500.withValues(alpha: 0.10)
                  : (isDark ? AppThemeData.darkBgPrimary : AppThemeData.neutral50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !enabled
                ? (isDark ? AppThemeData.darkBorderSecondary.withValues(alpha: 0.4) : AppThemeData.neutral200.withValues(alpha: 0.6))
                : isSelected
                    ? AppThemeData.primary500
                    : (isDark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
            width: isSelected && enabled ? 2 : 1,
          ),
          boxShadow: !enabled || isDark
              ? null
              : isSelected
                  ? [
                      BoxShadow(
                        color: AppThemeData.primary500.withValues(alpha: 0.20),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: !enabled
                      ? (isDark ? AppThemeData.neutral600 : AppThemeData.neutral300)
                      : isSelected
                          ? AppThemeData.primary500
                          : (isDark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500),
                  size: 26,
                ),
                if (!enabled) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? AppThemeData.neutral700 : AppThemeData.neutral200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'N/A'.tr(),
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark ? AppThemeData.neutral500 : AppThemeData.neutral400,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title.tr(),
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: !enabled
                    ? (isDark ? AppThemeData.neutral600 : AppThemeData.neutral400)
                    : isSelected
                        ? AppThemeData.primary500
                        : (isDark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              !enabled
                  ? (disabledSubtitle ?? 'Not available for this order'.tr())
                  : subtitle,
              style: AppTypography.bodySmall.copyWith(
                color: !enabled
                    ? (isDark ? AppThemeData.neutral700 : AppThemeData.neutral300)
                    : (isDark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500),
                fontStyle: !enabled ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Premium Tip Section
  Widget _modernTipSection() {
    final dark = isDarkMode(context);
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.volunteer_activism_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Tip Your Delivery Partner".tr(),
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tipValue > 0
                            ? "${"Tip added".tr()} · ${"Thank you".tr()}! 🙏"
                            : "100% goes to your delivery partner".tr(),
                        style: AppTypography.bodySmall.copyWith(
                          color: tipValue > 0
                              ? AppThemeData.success500
                              : (dark
                                  ? AppThemeData.darkTextSecondary
                                  : AppThemeData.neutral500),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tipValue > 0)
                  GestureDetector(
                    onTap: () => setState(() {
                      tipValue = 0;
                      isTipSelected = false;
                      isTipSelected1 = false;
                      isTipSelected2 = false;
                      isTipSelected3 = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppThemeData.error500.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Clear".tr(),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppThemeData.semiBold,
                          color: AppThemeData.error500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _tipCard(10, isTipSelected)),
                const SizedBox(width: 8),
                Expanded(child: _tipCard(20, isTipSelected1)),
                const SizedBox(width: 8),
                Expanded(
                    child: _tipCard(30, isTipSelected2, label: "Popular")),
                const SizedBox(width: 8),
                Expanded(child: _tipCardCustom()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Single consistent icon for every preset tip amount — a heart communicates
  // "tip" on its own, unlike the old per-card food icons that had no relation
  // to the amount and made the row feel arbitrary.
  static const IconData _tipIcon = Icons.favorite_rounded;

  Widget _tipCard(int value, bool selected, {String? label}) {
    final dark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          tipValue = selected ? 0 : value.toDouble();
          isTipSelected = value == 10 ? !isTipSelected : false;
          isTipSelected1 = value == 20 ? !isTipSelected1 : false;
          isTipSelected2 = value == 30 ? !isTipSelected2 : false;
          isTipSelected3 = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppThemeData.primary500.withValues(alpha: 0.08)
              : (dark ? AppThemeData.darkBgPrimary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppThemeData.primary500
                : (dark
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppThemeData.primary500.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppThemeData.primary500.withValues(alpha: 0.15)
                        : (dark
                            ? AppThemeData.darkBorderPrimary
                            : AppThemeData.neutral100),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_tipIcon,
                      color: selected
                          ? AppThemeData.primary500
                          : (dark
                              ? AppThemeData.darkTextSecondary
                              : AppThemeData.neutral500),
                      size: 18),
                ),
                if (selected)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppThemeData.primary500,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: dark ? AppThemeData.darkBgPrimary : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              amountShow(amount: value.toString()),
              style: TextStyle(
                fontSize: 13.5,
                fontFamily: AppThemeData.bold,
                color: selected
                    ? AppThemeData.primary500
                    : (dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900),
              ),
            ),
            const SizedBox(height: 6),
            label != null
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppThemeData.primary500
                          : AppThemeData.warning500,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontFamily: AppThemeData.semiBold),
                    ),
                  )
                : const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _tipCardCustom() {
    final dark = isDarkMode(context);
    return GestureDetector(
      onTap: () {
        if (isTipSelected3) {
          setState(() {
            isTipSelected3 = false;
            tipValue = 0;
            isTipSelected = false;
            isTipSelected1 = false;
            isTipSelected2 = false;
          });
        } else {
          _showCustomTipSheet(context);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: isTipSelected3
              ? AppThemeData.primary500.withValues(alpha: 0.08)
              : (dark ? AppThemeData.darkBgPrimary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTipSelected3
                ? AppThemeData.primary500
                : (dark
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200),
            width: isTipSelected3 ? 1.5 : 1,
          ),
          boxShadow: isTipSelected3
              ? [
                  BoxShadow(
                      color: AppThemeData.primary500.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isTipSelected3
                        ? AppThemeData.primary500.withValues(alpha: 0.15)
                        : (dark
                            ? AppThemeData.darkBorderPrimary
                            : AppThemeData.neutral100),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: isTipSelected3
                        ? AppThemeData.primary500
                        : (dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral500),
                    size: 18,
                  ),
                ),
                if (isTipSelected3)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppThemeData.primary500,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: dark ? AppThemeData.darkBgPrimary : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isTipSelected3
                  ? amountShow(amount: tipValue.toString())
                  : "Custom".tr(),
              style: TextStyle(
                fontSize: 13.5,
                fontFamily: AppThemeData.bold,
                color: isTipSelected3
                    ? AppThemeData.primary500
                    : (dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900),
              ),
            ),
            const SizedBox(height: 6),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  // Global container: all item cards + Add More Items + Note for Restaurant
  Widget _buildItemsContainer() {
    final dark = isDarkMode(context);
    final dividerColor =
        dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral100;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark
              ? AppThemeData.darkBorderPrimary
              : const Color(0xFFE5E1FF),
          width: 1.0,
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AppThemeData.primary500.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendorModel != null ? vendorModel!.title : "Your Order".tr(),
                        style: AppTypography.h5.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Item rows with hairline dividers
          for (int i = 0; i < cartProducts.length; i++) ...[
            _modernCartItem(cartProducts[i], lstExtras),
            if (i != cartProducts.length - 1)
              Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
          ],

          // ── Add More Items (not offered for a locked Bill Pay cart) ──
          if (!_isBillPayMode) ...[
            Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
            InkWell(
              onTap: () {
                if (vendorModel != null) {
                  BehaviorTracker.setNextEntrySource('Cart');
                  precacheVendorHeroImage(context, vendorModel!);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        NewVendorProductsScreen(vendorModel: vendorModel!),
                  ));
                } else {
                  // Vendor data not yet ready — re-trigger the load pipeline
                  // and show the skeleton until it completes.
                  setState(() {
                    _isCartInitialized = false;
                    isDeliverFound = false;
                  });
                  getDeliveyData();
                }
              },
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppThemeData.primary500.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add,
                          color: AppThemeData.primary500, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Add More Items".tr(),
                      style: AppTypography.labelMedium.copyWith(
                        color: AppThemeData.primary500,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppThemeData.primary500,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Divider(height: 1, indent: 16, endIndent: 16, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      color: AppThemeData.neutral400, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Bill sent by the vendor — items can't be changed".tr(),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppThemeData.neutral400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Note for Restaurant ──
          Divider(height: 1, color: dividerColor),
          _noteForRestaurantFlat(dark),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // Flat "Note for Restaurant" section (lives inside the global container)
  Widget _noteForRestaurantFlat(bool dark) {
    final hasNote = noteController.text.isNotEmpty;
    return InkWell(
      onTap: () => showModalBottomSheet(
        isScrollControlled: true,
        isDismissible: true,
        context: context,
        backgroundColor: Colors.transparent,
        enableDrag: true,
        builder: (sheetCtx) => Notesheet(sheetCtx),
      ),
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(20),
        bottomRight: Radius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF2A2218)
                    : const Color(0xFFFFF8EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.edit_note_rounded,
                    color: Color(0xFFE89B2F), size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Order Note".tr(),
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (hasNote)
                    Text(
                      noteController.text,
                      style: AppTypography.bodySmall.copyWith(
                        color: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      "Add special instructions for the restaurant".tr(),
                      style: AppTypography.bodySmall.copyWith(
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral400,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                hasNote ? "Edit".tr() : "Add".tr(),
                style: AppTypography.labelSmall.copyWith(
                  color: AppThemeData.primary500,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Zomato/Swiggy-style veg · non-veg indicator
  Widget _foodTypeBadge(ProductModel? product) {
    const double size = 20;
    const double dotSize = 9;

    // Determine type
    final bool isVeg = product?.veg == true;
    final bool isNonVeg = product?.nonveg == true;

    final Color borderColor = isVeg
        ? const Color(0xFF2E7D32) // deep green
        : isNonVeg
            ? const Color(0xFF8B3A2A) // warm brown / maroon
            : AppThemeData.neutral300; // unknown – neutral grey

    final Color dotColor = isVeg
        ? const Color(0xFF2E7D32)
        : isNonVeg
            ? const Color(0xFF8B3A2A)
            : AppThemeData.neutral400;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1.8),
        color: isDarkMode(context)
            ? borderColor.withValues(alpha: 0.08)
            : borderColor.withValues(alpha: 0.05),
      ),
      child: Center(
        child: Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _modernCartItem(CartProduct cartProduct, List<AddAddonsDemo> addons) {
    List addOnVal = [];
    var quen = cartProduct.quantity;
    double priceTotalValue = 0.0;
    double AddOnVal = 0;
    for (int i = 0; i < lstExtras.length; i++) {
      AddAddonsDemo addAddonsDemo = lstExtras[i];
      if (addAddonsDemo.categoryID == cartProduct.id) {
        AddOnVal = AddOnVal + double.parse(addAddonsDemo.price!);
      }
    }

    // Performance optimization: Use cache to avoid N+1 queries
    ProductModel? productModel;
    final productId = cartProduct.id.split('~').first;
    if (_productCache.containsKey(productId)) {
      productModel = _productCache[productId];
    } else {
      // Only fetch if not in cache
      FireStoreUtils()
          .getProductByID(productId)
          .then((value) {
        if (value != null && mounted) {
          setState(() {
            _productCache[productId] = value;
          });
        }
      });
    }

    VariantInfo? variantInfo;
    if (cartProduct.variant_info != null) {
      try {
        final decoded = jsonDecode(cartProduct.variant_info.toString());
        if (decoded is Map<String, dynamic>) {
          variantInfo = VariantInfo.fromJson(decoded);
        }
      } catch (_) {}
    }
    if (cartProduct.extras == null) {
      addOnVal.clear();
    } else {
      if (cartProduct.extras is String) {
        if (cartProduct.extras == '[]') {
          addOnVal.clear();
        } else {
          String extraDecode = cartProduct.extras
              .toString()
              .replaceAll("[", "")
              .replaceAll("]", "")
              .replaceAll("\\", "");

          if (extraDecode.contains(",")) {
            addOnVal = extraDecode.split(",");
          } else {
            if (extraDecode.trim().isNotEmpty) {
              addOnVal = [extraDecode];
            }
          }
        }
      }

      if (cartProduct.extras is List) {
        addOnVal = List.from(cartProduct.extras);
      }
    }

    if (cartProduct.extras_price != null &&
        cartProduct.extras_price != "" &&
        double.parse(cartProduct.extras_price!) != 0.0) {
      priceTotalValue +=
          double.parse(cartProduct.extras_price!) * cartProduct.quantity;
    }
    priceTotalValue += double.parse(cartProduct.price) * cartProduct.quantity;

    final dark = isDarkMode(context);
    final hasVariants = variantInfo != null &&
        variantInfo.variant_options != null &&
        variantInfo.variant_options!.isNotEmpty;
    final hasAddons = addOnVal.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: veg badge + name + variants + add-ons ──
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _foodTypeBadge(productModel),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product name
                  Text(
                    cartProduct.name,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral900,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Customization chips — variants + add-ons in one row
                  if (hasVariants || hasAddons) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (hasVariants)
                          ...variantInfo!.variant_options!.entries.map(
                            (e) => _buildChip(
                              e.value.toString(),
                              e.key.hashCode,
                              isDark: dark,
                              isVariant: true,
                            ),
                          ),
                        if (hasAddons)
                          ...addOnVal
                              .map((e) => e.toString().replaceAll('"', '').trim())
                              .where((e) => e.isNotEmpty)
                              .map((e) => _buildChip(e, e.hashCode, isDark: dark)),
                      ],
                    ),
                  ],
                  // ── Edit button (minimal whisper) — hidden for a locked Bill Pay item ──
                  const SizedBox(height: 9),
                  if (_isBillPayMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 12,
                            color: dark
                                ? AppThemeData.darkBorderPrimary
                                : AppThemeData.neutral300),
                        const SizedBox(width: 4),
                        Text(
                          "Fixed by vendor".tr(),
                          style: AppTypography.caption.copyWith(
                            color: dark
                                ? AppThemeData.darkBorderPrimary
                                : AppThemeData.neutral400,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    )
                  else
                  GestureDetector(
                    onTap: () async {
                      final pid = cartProduct.id.split('~').first;
                      ProductModel? pm = _productCache[pid];
                      if (pm == null) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const Center(
                              child: CircularProgressIndicator.adaptive()),
                        );
                        pm = await FireStoreUtils().getProductByID(pid);
                        if (mounted) Navigator.of(context).pop();
                      }
                      if (pm == null || !mounted) return;

                      // Restore previously chosen variant so the dialog
                      // opens with the right option already highlighted.
                      VariantInfo? vi;
                      try {
                        final raw = cartProduct.variant_info;
                        if (raw is VariantInfo) {
                          vi = raw;
                        } else if (raw is Map<String, dynamic>) {
                          vi = VariantInfo.fromJson(raw);
                        } else if (raw is String && raw.isNotEmpty && raw != 'null') {
                          vi = VariantInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
                        }
                      } catch (_) {}

                      // Restore previously selected add-ons so quantities
                      // match what the user had in the cart.
                      final String? prevExtras = cartProduct.extras
                          ?.toString()
                          .replaceAll('"', '')
                          .replaceAll('[', '')
                          .replaceAll(']', '')
                          .replaceAll('\\', '');

                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        useSafeArea: true,
                        builder: (BuildContext ctx) {
                          return ProductOptionsDialog(
                            productModel: pm!,
                            initialVariantInfo: vi,
                            initialExtras: prevExtras,
                            onAddToCart: (ProductModel updatedProduct, double totalPrice, int quantity) async {
                              Navigator.of(ctx).pop();
                              await cartDatabase.removeProduct(cartProduct.id);
                              await cartDatabase.addProduct(updatedProduct, cartDatabase, true);
                            },
                          );
                        },
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.neutral300,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Edit item".tr(),
                          style: AppTypography.caption.copyWith(
                            color: dark
                                ? AppThemeData.darkBorderPrimary
                                : AppThemeData.neutral400,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Validation issue banner ──
                  if (_itemIssues.containsKey(cartProduct.id)) ...[
                    const SizedBox(height: 8),
                    _buildItemIssueBanner(
                      message: _itemIssues[cartProduct.id]!,
                      isBlocking: _itemBlocking[cartProduct.id] ?? false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Right: qty stepper (top) + price (bottom) ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Qty — locked read-only chip for a Bill Pay item, editable
                // Swiggy-style stepper pill otherwise.
                if (_isBillPayMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'x${cartProduct.quantity}',
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppThemeData.primary500,
                      ),
                    ),
                  )
                else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppThemeData.primary500, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Minus button
                      GestureDetector(
                        onTap: () {
                          if (quen <= 1) {
                            cartDatabase.removeProduct(cartProduct.id);
                            BehaviorTracker.track(kEvtProductRemovedFromCart, {
                              'productId': cartProduct.id,
                              'vendorId': cartProduct.vendorID,
                              'categoryId': cartProduct.category_id,
                            });
                          } else {
                            quen--;
                            removetocard(cartProduct, quen);
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              bottomLeft: Radius.circular(6),
                            ),
                          ),
                          child: const Icon(Icons.remove,
                              color: Colors.white, size: 14),
                        ),
                      ),
                      // Count
                      SizedBox(
                        width: 30,
                        child: Center(
                          child: Text(
                            '${cartProduct.quantity}',
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral900,
                            ),
                          ),
                        ),
                      ),
                      // Plus button
                      GestureDetector(
                        onTap: () async {
                          if (productModel == null) return;

                          int computeMaxQty(ProductModel pm) {
                            if (pm.itemAttributes != null) {
                              final variantList =
                                  pm.itemAttributes!.variants!;
                              Variants? matchingVariant;
                              try {
                                matchingVariant = variantList.firstWhere(
                                  (v) =>
                                      v.variant_sku ==
                                      variantInfo?.variant_sku,
                                );
                              } catch (_) {
                                matchingVariant = null;
                              }
                              return matchingVariant != null
                                  ? int.parse(matchingVariant
                                      .variant_quantity
                                      .toString())
                                  : pm.quantity;
                            }
                            return pm.quantity;
                          }

                          var maxQty = computeMaxQty(productModel!);

                          // Soft stock re-verification (2026-08-05):
                          // productModel is cached from the last full cart
                          // validation (_validateCart), not live - it can
                          // be stale if the vendor's stock changed since.
                          // Abundant stock (>=10) is never worth an extra
                          // read to double-check before a single +1; scarce
                          // stock (<10, where two customers racing for the
                          // last few units is a real scenario) gets one
                          // fresh check first, so the cap can't be stale
                          // exactly when staleness would actually matter.
                          // Client-side only - the definitive stock check
                          // still happens wherever order verification
                          // already re-checks the catalog server-side.
                          if (maxQty != -1 && maxQty < 10) {
                            if (_stockCheckInFlight.contains(productId)) {
                              return; // a check for this line is already running
                            }
                            _stockCheckInFlight.add(productId);
                            try {
                              final fresh =
                                  await _fireStoreUtils.getProductByID(productId);
                              if (mounted) {
                                setState(() => _productCache[productId] = fresh);
                              }
                              maxQty = computeMaxQty(fresh);
                            } catch (_) {
                              // Fetch failed - proceed with the cached
                              // number rather than blocking the tap.
                            } finally {
                              _stockCheckInFlight.remove(productId);
                            }
                          }

                          if (maxQty > quen || maxQty == -1) {
                            quen++;
                            addtocard(cartProduct, quen);
                          } else {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                              SnackBar(
                                  content: Text(
                                      "Product is out of Stock".tr())),
                            );
                          }
                        },
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500,
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(6),
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                // Price — directly below qty
                const SizedBox(height: 8),
                Text(
                  amountShow(amount: priceTotalValue.toString()),
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.1,
                    color: AppThemeData.primary500,
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = _serverAdjustedNow;
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  Widget _buildIssuesSummaryCard() {
    final dark = isDarkMode(context);
    final bool hasGlobal = _cartGlobalWarning != null;
    final blockingItems = _itemIssues.entries
        .where((e) => _itemBlocking[e.key] == true)
        .toList();
    final infoItems = _itemIssues.entries
        .where((e) => _itemBlocking[e.key] != true)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: dark
            ? AppThemeData.error500.withValues(alpha: 0.12)
            : AppThemeData.error500.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppThemeData.error500.withValues(alpha: 0.30),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppThemeData.error500, size: 18),
              const SizedBox(width: 8),
              Text(
                "Cart Issues".tr(),
                style: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppThemeData.error500,
                ),
              ),
              const Spacer(),
              Text(
                "${_itemIssues.length + (hasGlobal ? 1 : 0)} ${'issue(s) found'.tr()}",
                style: AppTypography.caption.copyWith(
                  color: AppThemeData.error500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          if (hasGlobal) ...[
            const SizedBox(height: 10),
            _issueLine(
              icon: Icons.storefront_outlined,
              message: _cartGlobalWarning!,
              blocking: true,
              dark: dark,
            ),
          ],

          if (blockingItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...blockingItems.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _issueLine(
                    icon: Icons.remove_circle_outline_rounded,
                    message: e.value,
                    blocking: true,
                    dark: dark,
                  ),
                )),
          ],

          if (infoItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...infoItems.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _issueLine(
                    icon: Icons.info_outline_rounded,
                    message: e.value,
                    blocking: false,
                    dark: dark,
                  ),
                )),
          ],

        ],
      ),
    );
  }

  Widget _issueLine({
    required IconData icon,
    required String message,
    required bool blocking,
    required bool dark,
  }) {
    final color =
        blocking ? AppThemeData.error500 : const Color(0xFFF59E0B);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTypography.caption.copyWith(
              color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral700,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidatingBanner() {
    final dark = isDarkMode(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: dark
            ? AppThemeData.primary500.withValues(alpha: 0.15)
            : AppThemeData.primary500.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppThemeData.primary500.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            "Checking item availability...".tr(),
            style: AppTypography.labelSmall.copyWith(
              color: AppThemeData.primary500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemIssueBanner(
      {required String message, required bool isBlocking}) {
    final dark = isDarkMode(context);
    final color =
        isBlocking ? AppThemeData.error500 : const Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: dark
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(
            isBlocking
                ? Icons.remove_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> addtocard(CartProduct cartProduct, int qun) async {
    try {
      await cartDatabase.updateProduct(CartProduct(
        id: cartProduct.id,
        category_id: cartProduct.category_id,
        name: cartProduct.name,
        photo: cartProduct.photo,
        price: cartProduct.price,
        vendorID: cartProduct.vendorID,
        quantity: qun,
        // nullable fields omitted → Moor's nullToAbsent keeps DB values intact
      ));
      BehaviorTracker.track(kEvtProductQuantityChanged, {
        'productId': cartProduct.id,
        'vendorId': cartProduct.vendorID,
        'categoryId': cartProduct.category_id,
        'direction': 'inc',
        'newQuantity': qun,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
          content: Text("Failed to update quantity".tr()),
          backgroundColor: AppThemeData.error500,
        ));
      }
    }
  }

  Future<void> removetocard(CartProduct cartProduct, int qun) async {
    try {
      if (qun >= 1) {
        await cartDatabase.updateProduct(CartProduct(
          id: cartProduct.id,
          category_id: cartProduct.category_id,
          name: cartProduct.name,
          photo: cartProduct.photo,
          price: cartProduct.price,
          vendorID: cartProduct.vendorID,
          quantity: qun,
        ));
        BehaviorTracker.track(kEvtProductQuantityChanged, {
          'productId': cartProduct.id,
          'vendorId': cartProduct.vendorID,
          'categoryId': cartProduct.category_id,
          'direction': 'dec',
          'newQuantity': qun,
        });
      } else {
        await cartDatabase.removeProduct(cartProduct.id);
        BehaviorTracker.track(kEvtProductRemovedFromCart, {
          'productId': cartProduct.id,
          'vendorId': cartProduct.vendorID,
          'categoryId': cartProduct.category_id,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
          content: Text("Failed to update quantity".tr()),
          backgroundColor: AppThemeData.error500,
        ));
      }
    }
  }

  List<Map<String, dynamic>> _getActiveSpecialDiscounts() {
    if (vendorModel == null ||
        !specialDiscountEnable ||
        !vendorModel!.specialDiscountEnable) {
      return [];
    }

    final now = _serverAdjustedNow;
    final currentDay = DateFormat('EEEE', 'en_US').format(now);
    final dateStr = DateFormat('dd-MM-yyyy').format(now);
    final List<Map<String, dynamic>> active = [];

    for (final dayDiscount in vendorModel!.specialDiscount) {
      if (dayDiscount.day != currentDay) continue;
      if (dayDiscount.timeslot == null || dayDiscount.timeslot!.isEmpty) continue;

      for (final slot in dayDiscount.timeslot!) {
        if ((slot.from?.isEmpty ?? true) || (slot.to?.isEmpty ?? true)) continue;

        try {
          final start = DateFormat("dd-MM-yyyy HH:mm")
              .parse('$dateStr ${slot.from}');
          var end = DateFormat("dd-MM-yyyy HH:mm")
              .parse('$dateStr ${slot.to}');
          // Midnight-crossing: if end ≤ start, slot wraps into next day
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          if (!isCurrentDateInRange(start, end)) continue;
        } catch (_) {
          continue;
        }

        if (slot.orderType != null && slot.orderType!.isNotEmpty) {
          final currentOrderType =
              selctedOrderTypeValue == "Delivery" ? "Delivery" : "Takeaway";
          if (slot.orderType != currentOrderType) continue;
        }

        final discountValue = double.tryParse(slot.discount ?? '0') ?? 0;
        final isPercentage = slot.type == "percentage";
        final applicableAmount =
            double.tryParse(slot.applicableAmount ?? '0') ?? 0;
        // Must match the eligibility check in the actual-total calculation
        // above (subtotalCondition) - this is what decides whether the card
        // is shown as applied/"Best Offer" or as a locked "add more to
        // unlock" card below, and it has to agree with what's really
        // charged so the UI never shows an offer as applied that the cart
        // doesn't actually qualify for.
        final isApplicable = applicableAmount <= 0 || subTotal >= applicableAmount;
        final actualAmount =
            isPercentage ? (subTotal * discountValue / 100) : discountValue;

        String validTill = slot.to ?? '';
        try {
          final parsedTime = DateFormat("HH:mm").parse(validTill);
          validTill = DateFormat("hh:mm a").format(parsedTime);
        } catch (_) {}

        active.add({
          'discountValue': discountValue,
          'isPercentage': isPercentage,
          'applicableAmount': applicableAmount,
          'actualAmount': actualAmount,
          'validTill': validTill,
          'isApplicable': isApplicable,
        });
      }
    }

    // Eligible offers first (highest actual value first, matching which one
    // really gets applied to the total); locked/not-yet-applicable offers
    // after, closest-to-unlock first - same ordering convention as the
    // coupon list's applicable/otherCoupons split above.
    final eligible = active.where((d) => d['isApplicable'] as bool).toList()
      ..sort((a, b) =>
          (b['actualAmount'] as double).compareTo(a['actualAmount'] as double));
    final locked = active.where((d) => !(d['isApplicable'] as bool)).toList()
      ..sort((a, b) => (a['applicableAmount'] as double)
          .compareTo(b['applicableAmount'] as double));
    return [...eligible, ...locked];
  }

  sheet(BuildContext sheetCtx) {
    final dark = isDarkMode(context);
    final keyboardH = MediaQuery.of(sheetCtx).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
      child: FutureBuilder<List<OfferModel>>(
        future: coupon,
        initialData: const [],
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }

          if (snapshot.hasError) {
            return SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'Could not load coupons. Please try again.'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppThemeData.error500),
                ),
              ),
            );
          }

          if (vendorID.isEmpty && cartProducts.isNotEmpty) {
            vendorID = cartProducts.first.vendorID;
          }

          // All coupons for this vendor — used for manual code entry (includes private).
          final allCoupons = (snapshot.data ?? [])
              .where((c) =>
                  vendorID == c.storeId ||
                  c.storeId == null ||
                  (c.storeId?.isEmpty ?? true))
              .toList();

          // Only publicly listed coupons are shown in the UI.
          // Private coupons (isPublic == false) are redeemable via manual code only.
          // Null isPublic means legacy data — show it for backward compatibility.
          final publicCoupons =
              allCoupons.where((c) => c.isPublic != false).toList();

          final applicableCoupons = publicCoupons.where((c) {
            final minAmt = double.tryParse(c.applicableAmount ?? '0') ?? 0;
            return subTotal >= minAmt;
          }).toList();

          final otherCoupons = publicCoupons.where((c) {
            final minAmt = double.tryParse(c.applicableAmount ?? '0') ?? 0;
            return subTotal < minAmt;
          }).toList();

          final activeSpecialDiscounts = _getActiveSpecialDiscounts();
          final hasAppliedSpecialDiscount = activeSpecialDiscounts.isNotEmpty &&
              (activeSpecialDiscounts.first['isApplicable'] as bool);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dark
                          ? AppThemeData.darkBorderPrimary
                          : AppThemeData.neutral300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Coupons".tr(),
                            style: AppTypography.h5.copyWith(
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? AppThemeData.darkTextPrimary
                                  : AppThemeData.neutral900,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: dark
                                    ? AppThemeData.darkBgTertiary
                                    : AppThemeData.neutral100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: dark
                                    ? AppThemeData.darkTextSecondary
                                    : AppThemeData.neutral600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Manual entry ──
                      Text(
                        "Enter Coupon Code".tr(),
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: txt,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 30,
                              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                              style: AppTypography.labelMedium.copyWith(
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral900,
                                letterSpacing: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText: "e.g. GET30",
                                hintStyle: AppTypography.labelMedium.copyWith(
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral400,
                                  letterSpacing: 0,
                                ),
                                filled: true,
                                fillColor: dark
                                    ? AppThemeData.darkBgTertiary
                                    : AppThemeData.neutral50,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: dark
                                        ? AppThemeData.darkBorderSecondary
                                        : AppThemeData.neutral200,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppThemeData.primary500,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppThemeData.primary500,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                            onPressed: () => _applyManualCoupon(
                                snapshot.data ?? [], ctx),
                            child: Text(
                              "Apply".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      Container(
                          height: 1,
                          color: dark
                              ? AppThemeData.darkBorderSecondary
                              : AppThemeData.neutral100),
                      const SizedBox(height: 20),

                      // ── Applicable coupons ──
                      if (applicableCoupons.isNotEmpty) ...[
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppThemeData.success400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Applicable Coupons".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...applicableCoupons.map(
                          (c) => _couponCard(c,
                              applicable: true, sheetCtx: ctx),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Other coupons ──
                      if (otherCoupons.isNotEmpty) ...[
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: dark
                                    ? AppThemeData.darkBorderPrimary
                                    : AppThemeData.neutral300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Other Available Coupons".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextSecondary
                                    : AppThemeData.neutral500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...otherCoupons.map(
                          (c) => _couponCard(c,
                              applicable: false, sheetCtx: ctx),
                        ),
                      ],

                      // ── Special Discounts ──
                      if (activeSpecialDiscounts.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                            height: 1,
                            color: dark
                                ? AppThemeData.darkBorderSecondary
                                : AppThemeData.neutral100),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppThemeData.warning400,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Special Discounts".tr(),
                              style: AppTypography.labelMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (hasAppliedSpecialDiscount)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppThemeData.success400
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppThemeData.success400
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: AppThemeData.success400,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  "Automatically Added Best Offer".tr(),
                                  style: AppTypography.caption.copyWith(
                                    color: AppThemeData.success400,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...activeSpecialDiscounts.asMap().entries.map(
                              (e) => _specialDiscountCard(
                                e.value,
                                isBest: e.key == 0 &&
                                    (e.value['isApplicable'] as bool),
                              ),
                            ),
                      ],

                      // Empty state
                      if (allCoupons.isEmpty && activeSpecialDiscounts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.local_offer_outlined,
                                  size: 48,
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "No coupons available".tr(),
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: dark
                                        ? AppThemeData.darkTextSecondary
                                        : AppThemeData.neutral500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  }

  Widget _couponCard(OfferModel offer,
      {required bool applicable, required BuildContext sheetCtx}) {
    final dark = isDarkMode(context);
    final isApplied = couponId == offer.offerId;
    final isPercentage = offer.discountTypeOffer == 'Percentage' ||
        offer.discountTypeOffer == 'Percent';
    final discountLabel = isPercentage
        ? "${offer.discountOffer}% OFF"
        : "${amountShow(amount: offer.discountOffer ?? '0')} OFF";
    final minAmt = double.tryParse(offer.applicableAmount ?? '0') ?? 0;
    final hasMinAmt = minAmt > 0;

    // Locked (not-yet-applicable) cards get a soft red glow under the
    // bottom edge, matching the reference design's "still out of reach"
    // treatment - only when there's actually an unlock hint to draw
    // attention to, not on every non-applicable card indiscriminately.
    final isLocked = !applicable && hasMinAmt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // Applicable cards get a light purple/lavender tint (primary50) to
        // match the reference design, instead of a plain neutral grey -
        // non-applicable/locked cards keep the neutral grey since they're
        // deliberately de-emphasized either way.
        color: dark
            ? AppThemeData.darkBgTertiary
            : (applicable ? AppThemeData.primary50 : AppThemeData.neutral50),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isApplied
              ? AppThemeData.success400
              : (applicable
                  ? AppThemeData.primary200
                  : (dark
                      ? AppThemeData.darkBorderSecondary
                      : AppThemeData.neutral200)),
          width: isApplied ? 1.5 : 1,
        ),
        boxShadow: isLocked
            ? [
                BoxShadow(
                  color: AppThemeData.danger300.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: applicable
                          ? AppThemeData.primary500.withValues(alpha: 0.10)
                          : (dark
                              ? AppThemeData.darkBgSecondary
                              : AppThemeData.neutral100),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: applicable
                            ? AppThemeData.primary200
                            : (dark
                                ? AppThemeData.darkBorderSecondary
                                : AppThemeData.neutral300),
                      ),
                    ),
                    child: Text(
                      offer.offerCode ?? '',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: applicable
                            ? AppThemeData.primary500
                            : (dark
                                ? AppThemeData.darkTextTertiary
                                : AppThemeData.neutral500),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Discount description
                  Text(
                    hasMinAmt
                        ? "Get $discountLabel on orders above ${amountShow(amount: offer.applicableAmount!)}"
                        : "Get $discountLabel on your order",
                    style: AppTypography.bodySmall.copyWith(
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Unlock hint for non-applicable coupons — danger300 (not
                  // warning400) to match the reference design's vivid red
                  // treatment for "still locked", and bold per the
                  // reference rather than regular weight.
                  if (isLocked) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 12, color: AppThemeData.danger300),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Add ${amountShow(amount: (minAmt - subTotal).toStringAsFixed(2))} more to unlock",
                            style: AppTypography.caption.copyWith(
                              color: AppThemeData.danger300,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (applicable) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _applyListCoupon(offer, sheetCtx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isApplied
                        ? AppThemeData.success400
                        : AppThemeData.primary500,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isApplied ? "Applied".tr() : "Apply".tr(),
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _specialDiscountCard(Map<String, dynamic> discount,
      {required bool isBest}) {
    final dark = isDarkMode(context);
    final isPercentage = discount['isPercentage'] as bool;
    final discountValue = discount['discountValue'] as double;
    final applicableAmount = discount['applicableAmount'] as double;
    final validTill = discount['validTill'] as String;
    final isApplicable = discount['isApplicable'] as bool;
    // Same "still out of reach" treatment as the coupon list's locked
    // cards (_couponCard's isLocked) - a soft red glow plus a red
    // "Add ₹X more to unlock" hint, only for offers whose minimum order
    // value the current cart doesn't meet.
    final isLocked = !isApplicable && applicableAmount > 0;

    final discountLabel = isPercentage
        ? "Get ${discountValue.toStringAsFixed(0)}% OFF"
        : "Flat ${amountShow(amount: discountValue.toStringAsFixed(2))} OFF";

    // Only the best (isBest) discount is the one actually auto-applied to
    // the total (see _getActiveSpecialDiscounts' caller) - every other
    // entry here is shown for transparency only, so it's styled grey/muted
    // rather than sharing the applied card's orange treatment, matching
    // the "unapplied = neutral, applied = colored" convention already used
    // for coupon cards (_couponCard's applicable/non-applicable styling).
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark
            ? AppThemeData.darkBgTertiary
            : (isBest ? AppThemeData.warning50 : AppThemeData.neutral50),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBest
              ? AppThemeData.warning300
              : (dark
                  ? AppThemeData.darkBorderPrimary
                  : AppThemeData.neutral200),
          width: isBest ? 1.5 : 1,
        ),
        boxShadow: isLocked
            ? [
                BoxShadow(
                  color: AppThemeData.danger300.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isBest
                    ? AppThemeData.warning400.withValues(alpha: 0.15)
                    : (dark
                        ? AppThemeData.darkBorderPrimary
                        : AppThemeData.neutral200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                // Emoji glyphs render in their own fixed color regardless of
                // TextStyle.color, so the flame itself can't be desaturated
                // for the unapplied state - the grey chip background above
                // and the grey card/border are what actually signal
                // "unapplied" here.
                child: Text(
                  isBest ? "🏆" : "🔥",
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBest) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: AppThemeData.warning400.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "Best Offer",
                        style: AppTypography.caption.copyWith(
                          color: AppThemeData.warning400,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    discountLabel,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: dark
                          ? AppThemeData.darkTextPrimary
                          : AppThemeData.neutral900,
                    ),
                  ),
                  if (applicableAmount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      "On orders above ${amountShow(amount: applicableAmount.toStringAsFixed(2))}",
                      style: AppTypography.caption.copyWith(
                        color: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                      ),
                    ),
                  ],
                  if (isLocked) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 12, color: AppThemeData.danger300),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Add ${amountShow(amount: (applicableAmount - subTotal).toStringAsFixed(2))} more to unlock",
                            style: AppTypography.caption.copyWith(
                              color: AppThemeData.danger300,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: dark
                            ? AppThemeData.darkTextTertiary
                            : AppThemeData.neutral500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Valid till $validTill",
                        style: AppTypography.caption.copyWith(
                          color: dark
                              ? AppThemeData.darkTextTertiary
                              : AppThemeData.neutral500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Only the auto-picked best discount is actually applied to the
            // total (see the max-discount selection above _getActiveSpecialDiscounts
            // is called from) - every other entry here is shown for
            // transparency only and isn't independently selectable, so it
            // gets no badge at all rather than a misleading "Apply" button.
            if (isBest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppThemeData.warning400.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 14, color: AppThemeData.warning400),
                    const SizedBox(width: 4),
                    Text(
                      "Applied".tr(),
                      style: AppTypography.caption.copyWith(
                        color: AppThemeData.warning400,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _applyListCoupon(OfferModel offer, BuildContext sheetCtx) async {
    if (couponId.isNotEmpty && couponId != offer.offerId) {
      final confirmed = await AppDialog.showConfirm(
        context,
        title: 'Replace Coupon?'.tr(),
        message: 'Only one coupon can be used at a time. Replace the current coupon?'.tr(),
        confirmLabel: 'Replace'.tr(),
        cancelLabel: 'Cancel'.tr(),
      );
      if (confirmed) {
        _doApplyCoupon(offer, sheetCtx);
      }
    } else {
      _doApplyCoupon(offer, sheetCtx);
    }
  }

  void _applyManualCoupon(List<OfferModel> coupons, BuildContext sheetCtx) async {
    if (txt.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
        content: Text("Please enter a coupon code".tr()),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    if (vendorID.isEmpty && cartProducts.isNotEmpty) {
      vendorID = cartProducts.first.vendorID;
    }

    OfferModel? found;
    for (final c in coupons) {
      if (vendorID == c.storeId ||
          c.storeId == null ||
          (c.storeId?.isEmpty ?? true)) {
        if (txt.text.trim().toUpperCase() ==
            (c.offerCode ?? '').toUpperCase()) {
          found = c;
          break;
        }
      }
    }

    if (found == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
        content: Text(
            "Invalid coupon code or not applicable for this store".tr()),
        backgroundColor: AppThemeData.error500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      txt.clear();
      return;
    }

    final minAmt = double.tryParse(found.applicableAmount ?? '0') ?? 0;
    if (subTotal < minAmt) {
      Navigator.pop(sheetCtx);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
        content: Text(
            "Add ${amountShow(amount: (minAmt - subTotal).toStringAsFixed(2))} more to use this coupon.".tr()),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    if (couponId.isNotEmpty && couponId != found.offerId) {
      final confirmed = await AppDialog.showConfirm(
        context,
        title: 'Replace Coupon?'.tr(),
        message: 'Only one coupon can be used at a time. Replace the current coupon?'.tr(),
        confirmLabel: 'Replace'.tr(),
        cancelLabel: 'Cancel'.tr(),
      );
      if (confirmed) {
        _doApplyCoupon(found, sheetCtx);
      }
    } else {
      _doApplyCoupon(found, sheetCtx);
    }
  }

  void _doApplyCoupon(OfferModel offer, BuildContext sheetCtx) {
    final isPercentage = offer.discountTypeOffer == 'Percentage' ||
        offer.discountTypeOffer == 'Percent';
    final raw = double.tryParse(offer.discountOffer ?? '0') ?? 0;
    final couponMinAmount = double.tryParse(offer.applicableAmount ?? '0') ?? 0;
    // Percentage is already bounded to <=100% by the vendor app (so it can
    // never exceed subtotal), but a flat-amount coupon has no such guarantee
    // if the vendor left "Minimum Order Amount" at 0 — cap it here as a
    // cart-side backstop so a coupon can never discount more than the cart
    // is actually worth.
    final couponEffective =
        isPercentage ? subTotal * raw / 100 : (raw > subTotal ? subTotal : raw);

    // Coupon and special discount stack up to the combined-discount ceiling
    // (see build()'s combined-discount-ceiling block) — the coupon is always
    // applied here; the summary section is what actually resolves how much
    // of each survives the ceiling, and reruns on every build.
    if (specialDiscountAmount > 0 &&
        couponEffective > 0 &&
        couponEffective + specialDiscountAmount >
            subTotal * maxCombinedDiscountPercent / 100) {
      Navigator.pop(sheetCtx);
      setState(() {
        if (isPercentage) {
          percentage = raw;
          type = 0.0;
        } else {
          type = couponEffective;
          percentage = 0.0;
        }
        couponId = offer.offerId!;
        txt.text = offer.offerCode ?? '';
        _appliedCouponMinAmount = couponMinAmount;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
        content: Text(
          'Coupon applied. Combined with the special discount, savings are '
          'capped at ${maxCombinedDiscountPercent.toStringAsFixed(0)}% of your order total.'
              .tr(),
        ),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    // No conflict — apply coupon normally.
    setState(() {
      if (isPercentage) {
        percentage = raw;
        type = 0.0;
      } else {
        type = couponEffective;
        percentage = 0.0;
      }
      couponId = offer.offerId!;
      txt.text = offer.offerCode ?? '';
      _appliedCouponMinAmount = couponMinAmount;
    });
    Navigator.pop(sheetCtx);
    _showCouponAppliedBanner(code: offer.offerCode ?? '', savedAmount: couponEffective);
  }

  // Coupon-applied confirmation modal — a green percent badge with a
  // continuously-bursting confetti backdrop behind it, the code + savings
  // copy, a green progress line that runs over 4s, and a "YAY!" button.
  // The dialog auto-dismisses itself when the progress line completes, but
  // X / YAY! / tapping the scrim still dismiss it early.
  void _showCouponAppliedBanner({required String code, required double savedAmount}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogCtx) =>
          _CouponAppliedBanner(code: code, savedAmount: savedAmount),
    );
  }

  Notesheet(BuildContext sheetCtx) {
    final dark = isDarkMode(context);
    return Padding(
      // Lifts the entire sheet above the software keyboard
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar — always visible at top of sheet
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? AppThemeData.darkBorderPrimary
                        : AppThemeData.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Scrollable content — prevents overflow on small devices
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(sheetCtx).padding.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xFF2A2218)
                                : const Color(0xFFFFF8EC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_note_rounded,
                              color: Color(0xFFE89B2F), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Order Note".tr(),
                              style: AppTypography.h6.copyWith(
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextPrimary
                                    : AppThemeData.neutral900,
                              ),
                            ),
                            Text(
                              "Visible only to the restaurant".tr(),
                              style: AppTypography.caption.copyWith(
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Text field
                    Container(
                      decoration: BoxDecoration(
                        color: dark
                            ? AppThemeData.darkBgPrimary
                            : AppThemeData.neutral50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: dark
                              ? AppThemeData.darkBorderSecondary
                              : AppThemeData.neutral200,
                        ),
                      ),
                      child: TextField(
                        controller: noteController,
                        maxLines: 4,
                        maxLength: 200,
                        style: AppTypography.bodyMedium.copyWith(
                          color: dark ? Colors.white : AppThemeData.neutral900,
                          height: 1.6,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              "e.g. No onions, extra spicy, ring the bell...".tr(),
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: dark
                                ? AppThemeData.darkTextTertiary
                                : AppThemeData.neutral400,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          counterStyle: AppTypography.caption.copyWith(
                            color: dark
                                ? AppThemeData.darkTextTertiary
                                : AppThemeData.neutral400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {});
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeData.primary500,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 0,
                        ),
                        child: Text(
                          "Save Note".tr(),
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomTipSheet(BuildContext ctx) {
    final dark = isDarkMode(ctx);
    _textFieldController.clear();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 14, 24, 32 + MediaQuery.of(sheetCtx).padding.bottom),
          decoration: BoxDecoration(
            color: dark ? AppThemeData.darkBgSecondary : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -4))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: dark
                        ? AppThemeData.darkBorderPrimary
                        : AppThemeData.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.volunteer_activism_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Custom Tip Amount".tr(),
                          style: TextStyle(
                            fontSize: 17,
                            fontFamily: AppThemeData.bold,
                            color: dark
                                ? AppThemeData.darkTextPrimary
                                : AppThemeData.neutral900,
                          ),
                        ),
                        Text(
                          "Enter any amount you'd like to tip".tr(),
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppThemeData.regular,
                            color: dark
                                ? AppThemeData.darkTextSecondary
                                : AppThemeData.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _textFieldController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  fontSize: 32,
                  fontFamily: AppThemeData.bold,
                  color: dark
                      ? AppThemeData.darkTextPrimary
                      : AppThemeData.neutral900,
                ),
                decoration: InputDecoration(
                  hintText: "0.00",
                  hintStyle: TextStyle(
                    color: dark
                        ? AppThemeData.darkTextTertiary
                        : AppThemeData.neutral400,
                    fontSize: 32,
                    fontFamily: AppThemeData.bold,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: dark
                            ? AppThemeData.darkBorderSecondary
                            : AppThemeData.neutral300,
                        width: 1.5),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: AppThemeData.primary500, width: 2.5),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dark
                            ? AppThemeData.darkTextSecondary
                            : AppThemeData.neutral600,
                        side: BorderSide(
                            color: dark
                                ? AppThemeData.darkBorderPrimary
                                : AppThemeData.neutral300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text("Cancel".tr(),
                          style: const TextStyle(
                              fontFamily: AppThemeData.semiBold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final val = _textFieldController.text.trim();
                        setState(() {
                          if (val.isEmpty) {
                            isTipSelected3 = false;
                            tipValue = 0;
                          } else {
                            isTipSelected3 = true;
                            tipValue = double.tryParse(val) ?? 0;
                            isTipSelected = false;
                            isTipSelected1 = false;
                            isTipSelected2 = false;
                          }
                        });
                        Navigator.pop(sheetCtx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeData.primary500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text("Apply Tip".tr(),
                          style: const TextStyle(
                              fontSize: 15,
                              fontFamily: AppThemeData.semiBold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> getPrefData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey("musics_key")) {
      final String musicsString = prefs.getString('musics_key')!;
      if (musicsString.isNotEmpty) {
        lstExtras = AddAddonsDemo.decode(musicsString);
        for (var element in lstExtras) {
          commaSepratedAddOns.add(element.name!);
        }
        commaSepratedAddOnsString = commaSepratedAddOns.join(", ");
      }
    }

    // Simplified tax fetching - just use the global tax data we already fetched
    print('Using global tax data from getTaxData()');
  }

  Future<void> setPrefData() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    sp.setString("musics_key", "");
    sp.setString("addsize", "");
  }
}

// Coupon-applied dialog content: a green percent badge sitting in front of
// a backdrop of small confetti "crackers" that boom (burst outward from a
// point, flash, then fade) on a stagger, plus a green line under the copy
// that fills over 4s and auto-dismisses the dialog when it completes.
class _CouponAppliedBanner extends StatefulWidget {
  final String code;
  final double savedAmount;

  const _CouponAppliedBanner({required this.code, required this.savedAmount});

  @override
  State<_CouponAppliedBanner> createState() => _CouponAppliedBannerState();
}

class _CouponAppliedBannerState extends State<_CouponAppliedBanner>
    with TickerProviderStateMixin {
  static const _autoDismissDuration = Duration(seconds: 4);

  late final AnimationController _progressController;
  late final AnimationController _burstController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _autoDismissDuration,
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.of(context).pop();
        }
      })
      ..forward();
    // One full lap = one round of crackers booming across the backdrop;
    // it repeats for as long as the dialog is on screen.
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 44, 24, 20),
            decoration: BoxDecoration(
              color: dark ? AppThemeData.darkBgSecondary : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _boomingConfettiBadge(),
                const SizedBox(height: 14),
                Text(
                  "'${widget.code}' applied".tr(),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: dark
                        ? AppThemeData.darkTextSecondary
                        : AppThemeData.neutral700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "${amountShow(amount: widget.savedAmount.toStringAsFixed(2))} savings with this coupon."
                      .tr(),
                  textAlign: TextAlign.center,
                  style: AppTypography.h5.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: dark
                        ? AppThemeData.darkTextPrimary
                        : AppThemeData.neutral900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Woohoo! Your coupon is successfully applied".tr(),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: dark
                        ? AppThemeData.darkTextTertiary
                        : AppThemeData.neutral500,
                  ),
                ),
                const SizedBox(height: 18),
                _autoDismissLine(dark),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.success400,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      "YAY!".tr(),
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: dark
                      ? AppThemeData.darkBgTertiary
                      : AppThemeData.neutral100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded,
                    size: 16,
                    color: dark
                        ? AppThemeData.darkTextSecondary
                        : AppThemeData.neutral600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Thin green line that fills left-to-right over exactly _autoDismissDuration,
  // tied to the same controller that closes the dialog — so the dialog is
  // always gone right as the line finishes filling.
  Widget _autoDismissLine(bool dark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        child: AnimatedBuilder(
          animation: _progressController,
          builder: (_, __) => LinearProgressIndicator(
            value: _progressController.value,
            backgroundColor:
                dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral200,
            valueColor:
                const AlwaysStoppedAnimation(AppThemeData.success400),
            minHeight: 4,
          ),
        ),
      ),
    );
  }

  // Several small "cracker" bursts scattered around the percent badge, each
  // popping — particles flash out from their own origin then fade — on its
  // own staggered timing so it reads as crackers booming in the background
  // rather than one single firework.
  Widget _boomingConfettiBadge() {
    return SizedBox(
      width: 130,
      height: 130,
      child: AnimatedBuilder(
        animation: _burstController,
        builder: (_, __) {
          final v = _burstController.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final burst in _bursts) ..._buildBurst(burst, v),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppThemeData.success400,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppThemeData.success400.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.percent_rounded,
                    color: Colors.white, size: 26),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildBurst(_CrackerBurst burst, double v) {
    // Each burst only "booms" for a short window of the loop, then sits
    // invisible until its next turn — the pop, not a smooth continuous
    // drift, is what reads as a firecracker rather than falling confetti.
    const window = 0.45;
    double raw = v - burst.phase;
    raw -= raw.floorToDouble();
    final active = raw <= window;
    final bt = active ? (raw / window).clamp(0.0, 1.0) : 1.0;
    final dist = Curves.easeOutCubic.transform(bt);
    final opacity = active
        ? (bt < 0.2 ? bt / 0.2 : (1 - (bt - 0.2) / 0.8)).clamp(0.0, 1.0)
        : 0.0;

    if (opacity <= 0) return const [];

    return [
      // Flash/spark at the origin to sell the "boom".
      Positioned(
        left: burst.origin.dx - 10,
        top: burst.origin.dy - 10,
        child: Opacity(
          opacity: (opacity * 0.8).clamp(0.0, 1.0),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppThemeData.warning300.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      for (final p in burst.pieces)
        Positioned(
          left: burst.origin.dx + p.dx * dist - 4,
          top: burst.origin.dy + p.dy * dist - 4,
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: p.angle + bt * math.pi * 1.5,
              child: p.circle
                  ? Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: p.color, shape: BoxShape.circle),
                    )
                  : Container(
                      width: 6,
                      height: 11,
                      decoration: BoxDecoration(
                        color: p.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
            ),
          ),
        ),
    ];
  }

  // Fixed (not math.Random) burst layout so it's identical on every dialog
  // open instead of jittering — three cracker origins scattered around the
  // badge, staggered so they boom one after another on a loop.
  static final List<_CrackerBurst> _bursts = [
    _CrackerBurst(
      origin: const Offset(38, 40),
      phase: 0.0,
      pieces: const [
        _ConfettiPiece(dx: -30, dy: -22, angle: -0.35, color: AppThemeData.warning300, circle: false),
        _ConfettiPiece(dx: -6, dy: -34, angle: 0.2, color: AppThemeData.danger300, circle: true),
        _ConfettiPiece(dx: -34, dy: 6, angle: 0.5, color: AppThemeData.accent500, circle: false),
        _ConfettiPiece(dx: -14, dy: 30, angle: -0.4, color: AppThemeData.primary400, circle: true),
      ],
    ),
    _CrackerBurst(
      origin: const Offset(92, 34),
      phase: 0.33,
      pieces: const [
        _ConfettiPiece(dx: 30, dy: -20, angle: 0.35, color: AppThemeData.info300, circle: false),
        _ConfettiPiece(dx: 8, dy: -32, angle: -0.25, color: AppThemeData.success300, circle: true),
        _ConfettiPiece(dx: 34, dy: 10, angle: -0.5, color: AppThemeData.warning300, circle: false),
        _ConfettiPiece(dx: 16, dy: 28, angle: 0.4, color: AppThemeData.accent400, circle: true),
      ],
    ),
    _CrackerBurst(
      origin: const Offset(65, 96),
      phase: 0.66,
      pieces: const [
        _ConfettiPiece(dx: -28, dy: 16, angle: 0.3, color: AppThemeData.accent500, circle: true),
        _ConfettiPiece(dx: -8, dy: 30, angle: -0.4, color: AppThemeData.danger300, circle: false),
        _ConfettiPiece(dx: 20, dy: 26, angle: 0.45, color: AppThemeData.info300, circle: true),
        _ConfettiPiece(dx: 30, dy: 2, angle: -0.3, color: AppThemeData.primary400, circle: false),
      ],
    ),
  ];
}

class _CrackerBurst {
  final Offset origin;
  final double phase;
  final List<_ConfettiPiece> pieces;

  const _CrackerBurst({
    required this.origin,
    required this.phase,
    required this.pieces,
  });
}

class _ConfettiPiece {
  final double dx, dy, angle;
  final Color color;
  final bool circle;

  const _ConfettiPiece({
    required this.dx,
    required this.dy,
    required this.angle,
    required this.color,
    required this.circle,
  });
}

Widget _buildChip(String label, int attributesOptionIndex,
    {bool isDark = false, bool isVariant = false}) {
  final bgColor = isVariant
      ? AppThemeData.primary500.withValues(alpha: isDark ? 0.18 : 0.10)
      : (isDark ? AppThemeData.darkBgTertiary : AppThemeData.neutral100);
  final borderColor = isVariant
      ? AppThemeData.primary500.withValues(alpha: isDark ? 0.40 : 0.30)
      : (isDark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200);
  final textColor = isVariant
      ? AppThemeData.primary500
      : (isDark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600);
  return Container(
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: borderColor, width: 0.6),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: textColor,
      ),
    ),
  );
}

Widget dashedSeparator([BuildContext? context]) {
  return DottedBorder(
    dashPattern: [5, 4],
    color: context != null && isDarkMode(context)
        ? AppThemeData.darkTextTertiary
        : AppThemeData.neutral400,
    strokeWidth: 1,
    borderType: BorderType.RRect,
    radius: Radius.circular(0),
    padding: EdgeInsets.zero,
    child: SizedBox(
      width: double.infinity,
      height: 0,
    ),
  );
}
   
