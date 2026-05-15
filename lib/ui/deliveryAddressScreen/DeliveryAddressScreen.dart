// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:easy_localization/easy_localization.dart';
// import 'package:flutter/material.dart';
// import 'package:foodie_customer/constants.dart';
// import 'package:foodie_customer/main.dart';
// import 'package:foodie_customer/model/AddressModel.dart';
// import 'package:foodie_customer/model/DeliveryChargeModel.dart';
// import 'package:foodie_customer/model/User.dart';
// import 'package:foodie_customer/model/VendorModel.dart';
// import 'package:foodie_customer/services/FirebaseHelper.dart';
// import 'package:foodie_customer/services/helper.dart';
// import 'package:foodie_customer/services/localDatabase.dart';
// import 'package:foodie_customer/ui/payment/PaymentScreen.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:place_picker/place_picker.dart';
//
// import '../../model/TaxModel.dart';
//
// class DeliveryAddressScreen extends StatefulWidget {
//   static final kInitialPosition = LatLng(-33.8567844, 151.213108);
//
//   final double total;
//   final double? discount;
//   final String? couponCode;
//   final String? couponId, notes;
//   final List<CartProduct> products;
//   final List<String>? extraAddons;
//   final String? extraSize;
//   final String? tipValue;
//   final String? deliveryCharge;
//   final bool? takeAway;
//   final List<TaxModel>? taxModel;
//   final Map<String, dynamic>? specialDiscountMap;
//   final Timestamp? scheduleTime;
//
//   const DeliveryAddressScreen(
//       {Key? key,
//       required this.total,
//       this.discount,
//       this.couponCode,
//       this.couponId,
//       required this.products,
//       this.extraAddons,
//       this.extraSize,
//       this.tipValue,
//       this.takeAway,
//       this.specialDiscountMap,
//       this.deliveryCharge,
//       this.taxModel,
//         this.scheduleTime,
//       this.notes})
//       : super(key: key);
//
//   @override
//   _DeliveryAddressScreenState createState() => _DeliveryAddressScreenState();
// }
//
// class _DeliveryAddressScreenState extends State<DeliveryAddressScreen> {
//   final _formKey = GlobalKey<FormState>();
//
//   String? country;
//   var street = TextEditingController();
//   var street1 = TextEditingController();
//   var landmark = TextEditingController();
//   var landmark1 = TextEditingController();
//   var zipcode = TextEditingController();
//   var zipcode1 = TextEditingController();
//   var city = TextEditingController();
//   var city1 = TextEditingController();
//   var cutries = TextEditingController();
//   var cutries1 = TextEditingController();
//   var lat;
//   var long;
//
//   AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;
//
//   @override
//   void dispose() {
//     street.dispose();
//     landmark.dispose();
//     city.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // if(MyAppState.currentUser!.shippingAddress.country != ''){
//     //   country = MyAppState.currentUser!.shippingAddress.country;
//     // }
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           'Delivery Address'.tr(),
//           style: TextStyle(color: isDarkMode(context) ? Colors.white : Colors.black),
//         ).tr(),
//       ),
//       body: Container(
//           color: isDarkMode(context) ? null : Color(0XFFF1F4F7),
//           child: Form(
//               key: _formKey,
//               autovalidateMode: _autoValidateMode,
//               child: SingleChildScrollView(
//                   child: Column(children: [
//                 SizedBox(
//                   height: 40,
//                 ),
//                 Card(
//                   elevation: 0.5,
//                   color: isDarkMode(context) ? Color(DARK_BG_COLOR) : Color(0XFFFFFFFF),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//                   margin: EdgeInsets.only(left: 20, right: 20),
//                   child: Column(
//                     children: [
//                       Container(
//                         padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 10),
//                         child: TextFormField(
//                             // controller: street,
//                             controller: street1.text.isEmpty ? street : street1,
//                             textAlignVertical: TextAlignVertical.center,
//                             textInputAction: TextInputAction.next,
//                             validator: validateEmptyField,
//                             // onSaved: (text) => line1 = text,
//                             onSaved: (text) => street.text = text!,
//                             style: TextStyle(fontSize: 18.0),
//                             keyboardType: TextInputType.streetAddress,
//                             cursorColor: AppThemeData.primary500,
//                             // initialValue:
//                             //     MyAppState.currentUser!.shippingAddress.line1,
//                             decoration: InputDecoration(
//                               // contentPadding: EdgeInsets.symmetric(horizontal: 24),
//                               labelText: 'Street 1'.tr(),
//                               labelStyle: TextStyle(color: Color(0Xff696A75), fontSize: 17),
//                               hintStyle: TextStyle(color: Colors.grey.shade400),
//                               focusedBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: AppThemeData.primary500),
//                               ),
//                               errorBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                                 borderRadius: BorderRadius.circular(8.0),
//                               ),
//                               focusedErrorBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                                 borderRadius: BorderRadius.circular(8.0),
//                               ),
//                               enabledBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Color(0XFFB1BCCA)),
//                                 // borderRadius: BorderRadius.circular(8.0),
//                               ),
//                             )),
//                       ),
//                       // ListTile(
//                       //   contentPadding:
//                       //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
//                       //   leading: Container(
//                       //     // width: 0,
//                       //     child: Text(
//                       //       'Street 2'.tr(),
//                       //       style: TextStyle(fontSize: 16),
//                       //     ),
//                       //   ),
//                       // ),
//                       Container(
//                         padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 10),
//                         child: TextFormField(
//                           // controller: _controller,
//                           controller: landmark1.text.isEmpty ? landmark : landmark1,
//                           textAlignVertical: TextAlignVertical.center,
//                           textInputAction: TextInputAction.next,
//                           validator: validateEmptyField,
//                           onSaved: (text) => landmark.text = text!,
//                           style: TextStyle(fontSize: 18.0),
//                           keyboardType: TextInputType.streetAddress,
//                           cursorColor: AppThemeData.primary500,
//                           // initialValue:
//                           //     MyAppState.currentUser!.shippingAddress.line2,
//                           decoration: InputDecoration(
//                             // contentPadding: EdgeInsets.symmetric(horizontal: 24),
//                             labelText: 'Landmark'.tr(),
//                             labelStyle: TextStyle(color: Color(0Xff696A75), fontSize: 17),
//                             hintStyle: TextStyle(color: Colors.grey.shade400),
//                             focusedBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: AppThemeData.primary500),
//                             ),
//                             errorBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                               borderRadius: BorderRadius.circular(8.0),
//                             ),
//                             focusedErrorBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                               borderRadius: BorderRadius.circular(8.0),
//                             ),
//                             enabledBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: Color(0XFFB1BCCA)),
//                               // borderRadius: BorderRadius.circular(8.0),
//                             ),
//                           ),
//                         ),
//                       ),
//                       // ListTile(
//                       //   contentPadding:
//                       //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
//                       //   leading: Container(
//                       //     // width: 0,
//                       //     child: Text(
//                       //       'Zip Code'.tr(),
//                       //       style: TextStyle(fontSize: 16),
//                       //     ),
//                       //   ),
//                       // ),
//                       Container(
//                         padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 10),
//                         child: TextFormField(
//                           controller: zipcode1.text.isEmpty ? zipcode : zipcode1,
//                           textAlignVertical: TextAlignVertical.center,
//                           textInputAction: TextInputAction.next,
//                           validator: validateEmptyField,
//                           onSaved: (text) => zipcode.text = text!,
//                           style: TextStyle(fontSize: 18.0),
//                           keyboardType: TextInputType.phone,
//                           cursorColor: AppThemeData.primary500,
//                           // initialValue: MyAppState
//                           //     .currentUser!.shippingAddress.postalCode,
//                           decoration: InputDecoration(
//                             // contentPadding: EdgeInsets.symmetric(horizontal: 24),
//                             labelText: 'Zip Code'.tr(),
//                             labelStyle: TextStyle(color: Color(0Xff696A75), fontSize: 17),
//                             hintStyle: TextStyle(color: Colors.grey.shade400),
//                             focusedBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: AppThemeData.primary500),
//                             ),
//                             errorBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                               borderRadius: BorderRadius.circular(8.0),
//                             ),
//                             focusedErrorBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                               borderRadius: BorderRadius.circular(8.0),
//                             ),
//                             enabledBorder: UnderlineInputBorder(
//                               borderSide: BorderSide(color: Color(0XFFB1BCCA)),
//                               // borderRadius: BorderRadius.circular(8.0),
//                             ),
//                           ),
//                         ),
//                       ),
//                       // ListTile(
//                       //   contentPadding:
//                       //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
//                       //   leading: Container(
//                       //     // width: 0,
//                       //     child: Text(
//                       //       'City'.tr(),
//                       //       style: TextStyle(fontSize: 16),
//                       //     ),
//                       //   ),
//                       // ),
//                       Container(
//                           padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 10),
//                           child: TextFormField(
//                             controller: city1.text.isEmpty ? city : city1,
//                             textAlignVertical: TextAlignVertical.center,
//                             textInputAction: TextInputAction.next,
//                             validator: validateEmptyField,
//                             onSaved: (text) => city.text = text!,
//                             style: TextStyle(fontSize: 18.0),
//                             keyboardType: TextInputType.streetAddress,
//                             cursorColor: AppThemeData.primary500,
//                             // initialValue:
//                             //     MyAppState.currentUser!.shippingAddress.city,
//                             decoration: InputDecoration(
//                               // contentPadding: EdgeInsets.symmetric(horizontal: 24),
//                               labelText: 'City'.tr(),
//                               labelStyle: TextStyle(color: Color(0Xff696A75), fontSize: 17),
//                               hintStyle: TextStyle(color: Colors.grey.shade400),
//                               focusedBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: AppThemeData.primary500),
//                               ),
//                               errorBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                                 borderRadius: BorderRadius.circular(8.0),
//                               ),
//                               focusedErrorBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                                 borderRadius: BorderRadius.circular(8.0),
//                               ),
//                               enabledBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Color(0XFFB1BCCA)),
//                                 // borderRadius: BorderRadius.circular(8.0),
//                               ),
//                             ),
//                           )),
//
//                       Container(
//                           padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 10),
//                           child: TextFormField(
//                             controller: cutries1.text.isEmpty ? cutries : cutries1,
//                             textAlignVertical: TextAlignVertical.center,
//                             textInputAction: TextInputAction.next,
//                             validator: validateEmptyField,
//                             onSaved: (text) => cutries.text = text!,
//                             style: TextStyle(fontSize: 18.0),
//                             keyboardType: TextInputType.streetAddress,
//                             cursorColor: AppThemeData.primary500,
//                             // initialValue:
//                             //     MyAppState.currentUser!.shippingAddress.city,
//                             decoration: InputDecoration(
//                               // contentPadding: EdgeInsets.symmetric(horizontal: 24),
//                               labelText: 'Country'.tr(),
//                               labelStyle: TextStyle(color: Color(0Xff696A75), fontSize: 17),
//                               hintStyle: TextStyle(color: Colors.grey.shade400),
//                               focusedBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: AppThemeData.primary500),
//                               ),
//                               errorBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                                 borderRadius: BorderRadius.circular(8.0),
//                               ),
//                               focusedErrorBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                                 borderRadius: BorderRadius.circular(8.0),
//                               ),
//                               enabledBorder: UnderlineInputBorder(
//                                 borderSide: BorderSide(color: Color(0XFFB1BCCA)),
//                                 // borderRadius: BorderRadius.circular(8.0),
//                               ),
//                             ),
//                           )),
//
//                       // ListTile(
//                       //   contentPadding:
//                       //       const EdgeInsetsDirectional.only(start: 40, end: 30, top: 24),
//                       //   leading: Container(
//                       //     // width: 0,
//                       //     child: Text(
//                       //       'Country'.tr(),
//                       //       style: TextStyle(fontSize: 16),
//                       //     ),
//                       //   ),
//                       // ),
//
//                       // ListTile(
//                       //     contentPadding: const EdgeInsetsDirectional.only(
//                       //         start: 5, end: 10),
//                       //     subtitle: Padding(
//                       //         padding: EdgeInsets.only(left: 16, right: 10),
//                       //         child: Divider(
//                       //           color: Color(0XFFB1BCCA),
//                       //           thickness: 1.5,
//                       //         )),
//                       //     title: ButtonTheme(
//                       //         alignedDropdown: true,
//                       //         child: DropdownButtonHideUnderline(
//                       //             child: DropdownButton<String>(
//                       //           icon: Icon(Icons.keyboard_arrow_down_outlined),
//                       //           hint: country == null
//                       //               ? Text('Country'.tr())
//                       //               : Text(
//                       //                   country!,
//                       //                   style: TextStyle(
//                       //                       color: AppThemeData.primary500),
//                       //                 ),
//                       //           items: <String>[
//                       //             'USA',
//                       //             'UK',
//                       //             'India',
//                       //             'France',
//                       //             'Russia',
//                       //             'Japan',
//                       //             'UAE',
//                       //             'Qatar',
//                       //             'Netherland',
//                       //             'Canada'
//                       //           ].map((String value) {
//                       //             return DropdownMenuItem<String>(
//                       //               value: value,
//                       //               child: Text(value),
//                       //             );
//                       //           }).toList(),
//                       //           isExpanded: true,
//                       //           iconSize: 30.0,
//                       //           onChanged: (value) {
//                       //             setState(() {
//                       //               country = value;
//                       //             });
//                       //           },
//                       //         )))
//                       // ),
//                       // leading: Container(
//                       //   width: 60,
//                       //   child: Text(
//                       //     'Country'.tr(),
//                       //     style: TextStyle(fontWeight: FontWeight.bold),
//                       //   ),
//                       // ),
//                       // title: TextFormField(
//                       //   textAlignVertical: TextAlignVertical.center,
//                       //   textInputAction: TextInputAction.done,
//                       //   validator: validateEmptyField,
//                       //   onFieldSubmitted: (_) => validateForm(),
//                       //   maxLength: 2,
//                       //   onSaved: (text) => country = text,
//                       //   style: TextStyle(fontSize: 18.0),
//                       //   keyboardType: TextInputType.streetAddress,
//                       //   cursorColor: AppThemeData.primary500,
//                       //   initialValue: MyAppState.currentUser!.shippingAddress.country,
//                       //   decoration: InputDecoration(
//                       //     contentPadding: EdgeInsets.symmetric(horizontal: 24),
//                       //     hintText: 'UK'.tr(),
//                       //     hintStyle: TextStyle(color: Colors.grey.shade400),
//                       //     focusedBorder: OutlineInputBorder(
//                       //       borderRadius: BorderRadius.circular(8.0),
//                       //       borderSide:
//                       //           BorderSide(color: AppThemeData.primary500, width: 2.0),
//                       //     ),
//                       //     errorBorder: OutlineInputBorder(
//                       //       borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                       //       borderRadius: BorderRadius.circular(8.0),
//                       //     ),
//                       //     focusedErrorBorder: OutlineInputBorder(
//                       //       borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
//                       //       borderRadius: BorderRadius.circular(8.0),
//                       //     ),
//                       //     enabledBorder: OutlineInputBorder(
//                       //       borderSide: BorderSide(color: Colors.grey.shade300),
//                       //       borderRadius: BorderRadius.circular(8.0),
//                       //     ),
//                       //   ),
//                       // ),
//                       Padding(
//                         padding: const EdgeInsets.all(12.0),
//                         child: Card(
//                             child: ListTile(
//                                 leading: Column(
//                                   mainAxisAlignment: MainAxisAlignment.center,
//                                   children: [
//                                     // ImageIcon(
//                                     //   AssetImage('assets/images/current_location1.png'),
//                                     //   size: 23,
//                                     //   color: AppThemeData.primary500,
//                                     // ),
//                                     Icon(
//                                       Icons.location_searching_rounded,
//                                       color: AppThemeData.primary500,
//                                     ),
//                                   ],
//                                 ),
//                                 title: Text(
//                                   "Current Location".tr(),
//                                   style: TextStyle(color: AppThemeData.primary500),
//                                 ),
//                                 subtitle: Text(
//                                   "Using GPS".tr(),
//                                   style: TextStyle(color: AppThemeData.primary500),
//                                 ),
//                                 onTap: () async {
//                                   LocationResult result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => PlacePicker(GOOGLE_API_KEY)));
//
//                                   street1.text = result.name.toString();
//                                   landmark1.text = result.subLocalityLevel1!.name == null ? result.subLocalityLevel2!.name.toString() : result.subLocalityLevel1!.name.toString();
//                                   city1.text = result.city!.name.toString();
//                                   cutries1.text = result.country!.name.toString();
//                                   zipcode1.text = result.postalCode.toString();
//                                   lat = result.latLng!.latitude;
//                                   long = result.latLng!.longitude;
//
//                                   // MyAppState.currentUser!.shippingAddress.location.latitude = result.latLng!.latitude;
//                                   // MyAppState.currentUser!.shippingAddress.location.longitude = result.latLng!.longitude;
//                                   getDeliveyData();
//                                   setState(() {});
//                                 })),
//                       ),
//
//                       SizedBox(
//                         height: 40,
//                       ),
//
//                       Visibility(
//                         child: Text("Your new delivery charge will be".tr() + " ${amountShow(amount: deliveryCharges.toString())}",
//                             style: TextStyle(
//                                fontFamily: AppThemeData.regular,
//                             )),
//                         visible: isLocationChange,
//                       ),
//                     ],
//                   ),
//                 ),
//                 SizedBox()
//               ])))),
//       bottomNavigationBar: Padding(
//         padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 25),
//         child: ElevatedButton(
//           style: ElevatedButton.styleFrom(
//             padding: const EdgeInsets.all(15),
//             backgroundColor: AppThemeData.primary500,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(8),
//             ),
//           ),
//           onPressed: () => validateForm(),
//           child: Text(
//             'CONTINUE'.tr(),
//             style: TextStyle(color: isDarkMode(context) ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
//           ),
//         ),
//       ),
//     );
//   }
//
//   VendorModel? vendorModel;
//   var deliveryCharges = "0.0";
//   bool isLocationChange = false;
//
//   getDeliveyData() async {
//     print("delivery called");
//     if (!widget.takeAway!) {
//       print("caen id ${widget.products.first.vendorID} ");
//       await FireStoreUtils().getVendorByVendorID(widget.products.first.vendorID).then((value) {
//         vendorModel = value;
//       });
//       num km = num.parse(getKm(Position.fromMap({'latitude': lat, 'longitude': long}), Position.fromMap({'latitude': vendorModel!.latitude, 'longitude': vendorModel!.longitude})));
//       await FireStoreUtils().getDeliveryCharges().then((value) {
//         if (value != null) {
//           DeliveryChargeModel deliveryChargeModel = value;
//
//           if (!deliveryChargeModel.vendorCanModify) {
//             if (km > deliveryChargeModel.minimumDeliveryChargesWithinKm) {
//               deliveryCharges = (km * deliveryChargeModel.deliveryChargesPerKm).toDouble().toString();
//               if (widget.deliveryCharge != deliveryCharges) {
//                 isLocationChange = true;
//               }
//               setState(() {});
//             } else {
//               deliveryCharges = deliveryChargeModel.minimumDeliveryCharges.toDouble().toString();
//               if (widget.deliveryCharge != deliveryCharges) {
//                 isLocationChange = true;
//               }
//               setState(() {});
//             }
//           } else {
//             if (vendorModel != null && vendorModel!.deliveryCharge != null) {
//               if (km > vendorModel!.deliveryCharge!.minimumDeliveryChargesWithinKm) {
//                 deliveryCharges = (km * vendorModel!.deliveryCharge!.deliveryChargesPerKm).toDouble().toString();
//                 if (widget.deliveryCharge != deliveryCharges) {
//                   isLocationChange = true;
//                 }
//                 setState(() {});
//               } else {
//                 deliveryCharges = vendorModel!.deliveryCharge!.minimumDeliveryCharges.toDouble().toString();
//                 if (widget.deliveryCharge != deliveryCharges) {
//                   isLocationChange = true;
//                 }
//                 setState(() {});
//               }
//               print("delivery charges ${widget.deliveryCharge!}  dd $deliveryCharges");
//             } else {
//               if (km > deliveryChargeModel.minimumDeliveryChargesWithinKm) {
//                 deliveryCharges = (km * deliveryChargeModel.deliveryChargesPerKm).toDouble().toString();
//                 if (widget.deliveryCharge != deliveryCharges) {
//                   isLocationChange = true;
//                 }
//                 setState(() {});
//               } else {
//                 deliveryCharges = deliveryChargeModel.minimumDeliveryCharges.toDouble().toString();
//                 if (widget.deliveryCharge != deliveryCharges) {
//                   isLocationChange = true;
//                 }
//                 setState(() {});
//               }
//             }
//           }
//         }
//       });
//     }
//   }
//
//   validateForm() async {
//     // if (_formKey.currentState?.validate() ?? false) {
//     //   _formKey.currentState!.save();
//       // if (country == null) {
//       //   showDialog(
//       //     context: context,
//       //     builder: (BuildContext context) => ShowDialogToDismiss(
//       //       title: 'Error'.tr(),
//       //       content: 'Please Select Country'.tr(),
//       //       buttonText: 'CLOSE'.tr(),
//       //     ),
//       //   );
//       // } else
//       // {
//       //   showProgress(context, 'Saving Address...'.tr(), false);
//       //
//       //   MyAppState.currentUser!.location = UserLocation(
//       //     latitude: lat == null
//       //         ? MyAppState.currentUser!.shippingAddress.location!.latitude == 0.01
//       //             ? showDialog(
//       //                 barrierDismissible: false,
//       //                 context: context,
//       //                 builder: (_) {
//       //                   return AlertDialog(
//       //                     content: Text("Please select current address using GPS location. Move pin to exact location".tr()),
//       //                     actions: [
//       //                       // FlatButton(
//       //                       //   onPressed: () => Navigator.pop(
//       //                       //       context, false), // passing false
//       //                       //   child: Text('No'),
//       //                       // ),
//       //                       TextButton(
//       //                         onPressed: () {
//       //                           hideProgress();
//       //                           Navigator.pop(context, true);
//       //                         }, // passing true
//       //                         child: Text('OK'.tr()),
//       //                       ),
//       //                     ],
//       //                   );
//       //                 }).then((exit) {
//       //                 if (exit == null) return;
//       //
//       //                 if (exit) {
//       //                   // user pressed Yes button
//       //                 } else {
//       //                   // user pressed No button
//       //                 }
//       //               })
//       //             : MyAppState.currentUser!.shippingAddress.location!.latitude
//       //         : lat,
//       //     longitude: long == null
//       //         ? MyAppState.currentUser!.shippingAddress.location!.longitude == 0.01
//       //             ? showDialog(
//       //                 barrierDismissible: false,
//       //                 context: context,
//       //                 builder: (_) {
//       //                   return AlertDialog(
//       //                     content: Text("Please select current address using GPS location. Move pin to exact location".tr()),
//       //                     actions: [
//       //                       // FlatButton(
//       //                       //   onPressed: () => Navigator.pop(
//       //                       //       context, false), // passing false
//       //                       //   child: Text('No'),
//       //                       // ),
//       //                       TextButton(
//       //                         onPressed: () {
//       //                           hideProgress();
//       //                           Navigator.pop(context, true);
//       //                         }, // passing true
//       //                         child: Text('OK'.tr()),
//       //                       ),
//       //                     ],
//       //                   );
//       //                 }).then((exit) {
//       //                 if (exit == null) return;
//       //
//       //                 if (exit) {
//       //                   // user pressed Yes button
//       //                 } else {
//       //                   // user pressed No button
//       //                 }
//       //               })
//       //             : MyAppState.currentUser!.shippingAddress.location!.longitude
//       //         : long,
//       //     // locationData!.longitude,
//       //   );
//       //
//       //   AddressModel userAddress = AddressModel(
//       //       postalCode: zipcode.text.toString(),
//       //       address: street.text.toString(),
//       //       landmark: landmark.text.toString(),
//       //       country: cutries.text.toString(),
//       //       city: city.text.toString(),
//       //       location: MyAppState.currentUser!.location);
//       //   MyAppState.currentUser!.shippingAddress = userAddress;
//       //   await FireStoreUtils.updateCurrentUserAddress(userAddress);
//       //   hideProgress();
//       //   debugPrint('==>-  $isLocationChange');
//       //   debugPrint(widget.total.toString());
//       //   debugPrint(isLocationChange ? deliveryCharges.toString() : widget.deliveryCharge);
//       //   debugPrint(widget.couponCode!);
//       //   debugPrint(widget.couponId!);
//       //   push(
//       //     context,
//       //     PaymentScreen(
//       //       total: isLocationChange ? ((widget.total - num.parse(widget.deliveryCharge!)) + num.parse(deliveryCharges)) : widget.total,
//       //       discount: widget.discount!,
//       //       couponCode: widget.couponCode!,
//       //       couponId: widget.couponId!,
//       //       products: widget.products,
//       //       extraAddons: widget.extraAddons,
//       //       tipValue: widget.tipValue,
//       //       takeAway: widget.takeAway,
//       //       deliveryCharge: isLocationChange ? deliveryCharges.toString() : widget.deliveryCharge,
//       //       notes: widget.notes,
//       //       specialDiscountMap: widget.specialDiscountMap,
//       //       taxModel: widget.taxModel,
//       //       scheduleTime: widget.scheduleTime,
//       //     ),
//       //   );
//       // }
//     // } else {
//     //   setState(() {
//     //     _autoValidateMode = AutovalidateMode.onUserInteraction;
//     //   });
//     // }
//   }
// }

