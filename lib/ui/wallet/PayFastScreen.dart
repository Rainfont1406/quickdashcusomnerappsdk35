// ignore_for_file: deprecated_member_use

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayFastScreen extends StatefulWidget {
  final String htmlData;
  final PayFastSettingData payFastSettingData;

  const PayFastScreen({Key? key, required this.htmlData, required this.payFastSettingData}) : super(key: key);

  @override
  State<PayFastScreen> createState() => _PayFastScreenState();
}

class _PayFastScreenState extends State<PayFastScreen> {
  WebViewController controller = WebViewController();

  @override
  void initState() {
    initController();
    super.initState();
  }

  initController() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest navigation) async {
            if (kDebugMode) {
              print("--->2 $navigation");
            }
            if (navigation.url == widget.payFastSettingData.return_url) {
              Navigator.pop(context, true);
            } else if (navigation.url == widget.payFastSettingData.notify_url) {
              Navigator.pop(context, false);
            } else if (navigation.url == widget.payFastSettingData.cancel_url) {
              _showMyDialog();
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString((widget.htmlData));
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showMyDialog();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: GestureDetector(
            onTap: () {
              _showMyDialog();
            },
            child: const Icon(
              Icons.arrow_back,
            ),
          ),
        ),
        body: WebViewWidget(controller: controller),
      ),
    );
  }

  Future<void> _showMyDialog() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: 'Cancel Payment'.tr(),
      message: 'cancelPayment?'.tr(),
      confirmLabel: 'Exit'.tr(),
      cancelLabel: 'Continue Payment'.tr(),
      destructive: true,
    );
    if (confirmed) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }
}
