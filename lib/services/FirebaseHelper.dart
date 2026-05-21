import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/AddressModel.dart';
import 'package:emartconsumer/model/AttributesModel.dart';
import 'package:emartconsumer/model/BannerModel.dart';
import 'package:emartconsumer/model/BlockUserModel.dart';
import 'package:emartconsumer/model/BookTableModel.dart';
import 'package:emartconsumer/model/BrandsModel.dart';
import 'package:emartconsumer/model/CabOrderModel.dart';
import 'package:emartconsumer/model/ChatVideoContainer.dart';
import 'package:emartconsumer/model/CodModel.dart';
import 'package:emartconsumer/model/CurrencyModel.dart';
import 'package:emartconsumer/model/DeliveryChargeModel.dart';
import 'package:emartconsumer/model/FavouriteItemModel.dart';
import 'package:emartconsumer/model/FavouriteModel.dart';
import 'package:emartconsumer/model/MercadoPagoSettingsModel.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/PayFastSettingData.dart';
import 'package:emartconsumer/model/ProductModel.dart';
import 'package:emartconsumer/model/Ratingmodel.dart';
import 'package:emartconsumer/model/RentalVehicleType.dart';
import 'package:emartconsumer/model/ReviewAttributeModel.dart';
import 'package:emartconsumer/model/SectionModel.dart';
import 'package:emartconsumer/model/TaxModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/VehicleType.dart';
import 'package:emartconsumer/model/VendorCategoryModel.dart';
import 'package:emartconsumer/model/VendorModel.dart';
import 'package:emartconsumer/model/conversation_model.dart';
import 'package:emartconsumer/model/email_template_model.dart';
import 'package:emartconsumer/model/favorite_ondemand_service_model.dart';
import 'package:emartconsumer/model/gift_cards_model.dart';
import 'package:emartconsumer/model/gift_cards_order_model.dart';
import 'package:emartconsumer/model/inbox_model.dart';
import 'package:emartconsumer/model/notification_model.dart';
import 'package:emartconsumer/model/offer_model.dart';
import 'package:emartconsumer/model/on_boarding_model.dart';
import 'package:emartconsumer/model/payment_model/mid_trans.dart';
import 'package:emartconsumer/model/payment_model/orange_money.dart';
import 'package:emartconsumer/model/payment_model/xendit.dart';
import 'package:emartconsumer/model/paypalSettingData.dart';
import 'package:emartconsumer/model/paytmSettingData.dart';
import 'package:emartconsumer/model/popular_destination.dart';
import 'package:emartconsumer/model/razorpayKeyModel.dart';
import 'package:emartconsumer/model/referral_model.dart';
import 'package:emartconsumer/model/story_model.dart';
import 'package:emartconsumer/model/stripeKey.dart';
import 'package:emartconsumer/model/stripeSettingData.dart';
import 'package:emartconsumer/model/topupTranHistory.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/ui/reauthScreen/reauth_user_screen.dart';
import 'package:emartconsumer/userPrefrence.dart';
import 'package:emartconsumer/widget/geoflutterfire/src/geoflutterfire.dart';
import 'package:emartconsumer/widget/geoflutterfire/src/models/point.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../constants.dart';
import '../model/FlutterWaveSettingDataModel.dart';
import '../model/PayStackSettingsModel.dart';

class FireStoreUtils {
  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
  static FirebaseFirestore firestore = FirebaseFirestore.instance;
  static Reference storage = FirebaseStorage.instance.ref();

  static String getCurrentUid() {
    return auth.FirebaseAuth.instance.currentUser!.uid;
  }

  static Future<bool> userExistOrNot(String uid) async {
    bool isExist = false;

    await firestore.collection(USERS).doc(uid).get().then(
      (value) {
        if (value.exists) {
          isExist = true;
        } else {
          isExist = false;
        }
      },
    ).catchError((error) {
      log("Failed to check user exist: $error");
      isExist = false;
    });
    return isExist;
  }

  static Future<User?> getUserProfile(String uuid) async {
    User? userModel;
    await firestore.collection(USERS).doc(uuid).get().then((value) {
      if (value.exists) {
        userModel = User.fromJson(value.data()!);
        MyAppState.currentUser = userModel;
      }
    }).catchError((error) {
      log("Failed to update user: $error");
      userModel = null;
    });
    return userModel;
  }

