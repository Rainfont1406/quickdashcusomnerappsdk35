import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PhonePayScreen extends StatefulWidget {
  final String initialUrl;
  final String redirectUrl;

  const PhonePayScreen({
    super.key,
    required this.initialUrl,
    required this.redirectUrl,
  });

  @override
  State<PhonePayScreen> createState() => _PhonePayScreenState();
}

class _PhonePayScreenState extends State<PhonePayScreen> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Override user agent to remove Android WebView's "wv" marker.
      // PhonePe detects "wv" and falls back to QR-only mode, hiding UPI app buttons.
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            // PhonePe uses window.open() to launch UPI apps in Chrome.
            // WebView's onNavigationRequest only catches current-frame navigation,
            // not window.open(). Redirect all window.open() calls into the current
            // frame so our intent handler picks them up.
            _controller.runJavaScript('''
              (function() {
                var _orig = window.open;
                window.open = function(url, target, features) {
                  if (typeof url === 'string' && url.length > 0) {
                    window.location.href = url;
                    return null;
                  }
                  return _orig.apply(this, arguments);
                };
              })();
            ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            // Detect redirect to our configured redirectUrl (payment completed)
            if (widget.redirectUrl.isNotEmpty &&
                url.startsWith(widget.redirectUrl)) {
              final uri = Uri.tryParse(url);
              final code = uri?.queryParameters['code'];
              final transactionId = uri?.queryParameters['transactionId'];
              final success = code == 'PAYMENT_SUCCESS' ||
                  (transactionId != null && transactionId.isNotEmpty);
              Navigator.of(context).pop(success);
              return NavigationDecision.prevent;
            }

            // UPI app deep links cannot be opened inside WebView —
            // hand them to the Android system so GPay/Paytm/PhonePe app opens.
            final uri = Uri.tryParse(url);
            final scheme = uri?.scheme ?? '';

            if (scheme == 'intent') {
              final upiUrl = _extractUpiFromIntent(url);
              debugPrint('PhonePe WebView: intent intercepted → $upiUrl');
              if (upiUrl != null) {
                _launchUpi(upiUrl);
              } else {
                ShowToastDialog.showToast('Could not parse UPI intent URL');
              }
              return NavigationDecision.prevent;
            }

            const upiSchemes = {
              'upi', 'phonepe', 'tez', 'gpay', 'paytmmp',
              'bhim', 'bharatpe', 'credpay', 'mobikwik', 'freecharge',
            };
            if (upiSchemes.contains(scheme)) {
              debugPrint('PhonePe WebView: $scheme intercepted → $url');
              _launchUpi(url);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _showCancelDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF5F259F), // PhonePe purple
          title: Text(
            'PhonePe Payment'.tr(),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          leading: GestureDetector(
            onTap: _showCancelDialog,
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF5F259F),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUpi(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        ShowToastDialog.showToast('No UPI app found to handle payment');
      }
    } catch (e) {
      debugPrint('PhonePe WebView: launchUpi error: $e');
      ShowToastDialog.showToast('Could not open UPI app: $e');
    }
  }

  /// Converts an Android intent:// URL into a plain upi:// URL.
  ///
  /// Example:
  ///   intent://pay?pa=m@ybl&am=100#Intent;scheme=upi;package=com.phonepe.app;end
  ///   → upi://pay?pa=m@ybl&am=100
  ///
  /// This lets Android show a chooser across all installed UPI apps
  /// rather than requiring one specific package to be present.
  String? _extractUpiFromIntent(String intentUrl) {
    try {
      final hashIndex = intentUrl.indexOf('#');
      final urlPart = hashIndex >= 0 ? intentUrl.substring(0, hashIndex) : intentUrl;
      final extras = hashIndex >= 0 ? intentUrl.substring(hashIndex + 1) : '';

      final schemeMatch = RegExp(r'scheme=([^;]+)').firstMatch(extras);
      final innerScheme = schemeMatch?.group(1) ?? 'upi';

      // urlPart = "intent://pay?..." → replace "intent" with innerScheme
      final upiUrl = innerScheme + urlPart.substring('intent'.length);
      debugPrint('PhonePe WebView: intent → $upiUrl');
      return upiUrl;
    } catch (e) {
      debugPrint('PhonePe WebView: intent parse failed: $e');
      return null;
    }
  }

  Future<void> _showCancelDialog() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: 'Cancel Payment'.tr(),
      message: 'Are you sure you want to cancel the payment?'.tr(),
      confirmLabel: 'Cancel Payment'.tr(),
      cancelLabel: 'Continue'.tr(),
      destructive: true,
    );
    if (confirmed) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }
}
