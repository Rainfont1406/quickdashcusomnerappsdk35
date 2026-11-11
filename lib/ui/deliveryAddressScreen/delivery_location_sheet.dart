// Cart delivery-location flow (2026-11-11, staging):
//
//   cart address card --tap--> "Select delivery location" bottom sheet
//        search / map  ┐
//        current GPS   ├--> "Complete your address" sheet --> back to cart
//        add new       ┘          (house/flat, landmark, Home/Work/...)
//        saved address  --> straight back to the cart (or to the complete
//                           sheet when it has no house/flat number yet)
//
// Delivery only. Dining / Takeaway never open these sheets.

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/delivery_location_helper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/services/show_toast_dialog.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

const _labels = ['Home', 'Work', 'Hotel', 'Other'];

/// Amber used for "house / flat no. missing" hints.
const Color kAddressWarning = Color(0xFFD97706);

IconData deliveryLabelIcon(String? label) {
  switch ((label ?? '').toLowerCase()) {
    case 'home':
      return Icons.home_rounded;
    case 'work':
      return Icons.work_rounded;
    case 'hotel':
      return Icons.hotel_rounded;
    default:
      return Icons.location_on_rounded;
  }
}

/// 2026-11-11 (owner, Zomato-style): the Delivery cart never pre-fills an
/// address - not a saved/default one and not the one picked last time.
/// Customers add items at the office and open the cart later at home, or
/// order from hotels and friends' places, so any remembered address can send
/// food to the wrong place (cancelled orders, wasted rides). Every time the
/// cart opens the address starts empty and must be picked again.
AddressModel initialDeliveryAddress() => AddressModel();

/// Straight-line km from the restaurant, or null when either point is unknown.
double? kmFromVendor(VendorModel? vendor, AddressModel? a) {
  if (vendor == null || a == null || !isRealLocation(a.location)) return null;
  if (vendor.latitude.abs() < 1 && vendor.longitude.abs() < 1) return null;
  return Geolocator.distanceBetween(vendor.latitude, vendor.longitude,
          a.location!.latitude, a.location!.longitude) /
      1000;
}

String _kmText(double km) =>
    km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';

/// First comma part of an address, used as the bold title ("Osmanpura").
String shortPlaceName(String? text) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return '';
  return t.split(',').first.trim();
}

class _C {
  final bool dark;
  _C(this.dark);
  Color get sheet => dark ? AppThemeData.darkBgSecondary : Colors.white;
  Color get page => dark ? AppThemeData.surfaceDark : const Color(0xFFF4F5F9);
  Color get tile => dark ? AppThemeData.darkBgTertiary : Colors.white;
  Color get border => dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200;
  Color get text => dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900;
  Color get sub => dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600;
  Color get faint => dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400;
}

Widget _grabber(_C c) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
      ),
    );

// ───────────────────────────────────────────────────────────────────────────
// 1. Select delivery location
// ───────────────────────────────────────────────────────────────────────────

/// Returns the address to deliver to (always with a map pin and a
/// house/flat number), or null when the customer closes the sheet.
Future<AddressModel?> showDeliveryLocationSheet(
  BuildContext context, {
  VendorModel? vendor,
  AddressModel? current,
}) async {
  final picked = await showModalBottomSheet<_SheetChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SelectLocationSheet(vendor: vendor, current: current),
  );
  if (picked == null || !context.mounted) return null;

  final a = picked.address;
  // A saved address that is already complete goes straight to the cart.
  if (picked.saved && (a.address ?? '').trim().isNotEmpty && isRealLocation(a.location)) {
    return a;
  }
  return showCompleteAddressSheet(context, a, vendor: vendor);
}

class _SheetChoice {
  final AddressModel address;
  final bool saved;
  _SheetChoice(this.address, {this.saved = false});
}

class _SelectLocationSheet extends StatefulWidget {
  final VendorModel? vendor;
  final AddressModel? current;
  const _SelectLocationSheet({this.vendor, this.current});

  @override
  State<_SelectLocationSheet> createState() => _SelectLocationSheetState();
}

class _SelectLocationSheetState extends State<_SelectLocationSheet> {
  LocationLookup? _gps;
  bool _gpsLoading = true;
  bool _gpsTapped = false;

