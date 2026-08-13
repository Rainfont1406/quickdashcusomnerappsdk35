import 'dart:async';
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
import 'package:emartconsumer/ui/auth_screen/auth_widgets.dart';
import 'package:emartconsumer/services/localDatabase.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/container/ContainerScreen.dart';
import 'package:flutter_google_maps_webservices/places.dart' show Component;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
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

      // Was 12 sequential `await`ed calls (13 with wallet) — harmless when
      // these functions were fire-and-forget internally, but since they were
      // converted to real awaited Future<void>s this session (for the
      // Cart/Wallet/GiftCard fix), that made this screen block on 12
      // back-to-back round trips. Nothing below this point actually reads
      // gateway settings — they're only consumed later by
      // Cart/Payment/Wallet/GiftCard — so this can be unawaited like
      // CartScreen's own call, and routed through the memoized guard so it
      // also stops bypassing the session-wide dedup.
      unawaited(FireStoreUtils.ensurePaymentGatewaySettingsLoaded());
      FireStoreUtils.getWalletSettingData();

      SectionModel firstSection = sectionList[0];
      AppThemeData.primary300 =
          Color(int.parse(firstSection.color!.replaceFirst("#", "0xff")));

      // Accept both Firebase Auth users and MSG91 phone-login users
      // (MSG91 has no FirebaseAuth session — only MyAppState.currentUser is set)
      if (MyAppState.currentUser != null) {
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
                // Hard filter: only Indian results are returned at all.
                autocompleteComponents: [Component(Component.country, 'in')],
              ),
            ),
          );
        }
      } catch (e) {
        // GPS failed — proceed without a location so the user must
        // pick their address manually. No hardcoded fallback.
        await hideProgress();
        await _autoSelectFirstServiceAndNavigate();
      }
    }, context);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);

    return Scaffold(
      backgroundColor:
          dark ? AppThemeData.surfaceDark : const Color(0xFFF5F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),

              // ── Icon illustration ───────────────────────────────────
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppThemeData.primary500.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 52,
                  color: AppThemeData.primary500,
                ),
              ),

              const SizedBox(height: 28),

              // ── Title ───────────────────────────────────────────────
              Text(
                'Set Your Location'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontFamily: AppThemeData.bold,
                  color: dark ? AppThemeData.grey50 : AppThemeData.grey900,
                ),
              ),

              const SizedBox(height: 10),

              // ── Subtitle ────────────────────────────────────────────
              Text(
                'Allow location access so we can show nearby restaurants and services.'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: AppThemeData.regular,
                  color: dark ? AppThemeData.grey400 : AppThemeData.grey500,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 40),

              // ── Primary button ──────────────────────────────────────
              // "Use Current Location" was removed — the map screen this
              // opens already has its own current-location button plus
              // search and manual pin-drop, so it covered every case the
              // standalone button did and more. One button, not two.
              AuthPrimaryButton(
                label: 'Set from Map'.tr(),
                onTap: _onSetFromMap,
              ),

              // ── Manual entry link — logged-in users only ────────────
              if (MyAppState.currentUser != null) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

}
