import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

// Shown instead of real content anywhere Delivery-mode browsing/ordering is
// blocked because the admin disabled delivery for this section. Used both
// inline (e.g. inside HomeScreen's existing scroll body) and wrapped in
// ComingSoonScreen for screens that are pushed as their own route.
class ComingSoonView extends StatelessWidget {
  final String message;

  const ComingSoonView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final String displayMessage = message.trim().isNotEmpty
        ? message
        : "We're not delivering right now. Please check back soon!".tr();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Column(
        children: [
          Icon(
            Icons.delivery_dining_rounded,
            size: 64,
            color: isDarkMode(context)
                ? AppThemeData.grey400
                : AppThemeData.grey500,
          ),
          const SizedBox(height: 20),
          Text(
            'Coming Soon'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontFamily: AppThemeData.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            displayMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: AppThemeData.regular,
              color: isDarkMode(context)
                  ? AppThemeData.grey400
                  : AppThemeData.grey600,
            ),
          ),
        ],
      ),
    );
  }
}

// Full-screen variant (Scaffold + back button) for screens that are entirely
// replaced while Delivery is off, e.g. Search, Map, Product Details.
class ComingSoonScreen extends StatelessWidget {
  final String message;

  const ComingSoonScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDarkMode(context) ? Colors.white : Colors.black87,
        ),
      ),
      body: Center(child: ComingSoonView(message: message)),
    );
  }
}
