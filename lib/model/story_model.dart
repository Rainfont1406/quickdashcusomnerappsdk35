import 'package:cloud_firestore/cloud_firestore.dart';

class StoryModel {
  String? videoThumbnail;
  List<dynamic> videoUrl = [];
  List<dynamic> imageUrl = [];
  String? vendorID;
  String? sectionID;
  String? storyID;
  Timestamp? createdAt;
  int? duration; // Duration in seconds (e.g., 86400 = 24 hours)
  bool takeaway = false;
  bool delivery = false;
  bool approved = false;
  String? storyType;

  // View-package model (replaces day-based `duration` for new stories).
  int? viewPackageSize; // total unique views purchased
  int viewCount = 0; // atomically incremented per unique viewer (per day)
  double? pricePerView;
  double? amountPaid;
  Timestamp? backstopExpiresAt; // hard cap, locked at purchase time

  StoryModel({
    this.videoThumbnail,
    this.videoUrl = const [],
    this.imageUrl = const [],
    this.vendorID,
    this.sectionID,
    this.storyID,
    this.createdAt,
    this.duration,
    this.takeaway = false,
    this.delivery = false,
    this.approved = false,
    this.storyType,
    this.viewPackageSize,
    this.viewCount = 0,
    this.pricePerView,
    this.amountPaid,
    this.backstopExpiresAt,
  });

  // Helper method to normalize URL fields (handle both string and array formats)
  List<dynamic> _normalizeUrlField(dynamic value) {
    if (value == null) {
      return [];
    }
    if (value is String) {
      // If it's a string, convert to single-element array if not empty
      return value.isEmpty ? [] : [value];
    }
    if (value is List) {
      // If it's already a list, return as-is
      return value;
    }
    // Fallback for any other type
    return [];
  }

  StoryModel.fromJson(Map<String, dynamic> json) {
    videoThumbnail = json['videoThumbnail'] ?? '';
    
    // Normalize videoUrl and imageUrl to handle both string and array formats
    videoUrl = _normalizeUrlField(json['videoUrl']);
    imageUrl = _normalizeUrlField(json['imageUrl']);
    
    vendorID = json['vendorID'] ?? '';
    sectionID = json['sectionID'] ?? '';
    storyID = json['storyID'];
    createdAt = json['createdAt'] ?? Timestamp.now();
    duration = json['duration'] is int ? json['duration'] : (json['duration'] != null ? int.tryParse(json['duration'].toString()) : null);
    takeaway = json['takeaway'] ?? false;
    delivery = json['delivery'] ?? false;
    approved = json['approved'] ?? false;
    storyType = json['storyType'];
    viewPackageSize = json['viewPackageSize'];
    viewCount = json['viewCount'] ?? 0;
    pricePerView = json['pricePerView'] != null
        ? (json['pricePerView'] as num).toDouble()
        : null;
    amountPaid = json['amountPaid'] != null
        ? (json['amountPaid'] as num).toDouble()
        : null;
    backstopExpiresAt = json['backstopExpiresAt'];

    // Debug logs
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['videoThumbnail'] = videoThumbnail;
    data['videoUrl'] = videoUrl;
    data['imageUrl'] = imageUrl;
    data['vendorID'] = vendorID;
    data['sectionID'] = sectionID;
    data['storyID'] = storyID;
    data['createdAt'] = createdAt;
    data['duration'] = duration;
    data['takeaway'] = takeaway;
    data['delivery'] = delivery;
    data['approved'] = approved;
    data['storyType'] = storyType;
    data['viewPackageSize'] = viewPackageSize;
    data['viewCount'] = viewCount;
    data['pricePerView'] = pricePerView;
    data['amountPaid'] = amountPaid;
    data['backstopExpiresAt'] = backstopExpiresAt;
    return data;
  }

  // Helper methods to check story type
  bool get hasVideo => videoUrl.isNotEmpty;
  bool get hasImage => imageUrl.isNotEmpty;
  bool get isVideoStory => hasVideo && !hasImage;
  bool get isImageStory => hasImage && !hasVideo;
  bool get hasBothTypes => hasVideo && hasImage;
  
  // Check if story is expired.
  // View-package stories: expired once views are exhausted or the backstop
  // day-cap is hit, whichever comes first. Legacy day-based stories (no
  // viewPackageSize/backstopExpiresAt - pre-migration docs) fall back to the
  // old createdAt+duration check.
  bool get isExpired {
    if (viewPackageSize != null || backstopExpiresAt != null) {
      final viewsExhausted =
          viewPackageSize != null && viewCount >= viewPackageSize!;
      final backstopHit = backstopExpiresAt != null &&
          DateTime.now().isAfter(backstopExpiresAt!.toDate());
      return viewsExhausted || backstopHit;
    }

    final now = DateTime.now();

    // Calculate expiration based on createdAt + duration
    if (createdAt != null && duration != null && duration! > 0) {
      final expirationTime = createdAt!.toDate().add(Duration(seconds: duration!));
      return expirationTime.isBefore(now);
    }

    // If no duration specified, default to 24 hours from creation time
    if (createdAt != null) {
      final expirationTime = createdAt!.toDate().add(const Duration(hours: 24));
      return expirationTime.isBefore(now);
    }

    // If no createdAt, consider it expired (shouldn't happen, but safety check)
    return true;
  }
}
