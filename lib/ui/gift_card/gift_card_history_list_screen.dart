import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:emartconsumer/constants.dart';
import 'package:emartconsumer/model/gift_cards_order_model.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:share_plus/share_plus.dart';

class GiftCardHistoryListScreen extends StatefulWidget {
  const GiftCardHistoryListScreen({super.key});

  @override
  State<GiftCardHistoryListScreen> createState() => _GiftCardHistoryListScreenState();
}

class _GiftCardHistoryListScreenState extends State<GiftCardHistoryListScreen> {
  @override
  void initState() {
    // TODO: implement initState
    getList();
    super.initState();
  }

  List<GiftCardsOrderModel> giftCardsOrderList = [];

  bool isLoading = true;

  getList() async {
    await FireStoreUtils().getGiftHistory().then((value) {
      setState(() {
        giftCardsOrderList = value;
      });
    });
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        title: Text("History", style: TextStyle(color: AppThemeData.primary500, fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: isLoading == true
          ? Center(
              child: CircularProgressIndicator(),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: giftCardsOrderList.isEmpty
                  ? Center(
                      child: Text("No History Found "),
                    )
                  : ListView.builder(
                      itemCount: giftCardsOrderList.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        GiftCardsOrderModel giftCardOrderModel = giftCardsOrderList[index];
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            decoration: BoxDecoration(color: isDarkMode(context) ? Color(DarkContainerColor) : Colors.white, borderRadius: BorderRadius.all(Radius.circular(12))),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          giftCardOrderModel.giftTitle.toString(),
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: isDarkMode(context) ? Colors.white : Colors.black,
                                             fontFamily: AppThemeData.semiBold
                                          ),
                                        ),
                                      ),
                                      Text(
                                        giftCardOrderModel.redeem == true ? "Redeemed" : "Not Redeem",
                                        style: TextStyle(
                                          color: giftCardOrderModel.redeem == true ? Colors.green : AppThemeData.primary500,
                                           fontFamily: AppThemeData.semiBold
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 10,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Gift code".toUpperCase(),
                                          style: TextStyle(
                                            color: isDarkMode(context) ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        giftCardOrderModel.giftCode.toString().replaceAllMapped(RegExp(r".{4}"), (match) => "${match.group(0)} "),
                                        style: TextStyle(
                                          color: isDarkMode(context) ? Colors.white : Colors.black,
                                           fontFamily: AppThemeData.semiBold
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "Gift Pin".toUpperCase(),
                                          style: TextStyle(
                                            color: isDarkMode(context) ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      giftCardOrderModel.isPasswordShow == true
                                          ? Text(
                                              giftCardOrderModel.giftPin.toString(),
                                              style: TextStyle(
                                                color: isDarkMode(context) ? Colors.white : Colors.black,
                                                 fontFamily: AppThemeData.semiBold
                                              ),
                                            )
                                          : Text(
                                              "****",
                                              style: TextStyle(
                                                color: isDarkMode(context) ? Colors.white : Colors.black,
                                                 fontFamily: AppThemeData.semiBold
                                              ),
                                            ),
                                      SizedBox(
                                        width: 10,
                                      ),
                                      giftCardOrderModel.isPasswordShow == true
                                          ? InkWell(
                                              onTap: () {
                                                setState(() {
                                                  giftCardOrderModel.isPasswordShow = false;
                                                });
                                              },
                                              child: Icon(Icons.visibility_off))
                                          : InkWell(
                                              onTap: () {
                                                setState(() {
                                                  giftCardOrderModel.isPasswordShow = true;
                                                });
                                              },
                                              child: Icon(Icons.remove_red_eye)),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          share(giftCardOrderModel.giftCode.toString(), giftCardOrderModel.giftPin.toString(), giftCardOrderModel.message.toString(),
                                              giftCardOrderModel.price.toString(), giftCardOrderModel.expireDate!);
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.all(Radius.circular(30)),
                                            color: AppThemeData.primary500,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text(
                                                  "Share",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                     fontFamily: AppThemeData.semiBold
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 5,
                                                ),
                                                Icon(
                                                  Icons.share,
                                                  size: 18,
                                                  color: Colors.white,
                                                )
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        amountShow(amount: giftCardOrderModel.price.toString()),
                                        style: TextStyle(
                                          color: isDarkMode(context) ? Colors.white : Colors.black,
                                           fontFamily: AppThemeData.semiBold
                                        ),
                                      )
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Future<void> share(String giftCode, String giftPin, String msg, String amount, Timestamp date) async {
    await Share.share(
      subject: 'Quickdash'.tr(),
       "Gift Code : $giftCode\nGift Pin : $giftPin\nPrice : ${amountShow(amount: amount)}\nExpire Date : ${date.toDate()}\n\nMessage : $msg",
    );
  }
}
