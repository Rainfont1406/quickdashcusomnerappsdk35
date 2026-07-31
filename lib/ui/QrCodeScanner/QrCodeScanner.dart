import 'dart:math' as math;
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/behavior/behavior_tracker.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../vendorProductsScreen/newVendorProductsScreen.dart';

// ── Phase states ─────────────────────────────────────────────────────────────
enum _Phase { requesting, denied, permanentlyDenied, cameraError, active }

class QrCodeScanner extends StatefulWidget {
  const QrCodeScanner({Key? key, required this.presectionList})
      : super(key: key);
  final List<SectionModel> presectionList;

  @override
  State<QrCodeScanner> createState() => _QrCodeScannerState();
}

class _QrCodeScannerState extends State<QrCodeScanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ── Scanner controller ──────────────────────────────────────────
  late final MobileScannerController _controller;

  // ── Scan-line animation ─────────────────────────────────────────
  late final AnimationController _animCtrl;
  late final Animation<double> _scanLine;

  // ── State ───────────────────────────────────────────────────────
  _Phase _phase = _Phase.requesting;
  bool _torchOn = false;
  bool _hasScanned = false;
  bool _detected = false;   // brief green flash on successful read
  bool _isVerifying = false; // live Firestore check in progress
  String? _verifyError;      // non-null while showing inline error

  @override
  void initState() {
    super.initState();

    // Keep bars but make them transparent so camera truly fills edge-to-edge.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scanLine = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );

    // Defer permission check so the first frame can render (shows loading UI).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermission());
  }

  // ── Lifecycle ───────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_phase != _Phase.active) return;
    switch (state) {
      case AppLifecycleState.resumed:
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ));
        if (_controller.value.isInitialized) _controller.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (_controller.value.isInitialized) _controller.stop();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore system UI to app default.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    _controller.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Permission ──────────────────────────────────────────────────
  Future<void> _checkPermission() async {
    PermissionStatus status = await Permission.camera.status;

    if (status.isGranted) {
      if (mounted) setState(() => _phase = _Phase.active);
      return;
    }

    if (status.isPermanentlyDenied) {
      if (mounted) setState(() => _phase = _Phase.permanentlyDenied);
      return;
    }

    // Request (first-time or "denied but requestable").
    status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _phase = _Phase.active);
    } else if (status.isPermanentlyDenied) {
      setState(() => _phase = _Phase.permanentlyDenied);
    } else {
      setState(() => _phase = _Phase.denied);
    }
  }

  // ── Torch ───────────────────────────────────────────────────────
  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  // ── QR detection ────────────────────────────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_hasScanned || _isVerifying) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final qrValue = barcodes.first.rawValue;
    if (qrValue == null) return;

    _hasScanned = true;

    // Brief green-flash feedback.
    if (mounted) setState(() => _detected = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() { _detected = false; _isVerifying = true; _verifyError = null; });

    try {
      // Live Firestore fetch — never use the stale allstoreList cache.
      final query = await FireStoreUtils.firestore
          .collection(VENDORS)
          .where('id', isEqualTo: qrValue)
          .limit(1)
          .get();

      if (!mounted) return;

      // ── Gate 1: vendor doesn't exist ──────────────────────────────
      if (query.docs.isEmpty) {
        _setVerifyError('Restaurant not found. The QR code may be invalid or outdated.'.tr());
        return;
      }

      final data = query.docs.first.data();

      // ── Gate 2: admin banned / not approved ───────────────────────
      final storeStatus = data['store_status'] as String?;
      final isActive    = data['isActive'];
      if ((storeStatus != null && storeStatus != 'approved') ||
          isActive == false) {
        _setVerifyError('This restaurant is currently unavailable.'.tr());
        return;
      }

      // ── Gate 3: section mismatch ───────────────────────────────────
      final sectionId = data['section_id'] as String?;
      if (sectionConstantModel != null &&
          sectionId != null &&
          sectionId != sectionConstantModel!.id) {
        _setVerifyError('This restaurant is not available in your current area.'.tr());
        return;
      }

      // ── All gates passed — navigate ────────────────────────────────
      if (mounted) setState(() => _isVerifying = false);
      final VendorModel vendor = VendorModel.fromJson(data);
      if (mounted) {
        Navigator.pop(context);
        BehaviorTracker.setNextEntrySource('QRCode');
        push(context, NewVendorProductsScreen(vendorModel: vendor));
      }
    } catch (_) {
      if (mounted) _setVerifyError('Something went wrong. Please try again.'.tr());
    }
  }

  void _setVerifyError(String message) {
    if (!mounted) return;
    setState(() { _isVerifying = false; _verifyError = message; });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _verifyError = null; _hasScanned = false; });
    });
  }

  // ── Navigation helper ───────────────────────────────────────────
  Future<void> callMainScreen(
      SectionModel sectionModel, String codeVal) async {
    auth.User? firebaseUser = auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      User? user = await FireStoreUtils.getCurrentUser(firebaseUser.uid);
      if (user != null && user.role == USER_ROLE_CUSTOMER) {
        user.active = true;
        user.role = USER_ROLE_CUSTOMER;
        sectionConstantModel = sectionModel;
        AppThemeData.primary300 = Color(
            int.parse(sectionModel.color!.replaceFirst('#', '0xff')));
        user.fcmToken =
            await FireStoreUtils.firebaseMessaging.getToken() ?? '';
        await FireStoreUtils.updateCurrentUser(user);
        if (!mounted) return;
        Navigator.of(context).pop();
        pushReplacement(
            context,
            ContainerScreen(
              user: user,
              vendorId: codeVal,
            ));
      } else {
        if (!mounted) return;
        pushReplacement(context, const LoginScreen());
      }
    } else {
      sectionConstantModel = sectionModel;
      AppThemeData.primary300 = Color(
          int.parse(sectionModel.color!.replaceFirst('#', '0xff')));
      if (!mounted) return;
      push(context, ContainerScreen(user: null));
    }
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Compute responsive scan-frame size once here.
    final double sw = MediaQuery.of(context).size.width;
    final double scanSize = (sw * 0.72).clamp(240.0, 300.0);

    Widget body;
    switch (_phase) {
      case _Phase.requesting:
        body = _buildLoading();
        break;
      case _Phase.denied:
        body = _buildPermissionDenied(permanent: false);
        break;
      case _Phase.permanentlyDenied:
        body = _buildPermissionDenied(permanent: true);
        break;
      case _Phase.cameraError:
        body = _buildCameraErrorState();
        break;
      case _Phase.active:
        body = _buildScanner(scanSize);
        break;
    }

    // extendBodyBehindAppBar + extendBody push the body to fill the entire
    // screen, including behind the status bar and navigation bar.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: body,
      ),
    );
  }

  // ── Scanner view ─────────────────────────────────────────────────
  Widget _buildScanner(double scanSize) {
    return Stack(
      // StackFit.expand is the critical fix:
      // Without it the Stack sizes itself to its smallest un-positioned child
      // (the SafeArea header row, ~70 dp), so Positioned.fill children only
      // fill that ~70 dp band, not the full screen.
      fit: StackFit.expand,
      children: [
        // ── 1. Full-screen camera preview ───────────────────────
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          fit: BoxFit.cover,
          placeholderBuilder: (context, child) => _buildCameraLoading(),
          errorBuilder: (context, error, child) {
            // Permission denied surfaced by the scanner itself.
            final isPerm = error.errorCode ==
                MobileScannerErrorCode.permissionDenied;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _phase = isPerm
                    ? _Phase.permanentlyDenied
                    : _Phase.cameraError);
              }
            });
            return _buildCameraLoading(); // show spinner while transitioning
          },
        ),

        // ── 2. Dark overlay + scan frame + animated scan line ───
        AnimatedBuilder(
          animation: _animCtrl,
          builder: (_, __) => CustomPaint(
            painter: _ScannerOverlayPainter(
              scanLineProgress: _scanLine.value,
              accentColor: _detected
                  ? const Color(0xFF22C55E)
                  : AppThemeData.primary500,
              scanFrameSize: scanSize,
              detected: _detected,
            ),
          ),
        ),

        // ── 3. Title + hint text (positioned relative to frame) ─
        Positioned.fill(
          child: LayoutBuilder(builder: (context, box) {
            // Mirror the painter's frame centre (shifted -scanSize*0.08 up).
            final double cy = box.maxHeight / 2 - scanSize * 0.08;
            final double frameTop = cy - scanSize / 2;
            final double frameBottom = cy + scanSize / 2;
            return Stack(children: [
              // Title block above frame
              Positioned(
                top: math.max(frameTop - 88, 80),
                left: 24,
                right: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scan QR Code'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                              offset: Offset(0, 2))
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Point your camera at the restaurant QR code'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 13,
                        height: 1.5,
                        shadows: const [
                          Shadow(
                              color: Colors.black45,
                              blurRadius: 6,
                              offset: Offset(0, 1))
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Hint / verifying / error text below frame
              Positioned(
                top: frameBottom + 22,
                left: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _detected ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: _isVerifying
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Verifying restaurant…'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : _verifyError != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _verifyError!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Text(
                              'Align the QR code within the frame'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 12,
                                letterSpacing: 0.2,
                                shadows: const [
                                  Shadow(
                                      color: Colors.black38,
                                      blurRadius: 4,
                                      offset: Offset(0, 1))
                                ],
                              ),
                            ),
                ),
              ),
            ]);
          }),
        ),

        // ── 4. Top control bar ───────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _CircleIconBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _CircleIconBtn(
                    icon: _torchOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    onTap: _toggleTorch,
                    active: _torchOn,
                    activeColor: const Color(0xFFFBBF24),
                  ),
                ],
              ),
            ),
          ),
        ),

      ],
    );
  }

  // ── Loading state ────────────────────────────────────────────────
  Widget _buildLoading() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        _buildFullScreenMessage(
          icon: const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
          title: 'Starting camera…'.tr(),
          subtitle: 'Please wait a moment'.tr(),
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CircleIconBtn(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Camera initialising (shown while MobileScanner is warming up) ─
  Widget _buildCameraLoading() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Colors.white54,
        ),
      ),
    );
  }

  // ── Permission denied states ─────────────────────────────────────
  Widget _buildPermissionDenied({required bool permanent}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF0D0D0D)),
        _buildFullScreenMessage(
          icon: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12), width: 1.5),
            ),
            child: const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 36),
          ),
          title: 'Camera Permission Required'.tr(),
          subtitle: permanent
              ? 'Camera access was permanently denied. Please enable it in your device settings to scan QR codes.'
                  .tr()
              : 'Camera access is needed to scan QR codes. Please grant permission.'
                  .tr(),
          actions: [
            if (permanent)
              _OutlinedWhiteBtn(
                label: 'Open Settings'.tr(),
                onTap: openAppSettings,
              )
            else
              _OutlinedWhiteBtn(
                label: 'Allow Camera'.tr(),
                onTap: () async {
                  setState(() => _phase = _Phase.requesting);
                  await _checkPermission();
                },
              ),
          ],
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CircleIconBtn(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Generic camera error ─────────────────────────────────────────
  Widget _buildCameraErrorState() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF0D0D0D)),
        _buildFullScreenMessage(
          icon: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.08),
              border: Border.all(
                  color: Colors.red.withValues(alpha: 0.20), width: 1.5),
            ),
            child:
                const Icon(Icons.error_outline, color: Colors.red, size: 36),
          ),
          title: 'Camera Unavailable'.tr(),
          subtitle:
              'Unable to access the camera. Please restart the app and try again.'
                  .tr(),
          actions: [
            _OutlinedWhiteBtn(
              label: 'Retry'.tr(),
              onTap: () async {
                // Dispose old controller and create a fresh one.
                _controller.dispose();
                setState(() {
                  _phase = _Phase.requesting;
                });
                await _checkPermission();
              },
            ),
          ],
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CircleIconBtn(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared full-screen message layout ────────────────────────────
  Widget _buildFullScreenMessage({
    required Widget icon,
    required String title,
    required String subtitle,
    List<Widget> actions = const [],
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
                height: 1.55,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 32),
              ...actions,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Scanner overlay painter ──────────────────────────────────────────────────
class _ScannerOverlayPainter extends CustomPainter {
  final double scanLineProgress;
  final Color accentColor;
  final double scanFrameSize;
  final bool detected;

  const _ScannerOverlayPainter({
    required this.scanLineProgress,
    required this.accentColor,
    required this.scanFrameSize,
    this.detected = false,
  });

  static const double _cornerLen = 28.0;
  static const double _cornerRadius = 14.0;
  static const double _strokeW = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Frame centre: horizontal centre, slightly above vertical centre.
    final double cx = size.width / 2;
    final double cy = size.height / 2 - scanFrameSize * 0.08;
    final double left = cx - scanFrameSize / 2;
    final double top = cy - scanFrameSize / 2;
    final double right = left + scanFrameSize;
    final double bottom = top + scanFrameSize;

    final scanRect = Rect.fromLTWH(left, top, scanFrameSize, scanFrameSize);
    final scanRRect =
        RRect.fromRectAndRadius(scanRect, const Radius.circular(_cornerRadius));

    // ── Dark overlay with transparent cut-out ─────────────────────
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutPath = Path()..addRRect(scanRRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, overlayPath, cutPath),
      Paint()..color = Colors.black.withValues(alpha: 0.68),
    );

    // ── Subtle inner border ───────────────────────────────────────
    canvas.drawRRect(
      scanRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: detected ? 0.0 : 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── Green detected flash ──────────────────────────────────────
    if (detected) {
      canvas.drawRRect(
        scanRRect,
        Paint()
          ..color = const Color(0xFF22C55E).withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
    }

    // ── Corner brackets ───────────────────────────────────────────
    final Paint cp = Paint()
      ..color = detected ? const Color(0xFF22C55E) : accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeW
      ..strokeCap = StrokeCap.round;

    void drawCorner(double x, double y, double sx, double sy) {
      // Horizontal arm
      canvas.drawLine(
        Offset(x + sx * _cornerRadius, y),
        Offset(x + sx * _cornerLen, y),
        cp,
      );
      // Vertical arm
      canvas.drawLine(
        Offset(x, y + sy * _cornerRadius),
        Offset(x, y + sy * _cornerLen),
        cp,
      );
      // Rounded arc at corner
      final arcRect = Rect.fromCenter(
        center: Offset(x + sx * _cornerRadius, y + sy * _cornerRadius),
        width: _cornerRadius * 2,
        height: _cornerRadius * 2,
      );
      // Start angle depends on which corner
      final double startAngle = sx > 0
          ? (sy > 0 ? math.pi : math.pi / 2)
          : (sy > 0 ? -math.pi / 2 : 0.0);
      canvas.drawArc(arcRect, startAngle, math.pi / 2 * sx * sy, false, cp);
    }

    drawCorner(left, top, 1, 1);     // top-left
    drawCorner(right, top, -1, 1);   // top-right
    drawCorner(left, bottom, 1, -1); // bottom-left
    drawCorner(right, bottom, -1, -1); // bottom-right

    // ── Animated scan line (only while not detected) ──────────────
    if (!detected) {
      final double lineY = top + scanLineProgress * scanFrameSize;

      // Glow halo
      canvas.drawRect(
        Rect.fromLTWH(left, lineY - 8, scanFrameSize, 16),
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.transparent,
            accentColor.withValues(alpha: 0.10),
            accentColor.withValues(alpha: 0.10),
            Colors.transparent,
          ], stops: const [
            0.0,
            0.2,
            0.8,
            1.0
          ]).createShader(
              Rect.fromLTWH(left, lineY - 8, scanFrameSize, 16))
          ..style = PaintingStyle.fill,
      );

      // Core line
      canvas.drawLine(
        Offset(left, lineY),
        Offset(right, lineY),
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.transparent,
            accentColor.withValues(alpha: 0.90),
            accentColor,
            accentColor.withValues(alpha: 0.90),
            Colors.transparent,
          ], stops: const [
            0.0,
            0.10,
            0.50,
            0.90,
            1.0
          ]).createShader(
              Rect.fromLTWH(left, lineY - 1, scanFrameSize, 2))
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter old) =>
      old.scanLineProgress != scanLineProgress ||
      old.accentColor != accentColor ||
      old.detected != detected ||
      old.scanFrameSize != scanFrameSize;
}

// ── Circular icon button (top bar) ──────────────────────────────────────────
class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color activeColor;

  const _CircleIconBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.40),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: active ? activeColor : Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

// ── Outlined white button (permission / error screens) ───────────────────────
class _OutlinedWhiteBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlinedWhiteBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
