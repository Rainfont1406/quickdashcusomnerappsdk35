import 'package:cloud_firestore/cloud_firestore.dart';

class OfferModel {
  String? offerId;
  String? offerCode;
  String? descriptionOffer;
  String? discountOffer;
  String? discountTypeOffer;
  Timestamp? expireOfferDate;
  bool? isEnableOffer;
  bool? isPublic;
  String? imageOffer = "";
  String? storeId;
  String? parcelCategoryId;
  String? applicableAmount;

  OfferModel({this.descriptionOffer, this.discountOffer, this.discountTypeOffer, this.expireOfferDate, this.imageOffer = "", this.isEnableOffer, this.isPublic, this.offerCode, this.offerId, this.storeId, this.parcelCategoryId, this.applicableAmount});

  factory OfferModel.fromJson(Map<String, dynamic> parsedJson) {
    return OfferModel(
        descriptionOffer: parsedJson["description"],
        discountOffer: parsedJson["discount"],
        discountTypeOffer: parsedJson["discountType"],
        expireOfferDate: parsedJson["expiresAt"],
        imageOffer: parsedJson["image"] ?? ((parsedJson["photo"] ?? "")),
        isEnableOffer: parsedJson["isEnabled"],
        isPublic: parsedJson["isPublic"],
        offerCode: parsedJson["code"],
        offerId: parsedJson["id"],
        storeId: parsedJson["vendorID"],
        parcelCategoryId: parsedJson["parcelCategoryId"],
        applicableAmount: parsedJson["applicableAmount"]);
  }

  Map<String, dynamic> toJson() {
    return {
      "description": descriptionOffer,
      "discount": discountOffer,
      "discountType": discountTypeOffer,
      "expiresAt": expireOfferDate,
      "image": imageOffer,
      "isEnabled": isEnableOffer,
      "isPublic": isPublic,
      "code": offerCode,
      "id": offerId,
      "vendorID": storeId,
      "parcelCategoryId": parcelCategoryId,
      "applicableAmount": applicableAmount
    };
  }
}