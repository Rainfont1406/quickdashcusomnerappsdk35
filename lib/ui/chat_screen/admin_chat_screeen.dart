import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_them_data.dart';
import '../../services/helper.dart';
import '../../main.dart';

class AdminChatScreen extends StatefulWidget {
  final String? orderId;
  final String? initialMessage;

  const AdminChatScreen({Key? key, this.orderId, this.initialMessage})
      : super(key: key);

  @override
  _AdminChatScreenState createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final String _userId;
  bool _isSending = false;

  static const _quickOptions = [
    'My order is delayed',
    'I received the wrong item',
    'Some items are missing',
    'Need help with payment',
    'Refund related issue',
    'Delivery related issue',
    'Need invoice or billing help',
  ];

  @override
  void initState() {
    super.initState();
    _userId = MyAppState.currentUser?.userID.isNotEmpty == true
        ? MyAppState.currentUser!.userID
        : (FirebaseAuth.instance.currentUser?.uid ?? '');
    debugPrint('AdminChat DEBUG: _userId=$_userId orderId=${widget.orderId}');
    if (widget.initialMessage?.isNotEmpty ?? false) {
      _controller.text = widget.initialMessage!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _shortOrderId {
    final id = widget.orderId;
    if (id == null || id.isEmpty) return '';
    return '#${id.length >= 8 ? id.substring(id.length - 8).toUpperCase() : id.toUpperCase()}';
  }

  Future<void> _send(String text) async {
    final content = text.trim();
    if (content.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _controller.clear();
    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'content': content,
        'timestamp': Timestamp.now(),
        'userId': _userId,
        'orderId': widget.orderId ?? '',
        'isAdmin': false,
        'isNewMsg': true,
        'isNewMsgCustomer': false,
        'isNewMsgAdmin': true,
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('AdminChat send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message. Try again.')),
        );
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    return Scaffold(
      backgroundColor:
          dark ? const Color(0xFF111118) : const Color(0xFFF2F3F8),
      appBar: _buildAppBar(dark),
      body: Column(
        children: [
          Expanded(child: _buildMessageArea(dark)),
          _buildInputBar(dark),
        ],
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(bool dark) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppThemeData.primary500,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.headset_mic_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QuickDash Support',
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6EF08C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _shortOrderId.isNotEmpty
                          ? 'Online · Order $_shortOrderId'
                          : 'Online',
                      style: TextStyle(
                        fontFamily: AppThemeData.regular,
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Message area ───────────────────────────────────────────────────────────

  Widget _buildMessageArea(bool dark) {
    // Filter by both userId and orderId so chips are per-conversation, not per-user.
    var query = FirebaseFirestore.instance
        .collection('messages')
        .where('userId', isEqualTo: _userId);
    if (widget.orderId?.isNotEmpty ?? false) {
      query = query.where('orderId', isEqualTo: widget.orderId);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final msgs = (snapshot.data?.docs ?? [])
            .map((d) => d.data() as Map<String, dynamic>)
            .toList()
          ..sort((a, b) {
            final at = a['timestamp'] is Timestamp
                ? (a['timestamp'] as Timestamp).millisecondsSinceEpoch
                : 0;
            final bt = b['timestamp'] is Timestamp
                ? (b['timestamp'] as Timestamp).millisecondsSinceEpoch
                : 0;
            return at.compareTo(bt);
          });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && msgs.isNotEmpty) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          children: [
            _buildWelcomeCard(dark),
            const SizedBox(height: 16),
            if (loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator.adaptive(
                    valueColor:
                        AlwaysStoppedAnimation(AppThemeData.primary500),
                  ),
                ),
              )
            else if (msgs.isEmpty) ...[
              _buildQuickHelpSection(dark),
              const SizedBox(height: 12),
            ] else ...[
              ..._buildMessagesWithSeparators(msgs, dark),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildMessagesWithSeparators(
      List<Map<String, dynamic>> msgs, bool dark) {
    final List<Widget> widgets = [];
    DateTime? lastDay;

    for (final data in msgs) {
      final ts = data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now();
      final msgDay = DateTime(ts.year, ts.month, ts.day);

      if (lastDay == null || msgDay != lastDay) {
        widgets.add(_buildDateSeparator(ts, dark));
        lastDay = msgDay;
      }
      widgets.add(_buildBubble(data, dark));
    }
    return widgets;
  }

  Widget _buildDateSeparator(DateTime ts, bool dark) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(ts.year, ts.month, ts.day);

    String label;
    if (msgDay == today) {
      label = 'Today';
    } else if (msgDay == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('d/M/yyyy').format(ts);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: dark ? Colors.white12 : Colors.black12,
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF252535)
                    : const Color(0xFFE8E9EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppThemeData.regular,
                  fontSize: 11,
                  color: dark
                      ? AppThemeData.neutral400
                      : AppThemeData.neutral500,
                ),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: dark ? Colors.white12 : Colors.black12,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  // Welcome card

  Widget _buildWelcomeCard(bool dark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C27) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppThemeData.primary500.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.support_agent_rounded,
                color: AppThemeData.primary500, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi there! 👋',
                  style: TextStyle(
                    fontFamily: AppThemeData.semiBold,
                    fontSize: 14,
                    color: dark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "We're here to help with your order. Pick a quick option below or describe your issue.",
                  style: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 12,
                    color: AppThemeData.neutral500,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Quick help section

  Widget _buildQuickHelpSection(bool dark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            'QUICK HELP',
            style: TextStyle(
              fontFamily: AppThemeData.semiBold,
              fontSize: 11,
              letterSpacing: 0.8,
              color: AppThemeData.neutral500,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _quickOptions.map((opt) => _buildQuickChip(opt, dark)).toList(),
        ),
      ],
    );
  }

  Widget _buildQuickChip(String label, bool dark) {
    return GestureDetector(
      onTap: () => _send(label),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1C1C27) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppThemeData.primary500.withValues(alpha: 0.38),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flash_on_rounded,
                size: 12, color: AppThemeData.primary500),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppThemeData.medium,
                fontSize: 12,
                color: dark
                    ? AppThemeData.neutral200
                    : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Message bubble

  Widget _buildBubble(Map<String, dynamic> data, bool dark) {
    final isAdmin = data['isAdmin'] == true;
    final content = data['content']?.toString() ?? '';
    final ts = data['timestamp'] is Timestamp
        ? (data['timestamp'] as Timestamp).toDate()
        : DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdmin) ...[
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppThemeData.primary500.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent_rounded,
                  size: 13, color: AppThemeData.primary500),
            ),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? (dark
                          ? const Color(0xFF252535)
                          : Colors.white)
                      : AppThemeData.primary500,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isAdmin ? 4 : 16),
                    bottomRight: Radius.circular(isAdmin ? 16 : 4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isAdmin
                          ? Colors.black.withValues(alpha: 0.06)
                          : AppThemeData.primary500.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content,
                      style: TextStyle(
                        fontFamily: AppThemeData.regular,
                        fontSize: 13,
                        height: 1.55,
                        color: isAdmin
                            ? (dark
                                ? Colors.white
                                : const Color(0xFF1A1A2E))
                            : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(ts),
                          style: TextStyle(
                            fontFamily: AppThemeData.regular,
                            fontSize: 10,
                            color: isAdmin
                                ? (dark
                                    ? AppThemeData.neutral500
                                    : AppThemeData.neutral400)
                                : Colors.white.withValues(alpha: 0.70),
                          ),
                        ),
                        if (!isAdmin) ...[
                          const SizedBox(width: 3),
                          Icon(
                            Icons.done_all_rounded,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!isAdmin) const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  Widget _buildInputBar(bool dark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1A1A24) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF262636)
                    : const Color(0xFFF4F5F9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: dark
                      ? AppThemeData.neutral700
                      : AppThemeData.neutral200,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 5,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontFamily: AppThemeData.regular,
                  fontSize: 14,
                  height: 1.45,
                  color: dark ? Colors.white : const Color(0xFF1A1A2E),
                ),
                decoration: InputDecoration(
                  hintText: 'Type your message…',
                  hintStyle: TextStyle(
                    fontFamily: AppThemeData.regular,
                    fontSize: 14,
                    color: AppThemeData.neutral400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isSending ? null : () => _send(_controller.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _isSending
                    ? AppThemeData.primary500.withValues(alpha: 0.55)
                    : AppThemeData.primary500,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _isSending
                    ? []
                    : [
                        BoxShadow(
                          color:
                              AppThemeData.primary500.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
