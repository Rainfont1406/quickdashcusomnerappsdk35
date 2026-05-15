import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/HistoryTableBooking.dart';
import 'package:emartconsumer/ui/dineInScreen/UpComingTableBooking.dart';
import 'package:flutter/material.dart';

class MyBookingScreen extends StatelessWidget {
  const MyBookingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: dark ? AppThemeData.surfaceDark : AppThemeData.surface,
        appBar: AppBar(
          backgroundColor: dark ? AppThemeData.darkBgPrimary : Colors.white,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: dark ? Colors.white : Colors.black),
          ),
          title: Text(
            'My Bookings'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontFamily: AppThemeData.semiBold,
              color: dark ? Colors.white : Colors.black,
            ),
          ),
          centerTitle: true,
          bottom: TabBar(
            labelColor: AppThemeData.primary500,
            unselectedLabelColor: dark ? AppThemeData.grey500 : AppThemeData.grey400,
            indicatorColor: AppThemeData.primary500,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 14),
            tabs: [
              Tab(text: 'Upcoming'.tr()),
              Tab(text: 'History'.tr()),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            UpComingTableBooking(),
            HistoryTableBooking(),
          ],
        ),
      ),
    );
  }
}
