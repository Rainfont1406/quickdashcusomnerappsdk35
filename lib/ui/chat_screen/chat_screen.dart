import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart' as easyLocal;
import 'package:emartconsumer/main.dart';
import 'package:emartconsumer/model/ChatVideoContainer.dart';
import 'package:emartconsumer/model/OrderModel.dart';
import 'package:emartconsumer/model/User.dart';
import 'package:emartconsumer/model/conversation_model.dart';
import 'package:emartconsumer/model/inbox_model.dart';
import 'package:emartconsumer/send_notification.dart';
import 'package:emartconsumer/services/FirebaseHelper.dart';
import 'package:emartconsumer/services/helper.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:emartconsumer/ui/fullScreenImageViewer/FullScreenImageViewer.dart';
import 'package:emartconsumer/ui/fullScreenVideoViewer/FullScreenVideoViewer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class ChatScreens extends StatefulWidget {
  final String? orderId;
  final String? customerId;
  final String? customerName;
  final String? customerProfileImage;
  final String? restaurantId;
  final String? restaurantName;
  final String? restaurantProfileImage;
  final String? token;
  final String? chatType;
  final String? type;

  ChatScreens({
    Key? key,
    this.orderId,
    this.customerId,
    this.customerName,
    this.restaurantName,
    this.restaurantId,
    this.customerProfileImage,
    this.restaurantProfileImage,
    this.token,
    this.chatType,
    this.type,
  }) : super(key: key);

  @override
  State<ChatScreens> createState() => _ChatScreensState();
}

