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
    return data;
  }

  // Helper methods to check story type
  bool get hasVideo => videoUrl.isNotEmpty;
  bool get hasImage => imageUrl.isNotEmpty;
  bool get isVideoStory => hasVideo && !hasImage;
  bool get isImageStory => hasImage && !hasVideo;
  bool get hasBothTypes => hasVideo && hasImage;
  
  // Check if story is expired
  // Stories expire based on createdAt + duration (in seconds)
  bool get isExpired {
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
