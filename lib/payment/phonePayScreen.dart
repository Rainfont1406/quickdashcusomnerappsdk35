import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            // Detect redirect to our configured redirectUrl (payment completed)
            if (widget.redirectUrl.isNotEmpty &&
                url.startsWith(widget.redirectUrl)) {
              // Check if the URL indicates success or failure
              final uri = Uri.tryParse(url);
              final code = uri?.queryParameters['code'];
              final transactionId = uri?.queryParameters['transactionId'];
              final success = code == 'PAYMENT_SUCCESS' ||
                  (transactionId != null && transactionId.isNotEmpty);
              Navigator.of(context).pop(success);
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
