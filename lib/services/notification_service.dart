import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/services/device_session_service.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/ui/chat_screen/chat_screen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:emartconsumer/ui/dineInScreen/my_booking_screen.dart';
import 'package:emartconsumer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:emartconsumer/ui/billPayRequest/BillPayRequestScreen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
}

class NotificationService {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  final GlobalKey<NavigatorState> navigatorKey = new GlobalKey<NavigatorState>();

  initInfo() async {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    var request = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (request.authorizationStatus == AuthorizationStatus.authorized || request.authorizationStatus == AuthorizationStatus.provisional) {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      var iosInitializationSettings = const DarwinInitializationSettings();
      final InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid, iOS: iosInitializationSettings);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings,
          onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          _handleNotificationTap(Map<String, dynamic>.from(jsonDecode(payload)));
        } catch (e) {
          log('Failed to handle local notification tap: $e');
        }
      });
      setupInteractedMessage();
    }
  }

  Future<void> setupInteractedMessage() async {
    // App was cold-started (fully terminated, not just backgrounded) by
    // tapping this notification — onMessageOpenedApp below never fires in
    // that case (it only covers background→foreground taps), so without
    // this the app launched straight to Home and the tap's data (e.g. which
    // Bill Pay request to open) was silently discarded. Data-only, same
    // routing as onMessageOpenedApp/onDidReceiveNotificationResponse.
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      FirebaseMessaging.onBackgroundMessage((message) => firebaseMessageBackgroundHandle(message));
      if (initialMessage.data['type'] == 'force_logout') {
        DeviceSessionService.handleSessionInvalidated(navigatorKey.currentContext);
      } else {
        _handleNotificationTap(initialMessage.data);
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log("::::::::::::onMessage:::::::::::::::::");
      if (message.data['type'] == 'force_logout') {
        DeviceSessionService.handleSessionInvalidated(navigatorKey.currentContext);
        return;
      }
      if (message.notification != null) {
        log(message.notification.toString());
        display(message);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log("::::::::::::MessageOpenedApp:::::::::::::::::");
      print(message);
      if (message.data['type'] == 'force_logout') {
        DeviceSessionService.handleSessionInvalidated(navigatorKey.currentContext);
        return;
      }
      if (message.notification != null) {
        log(message.data.toString());
        _handleNotificationTap(message.data);
      }
    });
    log("::::::::::::Permission authorized:::::::::::::::::");
    await FirebaseMessaging.instance.subscribeToTopic("eMart_customer");
  }

  // Shared routing for a tapped notification — used both when the OS-level
  // FCM notification is tapped (background/terminated app, via
  // onMessageOpenedApp) and when our own locally-shown notification is
  // tapped (app was in foreground, via onDidReceiveNotificationResponse).
  // Previously only the former was wired up, so tapping a foreground
  // Bill Pay / order notification silently did nothing.
  void _handleNotificationTap(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      // Cold start: the app process was fully killed, then launched fresh
      // by tapping this notification. getInitialMessage() can resolve
      // (see setupInteractedMessage above) before MaterialApp's first
      // build() completes, so navigatorKey isn't attached to a Navigator
      // yet - context is null here through no fault of the tap itself.
      // Previously this just silently dropped the tap (Bill Pay/order
      // notifications opened to Home with no error). Re-run this exact
      // call after the next frame instead of giving up - each retry
      // re-checks context itself, so this naturally keeps deferring until
      // the Navigator is actually attached, however many frames that takes.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotificationTap(data));
      return;
    }
    final String orderId = data['orderId']?.toString() ?? '';
    final String? type = data['type']?.toString();
    if (type == 'vendor_order') {
      push(context, OrderDetailsScreen(orderId: orderId));
    } else if (type == 'vendor_bill_pay_request') {
      push(context, BillPayRequestScreen(orderId: orderId));
    } else if (type == 'vendor_chat' || type == 'cab_parcel_chat') {
      push(
          context,
          ChatScreens(
            orderId: orderId,
            customerId: data['customerId'],
            customerName: data['customerName'],
            customerProfileImage: data['customerProfileImage'],
            restaurantId: data['restaurantId'],
            restaurantName: data['restaurantName'],
            restaurantProfileImage: data['restaurantProfileImage'],
            token: data['token'],
            chatType: data['chatType'],
            type: type,
          ));
    } else if (type == 'dine_in') {
      pushReplacement(
          context,
          ContainerScreen(
            user: MyAppState.currentUser,
            drawerSelection: DrawerSelection.MyBooking,
            appBarTitle: 'Dine-In Bookings'.tr(),
            currentWidget: MyBookingScreen(),
          ));
    } else {
      /// receive message through inbox
      push(
          context,
          ChatScreens(
            orderId: orderId,
            customerId: data['customerId'],
            customerName: data['customerName'],
            customerProfileImage: data['customerProfileImage'],
            restaurantId: data['restaurantId'],
            restaurantName: data['restaurantName'],
            restaurantProfileImage: data['restaurantProfileImage'],
            token: data['token'],
            chatType: data['chatType'],
          ));
    }
  }

  static getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    return token!;
  }

  display(RemoteMessage message) async {
    log('Got a message whilst in the foreground!');
    log('Message title: ${message.notification!.title.toString()}');
    log('Message data: ${message.notification!.body.toString()}');

    try {
      // final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      AndroidNotificationChannel channel = const AndroidNotificationChannel(
        "01",
        "emart_customer",
        description: 'Show QuickDash Notification',
        importance: Importance.max,
      );
      AndroidNotificationDetails notificationDetails = AndroidNotificationDetails(channel.id, channel.name,
          channelDescription: 'your channel Description', importance: Importance.high, priority: Priority.high, ticker: 'ticker');
      const DarwinNotificationDetails darwinNotificationDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
      NotificationDetails notificationDetailsBoth = NotificationDetails(android: notificationDetails, iOS: darwinNotificationDetails);
      await FlutterLocalNotificationsPlugin().show(
        0,
        message.notification!.title,
        message.notification!.body,
        notificationDetailsBoth,
        payload: jsonEncode(message.data),
      );
    } on Exception catch (e) {
      log(e.toString());
    }
  }
}
