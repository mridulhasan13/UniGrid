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
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../widgets/unigrid_loader.dart';
import '../utils/constants.dart';
import 'file_viewer_screen.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
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
    final user = Provider.of<AppUser?>(context, listen: false);
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

    final conversationRef =
        _firestore.collection('conversations').doc(_conversationId);

     // Write message
    await conversationRef.collection('messages').add(textMessage);
    FCMService.sendPrivateNotification(
      recipientId: widget.recipient.id,
      title: user.name.isNotEmpty ? user.name : user.email.split('@')[0],
      body: message.text,
      senderUserId: user.id,
      messageId: textMessage['id'] as String?,
    );

    // Update conversation metadata for Inbox sorting
    await conversationRef.set({
      'participants': [user.id, widget.recipient.id],
      'lastMessage': message.text,
      'lastMessageTime': timestamp,
      'lastMessageSenderId': user.id,
      'unreadCount_${widget.recipient.id}': FieldValue.increment(1),
    }, SetOptions(merge: true));
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
            CircleAvatar(
              radius: 16,
              backgroundImage: widget.recipient.photoUrl.startsWith('data:image')
                  ? MemoryImage(
                      base64Decode(widget.recipient.photoUrl.split(',').last))
                  : ((widget.recipient.photoUrl.isNotEmpty && (!kIsWeb || widget.recipient.photoUrl.contains('supabase')))
                      ? NetworkImage(widget.recipient.photoUrl)
                      : null) as ImageProvider?,
              child: (widget.recipient.photoUrl.isEmpty || (kIsWeb && !widget.recipient.photoUrl.contains('supabase') && !widget.recipient.photoUrl.startsWith('data:image')))
                  ? Text(widget.recipient.name.isNotEmpty
                      ? widget.recipient.name[0]
                      : 'U')
                  : null,
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
                .doc(_conversationId)
                .collection('messages')
                .orderBy('createdAt', descending: true)
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
                user: currentChatUser,
                showUserAvatars: true,
                showUserNames: false,
                imageMessageBuilder: (message, {required messageWidth}) {
                  Widget imgWidget;
                  if (message.uri.startsWith('data:image')) {
                    try {
                      final base64String = message.uri.split(',').last;
                      final bytes = base64Decode(base64String);
                      imgWidget = Image.memory(
                        bytes,
                        width: messageWidth.toDouble(),
                        fit: BoxFit.cover,
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
                      width: messageWidth.toDouble(),
                      fit: BoxFit.cover,
                    );
                  } else if (kIsWeb) {
                    imgWidget = Image.network(
                      message.uri,
                      width: messageWidth.toDouble(),
                      fit: BoxFit.cover,
                    );
                  } else {
                    imgWidget = Image.file(
                      File(message.uri),
                      width: messageWidth.toDouble(),
                      fit: BoxFit.cover,
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
                    child: imgWidget,
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
                  return CircleAvatar(
                    radius: 16,
                    backgroundImage: (user.imageUrl != null && (!kIsWeb || user.imageUrl!.contains('supabase')))
                        ? NetworkImage(user.imageUrl!)
                        : null,
                    child: (user.imageUrl == null || (kIsWeb && !user.imageUrl!.contains('supabase')))
                        ? Text(user.firstName?[0] ?? 'U')
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
