import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/theme/round_button_fill.dart';
import 'package:flutter/material.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:geolocator/geolocator.dart';

class PermissionDialog extends StatelessWidget {
  const PermissionDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      insetPadding: const EdgeInsets.all(30),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_location_alt_rounded, color: Theme.of(context).primaryColor, size: 100),
            const SizedBox(height: 20),
            Text(
              'You denied location permission forever. Please allow location permission from your app settings and receive more accurate delivery.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30), side: BorderSide(width: 2, color: Theme.of(context).primaryColor)),
                    minimumSize: const Size(1, 50),
                  ),
                  child: Text('close'.tr()),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RoundedButtonFill(
                  title: "Settings".tr(),
                  color: AppThemeData.primary500,
                  textColor: AppThemeData.grey50,
                  onPress: () async {
                    await Geolocator.openAppSettings();
                    Navigator.pop(context);
                  },
                ),
              )
            ]),
          ]),
        ),
    );
  }
}
