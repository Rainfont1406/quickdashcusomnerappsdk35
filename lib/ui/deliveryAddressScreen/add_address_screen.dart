import 'dart:developer';

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/widget/place_picker_osm.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:uuid/uuid.dart';

class AddAddressScreen extends StatefulWidget {
  final int? index;

  const AddAddressScreen({super.key, this.index});

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _landmark = TextEditingController();
  final TextEditingController _locality = TextEditingController();

  final _focusAddress = FocusNode();
  final _focusLocality = FocusNode();
  final _focusLandmark = FocusNode();

  final List<_LabelOption> _labels = [
    _LabelOption(label: 'Home', icon: Icons.home_rounded),
    _LabelOption(label: 'Work', icon: Icons.work_rounded),
    _LabelOption(label: 'Hotel', icon: Icons.hotel_rounded),
    _LabelOption(label: 'Other', icon: Icons.location_on_rounded),
  ];
  String _selectedSaveAs = 'Home';

  UserLocation? _userLocation;
  AddressModel _addressModel = AddressModel();
  List<AddressModel> _shippingAddress = [];

  @override
  void initState() {
    super.initState();
    _getData();
  }

  @override
  void dispose() {
    _address.dispose();
    _landmark.dispose();
    _locality.dispose();
    _focusAddress.dispose();
    _focusLocality.dispose();
    _focusLandmark.dispose();
    super.dispose();
  }

  void _getData() {
    if (MyAppState.currentUser?.shippingAddress != null) {
      _shippingAddress = MyAppState.currentUser!.shippingAddress!;
    }
    if (widget.index != null) {
      _addressModel = _shippingAddress[widget.index!];
      _address.text = _addressModel.address.toString();
      _landmark.text = _addressModel.landmark.toString();
      _locality.text = _addressModel.locality.toString();
      _selectedSaveAs = _addressModel.addressAs.toString();
      _userLocation = _addressModel.location;
    }
    setState(() {});
  }

