import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

/// Global, root-level full-screen gate: whenever the device has no real
/// internet connection, this blocks the entire app behind an explanatory
/// page (offline data can't be trusted to reflect the account's current
/// active-device status — see the whole device-session gate this protects).
///
/// Deliberately an overlay (Stack), never a pushed route — a pushed screen
/// would stack multiple instances on flapping connectivity and create
/// back-button/navigation-stack edge cases; an overlay just shows/hides.
/// Mounted once, above MaterialApp's `home`, via the `builder:` callback —
/// applies to every screen, logged in or not.
class ConnectivityGate extends StatefulWidget {
  final Widget? child;

  const ConnectivityGate({Key? key, required this.child}) : super(key: key);

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  bool _offline = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    final initial = await Connectivity().checkConnectivity();
    _onConnectivityChanged(initial, debounced: false);
  }

  // OS-level connectivity ("connected to wifi") does not mean real internet
  // access (captive portals, DNS issues) — losing OS connectivity is treated
  // as an immediate, reliable "offline" signal, but *regaining* it only
  // triggers a real reachability check (see _verifyReachability) rather than
  // closing the gate outright.
  void _onConnectivityChanged(List<ConnectivityResult> results, {bool debounced = true}) {
    final hasSignal = results.any((r) => r != ConnectivityResult.none);

    _debounce?.cancel();
    if (!debounced) {
      _handleSignalChange(hasSignal);
      return;
    }
    // Debounce flapping connectivity (e.g. switching wifi APs) so a
    // momentary blip doesn't flash the gate on and off.
    _debounce = Timer(const Duration(milliseconds: 600), () => _handleSignalChange(hasSignal));
  }

  void _handleSignalChange(bool hasSignal) {
    if (!mounted) return;
    if (!hasSignal) {
      if (!_offline) setState(() => _offline = true);
      return;
    }
    _verifyReachability();
  }

  // A separate resume trigger matters here too: connectivity can silently
  // recover while the app is backgrounded (e.g. phone leaves airplane mode
  // mid-background), and onConnectivityChanged alone may already have fired
  // and been acted on before the app is even visible again — resuming is a
  // second, independent chance to catch a state the user is now looking at.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _offline) {
      _verifyReachability();
    }
  }

  Future<void> _verifyReachability() async {
    if (_checking) return; // coalesce overlapping triggers
    if (paymentInProgressNotifier.value) return; // never interrupt an in-flight gateway checkout sheet
    _checking = true;
    final wasOffline = _offline;
    try {
      final result = await DeviceSessionService.verifyOnReconnect(context);
      if (!mounted) return;
      // Every outcome (confirmed active, confirmed invalidated — which has
      // already run the force-logout flow itself — or an infra failure that
      // fails open) converges on the same thing here: there's nothing left
      // for this gate to usefully keep blocking, so close it.
      switch (result) {
        case ReconnectCheckResult.active:
        case ReconnectCheckResult.invalidated:
        case ReconnectCheckResult.unknown:
          setState(() => _offline = false);
          // Only a genuine offline->online transition, not every reachability
          // check (this method also runs on first bootstrap when never
          // offline) — one of BehaviorTracker's three flush triggers.
          if (wasOffline) BehaviorTracker.onReconnected();
          break;
        case ReconnectCheckResult.offline:
          // Genuinely still offline (2026-09-01 fix) - do NOT close the
          // gate. Tapping "Retry" while still offline used to dismiss this
          // screen anyway (verifyOnReconnect's network failure was
          // indistinguishable from "unknown", which fails open) and show
          // the app underneath with no real connection. Leave _offline as
          // it already is (true) so the gate stays up.
          break;
      }
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        if (_offline)
          _OfflineScreen(onRetry: _verifyReachability),
      ],
    );
  }
}

class _OfflineScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _OfflineScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Material(
      color: dark ? AppThemeData.darkBgPrimary : Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppThemeData.error500.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wifi_off_rounded, size: 40, color: AppThemeData.error500),
                ),
                const SizedBox(height: 24),
                Text(
                  'Internet Connection Required'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    fontSize: 20,
                    color: dark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'QuickDash needs an internet connection to verify your session and keep your account secure. Please reconnect to continue.'
                      .tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 14,
                    color: AppThemeData.neutral400,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Retry'.tr(),
                      style: const TextStyle(color: Colors.white, fontFamily: AppThemeData.semiBold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This page will close automatically once you\'re back online.'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 12,
                    color: AppThemeData.neutral400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