import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/auth_screen/login_screen.dart';
import 'package:emartconsumer/ui/deliveryAddressScreen/add_address_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DeliveryAddressScreen extends StatefulWidget {
  const DeliveryAddressScreen({super.key});

  @override
  State<DeliveryAddressScreen> createState() => _DeliveryAddressScreenState();
}

class _DeliveryAddressScreenState extends State<DeliveryAddressScreen> {
  List<AddressModel> shippingAddress = [];

  @override
  void initState() {
    super.initState();
    getListAddress();
  }

  void getListAddress() {
    setState(() {
      if (MyAppState.currentUser?.shippingAddress != null) {
        shippingAddress = MyAppState.currentUser!.shippingAddress!;
      }
    });
  }

  // ── icon helper ──────────────────────────────────────────────────────────
  IconData _labelIcon(String? label) {
    switch (label?.toLowerCase()) {
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

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
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
          'Delivery Address'.tr(),
          style: TextStyle(
            fontSize: 18,
            fontFamily: AppThemeData.semiBold,
            color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () async {
                if (MyAppState.currentUser != null) {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AddAddressScreen()))
                      .then((_) => getListAddress());
                } else {
                  Navigator.pop(context);
                  push(context, LoginScreen());
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppThemeData.primary500,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Add'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: AppThemeData.semiBold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1,
              color: dark ? AppThemeData.darkBorderSecondary : AppThemeData.neutral200),
        ),
      ),
      body: shippingAddress.isEmpty ? _buildEmptyState(dark) : _buildList(dark),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────
  Widget _buildEmptyState(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_off_rounded, size: 44, color: AppThemeData.primary500.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            Text(
              'No Saved Addresses'.tr(),
              style: TextStyle(
                fontSize: 18,
                fontFamily: AppThemeData.bold,
                color: dark ? AppThemeData.darkTextPrimary : AppThemeData.neutral900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a delivery address to get started with faster checkout.'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontFamily: AppThemeData.regular,
                height: 1.5,
                color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (MyAppState.currentUser != null) {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const AddAddressScreen()))
                        .then((_) => getListAddress());
                  } else {
                    Navigator.pop(context);
                    push(context, LoginScreen());
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeData.primary500,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 20),
                label: Text(
                  'Add New Address'.tr(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: AppThemeData.semiBold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Address list ─────────────────────────────────────────────────────────
  Widget _buildList(bool dark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: shippingAddress.length,
      itemBuilder: (context, index) {
        final addr = shippingAddress[index];
        return _AddressCard(
          addressModel: addr,
          dark: dark,
          labelIcon: _labelIcon(addr.addressAs),
          onTap: () => Navigator.pop(context, addr),
          onMore: () => _showActionSheet(context, index),
        );
      },
    );
  }

  // ── Action sheet (business logic unchanged) ──────────────────────────────
  void _showActionSheet(BuildContext context1, int index) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              await showProgress('Please wait...'.tr(), false);
              final tempList = shippingAddress.map((element) {
                element.isDefault = element.id == shippingAddress[index].id;
                return element;
              }).toList();
              MyAppState.currentUser!.shippingAddress = tempList;
              await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
              getListAddress();
              hideProgress();
              Navigator.pop(ctx);
            },
            child: Text('Set as Default'.tr(), style: const TextStyle(color: Colors.blue)),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => AddAddressScreen(index: index)))
                  .then((_) => getListAddress());
            },
            child: Text('Edit'.tr(), style: const TextStyle(color: Colors.blue)),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              shippingAddress.removeAt(index);
              MyAppState.currentUser!.shippingAddress = shippingAddress;
              FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
              getListAddress();
              Navigator.pop(ctx);
            },
            child: Text('Delete'.tr(), style: const TextStyle(color: AppThemeData.error500)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, 'Cancel'),
          child: Text('Cancel'.tr()),
        ),
      ),
    );
  }
}

