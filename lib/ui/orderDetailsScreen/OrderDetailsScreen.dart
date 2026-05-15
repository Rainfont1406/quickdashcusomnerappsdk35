// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/constants/spacing.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/variant_info.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/chat_screen/admin_chat_screeen.dart';
import 'package:emartconsumer/ui/chat_screen/chat_screen.dart';
import 'package:emartconsumer/ui/orderDetailsScreen/order_tracking_screen.dart';
import 'package:emartconsumer/widget/userAvatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart' as lottie;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/localDatabase.dart';

class OrderDetailsScreen extends StatefulWidget {
  final OrderModel? orderModel;
  final String? orderId;
  final bool hideBackButton;

  const OrderDetailsScreen({Key? key, this.orderModel, this.orderId, this.hideBackButton = false})
      : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late CartDatabase cartDatabase;
  OrderModel? orderModel;

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    super.didChangeDependencies();
  }

  FireStoreUtils fireStoreUtils = FireStoreUtils();
  int estimatedSecondsFromDriverToStore = 900;
  late String orderStatus;
  bool isTakeAway = false;
  late String storeName;
  late String phoneNumberStore;
  String currentEvent = '';
  int estimatedTime = 0;
  Timer? timerCountDown;
  double total = 0.0;
  var discount;
  GoogleMapController? _mapController;
  StreamController<String> arrivalTimeStreamController = StreamController();
  var tipAmount = "0.0";

  //latlng of the vendor
  LatLng? vendorLocation;

  //latlng of the user
  LatLng? userLocation;

  List<LatLng> polylineCoordinates = [];

  // Future<PolylineResult>? polyLinesFuture;

  List<Polyline> polylines = [];
  List<Marker> mapMarkers = [];

  @override
  void initState() {
    loadData();

    super.initState();
  }

  loadData() async {
    if (widget.orderModel != null) {
      orderModel = widget.orderModel;
      await calculate();
    } else {
      await FireStoreUtils().getOrderById(widget.orderId).then((value) {
        orderModel = value;
        calculate();
      });
      if (orderModel == null) return;
      await FireStoreUtils()
          .getSectionsById(orderModel!.sectionId)
          .then((value) {
        sectionConstantModel = value;
      });
      setState(() {});
    }
  }

  calculate() {
    total = 0.0;
    discount = 0.0;
    setMarkerIcon();

    getCurrentOrder();
    checkPerm();
    orderStatus = orderModel!.status;
    isTakeAway = orderModel!.takeAway!;

    orderModel!.products.forEach((element) {
      if (element.extras_price != null &&
          element.extras_price!.isNotEmpty &&
          double.parse(element.extras_price!) != 0.0) {
        total += element.quantity * double.parse(element.extras_price!);
      }
      total += element.quantity * double.parse(element.price);

      //     var price =  (element.extras_price == null || element.extras_price == "" || element.extras_price == "0.0")
      //     ? ((element.discountPrice == "" || element.discountPrice == "0" || element.discountPrice == null)
      //         ? element.price
      //         : element.discountPrice)
      //     : element.extras_price;
      // total += element.quantity * double.parse(price!);
      discount = orderModel!.discount;
    });
  }

  checkPerm() async {
    var status = await Permission.bluetooth.status;
    var bluetoothConnect = await Permission.bluetoothConnect.status;
    var bluetoothScan = await Permission.bluetoothScan.status;
    var locationstatus = await Permission.location.status;

    if (locationstatus.isDenied) {
      await Permission.location.request();
    }
    if (bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    if (bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }

    if (status.isDenied) {
      await Permission.bluetooth.request();
    }
    if (await Permission.bluetooth.status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  @override
  void dispose() {
    timerCountDown?.cancel();
    arrivalTimeStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.darkBgSecondary : const Color(0xFFF2F3F8),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.hideBackButton,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
        title: Text(
          'Order Details'.tr(),
          style: TextStyle(
            fontFamily: AppThemeData.semiBold,
            fontSize: 18,
            color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        leading: widget.hideBackButton
            ? null
            : IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18,
                    color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E)),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.chat_bubble_2_fill, color: AppThemeData.primary500, size: 20),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminChatScreen())),
            tooltip: 'Support'.tr(),
          ),
        ],
      ),
      body: orderModel != null
          ? StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: fireStoreUtils.watchOrderStatus(orderModel!.id),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  OrderModel orderModel = OrderModel.fromJson(snapshot.data!.data()!);
                  orderStatus = orderModel.status;
                  storeName = orderModel.vendor.title;
                  phoneNumberStore = orderModel.vendor.phonenumber;
                  switch (orderStatus) {
                    case ORDER_STATUS_PLACED:
                      currentEvent = 'We sent your order to'.tr() + " ${orderModel.vendor.title}";
                      break;
                    case ORDER_STATUS_ACCEPTED:
                      currentEvent = 'preparingYourOrder'.tr();
                      break;
                    case ORDER_STATUS_REJECTED:
                      currentEvent = 'Your order is reject by the restaurant'.tr();
                      break;
                    case ORDER_STATUS_DRIVER_PENDING:
                      currentEvent = 'Looking for a driver...'.tr();
                      break;
                    case ORDER_STATUS_DRIVER_REJECTED:
                      currentEvent = 'Looking for a driver...'.tr();
                      break;
                    case ORDER_STATUS_SHIPPED:
                      currentEvent = 'has picked up your order.'.tr(args: [
                        orderModel.driver?.firstName ?? 'Our Driver'.tr(),
                      ]);
                      break;
                    case ORDER_STATUS_IN_TRANSIT:
                      currentEvent = 'Your order is on the way'.tr();
                      break;
                    case ORDER_STATUS_COMPLETED:
                      currentEvent = 'Your order is Deliver.'.tr();
                      break;
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      children: [
                        _buildRestaurantAndItemsCard(orderModel),
                        const SizedBox(height: 12),
                        _buildStatusCard(orderModel),
                        if (orderStatus == ORDER_STATUS_SHIPPED || orderStatus == ORDER_STATUS_IN_TRANSIT) ...[
                          const SizedBox(height: 12),
                          buildDriverCard(orderModel),
                        ],
                        if (sectionConstantModel!.serviceTypeFlag != "ecommerce-service" &&
                            (orderStatus == ORDER_STATUS_SHIPPED || orderStatus == ORDER_STATUS_IN_TRANSIT)) ...[
                          const SizedBox(height: 12),
                          _buildTrackCard(orderModel),
                        ],
                        const SizedBox(height: 12),
                        buildBillSummaryCard(orderModel),
                      ],
                    ),
                  );
                } else if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(AppThemeData.primary500),
                    ),
                  );
                } else {
                  return Center(child: showEmptyState('Order Not Found'.tr(), context));
                }
              })
          : Container(),
    );
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return AppThemeData.success500;
      case 'pending':
      case 'confirmed':
      case ORDER_STATUS_PLACED:
      case ORDER_STATUS_ACCEPTED:
      case ORDER_STATUS_SHIPPED:
      case ORDER_STATUS_IN_TRANSIT:
        return AppThemeData.warning500;
      case 'cancelled':
      case 'rejected':
        return AppThemeData.error500;
      default:
        return AppThemeData.primary500;
    }
  }

  estimateTime() async {
    double originLat, originLong, destLat, destLong;
    originLat = orderModel!.vendor.latitude;
    originLong = orderModel!.vendor.longitude;
    destLat = orderModel!.author.location.latitude;
    destLong = orderModel!.author.location.longitude;

    String url = 'https://maps.googleapis.com/maps/api/distancematrix/json';
    http.Response storeToCustomerTime =
        await http.get(Uri.parse('$url?units=metric&origins=$originLat,'
            '$originLong&destinations=$destLat,$destLong&key=$GOOGLE_API_KEY'));
    print('_OrderDetailsScreenState.estimateTime ${storeToCustomerTime.body}');
    var decodedResponse = jsonDecode(storeToCustomerTime.body);
    if (decodedResponse['status'] == 'OK' &&
        decodedResponse['rows'].first['elements'].first['status'] == 'OK') {
      int secondsFromStoreToClient =
          decodedResponse['rows'].first['elements'].first['duration']['value'];
      if (orderStatus == ORDER_STATUS_SHIPPED) {
        if (_driverModel?.location != null) {
          double driverLat = _driverModel!.location.latitude;
          double driverLong = _driverModel!.location.longitude;
          http.Response driverToStoreTime = await http.get(Uri.parse(
              '$url?units=metric&origins=$driverLat,'
              '$driverLong&destinations=$originLat,$originLong&key=$GOOGLE_API_KEY'));
          var decodedDriverToStoreTimeResponse =
              jsonDecode(driverToStoreTime.body);
          if (decodedDriverToStoreTimeResponse['status'] == 'OK' &&
              decodedDriverToStoreTimeResponse['rows']
                      .first['elements']
                      .first['status'] ==
                  'OK') {
            int secondsFromDriverToStore =
                decodedDriverToStoreTimeResponse['rows']
                    .first['elements']
                    .first['duration']['value'];
            estimatedTime = secondsFromStoreToClient + secondsFromDriverToStore;
          } else {
            estimatedTime =
                secondsFromStoreToClient + estimatedSecondsFromDriverToStore;
          }
        } else {
          estimatedTime =
              secondsFromStoreToClient + estimatedSecondsFromDriverToStore;
        }
      } else if (orderStatus == ORDER_STATUS_IN_TRANSIT) {
        estimatedTime = secondsFromStoreToClient;
      } else {
        estimatedTime =
            secondsFromStoreToClient + estimatedSecondsFromDriverToStore;
      }
      setState(() {});
      timerCountDown = Timer.periodic(
        const Duration(seconds: 1),
        (timer) {
          if (estimatedTime == 0) {
            arrivalTimeStreamController.sink.add('');
            timer.cancel();
            setState(() {});
          } else {
            estimatedTime--;
            arrivalTimeStreamController.sink.add(
              _formatArrivalTimeDuration(
                Duration(seconds: estimatedTime),
              ),
            );
          }
        },
      );
    }
  }

  String _formatArrivalTimeDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    String formattedTime =
        '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds'
            .replaceAll('00:', '');
    return formattedTime.length == 2 ? '$formattedTime Seconds' : formattedTime;
  }

  // â”€â”€ Premium UI helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildRestaurantAndItemsCard(OrderModel order) {
    final DateTime dt = order.createdAt.toDate();
    final String formattedDate = DateFormat("MMM d, yyyy â€¢ h:mm a").format(dt);
    String orderTypeLabel;
    Color badgeColor;
    IconData badgeIcon;
    if (order.orderType == "Dining") {
      orderTypeLabel = 'DineAway (Dining)';
      badgeColor = const Color(0xFF7C3AED);
      badgeIcon = Icons.restaurant_rounded;
    } else if (order.orderType == "Takeaway") {
      orderTypeLabel = 'DineAway (Takeaway)';
      badgeColor = const Color(0xFFD97706);
      badgeIcon = Icons.shopping_bag_outlined;
    } else if (order.takeAway == false) {
      orderTypeLabel = 'Delivery';
      badgeColor = AppThemeData.primary500;
      badgeIcon = Icons.delivery_dining_rounded;
    } else {
      orderTypeLabel = 'Takeaway';
      badgeColor = const Color(0xFFD97706);
      badgeIcon = Icons.shopping_bag_outlined;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // â”€â”€ Restaurant header â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppThemeData.primary500.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.storefront_rounded, color: AppThemeData.primary500, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.vendor.title,
                        style: TextStyle(
                          fontFamily: AppThemeData.semiBold,
                          fontSize: 16,
                          color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (order.vendor.location.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.location_on_outlined, size: 12, color: AppThemeData.grey500),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              () {
                                final parts = order.vendor.location.split(',');
                                return parts.length <= 2
                                    ? order.vendor.location
                                    : '${parts[0].trim()}, ${parts[1].trim()}';
                              }(),
                              style: TextStyle(fontSize: 12, color: AppThemeData.grey500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: badgeColor.withOpacity(0.45), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 12, color: badgeColor),
                            const SizedBox(width: 5),
                            Text(orderTypeLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // â”€â”€ Call + Chat (horizontal) â”€â”€
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _smallActionBtn(
                      icon: Icons.call_rounded,
                      color: AppThemeData.success400,
                      onTap: () => launch('tel:${order.vendor.phonenumber}'),
                    ),
                    const SizedBox(width: 8),
                    _smallActionBtn(
                      icon: CupertinoIcons.chat_bubble_text_fill,
                      color: AppThemeData.primary500,
                      onTap: (order.status == ORDER_STATUS_COMPLETED || order.status == ORDER_STATUS_REJECTED)
                          ? null
                          : () async {
                              await showProgress("Please wait...".tr(), false);
                              User? customer = await FireStoreUtils.getCurrentUser(order.authorID);
                              User? restaurantUser = await FireStoreUtils.getCurrentUser(order.vendor.author);
                              VendorModel? vendorModel = await FireStoreUtils.getVendor(restaurantUser!.vendorID.toString());
                              await hideProgress();
                              push(context, ChatScreens(
                                type: "vendor_chat",
                                customerName: '${customer!.firstName} ${customer.lastName}',
                                restaurantName: vendorModel!.title,
                                orderId: order.id,
                                restaurantId: restaurantUser.userID,
                                customerId: customer.userID,
                                customerProfileImage: customer.profilePictureURL,
                                restaurantProfileImage: vendorModel.photo,
                                token: restaurantUser.fcmToken,
                                chatType: 'Restaurant',
                              ));
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // â”€â”€ Order ID + date â”€â”€
          Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 13, color: AppThemeData.grey400),
                const SizedBox(width: 6),
                Text(
                  '#${order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase()}',
                  style: TextStyle(
                    fontFamily: AppThemeData.medium,
                    fontSize: 12,
                    color: isDarkMode(context) ? AppThemeData.grey400 : AppThemeData.grey600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.access_time_rounded, size: 12, color: AppThemeData.grey400),
                const SizedBox(width: 4),
                Text(formattedDate, style: TextStyle(fontFamily: AppThemeData.regular, fontSize: 11, color: AppThemeData.grey500)),
              ],
            ),
          ),
          // â”€â”€ Items â”€â”€
          Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: order.products.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
            itemBuilder: (context, index) {
              final CartProduct item = order.products[index];
              return FutureBuilder<ProductModel>(
                future: FireStoreUtils().getProductByID(item.id.split('~').first),
                builder: (context, snapshot) {
                  final bool isVeg = snapshot.data?.veg ?? false;
                  final bool isNonVeg = snapshot.data?.nonveg ?? false;

                  // Parse variant_info inside builder â€” avoids closure-capture ambiguity
                  VariantInfo? variantInfo;
                  final dynamic rawVariant = item.variant_info;
                  if (rawVariant is VariantInfo) {
                    variantInfo = rawVariant;
                  } else if (rawVariant is Map<String, dynamic>) {
                    variantInfo = VariantInfo.fromJson(rawVariant);
                  } else if (rawVariant is String && rawVariant.isNotEmpty && rawVariant != 'null') {
                    try { variantInfo = VariantInfo.fromJson(jsonDecode(rawVariant)); } catch (_) {}
                  }

                  // Parse extras inside builder
                  List<String> addons = [];
                  final dynamic rawExtras = item.extras;
                  if (rawExtras is List) {
                    addons = rawExtras
                        .map((e) => e.toString().replaceAll('"', '').replaceAll('\\', '').trim())
                        .where((s) => s.isNotEmpty && s != 'null' && s != '[]')
                        .toList();
                  } else if (rawExtras is String && rawExtras.isNotEmpty && rawExtras != '[]') {
                    addons = rawExtras
                        .replaceAll('[', '').replaceAll(']', '').replaceAll('"', '')
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Item row: [badge] name ... Ã—qty  price
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _vegBadge(isVeg: isVeg, isNonVeg: isNonVeg),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontFamily: AppThemeData.medium,
                                  fontSize: 14,
                                  color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Ã—${item.quantity}',
                              style: TextStyle(
                                fontFamily: AppThemeData.medium,
                                fontSize: 13,
                                color: AppThemeData.grey500,
                              ),
                            ),
                            const SizedBox(width: 10),
                            getPriceTotalText(item),
                          ],
                        ),
                        // Customization chips â€” variants + add-ons unified
                        if ((variantInfo?.variant_options?.isNotEmpty ?? false) || addons.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Padding(
                            padding: const EdgeInsets.only(left: 23),
                            child: Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                if (variantInfo?.variant_options?.isNotEmpty ?? false)
                                  ...variantInfo!.variant_options!.entries.map((e) =>
                                    _buildChip('${e.key}: ${e.value}', e.key.hashCode)),
                                ...addons.asMap().entries.map((e) =>
                                  _buildChip(e.value, e.key + 100)),
                              ],
                            ),
                          ),
                        ],
                        // Digital download
                        if (snapshot.hasData && snapshot.data!.isDigitalProduct == true && order.status == ORDER_STATUS_COMPLETED) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 23),
                            child: GestureDetector(
                              onTap: () async {
                                await Permission.storage.request();
                                await Permission.manageExternalStorage.request();
                                var storageStatus = await Permission.storage.status;
                                var externalStatus = await Permission.manageExternalStorage.status;
                                if (storageStatus.isGranted || externalStatus.isGranted) {
                                  await showProgress("Please wait...".tr(), false);
                                  _downloadFile(snapshot.data!.digitalProduct.toString(), getFileName(snapshot.data!.digitalProduct.toString()));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppThemeData.primary500.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.download_for_offline_outlined, size: 15, color: AppThemeData.primary500),
                                  const SizedBox(width: 5),
                                  Text('Download'.tr(), style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 12, color: AppThemeData.primary500)),
                                ]),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _smallActionBtn({required IconData icon, required Color color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.15) : (isDarkMode(context) ? AppThemeData.darkBgTertiary : AppThemeData.grey100),
          shape: BoxShape.circle,
          border: Border.all(
            color: onTap != null ? color.withOpacity(0.45) : AppThemeData.grey300,
            width: 1.5,
          ),
        ),
        child: Icon(icon, size: 18, color: onTap != null ? color : AppThemeData.grey400),
      ),
    );
  }

  Widget _vegBadge({required bool isVeg, required bool isNonVeg}) {
    Color borderColor;
    Color dotColor;
    if (isVeg) {
      borderColor = const Color(0xFF27AE60);
      dotColor = const Color(0xFF27AE60);
    } else if (isNonVeg) {
      borderColor = const Color(0xFFC0392B);
      dotColor = const Color(0xFFC0392B);
    } else {
      borderColor = AppThemeData.grey300;
      dotColor = AppThemeData.grey400;
    }
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildStatusCard(OrderModel order) {
    final bool isDineAway = order.orderType == "Dining" || order.orderType == "Takeaway";
    String statusTitle;
    String statusSubtitle;
    Color statusColor;
    IconData statusIcon;
    switch (order.status) {
      case ORDER_STATUS_PLACED:
        statusTitle = 'Order Placed'.tr();
        statusSubtitle = 'Waiting for restaurant responseâ€¦'.tr();
        statusColor = const Color(0xFF3B82F6);
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case ORDER_STATUS_ACCEPTED:
        statusTitle = 'Preparing Your Order'.tr();
        statusSubtitle = isDineAway ? 'Your order will be ready soon'.tr() : 'Getting your order ready for pickup'.tr();
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.restaurant_menu_rounded;
        break;
      case ORDER_STATUS_REJECTED:
        statusTitle = 'Order Rejected'.tr();
        statusSubtitle = 'The restaurant could not accept your order'.tr();
        statusColor = AppThemeData.danger300;
        statusIcon = Icons.cancel_outlined;
        break;
      case ORDER_STATUS_DRIVER_PENDING:
      case ORDER_STATUS_DRIVER_REJECTED:
        statusTitle = 'Ready â€“ Finding Driver'.tr();
        statusSubtitle = 'Your food is ready, locating a driverâ€¦'.tr();
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.delivery_dining_rounded;
        break;
      case ORDER_STATUS_SHIPPED:
        statusTitle = 'Driver On the Way'.tr();
        statusSubtitle = '${order.driver?.firstName ?? "Your driver"} is heading to pick up your order'.tr();
        statusColor = AppThemeData.primary500;
        statusIcon = Icons.directions_bike_rounded;
        break;
      case ORDER_STATUS_IN_TRANSIT:
        statusTitle = 'Out for Delivery'.tr();
        statusSubtitle = 'Your order is on the way to you!'.tr();
        statusColor = AppThemeData.primary500;
        statusIcon = Icons.local_shipping_outlined;
        break;
      case ORDER_STATUS_COMPLETED:
        statusTitle = isDineAway ? 'Order Ready'.tr() : 'Order Delivered'.tr();
        statusSubtitle = isDineAway ? 'Enjoy your meal!'.tr() : 'Your order has been delivered'.tr();
        statusColor = AppThemeData.success400;
        statusIcon = Icons.check_circle_rounded;
        break;
      default:
        statusTitle = order.status.tr();
        statusSubtitle = currentEvent;
        statusColor = AppThemeData.primary500;
        statusIcon = Icons.info_outline_rounded;
    }
    final List<String> steps = isDineAway
        ? ['Placed', 'Preparing', 'Ready']
        : ['Placed', 'Preparing', 'Driver', 'Delivered'];
    int currentStep;
    switch (order.status) {
      case ORDER_STATUS_PLACED:      currentStep = 0; break;
      case ORDER_STATUS_ACCEPTED:    currentStep = 1; break;
      case ORDER_STATUS_DRIVER_PENDING:
      case ORDER_STATUS_DRIVER_REJECTED: currentStep = 1; break;
      case ORDER_STATUS_SHIPPED:     currentStep = 2; break;
      case ORDER_STATUS_IN_TRANSIT:  currentStep = isDineAway ? 2 : 3; break;
      case ORDER_STATUS_COMPLETED:   currentStep = isDineAway ? 2 : 3; break;
      default:                       currentStep = 0;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Status banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: TextStyle(
                          fontFamily: AppThemeData.semiBold,
                          fontSize: 15,
                          color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        statusSubtitle,
                        style: TextStyle(
                          fontFamily: AppThemeData.regular,
                          fontSize: 13,
                          color: isDarkMode(context)
                              ? statusColor.withOpacity(0.85)
                              : statusColor.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Prep time tile
          if ((order.status == ORDER_STATUS_ACCEPTED ||
               order.status == ORDER_STATUS_DRIVER_PENDING ||
               order.status == ORDER_STATUS_DRIVER_REJECTED) &&
              order.estimatedTimeToPrepare != null &&
              order.estimatedTimeToPrepare!.isNotEmpty &&
              sectionConstantModel!.serviceTypeFlag != "ecommerce-service") ...[
            Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: lottie.Lottie.asset(
                      isDarkMode(context) ? 'assets/images/chef_dark_bg.json' : 'assets/images/chef_light_bg.json',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estimated Prep Time'.tr(), style: TextStyle(fontSize: 11, color: AppThemeData.grey500)),
                      const SizedBox(height: 4),
                      Text(
                        '${order.estimatedTimeToPrepare}${int.parse(order.estimatedTimeToPrepare!.split(":").first) == 0 ? " mins" : " hr"}',
                        style: const TextStyle(
                          fontFamily: AppThemeData.semiBold,
                          fontSize: 24,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // Progress step indicator
          if (order.status != ORDER_STATUS_REJECTED) ...[
            Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  for (int i = 0; i < steps.length; i++) ...[
                    Column(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: i <= currentStep
                                ? AppThemeData.primary500
                                : (isDarkMode(context) ? AppThemeData.darkBgTertiary : AppThemeData.neutral200),
                            shape: BoxShape.circle,
                          ),
                          child: i <= currentStep
                              ? const Icon(Icons.check, color: Colors.white, size: 13)
                              : Center(child: Text('${i + 1}', style: TextStyle(fontSize: 10, color: AppThemeData.grey500))),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          width: 54,
                          child: Text(
                            steps[i].tr(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: i <= currentStep ? FontWeight.w700 : FontWeight.w400,
                              color: i <= currentStep ? AppThemeData.primary500 : AppThemeData.grey400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: i < currentStep
                                ? AppThemeData.primary500
                                : (isDarkMode(context) ? AppThemeData.darkBgTertiary : AppThemeData.neutral200),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackCard(OrderModel order) {
    return GestureDetector(
      onTap: () => push(context, OrderTrackingScreen(orderModel: order)),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppThemeData.primary500.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.map_rounded, color: AppThemeData.primary500, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track Your Order'.tr(),
                    style: TextStyle(
                      fontFamily: AppThemeData.semiBold,
                      fontSize: 14,
                      color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('See driver location in real-time'.tr(), style: TextStyle(fontSize: 11, color: AppThemeData.grey500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppThemeData.primary500),
          ],
        ),
      ),
    );
  }

  Widget buildDeliveryDetailsCard(OrderModel orderModel) {
    DateTime dateTime = orderModel.createdAt.toDate();
    String formattedDate = DateFormat("MMM d, yyyy 'at' h:mm a").format(dateTime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode(context) ? const Color(DARK_BG_COLOR) : Colors.white,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              orderModel.takeAway == false
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          minVerticalPadding:
                              0, // reduce extra vertical padding
                          leading: UserAvatar(name: orderModel.author.fullName() ?? "Avatar", radius: 30),
                          // CachedNetworkImage(
                          //     height: 55,
                          //     width: 55,
                          //     imageUrl: getImageVAlidUrl(
                          //         orderModel.author.profilePictureURL),
                          //     imageBuilder: (context, imageProvider) =>
                          //         Container(
                          //           decoration: BoxDecoration(
                          //               borderRadius: BorderRadius.circular(30),
                          //               image: DecorationImage(
                          //                 image: imageProvider,
                          //                 fit: BoxFit.cover,
                          //               )),
                          //         ),
                          //     errorWidget: (context, url, error) => ClipRRect(
                          //         borderRadius: BorderRadius.circular(15),
                          //         child: Image.network(
                          //           placeholderImage,
                          //           fit: BoxFit.cover,
                          //           width: MediaQuery.of(context).size.width,
                          //           height: MediaQuery.of(context).size.height,
                          //         ))),
                          title: Text(
                            orderModel.author.firstName,
                            style: TextStyle(
                              fontSize: 18,
                              letterSpacing: 0.5,
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : const Color(0XFF000000),
                            ),
                          ),
                          subtitle: Text(
                            orderModel.author.phoneNumber.length > 6
                                ? "XXXXXX" +
                                    orderModel.author.phoneNumber.substring(6)
                                : orderModel.author.phoneNumber,
                            style: TextStyle(
                              fontSize: 14,
                              letterSpacing: 0.5,
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Colors.black45,
                            ),
                          ),
                        ),
                        Divider(thickness: 1.5),
                        // const SizedBox(height: 16),
                        ListTile(
                          dense: true,
                          // makes it more compact
                          minVerticalPadding: 0,
                          // reduce extra vertical padding
                          visualDensity: VisualDensity.compact,
                          // shrinks overall density
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                          leading: Icon(Icons.payment),
                          title: Text(
                            "Payment Method",
                            style: TextStyle(
                                fontSize: 17,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.black),
                          ),
                          subtitle: Text(
                            "Paid via: ${orderModel.payment_method}",
                            style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.grey.shade700),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          // makes it more compact
                          minVerticalPadding: 0,
                          // reduce extra vertical padding
                          visualDensity: VisualDensity.compact,
                          // shrinks overall density
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                          leading: Icon(Icons.edit_calendar),
                          title: Text(
                            "Payment Date",
                            style: TextStyle(
                                fontSize: 17,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.black),
                          ),
                          subtitle: Text(
                            formattedDate,
                            style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.grey.shade700),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          // makes it more compact
                          minVerticalPadding: 0,
                          // reduce extra vertical padding
                          visualDensity: VisualDensity.compact,
                          // shrinks overall density
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                          leading: Icon(Icons.location_on_outlined),
                          title: Text(
                            "Delivery Address".tr(),
                            style: TextStyle(
                                fontSize: 17,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.black),
                          ),
                          subtitle: Text(
                            orderModel.address!.getFullAddress(),
                            style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.grey.shade700),
                          ),
                        ),
                      ],
                    )
                  : Container(),
              ListTile(
                dense: true,
                // makes it more compact
                minVerticalPadding: 0,
                // reduce extra vertical padding
                visualDensity: VisualDensity.compact,
                // shrinks overall density
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                leading: Icon(Icons.bookmark_border),
                title: Text(
                  "Order Type".tr(),
                  style: TextStyle(
                      fontSize: 17,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode(context)
                          ? Colors.grey.shade200
                          : Colors.black),
                ),
                subtitle: (orderModel.orderType != null && orderModel.orderType!.isNotEmpty)
                    ? Text(
                        orderModel.orderType == "Dining"
                            ? 'Type : Dineaway (Dining)'.tr()
                            : orderModel.orderType == "Takeaway"
                                ? 'Type : Dineaway (Takeaway)'.tr()
                                : 'Type : Takeaway'.tr(),
                        style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode(context)
                                ? Colors.grey.shade200
                                : Colors.grey.shade700),
                      )
                    : orderModel.takeAway == false
                        ? Text(
                            'Type : Deliver to door'.tr(),
                            style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.grey.shade700),
                          )
                        : Text(
                            'Type : Takeaway'.tr(),
                            style: TextStyle(
                                fontSize: 13,
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade200
                                    : Colors.grey.shade700),
                          ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildOrderSummaryCard(OrderModel orderModel) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.shopping_bag_outlined, size: 18, color: AppThemeData.primary500),
                const SizedBox(width: 8),
                Text(
                  'Your Order'.tr(),
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    fontSize: 15,
                    color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const Spacer(),
                Text(
                  '${orderModel.products.length} ${"items".tr()}',
                  style: TextStyle(fontSize: 12, color: AppThemeData.grey500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: orderModel.products.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
            itemBuilder: (context, index) {
              final CartProduct item = orderModel.products[index];
              // Parse variant_info defensively from dynamic field
              VariantInfo? variantIno;
              final dynamic rawVi2 = item.variant_info;
              if (rawVi2 is VariantInfo) {
                variantIno = rawVi2;
              } else if (rawVi2 is Map<String, dynamic>) {
                variantIno = VariantInfo.fromJson(rawVi2);
              } else if (rawVi2 is String &&
                  rawVi2.isNotEmpty &&
                  rawVi2 != 'null') {
                try {
                  variantIno = VariantInfo.fromJson(jsonDecode(rawVi2));
                } catch (_) {}
              }
              // Parse extras defensively from dynamic field
              List<String> addon = [];
              final dynamic rawExtras2 = item.extras;
              if (rawExtras2 is List) {
                addon = rawExtras2
                    .map((e) =>
                        e.toString().replaceAll('"', '').replaceAll('\\', '').trim())
                    .where((s) => s.isNotEmpty && s != 'null' && s != '[]')
                    .toList();
              } else if (rawExtras2 is String &&
                  rawExtras2.isNotEmpty &&
                  rawExtras2 != '[]') {
                final cleaned = rawExtras2
                    .replaceAll('[', '')
                    .replaceAll(']', '')
                    .replaceAll('"', '');
                addon = cleaned
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
              return FutureBuilder<ProductModel>(
                future: FireStoreUtils().getProductByID(item.id),
                builder: (context, snapshot) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppThemeData.primary500.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(
                                child: Text(
                                  '${item.quantity}',
                                  style: TextStyle(
                                    fontFamily: AppThemeData.semiBold,
                                    fontSize: 13,
                                    color: AppThemeData.primary500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontFamily: AppThemeData.medium,
                                  fontSize: 14,
                                  color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            getPriceTotalText(item),
                            if (snapshot.hasData && snapshot.data!.isDigitalProduct == true && orderModel.status == ORDER_STATUS_COMPLETED) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  await Permission.storage.request();
                                  await Permission.manageExternalStorage.request();
                                  var status = await Permission.storage.status;
                                  var manageExternalStorage = await Permission.manageExternalStorage.status;
                                  if (status.isGranted) {
                                    await showProgress("Please wait...".tr(), false);
                                    _downloadFile(snapshot.data!.digitalProduct.toString(), getFileName(snapshot.data!.digitalProduct.toString()));
                                  }
                                  if (manageExternalStorage.isGranted) {
                                    await showProgress("Please wait...".tr(), false);
                                    _downloadFile(snapshot.data!.digitalProduct.toString(), getFileName(snapshot.data!.digitalProduct.toString()));
                                  }
                                },
                                child: Icon(Icons.download_for_offline_outlined, size: 22, color: AppThemeData.primary500),
                              ),
                            ],
                          ],
                        ),
                        if ((variantIno?.variant_options?.isNotEmpty ?? false) || addon.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Builder(builder: (context) {
                            final List<String> parts = [
                              if (variantIno?.variant_options?.isNotEmpty ?? false)
                                ...variantIno!.variant_options!.entries
                                    .map((e) => '${e.key}: ${e.value}'),
                              ...addon,
                            ];
                            return Text(
                              parts.join(' Â· '),
                              style: TextStyle(fontSize: 12, color: AppThemeData.grey500),
                            );
                          }),
                        ],
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () async {
                            await showProgress("Please wait...".tr(), false);
                            ProductModel? productModel;
                            await FireStoreUtils().getProductByID(item.id).then((value) { productModel = value; });
                            if (productModel!.itemAttributes != null) {
                              if (productModel!.itemAttributes!.variants!.where((element) => element.variant_sku == variantIno?.variant_sku).isNotEmpty) {
                                if (int.parse(productModel!.itemAttributes!.variants!.where((element) => element.variant_sku == variantIno?.variant_sku).first.variant_quantity.toString()) >= item.quantity) {
                                  cartDatabase.reAddProduct(CartProduct(id: item.id + "~" + (variantIno != null ? variantIno.variant_id.toString() : ""), name: item.name, photo: item.photo, price: item.price, discountPrice: item.discountPrice, vendorID: item.vendorID, quantity: item.quantity, extras_price: item.extras_price, extras: item.extras, category_id: item.category_id, variant_info: variantIno));
                                  await hideProgress();
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product is added in cart".tr())));
                                } else {
                                  await hideProgress();
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product is out of Stock".tr())));
                                }
                              } else {
                                if (productModel!.quantity >= item.quantity || productModel!.quantity == -1) {
                                  cartDatabase.reAddProduct(CartProduct(id: item.id + "~" + (variantIno != null ? variantIno.variant_id.toString() : ""), name: item.name, photo: item.photo, price: item.price, discountPrice: item.discountPrice, vendorID: item.vendorID, quantity: item.quantity, extras_price: item.extras_price, extras: item.extras, category_id: item.category_id, variant_info: variantIno));
                                  await hideProgress();
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product is added in cart".tr())));
                                } else {
                                  await hideProgress();
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product is out of Stock".tr())));
                                }
                              }
                            } else {
                              List<CartProduct> cartProducts = await cartDatabase.allCartProducts;
                              if (productModel!.quantity >= item.quantity || productModel!.quantity == -1) {
                                final bool productIsInList = cartProducts.any((product) => product.id == productModel!.id + "~" + (productModel!.variant_info != null ? productModel!.variant_info!.variant_id.toString() : ""));
                                if (productIsInList) {
                                  CartProduct element = cartProducts.firstWhere((product) => product.id == productModel!.id + "~" + (productModel!.variant_info != null ? productModel!.variant_info!.variant_id.toString() : ""));
                                  await cartDatabase.updateProduct(CartProduct(id: element.id, name: element.name, photo: element.photo, price: element.price, vendorID: element.vendorID, quantity: element.quantity + element.quantity, category_id: element.category_id, extras_price: element.extras_price, extras: element.extras, discountPrice: element.discountPrice));
                                } else {
                                  cartDatabase.reAddProduct(CartProduct(id: item.id + "~" + (variantIno != null ? variantIno.variant_id.toString() : ""), name: item.name, photo: item.photo, price: item.price, discountPrice: item.discountPrice, vendorID: item.vendorID, quantity: item.quantity, extras_price: item.extras_price, extras: item.extras, category_id: item.category_id, variant_info: variantIno));
                                }
                                await hideProgress();
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product is added in cart".tr())));
                              } else {
                                await hideProgress();
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Product is out of Stock".tr())));
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                width: 1,
                                color: isDarkMode(context) ? AppThemeData.darkBgTertiary : AppThemeData.neutral200,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Reorder'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode(context) ? Colors.white : AppThemeData.grey700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget buildBillSummaryCard(OrderModel orderModel) {
    double tipValue = orderModel.tipValue!.isEmpty ? 0.0 : double.parse(orderModel.tipValue!);
    double specialDiscountAmount = 0.0;
    if (orderModel.specialDiscount!.isNotEmpty) {
      specialDiscountAmount = double.parse(orderModel.specialDiscount!['special_discount'].toString());
    }
    List<TaxModel> taxesToDisplay = [];
    double totalTaxAmount = 0.0;
    if (orderModel.taxModel != null) {
      for (var element in orderModel.taxModel!) {
        bool shouldApplyTax = (orderModel.takeAway == false && (element.isTakeaway == false || element.isTakeaway == null)) ||
            (orderModel.takeAway == true && element.isTakeaway == true);
        if (shouldApplyTax) {
          double taxAmount = getTaxValue(amount: (total - discount - specialDiscountAmount).toString(), taxModel: element);
          totalTaxAmount += taxAmount;
          taxesToDisplay.add(element);
        }
      }
    }
    var totalamount = orderModel.deliveryCharge == null || orderModel.deliveryCharge!.isEmpty
        ? total + totalTaxAmount - discount - specialDiscountAmount
        : total + totalTaxAmount + double.parse(orderModel.deliveryCharge!) + tipValue - discount - specialDiscountAmount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: AppThemeData.primary500),
                const SizedBox(width: 8),
                Text(
                  'Bill Details'.tr(),
                  style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 15, color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
          _billRow('Subtotal'.tr(), amountShow(amount: total.toString())),
          if (orderModel.vendor.specialDiscountEnable &&
              orderModel.specialDiscount != null &&
              orderModel.specialDiscount!.isNotEmpty &&
              double.parse(orderModel.specialDiscount!['special_discount'].toString()) > 0)
            _billRow('Special Discount'.tr(), '- ${amountShow(amount: orderModel.specialDiscount!['special_discount'].toString())}', valueColor: AppThemeData.primary500),
          if ((double.tryParse(discount.toString()) ?? 0.0) > 0.0)
            _billRow('Discount'.tr(), '- ${amountShow(amount: discount.toString())}', valueColor: AppThemeData.primary500),
          if (orderModel.takeAway == false && (double.tryParse(orderModel.deliveryCharge.toString()) ?? 0.0) > 0.0)
            _billRow('Delivery Charges'.tr(), orderModel.deliveryCharge == null ? amountShow(amount: "0") : amountShow(amount: orderModel.deliveryCharge!)),
          if (orderModel.takeAway == false && (double.tryParse(orderModel.tipValue.toString()) ?? 0.0) > 0.0)
            _billRow('Tip Amount'.tr(), orderModel.tipValue!.isEmpty ? amountShow(amount: "0.0") : amountShow(amount: orderModel.tipValue)),
          ListView.builder(
            itemCount: taxesToDisplay.length,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              TaxModel taxModel = taxesToDisplay[index];
              return _billRow(
                taxModel.title ?? 'Tax',
                amountShow(amount: getTaxValue(amount: (double.parse(total.toString()) - discount - specialDiscountAmount).toString(), taxModel: taxModel).toString()),
              );
            },
          ),
          if (orderModel.notes != null && orderModel.notes!.isNotEmpty)
            _billRow(
              'Remarks'.tr(),
              '',
              trailingWidget: GestureDetector(
                onTap: () => showModalBottomSheet(
                  isScrollControlled: true,
                  isDismissible: true,
                  context: context,
                  backgroundColor: Colors.transparent,
                  enableDrag: true,
                  builder: (ctx) => viewNotesheet(orderModel.notes!),
                ),
                child: Text('View'.tr(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeData.primary500)),
              ),
            ),
          if (orderModel.couponCode!.trim().isNotEmpty)
            _billRow('Coupon Code'.tr(), orderModel.couponCode!),
          Divider(height: 1, color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xFFF0F0F5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order Total'.tr(), style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 15, color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E))),
                Text(amountShow(amount: totalamount.toString()), style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 15, color: AppThemeData.primary500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _billRow(String label, String value, {Color? valueColor, Widget? trailingWidget}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDarkMode(context) ? AppThemeData.darkTextSecondary : AppThemeData.grey600)),
          trailingWidget ?? Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? (isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E)),
            ),
          ),
        ],
      ),
    );
  }

  // Widget buildOrderSummaryCard() {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //     child: Card(
  //       color: isDarkMode(context) ? Colors.grey.shade900 : Colors.white,
  //       child: Padding(
  //         padding: const EdgeInsets.all(16.0),
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Text(
  //               'Order Summary'.tr(),
  //               style: TextStyle(
  //                    fontFamily: AppThemeData.semiBold
  //                   fontSize: 20,
  //                   color: isDarkMode(context)
  //                       ? Colors.grey.shade200
  //                       : Colors.grey.shade700),
  //             ),
  //             SizedBox(height: 16),
  //             Text(
  //               '${widget.orderModel.vendor.title}',
  //               style: TextStyle(
  //                   fontWeight: FontWeight.w400,
  //                    fontSize: 16,
  //                   color: isDarkMode(context)
  //                       ? Colors.grey.shade200
  //                       : Colors.grey.shade700),
  //             ),
  //             SizedBox(height: 16),
  //             ListView.builder(
  //               physics: NeverScrollableScrollPhysics(),
  //               shrinkWrap: true,
  //               itemCount: widget.orderModel.products.length,
  //               itemBuilder: (context, index) => Padding(
  //                 padding: EdgeInsets.symmetric(vertical: 12),
  //                 child: Row(
  //                   children: [
  //                     Container(
  //                       color: isDarkMode(context)
  //                           ? Colors.grey.shade700
  //                           : Colors.grey.shade200,
  //                       padding: EdgeInsets.all(6),
  //                       child: Text(
  //                         '${widget.orderModel.products[index].quantity}',
  //                         style: TextStyle(
  //                             fontSize: 18, fontWeight: FontWeight.bold),
  //                       ),
  //                     ),
  //                     SizedBox(width: 16),
  //                     Text(
  //                       '${widget.orderModel.products[index].name}',
  //                       style: TextStyle(
  //                           color: isDarkMode(context)
  //                               ? Colors.grey.shade300
  //                               : Colors.grey.shade800,
  //                           fontWeight: FontWeight.w500,
  //                           fontSize: 18),
  //                     )
  //                   ],
  //                 ),
  //               ),
  //             ),
  //             SizedBox(height: 16),
  //             ListTile(
  //               title: Text(
  //                 'Total'.tr(),
  //                 style: TextStyle(
  //                   fontSize: 25,
  //                    fontFamily: AppThemeData.semiBold
  //                   color: isDarkMode(context)
  //                       ? Colors.grey.shade300
  //                       : Colors.grey.shade700,
  //                 ),
  //               ),
  //               trailing: Text(
  //                 '\$${total.toStringAsFixed(decimal)}',
  //                 style: TextStyle(
  //                   fontSize: 25,
  //                   fontWeight: FontWeight.w400,
  //                   color: isDarkMode(context)
  //                       ? Colors.grey.shade300
  //                       : Colors.grey.shade700,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  BitmapDescriptor? departureIcon;
  BitmapDescriptor? destinationIcon;
  BitmapDescriptor? taxiIcon;

  void setMarkerIcon() async {
    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(
              size: Size(10, 10),
            ),
            "assets/images/pickup.png")
        .then((value) {
      departureIcon = value;
    });

    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(
              size: Size(10, 10),
            ),
            "assets/images/dropoff.png")
        .then((value) {
      destinationIcon = value;
    });

    BitmapDescriptor.fromAssetImage(
            const ImageConfiguration(
              size: Size(10, 10),
            ),
            "assets/images/ic_taxi.png")
        .then((value) {
      taxiIcon = value;
    });
  }

  Map<PolylineId, Polyline> polyLines = {};
  PolylinePoints polylinePoints = PolylinePoints();
  final Map<String, Marker> _markers = {};

  late Stream<User> driverStream;
  User? _driverModel = User();

  getDriver() async {
    driverStream =
        FireStoreUtils().getDriver(currentOrder!.driverID.toString());
    driverStream.listen((event) {
      _driverModel = event;
      getDirections();
      setState(() {});
    });
  }

  late Stream<OrderModel?> ordersFuture;
  OrderModel? currentOrder;

  getCurrentOrder() async {
    ordersFuture = FireStoreUtils().getOrderByID(orderModel!.id);
    ordersFuture.listen((event) {
      if (event == null) return;
      print("----?${event.driverID}");
      setState(() {
        currentOrder = event;
        if (event.driverID != null) {
          getDriver();
        }
      });
    });
  }

  getDirections() async {
    if (currentOrder != null) {
      if (currentOrder!.status == ORDER_STATUS_SHIPPED) {
        List<LatLng> polylineCoordinates = [];

        PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
          googleApiKey: GOOGLE_API_KEY,
          request: PolylineRequest(
              origin: PointLatLng(_driverModel!.location.latitude,
                  _driverModel!.location.longitude),
              destination: PointLatLng(currentOrder!.vendor.latitude,
                  currentOrder!.vendor.longitude),
              mode: TravelMode.driving),
        );

        print("----?${result.points}");
        if (result.points.isNotEmpty) {
          for (var point in result.points) {
            polylineCoordinates.add(LatLng(point.latitude, point.longitude));
          }
        }
        setState(() {
          _markers.remove("Driver");
          _markers['Driver'] = Marker(
              markerId: const MarkerId('Driver'),
              infoWindow: const InfoWindow(title: "Driver"),
              position: LatLng(_driverModel!.location.latitude,
                  _driverModel!.location.longitude),
              icon: taxiIcon!,
              rotation: double.parse(_driverModel!.rotation.toString()));
        });

        _markers.remove("Destination");
        _markers['Destination'] = Marker(
          markerId: const MarkerId('Destination'),
          infoWindow: const InfoWindow(title: "Destination"),
          position: LatLng(
              currentOrder!.vendor.latitude, currentOrder!.vendor.longitude),
          icon: destinationIcon!,
        );
        addPolyLine(polylineCoordinates);
      } else if (currentOrder!.status == ORDER_STATUS_IN_TRANSIT) {
        List<LatLng> polylineCoordinates = [];

        PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
          googleApiKey: GOOGLE_API_KEY,
          request: PolylineRequest(
              origin: PointLatLng(_driverModel!.location.latitude,
                  _driverModel!.location.longitude),
              destination: PointLatLng(
                  currentOrder!.address!.location!.latitude,
                  currentOrder!.address!.location!.longitude),
              mode: TravelMode.driving),
        );

        print("----?${result.points}");
        if (result.points.isNotEmpty) {
          for (var point in result.points) {
            polylineCoordinates.add(LatLng(point.latitude, point.longitude));
          }
        }
        setState(() {
          _markers.remove("Driver");
          _markers['Driver'] = Marker(
            markerId: const MarkerId('Driver'),
            infoWindow: const InfoWindow(title: "Driver"),
            position: LatLng(_driverModel!.location.latitude,
                _driverModel!.location.longitude),
            rotation: double.parse(_driverModel!.rotation.toString()),
            icon: taxiIcon!,
          );
        });

        _markers.remove("Destination");
        _markers['Destination'] = Marker(
          markerId: const MarkerId('Destination'),
          infoWindow: const InfoWindow(title: "Destination"),
          position: LatLng(currentOrder!.address!.location!.latitude,
              currentOrder!.address!.location!.longitude),
          icon: destinationIcon!,
        );
        addPolyLine(polylineCoordinates);
      }
    }
  }

  addPolyLine(List<LatLng> polylineCoordinates) {
    PolylineId id = const PolylineId("poly");
    Polyline polyline = Polyline(
      polylineId: id,
      color: AppThemeData.primary500,
      points: polylineCoordinates,
      width: 4,
      geodesic: true,
    );
    polyLines[id] = polyline;
    updateCameraLocation(
        polylineCoordinates.first, polylineCoordinates.last, _mapController);
    setState(() {});
  }

  Future<void> updateCameraLocation(
    LatLng source,
    LatLng destination,
    GoogleMapController? mapController,
  ) async {
    if (mapController == null) return;

    LatLngBounds bounds;

    if (source.latitude > destination.latitude &&
        source.longitude > destination.longitude) {
      bounds = LatLngBounds(southwest: destination, northeast: source);
    } else if (source.longitude > destination.longitude) {
      bounds = LatLngBounds(
          southwest: LatLng(source.latitude, destination.longitude),
          northeast: LatLng(destination.latitude, source.longitude));
    } else if (source.latitude > destination.latitude) {
      bounds = LatLngBounds(
          southwest: LatLng(destination.latitude, source.longitude),
          northeast: LatLng(source.latitude, destination.longitude));
    } else {
      bounds = LatLngBounds(southwest: source, northeast: destination);
    }

    CameraUpdate cameraUpdate = CameraUpdate.newLatLngBounds(bounds, 100);

    return checkCameraLocation(cameraUpdate, mapController);
  }

  Future<void> checkCameraLocation(
      CameraUpdate cameraUpdate, GoogleMapController mapController) async {
    mapController.animateCamera(cameraUpdate);
    LatLngBounds l1 = await mapController.getVisibleRegion();
    LatLngBounds l2 = await mapController.getVisibleRegion();

    if (l1.southwest.latitude == -90 || l2.southwest.latitude == -90) {
      return checkCameraLocation(cameraUpdate, mapController);
    }
  }

  Widget buildDeliveryMap(OrderModel orderModel) {
    return SizedBox(
      height: MediaQuery.of(context).size.height / 2.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0.0),
          ),
          child: GoogleMap(
            onMapCreated: _onMapCreated,
            myLocationEnabled: false,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            zoomControlsEnabled: true,
            polylines: Set<Polyline>.of(polyLines.values),
            markers: _markers.values.toSet(),
            initialCameraPosition: CameraPosition(
              zoom: 15,
              target: LatLng(currentOrder!.vendor.latitude,
                  currentOrder!.vendor.longitude),
            ),
          ),
        ),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (isDarkMode(context)) {
      _mapController!.setMapStyle('[{"featureType": "all","'
          'elementType": "'
          'geo'
          'met'
          'ry","stylers": [{"color": "#242f3e"}]},{"featureType": "all","elementType": "labels.text.stroke","stylers": [{"lightness": -80}]},{"featureType": "administrative","elementType": "labels.text.fill","stylers": [{"color": "#746855"}]},{"featureType": "administrative.locality","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "poi","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "poi.park","elementType": "geometry","stylers": [{"color": "#263c3f"}]},{"featureType": "poi.park","elementType": "labels.text.fill","stylers": [{"color": "#6b9a76"}]},{"featureType": "road","elementType": "geometry.fill","stylers": [{"color": "#2b3544"}]},{"featureType": "road","elementType": "labels.text.fill","stylers": [{"color": "#9ca5b3"}]},{"featureType": "road.arterial","elementType": "geometry.fill","stylers": [{"color": "#38414e"}]},{"featureType": "road.arterial","elementType": "geometry.stroke","stylers": [{"color": "#212a37"}]},{"featureType": "road.highway","elementType": "geometry.fill","stylers": [{"color": "#746855"}]},{"featureType": "road.highway","elementType": "geometry.stroke","stylers": [{"color": "#1f2835"}]},{"featureType": "road.highway","elementType": "labels.text.fill","stylers": [{"color": "#f3d19c"}]},{"featureType": "road.local","elementType": "geometry.fill","stylers": [{"color": "#38414e"}]},{"featureType": "road.local","elementType": "geometry.stroke","stylers": [{"color": "#212a37"}]},{"featureType": "transit","elementType": "geometry","stylers": [{"color": "#2f3948"}]},{"featureType": "transit.station","elementType": "labels.text.fill","stylers": [{"color": "#d59563"}]},{"featureType": "water","elementType": "geometry","stylers": [{"color": "#17263c"}]},{"featureType": "water","elementType": "labels.text.fill","stylers": [{"color": "#515c6d"}]},{"featureType": "water","elementType": "labels.text.stroke","stylers": [{"lightness": -20}]}]');
    }
    if (orderStatus == ORDER_STATUS_IN_TRANSIT) {
      updateCameraLocation(vendorLocation!, userLocation!, _mapController);
    } else if (orderStatus == ORDER_STATUS_SHIPPED) {
      updateCameraLocation(
          LatLng(_driverModel?.location.latitude ?? 0,
              _driverModel!.location.longitude),
          vendorLocation!,
          _mapController);
    } else if (orderStatus == ORDER_STATUS_ACCEPTED && isTakeAway) {
      updateCameraLocation(vendorLocation!, userLocation!, _mapController);
    }
  }

  Widget buildDriverCard(OrderModel order) {
    if (sectionConstantModel!.serviceTypeFlag == "ecommerce-service") {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Courier Details'.tr(), style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 13, color: AppThemeData.grey500)),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.local_shipping_outlined, size: 16, color: AppThemeData.grey500),
              const SizedBox(width: 8),
              Text(order.courierCompanyName, style: TextStyle(fontSize: 14, color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.numbers_rounded, size: 16, color: AppThemeData.grey500),
              const SizedBox(width: 8),
              Text(order.courierTrackingId, style: TextStyle(fontSize: 13, color: AppThemeData.grey500)),
            ]),
          ],
        ),
      );
    }

    final String initials = order.driver != null && order.driver!.firstName.isNotEmpty
        ? order.driver!.firstName.substring(0, 1).toUpperCase()
        : 'D';
    final String driverName = order.driver != null
        ? '${order.driver!.firstName} ${order.driver!.lastName ?? ""}'.trim()
        : 'Your Driver'.tr();
    final String carInfo = [order.driver?.carName, order.driver?.carNumber].where((s) => s != null && s!.isNotEmpty).join(' Â· ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.darkBgPrimary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Driver'.tr(), style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 13, color: AppThemeData.grey500)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppThemeData.primary500, AppThemeData.primary400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 15, color: isDarkMode(context) ? Colors.white : const Color(0xFF1A1A2E)),
                    ),
                    if (carInfo.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(carInfo, style: TextStyle(fontSize: 12, color: AppThemeData.grey500)),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: order.driver == null ? null : () => launch('tel:${order.driver!.phoneNumber}'),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppThemeData.success400.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(Icons.call_rounded, color: AppThemeData.success400, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: order.driver == null
                    ? null
                    : () async {
                        await showProgress("Please wait...".tr(), false);
                        User? customer = await FireStoreUtils.getCurrentUser(orderModel!.authorID);
                        User? driver = await FireStoreUtils.getCurrentUser(orderModel!.driverID.toString());
                        await hideProgress();
                        push(context, ChatScreens(
                          type: "vendor_chat",
                          customerName: '${customer!.firstName} ${customer.lastName}',
                          restaurantName: '${driver!.firstName} ${driver.lastName}',
                          orderId: orderModel!.id,
                          restaurantId: driver.userID,
                          customerId: customer.userID,
                          customerProfileImage: customer.profilePictureURL,
                          restaurantProfileImage: driver.profilePictureURL,
                          token: driver.fcmToken,
                          chatType: 'Driver',
                        ));
                      },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppThemeData.primary500.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.chat_bubble_text_fill, color: AppThemeData.primary500, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, int attributesOptionIndex) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode(context) ? AppThemeData.darkBgTertiary : const Color(0xffEEEDED),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  getPriceTotalText(CartProduct s) {
    double total = 0.0;

    if (s.extras_price != null &&
        s.extras_price!.isNotEmpty &&
        double.parse(s.extras_price!) != 0.0) {
      total += s.quantity * double.parse(s.extras_price!);
    }
    total += s.quantity * double.parse(s.price);

    return Text(
      amountShow(amount: total.toString()),
      style: TextStyle(fontFamily: AppThemeData.semiBold, fontSize: 14, color: AppThemeData.primary500),
    );
  }

  viewNotesheet(String notes) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height / 4.3,
          left: 25,
          right: 25),
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(style: BorderStyle.none)),
      child: Column(
        children: [
          InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 45,
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 0.3),
                    color: Colors.transparent,
                    shape: BoxShape.circle),

                // radius: 20,
                child: const Center(
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              )),
          const SizedBox(
            height: 25,
          ),
          Expanded(
              child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDarkMode(context)
                    ? const Color(0XFF2A2A2A)
                    : Colors.white),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'Remark'.tr(),
                        style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black,
                            fontSize: 16),
                      )),
                  Container(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, top: 20),
                    // height: 120,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      child: Container(
                        padding: const EdgeInsets.only(
                            left: 20, right: 20, top: 20, bottom: 20),
                        color: isDarkMode(context)
                            ? const Color(DARK_BG_COLOR)
                            : const Color(0XFFF1F4F7),
                        // height: 120,
                        alignment: Alignment.center,
                        child: Text(
                          notes,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Future<File> _downloadFile(String url, String filename) async {
    var httpClient = HttpClient();
    try {
      var request = await httpClient.getUrl(Uri.parse(url));
      var response = await request.close();
      var bytes = await consolidateHttpClientResponseBytes(response);
      File file = File('/storage/emulated/0/Download/$filename');
      await file.writeAsBytes(bytes);
      print('downloaded file path = ${file.path}');
      await hideProgress();
      showAlertDialog(context, 'File downloaded in'.tr(), file.path, true);

      return file;
    } catch (error) {
      print('pdf downloading error = $error');
      return File('');
    }
  }
}