  static Future<List<OnBoardingModel>> getOnBoardingList() async {
    List<OnBoardingModel> onBoardingModel = [];
    await firestore.collection(ONBoarding).where("type",isEqualTo: "customer").get().then((value) {
      for (var element in value.docs) {
        OnBoardingModel documentModel = OnBoardingModel.fromJson(element.data());
        onBoardingModel.add(documentModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return onBoardingModel;
  }


  static Future<List<FavouriteItemModel>> getFavouriteItem() async {
    List<FavouriteItemModel> favouriteList = [];
    await firestore.collection(FavouriteItem).where('user_id', isEqualTo: getCurrentUid()).get().then(
      (value) {
        for (var element in value.docs) {
          FavouriteItemModel favouriteModel = FavouriteItemModel.fromJson(element.data());
          favouriteList.add(favouriteModel);
        }
      },
    );
    return favouriteList;
  }

  static Future<bool?> checkReferralCodeValidOrNot(String referralCode) async {
    bool? isExit;
    try {
      await firestore.collection(REFERRAL).where("referralCode", isEqualTo: referralCode).get().then((value) {
        if (value.size > 0) {
          isExit = true;
        } else {
          isExit = false;
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return false;
    }
    return isExit;
  }

  static Future<ReferralModel?> getReferralUserByCode(String referralCode) async {
    ReferralModel? referralModel;
    try {
      await firestore.collection(REFERRAL).where("referralCode", isEqualTo: referralCode).get().then((value) {
        if (value.docs.isNotEmpty) {
          referralModel = ReferralModel.fromJson(value.docs.first.data());
        }
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  static Future<ReferralModel?> getReferralUserBy() async {
    ReferralModel? referralModel;
    try {
      await firestore.collection(REFERRAL).doc(MyAppState.currentUser!.userID).get().then((value) {
        referralModel = ReferralModel.fromJson(value.data()!);
      });
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return referralModel;
  }

  List<BlockUserModel> blockedList = [];

  Future<List<StoryModel>> getStory() async {
    List<StoryModel> story = [];
    QuerySnapshot<Map<String, dynamic>> storyQuery = await firestore.collection(STORY).where('sectionID', isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(storyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        story.add(StoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return story;
  }

  static Future<List<AttributesModel>> getAttributes() async {
    List<AttributesModel> attributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(VENDOR_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        attributesList.add(AttributesModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return attributesList;
  }

  static Future<List<BrandsModel>> getBrands() async {
    List<BrandsModel> brandList = [];
    QuerySnapshot<Map<String, dynamic>> brandQuery = await firestore.collection(BRANDS).where('is_publish', isEqualTo: true).get();
    await Future.forEach(brandQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        brandList.add(BrandsModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return brandList;
  }

  static Future addRestaurantInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_store").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addRestaurantChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_store").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  static Future addDriverInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_driver").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addDriverChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_driver").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  Future<List<RatingModel>> getReviewList(String productId) async {
    List<RatingModel> reviewList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(Order_Rating).where('productId', isEqualTo: productId).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewList.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return reviewList;
  }

  static Future<List<ProductModel>> getProductListByCategoryId(String categoryId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('categoryID', isEqualTo: categoryId).where('publish', isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ProductModel>> getStoreProduct(String storeId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: storeId).where('publish', isEqualTo: true).limit(6).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ProductModel>> getProductListByBrandId(String brandId) async {
    List<ProductModel> productList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(PRODUCTS).where('brandID', isEqualTo: brandId).where('publish', isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        productList.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return productList;
  }

  static Future<List<ReviewAttributeModel>> getAllReviewAttributes() async {
    List<ReviewAttributeModel> reviewAttributesList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(REVIEW_ATTRIBUTES).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        reviewAttributesList.add(ReviewAttributeModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return reviewAttributesList;
  }

  late StreamController<OrderModel> ordersByIdStreamController;
  late StreamSubscription ordersByIdStreamSub;

  Stream<OrderModel?> getOrderByID(String inProgressOrderID) async* {
    ordersByIdStreamController = StreamController();
    ordersByIdStreamSub = firestore.collection(ORDERS).doc(inProgressOrderID).snapshots().listen((onData) async {
      if (onData.data() != null) {
        OrderModel? orderModel = OrderModel.fromJson(onData.data()!);
        ordersByIdStreamController.sink.add(orderModel);
      }
    });
    yield* ordersByIdStreamController.stream;
  }

  static Future<VendorModel?> getVendor(String vid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(VENDORS).doc(vid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return VendorModel.fromJson(userDocument.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  final geo = Geoflutterfire();
  late StreamController<List<User>> nearestDriverStreamController;

  Future setSos(String orderId, UserLocation userLocation) async {
    DocumentReference documentReference = firestore.collection(SOS).doc();
    Map<String, dynamic> sosMap = {'id': documentReference.id, 'orderId': orderId, 'status': "Initiated", 'latLong': userLocation.toJson()};
    await documentReference.set(sosMap);
  }

  Future<bool> getSOS(String orderId) async {
    bool isAdded = false;
    QuerySnapshot documentReference = await firestore.collection(SOS).where('orderId', isEqualTo: orderId).get();
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = true;
      }
    });

    return isAdded;
  }

  Future setRideComplain(
      {required String orderId,
      required String title,
      required String description,
      required String driverID,
      required String driverName,
      required String customerID,
      required String customerName}) async {
    DocumentReference documentReference = firestore.collection(complaints).doc();
    Map<String, dynamic> sosMap = {
      'id': documentReference.id,
      'createdAt': Timestamp.now(),
      'description': description,
      'driverId': driverID,
      'driverName': driverName,
      'orderId': orderId,
      'customerName': customerName,
      'customerId': customerID,
      'status': "Initiated",
      'title': title,
    };

    await documentReference.set(sosMap);
  }

  Future<bool> getRideComplain(String orderId) async {
    bool isAdded = false;
    QuerySnapshot documentReference = await firestore.collection(complaints).where('orderId', isEqualTo: orderId).get();
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = true;
      }
    });

    return isAdded;
  }

  Future<QueryDocumentSnapshot?> getRideComplainData(String orderId) async {
    QueryDocumentSnapshot? isAdded;
    QuerySnapshot documentReference = await firestore.collection(complaints).where('orderId', isEqualTo: orderId).get();
    documentReference.docs.forEach((element) {
      if (element['orderId'] == orderId) {
        isAdded = element;
      }
    });
    return isAdded;
  }

  late StreamController<User> driverStreamController;
  late StreamSubscription driverStreamSub;

  Stream<User> getDriver(String userId) async* {
    driverStreamController = StreamController();
    driverStreamSub = firestore.collection(USERS).doc(userId).snapshots().listen((onData) async {
      if (onData.data() != null) {
        User? user = User.fromJson(onData.data()!);
        driverStreamController.sink.add(user);
      }
    });
    yield* driverStreamController.stream;
  }

  static Future<List<VehicleType>> getVehicleType() async {
    List<VehicleType> vehicleType = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery =
        await firestore.collection(VEHICLETYPE).where('sectionId', isEqualTo: sectionConstantModel!.id).where("isActive", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vehicleType.add(VehicleType.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return vehicleType;
  }

  static Future<List<PopularDestination>> getPopularDestination() async {
    List<PopularDestination> popularDestination = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(POPULAR_DESTINATION).where('is_publish', isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        popularDestination.add(PopularDestination.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return popularDestination;
  }

  static Future<List<RentalVehicleType>> getRentalVehicleType() async {
    List<RentalVehicleType> vehicleType = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(RENTALVEHICLETYPE).where("isActive", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vehicleType.add(RentalVehicleType.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return vehicleType;
  }

  static Future<User?> getCurrentUser(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(USERS).doc(uid).get();
    if (userDocument.data() != null && userDocument.exists) {
      return User.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  Future<User?> getNearestDriver(LatLng? sourceLateLong) async {
    User? user;
    var collectionReference = firestore.collection(USERS).where("role", isEqualTo: "driver");

    GeoFirePoint center = geo.point(latitude: sourceLateLong!.latitude, longitude: sourceLateLong.longitude);

    String field = 'g';

    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: field, strictMode: true);

    stream.listen((List<DocumentSnapshot> documentList) {
      for (var document in documentList) {
        final data = document.data() as Map<String, dynamic>;
        user = User.fromJson(data);
      }
    });

    return user;
  }

  static Future<NotificationModel?> getNotificationContent(String type) async {
    NotificationModel? notificationModel;
    await firestore.collection(dynamicNotification).where('type', isEqualTo: type).get().then((value) {
      if (value.docs.isNotEmpty) {

        notificationModel = NotificationModel.fromJson(value.docs.first.data());
      } else {
        notificationModel = NotificationModel(id: "", message: "Notification setup is pending".tr(), subject: "setup notification".tr(), type: "");
      }
    });
    return notificationModel;
  }

  Future<TaxModel?> getTaxSetting() async {
    DocumentSnapshot<Map<String, dynamic>> taxQuery = await firestore.collection(Setting).doc('taxSetting').get();
    if (taxQuery.data() != null) {
      return TaxModel.fromJson(taxQuery.data()!);
    }
    return null;
  }

  Future<List<TaxModel>?> getTaxList(String? sectionId) async {
    List<TaxModel> taxList = [];
    await firestore.collection(tax).where('country', isEqualTo: country).where('sectionId', isEqualTo: sectionId).where('enable', isEqualTo: true).get().then((value) {
      for (var element in value.docs) {
        TaxModel taxModel = TaxModel.fromJson(element.data());
        taxList.add(taxModel);
      }
    }).catchError((error) {
      log(error.toString());
    });
    return taxList;
  }

  Future<String> uploadProductImage(File image, String progress) async {
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT +
        '/productImages/$uniqueID'
            '.png');
    UploadTask uploadTask = upload.putFile(image);
    uploadTask.whenComplete(() {}).catchError((onError) => print((onError as PlatformException).message));
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    return downloadUrl.toString();
  }

  static Future<ProductModel?> getProductById(String productId) async {
    ProductModel? vendorCategoryModel;
    try {
      await firestore.collection(PRODUCTS).doc(productId).get().then((value) {
        if (value.exists) {
          vendorCategoryModel = ProductModel.fromJson(value.data()!);
        }
      });
    } catch (e, s) {
      log('FireStoreUtils.firebaseCreateNewUser $e $s');
      return null;
    }
    return vendorCategoryModel;
  }

  static Future<User?> updateCurrentUser(User user) async {
    return await firestore.collection(USERS).doc(user.userID).set(user.toJson()).then((document) {
      MyAppState.currentUser = user;
      return user;
    });
  }

  static Future<void> updateCurrentUserAddress(AddressModel userAddress) async {
    //UserPreference.setUserId(userID: user.userID);
    return await firestore.collection(USERS).doc(MyAppState.currentUser!.userID).update(
      {"shippingAddress": userAddress.toJson()},
    ).then((document) {
      print("AAADDDDDD");
    });
  }

  static Future<ProductModel?> updateProduct(ProductModel prodduct) async {
    return await firestore.collection(PRODUCTS).doc(prodduct.id).set(prodduct.toJson()).then((document) {
      return prodduct;
    });
  }

  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
    return await firestore.collection(VENDORS).doc(vendor.id).set(vendor.toJson()).then((document) {
      return vendor;
    });
  }

  static Future<String> uploadUserImageToFireStorage(File image, String userID) async {
    Reference upload = storage.child(STORAGE_ROOT + '/User/images/$userID.png');
    UploadTask uploadTask = upload.putFile(image);
    var downloadUrl = await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  Future<Url> uploadChatImageToFireStorage(File image, BuildContext context) async {
    await showProgress("Please wait...".tr(), false);
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/chat/images/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(image);
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(mime: metaData.contentType ?? 'image', url: downloadUrl.toString());
  }

  Future<ChatVideoContainer> uploadChatVideoToFireStorage(File video, BuildContext context) async {
    await showProgress("Please wait...".tr(), false);
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/chat/videos/$uniqueID.mp4');
    File compressedVideo = await _compressVideo(video);
    SettableMetadata metadata = SettableMetadata(contentType: 'video');
    UploadTask uploadTask = upload.putFile(compressedVideo, metadata);
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    final uint8list = await VideoThumbnail.thumbnailFile(video: downloadUrl, thumbnailPath: (await getTemporaryDirectory()).path, imageFormat: ImageFormat.PNG);
    final file = File(uint8list ?? '');
    String thumbnailDownloadUrl = await uploadVideoThumbnailToFireStorage(file);
    hideProgress();
    return ChatVideoContainer(videoUrl: Url(url: downloadUrl.toString(), mime: metaData.contentType ?? 'video'), thumbnailUrl: thumbnailDownloadUrl);
  }

  Future<String> uploadVideoThumbnailToFireStorage(File file) async {
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/thumbnails/$uniqueID.png');
    UploadTask uploadTask = upload.putFile(file);
    var downloadUrl = await (await uploadTask.whenComplete(() {})).ref.getDownloadURL();
    return downloadUrl.toString();
  }

  Stream<User> getUserByID(String id) async* {
    StreamController<User> userStreamController = StreamController();
    firestore.collection(USERS).doc(id).snapshots().listen((user) {
      try {
        User userModel = User.fromJson(user.data() ?? {});
        userStreamController.sink.add(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
    yield* userStreamController.stream;
  }

  Future<List> getVendorCusions(String id) async {
    List tagList = [];
    List prodtagList = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: id).get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      if (document.data().containsKey("categoryID") && document.data()['categoryID'].toString().isNotEmpty) {
        prodtagList.add(document.data()['categoryID']);
      }
    });
    QuerySnapshot<Map<String, dynamic>> catQuery = await firestore.collection(CATEGORIES).where('publish', isEqualTo: true).get();
    await Future.forEach(catQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      Map<String, dynamic> catDoc = document.data();
      if (catDoc.containsKey("id") &&
          catDoc['id'].toString().isNotEmpty &&
          catDoc.containsKey("title") &&
          catDoc['title'].toString().isNotEmpty &&
          prodtagList.contains(catDoc['id'])) {
        tagList.add(catDoc['title']);
      }
    });

    return tagList;
  }

  Stream<StripeKeyModel> getStripe() async* {
    // ignore: close_sinks
    StreamController<StripeKeyModel> stripeStreamController = StreamController();
    firestore.collection(Setting).doc(StripeSetting).snapshots().listen((user) {
      try {
        StripeKeyModel userModel = StripeKeyModel.fromJson(user.data() ?? {});
        stripeStreamController.sink.add(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
    yield* stripeStreamController.stream;
  }

  static getRazorPay() async {
    // ignore: close_sinks
    firestore.collection(Setting).doc(StripeSetting).get().then((user) {
      try {
        RazorPayModel userModel = RazorPayModel.fromJson(user.data() ?? {});
        UserPreference.setRazorPayData(userModel);
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });
  }

  static getPayFastSettingData() async {
    firestore.collection(Setting).doc("payFastSettings").get().then((payFastData) {
      try {
        PayFastSettingData payFastSettingData = PayFastSettingData.fromJson(payFastData.data() ?? {});
        UserPreference.setPayFastData(payFastSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getPaypalSettingData() async {
    firestore.collection(Setting).doc("paypalSettings").get().then((paypalData) {
      try {
        PaypalSettingData payplaDataModel = PaypalSettingData.fromJson(paypalData.data() ?? {});
        UserPreference.setPayPalData(payplaDataModel);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getMercadoPagoSettingData() async {
    firestore.collection(Setting).doc("MercadoPago").get().then((mercadoPago) {
      try {
        MercadoPagoSettingData mercadoPagoDataModel = MercadoPagoSettingData.fromJson(mercadoPago.data() ?? {});
        UserPreference.setMercadoPago(mercadoPagoDataModel);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getStripeSettingData() async {
    firestore.collection(Setting).doc("stripeSettings").get().then((stripeData) {
      try {
        StripeSettingData stripeSettingData = StripeSettingData.fromJson(stripeData.data() ?? {});
        UserPreference.setStripeData(stripeSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getFlutterWaveSettingData() async {
    firestore.collection(Setting).doc("flutterWave").get().then((flutterWaveData) {
      try {
        FlutterWaveSettingData flutterWaveSettingData = FlutterWaveSettingData.fromJson(flutterWaveData.data() ?? {});

        UserPreference.setFlutterWaveData(flutterWaveSettingData);
      } catch (error) {}
    });
  }

  static getPayStackSettingData() async {
    firestore.collection(Setting).doc("payStack").get().then((payStackData) {
      try {
        PayStackSettingData payStackSettingData = PayStackSettingData.fromJson(payStackData.data() ?? {});
        UserPreference.setPayStackData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }


  static getOrangeMoneySettingData() async {
    firestore.collection(Setting).doc("orange_money_settings").get().then((payStackData) {
      try {
        OrangeMoney payStackSettingData = OrangeMoney.fromJson(payStackData.data() ?? {});
        UserPreference.setOrangeData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getXenditSettingData() async {
    firestore.collection(Setting).doc("xendit_settings").get().then((payStackData) {
      try {
        Xendit payStackSettingData = Xendit.fromJson(payStackData.data() ?? {});

        UserPreference.setXenditData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getMidTransSettingData() async {
    firestore.collection(Setting).doc("midtrans_settings").get().then((payStackData) {
      try {
        MidTrans payStackSettingData = MidTrans.fromJson(payStackData.data() ?? {});
        UserPreference.setMidTransData(payStackSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getPaytmSettingData() async {
    firestore.collection(Setting).doc("PaytmSettings").get().then((paytmData) {
      try {
        PaytmSettingData paytmSettingData = PaytmSettingData.fromJson(paytmData.data() ?? {});
        UserPreference.setPaytmData(paytmSettingData);
      } catch (error) {
        print(error.toString());
      }
    });
  }

  static getWalletSettingData() {
    firestore.collection(Setting).doc('walletSettings').get().then((walletSetting) {
      try {
        bool walletEnable = walletSetting.data()!['isEnabled'];
        UserPreference.setWalletData(walletEnable);
      } catch (e) {
        print(e.toString());
      }
    });
  }

  static getRazorPayDemo() async {
    RazorPayModel userModel;
    firestore.collection(Setting).doc("razorpaySettings").get().then((user) {
      try {
        userModel = RazorPayModel.fromJson(user.data() ?? {});
        UserPreference.setRazorPayData(userModel);
        RazorPayModel fhg = UserPreference.getRazorPayData();
      } catch (e) {
        print('FireStoreUtils.getUserByID failed to parse user object ${user.id}');
      }
    });

    //yield* razorPayStreamController.stream;
  }

  Future<CodModel?> getCod() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery = await firestore.collection(Setting).doc('CODSettings').get();
    if (codQuery.data() != null) {
      return CodModel.fromJson(codQuery.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<DeliveryChargeModel?> getDeliveryCharges() async {
    DocumentSnapshot<Map<String, dynamic>> codQuery = await firestore.collection(Setting).doc('DeliveryCharge').get();
    if (codQuery.data() != null) {
      return DeliveryChargeModel.fromJson(codQuery.data()!);
    } else {
      return null;
    }
  }

  static Future<List<SectionModel>> getSections() async {
    List<SectionModel> sections = [];
    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(SECTION).where("isActive", isEqualTo: true).get();

    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        sections.add(SectionModel.fromJson(document.data()));
      } catch (e) {
        print('**-FireStoreUtils.getSection Parse error $e');
      }
    });

    return sections;
  }

  Future<SectionModel?> getSectionsById(String? sectionId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(SECTION).doc(sectionId).get();
    if (userDocument.data() != null && userDocument.exists) {
      return SectionModel.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  Future<List<ProductModel>> getAllProducts() async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery =
        await firestore.collection(PRODUCTS).where("section_id", isEqualTo: sectionConstantModel!.id).where('publish', isEqualTo: true).get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('productspppp**-FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return products;
  }

  Future<List<ProductModel>> getAllDelevryProducts() async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        // .where("deliveryOption", isEqualTo: true)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('productspppp**-FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return products;
  }

  Future<List<ProductModel>> getAllTakeAWayProducts() async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        // .where("takeawayOption", isEqualTo: true)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('productspppp**-123--FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return products;
  }

  Future<bool> blockUser(User blockedUser, String type) async {
    bool isSuccessful = false;
    BlockUserModel blockUserModel = BlockUserModel(type: type, source: MyAppState.currentUser!.userID, dest: blockedUser.userID, createdAt: Timestamp.now());
    await firestore.collection(REPORTS).add(blockUserModel.toJson()).then((onValue) {
      isSuccessful = true;
    });
    return isSuccessful;
  }

  Stream<bool> getBlocks() async* {
    StreamController<bool> refreshStreamController = StreamController();
    firestore.collection(REPORTS).where('source', isEqualTo: MyAppState.currentUser!.userID).snapshots().listen((onData) {
      List<BlockUserModel> list = [];
      for (DocumentSnapshot<Map<String, dynamic>> block in onData.docs) {
        list.add(BlockUserModel.fromJson(block.data() ?? {}));
      }
      blockedList = list;
      refreshStreamController.sink.add(true);
    });
    yield* refreshStreamController.stream;
  }

  bool validateIfUserBlocked(String userID) {
    for (BlockUserModel blockedUser in blockedList) {
      if (userID == blockedUser.dest) {
        return true;
      }
    }
    return false;
  }

  Future<Url> uploadAudioFile(File file, BuildContext context) async {
    await showProgress("Please wait...".tr(), false);
    var uniqueID = const Uuid().v4();
    Reference upload = storage.child(STORAGE_ROOT + '/audio/$uniqueID.mp3');
    SettableMetadata metadata = SettableMetadata(contentType: 'audio');
    UploadTask uploadTask = upload.putFile(file, metadata);
    uploadTask.whenComplete(() {}).catchError((onError) => print((onError as PlatformException).message));
    var storageRef = (await uploadTask.whenComplete(() {})).ref;
    var downloadUrl = await storageRef.getDownloadURL();
    var metaData = await storageRef.getMetadata();
    hideProgress();
    return Url(mime: metaData.contentType ?? 'audio', url: downloadUrl.toString());
  }

  Future<List<VendorCategoryModel>> getCuisines() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery =
        await firestore.collection(CATEGORIES).where("section_id", isEqualTo: sectionConstantModel!.id).where('publish', isEqualTo: true).get();
    await Future.forEach(cuisinesQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return cuisines;
  }

  Future<List<VendorCategoryModel>> getHomePageShowCategory() async {
    List<VendorCategoryModel> cuisines = [];
    QuerySnapshot<Map<String, dynamic>> cuisinesQuery = await firestore
        .collection(CATEGORIES)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where("show_in_homepage", isEqualTo: true)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(cuisinesQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        cuisines.add(VendorCategoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return cuisines;
  }

  Stream<List<VendorModel>> getAllDineInRestaurants() {
    return firestore
        .collection(VENDORS)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where("enabledDiveInFuture", isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final List<VendorModel> vendors = [];
      for (var doc in snapshot.docs) {
        try {
          vendors.add(VendorModel.fromJson(doc.data()));
        } catch (e) {
          print('getAllDineInRestaurants parse error: $e');
        }
      }
      return vendors;
    });
  }

  late StreamSubscription vendorStreamSub;
  StreamController<List<VendorModel>>? vendorStreamController;

  Stream<List<VendorModel>> getVendors1({String? path}) {
    final query = (path == null || path.isEmpty)
        ? firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id)
        : firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id).where("enabledDiveInFuture", isEqualTo: true);

    return query.snapshots().map((snapshot) {
      final List<VendorModel> vendors = [];
      for (var doc in snapshot.docs) {
        try {
          vendors.add(VendorModel.fromJson(doc.data()));
        } catch (e) {
          print('getVendors1 parse error: $e');
        }
      }
      return vendors;
    });
  }

  Future<List<VendorModel>> getVendors() async {
    List<VendorModel> vendors = [];
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vendors.add(VendorModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return vendors;
  }

  Stream<List<BookTableModel>> getBookingOrders(String userID, bool isUpComing) async* {
    List<BookTableModel> orders = [];

    if (isUpComing) {
      StreamController<List<BookTableModel>> upcomingordersStreamController = StreamController();
      firestore
          .collection(ORDERS_TABLE)
          .where('author.id', isEqualTo: userID)
          .where('date', isGreaterThan: Timestamp.now())
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((onData) async {
        await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
          } catch (e, s) {
            print('booktable parse error ${element.id} $e $s');
          }
        });
        upcomingordersStreamController.sink.add(orders);
      });
      yield* upcomingordersStreamController.stream;
    } else {
      StreamController<List<BookTableModel>> bookedordersStreamController = StreamController();
      firestore
          .collection(ORDERS_TABLE)
          .where('author.id', isEqualTo: userID)
          .where('date', isLessThan: Timestamp.now())
          .where("section_id", isEqualTo: sectionConstantModel!.id)
          .orderBy('date', descending: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((onData) async {
        await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
          try {
            orders.add(BookTableModel.fromJson(element.data()));
          } catch (e, s) {
            print('booktable parse error ${element.id} $e $s');
          }
        });
        bookedordersStreamController.sink.add(orders);
      });
      yield* bookedordersStreamController.stream;
    }
  }

  late StreamSubscription ordersStreamSub;
  late StreamController<List<OrderModel>> ordersStreamController;

  Stream<List<OrderModel>> getOrders(String userID) async* {
    List<OrderModel> orders = [];
    ordersStreamController = StreamController();
    ordersStreamSub = firestore
        .collection(ORDERS)
        .where('authorID', isEqualTo: userID)
        .where('section_id', isEqualTo: sectionConstantModel!.id)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((onData) async {
      orders.clear();

      await Future.forEach(onData.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          OrderModel orderModel = OrderModel.fromJson(element.data());
          if (!orders.contains(orderModel)) {
            orders.add(orderModel);
          }
        } catch (e, s) {
          print('watchOrdersStatus parse error ${element.id} $e $s');
        }
      });
      ordersStreamController.sink.add(orders);
    });
    yield* ordersStreamController.stream;
  }

  closeOrdersStream() {
    ordersStreamSub.cancel();
    ordersStreamController.close();
  }

  static setFavouriteStore(FavouriteModel favouriteModel) {
    firestore.collection(FavouriteStore).add(favouriteModel.toJson()).then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  static removeFavouriteStore(FavouriteModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteStore)
        .where("store_id", isEqualTo: favouriteModel.store_id)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .get()
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance.collection(FavouriteStore).doc(element.id).delete().then((value) {
          print("Success!");
        });
      }
    });
  }

  Future<List<FavouriteItemModel>> getFavouritesProductList(String userId) async {
    List<FavouriteItemModel> lstFavourites = [];

    QuerySnapshot<Map<String, dynamic>> favourites =
        await firestore.collection(FavouriteItem).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(favourites.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        lstFavourites.add(FavouriteItemModel.fromJson(document.data()));
      } catch (e) {
        print('FavouriteModel.getCurrencys Parse error $e');
      }
    });
    return lstFavourites;
  }

  Future<List<FavouriteOndemandServiceModel>> getFavouritesServiceList(
    String userId,
  ) async {
    List<FavouriteOndemandServiceModel> lstFavourites = [];

    QuerySnapshot<Map<String, dynamic>> favourites =
        await firestore.collection(FavouriteOndemandItem).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(favourites.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        lstFavourites.add(FavouriteOndemandServiceModel.fromJson(document.data()));
      } catch (e) {
        print('FavouriteModel.getCurrencys Parse error $e');
      }
    });
    return lstFavourites;
  }

  Future<void> setFavouriteStoreItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).add(favouriteModel.toJson()).then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  Future<void> setFavouriteOndemandSection(FavouriteOndemandServiceModel favouriteModel) async {
    await firestore.collection(FavouriteOndemandItem).add(favouriteModel.toJson()).then((value) {
      print("===FAVOURITE ADDED===");
    });
  }

  void removeFavouriteOndemandService(FavouriteOndemandServiceModel favouriteModel) {
    FirebaseFirestore.instance
        .collection(FavouriteOndemandItem)
        .where("user_id", isEqualTo: favouriteModel.user_id)
        .where("service_id", isEqualTo: favouriteModel.service_id)
        .get()
        .then((value) {
      for (var element in value.docs) {
        FirebaseFirestore.instance.collection(FavouriteOndemandItem).doc(element.id).delete().then((value) {
          print("Remove Success!");
        });
      }
    });
  }

  /*closeFavouriteStream() {
    favouriteStreamSub.cancel();
    favouriteStreamControleer.close();
  }*/

  StreamController<List<VendorModel>>? allResaturantStreamController;

  Stream<List<VendorModel>> getAllStores() async* {
    allResaturantStreamController = StreamController<List<VendorModel>>.broadcast();

    try {
      var collectionReference = firestore.collection(VENDORS).where("section_id", isEqualTo: sectionConstantModel!.id);

      GeoFirePoint center = geo.point(latitude: MyAppState.selectedPosotion.location!.latitude, longitude: MyAppState.selectedPosotion.location!.longitude);

      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: 'g', strictMode: true);

      stream.listen((List<DocumentSnapshot> documentList) {
        // Rebuild fresh on every Geofire event — never accumulate, never close early
        final List<VendorModel> vendors = [];
        for (var document in documentList) {
          try {
            final data = document.data() as Map<String, dynamic>;
            vendors.add(VendorModel.fromJson(data));
          } catch (e) {
            print('getAllStores parse error: $e');
          }
        }
        if (allResaturantStreamController?.isClosed == false) {
          allResaturantStreamController!.add(vendors);
        }
      });
    } catch (e) {
      print('getAllStores setup error: $e');
    }

    yield* allResaturantStreamController!.stream;
  }

  closeVendorStream() {
    if (vendorStreamController != null) {
      vendorStreamController!.close();
    }
    if (allResaturantStreamController != null) {
      allResaturantStreamController!.close();
    }
    //newArrivalStreamController.close();
    //productStreamController123.close();
    //productStreamController.close();
  }

  late StreamController<List<VendorModel>> cusionStreamController;

  Stream<List<VendorModel>> getVendorsByCuisineID(String cuisineID, {bool? isDinein}) async* {
    cusionStreamController = StreamController<List<VendorModel>>.broadcast();
    var collectionReference = isDinein!
        ? firestore.collection(VENDORS).where('categoryID', isEqualTo: cuisineID).where("enabledDiveInFuture", isEqualTo: true)
        : firestore.collection(VENDORS).where('categoryID', isEqualTo: cuisineID);

    GeoFirePoint center = geo.point(latitude: MyAppState.selectedPosotion.location!.latitude, longitude: MyAppState.selectedPosotion.location!.longitude);
    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(center: center, radius: double.parse(sectionConstantModel!.nearByRadius.toString()), field: 'g', strictMode: true);
    stream.listen((List<DocumentSnapshot> documentList) {
      // Rebuild fresh on every Geofire event — never accumulate, never close early
      final List<VendorModel> vendors = [];
      for (var element in documentList) {
        try {
          final data = element.data() as Map<String, dynamic>;
          vendors.add(VendorModel.fromJson(data));
        } catch (e) {
          print('getVendorsByCuisineID parse error: $e');
        }
      }
      if (!cusionStreamController.isClosed) {
        cusionStreamController.add(vendors);
      }
    });

    yield* cusionStreamController.stream;
  }

  Future<List<OfferModel>> getViewAllOffer() async {
    List<OfferModel> offersData = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(COUPONS).where("isEnabled", isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offersData.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return offersData;
  }

  // Stream<List<OfferModel>>? getOfferStream() async* {
  //   List<OfferModel> offers = [];
  //   offerStreamController = StreamController<List<OfferModel>>.broadcast();
  //   var date = DateTime.now();
  //
  //   offerStreamSub = firestore
  //       .collection(COUPONS)
  //       .where("isEnabled", isEqualTo: true)
  //       .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()))
  //       .snapshots()
  //       .listen((event) async {
  //     offers.clear();
  //     if (event.docs.isEmpty) {
  //       offerStreamController!.add(offers);
  //     } else {
  //       await Future.forEach(event.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
  //         try {
  //           offers.add(OfferModel.fromJson(element.data()));
  //         } catch (e, s) {
  //           print('getOrder parse error ${element.id}$e $s');
  //         }
  //       });
  //       offerStreamController!.add(offers);
  //     }
  //
  //     print(offers.length.toString() + "{}{}====+++999");
  //   });
  //   yield* offerStreamController!.stream;
  // }

  StreamController<List<OfferModel>>? offerStreamController;
  StreamSubscription? offerStreamSub;

  Stream<List<OfferModel>> getOfferStreamByVendorID(String vendorID) async* {
    List<OfferModel> offers = [];
    offerStreamController = StreamController<List<OfferModel>>();
    offerStreamSub = firestore
        .collection(COUPONS)
        .where("vendorID", isEqualTo: vendorID)
        .where("isEnabled", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .snapshots()
        .listen((event) async {
      offers.clear();
      await Future.forEach(event.docs, (QueryDocumentSnapshot<Map<String, dynamic>> element) {
        try {
          offers.add(OfferModel.fromJson(element.data()));
        } catch (e, s) {
          print('getProductsStream parse error ${element.id}$e $s');
        }
      });
      offerStreamController!.add(offers);
    });
    yield* offerStreamController!.stream;
  }

  Future<List<OfferModel>> getOfferByVendorID(String vendorID) async {
    List<OfferModel> offers = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(COUPONS)
        .where("vendorID", isEqualTo: vendorID)
        .where("isEnabled", isEqualTo: true)
        .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();
    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  closeOfferStream() {
    if (offerStreamSub != null) {
      offerStreamSub!.cancel();
    }
    if (offerStreamController != null) {
      offerStreamController!.close();
    }
  }


  static Future removeFavouriteItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).where("product_id", isEqualTo: favouriteModel.product_id).get().then((value) {
      value.docs.forEach((element) async {
        await firestore.collection(FavouriteItem).doc(element.id).delete();
      });
    });
  }

  static Future<void> setFavouriteItem(FavouriteItemModel favouriteModel) async {
    await firestore.collection(FavouriteItem).add(favouriteModel.toJson());
  }

  Future<List<BannerModel>> getHomeTopBanner() async {
    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where('sectionId', isEqualTo: sectionConstantModel!.id)
        .where("position", isEqualTo: "top")
        .orderBy("set_order", descending: false)
        .get();

    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return bannerHome;
  }

  Future<List<BannerModel>> getHomeMiddleBanner() async {
    List<BannerModel> bannerHome = [];
    QuerySnapshot<Map<String, dynamic>> bannerHomeQuery = await firestore
        .collection(MENU_ITEM)
        .where("is_publish", isEqualTo: true)
        .where('sectionId', isEqualTo: sectionConstantModel!.id)
        .where("position", isEqualTo: "middle")
        .orderBy("set_order", descending: false)
        .get();

    await Future.forEach(bannerHomeQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        bannerHome.add(BannerModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return bannerHome;
  }

  /*Future<List<CurrencyModel>> getCurrency() async {
    List<CurrencyModel> currency = [];

    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(Currency).where("isActive", isEqualTo: true).get();
    print(currencyQuery.docs);
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        currency.add(CurrencyModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCurrencys Parse error $e');
      }
    });
    return currency;
  }*/
  Future<CurrencyModel?> getCurrency() async {
    CurrencyModel? currency;
    await firestore.collection(Currency).where("isActive", isEqualTo: true).get().then((value) {
      if (value.docs.isNotEmpty) {
        currency = CurrencyModel.fromJson(value.docs.first.data());
      }
    });
    return currency;
  }

  Future<List<OfferModel>> getPublicCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(COUPON).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).where("isEnabled", isEqualTo: true).where("isPublic", isEqualTo: true).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<OfferModel>> getAllCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(COUPON).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<OfferModel>> getOfferByCabCoupons() async {
    List<OfferModel> offers = [];

    QuerySnapshot<Map<String, dynamic>> offerQuery = await firestore
        .collection(CAB_COUPONS)
        .where("isEnabled", isEqualTo: true)
        // .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(offerQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  Future<List<OfferModel>> getCabCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(CAB_COUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<OfferModel>> getOfferByParcelID(String? parcelCategoryId) async {
    List<OfferModel> offers = [];

    QuerySnapshot<Map<String, dynamic>> offerQuery = await firestore
        .collection(PARCELCOUPONS)
        .where("isEnabled", isEqualTo: true)
        //  .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(offerQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  Future<List<OfferModel>> getParcelCoupan() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(PARCELCOUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<OfferModel>> getOfferByRentalCoupons() async {
    List<OfferModel> offers = [];

    QuerySnapshot<Map<String, dynamic>> offerQuery = await firestore
        .collection(RENTALCOUPONS)
        .where("isEnabled", isEqualTo: true)
        //  .where("isPublic", isEqualTo: true)
        .where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now())
        .get();

    await Future.forEach(offerQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        offers.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getCuisines Parse error $e');
      }
    });
    return offers;
  }

  Future<List<OfferModel>> getRentalCoupons() async {
    List<OfferModel> coupon = [];

    QuerySnapshot<Map<String, dynamic>> couponsQuery =
        await firestore.collection(RENTALCOUPONS).where('isEnabled', isEqualTo: true).where('expiresAt', isGreaterThanOrEqualTo: Timestamp.now()).get();
    await Future.forEach(couponsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        coupon.add(OfferModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    return coupon;
  }

  Future<List<ProductModel>> getVendorProducts(String vendorID) async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(PRODUCTS).where('vendorID', isEqualTo: vendorID).where('publish', isEqualTo: true).get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendorProducts Parse error $e');
      }
    });
    return products;
  }

  Future<List<ProductModel>> getVendorProductsTakeAWay(String vendorID) async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: vendorID)
        // .where('takeaway', isEqualTo: true)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendorProducts Parse error $e');
      }
    });
    return products;
  }

  Future<List<ProductModel>> getVendorProductsDelivery(String vendorID) async {
    List<ProductModel> products = [];

    QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore
        .collection(PRODUCTS)
        .where('vendorID', isEqualTo: vendorID)
        // .where('deliveryOption', isEqualTo: true)
        .where('publish', isEqualTo: true)
        .get();
    await Future.forEach(productsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        products.add(ProductModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendorProducts Parse error $e');
      }
    });
    return products;
  }

  //  Future<List<ProductModel>> updatevendorProduct(ProductModel productModel) async {
  //   return await firestore
  //       .collection(PRODUCTS)
  //       .doc(productModel.id).collection("quentity").doc(productModel.quantity)
  //       .set(user.toJson())
  //       .then((document) {
  //     return user;
  //   });
  // }
//  static Future<VendorModel?> updateVendor(VendorModel vendor) async {
//     return await firestore
//         .collection(VENDORS)
//         .doc(vendor.id)
//         .set(vendor.toJson())
//         .then((document) {
//       return vendor;
//     });
//   }

  static Future<VendorCategoryModel?> getVendorCategoryById(String vendorCategoryID) async {
    VendorCategoryModel? vendorCategoryModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(CATEGORIES)
        .where('id', isEqualTo: vendorCategoryID)
        .where("section_id", isEqualTo: sectionConstantModel!.id)
        .where('publish', isEqualTo: true)
        .get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        vendorCategoryModel = VendorCategoryModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return vendorCategoryModel;
  }

  Future<VendorCategoryModel?> getVendorCategoryByCategoryId(String vendorCategoryID) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore.collection(CATEGORIES).doc(vendorCategoryID).get();
    if (documentReference.data() != null && documentReference.exists) {
      return VendorCategoryModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<ReviewAttributeModel?> getVendorReviewAttribute(String attrubuteId) async {
    DocumentSnapshot<Map<String, dynamic>> documentReference = await firestore.collection(REVIEW_ATTRIBUTES).doc(attrubuteId).get();
    if (documentReference.data() != null && documentReference.exists) {
      return ReviewAttributeModel.fromJson(documentReference.data()!);
    } else {
      print("nulllll");
      return null;
    }
  }

  Future<VendorModel> getVendorByVendorID(String vendorID) async {
    late VendorModel vendor;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(VENDORS).where('id', isEqualTo: vendorID).get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        vendor = VendorModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return vendor;
  }

  Future<ProductModel> getProductByProductID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(PRODUCTS).where('id', isEqualTo: productId).where('publish', isEqualTo: true).get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  Future<ProductModel> getProductByID(String productId) async {
    late ProductModel productModel;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(PRODUCTS).where('id', isEqualTo: productId).get();
    try {
      if (vendorsQuery.docs.isNotEmpty) {
        productModel = ProductModel.fromJson(vendorsQuery.docs.first.data());
      }
    } catch (e) {
      print('FireStoreUtils.getVendorByVendorID Parse error $e');
    }
    return productModel;
  }

  Future<RatingModel?> getReviewsbyID(String ordertId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  Future<RatingModel?> getReviewsbyProviderID(String ordertId, String providerId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('VendorId', isEqualTo: providerId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  Future<RatingModel?> getReviewsbyWorkerID(String ordertId, String workerId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('driverId', isEqualTo: workerId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  Future<RatingModel?> getOrderReviewsbyID(String ordertId, String productId) async {
    RatingModel? ratingproduct;
    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(Order_Rating).where('orderid', isEqualTo: ordertId).where('productId', isEqualTo: productId).get();
    if (vendorsQuery.docs.isNotEmpty) {
      try {
        if (vendorsQuery.docs.isNotEmpty) {
          ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
        }
      } catch (e) {
        print('FireStoreUtils.getVendorByVendorID Parse error $e');
      }
    }
    return ratingproduct;
  }

  // Future<RatingModel> getReviewsbyVendorID(String vendorId) async {
  //   late RatingModel ratingproduct;
  //   QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
  //       .collection(Order_Rating)
  //       .where('VendorId', isEqualTo: vendorId)
  //       .get();
  //   try {
  //     ratingproduct = RatingModel.fromJson(vendorsQuery.docs.first.data());
  //   } catch (e) {
  //     print('FireStoreUtils.getVendorByVendorID Parse error $e');
  //   }
  //   return ratingproduct;
  // }

  Future<List<RatingModel>> getReviewsbyVendorID(String vendorId) async {
    List<RatingModel> vendorreview = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(Order_Rating)
        .where('VendorId', isEqualTo: vendorId)
        // .orderBy('createdAt', descending: true)
        .get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vendorreview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getOrders Parse error ${document.id} $e');
      }
    });
    return vendorreview;
  }

  Future<List<RatingModel>> getReviewByDriverId(String driverId) async {
    List<RatingModel> vendorreview = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery = await firestore
        .collection(Order_Rating)
        .where('driverId', isEqualTo: driverId)
        // .orderBy('createdAt', descending: true)
        .get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        vendorreview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getOrders Parse error ${document.id} $e');
      }
    });
    return vendorreview;
  }

  static Future<RatingModel?> updateReviewbyId(RatingModel ratingproduct) async {
    return await firestore.collection(Order_Rating).doc(ratingproduct.id).set(ratingproduct.toJson()).then((document) {
      return ratingproduct;
    });
  }

  static Future<List<FavouriteModel>> getFavouriteStore(String userId) async {
    List<FavouriteModel> favouriteItem = [];

    QuerySnapshot<Map<String, dynamic>> vendorsQuery =
        await firestore.collection(FavouriteStore).where('user_id', isEqualTo: userId).where("section_id", isEqualTo: sectionConstantModel!.id).get();
    await Future.forEach(vendorsQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        favouriteItem.add(FavouriteModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getVendors Parse error $e');
      }
    });
    return favouriteItem;
  }

  Future<BookTableModel> bookTable(BookTableModel orderModel) async {
    DocumentReference documentReference = firestore.collection(ORDERS_TABLE).doc();
    orderModel.id = documentReference.id;
    await documentReference.set(orderModel.toJson());
    return orderModel;
  }

  static Future<int> getSlotBookingCount({
    required String vendorId,
    required String slotId,
    required DateTime date,
  }) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snapshot = await firestore
        .collection(ORDERS_TABLE)
        .where('vendorID', isEqualTo: vendorId)
        .where('slotId', isEqualTo: slotId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .get();
    return snapshot.docs.where((doc) {
      final status = doc.data()['status'] as String? ?? '';
      return status != 'Cancelled' && status != 'Rejected';
    }).length;
  }

  Future<OrderModel> placeOrder(OrderModel orderModel) async {
    DocumentReference documentReference = firestore.collection(ORDERS).doc(orderModel.id);
    orderModel.id = documentReference.id;
    await documentReference.set(orderModel.toJson());
    return orderModel;
  }

  Future<OrderModel> placeOrderWithTakeAWay(OrderModel orderModel) async {
    DocumentReference documentReference;
    if (orderModel.id.isEmpty) {
      documentReference = firestore.collection(ORDERS).doc();
      orderModel.id = documentReference.id;
    } else {
      documentReference = firestore.collection(ORDERS).doc(orderModel.id);
    }
    await documentReference.set(orderModel.toJson());
    return orderModel;
  }

  static Future<List<TopupTranHistoryModel>> getTopUpTransaction() async {
    final userId = MyAppState.currentUser!.userID; //UserPreference.getUserId();
    List<TopupTranHistoryModel> topUpHistoryList = [];
    QuerySnapshot<Map<String, dynamic>> documentReference = await firestore.collection(Wallet).where('user_id', isEqualTo: userId).get();
    await Future.forEach(documentReference.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        topUpHistoryList.add(TopupTranHistoryModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getAllProducts Parse error $e');
      }
    });
    // QuerySnapshot<Map<String, dynamic>> productsQuery = await firestore.collection(Wallet).get();
    // await Future.forEach(productsQuery.docs,
    //         (QueryDocumentSnapshot<Map<String, dynamic>> document) {
    //       try {
    //         products.add(TopupTranHistoryModel.fromJson(document.data()));
    //       } catch (e) {
    //         print('FireStoreUtils.getAllProducts Parse error $e');
    //       }
    //     });

    // final paymentId = documentReference;
    // UserPreference.setPaymentId(paymentId: paymentId);
    return topUpHistoryList;
  }

  // static Future topUpWalletAmount({String serviceType = "", String paymentMethod = "test", bool isTopup = true, required amount, required id, orderId = ""}) async {
  //   print("this is te payment id");
  //   print(id);
  //   print(MyAppState.currentUser!.userID);
  //
  //   await firestore.collection(Wallet).doc(id).set({
  //     "serviceType": serviceType,
  //     "user_id": MyAppState.currentUser!.userID,
  //     "payment_method": paymentMethod,
  //     "amount": amount,
  //     "id": id,
  //     "order_id": orderId,
  //     "isTopUp": isTopup,
  //     "payment_status": "success",
  //     "date": DateTime.now(),
  //   }).then((value) {
  //     firestore.collection(Wallet).doc(id).get().then((value) {
  //       DocumentSnapshot<Map<String, dynamic>> documentData = value;
  //       print("nato");
  //       print(documentData.data());
  //     });
  //   });
  //
  //   return "updated Amount".tr();
  // }

  static Future topUpOtherWalletAmount({required String userId, String paymentMethod = "test", bool isTopup = true, required amount, required id, orderId = ""}) async {
    TopupTranHistoryModel adminCommission = TopupTranHistoryModel(
        amount: amount,
        id: Uuid().v4(),
        order_id: orderId,
        user_id: userId,
        date: Timestamp.now(),
        isTopup: true,
        payment_method: "Wallet",
        payment_status: "success",
        transactionUser: "customer",
        note: paymentMethod,
        serviceType: 'ondemand-service');

    await firestore.collection("wallet").doc(id).set(adminCommission.toJson()).then((value) {
      firestore.collection("wallet").doc(id).get().then((value) {
        DocumentSnapshot<Map<String, dynamic>> documentData = value;
        print("nato");
        print(documentData.data());
      });
    });
    return "updated Amount".tr();
  }

  static Future updateOtherWalletAmount({required String userId, required amount}) async {
    dynamic walletAmount = 0;

    await firestore.collection(USERS).doc(userId).get().then((value) async {
      DocumentSnapshot<Map<String, dynamic>> userDocument = value;
      if (userDocument.data() != null && userDocument.exists) {
        try {
          print(userDocument.data());
          await firestore.collection(USERS).doc(userId).update({"wallet_amount": (num.parse(userDocument.data()!['wallet_amount'].toString()) + amount)}).then((value) {
            MyAppState.currentUser!.wallet_amount = num.parse(userDocument.data()!['wallet_amount'].toString()) + amount;
          });
        } catch (error) {
          print(error);
          if (error.toString() == "Bad state: field does not exist within the DocumentSnapshotPlatform") {
            print("does not exist");
          } else {
            print("went wrong!!");
            walletAmount = "ERROR";
          }
        }
        return walletAmount; //User.fromJson(userDocument.data()!);
      } else {
        return 0.111;
      }
    });
  }

  static Future updateWalletAmount({required amount}) async {
    dynamic walletAmount = 0;
    final userId = MyAppState.currentUser!.userID;
    await firestore.collection(USERS).doc(userId).get().then((value) async {
      DocumentSnapshot<Map<String, dynamic>> userDocument = value;
      if (userDocument.data() != null && userDocument.exists) {
        try {
          print(userDocument.data());
          User user = User.fromJson(userDocument.data()!);
          MyAppState.currentUser = user;

          await firestore.collection(USERS).doc(userId).update({"wallet_amount": user.wallet_amount + double.parse(amount.toString())}).then((value) => print("north"));

          DocumentSnapshot<Map<String, dynamic>> newUserDocument = await firestore.collection(USERS).doc(userId).get();
          MyAppState.currentUser = User.fromJson(newUserDocument.data()!);
          print(MyAppState.currentUser);
        } catch (error) {
          print(error);
        }
        return walletAmount; //User.fromJson(userDocument.data()!);
      } else {
        return 0.111;
      }
    });
  }

  static sendTopUpMail({required String amount, required String paymentMethod, required String tractionId}) async {
    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(walletTopup);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}", MyAppState.currentUser!.firstName + " " + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{date}", DateFormat('dd-MM-yyyy').format(Timestamp.now().toDate()));
    newString = newString.replaceAll("{amount}", amountShow(amount: amount));
    newString = newString.replaceAll("{paymentmethod}", paymentMethod.toString());
    newString = newString.replaceAll("{transactionid}", tractionId.toString());
    newString = newString.replaceAll("{newwalletbalance}.", amountShow(amount: MyAppState.currentUser!.wallet_amount.toString()));
    await sendMail(subject: emailTemplateModel.subject, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [MyAppState.currentUser!.email]);
  }

  static sendOrderEmail({required OrderModel orderModel}) async {
    String firstHTML = """
       <table style="width: 100%; border-collapse: collapse; border: 1px solid rgb(0, 0, 0);">
    <thead>
        <tr>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Product Name<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Quantity<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Price<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Extra Item Price<br></th>
            <th style="text-align: left; border: 1px solid rgb(0, 0, 0);">Total<br></th>
        </tr>
    </thead>
    <tbody>
    """;

    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(newOrderPlaced);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{username}", MyAppState.currentUser!.firstName + " " + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{orderid}", orderModel.id);
    newString = newString.replaceAll("{date}", DateFormat('dd-MM-yyyy').format(orderModel.createdAt.toDate()));
    newString = newString.replaceAll(
      "{address}",
      '${orderModel.address!.getFullAddress()}',
    );
    newString = newString.replaceAll(
      "{paymentmethod}",
      orderModel.payment_method,
    );

    double deliveryCharge = 0.0;
    double total = 0.0;
    double specialDiscount = 0.0;
    double discount = 0.0;
    double taxAmount = 0.0;
    double tipValue = 0.0;
    String specialLabel = '';
    if (orderModel.specialDiscount != null && orderModel.specialDiscount!.isNotEmpty) {
      specialLabel = '(${orderModel.specialDiscount!['special_discount_label']}${orderModel.specialDiscount!['specialType'] == "amount" ? currencyData!.symbol : "%"})';
    }
    List<String> htmlList = [];

    if (orderModel.deliveryCharge != null) {
      deliveryCharge = double.parse(orderModel.deliveryCharge.toString());
    }
    if (orderModel.tipValue != null) {
      tipValue = double.parse(orderModel.tipValue.toString());
    }
    orderModel.products.forEach((element) {
      if (element.extras_price != null && element.extras_price!.isNotEmpty && double.parse(element.extras_price!) != 0.0) {
        total += element.quantity * double.parse(element.extras_price!);
      }
      total += element.quantity * double.parse(element.price);

      List<dynamic>? addon = element.extras;
      String extrasDisVal = '';
      for (int i = 0; i < addon!.length; i++) {
        extrasDisVal += '${addon[i].toString().replaceAll("\"", "")} ${(i == addon.length - 1) ? "" : ","}';
      }
      String product = """
        <tr>
            <td style="width: 20%; border-top: 1px solid rgb(0, 0, 0);">${element.name}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${element.quantity}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: element.price.toString())}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: element.extras_price.toString())}</td>
            <td style="width: 20%; border: 1px solid rgb(0, 0, 0);" rowspan="2">${amountShow(amount: ((element.quantity * double.parse(element.extras_price!) + (element.quantity * double.parse(element.price)))).toString())}</td>
        </tr>
        <tr>
            <td style="width: 20%;">${extrasDisVal.isEmpty ? "" : "Extra Item : $extrasDisVal"}</td>
        </tr>
    """;
      htmlList.add(product);
    });

    if (orderModel.specialDiscount!.isNotEmpty) {
      specialDiscount = double.parse(orderModel.specialDiscount!['special_discount'].toString());
    }

    if (orderModel.couponId != null && orderModel.couponId!.isNotEmpty) {
      discount = double.parse(orderModel.discount.toString());
    }

    List<String> taxHtmlList = [];
    if (taxList != null) {
      for (var element in taxList!) {
        taxAmount = taxAmount + getTaxValue(amount: (total - discount - specialDiscount).toString(), taxModel: element);
        String taxHtml =
            """<span style="font-size: 1rem;">${element.title}: ${amountShow(amount: getTaxValue(amount: (total - discount - specialDiscount).toString(), taxModel: element).toString())}${taxList!.indexOf(element) == taxList!.length - 1 ? "</span>" : "<br></span>"}""";
        taxHtmlList.add(taxHtml);
      }
    }

    var totalamount = orderModel.deliveryCharge == null || orderModel.deliveryCharge!.isEmpty
        ? total + taxAmount - discount - specialDiscount
        : total + taxAmount + double.parse(orderModel.deliveryCharge!) + double.parse(orderModel.tipValue!) - discount - specialDiscount;

    newString = newString.replaceAll("{subtotal}", amountShow(amount: total.toString()));
    newString = newString.replaceAll("{coupon}", '(${orderModel.couponCode.toString()})');
    newString = newString.replaceAll("{discountamount}", amountShow(amount: orderModel.discount.toString()));
    newString = newString.replaceAll("{specialcoupon}", specialLabel);
    newString = newString.replaceAll("{specialdiscountamount}", amountShow(amount: specialDiscount.toString()));
    newString = newString.replaceAll("{shippingcharge}", amountShow(amount: deliveryCharge.toString()));
    newString = newString.replaceAll("{tipamount}", amountShow(amount: tipValue.toString()));
    newString = newString.replaceAll("{totalAmount}", amountShow(amount: totalamount.toString()));

    String tableHTML = htmlList.join();
    String lastHTML = "</tbody></table>";
    newString = newString.replaceAll("{productdetails}", firstHTML + tableHTML + lastHTML);
    newString = newString.replaceAll("{taxdetails}", taxHtmlList.join());
    newString = newString.replaceAll("{newwalletbalance}.", amountShow(amount: MyAppState.currentUser!.wallet_amount.toString()));

    String subjectNewString = emailTemplateModel.subject.toString();
    subjectNewString = subjectNewString.replaceAll("{orderid}", orderModel.id);
    await sendMail(subject: subjectNewString, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [MyAppState.currentUser!.email]);
  }

  static sendRideBookEmail({required CabOrderModel? orderModel}) async {
    EmailTemplateModel? emailTemplateModel = await FireStoreUtils.getEmailTemplates(newRideBook);

    var dt = DateTime.fromMillisecondsSinceEpoch(orderModel!.createdAt.seconds * 1000);

    String newString = emailTemplateModel!.message.toString();
    newString = newString.replaceAll("{passengername}", MyAppState.currentUser!.firstName + " " + MyAppState.currentUser!.lastName);
    newString = newString.replaceAll("{rideid}", orderModel.id);
    newString = newString.replaceAll("{date}", DateFormat('dd-MM-yyyy').format(orderModel.createdAt.toDate()));
    newString = newString.replaceAll("{time}", DateFormat("hh:mm:ss a").format(dt));
    newString = newString.replaceAll(
      "{pickuplocation}",
      orderModel.sourceLocationName.toString(),
    );
    newString = newString.replaceAll(
      "{dropofflocation}",
      orderModel.destinationLocationName.toString(),
    );
    newString = newString.replaceAll(
      "{drivername}",
      orderModel.driver!.firstName.toString() + orderModel.driver!.lastName.toString(),
    );
    newString = newString.replaceAll(
      "{vehicle}",
      orderModel.driver!.carName.toString(),
    );
    newString = newString.replaceAll(
      "{carnumber}",
      orderModel.driver!.carNumber.toString(),
    );
    newString = newString.replaceAll(
      "{driverphone}",
      orderModel.driver!.phoneNumber.toString(),
    );

    String subjectNewString = emailTemplateModel.subject.toString();
    subjectNewString = subjectNewString.replaceAll("{orderid}", orderModel.id);
    await sendMail(subject: subjectNewString, isAdmin: emailTemplateModel.isSendToAdmin, body: newString, recipients: [MyAppState.currentUser!.email]);
  }

  static Future<EmailTemplateModel?> getEmailTemplates(String type) async {
    EmailTemplateModel? emailTemplateModel;
    await firestore.collection(emailTemplates).where('type', isEqualTo: type).get().then((value) {
      if (value.docs.isNotEmpty) {
        emailTemplateModel = EmailTemplateModel.fromJson(value.docs.first.data());
      }
    });
    return emailTemplateModel;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrderStatus(String orderID) async* {
    yield* firestore.collection(ORDERS).doc(orderID).snapshots();
  }

  /// compress image file to make it load faster but with lower quality,
  /// change the quality parameter to control the quality of the image after
  /// being compressed(100 = max quality - 0 = low quality)
  /// @param file the image file that will be compressed
  /// @return File a new compressed file with smaller size
  Future<File> _compressVideo(File file) async => file;


  /// save a new user document in the USERS table in firebase firestore
  /// returns an error message on failure or null on success
  static Future<String?> firebaseCreateNewUser(User user, String referralCode) async {
    try {
      if (referralCode.isNotEmpty) {
        FireStoreUtils.getReferralUserByCode(referralCode.toString()).then((value) async {
          if (value != null) {
            ReferralModel ownReferralModel = ReferralModel(id: user.userID, referralBy: value.id, referralCode: getReferralCode());
            await referralAdd(ownReferralModel);
          } else {
            ReferralModel referralModel = ReferralModel(id: user.userID, referralBy: "", referralCode: getReferralCode());
            await referralAdd(referralModel);
          }
        });
      } else {
        ReferralModel referralModel = ReferralModel(id: user.userID, referralBy: "", referralCode: getReferralCode());
        await referralAdd(referralModel);
      }

      await firestore.collection(USERS).doc(user.userID).set(user.toJson());
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return "notSignUp".tr();
    }
    return null;
  }

  static Future<String?> referralAdd(ReferralModel ratingModel) async {
    try {
      await firestore.collection(REFERRAL).doc(ratingModel.id).set(ratingModel.toJson());
    } catch (e, s) {
      print('FireStoreUtils.firebaseCreateNewUser $e $s');
      return 'Couldn\'t review'.tr();
    }
    return null;
  }

  /// login with email and password with firebase
  /// @param email user email
  /// @param password user password
  static Future<dynamic> loginWithEmailAndPassword(String email, String password) async {
    try {
      print('FireStoreUtils.loginWithEmailAndPassword');
      auth.UserCredential result = await auth.FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      // result.user.
      DocumentSnapshot<Map<String, dynamic>> documentSnapshot = await firestore.collection(USERS).doc(result.user?.uid ?? '').get();
      User? user;

      if (documentSnapshot.exists) {
        // if(user!.role != 'vendor'){
        user = User.fromJson(documentSnapshot.data() ?? {});
        // if(  USER_ROLE_CUSTOMER ==user.role)
        // {
        user.fcmToken = await firebaseMessaging.getToken() ?? '';

        //user.active = true;

        //      }
      }
      return user;
    } on auth.FirebaseAuthException catch (exception, s) {
      print(exception.toString() + '$s');
      print(exception.toString() + '${exception.code.toString()}');
      switch ((exception).code) {
        case 'invalid-email':
          return "Email address is malformed.".tr();
        case 'wrong-password':
          return 'Wrong password.'.tr();
        case 'user-not-found':
          return 'No user corresponding to the given email address.'.tr();
        case 'user-disabled':
          return 'This user has been disabled.'.tr();
        case 'too-many-requests':
          return 'Too many attempts to sign in as this user.'.tr();
      }
      return 'Unexpected firebase error, Please try again.'.tr();
    } catch (e, s) {
      print(e.toString() + '$s');
      return 'Login failed, Please try again.'.tr();
    }
  }

  ///submit a phone number to firebase to receive a code verification, will
  ///be used later to login
  static firebaseSubmitPhoneNumber(
    String phoneNumber,
    auth.PhoneCodeAutoRetrievalTimeout? phoneCodeAutoRetrievalTimeout,
    auth.PhoneCodeSent? phoneCodeSent,
    auth.PhoneVerificationFailed? phoneVerificationFailed,
    auth.PhoneVerificationCompleted? phoneVerificationCompleted,
  ) {
    auth.FirebaseAuth.instance.verifyPhoneNumber(
      timeout: const Duration(minutes: 2),
      phoneNumber: phoneNumber,
      verificationCompleted: phoneVerificationCompleted!,
      verificationFailed: phoneVerificationFailed!,
      codeSent: phoneCodeSent!,
      codeAutoRetrievalTimeout: phoneCodeAutoRetrievalTimeout!,
    );
  }

  /// submit the received code to firebase to complete the phone number
  /// verification process
  static Future<dynamic> firebaseSubmitPhoneNumberCode(String verificationID, String code, String phoneNumber,
      {String firstName = 'Anonymous', String lastName = 'User', File? image, String referralCode = ''}) async {
    auth.AuthCredential authCredential = auth.PhoneAuthProvider.credential(verificationId: verificationID, smsCode: code);
    auth.UserCredential userCredential = await auth.FirebaseAuth.instance.signInWithCredential(authCredential);
    User? user = await getCurrentUser(userCredential.user?.uid ?? '');
    if (user != null && user.role == USER_ROLE_CUSTOMER) {
      user.fcmToken = await firebaseMessaging.getToken() ?? '';
      user.role = USER_ROLE_CUSTOMER;
      //user.active = true;
      await updateCurrentUser(user);
      return user;
    } else if (user == null) {
      /// create a new user from phone login
      String profileImageUrl = '';
      if (image != null) {
        profileImageUrl = await uploadUserImageToFireStorage(image, userCredential.user?.uid ?? '');
      }
      User user = User(
        firstName: firstName,
        lastName: lastName,
        fcmToken: await firebaseMessaging.getToken() ?? '',
        phoneNumber: phoneNumber,
        profilePictureURL: profileImageUrl,
        userID: userCredential.user?.uid ?? '',
        role: USER_ROLE_CUSTOMER,
        active: true,
        lastOnlineTimestamp: Timestamp.now(),
        settings: UserSettings(),
        email: '',
      );
      String? errorMessage = await firebaseCreateNewUser(user, referralCode);
      if (errorMessage == null) {
        return user;
      } else {
        return 'Couldn\'t create new user with phone number.'.tr();
      }
    }
  }

  static firebaseSignUpWithEmailAndPassword(String emailAddress, String password, File? image, String firstName, String lastName, String mobile, String referralCode) async {
    try {
      auth.UserCredential result = await auth.FirebaseAuth.instance.createUserWithEmailAndPassword(email: emailAddress, password: password);
      String profilePicUrl = '';
      if (image != null) {
        profilePicUrl = await uploadUserImageToFireStorage(image, result.user?.uid ?? '');
      }
      User user = User(
          email: emailAddress,
          settings: UserSettings(),
          lastOnlineTimestamp: Timestamp.now(),
          active: true,
          phoneNumber: mobile,
          firstName: firstName,
          role: USER_ROLE_CUSTOMER,
          userID: result.user?.uid ?? '',
          lastName: lastName,
          fcmToken: await firebaseMessaging.getToken() ?? '',
          createdAt: Timestamp.now(),
          profilePictureURL: profilePicUrl);
      String? errorMessage = await firebaseCreateNewUser(user, referralCode);
      if (errorMessage == null) {
        return user;
      } else {
        return 'Couldn\'t sign up for firebase, Please try again.';
      }
    } on auth.FirebaseAuthException catch (error) {
      print(error.toString() + '${error.stackTrace}');
      String message = 'Couldn\'t sign up'.tr();
      switch (error.code) {
        case 'email-already-in-use':
          message = 'Email already in use, Please pick another email!'.tr();
          break;
        case 'invalid-email':
          message = 'Enter valid e-mail'.tr();
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled'.tr();
          break;
        case 'weak-password':
          message = 'Password must be more than 5 characters'.tr();
          break;
        case 'too-many-requests':
          message = 'Too many requests, Please try again later.'.tr();
          break;
      }
      return message;
    } catch (e) {
      return 'Couldn\'t sign up';
    }
  }

  static Future<auth.UserCredential?> reAuthUser(AuthProviders provider,
      {String? email, String? password, String? smsCode, String? verificationId}) async {
    late auth.AuthCredential credential;
    switch (provider) {
      case AuthProviders.PASSWORD:
        credential = auth.EmailAuthProvider.credential(email: email!, password: password!);
        break;
      case AuthProviders.PHONE:
        credential = auth.PhoneAuthProvider.credential(smsCode: smsCode!, verificationId: verificationId!);
        break;
    }
    return await auth.FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(credential);
  }

  static resetPassword(String emailAddress) async => await auth.FirebaseAuth.instance.sendPasswordResetEmail(email: emailAddress);

  static deleteUser() async {
    try {
      await firestore.collection(USERS).doc(auth.FirebaseAuth.instance.currentUser!.uid).delete();

      await auth.FirebaseAuth.instance.currentUser!.delete();
    } catch (e, s) {
      print('FireStoreUtils.deleteUser $e $s');
    }
  }

  Future<OrderModel?> getOrderById(String? orderId) async {
    DocumentSnapshot<Map<String, dynamic>> userDocument = await firestore.collection(ORDERS).doc(orderId).get();
    if (userDocument.data() != null && userDocument.exists) {
      return OrderModel.fromJson(userDocument.data()!);
    } else {
      return null;
    }
  }

  getContactUs() async {
    Map<String, dynamic> contactData = {};
    await firestore.collection(Setting).doc(CONTACT_US).get().then((value) {
      contactData = value.data()!;
    });

    return contactData;
  }

  Future<GiftCardsOrderModel> placeGiftCardOrder(GiftCardsOrderModel giftCardsOrderModel) async {
    await firestore.collection(GIFT_PURCHASES).doc(giftCardsOrderModel.id).set(giftCardsOrderModel.toJson());
    return giftCardsOrderModel;
  }

  Future<List<GiftCardsOrderModel>> getGiftHistory() async {
    List<GiftCardsOrderModel> giftCardsOrderList = [];
    await firestore.collection(GIFT_PURCHASES).where("userid", isEqualTo: MyAppState.currentUser!.userID).get().then((value) {
      for (var element in value.docs) {
        GiftCardsOrderModel giftCardsOrderModel = GiftCardsOrderModel.fromJson(element.data());
        giftCardsOrderList.add(giftCardsOrderModel);
      }
    });
    return giftCardsOrderList;
  }

  Future<GiftCardsOrderModel?> checkRedeemCode(String giftCode) async {
    GiftCardsOrderModel? giftCardsOrderModel;
    await firestore.collection(GIFT_PURCHASES).where("giftCode", isEqualTo: giftCode).get().then((value) {
      if (value.docs.isNotEmpty) {
        giftCardsOrderModel = GiftCardsOrderModel.fromJson(value.docs.first.data());
      }
    });
    return giftCardsOrderModel;
  }

  static Future<List<GiftCardsModel>> getGiftCard() async {
    List<GiftCardsModel> giftCardModelList = [];
    QuerySnapshot<Map<String, dynamic>> currencyQuery = await firestore.collection(GIFT_CARDS).where("isEnable", isEqualTo: true).get();
    await Future.forEach(currencyQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      try {
        log(document.data().toString());
        giftCardModelList.add(GiftCardsModel.fromJson(document.data()));
      } catch (e) {
        debugPrint('FireStoreUtils.get Currency Parse error $e');
      }
    });
    return giftCardModelList;
  }

  Future<List<RatingModel>> getReviewByProviderServiceId(String serviceId) async {
    List<RatingModel> providerReview = [];

    QuerySnapshot<Map<String, dynamic>> reviewQuery = await firestore.collection(Order_Rating).where('productId', isEqualTo: serviceId).get();
    await Future.forEach(reviewQuery.docs, (QueryDocumentSnapshot<Map<String, dynamic>> document) {
      print(document);
      try {
        providerReview.add(RatingModel.fromJson(document.data()));
      } catch (e) {
        print('FireStoreUtils.getReviewByProviderServiceId Parse error ${document.id} $e');
      }
    });
    return providerReview;
  }

  static Future addProviderInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_provider").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addProviderChat(ConversationModel conversationModel) async {
    return await firestore
        .collection("chat_provider")
        .doc(conversationModel.orderId)
        .collection("thread")
        .doc(conversationModel.id)
        .set(conversationModel.toJson())
        .then((document) {
      return conversationModel;
    });
  }

  static Future addWorkerInbox(InboxModel inboxModel) async {
    return await firestore.collection("chat_worker").doc(inboxModel.orderId).set(inboxModel.toJson()).then((document) {
      return inboxModel;
    });
  }

  static Future addWorkerChat(ConversationModel conversationModel) async {
    return await firestore.collection("chat_worker").doc(conversationModel.orderId).collection("thread").doc(conversationModel.id).set(conversationModel.toJson()).then((document) {
      return conversationModel;
    });
  }

  static Future<List<RatingModel>> getVendorReviews(String vendorId) async {
    List<RatingModel> ratingList = [];
    await firestore.collection(Order_Rating).where('VendorId', isEqualTo: vendorId).get().then((value) {
      for (var element in value.docs) {
        RatingModel giftCardsOrderModel = RatingModel.fromJson(element.data());
        ratingList.add(giftCardsOrderModel);
      }
    });
    return ratingList;
  }

}
