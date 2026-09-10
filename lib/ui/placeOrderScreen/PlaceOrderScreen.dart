import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/send_notification.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/firestore_instrumentation.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/home/HomeScreen.dart';
import 'package:emartconsumer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _OrderState { processing, success, error }

class PlaceOrderScreen extends StatefulWidget {
  /// Already-placed order — used by COD / wallet flows where Firestore write
  /// happens before this screen is pushed.
  final OrderModel? orderModel;

  /// Factory that performs the Firestore write and returns the placed order.
  /// Used by online payment flows (Razorpay etc.) so this screen is pushed
  /// BEFORE the write, letting the loading animation run concurrently.
  final Future<OrderModel> Function()? orderFactory;

  // true = payment already collected (Razorpay / online); shows payment-specific steps
  final bool isPaymentVerified;

  const PlaceOrderScreen({
    Key? key,
    this.orderModel,
    this.orderFactory,
    this.isPaymentVerified = false,
  })  : assert(orderModel != null || orderFactory != null,
            'Provide either orderModel or orderFactory'),
        super(key: key);

  @override
  _PlaceOrderScreenState createState() => _PlaceOrderScreenState();
}

class _PlaceOrderScreenState extends State<PlaceOrderScreen>
    with TickerProviderStateMixin {
  // ── State machine ─────────────────────────────────────────────────────────
  _OrderState _orderState = _OrderState.processing;
  String? _errorMessage;
  bool _navigationStarted = false;

  // Resolved order — null until _processOrder completes (orderFactory path)
  OrderModel? _order;

  // ── Step messages ─────────────────────────────────────────────────────────
  int _currentStep = 0;
  late final List<String> _steps;
  Timer? _stepTimer;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _checkCtrl;
  late AnimationController _fadeCtrl;

  late Animation<double> _pulseAnim;
  late Animation<double> _checkScaleAnim;
  late Animation<double> _fadeAnim;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _steps = widget.isPaymentVerified
        ? [
            'Payment Successful',
            'Payment in Transit',
            'Order Confirmed',
          ]
        : [
            'Creating your order',
            'Notifying restaurant',
            'Finalising your booking',
          ];

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);

    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350))
      ..forward();

    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _checkScaleAnim = CurvedAnimation(
        parent: _checkCtrl, curve: Curves.elasticOut);
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _startStepCycle();

    WidgetsBinding.instance.addPostFrameCallback((_) => _processOrder());
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _pulseCtrl.dispose();
    _checkCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Step cycling ──────────────────────────────────────────────────────────
  void _startStepCycle() {
    _stepTimer?.cancel();
    _stepTimer =
        Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted || _orderState != _OrderState.processing) return;
      if (_currentStep < _steps.length - 1) {
        setState(() => _currentStep++);
      }
    });
  }

  // ── Core logic ────────────────────────────────────────────────────────────
  Future<void> _processOrder() async {
    try {
      if (widget.orderFactory != null) {
        // Online payment path: place order concurrently with the loading animation.
        // Enforce a minimum 2-second animation window so it doesn't flash by.
        final start = DateTime.now();
        _order = await widget.orderFactory!();
        final elapsed = DateTime.now().difference(start).inMilliseconds;
        final remaining = 2000 - elapsed;
        if (remaining > 0) {
          await Future.delayed(Duration(milliseconds: remaining));
        }
      } else {
        // COD / wallet path: order is already placed, just animate
        _order = widget.orderModel;
        await Future.delayed(const Duration(milliseconds: 2000));
      }

      // Vendor push + customer email must fire regardless of whether this
      // screen is still around - the order already exists server-side by
      // this point, and neither call needs a BuildContext, so there is no
      // reason to let a `mounted` check silently drop them.
      _sendNotificationsBackground();

      if (!mounted) return;

      // Cart-clear does need a live context (Provider.of), so it stays
      // gated here.
      Provider.of<CartDatabase>(context, listen: false).deleteAllProducts();

      _stepTimer?.cancel();
      _pulseCtrl.stop();

      setState(() {
        _currentStep = _steps.length - 1;
        _orderState = _OrderState.success;
      });
      await _checkCtrl.forward();

      // Show success briefly before auto-navigating
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) _navigateAway();
    } catch (e) {
      if (!mounted) return;
      _stepTimer?.cancel();
      setState(() {
        _orderState = _OrderState.error;
        _errorMessage = _userFriendlyError(e.toString());
      });
    }
  }

  void _sendNotificationsBackground() {
    _sendVendorNotification().catchError((_) {});
    FireStoreUtils.sendOrderEmail(orderModel: _order!)
        .catchError((_) {});
  }

  Future<void> _sendVendorNotification() async {
    try {
      // Always fetch the live token from Firestore — never use the
      // cached value which may be stale (e.g. vendor logged out).
      final vendorId = _order!.vendorID;
      String liveToken = '';
      if (vendorId.isNotEmpty) {
        final doc = await FireStoreUtils.firestore
            .collection(VENDORS)
            .doc(vendorId)
            .getLogged('_sendVendorNotification:VENDORS');
        liveToken = (doc.data()?['fcmToken'] as String?) ?? '';
      }

      if (liveToken.isEmpty) return;

      final bool isBillPayAccept = _order!.billPayRequestId != null;
      final payload = <String, dynamic>{
        'type': isBillPayAccept ? 'customer_bill_pay_response' : 'vendor_order',
        'orderId': _order!.id,
        if (isBillPayAccept) 'action': 'accepted',
        if (isBillPayAccept) 'billPayRequestId': _order!.billPayRequestId,
      };
      final type = isBillPayAccept
          ? billPayRequestAccepted
          : (_order!.scheduleTime != null ? scheduleOrder : orderPlaced);
      SendNotification.sendFcmMessage(type, liveToken, payload);
    } catch (_) {}
  }

  void _navigateAway() {
    if (_navigationStarted || !mounted) return;
    _navigationStarted = true;

    // Capture nav and order before the first push — pushAndRemoveUntil
    // deactivates this widget's context, so a second Navigator.of(context)
    // call would trigger the _dependents.isEmpty assertion.
    final nav = Navigator.of(context);
    final orderModel = _order;

    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ContainerScreen(user: MyAppState.currentUser),
      ),
      (_) => false,
    );
    nav.push(MaterialPageRoute(
      builder: (_) => OrderDetailsScreen(
        orderModel: orderModel,
        hideBackButton: false,
      ),
    ));
  }

  String _userFriendlyError(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('socket') ||
        r.contains('network') ||
        r.contains('timeout') ||
        r.contains('connection')) {
      return 'Network issue. Please check your connection and try again.'.tr();
    }
    if (r.contains('permission-denied') || r.contains('unauthorized')) {
      return 'Permission denied. Please contact support.'.tr();
    }
    return 'Something went wrong. Your order may have been placed. Check Orders screen before retrying.'
        .tr();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor:
            dark ? AppThemeData.darkBgPrimary : Colors.white,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: SafeArea(
            child: switch (_orderState) {
              _OrderState.error => _buildError(dark),
              _OrderState.success => _buildSuccess(dark),
              _ => _buildProcessing(dark),
            },
          ),
        ),
      ),
    );
  }

  // ── Processing UI ─────────────────────────────────────────────────────────
  Widget _buildProcessing(bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 3),

          // Pulsing ring + spinner
          ScaleTransition(
            scale: _pulseAnim,
            child: _ringIcon(
              bg: AppThemeData.primary500.withValues(alpha: 0.10),
              innerBg: AppThemeData.primary500.withValues(alpha: 0.16),
              child: SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  color: AppThemeData.primary500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 44),

          Text(
            'Placing Your Order'.tr(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              fontFamily: AppThemeData.bold,
              color: dark
                  ? AppThemeData.darkTextPrimary
                  : AppThemeData.neutral900,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          Text(
            'Please do not press Back or close the app\nuntil your order is confirmed.'.tr(),
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: dark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral500,
              fontFamily: AppThemeData.regular,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 52),

          // Step list
          _buildSteps(dark),

          const Spacer(flex: 4),

          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppThemeData.warning50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 16, color: AppThemeData.warning400),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Secure payment processing'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppThemeData.warning400,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSteps(bool dark) {
    return Column(
      children: List.generate(_steps.length, (i) {
        final bool done = i < _currentStep;
        final bool active = i == _currentStep;

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppThemeData.success400
                      : active
                          ? AppThemeData.primary500
                          : (dark
                              ? AppThemeData.darkBgTertiary
                              : AppThemeData.neutral100),
                  border: !done && !active
                      ? Border.all(
                          color: dark
                              ? AppThemeData.darkBorderPrimary
                              : AppThemeData.neutral300,
                          width: 1.5,
                        )
                      : null,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 15)
                      : active
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? AppThemeData.darkTextTertiary
                                    : AppThemeData.neutral400,
                              ),
                            ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _steps[i].tr(),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: active || done
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: done
                        ? AppThemeData.success400
                        : active
                            ? (dark
                                ? AppThemeData.darkTextPrimary
                                : AppThemeData.neutral800)
                            : (dark
                                ? AppThemeData.darkTextTertiary
                                : AppThemeData.neutral400),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Success UI ────────────────────────────────────────────────────────────
  Widget _buildSuccess(bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 3),

          ScaleTransition(
            scale: _checkScaleAnim,
            child: _ringIcon(
              bg: AppThemeData.success400.withValues(alpha: 0.12),
              innerBg: AppThemeData.success400.withValues(alpha: 0.20),
              child: Icon(Icons.check_rounded,
                  size: 48, color: AppThemeData.success400),
            ),
          ),

          const SizedBox(height: 40),

          Text(
            'Order Placed!'.tr(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              fontFamily: AppThemeData.bold,
              color: dark
                  ? AppThemeData.darkTextPrimary
                  : AppThemeData.neutral900,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          Text(
            'Your order is confirmed and the restaurant has been notified.'
                .tr(),
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: dark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral500,
              fontFamily: AppThemeData.regular,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          // Order card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: dark
                  ? AppThemeData.darkBgSecondary
                  : AppThemeData.neutral50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark
                    ? AppThemeData.darkBorderSecondary
                    : AppThemeData.neutral200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        AppThemeData.primary500.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt_long_rounded,
                      color: AppThemeData.primary500, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${_order!.id}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: dark
                              ? AppThemeData.darkTextPrimary
                              : AppThemeData.neutral800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _order!.vendor.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: dark
                              ? AppThemeData.darkTextSecondary
                              : AppThemeData.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: dark
                        ? AppThemeData.darkTextTertiary
                        : AppThemeData.neutral400),
              ],
            ),
          ),

          const Spacer(flex: 2),

          GestureDetector(
            onTap: _navigateAway,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppThemeData.primary500,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Track Order'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  // ── Error UI ──────────────────────────────────────────────────────────────
  Widget _buildError(bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 3),

          _ringIcon(
            bg: AppThemeData.error500.withValues(alpha: 0.10),
            innerBg: AppThemeData.error500.withValues(alpha: 0.16),
            child: Icon(Icons.error_outline_rounded,
                size: 48, color: AppThemeData.error500),
          ),

          const SizedBox(height: 36),

          Text(
            'Could Not Complete'.tr(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontFamily: AppThemeData.bold,
              color: dark
                  ? AppThemeData.darkTextPrimary
                  : AppThemeData.neutral900,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          Text(
            _errorMessage ??
                'Something went wrong. Please check your Orders screen before retrying.'
                    .tr(),
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: dark
                  ? AppThemeData.darkTextSecondary
                  : AppThemeData.neutral500,
              fontFamily: AppThemeData.regular,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppThemeData.warning50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppThemeData.warning400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your payment was NOT charged again. Check your Orders page if unsure.'
                        .tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeData.warning400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(flex: 2),

          GestureDetector(
            onTap: () {
              setState(() {
                _orderState = _OrderState.processing;
                _currentStep = 0;
                _errorMessage = null;
                _navigationStarted = false;
              });
              _pulseCtrl.repeat(reverse: true);
              _startStepCycle();
              _processOrder();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppThemeData.primary500,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Try Again'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: () => _navigateAway(),
            child: Text(
              'View My Orders'.tr(),
              style: TextStyle(
                fontSize: 14,
                color: dark
                    ? AppThemeData.darkTextSecondary
                    : AppThemeData.neutral500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  // ── Shared ring widget ────────────────────────────────────────────────────
  Widget _ringIcon({
    required Color bg,
    required Color innerBg,
    required Widget child,
  }) {
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: innerBg),
          child: Center(child: child),
        ),
      ),
    );
  }
}
