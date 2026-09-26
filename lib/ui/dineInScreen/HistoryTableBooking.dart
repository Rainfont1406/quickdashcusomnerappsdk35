import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/booking_history_watcher.dart';
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
  // 2026-09-26: finished bookings come from the device cache, recent ones
  // live, only the recent 5 when the cache is empty - see
  // BookingHistoryWatcher. Was a plain live query that re-downloaded every
  // past booking (up to 20) on each open.
  late final BookingHistoryWatcher _watcher;
  late final Stream<List<BookTableModel>> _stream;

  @override
  void initState() {
    super.initState();
    _watcher = BookingHistoryWatcher(MyAppState.currentUser!.userID);
    _stream = _watcher.stream;
    _watcher.start();
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }

  Widget _buildShowOlder() {
    return ValueListenableBuilder<bool>(
      valueListenable: _watcher.hasOlder,
      builder: (context, hasOlder, _) {
        if (!hasOlder) return const SizedBox(height: 8);
        return ValueListenableBuilder<bool>(
          valueListenable: _watcher.loadingOlder,
          builder: (context, loading, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: loading
                  ? CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                    )
                  : TextButton.icon(
                      onPressed: _watcher.loadOlder,
                      icon: Icon(Icons.history_rounded, color: AppThemeData.primary500),
                      label: Text(
                        'Show older bookings'.tr(),
                        style: TextStyle(color: AppThemeData.primary500, fontWeight: FontWeight.w600),
                      ),
                    ),
            ),
          ),
        );
      },
    );
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                showEmptyState('No Previous Bookings'.tr(), context),
                _buildShowOlder(),
              ],
            ),
          );
        }
        final bookings = snapshot.data!;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: bookings.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == bookings.length) return _buildShowOlder();
            return BookingCard(model: bookings[index], isHistory: true);
          },
        );
      },
    );
  }
}