  List<AddressModel> get _saved =>
      (MyAppState.currentUser?.shippingAddress ?? []).where((a) => isRealLocation(a.location)).toList();

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() => _gpsLoading = true);
    final r = await currentLocationAddress();
    if (!mounted) return;
    setState(() {
      _gps = r;
      _gpsLoading = false;
    });
    if (_gpsTapped) _useGps();
  }

  void _useGps() {
    if (_gpsLoading) {
      setState(() => _gpsTapped = true);
      return;
    }
    _gpsTapped = false;
    final a = _gps?.address;
    if (a == null) {
      ShowToastDialog.showToast(_gps?.error ?? 'Could not get your location.'.tr());
      _detect();
      return;
    }
    Navigator.pop(context, _SheetChoice(a));
  }

  Future<void> _openMap() async {
    final a = await pickLocationOnMap(context, start: widget.current?.location);
    if (a != null && mounted) Navigator.pop(context, _SheetChoice(a));
  }

  @override
  Widget build(BuildContext context) {
    final c = _C(isDarkMode(context));
    final saved = _saved;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: saved.isEmpty ? 0.55 : 0.82,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: c.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).padding.bottom),
          children: [
            _grabber(c),
            Row(
              children: [
                Expanded(
                  child: Text('Select delivery location'.tr(),
                      style: TextStyle(fontSize: 19, fontFamily: AppThemeData.bold, color: c.text)),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: c.sub),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Search: opens the map with its search box.
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _openMap,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.tile,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppThemeData.primary500),
                    const SizedBox(width: 10),
                    Text('Search for area, street name...'.tr(),
                        style: TextStyle(fontSize: 14, fontFamily: AppThemeData.regular, color: c.faint)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: c.tile,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  _actionRow(
                    c,
                    icon: Icons.my_location_rounded,
                    title: 'Use current location'.tr(),
                    subtitle: _gpsLoading
                        ? 'Detecting your location...'.tr()
                        : (_gps?.address?.locality ?? _gps?.error ?? ''),
                    loading: _gpsLoading && _gpsTapped,
                    onTap: _useGps,
                  ),
                  Divider(height: 1, indent: 60, color: c.border),
                  _actionRow(
                    c,
                    icon: Icons.add_rounded,
                    title: 'Add new address'.tr(),
                    subtitle: 'Pick the exact spot on the map'.tr(),
                    onTap: _openMap,
                  ),
                ],
              ),
            ),
            if (saved.isNotEmpty) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text('SAVED ADDRESSES'.tr(),
                    style: TextStyle(
                        fontSize: 12, letterSpacing: 1.2, fontFamily: AppThemeData.semiBold, color: c.faint)),
              ),
              Container(
                decoration: BoxDecoration(
                  color: c.tile,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < saved.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 60, color: c.border),
                      _savedRow(c, saved[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionRow(_C c,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      bool loading = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: loading
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppThemeData.primary500)))
                  : Icon(icon, color: AppThemeData.primary500, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontFamily: AppThemeData.semiBold, color: AppThemeData.primary500)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontFamily: AppThemeData.regular, color: c.sub)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.faint),
          ],
        ),
      ),
    );
  }

  Widget _savedRow(_C c, AddressModel a) {
    final km = kmFromVendor(widget.vendor, a);
    final selected = widget.current?.id != null && widget.current!.id == a.id;
    final house = (a.address ?? '').trim();
    final line = [if (house.isNotEmpty) house, (a.locality ?? '').trim()].where((s) => s.isNotEmpty).join(', ');
    return InkWell(
      onTap: () => Navigator.pop(context, _SheetChoice(a, saved: true)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Icon(deliveryLabelIcon(a.addressAs), color: c.sub, size: 22),
                  if (km != null) ...[
                    const SizedBox(height: 4),
                    Text(_kmText(km),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, fontFamily: AppThemeData.medium, color: c.faint)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text((a.addressAs ?? 'Other').tr(),
                          style: TextStyle(fontSize: 15, fontFamily: AppThemeData.semiBold, color: c.text)),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppThemeData.primary500.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('SELECTED'.tr(),
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  letterSpacing: 0.6,
                                  fontFamily: AppThemeData.bold,
                                  color: AppThemeData.primary500)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 1.35, fontFamily: AppThemeData.regular, color: c.sub)),
                  if (house.isEmpty) ...[
                    const SizedBox(height: 4),
                    Text('House / flat no. missing - tap to add'.tr(),
                        style: const TextStyle(
                            fontSize: 11.5, fontFamily: AppThemeData.medium, color: kAddressWarning)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 2. Complete your address
// ───────────────────────────────────────────────────────────────────────────

/// House/flat + landmark + label for a picked pin. Saves it to the
/// customer's saved addresses and returns it, or null if closed.
Future<AddressModel?> showCompleteAddressSheet(
  BuildContext context,
  AddressModel picked, {
  VendorModel? vendor,
}) {
  return showModalBottomSheet<AddressModel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CompleteAddressSheet(picked: picked, vendor: vendor),
  );
}

class _CompleteAddressSheet extends StatefulWidget {
  final AddressModel picked;
  final VendorModel? vendor;
  const _CompleteAddressSheet({required this.picked, this.vendor});

  @override
  State<_CompleteAddressSheet> createState() => _CompleteAddressSheetState();
}

class _CompleteAddressSheetState extends State<_CompleteAddressSheet> {
  late AddressModel _a;
  late final TextEditingController _house;
  late final TextEditingController _landmark;
  late String _label;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.picked;
    _a = AddressModel(
      id: p.id ?? const Uuid().v4(),
      address: p.address,
      landmark: p.landmark,
      locality: p.locality,
      location: p.location,
      addressAs: p.addressAs,
      isDefault: p.isDefault ?? false,
    );
    _house = TextEditingController(text: (p.address ?? '').trim());
    _landmark = TextEditingController(text: (p.landmark ?? '').trim());
    _label = _labels.contains(p.addressAs) ? p.addressAs! : 'Home';
    _house.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _house.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _changePin() async {
    final a = await pickLocationOnMap(context, start: _a.location);
    if (a != null && mounted) {
      setState(() {
        _a.location = a.location;
        _a.locality = a.locality;
      });
    }
  }

  Future<void> _save() async {
    if (_house.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    _a
      ..address = _house.text.trim()
      ..landmark = _landmark.text.trim()
      ..addressAs = _label;

    final user = MyAppState.currentUser;
    if (user != null) {
      final list = List<AddressModel>.of(user.shippingAddress ?? []);
      final backup = List<AddressModel>.of(list);
      final i = list.indexWhere((x) => x.id == _a.id);
      if (i >= 0) {
        list[i] = _a;
      } else {
        list.add(_a);
      }
      user.shippingAddress = list;
      try {
        await FireStoreUtils.updateCurrentUser(user);
      } catch (_) {
        // Still deliver to it this time; only saving for later failed.
        user.shippingAddress = backup;
        ShowToastDialog.showToast('Address used for this order, but could not be saved.'.tr());
      }
    }
    if (mounted) Navigator.pop(context, _a);
  }

  @override
  Widget build(BuildContext context) {
    final c = _C(isDarkMode(context));
    final km = kmFromVendor(widget.vendor, _a);
    final title = shortPlaceName(_a.locality);
    final canSave = _house.text.trim().isNotEmpty && !_saving;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _grabber(c),
              Row(
                children: [
                  Expanded(
                    child: Text('Complete your address'.tr(),
                        style: TextStyle(fontSize: 19, fontFamily: AppThemeData.bold, color: c.text)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: c.sub),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Picked area + Change
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppThemeData.primary500.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeData.primary500.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppThemeData.primary500, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title.isEmpty ? 'Selected location'.tr() : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontFamily: AppThemeData.bold, color: c.text)),
                          const SizedBox(height: 2),
                          Text(_a.locality ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, height: 1.35, color: c.sub)),
                          if (km != null) ...[
                            const SizedBox(height: 6),
                            Text('${_kmText(km)} ${'from the restaurant'.tr()}',
                                style: const TextStyle(
                                    fontSize: 12, fontFamily: AppThemeData.semiBold, color: AppThemeData.primary500)),
                          ],
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _changePin,
                      style: TextButton.styleFrom(
                        foregroundColor: AppThemeData.primary500,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text('Change'.tr(), style: const TextStyle(fontFamily: AppThemeData.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _field(c, _house, 'House / Flat / Floor no. *'.tr(), Icons.home_work_rounded, autofocus: _house.text.isEmpty),
              const SizedBox(height: 12),
              _field(c, _landmark, 'Nearby landmark (optional)'.tr(), Icons.flag_outlined),
              const SizedBox(height: 18),
              Text('Save address as'.tr(),
                  style: TextStyle(fontSize: 13, fontFamily: AppThemeData.semiBold, color: c.sub)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 8,
                children: [
                  for (final l in _labels)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.only(left: 2, right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      selected: _label == l,
                      onSelected: (_) => setState(() => _label = l),
                      showCheckmark: false,
                      avatar: Icon(deliveryLabelIcon(l),
                          size: 16, color: _label == l ? AppThemeData.primary500 : c.sub),
                      label: Text(l.tr()),
                      labelStyle: TextStyle(
                        fontFamily: AppThemeData.semiBold,
                        color: _label == l ? AppThemeData.primary500 : c.sub,
                      ),
                      backgroundColor: c.sheet,
                      selectedColor: AppThemeData.primary500.withValues(alpha: 0.12),
                      shape: StadiumBorder(
                        side: BorderSide(color: _label == l ? AppThemeData.primary500 : c.border),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canSave ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeData.primary500,
                    disabledBackgroundColor: AppThemeData.primary500.withValues(alpha: 0.35),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _house.text.trim().isEmpty
                              ? 'Enter house / flat no. to continue'.tr()
                              : 'Save address & proceed'.tr(),
                          style: const TextStyle(fontSize: 15.5, fontFamily: AppThemeData.semiBold, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(_C c, TextEditingController ctrl, String hint, IconData icon, {bool autofocus = false}) {
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.words,
      maxLength: 250,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      style: TextStyle(fontSize: 14.5, color: c.text),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(fontSize: 13.5, color: c.faint),
        prefixIcon: Icon(icon, size: 20, color: AppThemeData.primary500),
        filled: true,
        fillColor: c.tile,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppThemeData.primary500, width: 1.5),
        ),
      ),
    );
  }
}
