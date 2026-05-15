import 'dart:developer';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/widget/place_picker_osm.dart';
import 'package:flutter/material.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:provider/provider.dart';
import 'deliveryAddressScreen/DeliveryAddressScreen.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({Key? key}) : super(key: key);

  @override
  _LocationPermissionScreenState createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {

  Future<void> _autoSelectFirstServiceAndNavigate() async {
    try {
      ShowToastDialog.showLoader("Please wait");

      await FireStoreUtils().getCurrency().then((value) {
        if (value != null) {
          currencyData = value;
        } else {
          currencyData = CurrencyModel(id: "", code: "USD", decimal: 2, isactive: true, name: "US Dollar", symbol: "\$", symbolatright: false);
        }
      });

      List<Placemark> placeMarks = await placemarkFromCoordinates(MyAppState.selectedPosotion.location!.latitude, MyAppState.selectedPosotion.location!.longitude);
      country = placeMarks.first.country;

      List<SectionModel> sectionList = await FireStoreUtils.getSections();

      if (sectionList.isEmpty) {
        ShowToastDialog.closeLoader();
        return;
      }

      await FireStoreUtils.getRazorPayDemo();
      await FireStoreUtils.getPaypalSettingData();
      await FireStoreUtils.getStripeSettingData();
      await FireStoreUtils.getPayStackSettingData();
      await FireStoreUtils.getFlutterWaveSettingData();
      await FireStoreUtils.getPaytmSettingData();
      await FireStoreUtils.getPayFastSettingData();
      await FireStoreUtils.getWalletSettingData();
      await FireStoreUtils.getMercadoPagoSettingData();
      await FireStoreUtils.getOrangeMoneySettingData();
      await FireStoreUtils.getXenditSettingData();
      await FireStoreUtils.getMidTransSettingData();

      SectionModel firstSection = sectionList[0];
      AppThemeData.primary300 = Color(int.parse(firstSection.color!.replaceFirst("#", "0xff")));

      if (auth.FirebaseAuth.instance.currentUser != null && MyAppState.currentUser != null) {
        User? user = await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID);

        if (user!.role == USER_ROLE_CUSTOMER) {
          user.active = true;
          user.role = USER_ROLE_CUSTOMER;
          sectionConstantModel = firstSection;

          user.fcmToken = await FireStoreUtils.firebaseMessaging.getToken() ?? '';
          await FireStoreUtils.updateCurrentUser(user);
          ShowToastDialog.closeLoader();

          await Provider.of<CartDatabase>(context, listen: false).allCartProducts.then((value) {
            if (value.isNotEmpty) {
              Provider.of<CartDatabase>(context, listen: false).deleteAllProducts();
            }
            pushAndRemoveUntil(context, ContainerScreen(user: user));
          });
        } else {
          ShowToastDialog.closeLoader();
          pushAndRemoveUntil(context, const LoginScreen());
        }
      } else {
        sectionConstantModel = firstSection;
        ShowToastDialog.closeLoader();
        pushAndRemoveUntil(context, ContainerScreen(user: null));
      }
    } catch (e) {
      ShowToastDialog.closeLoader();
      print("Error in auto-selection: $e");
    }
  }

  // ── button handlers (unchanged logic) ────────────────────────────────────

  Future<void> _onUseCurrentLocation() async {
    checkPermission(() async {
      await showProgress("Please wait...".tr(), false);
      AddressModel addressModel = AddressModel();
      try {
        await Geolocator.requestPermission();
        await Geolocator.getCurrentPosition();
        await hideProgress();
        Position newLocalData = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        await placemarkFromCoordinates(newLocalData.latitude, newLocalData.longitude).then((valuePlaceMaker) {
          Placemark placeMark = valuePlaceMaker[0];
          setState(() {
            addressModel.id = Uuid().v4();
            addressModel.location = UserLocation(latitude: newLocalData.latitude, longitude: newLocalData.longitude);
            String currentLocation = "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";
            addressModel.locality = currentLocation;
          });
        });
        setState(() {});
        MyAppState.selectedPosotion = addressModel;
        await _autoSelectFirstServiceAndNavigate();
      } catch (e) {
        await placemarkFromCoordinates(19.228825, 72.854118).then((valuePlaceMaker) {
          Placemark placeMark = valuePlaceMaker[0];
          setState(() {
            addressModel.id = Uuid().v4();
            addressModel.location = UserLocation(latitude: 19.228825, longitude: 72.854118);
            String currentLocation = "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";
            addressModel.locality = currentLocation;
          });
        });
        MyAppState.selectedPosotion = addressModel;
        await hideProgress();
        await _autoSelectFirstServiceAndNavigate();
      }
    }, context);
  }

  Future<void> _onSetFromMap() async {
    checkPermission(() async {
      await showProgress("Please wait...".tr(), false);
      AddressModel addressModel = AddressModel();
      try {
        await Geolocator.requestPermission();
        await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        await hideProgress();
        if (selectedMapType == 'osm') {
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => LocationPicker())).then((value) async {
            await hideProgress();
            if (value != null) {
              addressModel.locality = value.displayName!.toString();
              addressModel.location = UserLocation(latitude: value.lat, longitude: value.lon);
              MyAppState.selectedPosotion = addressModel;
              setState(() {});
              await _autoSelectFirstServiceAndNavigate();
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlacePicker(
                apiKey: GOOGLE_API_KEY,
                onPlacePicked: (result) async {
                  addressModel.locality = result.formattedAddress!.toString();
                  addressModel.location = UserLocation(latitude: result.geometry!.location.lat, longitude: result.geometry!.location.lng);
                  log(result.toString());
                  MyAppState.selectedPosotion = addressModel;
                  setState(() {});
                  await _autoSelectFirstServiceAndNavigate();
                },
                initialPosition: const LatLng(-33.8567844, 151.213108),
                useCurrentLocation: true,
                selectInitialPosition: true,
                usePinPointingSearch: true,
                usePlaceDetailSearch: true,
                zoomGesturesEnabled: true,
                zoomControlsEnabled: true,
                initialMapType: MapType.terrain,
                resizeToAvoidBottomInset: false,
              ),
            ),
          );
        }
      } catch (e) {
        await placemarkFromCoordinates(19.228825, 72.854118).then((valuePlaceMaker) {
          Placemark placeMark = valuePlaceMaker[0];
          setState(() {
            addressModel.id = Uuid().v4();
            addressModel.location = UserLocation(latitude: 19.228825, longitude: 72.854118);
            String currentLocation = "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";
            addressModel.locality = currentLocation;
          });
        });
        MyAppState.selectedPosotion = addressModel;
        await hideProgress();
        await _autoSelectFirstServiceAndNavigate();
      }
    }, context);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF2F4F8),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.06),

                // ── Illustration ──────────────────────────────────────
                Container(
                  width: size.width * 0.55,
                  height: size.width * 0.55,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        AppThemeData.primary500.withValues(alpha: 0.12),
                        AppThemeData.primary500.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                      stops: const [0.3, 0.7, 1.0],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Image.asset(
                      "assets/images/location_screen.png",
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Headline ──────────────────────────────────────────
                Text(
                  "Enable Location Access".tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.bold,
                    fontSize: 26,
                    height: 1.2,
                    color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "We use your location to find nearby restaurants, estimate delivery times, and provide accurate service.".tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 15,
                    height: 1.55,
                    color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Benefits row ──────────────────────────────────────
                Row(
                  children: [
                    _benefit(icon: Icons.storefront_rounded, label: 'Nearby stores'.tr(), dark: dark),
                    const SizedBox(width: 10),
                    _benefit(icon: Icons.delivery_dining_rounded, label: 'Fast delivery'.tr(), dark: dark),
                    const SizedBox(width: 10),
                    _benefit(icon: Icons.timer_rounded, label: 'Live tracking'.tr(), dark: dark),
                  ],
                ),

                const SizedBox(height: 36),

                // ── Primary CTA: Use current location ─────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _onUseCurrentLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeData.primary500,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          "Use Current Location".tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontFamily: AppThemeData.semiBold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Secondary CTA: Set from map ───────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _onSetFromMap,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.primary500,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_rounded, color: AppThemeData.primary500, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          "Set from Map".tr(),
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: AppThemeData.semiBold,
                            color: AppThemeData.primary500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Manual entry link (logged-in users only) ──────────
                if (MyAppState.currentUser != null) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () async {
                      await Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => DeliveryAddressScreen()))
                          .then((value) async {
                        if (value != null) {
                          AddressModel addressModel = value;
                          MyAppState.selectedPosotion = addressModel;
                          await _autoSelectFirstServiceAndNavigate();
                        }
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    ),
                    child: RichText(
                      text: TextSpan(
                        text: 'Or '.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: AppThemeData.regular,
                          color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
                        ),
                        children: [
                          TextSpan(
                            text: 'enter location manually'.tr(),
                            style: TextStyle(
                              fontFamily: AppThemeData.semiBold,
                              color: AppThemeData.primary500,
                              decoration: TextDecoration.underline,
                              decorationColor: AppThemeData.primary500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                SizedBox(height: size.height * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _benefit({required IconData icon, required String label, required bool dark}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppThemeData.primary500, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppThemeData.medium,
                color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
