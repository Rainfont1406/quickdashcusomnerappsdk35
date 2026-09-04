import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/dineInScreen/table_order_details_screen.dart';
import 'package:flutter/material.dart';

class UpComingTableBooking extends StatefulWidget {
  const UpComingTableBooking({Key? key}) : super(key: key);

  @override
  State<UpComingTableBooking> createState() => _UpComingTableBookingState();
}

class _UpComingTableBookingState extends State<UpComingTableBooking> {
  final fireStoreUtils = FireStoreUtils();
  Stream<List<BookTableModel>>? _stream;

  @override
  void initState() {
    super.initState();
    _stream = fireStoreUtils.getBookingOrders(MyAppState.currentUser!.userID, true);
  }

  @override
  void dispose() {
    fireStoreUtils.closeBookingOrdersStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
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
          return Center(child: showEmptyState('No Upcoming Bookings'.tr(), context));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return BookingCard(model: snapshot.data![index], isHistory: false);
          },
        );
      },
    );
  }
}

class BookingCard extends StatelessWidget {
  final BookTableModel model;
  final bool isHistory;

  const BookingCard({required this.model, required this.isHistory});

  _StatusInfo _getStatus() {
    if (model.status == ORDER_STATUS_ACCEPTED) {
      return _StatusInfo(
        label: 'Confirmed'.tr(),
        color: const Color(0xFF2E7D32),
        bg: const Color(0xFFE8F5E9),
        icon: Icons.check_circle_outline,
      );
    }
    if (model.status == ORDER_STATUS_REJECTED) {
      return _StatusInfo(
        label: 'Rejected'.tr(),
        color: AppThemeData.error500,
        bg: const Color(0xFFFFEBEE),
        icon: Icons.cancel_outlined,
      );
    }
    // ORDER_STATUS_PLACED
    if (isHistory) {
      return _StatusInfo(
        label: 'Expired'.tr(),
        color: AppThemeData.grey500,
        bg: AppThemeData.grey100,
        icon: Icons.schedule,
      );
    }
    return _StatusInfo(
      label: 'Processing'.tr(),
      color: AppThemeData.accent600,
      bg: AppThemeData.accent50,
      icon: Icons.hourglass_empty_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = isDarkMode(context);
    final status = _getStatus();
    final dateStr = DateFormat("EEE, MMM d · hh:mm a").format(model.date.toDate());

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => push(context, TableOrderDetailsScreen(bookTableModel: model)),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: dark
              ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
              : [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: image + restaurant info
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(model.vendor.photo),
                      height: 64,
                      width: 64,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppThemeData.grey100),
                      errorWidget: (_, __, ___) =>
                          Image.network(placeholderImage, fit: BoxFit.cover, height: 64, width: 64),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.vendor.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontFamily: AppThemeData.semiBold,
                            color: dark ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.location_on_outlined, size: 13, color: AppThemeData.grey400),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              model.vendor.location,
                              style: const TextStyle(fontSize: 12, color: AppThemeData.grey400),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: status.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(status.icon, size: 12, color: status.color),
                      const SizedBox(width: 4),
                      Text(status.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: AppThemeData.semiBold,
                            color: status.color,
                          )),
                    ]),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.grey200),
            // Details row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _detailChip(
                    icon: Icons.calendar_today_outlined,
                    text: dateStr,
                    dark: dark,
                  ),
                  const SizedBox(width: 12),
                  _detailChip(
                    icon: Icons.people_outline,
                    text: '${model.totalGuest} ${'Guests'.tr()}',
                    dark: dark,
                  ),
                ],
              ),
            ),
            // Guest name row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Icon(Icons.person_outline,
                    size: 14, color: dark ? AppThemeData.grey400 : AppThemeData.grey500),
                const SizedBox(width: 6),
                Text(
                  '${model.guestFirstName} ${model.guestLastName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: dark ? AppThemeData.grey300 : AppThemeData.grey600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 13, color: dark ? AppThemeData.grey600 : AppThemeData.grey300),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip({required IconData icon, required String text, required bool dark}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgTertiary : AppThemeData.grey50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: AppThemeData.primary500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppThemeData.medium,
                color: dark ? Colors.white70 : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;
  const _StatusInfo({required this.label, required this.color, required this.bg, required this.icon});
}
