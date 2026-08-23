// ignore_for_file: unused_import
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import 'file_viewer_screen.dart';
import '../widgets/linkified_text.dart';
import '../widgets/unigrid_loader.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../services/auth_service.dart';

import '../notifications/fcm_service.dart';
import '../utils/dept_scope.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../notifications/in_app_notification.dart';

// ============================================================
// Data Model
// ============================================================
class _ChatMsg {
  final String docId;
  final String id;
  final String authorId;
  final String authorName;
  final String authorPhoto;
  final DateTime createdAt;
  final int preciseTime;
  final String text;
  final String type;
  final bool isCR;
  final Map<String, dynamic>? replyTo;
  final List<String> seenBy;
  final bool isUnsent;
  final bool isDeleted;
  final DateTime? editedAt;
  final String? uri;
  final String? fileName;
  final int? fileSize;

  const _ChatMsg({
    required this.docId,
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhoto,
    required this.createdAt,
    required this.preciseTime,
    required this.text,
    required this.type,
    required this.isCR,
    this.replyTo,
    required this.seenBy,
    required this.isUnsent,
    required this.isDeleted,
    this.editedAt,
    this.uri,
    this.fileName,
    this.fileSize,
  });

  factory _ChatMsg.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime createdAt = DateTime.now();
    if (data['createdAt'] != null) {
      try {
        createdAt = (data['createdAt'] as Timestamp).toDate();
      } catch (_) {}
    }
    List<String> seenBy = [];
    final rawSeen = data['seenBy'];
    if (rawSeen is List) seenBy = List<String>.from(rawSeen);

    Map<String, dynamic>? replyTo;
    final rawReply = data['replyTo'];
    if (rawReply is Map) replyTo = Map<String, dynamic>.from(rawReply);

    DateTime? editedAt;
    if (data['editedAt'] != null) {
      try {
        editedAt = (data['editedAt'] as Timestamp).toDate();
      } catch (_) {}
    }
    return _ChatMsg(
      docId: doc.id,
      id: data['id'] ?? doc.id,
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Unknown',
      authorPhoto: data['authorPhoto'] ?? '',
      createdAt: createdAt,
      preciseTime:
          data['preciseTime'] ?? createdAt.millisecondsSinceEpoch * 1000,
      text: data['text'] ?? '',
      type: data['type'] ?? 'text',
      isCR: data['isCR'] ?? false,
      replyTo: replyTo,
      seenBy: seenBy,
      isUnsent: data['isUnsent'] ?? false,
      isDeleted: data['isDeleted'] ?? false,
      editedAt: editedAt,
      uri: data['uri'],
      fileName: data['name'],
      fileSize: data['size'],
    );
  }
}

// ============================================================
// Swipe-to-Reply Wrapper
// ============================================================
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.onReply});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  final ValueNotifier<double> _offsetNotifier = ValueNotifier<double>(0.0);
  bool _triggered = false;

  @override
  void dispose() {
    _offsetNotifier.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx > 0) {
      final newOffset =
          (_offsetNotifier.value + details.delta.dx).clamp(0.0, 72.0);
      _offsetNotifier.value = newOffset;
      if (newOffset >= 58 && !_triggered) {
        _triggered = true;
        HapticFeedback.mediumImpact();
        widget.onReply();
      }
    }
  }

  void _onDragEnd(DragEndDetails _) {
    _offsetNotifier.value = 0.0;
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ValueListenableBuilder<double>(
        valueListenable: _offsetNotifier,
        builder: (context, offset, child) {
          return Stack(
            children: [
              // Reply icon revealed behind sliding message
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Opacity(
                      opacity: (offset / 58).clamp(0.0, 1.0),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.5),
                              width: 1),
                        ),
                        child: Icon(Icons.reply_rounded,
                            color: AppColors.textPrimary, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
              // Sliding message
              Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ============================================================
// Action Tile in Bottom Sheet
// ============================================================
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Seen By Bottom Sheet
// ============================================================
class _SeenBySheet extends StatelessWidget {
  final List<String> viewerIds;
  final FirebaseFirestore firestore;
  const _SeenBySheet({required this.viewerIds, required this.firestore});

  ImageProvider? _imgProvider(String photo) {
    if (photo.isEmpty) return null;
    if (photo.startsWith('data:image')) {
      try {
        return MemoryImage(base64Decode(photo.split(',').last));
      } catch (_) {}
    }
    return NetworkImage(photo);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundTop.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.done_all, color: AppColors.secondary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Seen by ${viewerIds.length}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: AppColors.textPrimary.withOpacity(0.08)),
              FutureBuilder<List<DocumentSnapshot>>(
                future: Future.wait(viewerIds
                    .map((id) => firestore.collection('users').doc(id).get())),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    );
                  }
                  final docs = snap.data ?? [];
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 24,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final data =
                          docs[i].data() as Map<String, dynamic>? ?? {};
                      final photo = data['photoUrl'] ?? '';
                      final name = data['name'] ?? 'Unknown';
                      final batch = data['batch'] ?? '';
                      final provider = _imgProvider(photo);
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.glassCardColor,
                          backgroundImage: provider,
                          child: provider == null
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold))
                              : null,
                        ),
                        title: Text(name,
                            style: TextStyle(color: AppColors.textPrimary)),
                        subtitle: batch.isNotEmpty
                            ? Text(batch,
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontSize: 12))
                            : null,
                        trailing: Icon(Icons.done_all,
                            color: AppColors.secondary, size: 18),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Message Bubble
