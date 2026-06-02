import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/paystack_url_genrater.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayStackScreen extends StatefulWidget {
  final String initialURl;
  final String reference;
  final String amount;
  final String secretKey;
  final String callBackUrl;

  const PayStackScreen({Key? key, required this.initialURl, required this.reference, required this.amount, required this.secretKey, required this.callBackUrl}) : super(key: key);

  @override
  State<PayStackScreen> createState() => _PayStackScreenState();
}

class _PayStackScreenState extends State<PayStackScreen> {
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
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest navigation) async {
            print("--->2" + navigation.url);
            print("--->2" + "${widget.callBackUrl}?trxref=${widget.reference}&reference=${widget.reference}");
            if (navigation.url == 'https://foodieweb.siswebapp.com/success?trxref=${widget.reference}&reference=${widget.reference}' ||
                navigation.url == '${widget.callBackUrl}?trxref=${widget.reference}&reference=${widget.reference}') {
              final isDone = await PayStackURLGen.verifyTransaction(secretKey: widget.secretKey, reference: widget.reference, amount: widget.amount);
              Navigator.pop(context, isDone); //close webview
            }
            if ((navigation.url == '${widget.callBackUrl}?trxref=${widget.reference}&reference=${widget.reference}') ||
                (navigation.url == "https://hello.pstk.xyz/callback") ||
                (navigation.url == 'https://standard.paystack.co/close')) {
              final isDone = await PayStackURLGen.verifyTransaction(secretKey: widget.secretKey, reference: widget.reference, amount: widget.amount);
              Navigator.pop(context, isDone);
              //close webview
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialURl));
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
            backgroundColor: AppThemeData.primary500,
            title: Text("Payment".tr()),
            centerTitle: false,
            leading: GestureDetector(
              onTap: () {
                _showMyDialog();
              },
              child: const Icon(
                Icons.arrow_back,
              ),
            )),
        body: WebViewWidget(controller: controller),
      ),
    );
  }

  Future<void> _showMyDialog() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: 'Cancel Payment'.tr(),
      message: 'cancelPayment?'.tr(),
      confirmLabel: 'Cancel Payment'.tr(),
      cancelLabel: 'Continue'.tr(),
      destructive: true,
    );
    if (confirmed) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }
}
