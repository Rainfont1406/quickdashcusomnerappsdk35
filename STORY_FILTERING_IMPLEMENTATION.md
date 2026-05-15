# Story Filtering Implementation

## Overview
This document describes the implementation of story filtering based on order type (Delivery/Dineaway) and content type (Image/Video).

## Feature Requirements
- **Delivery Section**: Show ONLY IMAGE stories
- **Dineaway Section**: Show ONLY VIDEO stories
- Filter stories based on `imageUrl` and `videoUrl` fields
- **Note**: Dineaway = Takeaway (frontend shows "Dineaway", backend uses `takeaway` field)

## Implementation Details

### 1. StoryModel Updates (lib/model/story_model.dart)

#### Added Fields
- `List<dynamic> imageUrl = []` - Stores image URLs for image-based stories

#### Helper Methods
- `bool get hasVideo` - Returns true if story has video URLs
- `bool get hasImage` - Returns true if story has image URLs
- `bool get isVideoStory` - Returns true if story has only videos
- `bool get isImageStory` - Returns true if story has only images
- `bool get hasBothTypes` - Returns true if story has both images and videos

#### Debug Logs
Added console logs in `fromJson()` method to track:
- vendorID
- videoUrl count and content
- imageUrl count and content
- delivery and takeaway flags

### 2. HomeScreen Filtering Logic (lib/ui/home/HomeScreen.dart)

#### Story Filtering (getData method)
```dart
FireStoreUtils().getStory().then((value) {
  // Clear previous stories
  storyList.clear();

  // Filter stories based on:
  // 1. Order type (Delivery/Dineaway)
  // 2. Content type (Image/Video)

  // For Delivery: Show ONLY IMAGE stories
  if (selctedOrderTypeValue == "Delivery" && story.delivery) {
    if (story.hasImage) {
      storyList.add(story);
    }
  }

  // For Dineaway: Show ONLY VIDEO stories
  if (selctedOrderTypeValue == "Dineaway" && story.takeaway) {
    if (story.hasVideo) {
      storyList.add(story);
    }
  }
});
```

#### Console Logs
Added comprehensive logging to track:
- Total stories fetched from Firebase
- Current order type selected
- Story processing for each vendor
- Whether story has video/image content
- Whether story matches delivery/takeaway flags
- Filtering decisions with reasons
- Final filtered story count

### 3. Story Thumbnail Display (lib/ui/home/HomeScreen.dart - StoryView widget)

#### Dynamic Thumbnail Selection
```dart
String thumbnailUrl = '';
if (storyModel.hasImage && storyModel.imageUrl.isNotEmpty) {
  // For image stories, use first image as thumbnail
  thumbnailUrl = storyModel.imageUrl[0].toString();
} else if (storyModel.videoThumbnail != null) {
  // For video stories, use video thumbnail
  thumbnailUrl = storyModel.videoThumbnail.toString();
}
```

### 4. Story View Handling (lib/ui/home/story_view.dart - MoreStories)

#### Build Story Items
The story viewer now dynamically builds story items based on order type:

```dart
List<StoryItem> storyItems = [];

// For Delivery: show ONLY IMAGES
if (widget.orderType == "Delivery" && currentStory.hasImage) {
  for (int i = 0; i < currentStory.imageUrl.length; i++) {
    storyItems.add(
      StoryItem.pageImage(
        url: currentStory.imageUrl[i],
        controller: storyController,
        duration: Duration(seconds: 5),
      ),
    );
  }
}
// For Dineaway: show ONLY VIDEOS
else if (widget.orderType == "Dineaway" && currentStory.hasVideo) {
  for (int i = 0; i < currentStory.videoUrl.length; i++) {
    storyItems.add(
      StoryItem.pageVideo(
        currentStory.videoUrl[i],
        controller: storyController,
      ),
    );
  }
}
```

#### Console Logs
Added logging for:
- Current story index
- Total stories count
- Whether story has video/image content
- Video and image URLs
- Number of items being added
- Story completion events

## Console Log Format

