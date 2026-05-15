import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/UpComingTableBooking.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class HistoryTableBooking extends StatefulWidget {
  const HistoryTableBooking({Key? key}) : super(key: key);

  @override
  State<HistoryTableBooking> createState() => _HistoryTableBookingState();
}

class _HistoryTableBookingState extends State<HistoryTableBooking> {
  final fireStoreUtils = FireStoreUtils();
  Stream<List<BookTableModel>>? _stream;

  @override
  void initState() {
    super.initState();
    _stream = fireStoreUtils.getBookingOrders(MyAppState.currentUser!.userID, false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookTableModel>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator.adaptive(
              valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: showEmptyState('No Previous Bookings'.tr(), context));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return BookingCard(model: snapshot.data![index], isHistory: true);
          },
        );
      },
    );
  }
}
