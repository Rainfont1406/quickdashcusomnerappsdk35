import 'dart:developer';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
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
  _LocationPermissionScreenState createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {

  // ── Navigation / data logic (unchanged) ──────────────────────────────

  Future<void> _autoSelectFirstServiceAndNavigate() async {
    try {
      ShowToastDialog.showLoader("Please wait");

      await FireStoreUtils().getCurrency().then((value) {
        if (value != null) {
          currencyData = value;
        } else {
          currencyData = CurrencyModel(
              id: "",
              code: "USD",
              decimal: 2,
              isactive: true,
              name: "US Dollar",
              symbol: "\$",
              symbolatright: false);
        }
      });

      List<Placemark> placeMarks = await placemarkFromCoordinates(
          MyAppState.selectedPosotion.location!.latitude,
          MyAppState.selectedPosotion.location!.longitude);
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
      await FireStoreUtils.getPhonePaySettingData();

      SectionModel firstSection = sectionList[0];
      AppThemeData.primary300 =
          Color(int.parse(firstSection.color!.replaceFirst("#", "0xff")));

      if (auth.FirebaseAuth.instance.currentUser != null &&
          MyAppState.currentUser != null) {
        User? user =
            await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID);

        if (user!.role == USER_ROLE_CUSTOMER) {
          user.active = true;
          user.role = USER_ROLE_CUSTOMER;
          sectionConstantModel = firstSection;

          user.fcmToken =
              await FireStoreUtils.firebaseMessaging.getToken() ?? '';
          await FireStoreUtils.updateCurrentUser(user);
          ShowToastDialog.closeLoader();

          await Provider.of<CartDatabase>(context, listen: false)
              .allCartProducts
              .then((value) {
            if (value.isNotEmpty) {
              Provider.of<CartDatabase>(context, listen: false)
                  .deleteAllProducts();
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

  Future<void> _onUseCurrentLocation() async {
    checkPermission(() async {
      await showProgress("Please wait...".tr(), false);
      AddressModel addressModel = AddressModel();
      try {
        await Geolocator.requestPermission();
        await Geolocator.getCurrentPosition();
        await hideProgress();
        Position newLocalData = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        await placemarkFromCoordinates(
                newLocalData.latitude, newLocalData.longitude)
            .then((valuePlaceMaker) {
          Placemark placeMark = valuePlaceMaker[0];
          setState(() {
            addressModel.id = Uuid().v4();
            addressModel.location = UserLocation(
                latitude: newLocalData.latitude,
                longitude: newLocalData.longitude);
            String currentLocation =
                "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";
            addressModel.locality = currentLocation;
          });
        });
        setState(() {});
        MyAppState.selectedPosotion = addressModel;
        await _autoSelectFirstServiceAndNavigate();
      } catch (e) {
        await placemarkFromCoordinates(19.228825, 72.854118)
            .then((valuePlaceMaker) {
          Placemark placeMark = valuePlaceMaker[0];
          setState(() {
            addressModel.id = Uuid().v4();
            addressModel.location =
                UserLocation(latitude: 19.228825, longitude: 72.854118);
            String currentLocation =
                "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";
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
        await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        await hideProgress();
        if (selectedMapType == 'osm') {
          Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (context) => LocationPicker()))
              .then((value) async {
            await hideProgress();
            if (value != null) {
              addressModel.locality = value.displayName!.toString();
              addressModel.location =
                  UserLocation(latitude: value.lat, longitude: value.lon);
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
                  addressModel.locality =
                      result.formattedAddress!.toString();
                  addressModel.location = UserLocation(
                      latitude: result.geometry!.location.lat,
                      longitude: result.geometry!.location.lng);
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
        await placemarkFromCoordinates(19.228825, 72.854118)
            .then((valuePlaceMaker) {
          Placemark placeMark = valuePlaceMaker[0];
          setState(() {
            addressModel.id = Uuid().v4();
            addressModel.location =
                UserLocation(latitude: 19.228825, longitude: 72.854118);
            String currentLocation =
                "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";
            addressModel.locality = currentLocation;
          });
        });
        MyAppState.selectedPosotion = addressModel;
        await hideProgress();
        await _autoSelectFirstServiceAndNavigate();
      }
    }, context);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // ── Branded gradient header ─────────────────────────────────
          AuthHeader(
            title: 'Set Your Location',
            subtitle: 'We\'ll find the best restaurants and services near you.',
          ),

          // ── Scrollable content ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    children: [
                      // Illustration
                      _buildIllustration(size),
                      const SizedBox(height: 24),

                      // Benefit pills
                      Row(
                        children: [
                          _benefitPill(
                            icon: Icons.storefront_rounded,
                            label: 'Nearby stores'.tr(),
                            dark: dark,
                          ),
                          const SizedBox(width: 10),
                          _benefitPill(
                            icon: Icons.delivery_dining_rounded,
                            label: 'Fast delivery'.tr(),
                            dark: dark,
                          ),
                          const SizedBox(width: 10),
                          _benefitPill(
                            icon: Icons.timer_rounded,
                            label: 'Live tracking'.tr(),
                            dark: dark,
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Primary CTA — gradient button (matches AuthPrimaryButton)
                      _GradientButton(
                        icon: Icons.my_location_rounded,
                        label: 'Use Current Location'.tr(),
                        onTap: _onUseCurrentLocation,
                      ),

                      const SizedBox(height: 12),

                      // Secondary CTA — outlined button (matches AuthOutlinedButton)
                      _OutlineButton(
                        icon: Icons.map_rounded,
                        label: 'Set from Map'.tr(),
                        onTap: _onSetFromMap,
                      ),

                      // Manual entry link — logged-in users only
                      if (MyAppState.currentUser != null) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () async {
                            await Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) => DeliveryAddressScreen()))
                                .then((value) async {
                              if (value != null) {
                                final addressModel = value as AddressModel;
                                MyAppState.selectedPosotion = addressModel;
                                await _autoSelectFirstServiceAndNavigate();
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 10),
                            child: RichText(
                              text: TextSpan(
                                text: 'Or '.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: AppThemeData.regular,
                                  color: dark
                                      ? AppThemeData.darkTextTertiary
                                      : AppThemeData.neutral500,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'enter location manually'.tr(),
                                    style: const TextStyle(
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
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ─────────────────────────────────────────────────────

  Widget _buildIllustration(Size size) {
    return Center(
      child: Container(
        width: size.width * 0.50,
        height: size.width * 0.50,
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
          padding: const EdgeInsets.all(20),
          child: Image.asset(
            "assets/images/location_screen.png",
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _benefitPill({
    required IconData icon,
    required String label,
    required bool dark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: dark ? AppThemeData.darkBgSecondary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dark
                ? AppThemeData.darkBorderPrimary
                : AppThemeData.neutral200,
          ),
          boxShadow: dark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppThemeData.primary500, size: 19),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppThemeData.medium,
                color: dark
                    ? AppThemeData.darkTextSecondary
                    : AppThemeData.neutral600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable button widgets ──────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GradientButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppThemeData.primary500, AppThemeData.primary400],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppThemeData.primary500.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontFamily: AppThemeData.semiBold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppThemeData.primary500,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppThemeData.primary500, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontFamily: AppThemeData.semiBold,
                color: AppThemeData.primary500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