// ============================================================
class _MessageBubble extends StatelessWidget {
  final _ChatMsg message;
  final bool isOwn;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.currentUserId,
    required this.onTap,
    required this.onLongPress,
  });

  static final Map<String, MemoryImage> _base64Cache = {};

  ImageProvider? _imgProvider(String photo) {
    if (photo.isEmpty) return null;
    if (photo.startsWith('data:image')) {
      if (_base64Cache.containsKey(photo)) {
        return _base64Cache[photo];
      }
      try {
        final decoded = MemoryImage(base64Decode(photo.split(',').last));
        _base64Cache[photo] = decoded;
        return decoded;
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(photo);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        bottom: 3,
        left: isOwn ? 48 : 0,
        right: isOwn ? 0 : 48,
      ),
      child: Align(
        alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isOwn) ...[
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.glassCardColor,
                  backgroundImage: _imgProvider(message.authorPhoto),
                  child: _imgProvider(message.authorPhoto) == null
                      ? Text(
                          message.authorName.isNotEmpty
                              ? message.authorName[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(child: _buildBubble(context)),
              if (isOwn) ...[
                const SizedBox(width: 4),
                _buildSeenIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeenIndicator() {
    final viewCount =
        message.seenBy.where((id) => id != message.authorId).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          viewCount > 0 ? Icons.done_all : Icons.check,
          size: 14,
          color: viewCount > 0 ? AppColors.secondary : AppColors.textSecondary,
        ),
        if (viewCount > 0)
          Text(
            '$viewCount',
            style: TextStyle(
                color: AppColors.secondary,
                fontSize: 9,
                fontWeight: FontWeight.bold),
          ),
      ],
    );
  }

  Widget _buildBubble(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context, listen: false);
    final currentTheme = themeService.currentTheme;
    final isBW = currentTheme == 'Black & White';
    final textColor = isOwn
        ? (isBW ? Colors.white : AppColors.onPrimary)
        : AppColors.textPrimary;

    final currentUser = Provider.of<AppUser?>(context, listen: false);
    final String currentUserName = currentUser?.name.replaceAll(' ', '_').toLowerCase() ?? '';
    final String msgLower = message.text.toLowerCase();
    final bool isMentioned = !isOwn && (
      (currentUserName.isNotEmpty && msgLower.contains('@$currentUserName')) ||
      msgLower.contains('@all') ||
      msgLower.contains('@everyone')
    );

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isOwn ? 18 : 4),
      bottomRight: Radius.circular(isOwn ? 4 : 18),
    );

    final screenWidth = MediaQuery.sizeOf(context).width;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: screenWidth * 0.72),
      decoration: BoxDecoration(
        color: isOwn
            ? (isBW
                ? const Color(0xFF2E2E30)
                : AppColors.primary.withOpacity(0.95))
            : (isMentioned
                ? const Color(0xFF252015)
                : const Color(0xFF1E1E1E)),
        borderRadius: radius,
        border: Border.all(
          color: isMentioned
              ? Colors.amberAccent.withOpacity(0.85)
              : (isOwn
                  ? (isBW
                      ? const Color(0xFF3F3F46)
                      : AppColors.primary.withOpacity(0.4))
                  : Colors.white.withOpacity(0.08)),
          width: isMentioned ? 1.2 : 0.8,
        ),
        boxShadow: isMentioned
            ? [
                BoxShadow(
                  color: Colors.amberAccent.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mentioned tag
          if (isMentioned)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.withOpacity(0.4), width: 0.5),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alternate_email_rounded, size: 10.5, color: Colors.amberAccent),
                  SizedBox(width: 3.5),
                  Text('Mentioned you',
                      style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          // Sender name for received messages
          if (!isOwn)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.authorName,
                    style: TextStyle(
                      color: message.isCR
                          ? AppColors.secondary
                          : AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (message.isCR) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'CR',
                        style: TextStyle(
                            color: AppColors.secondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Reply preview
          if (message.replyTo != null) _buildReplyPreview(textColor),
          // Content
          if (message.isUnsent)
            Text(
              'This message was unsent',
              style: TextStyle(
                color: textColor.withOpacity(0.45),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (message.type == 'image' && message.uri != null) ...[
            _buildImageContent(context),
            if (message.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              LinkifiedText(
                message.text,
                selectable: true,
                style: TextStyle(
                    color: textColor, fontSize: 14, height: 1.4),
                linkStyle: TextStyle(
                    color: isOwn ? Colors.cyanAccent : AppColors.primary,
                    decoration: TextDecoration.underline,
                    fontSize: 14,
                    height: 1.4),
                mentionStyle: TextStyle(
                    color: isOwn ? Colors.amberAccent : Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    height: 1.4),
              ),
            ],
          ] else
            LinkifiedText(
              message.text,
              selectable: true,
              style: TextStyle(
                  color: textColor, fontSize: 14, height: 1.4),
              linkStyle: TextStyle(
                  color: isOwn ? Colors.cyanAccent : AppColors.primary,
                  decoration: TextDecoration.underline,
                  fontSize: 14,
                  height: 1.4),
              mentionStyle: TextStyle(
                  color: isOwn ? Colors.amberAccent : Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  height: 1.4),
            ),
          // Timestamp + edited tag
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('h:mm a').format(message.createdAt),
                style: TextStyle(
                    color: textColor.withOpacity(0.45), fontSize: 10),
              ),
              if (message.editedAt != null) ...[
                const SizedBox(width: 5),
                Text(
                  '· edited',
                  style: TextStyle(
                      color: textColor.withOpacity(0.35),
                      fontSize: 10,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(Color textColor) {
    final replyData = message.replyTo!;
    final replyText = replyData['text'] as String? ?? '';
    final replyAuthor = replyData['authorName'] as String? ?? 'Unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isOwn ? textColor.withOpacity(0.7) : AppColors.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyAuthor,
            style: TextStyle(
              color: isOwn ? textColor.withOpacity(0.9) : AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyText.isEmpty ? 'Image' : replyText,
            style:
                TextStyle(color: textColor.withOpacity(0.55), fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final uri = message.uri!;
    Widget img;
    if (uri.startsWith('data:image')) {
      try {
        final bytes = base64Decode(uri.split(',').last);
        img = Image.memory(
          bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        );
      } catch (_) {
        img = const Center(
            child: Icon(Icons.broken_image, size: 48));
      }
    } else if (uri.startsWith('http')) {
      img = Image.network(
        uri,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        loadingBuilder: (ctx, child, prog) => prog == null
            ? child
            : const Center(child: CircularProgressIndicator()),
      );
    } else if (kIsWeb) {
      img = Image.network(uri, fit: BoxFit.contain, filterQuality: FilterQuality.high);
    } else {
      img = Image.file(File(uri), fit: BoxFit.contain, filterQuality: FilterQuality.high);
    }
    return GestureDetector(
      onTap: () {
        // Open full-screen image viewer on tap
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: Center(child: InteractiveViewer(child: img)),
          ),
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 280,
            maxHeight: 340,
          ),
          child: img,
        ),
      ),
    );
  }
}

// ============================================================
// Main ChatScreen
// ============================================================
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  int _messageLimit = 50;
  _ChatMsg? _replyingTo;
  _ChatMsg? _editingMessage;
  bool _isSending = false;
  final List<PlatformFile> _selectedFiles = [];
  bool _isUploadingFiles = false;
  final Set<String> _pendingSeenDocIds = {};

  List<AppUser> _departmentMembers = [];
  String? _mentionQuery;
  int? _mentionStartIndex;

  String get _chatPath {
    final user = Provider.of<AppUser?>(context, listen: false);
    return _getChatPathForUser(user);
  }

  String get _configPath {
    final user = Provider.of<AppUser?>(context, listen: false);
    return _getConfigPathForUser(user);
  }

  String _getChatPathForUser(AppUser? user) {
    if (user != null && user.hasDeptScope) {
      return deptBatchCol(user.department, user.batch, 'chat_messages');
    }
    return 'chats';
  }

  String _getConfigPathForUser(AppUser? user) {
    if (user != null && user.hasDeptScope) {
      return deptBatchCol(user.department, user.batch, 'config');
    }
    return 'config';
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleMentionQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthService>(context, listen: false).updateOnlineStatus(true);
      _loadDepartmentMembers();
    });
  }

  void _loadDepartmentMembers() {
    final user = Provider.of<AppUser?>(context, listen: false);
    if (user != null && user.department.isNotEmpty) {
      _firestore
          .collection('users')
          .where('department', isEqualTo: user.department)
          .where('batch', isEqualTo: user.batch)
          .get()
          .then((snap) {
        if (mounted) {
          setState(() {
            _departmentMembers = snap.docs
                .map((d) => AppUser.fromMap(d.data(), d.id))
                .where((m) => m.id != user.id)
                .toList();
          });
        }
      }).catchError((_) {});
    }
  }

  void _handleMentionQuery() {
    final text = _textController.text;
    final selection = _textController.selection;
    if (!selection.isValid || selection.baseOffset <= 0) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }

    final cursorPosition = selection.baseOffset;
    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAt = textBeforeCursor.lastIndexOf('@');

    if (lastAt != -1) {
      final prefix = textBeforeCursor.substring(lastAt + 1);
      // Ensure no newlines and no spaces before cursor
      if (!prefix.contains('\n') && (prefix.isEmpty || !prefix.contains(' '))) {
        if (_mentionQuery != prefix.toLowerCase() || _mentionStartIndex != lastAt) {
          setState(() {
            _mentionQuery = prefix.toLowerCase();
            _mentionStartIndex = lastAt;
          });
        }
        return;
      }
    }

    if (_mentionQuery != null) {
      setState(() {
        _mentionQuery = null;
        _mentionStartIndex = null;
      });
    }
  }

  void _insertMention(String tag) {
    if (_mentionStartIndex == null) return;
    final text = _textController.text;
    final cursorPosition = _textController.selection.baseOffset;
    final before = text.substring(0, _mentionStartIndex!);
    final after = (cursorPosition > 0 && cursorPosition <= text.length)
        ? text.substring(cursorPosition)
        : '';

    final cleanTag = tag.replaceAll(' ', '_');
    final newText = '$before@$cleanTag $after';
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: before.length + cleanTag.length + 2),
    );
    setState(() {
      _mentionQuery = null;
      _mentionStartIndex = null;
    });
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _textController.removeListener(_handleMentionQuery);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- SEND / EDIT MESSAGE ----
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if ((text.isEmpty && _selectedFiles.isEmpty) ||
        _isSending ||
        _isUploadingFiles) return;

    AppUser? user = Provider.of<AppUser?>(context, listen: false);
    if (user == null) {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        try {
          final doc = await _firestore.collection('users').doc(fbUser.uid).get();
          if (doc.exists && doc.data() != null) {
            user = AppUser.fromMap(doc.data()!, doc.id);
          }
        } catch (e) {
          debugPrint('Error resolving AppUser fallback in chat: $e');
        }
      }
    }

    if (user == null) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Authentication Required',
          message: 'Unable to send message. Please log in again.',
          accentColor: Colors.redAccent,
        );
      }
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);

    // Editing existing message
    if (_editingMessage != null) {
      setState(() => _isSending = true);
      await _firestore
          .collection(_chatPath)
          .doc(_editingMessage!.docId)
          .update({'text': text, 'editedAt': FieldValue.serverTimestamp()});
      setState(() {
        _editingMessage = null;
        _isSending = false;
      });
      _textController.clear();
      return;
    }

    final senderName =
        user.name.isNotEmpty ? user.name : user.email.split('@')[0];

    // Case A: Selected files to upload and send
    if (_selectedFiles.isNotEmpty) {
      setState(() {
        _isUploadingFiles = true;
      });
      try {
        final filesToSend = List<PlatformFile>.from(_selectedFiles);
        final captionText = text;

        setState(() {
          _selectedFiles.clear();
        });
        _textController.clear();

        for (int i = 0; i < filesToSend.length; i++) {
          final file = filesToSend[i];
          Uint8List fileBytes;
          if (file.bytes != null && file.bytes!.isNotEmpty) {
            fileBytes = file.bytes!;
          } else if (file.path != null) {
            fileBytes = await File(file.path!).readAsBytes();
          } else {
            throw Exception('File bytes are empty and file path is missing.');
          }
          final imageUrl = await authService.uploadChatImage(
              fileBytes, file.extension ?? 'jpg');

          final msgData = <String, dynamic>{
            'authorId': user.id,
            'authorName': senderName,
            'authorPhoto': user.photoUrl,
            'createdAt': FieldValue.serverTimestamp(),
            'preciseTime': DateTime.now().microsecondsSinceEpoch + i,
            'id': const Uuid().v4(),
            'text': i == 0 ? captionText : '',
            'type': 'image',
            'isCR': user.isCR,
            'seenBy': [user.id],
            'isUnsent': false,
            'isDeleted': false,
            'uri': imageUrl,
            'name': file.name,
            'size': file.size,
          };

          if (_replyingTo != null && i == 0) {
            msgData['replyTo'] = {
              'id': _replyingTo!.id,
              'text': _replyingTo!.isUnsent
                  ? 'This message was unsent'
                  : (_replyingTo!.type == 'image'
                      ? 'Image'
                      : _replyingTo!.text),
              'authorName': _replyingTo!.authorName,
            };
          }

          await _firestore.collection(_chatPath).add(msgData);
          FCMService.notifyNewMessage(
            senderName: senderName,
            text: i == 0 && captionText.isNotEmpty ? captionText : 'Sent an image',
            senderUserId: user.id,
            department: user.department,
            batch: user.batch,
            messageId: msgData['id'] as String?,
          );

        }
      } catch (e) {
        if (mounted) {
          InAppNotification.show(
            context,
            title: 'Upload Failed',
            message: 'Failed to upload image: $e',
            accentColor: Colors.redAccent,
            icon: Icons.error_outline_rounded,
          );
        }
      } finally {
        setState(() {
          _isUploadingFiles = false;
          _replyingTo = null;
        });
      }
      return;
    }

    // Case B: New regular text message
    setState(() => _isSending = true);
    final msgData = <String, dynamic>{
      'authorId': user.id,
      'authorName': senderName,
      'authorPhoto': user.photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'preciseTime': DateTime.now().microsecondsSinceEpoch,
      'id': const Uuid().v4(),
      'text': text,
      'type': 'text',
      'isCR': user.isCR,
      'seenBy': [user.id],
      'isUnsent': false,
      'isDeleted': false,
    };
    if (_replyingTo != null) {
      msgData['replyTo'] = {
        'id': _replyingTo!.id,
        'text': _replyingTo!.isUnsent
            ? 'This message was unsent'
            : (_replyingTo!.type == 'image' ? 'Image' : _replyingTo!.text),
        'authorName': _replyingTo!.authorName,
      };
    }
    _textController.clear();
    setState(() {
      _replyingTo = null;
      _isSending = false;
    });

    // Write message to Firestore without blocking UI
    _firestore
        .collection(_getChatPathForUser(user))
        .add(msgData)
        .catchError((e) {
      debugPrint('[ChatScreen] Error writing message: $e');
      return _firestore.collection(_getChatPathForUser(user)).doc('error');
    });

    // Dispatch notification asynchronously
    FCMService.notifyNewMessage(
      senderName: senderName,
      text: text,
      senderUserId: user.id,
      department: user.department,
      batch: user.batch,
      messageId: msgData['id'] as String?,
    ).catchError((e) {
      debugPrint('[ChatScreen] Error dispatching notification: $e');
    });
  }

  Timer? _seenDebounceTimer;
  final Set<String> _queuedSeenDocIds = {};

  // ---- BATCH MARK AS SEEN (Debounced to prevent snapshot storm) ----
  void _queueMarkAsSeen(_ChatMsg msg, String userId) {
    if (msg.authorId == userId) return;
    if (msg.seenBy.contains(userId)) return;
    if (_pendingSeenDocIds.contains(msg.docId) || _queuedSeenDocIds.contains(msg.docId)) return;

    _queuedSeenDocIds.add(msg.docId);
    _seenDebounceTimer?.cancel();
    _seenDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (_queuedSeenDocIds.isEmpty) return;
      final docIdsToUpdate = Set<String>.from(_queuedSeenDocIds);
      _queuedSeenDocIds.clear();
      _pendingSeenDocIds.addAll(docIdsToUpdate);

      final batch = _firestore.batch();
      for (final docId in docIdsToUpdate) {
        final ref = _firestore.collection(_chatPath).doc(docId);
        batch.update(ref, {'seenBy': FieldValue.arrayUnion([userId])});
      }
      try {
        await batch.commit();
      } catch (e) {
        debugPrint('[ChatScreen] Error committing seenBy batch: $e');
      }
    });
  }

  // ---- MANUAL MARK AS SEEN (On Tap) ----
  Future<void> _markAsSeen(_ChatMsg msg, String userId) async {
    if (msg.authorId == userId) return;
    if (msg.seenBy.contains(userId)) return;
    if (_pendingSeenDocIds.contains(msg.docId)) return;
    _pendingSeenDocIds.add(msg.docId);
    try {
      await _firestore.collection(_chatPath).doc(msg.docId).update({
        'seenBy': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      _pendingSeenDocIds.remove(msg.docId);
    }
  }

  // ---- SHOW SEEN BY ----
  void _showSeenBy(_ChatMsg msg) {
    final viewerIds = msg.seenBy.where((id) => id != msg.authorId).toList();
    if (viewerIds.isEmpty) {
      InAppNotification.show(
        context,
        title: 'Read Status',
        message: 'Not seen by anyone yet.',
        accentColor: AppColors.primary,
        icon: Icons.done_all_rounded,
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SeenBySheet(viewerIds: viewerIds, firestore: _firestore),
    );
  }

  // ---- MESSAGE ACTIONS ----
  void _showActions(_ChatMsg msg, AppUser user) {
    final isOwn = msg.authorId == user.id;
    final canDelete = isOwn || user.isCR;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: AppColors.backgroundTop.withOpacity(0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Message preview
                if (!msg.isUnsent && msg.type == 'text' && msg.text.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: Text(
                      msg.text.characters.length > 100
                          ? '${msg.text.characters.take(100)}…'
                          : msg.text,
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      maxLines: 2,
                    ),
                  ),
                Divider(color: AppColors.textPrimary.withOpacity(0.08)),
                // Reply (always available)
                _ActionTile(
                  icon: Icons.reply_rounded,
                  label: 'Reply',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyingTo = msg);
                    _focusNode.requestFocus();
                  },
                ),
                // Copy Text (for non-empty text messages)
                if (msg.text.isNotEmpty && !msg.isUnsent)
                  _ActionTile(
                    icon: Icons.copy_rounded,
                    label: 'Copy Text',
                    color: Colors.cyanAccent,
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: msg.text));
                      InAppNotification.show(
                        context,
                        title: 'Copied',
                        message: 'Message text copied to clipboard',
                        accentColor: Colors.cyanAccent,
                        icon: Icons.copy_rounded,
                      );
                    },
                  ),
                // Edit (own text messages only)
                if (isOwn && !msg.isUnsent && msg.type == 'text')
                  _ActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: Colors.blueAccent,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _editingMessage = msg;
                        _replyingTo = null;
                      });
                      _textController.text = msg.text;
                      _textController.selection = TextSelection.fromPosition(
                          TextPosition(offset: msg.text.length));
                      _focusNode.requestFocus();
                    },
                  ),
                // Unsend (own messages only)
                if (isOwn && !msg.isUnsent)
                  _ActionTile(
                    icon: Icons.undo_rounded,
                    label: 'Unsend',
                    color: Colors.orangeAccent,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _firestore
                          .collection(_chatPath)
                          .doc(msg.docId)
                          .update({'isUnsent': true, 'text': ''});
                    },
                  ),
                // Delete
                if (canDelete)
                  _ActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: isOwn ? 'Delete' : 'Delete (Admin)',
                    color: Colors.redAccent,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          backgroundColor: AppColors.backgroundTop,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          title: Text('Delete Message?',
                              style: TextStyle(color: AppColors.textPrimary)),
                          content: Text(
                              'This will permanently delete this message for everyone.',
                              style: TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('Delete',
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _firestore
                            .collection(_chatPath)
                            .doc(msg.docId)
                            .delete();
                      }
                    },
                  ),
                // Seen by (own messages)
                if (isOwn)
                  _ActionTile(
                    icon: Icons.done_all,
                    label: 'Seen by',
                    color: AppColors.secondary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showSeenBy(msg);
                    },
                  ),
                // Report Message (Play Store UGC Policy - other users' messages)
                if (!isOwn)
                  _ActionTile(
                    icon: Icons.flag_outlined,
                    label: 'Report Message',
                    color: Colors.amberAccent,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showReportDialog(msg);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  void _showReportDialog(_ChatMsg msg) {
    String selectedReason = 'Inappropriate or Offensive Content';
    final List<String> reasons = [
      'Inappropriate or Offensive Content',
      'Harassment or Hate Speech',
      'Spam or Academic Dishonesty',
      'Misinformation or Impersonation',
      'Other Violation',
    ];

    showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          bool isSubmitting = false;
          return AlertDialog(
            backgroundColor: AppColors.glassCardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.amberAccent.withOpacity(0.3)),
            ),
            title: Row(
              children: const [
                Icon(Icons.flag_rounded, color: Colors.amberAccent, size: 22),
                SizedBox(width: 8),
                Text(
                  'Report Content',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select the reason for reporting this message by ${msg.authorName}:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 14),
                ...reasons.map((r) {
                  final isSelected = selectedReason == r;
                  return InkWell(
                    onTap: () => setDialogState(() => selectedReason = r),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected ? Colors.amberAccent : AppColors.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppColors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          final user = Provider.of<AppUser?>(context, listen: false);
                          await _firestore.collection('reports').add({
                            'reportedMessageId': msg.id,
                            'reportedDocId': msg.docId,
                            'reportedAuthorId': msg.authorId,
                            'reportedAuthorName': msg.authorName,
                            'messageSnippet': msg.text.isNotEmpty
                                ? (msg.text.length > 250 ? '${msg.text.substring(0, 250)}...' : msg.text)
                                : '[Media: ${msg.type}]',
                            'messageType': msg.type,
                            'mediaUrl': msg.uri,
                            'reportedByUserId': user?.id ?? 'anonymous',
                            'reportedByName': user?.name.isNotEmpty == true ? user!.name : 'Student',
                            'reportedByEmail': user?.email ?? '',
                            'department': user?.department ?? '',
                            'batch': user?.batch ?? '',
                            'chatPath': _chatPath,
                            'reason': selectedReason,
                            'timestamp': FieldValue.serverTimestamp(),
                            'status': 'pending',
                          });

                          if (mounted) {
                            Navigator.pop(dialogCtx);
                            InAppNotification.show(
                              context,
                              title: 'Report Submitted',
                              message: 'Thank you for keeping our community safe. Our moderation team will review this.',
                              accentColor: Colors.amberAccent,
                              icon: Icons.check_circle_outline_rounded,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.pop(dialogCtx);
                            InAppNotification.show(
                              context,
                              title: 'Report Notice',
                              message: 'Report received. Thank you.',
                              accentColor: Colors.amberAccent,
                              icon: Icons.flag_rounded,
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Submit Report',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- ATTACHMENT ----
  Future<void> _handleAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _selectedFiles
          .addAll(result.files.where((f) => f.bytes != null || f.path != null));
    });
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final appUser = Provider.of<AppUser?>(context);
    if (appUser == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          _buildAppBar(),
          Expanded(child: _buildMessageList(appUser)),
          if (_replyingTo != null) _buildReplyBanner(),
          if (_editingMessage != null) _buildEditBanner(),
          _buildInputBar(appUser),
        ],
      ),
    );
  }

  // ---- APP BAR ----
  Widget _buildAppBar() {
    final user = Provider.of<AppUser?>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isAllowed =
        user != null && (user.isCR || authService.isRootAdmin(user.email));

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore
          .collection(_getConfigPathForUser(user))
          .doc('department')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final deptName = data?['name'] as String? ?? 'IPE Department';
        final logoUrl = data?['logoUrl'] as String?;

        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.glassCardColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.glassCardBorder.withOpacity(0.7),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Dept Logo
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.secondary.withOpacity(0.8)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.45),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: (logoUrl != null && logoUrl.isNotEmpty)
                            ? ClipOval(
                                child: logoUrl.startsWith('data:image')
                                    ? Builder(
                                        builder: (context) {
                                          try {
                                            return Image.memory(
                                              base64Decode(logoUrl.split(',').last),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.school_rounded,
                                                      color: AppColors.textPrimary,
                                                      size: 20),
                                            );
                                          } catch (_) {
                                            return Icon(Icons.school_rounded,
                                                color: AppColors.textPrimary, size: 20);
                                          }
                                        },
                                      )
                                    : Image.network(
                                        logoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.school_rounded,
                                            color: AppColors.textPrimary,
                                            size: 20),
                                      ),
                              )
                            : Icon(Icons.school_rounded,
                                color: AppColors.textPrimary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      // Dept name + live indicator
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              deptName,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(right: 5),
                                  decoration: const BoxDecoration(
                                    color: Colors.greenAccent,
                                    shape: BoxShape.circle,
                                  ),
                                )
                                    .animate(onPlay: (c) => c.repeat(reverse: true))
                                    .fadeIn(duration: 700.ms),
                                Text(
                                  'Department Chat',
                                  style: TextStyle(
                                      color: AppColors.textPrimary.withOpacity(0.45),
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isAllowed) ...[
                        IconButton(
                          icon: Icon(
                            Icons.people_alt_rounded,
                            color: AppColors.textSecondary,
                            size: 24,
                          ),
                          onPressed: () => _showMembersDialog(context, user!),
                          tooltip: 'View Department Members',
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.edit_note_rounded,
                            color: AppColors.textSecondary,
                            size: 24,
                          ),
                          onPressed: () => _showEditDeptDialog(deptName, logoUrl),
                          tooltip: 'Edit Department Details',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- MEMBERS DIALOG ----
  void _showMembersDialog(BuildContext context, AppUser currentUser) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.backgroundTop,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: AppColors.glassCardBorder,
              width: 1.5,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 600,
              maxHeight: 700,
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('department', isEqualTo: currentUser.department)
                  .where('batch', isEqualTo: currentUser.batch)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(
                        'No members found',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;
                final members = docs
                    .map((d) => AppUser.fromMap(
                        d.data() as Map<String, dynamic>, d.id))
                    .toList();

                // Sort: CRs first, then by Student ID
                members.sort((a, b) {
                  if (a.isCR && !b.isCR) return -1;
                  if (!a.isCR && b.isCR) return 1;
                  return a.studentId.compareTo(b.studentId);
                });

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${currentUser.department} - Batch ${currentUser.batch}',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total Members: ${members.length}',
                                style: TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            color: AppColors.textSecondary,
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    // Members list
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final String displayName = member.name.isNotEmpty
                              ? member.name
                              : (member.email.contains('@')
                                  ? member.email.split('@')[0]
                                  : 'Student');

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: AppColors.primary.withOpacity(0.15),
                                      backgroundImage: member.photoUrl.startsWith('data:image')
                                          ? MemoryImage(base64Decode(member.photoUrl.split(',').last))
                                          : (member.photoUrl.isNotEmpty
                                              ? NetworkImage(member.photoUrl)
                                              : null) as ImageProvider?,
                                      child: member.photoUrl.isEmpty
                                          ? Text(
                                              displayName[0].toUpperCase(),
                                              style: TextStyle(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            )
                                          : null,
                                    ),
                                    if (member.isCR)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.amber,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.star,
                                            size: 10,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              displayName,
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13.5,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (member.isCR) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withOpacity(0.18),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.amber.withOpacity(0.4), width: 0.5),
                                              ),
                                              child: const Text(
                                                'CR',
                                                style: TextStyle(
                                                  color: Colors.amber,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        member.studentId.isNotEmpty
                                            ? 'ID: ${member.studentId}'
                                            : 'No ID set',
                                        style: TextStyle(
                                          color: member.studentId.isNotEmpty
                                              ? AppColors.textSecondary
                                              : AppColors.textSecondary.withOpacity(0.5),
                                          fontSize: 11.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    member.email,
                                    style: TextStyle(
                                      color: AppColors.textSecondary.withOpacity(0.85),
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ---- EDIT DEPARTMENT DETAILS DIALOG ----
  Future<void> _showEditDeptDialog(
      String currentName, String? currentLogoUrl) async {
    final nameController = TextEditingController(text: currentName);
    String? newLogoUrl = currentLogoUrl;
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            ImageProvider? imgProvider;
            if (newLogoUrl != null && newLogoUrl!.isNotEmpty) {
              if (newLogoUrl!.startsWith('data:image')) {
                try {
                  imgProvider =
                      MemoryImage(base64Decode(newLogoUrl!.split(',').last));
                } catch (_) {}
              } else {
                imgProvider = NetworkImage(newLogoUrl!);
              }
            }

            Future<void> pickAndUploadLogo() async {
              final authService = Provider.of<AuthService>(ctx, listen: false);
              setModalState(() {
                isUploading = true;
              });
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.image,
                  withData: true,
                );
                if (result != null && result.files.isNotEmpty) {
                  final file = result.files.first;
                  Uint8List? fileBytes;
                  if (file.bytes != null && file.bytes!.isNotEmpty) {
                    fileBytes = file.bytes!;
                  } else if (file.path != null) {
                    fileBytes = await File(file.path!).readAsBytes();
                  }

                  if (fileBytes != null) {
                    final uploadedUrl = await authService.uploadChatImage(
                      fileBytes,
                      file.extension ?? 'jpg',
                    );
                    setModalState(() {
                      newLogoUrl = uploadedUrl;
                    });
                  }
                }
              } catch (e) {
                if (ctx.mounted) {
                  InAppNotification.show(
                    ctx,
                    title: 'Upload Failed',
                    message: 'Upload failed: $e',
                    accentColor: Colors.redAccent,
                    icon: Icons.error_outline_rounded,
                  );
                }
              } finally {
                setModalState(() {
                  isUploading = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom,
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundTop.withOpacity(0.92),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Text(
                          'Edit Department Details',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Logo Preview + Action
                        GestureDetector(
                          onTap: isUploading ? null : pickAndUploadLogo,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.3),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 38,
                                  backgroundColor: AppColors.glassCardColor,
                                  backgroundImage: imgProvider,
                                  child: imgProvider == null
                                      ? Icon(
                                          Icons.school_rounded,
                                          color: AppColors.textPrimary,
                                          size: 36,
                                        )
                                      : null,
                                ),
                              ),
                              if (isUploading)
                                const SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.greenAccent),
                                  ),
                                )
                              else
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.backgroundTop,
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      color: AppColors.textPrimary,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isUploading
                              ? 'Uploading Logo...'
                              : 'Tap to change photo',
                          style: TextStyle(
                            color: isUploading
                                ? Colors.greenAccent
                                : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Name Input
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.textPrimary.withOpacity(0.1)),
                          ),
                          child: TextField(
                            controller: nameController,
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'Department Name',
                              labelStyle:
                                  TextStyle(color: AppColors.textSecondary),
                              floatingLabelStyle:
                                  TextStyle(color: AppColors.primary),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Save / Cancel
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: isUploading
                                    ? null
                                    : () => Navigator.pop(ctx),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textSecondary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isUploading
                                    ? null
                                    : () async {
                                        final newName =
                                            nameController.text.trim();
                                        if (newName.isEmpty) return;
                                        await _firestore
                                            .collection(_configPath)
                                            .doc('department')
                                            .set({
                                          'name': newName,
                                          'logoUrl': newLogoUrl,
                                        }, SetOptions(merge: true));
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          InAppNotification.show(
                                            ctx,
                                            title: 'Department Updated',
                                            message: 'Department details updated successfully!',
                                            accentColor: AppColors.primary,
                                            icon: Icons.business_rounded,
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Save',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- MESSAGE LIST ----
  Widget _buildMessageList(AppUser appUser) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection(_getChatPathForUser(appUser))
          .orderBy('preciseTime', descending: true)
          .limit(_messageLimit)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Text('Error: ${snap.error}',
                  style: TextStyle(color: AppColors.textPrimary)));
        }
        if (!snap.hasData) {
          return const UniGridLoader(
            title: 'Loading Chat',
            subtitle: 'Fetching group messages...',
            showBackground: false,
          );
        }

        final msgs = snap.data!.docs.map((d) => _ChatMsg.fromDoc(d)).toList()
          ..sort((a, b) => b.preciseTime.compareTo(a.preciseTime));

        // Batch mark unread messages as seen in database post-frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final msg in msgs) {
            if (msg.authorId != appUser.id && !msg.seenBy.contains(appUser.id)) {
              _queueMarkAsSeen(msg, appUser.id);
            }
          }
        });

        if (msgs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.textPrimary.withOpacity(0.2), size: 48),
                const SizedBox(height: 12),
                Text('No messages yet. Say hi!',
                    style: TextStyle(
                        color: AppColors.textPrimary.withOpacity(0.3), fontSize: 15)),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: msgs.length + 1,
          itemBuilder: (ctx, i) {
            if (i == msgs.length) {
              return Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Load older messages'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  onPressed: () => setState(() => _messageLimit += 50),
                ),
              );
            }
            final msg = msgs[i];
            final isOwn = msg.authorId == appUser.id;
            final showDate = i == msgs.length - 1 ||
                !_sameDay(msg.createdAt, msgs[i + 1].createdAt);

            return Column(
              key: ValueKey(msg.id),
              children: [
                if (showDate) _dateSeparator(msg.createdAt),
                _SwipeToReply(
                  onReply: () {
                    setState(() => _replyingTo = msg);
                    _focusNode.requestFocus();
                  },
                  child: _MessageBubble(
                    message: msg,
                    isOwn: isOwn,
                    currentUserId: appUser.id,
                    onTap: () {
                      if (msg.type == 'image' && msg.uri != null) {
                        if (!isOwn) {
                          _markAsSeen(msg, appUser.id);
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FileViewerScreen(
                              fileName: msg.fileName ?? 'Image.jpg',
                              fileUrl: msg.uri,
                            ),
                          ),
                        );
                      } else {
                        if (isOwn) {
                          _showSeenBy(msg);
                        } else {
                          _markAsSeen(msg, appUser.id);
                          HapticFeedback.selectionClick();
                        }
                      }
                    },
                    onLongPress: () => _showActions(msg, appUser),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 200.ms)
                    .slideY(begin: 0.05, end: 0, duration: 200.ms),
              ],
            );
          },
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dateSeparator(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_sameDay(date, now)) {
      label = 'Today';
    } else if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, y').format(date);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.textPrimary.withOpacity(0.1))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.textPrimary.withOpacity(0.45), fontSize: 11)),
            ),
          ),
          Expanded(child: Divider(color: AppColors.textPrimary.withOpacity(0.1))),
        ],
      ),
    );
  }

  // ---- REPLY BANNER ----
  Widget _buildReplyBanner() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            border: Border(
              top: BorderSide(color: AppColors.primary.withOpacity(0.3)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Replying to ${_replyingTo!.authorName}',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _replyingTo!.isUnsent
                          ? 'Unsent message'
                          : (_replyingTo!.type == 'image'
                              ? 'Image'
                              : _replyingTo!.text),
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                onPressed: () => setState(() => _replyingTo = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- EDIT BANNER ----
  Widget _buildEditBanner() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.12),
            border: Border(
              top: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Editing message',
                        style: TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text(
                      _editingMessage!.text,
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                onPressed: () {
                  setState(() => _editingMessage = null);
                  _textController.clear();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- MENTION AUTOCOMPLETE OVERLAY ----
  Widget _buildMentionOverlay() {
    if (_mentionQuery == null) return const SizedBox.shrink();

    final query = _mentionQuery!;
    final List<Map<String, dynamic>> items = [];

    // Option 1: @all / @everyone
    if ('all'.startsWith(query) || 'everyone'.startsWith(query) || query.isEmpty) {
      items.add({
        'isSpecial': true,
        'tag': 'all',
        'title': '@all',
        'subtitle': 'Notify all batch members',
        'icon': Icons.campaign_rounded,
        'color': Colors.amberAccent,
      });
    }

    // Option 2: Department members
    for (final member in _departmentMembers) {
      final name = member.name.isNotEmpty ? member.name : member.email.split('@')[0];
      final cleanName = name.replaceAll(' ', '_');
      if (name.toLowerCase().contains(query) || cleanName.toLowerCase().contains(query) || member.studentId.contains(query)) {
        items.add({
          'isSpecial': false,
          'tag': cleanName,
          'title': name,
          'subtitle': member.studentId.isNotEmpty ? 'ID: ${member.studentId}' : member.email,
          'photo': member.photoUrl,
          'isCR': member.isCR,
          'color': member.isCR ? Colors.amber : AppColors.primary,
        });
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundTop.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(
              color: AppColors.textPrimary.withOpacity(0.06),
              height: 1,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final bool isSpecial = item['isSpecial'] == true;
              final String tag = item['tag'];
              final String title = item['title'];
              final String subtitle = item['subtitle'];
              final Color color = item['color'];

              Widget leadingWidget;
              if (isSpecial) {
                leadingWidget = Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item['icon'] as IconData, color: color, size: 17),
                );
              } else {
                final photo = (item['photo'] as String?) ?? '';
                ImageProvider? provider;
                if (photo.isNotEmpty) {
                  if (photo.startsWith('data:image')) {
                    try {
                      provider = MemoryImage(base64Decode(photo.split(',').last));
                    } catch (_) {}
                  } else {
                    provider = NetworkImage(photo);
                  }
                }
                leadingWidget = CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withOpacity(0.18),
                  backgroundImage: provider,
                  child: provider == null
                      ? Text(
                          title.isNotEmpty ? title[0].toUpperCase() : 'U',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        )
                      : null,
                );
              }

              return InkWell(
                onTap: () => _insertMention(tag),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: [
                      leadingWidget,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item['isCR'] == true) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber.withOpacity(0.5), width: 0.5),
                                    ),
                                    child: const Text(
                                      'CR',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.north_west_rounded, size: 13, color: AppColors.textSecondary.withOpacity(0.4)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- INPUT BAR ----
  Widget _buildInputBar(AppUser appUser) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 10,
            bottom: MediaQuery.of(context).padding.bottom + 12 + 12,
          ),
          decoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMentionOverlay(),
              if (_selectedFiles.isNotEmpty) ...[
                _buildSelectedFilesPreview(),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment
                  IconButton(
                    icon: Icon(Icons.add_photo_alternate_outlined,
                        color: AppColors.primary),
                    onPressed: _handleAttachment,
                  ),
                  // Text field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style:
                            TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        maxLines: 5,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: _editingMessage != null
                              ? 'Edit message…'
                              : 'Message IPE…',
                          hintStyle: TextStyle(
                              color: AppColors.textPrimary.withOpacity(0.3),
                              fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.45),
                            blurRadius: 14,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: (_isSending || _isUploadingFiles)
                          ? Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                                ),
                              ),
                            )
                          : Icon(
                              _editingMessage != null
                                  ? Icons.check_rounded
                                  : Icons.send_rounded,
                              color: AppColors.onPrimary,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- SELECTED FILES PREVIEW ----
  Widget _buildSelectedFilesPreview() {
    return Container(
      height: 76,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _selectedFiles.length,
        itemBuilder: (ctx, i) {
          final file = _selectedFiles[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.glassCardBorder),
                    ),
                    child: file.bytes != null
                        ? Image.memory(file.bytes!, fit: BoxFit.cover)
                        : (file.path != null && !kIsWeb
                            ? Image.file(File(file.path!), fit: BoxFit.cover)
                            : Center(
                                child: Icon(Icons.insert_drive_file,
                                    color: AppColors.textSecondary))),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFiles.removeAt(i);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close,
                          color: AppColors.textPrimary, size: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
