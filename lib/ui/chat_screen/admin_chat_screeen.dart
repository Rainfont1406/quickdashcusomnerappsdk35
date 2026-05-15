import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../constants/typography.dart';
import '../../constants/spacing.dart';
import '../../constants/border_radius.dart';
import '../../constants/shadows.dart';
import '../../theme/app_them_data.dart';

class AdminChatScreen extends StatefulWidget {
  @override
  _AdminChatScreenState createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String userId = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppThemeData.primary500,
        elevation: 0,
        shadowColor: Colors.transparent,
        titleSpacing: AppSpacing.spacing4,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppThemeData.neutral0),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppThemeData.neutral0,
                borderRadius: AppBorderRadius.full,
              ),
              child: Icon(
                Icons.support_agent,
                color: AppThemeData.primary500,
                size: 20,
              ),
            ),
            SizedBox(width: AppSpacing.spacing3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support Chat',
                  style: AppTypography.h6.copyWith(
                    color: AppThemeData.neutral0,
                  ),
                ),
                // Text('Online', style: AppTypography.caption.copyWith(color: AppThemeData.neutral0.withOpacity(0.8))),
              ],
            ),
          ],
        ),
      ),
      body: Container(
        color: AppThemeData.neutral50,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('messages')
                    .orderBy('timestamp', descending: false)
                    .snapshots(),
                builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text('No messages yet.'));
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController
                          .jumpTo(_scrollController.position.maxScrollExtent);
                    }
                  });

                  final messages = snapshot.data!.docs
                      .where((doc) => doc['userId'] == userId)
                      .toList();

                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.all(AppSpacing.spacing4),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isAdminMessage = message['isAdmin'] == true;
                      final isUserMessage = message['userId'] == userId;
                      final timestamp =
                          (message['timestamp'] as Timestamp).toDate();
                      final timeString = DateFormat('HH:mm').format(timestamp);

                      return Align(
                        alignment: isAdminMessage
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          margin: EdgeInsets.only(
                            bottom: AppSpacing.spacing3,
                            left: isAdminMessage ? 0 : AppSpacing.spacing7,
                            right: isAdminMessage ? AppSpacing.spacing7 : 0,
                          ),
                          padding: EdgeInsets.all(AppSpacing.spacing3),
                          decoration: BoxDecoration(
                            color: isAdminMessage
                                ? AppThemeData.primary500
                                : AppThemeData.neutral0,
                            borderRadius: isAdminMessage
                                ? AppBorderRadius.lg.copyWith(
                                    topLeft: Radius.zero,
                                  )
                                : AppBorderRadius.lg.copyWith(
                                    topRight: Radius.zero,
                                  ),
                            boxShadow: [AppShadows.shadowSm],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['content'],
                                style: AppTypography.bodyMedium.copyWith(
                                  color: isAdminMessage
                                      ? AppThemeData.neutral0
                                      : AppThemeData.neutral900,
                                ),
                              ),
                              SizedBox(height: AppSpacing.spacing1),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      timeString,
                                      style: AppTypography.caption.copyWith(
                                        color: isAdminMessage
                                            ? AppThemeData.neutral100
                                            : AppThemeData.neutral600,
                                      ),
                                    ),
                                    if (isUserMessage) ...[
                                      SizedBox(width: AppSpacing.spacing1),
                                      Icon(
                                        Icons.done_all,
                                        size: 14,
                                        color: AppThemeData.primary500,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.all(AppSpacing.spacing4),
              color: AppThemeData.neutral0,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeData.neutral0,
                        borderRadius: AppBorderRadius.x3l,
                        border: Border.all(color: AppThemeData.neutral300),
                      ),
                      child: TextField(
                        controller: _controller,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppThemeData.neutral800,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type a message',
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: AppThemeData.neutral500,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.spacing4,
                            vertical: AppSpacing.spacing3,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: AppSpacing.spacing3),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppThemeData.primary500,
                      borderRadius: AppBorderRadius.lg,
                      boxShadow: [AppShadows.shadowSm],
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.send,
                        color: AppThemeData.neutral0,
                        size: 20,
                      ),
                      onPressed: () {
                        if (_controller.text.trim().isNotEmpty) {
                          FirebaseFirestore.instance
                              .collection('messages')
                              .add({
                            'content': _controller.text,
                            'timestamp': Timestamp.now(),
                            'userId': userId,
                            'isAdmin': false,
                            'isNewMsgCustomer': true,
                            'isNewMsgAdmin': false,
                          });
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
