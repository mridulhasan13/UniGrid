import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/unigrid_loader.dart';
import 'chat_screen.dart'; // Department Chat
import 'private_chat_screen.dart'; // Private Chat
import 'user_selection_screen.dart'; // New chat picker

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final appUser = Provider.of<AppUser?>(context);
    if (appUser == null)
      return const UniGridLoader(
        title: 'Loading Chats',
        subtitle: 'Retrieving conversation logs...',
      );

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          AppBar(
            title: const Text('Chats'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_square),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const UserSelectionScreen()),
                  );
                },
              )
            ],
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('conversations')
                  .where('participants', arrayContains: appUser.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: TextStyle(color: AppColors.textPrimary)));
                }

                final List<DocumentSnapshot> conversations =
                    snapshot.data?.docs.toList() ?? [];

                // Sort locally to avoid needing a Firestore Composite Index
                conversations.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  final timeA = (dataA['lastMessageTime'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  final timeB = (dataB['lastMessageTime'] as Timestamp?)
                          ?.millisecondsSinceEpoch ??
                      0;
                  return timeB.compareTo(timeA); // Descending order
                });

                return ListView.builder(
                  itemCount:
                      conversations.length + 1, // +1 for the Department Chat
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Pinned Department Chat
                      return _buildDepartmentChatTile(context);
                    }

                    final doc = conversations[index - 1];
                    final data = doc.data() as Map<String, dynamic>;

                    final List<dynamic> participants =
                        data['participants'] ?? [];
                    final String otherUserId = participants
                        .firstWhere((id) => id != appUser.id, orElse: () => '');

                    if (otherUserId.isEmpty) return const SizedBox.shrink();

                    return FutureBuilder<DocumentSnapshot>(
                      future:
                          _firestore.collection('users').doc(otherUserId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData)
                          return const SizedBox.shrink();

                        final userData =
                            userSnapshot.data!.data() as Map<String, dynamic>?;
                        if (userData == null) return const SizedBox.shrink();

                        final AppUser otherUser =
                            AppUser.fromMap(userData, userSnapshot.data!.id);
                        final String lastMessage = data['lastMessage'] ?? '';
                        final Timestamp? lastTime =
                            data['lastMessageTime'] as Timestamp?;

                        final Map<String, dynamic> readStatus =
                            data['readStatus'] ?? {};
                        final bool isUnread = readStatus[appUser.id] == false;

                        return _buildConversationTile(
                          context,
                          user: otherUser,
                          lastMessage: lastMessage,
                          time: lastTime != null
                              ? _formatTime(lastTime.toDate())
                              : '',
                          isUnread: isUnread,
                          onTap: () {
                            // Mark as read
                            doc.reference.set({
                              'readStatus': {appUser.id: true}
                            }, SetOptions(merge: true));

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      PrivateChatScreen(recipient: otherUser)),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentChatTile(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.groups, color: AppColors.textPrimary),
      ),
      title: Text('Department Chat',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      subtitle: Text('Tap to open group chat',
          style: TextStyle(color: AppColors.textSecondary)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => const Scaffold(
                    extendBodyBehindAppBar: true,
                    body: ChatScreen(), // The existing chat screen
                  )),
        );
      },
    );
  }

  Widget _buildConversationTile(
    BuildContext context, {
    required AppUser user,
    required String lastMessage,
    required String time,
    required bool isUnread,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundImage: user.photoUrl.startsWith('data:image')
                ? MemoryImage(base64Decode(user.photoUrl.split(',').last))
                : (user.photoUrl.isNotEmpty
                    ? NetworkImage(user.photoUrl)
                    : null) as ImageProvider?,
            child: user.photoUrl.isEmpty
                ? Text(user.name.isNotEmpty ? user.name[0] : 'U')
                : null,
          ),
          if (user.isCR) // Example badge
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.backgroundTop, width: 2),
                ),
                child: Icon(Icons.star, size: 10, color: AppColors.textPrimary),
              ),
            ),
        ],
      ),
      title: Text(user.name.isNotEmpty ? user.name : 'Student',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(
        lastMessage,
        style: TextStyle(
          color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(time,
              style: TextStyle(
                  color: isUnread ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 12)),
          if (isUnread) ...[
            const SizedBox(height: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ]
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inDays > 0) {
      if (difference.inDays == 1) return 'Yesterday';
      return '${time.day}/${time.month}';
    }
    final hours =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minutes = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hours:$minutes $period';
  }
}
