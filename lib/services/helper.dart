import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/services/app_dialog.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

String? validateName(String? value) {
  String pattern = r'(^[a-zA-Z ]*$)';
  RegExp regExp = RegExp(pattern);
  if (value!.isEmpty) {
    return 'Name is required'.tr();
  } else if (!regExp.hasMatch(value)) {
    return 'Name must be valid'.tr();
  }
  return null;
}

String? validateMobile(String? value) {
  String pattern = r'(^\+?[0-9]*$)';
  RegExp regExp = RegExp(pattern);
  if (value!.isEmpty) {
    return 'Mobile is required'.tr();
  } else if (!regExp.hasMatch(value)) {
    return 'Mobile Number must be digits'.tr();
  } else if (value.length < 10 || value.length > 10) {
    return 'please enter valid number'.tr();
  }
  return null;
}

String? validatePassword(String? value) {
  if ((value?.length ?? 0) < 6) {
    return 'Password must be more than 5 characters'.tr();
  } else {
    return null;
  }
}

String? validateEmail(String? value) {
  String pattern =
      r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
  RegExp regex = RegExp(pattern);
  if (!regex.hasMatch(value ?? '')) {
    return 'Enter valid e-mail'.tr();
  } else {
    return null;
  }
}

String? validateConfirmPassword(String? password, String? confirmPassword) {
  if (password != confirmPassword) {
    return 'Password doesn\'t match'.tr();
  } else if (confirmPassword!.isEmpty) {
    return 'Confirm password is required'.tr();
  } else {
    return null;
  }
}

String? validateEmptyField(String? text) =>
    text == null || text.isEmpty ? 'This field can\'t be empty.'.tr() : null;

//helper method to show progress

showProgress(String message, bool isDismissible) async {
  ShowToastDialog.showLoader("${message} ");
}

hideProgress() {
  ShowToastDialog.closeLoader();
}

void showAlertDialog(
    BuildContext context, String title, String content, bool addOkButton) {
  AppDialog.showInfo(context, title: title, message: content);
}

pushReplacement(BuildContext context, Widget destination) {
  Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (context) => destination));
}

push(BuildContext context, Widget destination) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (context) => destination));
}

pushAndRemoveUntil(BuildContext context, Widget destination) {
  Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => destination),
      (Route<dynamic> route) => false);
}

Widget displayCircleImage(String picUrl, double size, hasBorder) =>
    CachedNetworkImage(
        height: size,
        width: size,
        imageBuilder: (context, imageProvider) =>
            _getCircularImageProvider(imageProvider, size, hasBorder),
        imageUrl: getImageVAlidUrl(picUrl),
        placeholder: (context, url) =>
            _getPlaceholderOrErrorImage(size, hasBorder),
        errorWidget: (context, url, error) =>
            _getPlaceholderOrErrorImage(size, hasBorder));

Widget _getPlaceholderOrErrorImage(double size, hasBorder) => ClipOval(
      child: Image.network(
        placeholderImage,
        fit: BoxFit.cover,
      ),
    );

Widget _getCircularImageProvider(
    ImageProvider provider, double size, bool hasBorder) {
  return ClipOval(
      child: Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(size / 2)),
        border: Border.all(
          color: Colors.white,
          style: hasBorder ? BorderStyle.solid : BorderStyle.none,
          width: 1.0,
        ),
        image: DecorationImage(
          image: provider,
          fit: BoxFit.cover,
        )),
  ));
}

bool isDarkMode(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.light) {
    return false;
  } else {
    return true;
  }
}

/// Determine the current position of the device.
///
/// When the location services are not enabled or permissions
/// are denied the `Future` will return an error.
Future<Position> getCurrentLocation() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Test if location services are enabled.
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // Location services are not enabled don't continue
    // accessing the position and request users of the
    // App to enable the location services.
    await Geolocator.openLocationSettings();
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      // Permissions are denied, next time you could try
      // requesting permissions again (this is also where
      // Android's shouldShowRequestPermissionRationale
      // returned true. According to Android guidelines
      // your App should show an explanatory UI now.
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    // Permissions are denied forever, handle appropriately.
    return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
  }

  // When we reach here, permissions are granted and we can
  // continue accessing the position of the device.
  return await Geolocator.getCurrentPosition();
}

// Global function to get selected order type
Future<String> getSelectedOrderType() async {
  SharedPreferences sp = await SharedPreferences.getInstance();
  return sp.getString("foodType") == "" || sp.getString("foodType") == null
      ? "Delivery".tr()
      : sp.getString("foodType")!;
}

String audioMessageTime(Duration audioDuration) {
  String twoDigits(int n) {
    if (n >= 10) return '$n';
    return '0$n';
  }

  String twoDigitsHours(int n) {
    if (n >= 10) return '$n:';
    if (n == 0) return '';
    return '0$n:';
  }

  String twoDigitMinutes = twoDigits(audioDuration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(audioDuration.inSeconds.remainder(60));
  return '${twoDigitsHours(audioDuration.inHours)}$twoDigitMinutes:$twoDigitSeconds';
}

String updateTime(Timer timer) {
  Duration callDuration = Duration(seconds: timer.tick);
  String twoDigits(int n) {
    if (n >= 10) return '$n';
    return '0$n';
  }

  String twoDigitsHours(int n) {
    if (n >= 10) return '$n:';
    if (n == 0) return '';
    return '0$n:';
  }

  String twoDigitMinutes = twoDigits(callDuration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(callDuration.inSeconds.remainder(60));
  return '${twoDigitsHours(callDuration.inHours)}$twoDigitMinutes:$twoDigitSeconds';
}

Widget showEmptyState(String title, BuildContext context,
    {String? description, String? buttonTitle, VoidCallback? action}) {
  return Center(
    child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          Text(title,
              style: TextStyle(
                  fontSize: 20,
                  fontFamily: AppThemeData.medium,
                  color: isDarkMode(context) ? Colors.white : Colors.black)),
          const SizedBox(height: 15),
          Text(
            description == null ? "" : description.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDarkMode(context) ? Colors.white : Colors.black,
                fontSize: 16),
          ),
          const SizedBox(height: 25),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(left: 24.0, right: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: double.infinity),
                child: ElevatedButton(
                    child: Text(
                      buttonTitle!,
                      style: TextStyle(
                          color:
                              isDarkMode(context) ? Colors.white : Colors.black,
                          fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppThemeData.primary500,
                    ),
                    onPressed: action),
              ),
            )
        ]),
  );
}

String orderDate(Timestamp? timestamp) {
  return timestamp == null
      ? ""
      : DateFormat('dd MMM, yyyy').format(DateTime.fromMillisecondsSinceEpoch(
          timestamp.millisecondsSinceEpoch));
}

/// Legacy dialog widget — now delegates to [AppDialogWidget].
/// Preserved for backwards compatibility. Prefer [AppDialog] for new code.
class ShowDialogToDismiss extends StatelessWidget {
  final String content;
  final String title;
  final String buttonText;
  final String? secondaryButtonText;
  final VoidCallback? action;

  const ShowDialogToDismiss({
    super.key,
    required this.title,
    required this.buttonText,
    required this.content,
    this.secondaryButtonText,
    this.action,
  });

  @override
  Widget build(BuildContext context) => AppDialogWidget(
        type: action != null ? AppDialogType.confirm : AppDialogType.info,
        title: title,
        message: content,
        primaryLabel: buttonText,
        secondaryLabel: secondaryButtonText,
        onPrimary: action,
      );
}
