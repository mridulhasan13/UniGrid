import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../widgets/linkified_text.dart';
import '../widgets/unigrid_loader.dart';
import '../utils/constants.dart';
import 'file_viewer_screen.dart';
import '../services/auth_service.dart';
import '../notifications/fcm_service.dart';

import '../notifications/in_app_notification.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../services/theme_service.dart';

class PrivateChatScreen extends StatefulWidget {
  final AppUser recipient;

  const PrivateChatScreen({super.key, required this.recipient});

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Uint8List> _base64BytesCache = {};
  List<types.Message> _messages = [];
  int _messageLimit = 50;
  late String _conversationId;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AppUser?>(context, listen: false);
    if (user != null) {
      _conversationId = _getConversationId(user.id, widget.recipient.id);
    }
  }

  String _getConversationId(String id1, String id2) {
    List<String> ids = [id1, id2];
    ids.sort();
    return ids.join('_');
  }

  void _handleSendPressed(types.PartialText message) async {
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
          debugPrint('Error resolving AppUser fallback in private chat: $e');
        }
      }
    }
    if (user == null) return;

    final timestamp = FieldValue.serverTimestamp();
    final preciseTime = DateTime.now().microsecondsSinceEpoch;

    final textMessage = {
      'authorId': user.id,
      'authorName': user.name.isNotEmpty ? user.name : user.email.split('@')[0],
      'authorPhoto': user.photoUrl,
      'createdAt': timestamp,
      'preciseTime': preciseTime,
      'id': const Uuid().v4(),
      'text': message.text,
      'type': 'text',
    };

    final conversationId = _getConversationId(user.id, widget.recipient.id);
    final conversationRef =
        _firestore.collection('conversations').doc(conversationId);

    // Concurrently write message and update conversation metadata (eliminates roundtrip delay)
    Future.wait([
      conversationRef.set({
        'participants': [user.id, widget.recipient.id],
        'lastMessage': message.text,
        'lastMessageTime': timestamp,
        'lastMessageSenderId': user.id,
        'unreadCount_${widget.recipient.id}': FieldValue.increment(1),
        'readStatus': {
          user.id: true,
          widget.recipient.id: false,
        },
      }, SetOptions(merge: true)),
      conversationRef.collection('messages').add(textMessage),
    ]).catchError((e) {
      debugPrint('[PrivateChatScreen] Error writing message: $e');
      return <dynamic>[];
    });

    // Dispatch notification asynchronously in background
    FCMService.sendPrivateNotification(
      recipientId: widget.recipient.id,
      title: user.name.isNotEmpty ? user.name : user.email.split('@')[0],
      body: message.text,
      senderUserId: user.id,
      messageId: textMessage['id'] as String?,
      extraData: {
        'target': 'private_chat',
        'type': 'private_chat',
        'route': '/private_chat',
        'senderUserId': user.id,
        'senderName': user.name,
        'senderPhoto': user.photoUrl,
      },
    ).catchError((e) {
      debugPrint('[PrivateChatScreen] Error sending push notification: $e');
    });
  }

  void _handleAttachmentPressed() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      if (!mounted) return;
      final user = Provider.of<AppUser?>(context, listen: false);
      if (user == null) return;
      final authService = Provider.of<AuthService>(context, listen: false);

      final conversationRef =
          _firestore.collection('conversations').doc(_conversationId);
      final timestamp = FieldValue.serverTimestamp();
      final preciseTime = DateTime.now().microsecondsSinceEpoch;

      for (final file in result.files) {
        Uint8List? fileBytes;
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          fileBytes = file.bytes!;
        } else if (file.path != null) {
          fileBytes = await File(file.path!).readAsBytes();
        }

        if (fileBytes != null) {
          final imageUrl = await authService.uploadChatImage(
              fileBytes, file.extension ?? 'jpg');

          final imageMessage = {
            'authorId': user.id,
            'authorName':
                user.name.isNotEmpty ? user.name : user.email.split('@')[0],
            'authorPhoto': user.photoUrl,
            'createdAt': timestamp,
            'preciseTime': preciseTime,
            'id': const Uuid().v4(),
            'uri': imageUrl,
            'name': file.name,
            'size': file.size,
            'type': 'image',
          };

          await conversationRef.collection('messages').add(imageMessage);
          FCMService.sendPrivateNotification(
            recipientId: widget.recipient.id,
            title: user.name.isNotEmpty ? user.name : user.email.split('@')[0],
            body: 'Sent an image',
            senderUserId: user.id,
            messageId: imageMessage['id'] as String?,
            extraData: {
              'target': 'private_chat',
              'type': 'private_chat',
              'route': '/private_chat',
              'senderUserId': user.id,
              'senderName': user.name,
              'senderPhoto': user.photoUrl,
            },
          );
        }
      }

      await conversationRef.set({
        'participants': [user.id, widget.recipient.id],
        'lastMessage':
            '${result.files.length > 1 ? "${result.files.length} Images" : "Image"}',
        'lastMessageTime': timestamp,
        'preciseTime': preciseTime,
        'readStatus': {
          user.id: true,
          widget.recipient.id: false,
        }
      }, SetOptions(merge: true));
    }
  }

  Future<void> _handleEndReached() async {
    setState(() {
      _messageLimit += 50;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appUser = Provider.of<AppUser?>(context);
    final themeService = Provider.of<ThemeService>(context);
    final currentTheme = themeService.currentTheme;
    if (appUser == null)
      return const Scaffold(
        body: UniGridLoader(
          title: 'Opening Secure Chat',
          subtitle: 'Connecting to database...',
        ),
      );

    final conversationId = _getConversationId(appUser.id, widget.recipient.id);

    final currentChatUser = types.User(
      id: appUser.id,
      firstName:
          appUser.name.isNotEmpty ? appUser.name : appUser.email.split('@')[0],
      imageUrl: appUser.photoUrl.isNotEmpty ? appUser.photoUrl : null,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.2),
              ),
              child: ClipOval(
                child: widget.recipient.photoUrl.startsWith('data:image')
                    ? Image.memory(
                        base64Decode(widget.recipient.photoUrl.split(',').last),
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      )
                    : (widget.recipient.photoUrl.isNotEmpty
                        ? Image.network(
                            widget.recipient.photoUrl,
                            width: 36,
                            height: 36,
                            cacheWidth: 100,
                            cacheHeight: 100,
                            gaplessPlayback: true,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Text(
                                  widget.recipient.name.isNotEmpty
                                      ? widget.recipient.name[0]
                                      : 'U',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              widget.recipient.name.isNotEmpty
                                  ? widget.recipient.name[0]
                                  : 'U',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.recipient.name.isNotEmpty ? widget.recipient.name : 'Student',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: AppColors.backgroundTop.withOpacity(0.5),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.mainBackground,
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('conversations')
                .doc(conversationId)
                .collection('messages')
                .orderBy('preciseTime', descending: true)
                .limit(_messageLimit)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(
                    child: Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: AppColors.textPrimary)));
              if (!snapshot.hasData)
                return const Center(
                  child: UniGridLoader(
                    title: 'Loading Conversation',
                    subtitle: 'Decrypting history...',
                    showBackground: false,
                  ),
                );

              _messages = snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final author = types.User(
                  id: data['authorId'] ?? '',
                  firstName: data['authorName'] ?? 'Student',
                  imageUrl: (data['authorPhoto'] != null &&
                          data['authorPhoto'].toString().isNotEmpty)
                      ? data['authorPhoto']
                      : null,
                );

                int timestamp = DateTime.now().millisecondsSinceEpoch;
                if (data['createdAt'] != null) {
                  try {
                    timestamp =
                        (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
                  } catch (e) {
                    debugPrint('Timestamp parse error: $e');
                  }
                }

                final preciseTime = data['preciseTime'] ?? timestamp * 1000;

                if (data['type'] == 'image') {
                  return types.ImageMessage(
                    author: author,
                    createdAt: timestamp,
                    id: data['id'] ?? doc.id,
                    name: data['name'] ?? 'image.jpg',
                    size: data['size'] ?? 0,
                    uri: data['uri'] ?? '',
                    metadata: {'preciseTime': preciseTime},
                  );
                }

                return types.TextMessage(
                  author: author,
                  createdAt: timestamp,
                  id: data['id'] ?? doc.id,
                  text: data['text'] ?? '',
                  metadata: {'preciseTime': preciseTime},
                );
              }).toList();

              _messages.sort((a, b) {
                final aTime = a.metadata?['preciseTime'] ?? 0;
                final bTime = b.metadata?['preciseTime'] ?? 0;
                return bTime.compareTo(aTime);
              });

              return Chat(
                messages: _messages,
                onSendPressed: _handleSendPressed,
                onAttachmentPressed: _handleAttachmentPressed,
                onEndReached: _handleEndReached,
                textMessageBuilder: (message, {required messageWidth, required showName}) {
                  final isMe = message.author.id == currentChatUser.id;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: LinkifiedText(
                      message.text,
                      selectable: true,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      linkStyle: TextStyle(
                        color: isMe ? Colors.cyanAccent : AppColors.primary,
                        decoration: TextDecoration.underline,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  );
                },
                onMessageTap: (context, message) {
                  if (message is types.ImageMessage) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FileViewerScreen(
                          fileName: message.name,
                          fileUrl: message.uri,
                        ),
                      ),
                    );
                  }
                },
                onMessageLongPress: (context, message) {
                  _showPrivateMessageActions(message);
                },
                user: currentChatUser,
                showUserAvatars: true,
                showUserNames: false,
                imageMessageBuilder: (message, {required messageWidth}) {
                  Widget imgWidget;
                  if (message.uri.startsWith('data:image')) {
                    try {
                      Uint8List bytes;
                      if (_base64BytesCache.containsKey(message.uri)) {
                        bytes = _base64BytesCache[message.uri]!;
                      } else {
                        final base64String = message.uri.split(',').last;
                        bytes = base64Decode(base64String);
                        _base64BytesCache[message.uri] = bytes;
                      }
                      imgWidget = Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      );
                    } catch (e) {
                      imgWidget = const SizedBox(
                        width: 150,
                        height: 150,
                        child: Icon(Icons.broken_image, color: AppColors.textPrimary),
                      );
                    }
                  } else if (message.uri.startsWith('http') ||
                      message.uri.startsWith('https')) {
                    imgWidget = Image.network(
                      message.uri,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    );
                  } else if (kIsWeb) {
                    imgWidget = Image.network(
                      message.uri,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    );
                  } else {
                    imgWidget = Image.file(
                      File(message.uri),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    );
                  }
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FileViewerScreen(
                            fileName: message.name,
                            fileUrl: message.uri,
                          ),
                        ),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: messageWidth.toDouble(),
                        maxHeight: 360,
                      ),
                      child: imgWidget,
                    ),
                  );
                },
                theme: DefaultChatTheme(
                  primaryColor: currentTheme == 'Black & White'
                      ? const Color(0xFF2E2E30)
                      : AppColors.primary,
                  secondaryColor: const Color(0xFF1E1E1E),
                  backgroundColor: Colors.transparent,
                  inputBackgroundColor:
                      AppColors.backgroundTop.withOpacity(0.9),
                  inputTextColor: AppColors.textPrimary,
                  receivedMessageBodyTextStyle:
                      const TextStyle(color: AppColors.textPrimary),
                  sentMessageBodyTextStyle: TextStyle(
                      color: currentTheme == 'Black & White'
                          ? Colors.white
                          : AppColors.onPrimary),
                  inputBorderRadius:
                      const BorderRadius.all(Radius.circular(20)),
                  inputMargin: const EdgeInsets.only(
                      left: 12, right: 12, top: 12, bottom: 12),
                ),
                avatarBuilder: (user) {
                  if (user.imageUrl != null &&
                      user.imageUrl!.startsWith('data:image')) {
                    try {
                      final base64String = user.imageUrl!.split(',').last;
                      return CircleAvatar(
                        radius: 16,
                        backgroundImage:
                            MemoryImage(base64Decode(base64String)),
                      );
                    } catch (e) {
                      return CircleAvatar(
                          radius: 16, child: Text(user.firstName?[0] ?? 'U'));
                    }
                  }
                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.2),
                    ),
                    child: ClipOval(
                      child: user.imageUrl != null && user.imageUrl!.isNotEmpty
                          ? Image.network(
                              user.imageUrl!,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    user.firstName?[0] ?? 'U',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                user.firstName?[0] ?? 'U',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showPrivateMessageActions(types.Message message) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isOwn = message.author.id == currentUid;
    String messageText = '';
    if (message is types.TextMessage) {
      messageText = message.text;
    } else if (message is types.ImageMessage) {
      messageText = '[Image: ${message.name}]';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
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
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (messageText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: Text(
                      messageText.length > 100 ? '${messageText.substring(0, 100)}…' : messageText,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      maxLines: 2,
                    ),
                  ),
                Divider(color: AppColors.textPrimary.withOpacity(0.08)),
                if (message is types.TextMessage && message.text.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: Colors.cyanAccent),
                    title: const Text('Copy Text', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: message.text));
                      InAppNotification.show(
                        context,
                        title: 'Copied',
                        message: 'Message text copied to clipboard',
                        accentColor: Colors.cyanAccent,
                        icon: Icons.copy_rounded,
                      );
                    },
                  ),
                if (!isOwn)
                  ListTile(
                    leading: const Icon(Icons.flag_rounded, color: Colors.amberAccent),
                    title: const Text('Report Message', style: TextStyle(color: Colors.amberAccent)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showReportPrivateDialog(message);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReportPrivateDialog(types.Message message) {
    String selectedReason = 'Inappropriate or Offensive Content';
    final List<String> reasons = [
      'Inappropriate or Offensive Content',
      'Harassment or Hate Speech',
      'Spam or Academic Dishonesty',
      'Misinformation or Impersonation',
      'Other Violation',
    ];

    String snippet = '';
    String? mediaUri;
    if (message is types.TextMessage) {
      snippet = message.text;
    } else if (message is types.ImageMessage) {
      snippet = '[Image: ${message.name}]';
      mediaUri = message.uri;
    }

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
            title: const Row(
              children: [
                Icon(Icons.flag_rounded, color: Colors.amberAccent, size: 22),
                SizedBox(width: 8),
                Text('Report Content', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select the reason for reporting this message by ${widget.recipient.name}:',
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
                            isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
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
                          await FirebaseFirestore.instance.collection('reports').add({
                            'reportedMessageId': message.id,
                            'reportedDocId': message.id,
                            'reportedAuthorId': widget.recipient.id,
                            'reportedAuthorName': widget.recipient.name,
                            'messageSnippet': snippet.isNotEmpty
                                ? (snippet.length > 250 ? '${snippet.substring(0, 250)}...' : snippet)
                                : '[Media]',
                            'messageType': message is types.ImageMessage ? 'image' : 'text',
                            'mediaUrl': mediaUri,
                            'reportedByUserId': user?.id ?? 'anonymous',
                            'reportedByName': user?.name.isNotEmpty == true ? user!.name : 'Student',
                            'reportedByEmail': user?.email ?? '',
                            'department': user?.department ?? '',
                            'batch': user?.batch ?? '',
                            'chatPath': 'conversations/${_getConversationId(user?.id ?? '', widget.recipient.id)}/messages',
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
                child: const Text('Submit Report', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}