// ── Address card widget ──────────────────────────────────────────────────────
class _AddressCard extends StatelessWidget {
  final AddressModel addressModel;
  final bool dark;
  final IconData labelIcon;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _AddressCard({
    required this.addressModel,
    required this.dark,
    required this.labelIcon,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = addressModel.isDefault == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDefault
            ? AppThemeData.primary500.withValues(alpha: 0.05)
            : (dark ? AppThemeData.darkBgSecondary : Colors.white),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDefault
                    ? AppThemeData.primary500
                    : (dark ? AppThemeData.darkBorderPrimary : AppThemeData.neutral200),
                width: isDefault ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDefault
                        ? AppThemeData.primary500.withValues(alpha: 0.12)
                        : (dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    labelIcon,
                    color: isDefault ? AppThemeData.primary500 : (dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral500),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Address info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Label badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDefault
                                  ? AppThemeData.primary500
                                  : (dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral100),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              (addressModel.addressAs ?? 'Other').tr(),
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: AppThemeData.semiBold,
                                color: isDefault ? Colors.white : (dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral600),
                              ),
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 11),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Default'.tr(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: AppThemeData.semiBold,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        addressModel.getFullAddress(),
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: AppThemeData.regular,
                          height: 1.45,
                          color: dark ? AppThemeData.darkTextSecondary : AppThemeData.neutral700,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Bottom action row
                      Row(
                        children: [
                          Icon(Icons.touch_app_rounded, size: 13,
                              color: AppThemeData.primary500.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to select'.tr(),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: AppThemeData.regular,
                              color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // More button
                GestureDetector(
                  onTap: onMore,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: dark ? AppThemeData.darkBgTertiary : AppThemeData.neutral100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: dark ? AppThemeData.darkTextTertiary : AppThemeData.neutral500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