### Story Model Logs
```
📖 Story Model - fromJson:
  vendorID: [vendor_id]
  videoUrl count: [count]
  videoUrl: [urls]
  imageUrl count: [count]
  imageUrl: [urls]
  delivery: [true/false]
  takeaway: [true/false]
```

### Story Filtering Logs
```
🎬 ===== STORY FILTERING START =====
📊 Total stories fetched: [count]
🔄 Current order type: [Delivery/Dineaway]

📍 Processing story for vendor: [vendor_name]
  Story has video: [true/false]
  Story has image: [true/false]
  Story delivery: [true/false]
  Story takeaway: [true/false]
  ✅ Adding IMAGE story for DELIVERY
  OR
  ❌ Skipping: No images for delivery

📋 Final filtered story count: [count]
🎬 ===== STORY FILTERING END =====
```

### Story View Logs
```
🎥 ===== STORY VIEW BUILD =====
📍 Current story index: [index]
📊 Total stories: [count]
🎬 Story has video: [true/false]
🖼️ Story has image: [true/false]
📹 Video URLs: [urls]
🖼️ Image URLs: [urls]
✅ Adding [count] video items
  📹 Video 0: [url]
✅ Adding [count] image items
  🖼️ Image 0: [url]
📋 Total story items to display: [count]
🎥 ===== STORY VIEW BUILD END =====
```

### Thumbnail Selection Logs
```
🖼️ Using image thumbnail for story [index]: [url]
OR
📹 Using video thumbnail for story [index]: [url]
```

### User Interaction Logs
```
👆 Tapped on story [index]
✅ Story completed. Moving to next...
🏁 All stories completed. Closing...
👆 Swipe down detected. Closing story...
```

## Testing Guide

### To Test Delivery Section (Image Stories Only)
1. Switch to "Delivery" mode using the dropdown
2. Check console logs for filtering messages
3. Verify only stories with `imageUrl` are displayed
4. Tap on a story to verify images are shown (not videos)
5. Console should show image URLs being loaded
6. Each image displays for 5 seconds

### To Test Dineaway Section (Video Stories Only)
1. Switch to "Dineaway" mode using the dropdown
2. Check console logs for filtering messages
3. Verify only stories with `videoUrl` are displayed
4. Tap on a story to verify videos are played (not images)
5. Console should show video URLs being loaded

### Console Log Verification
1. Open the console/terminal where the app is running
2. Navigate to home screen
3. Look for logs starting with emoji indicators:
   - 📖 Story Model parsing
   - 🎬 Story filtering
   - 🖼️ Image thumbnails
   - 📹 Video thumbnails
   - 🎥 Story view building
4. Verify that logs show correct URLs and counts

## Troubleshooting

### Stories Not Showing
- Check if `imageUrl` or `videoUrl` fields exist in Firebase
- Verify `delivery` and `takeaway` flags are set correctly
- Check console logs to see if stories are being filtered out
- Look for "❌ Skipping" messages in logs

### Wrong Content Type Showing
- Verify the filtering logic in `getData()` method
- Check if story has correct `imageUrl` or `videoUrl` data
- Look at console logs to see which content type is detected

### No Console Logs
- Ensure the app is running in debug mode
- Check if `print()` statements are being executed
- Verify you're looking at the correct console output

## Firebase Data Structure

Stories should have this structure in Firebase:
```json
{
  "vendorID": "vendor_id",
  "videoThumbnail": "thumbnail_url",
  "videoUrl": ["video_url_1", "video_url_2"],
  "imageUrl": ["image_url_1", "image_url_2"],
  "delivery": true,
  "takeaway": false,
  "sectionID": "section_id",
  "createdAt": timestamp
}
```

## Notes
- Image stories display for 5 seconds each
- Video stories play until completion
- **Delivery Section**: Shows ONLY image stories (filters out videos)
- **Dineaway Section**: Shows ONLY video stories (filters out images)
- Thumbnails automatically use image or video thumbnail based on content type
- Stories with both `imageUrl` and `videoUrl` will only show the appropriate type based on section