class _ChatScreensState extends State<ChatScreens> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _controller = ScrollController();
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  String? token;
  late final Stream<QuerySnapshot> _chatStream;
  bool _initialScrollDone = false;

  // Messages added locally before Firestore confirms them — removed once the
  // stream returns the same ID, giving instant display with no UI blocking.
  final List<ConversationModel> _optimisticMessages = [];

  @override
  void initState() {
    super.initState();
    token = widget.token;
    _chatStream = FireStoreUtils.firestore
        .collection(widget.chatType == "Driver"
            ? 'chat_driver'
            : widget.chatType == "Provider"
                ? 'chat_provider'
                : widget.chatType == "Worker"
                    ? 'chat_worker'
                    : 'chat_store')
        .doc(widget.orderId)
        .collection("thread")
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  // Returns "hh:mm a" for today/yesterday messages (the date-separator chip
  // already provides the day context), and the full "MMM d, yyyy hh:mm a"
  // for older messages.
  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    if (msgDay == today || msgDay == today.subtract(const Duration(days: 1))) {
      return DateFormat('hh:mm a').format(dt);
    }
    return DateFormat('MMM d, yyyy hh:mm a').format(dt);
  }

  // Adds the message to the UI immediately, then writes to Firestore in the
  // background. The stream will confirm it shortly after; at that point the
  // optimistic entry is removed so no duplicate appears.
  void _onSend() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final id = const Uuid().v4();
    _messageController.clear();

    setState(() {
      _optimisticMessages.add(ConversationModel(
        id: id,
        message: text,
        senderId: widget.customerId,
        receiverId: widget.restaurantId,
        createdAt: Timestamp.now(),
        orderId: widget.orderId,
        messageType: 'text',
        videoThumbnail: '',
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) _controller.jumpTo(_controller.position.maxScrollExtent);
    });

    _sendMessage(id, text, null, '', 'text').catchError((e) {
      if (mounted) {
        setState(() => _optimisticMessages.removeWhere((m) => m.id == id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? AppThemeData.surfaceDark : AppThemeData.surface,
      appBar: AppBar(
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: AppThemeData.primary500,
        title: Row(
          children: [
            if (widget.restaurantProfileImage != null && widget.restaurantProfileImage!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                  backgroundImage: CachedNetworkImageProvider(widget.restaurantProfileImage!),
                ),
              ),
            Flexible(
              child: Text(
                widget.restaurantName.toString(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8, bottom: 8),
        child: Column(
          children: <Widget>[
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _chatStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;

                    // Build the confirmed list from Firestore
                    final streamMsgs = docs
                        .map((d) => ConversationModel.fromJson(d.data() as Map<String, dynamic>))
                        .toList();

                    // IDs the server has confirmed
                    final confirmedIds = {
                      for (final m in streamMsgs)
                        if (m.id != null && m.id!.isNotEmpty) m.id!
                    };

                    // Drop confirmed optimistic entries (post-frame to avoid
                    // calling setState during build).
                    if (_optimisticMessages.any((m) => confirmedIds.contains(m.id))) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _optimisticMessages.removeWhere((m) => confirmedIds.contains(m.id));
                          });
                        }
                      });
                    }

                    // Pending = optimistic messages not yet confirmed by the stream
                    final pending = _optimisticMessages
                        .where((m) => !confirmedIds.contains(m.id ?? ''))
                        .toList();

                    final allMsgs = [...streamMsgs, ...pending];

                    if (allMsgs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 72, color: AppThemeData.primary500.withValues(alpha: 0.35)),
                            const SizedBox(height: 16),
                            Text('No messages yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppThemeData.grey500)).tr(),
                            const SizedBox(height: 6),
                            Text('Send a message to start the conversation', style: TextStyle(fontSize: 13, color: AppThemeData.grey400)).tr(),
                          ],
                        ),
                      );
                    }
                    if (!_initialScrollDone || _isNearBottom()) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_controller.hasClients) {
                          _controller.jumpTo(_controller.position.maxScrollExtent);
                          _initialScrollDone = true;
                        }
                      });
                    }
                    return ListView.builder(
                      controller: _controller,
                      physics: const BouncingScrollPhysics(),
                      itemCount: allMsgs.length,
                      itemBuilder: (context, index) {
                        final inboxModel = allMsgs[index];
                        final bool showSeparator;
                        if (index == 0 || inboxModel.createdAt == null) {
                          showSeparator = true;
                        } else {
                          final prev = allMsgs[index - 1];
                          showSeparator = prev.createdAt == null ||
                              !_isSameDay(
                                prev.createdAt!.toDate(),
                                inboxModel.createdAt!.toDate(),
                              );
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showSeparator && inboxModel.createdAt != null)
                              _buildDateSeparator(inboxModel.createdAt!.toDate()),
                            chatItemView(
                                inboxModel.senderId == MyAppState.currentUser!.userID,
                                inboxModel),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: IconButton(
                          onPressed: () async {
                            _onCameraClick();
                          },
                          icon: const Icon(Icons.camera_alt),
                          color: AppThemeData.primary500,
                        ),
                      ),
                      Flexible(
                          child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: TextField(
                          textInputAction: TextInputAction.send,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.sentences,
                          controller: _messageController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.05),
                            contentPadding: const EdgeInsets.only(top: 3, left: 10),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.black.withOpacity(0.05), width: 0.0),
                              borderRadius: const BorderRadius.all(Radius.circular(30)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.black.withOpacity(0.05), width: 0.0),
                              borderRadius: const BorderRadius.all(Radius.circular(30)),
                            ),
                            hintText: 'Start typing ...'.tr(),
                          ),
                          onSubmitted: (_) => _onSend(),
                        ),
                      )),
                      Container(
                        margin: const EdgeInsets.only(left: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: IconButton(
                          onPressed: _onSend,
                          icon: const Icon(Icons.send_rounded),
                          color: AppThemeData.primary500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isNearBottom() {
    if (!_controller.hasClients) return true;
    final pos = _controller.position;
    return pos.maxScrollExtent - pos.pixels < 100;
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    String label;
    if (msgDay == today) {
      label = 'Today';
    } else if (msgDay == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('d/M/yyyy').format(date);
    }

    final lineColor = isDarkMode(context) ? Colors.white12 : Colors.black12;
    final chipColor = isDarkMode(context) ? Colors.white10 : Colors.grey.shade200;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: lineColor, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: lineColor, thickness: 1)),
        ],
      ),
    );
  }

  Widget chatItemView(bool isMe, ConversationModel data) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 10),
      child: isMe
          ? Align(
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  data.messageType == "text"
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomLeft: Radius.circular(10)),
                            color: AppThemeData.primary500,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Text(
                            data.message.toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      : data.messageType == "image"
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 50,
                                maxWidth: 200,
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomLeft: Radius.circular(10)),
                                child: Stack(alignment: Alignment.center, children: [
                                  GestureDetector(
                                    onTap: () {
                                      push(
                                          context,
                                          FullScreenImageViewer(
                                            imageUrl: data.url!.url,
                                          ));
                                    },
                                    child: Hero(
                                      tag: data.url!.url,
                                      child: CachedNetworkImage(
                                        imageUrl: data.url!.url,
                                        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                        errorWidget: (context, url, error) => const Icon(Icons.error),
                                      ),
                                    ),
                                  ),
                                ]),
                              ))
                          : FloatingActionButton(
                              mini: true,
                              heroTag: data.id,
                              backgroundColor: AppThemeData.primary500,
                              onPressed: () {
                                push(
                                    context,
                                    FullScreenVideoViewer(
                                      heroTag: data.id.toString(),
                                      videoUrl: data.url!.url,
                                    ));
                              },
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                              ),
                            ),
                  const SizedBox(height: 5),
                  Text(
                    _formatTimestamp(data.createdAt),
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    data.messageType == "text"
                        ? Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomRight: Radius.circular(10)),
                              color: Colors.grey.shade300,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Text(
                              data.message.toString(),
                              style: const TextStyle(color: Colors.black),
                            ),
                          )
                        : data.messageType == "image"
                            ? ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 50,
                                  maxWidth: 200,
                                ),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10), bottomRight: Radius.circular(10)),
                                  child: Stack(alignment: Alignment.center, children: [
                                    GestureDetector(
                                      onTap: () {
                                        push(
                                            context,
                                            FullScreenImageViewer(
                                              imageUrl: data.url!.url,
                                            ));
                                      },
                                      child: Hero(
                                        tag: data.url!.url,
                                        child: CachedNetworkImage(
                                          imageUrl: data.url!.url,
                                          placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                          errorWidget: (context, url, error) => const Icon(Icons.error),
                                        ),
                                      ),
                                    ),
                                  ]),
                                ))
                            : FloatingActionButton(
                                mini: true,
                                heroTag: data.id,
                                backgroundColor: AppThemeData.primary500,
                                onPressed: () {
                                  push(
                                      context,
                                      FullScreenVideoViewer(
                                        heroTag: data.id.toString(),
                                        videoUrl: data.url!.url,
                                      ));
                                },
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                ),
                              ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _formatTimestamp(data.createdAt),
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
    );
  }

  // Writes inbox + chat in parallel (vs. the old sequential await-then-await),
  // then fires the FCM push in the background.
  Future<void> _sendMessage(String id, String message, Url? url, String videoThumbnail, String messageType) async {
    final inboxModel = InboxModel(
        customerId: widget.customerId,
        customerName: widget.customerName,
        restaurantId: widget.restaurantId,
        restaurantName: widget.restaurantName,
        createdAt: Timestamp.now(),
        orderId: widget.orderId,
        customerProfileImage: widget.customerProfileImage,
        restaurantProfileImage: widget.restaurantProfileImage,
        lastMessage: message,
        chatType: widget.chatType);

    final conversationModel = ConversationModel(
        id: id,
        message: message,
        senderId: widget.customerId,
        receiverId: widget.restaurantId,
        createdAt: Timestamp.now(),
        url: url,
        orderId: widget.orderId,
        messageType: messageType,
        videoThumbnail: videoThumbnail);

    if (url != null && url.mime.toString().isNotEmpty) {
      if (url.mime.contains('image')) {
        conversationModel.message = "sent An Image".tr(args: ['${MyAppState.currentUser!.firstName} ${MyAppState.currentUser!.lastName}']);
      } else if (url.mime.contains('video')) {
        conversationModel.message = "sent A Video".tr(args: ['${MyAppState.currentUser!.firstName} ${MyAppState.currentUser!.lastName}']);
      } else if (url.mime.contains('audio')) {
        conversationModel.message = "sent A VoiceMessage".tr(args: ['${MyAppState.currentUser!.firstName} ${MyAppState.currentUser!.lastName}']);
      }
    } else if (messageType != "text") {
      conversationModel.message = messageType == "image"
          ? "sent An Image"
          : messageType == "video"
              ? "sent A Video"
              : "sent A VoiceMessage";
    }

    await Future.wait([
      _writeInbox(inboxModel),
      _writeChat(conversationModel),
    ]);

    _sendNotificationInBackground(conversationModel, messageType);
  }

  Future<void> _writeInbox(InboxModel inboxModel) {
    if (widget.chatType == "Driver") return FireStoreUtils.addDriverInbox(inboxModel);
    if (widget.chatType == "Provider") return FireStoreUtils.addProviderInbox(inboxModel);
    if (widget.chatType == "Worker") return FireStoreUtils.addWorkerInbox(inboxModel);
    return FireStoreUtils.addRestaurantInbox(inboxModel);
  }

  Future<void> _writeChat(ConversationModel conv) {
    if (widget.chatType == "Driver") return FireStoreUtils.addDriverChat(conv);
    if (widget.chatType == "Provider") return FireStoreUtils.addProviderChat(conv);
    if (widget.chatType == "Worker") return FireStoreUtils.addWorkerChat(conv);
    return FireStoreUtils.addRestaurantChat(conv);
  }

  void _sendNotificationInBackground(ConversationModel cm, String messageType) async {
    try {
      String? fcmToken;
      Map<String, dynamic> payLoad;

      if (widget.type == "cab_parcel_chat") {
        final driver = await FireStoreUtils.getCurrentUser(widget.restaurantId.toString());
        fcmToken = driver?.fcmToken;
        payLoad = {
          "type": "cab_parcel_chat",
          "customerName": widget.customerName.toString(),
          "restaurantName": widget.restaurantName.toString(),
          "orderId": widget.orderId,
          "restaurantId": widget.restaurantId,
          "customerId": widget.customerId,
          "customerProfileImage": widget.customerProfileImage,
          "restaurantProfileImage": widget.restaurantProfileImage,
          "token": fcmToken,
          "chatType": widget.chatType,
        };
      } else if (widget.type == "vendor_chat") {
        final orderModel = await FireStoreUtils().getOrderById(widget.orderId);
        if (orderModel != null) {
          if (widget.chatType == "Restaurant") {
            final u = await FireStoreUtils.getCurrentUser(orderModel.vendor.author);
            fcmToken = u?.fcmToken;
          } else {
            final u = await FireStoreUtils.getCurrentUser(orderModel.driverID.toString());
            fcmToken = u?.fcmToken;
          }
        }
        payLoad = {
          "type": "vendor_chat",
          "customerName": widget.customerName.toString(),
          "restaurantName": widget.restaurantName.toString(),
          "orderId": widget.orderId,
          "restaurantId": widget.restaurantId,
          "customerId": widget.customerId,
          "customerProfileImage": widget.customerProfileImage,
          "restaurantProfileImage": widget.restaurantProfileImage,
          "token": fcmToken,
          "chatType": widget.chatType,
        };
      } else {
        final u = await FireStoreUtils.getCurrentUser(widget.restaurantId.toString());
        fcmToken = u?.fcmToken;
        payLoad = {
          "customerName": widget.customerName.toString(),
          "restaurantName": widget.restaurantName.toString(),
          "orderId": widget.orderId,
          "restaurantId": widget.restaurantId,
          "customerId": widget.customerId,
          "customerProfileImage": widget.customerProfileImage,
          "restaurantProfileImage": widget.restaurantProfileImage,
          "token": fcmToken,
          "chatType": widget.chatType,
        };
      }

      if (fcmToken != null && fcmToken.isNotEmpty) {
        SendNotification.sendChatFcmMessage(
            "${MyAppState.currentUser!.fullName()} ${messageType == "image" ? "sent image to you" : messageType == "video" ? "sent video to you" : "sent message to you"}",
            cm.message.toString(),
            fcmToken,
            payLoad);
      }
    } catch (_) {}
  }

  final ImagePicker _imagePicker = ImagePicker();

  _onCameraClick() {
    final action = CupertinoActionSheet(
      message: const Text(
        'sendMedia',
        style: TextStyle(fontSize: 15.0),
      ).tr(),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: const Text("chooseImageFromGallery").tr(),
          isDefaultAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              Url url = await FireStoreUtils().uploadChatImageToFireStorage(File(image.path), context);
              _sendMessage(const Uuid().v4(), '', url, '', 'image');
            }
          },
        ),
        CupertinoActionSheetAction(
          child: const Text("chooseVideoFromGallery").tr(),
          isDefaultAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? galleryVideo = await _imagePicker.pickVideo(source: ImageSource.gallery);
            if (galleryVideo != null) {
              ChatVideoContainer videoContainer = await FireStoreUtils().uploadChatVideoToFireStorage(File(galleryVideo.path), context);
              _sendMessage(const Uuid().v4(), '', videoContainer.videoUrl, videoContainer.thumbnailUrl, 'video');
            }
          },
        ),
        CupertinoActionSheetAction(
          child: const Text("takeAPicture").tr(),
          isDestructiveAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
            if (image != null) {
              Url url = await FireStoreUtils().uploadChatImageToFireStorage(File(image.path), context);
              _sendMessage(const Uuid().v4(), '', url, '', 'image');
            }
          },
        ),
        CupertinoActionSheetAction(
          child: const Text("recordVideo").tr(),
          isDestructiveAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? recordedVideo = await _imagePicker.pickVideo(source: ImageSource.camera);
            if (recordedVideo != null) {
              ChatVideoContainer videoContainer = await FireStoreUtils().uploadChatVideoToFireStorage(File(recordedVideo.path), context);
              _sendMessage(const Uuid().v4(), '', videoContainer.videoUrl, videoContainer.thumbnailUrl, 'video');
            }
          },
        )
      ],
      cancelButton: CupertinoActionSheetAction(
        child: const Text(
          'Cancel',
        ).tr(),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    );
    showCupertinoModalPopup(context: context, builder: (context) => action);
  }
}