  void _pickLocation() {
    if (selectedMapType == 'osm') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => LocationPicker()))
          .then((value) {
        if (value != null) {
          setState(() {
            _locality.text = value.displayName.toString();
            _userLocation = UserLocation(latitude: value.lat, longitude: value.lon);
          });
        }
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlacePicker(
            apiKey: GOOGLE_API_KEY,
            onPlacePicked: (result) {
              setState(() {
                _locality.text = result.formattedAddress.toString();
                _userLocation = UserLocation(
                  latitude: result.geometry!.location.lat,
                  longitude: result.geometry!.location.lng,
                );
              });
              log(result.toString());
              Navigator.of(context).pop();
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
  }

  Future<void> _save() async {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please select a location'.tr()),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    if (_address.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter flat / house / floor / building'.tr()),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    if (_locality.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter area / sector / locality'.tr()),
        backgroundColor: AppThemeData.primary500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    ShowToastDialog.showLoader('Please wait'.tr());
    if (widget.index != null) {
      _addressModel
        ..location = _userLocation
        ..addressAs = _selectedSaveAs
        ..locality = _locality.text
        ..address = _address.text
        ..landmark = _landmark.text;
      _shippingAddress
        ..removeAt(widget.index!)
        ..insert(widget.index!, _addressModel);
    } else {
      _addressModel
        ..id = const Uuid().v4()
        ..location = _userLocation
        ..addressAs = _selectedSaveAs
        ..locality = _locality.text
        ..address = _address.text
        ..landmark = _landmark.text
        ..isDefault = false;
      _shippingAddress.add(_addressModel);
    }
    setState(() {});
    MyAppState.currentUser!.shippingAddress = _shippingAddress;
    await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
    ShowToastDialog.closeLoader();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final isEditing = widget.index != null;

    return Scaffold(
      backgroundColor: dark ? AppThemeData.surfaceDark : const Color(0xFFF2F4F8),
      appBar: AppBar(
        backgroundColor: dark ? AppThemeData.darkBgSecondary : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20,
              color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Address'.tr() : 'Add New Address'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppThemeData.semiBold,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1,
              color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
        ),
      ),
      bottomNavigationBar: _buildStickyButton(dark),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location picker
            _sectionLabel('Location'.tr(), dark),
            const SizedBox(height: 8),
            _locationPickerCard(dark),
            const SizedBox(height: 20),

            // Save as labels
            _sectionLabel('Save Address As'.tr(), dark),
            const SizedBox(height: 10),
            _labelChipsRow(dark),
            const SizedBox(height: 20),

            // Address fields
            _sectionLabel('Address Details'.tr(), dark),
            const SizedBox(height: 8),
            _formCard(dark),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, bool dark) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontFamily: AppThemeData.semiBold,
        letterSpacing: 0.8,
        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
      ),
    );
  }

  Widget _locationPickerCard(bool dark) {
    final hasLocation = _userLocation != null;
    return GestureDetector(
      onTap: _pickLocation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasLocation
              ? AppThemeData.primary500.withValues(alpha: 0.06)
              : (dark ? AppThemeData.darkBgSecondary : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasLocation
                ? AppThemeData.primary500
                : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
            width: hasLocation ? 1.5 : 1,
          ),
          boxShadow: hasLocation
              ? [BoxShadow(color: AppThemeData.primary500.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0 : 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: hasLocation
                    ? AppThemeData.primary500.withValues(alpha: 0.1)
                    : (dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral100),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasLocation ? Icons.location_on_rounded : Icons.location_searching_rounded,
                color: hasLocation ? AppThemeData.primary500 : (dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasLocation ? 'Location Selected'.tr() : 'Choose Location'.tr(),
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: AppThemeData.semiBold,
                      color: hasLocation
                          ? AppThemeData.primary500
                          : (dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900),
                    ),
                  ),
                  if (_locality.text.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _locality.text,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppThemeData.regular,
                        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else
                    Text(
                      'Tap to search for your address'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppThemeData.regular,
                        color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelChipsRow(bool dark) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final opt = _labels[i];
          final selected = _selectedSaveAs == opt.label;
          return GestureDetector(
            onTap: () => setState(() => _selectedSaveAs = opt.label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppThemeData.primary500
                    : (dark ? AppThemeData.darkBgSecondary : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppThemeData.primary500
                      : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    opt.icon,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : (dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    opt.label.tr(),
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: selected ? AppThemeData.semiBold : AppThemeData.medium,
                      color: selected
                          ? Colors.white
                          : (dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral700),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _formCard(bool dark) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Flat / House / Floor / Building'.tr(), required: true, dark: dark),
          const SizedBox(height: 6),
          _buildField(
            controller: _address,
            focusNode: _focusAddress,
            hint: 'e.g. Flat 4B, Green Towers'.tr(),
            prefixIcon: Icons.home_work_rounded,
            dark: dark,
            nextFocus: _focusLocality,
          ),
          const SizedBox(height: 16),
          _fieldLabel('Area / Sector / Locality'.tr(), required: true, dark: dark),
          const SizedBox(height: 6),
          _buildField(
            controller: _locality,
            focusNode: _focusLocality,
            hint: 'e.g. Koramangala, Sector 5'.tr(),
            prefixIcon: Icons.map_rounded,
            dark: dark,
            nextFocus: _focusLandmark,
          ),
          const SizedBox(height: 16),
          _fieldLabel('Nearby Landmark'.tr(), dark: dark),
          const SizedBox(height: 6),
          _buildField(
            controller: _landmark,
            focusNode: _focusLandmark,
            hint: 'Optional – e.g. Near City Mall'.tr(),
            prefixIcon: Icons.place_rounded,
            dark: dark,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text, {bool required = false, required bool dark}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13,
          fontFamily: AppThemeData.medium,
          color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600,
        ),
        children: required
            ? [
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppThemeData.error500),
                ),
              ]
            : [],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData prefixIcon,
    required bool dark,
    FocusNode? nextFocus,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: textInputAction,
      onFieldSubmitted: (_) {
        if (nextFocus != null) FocusScope.of(context).requestFocus(nextFocus);
      },
      style: TextStyle(
        fontSize: 15,
        fontFamily: AppThemeData.medium,
        color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          fontFamily: AppThemeData.regular,
          color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
        ),
        prefixIcon: Icon(prefixIcon, size: 19,
            color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400),
        filled: true,
        fillColor: dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppThemeData.primary500, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildStickyButton(bool dark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: dark ? AppThemeData.darkBgSecondary : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppThemeData.primary500,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.save_alt_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text(
                (widget.index != null ? 'Update Address' : 'Save Address').tr(),
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
    );
  }
}

class _LabelOption {
  final String label;
  final IconData icon;
  const _LabelOption({required this.label, required this.icon});
}
