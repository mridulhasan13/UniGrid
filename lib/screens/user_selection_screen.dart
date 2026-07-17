import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/unigrid_loader.dart';
import 'private_chat_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final appUser = Provider.of<AppUser?>(context);
    if (appUser == null) return const Scaffold();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('New Message'),
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.textPrimary.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('users')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError)
                      return Center(
                          child: Text('Error: ${snapshot.error}',
                              style: TextStyle(color: AppColors.textPrimary)));
                    if (!snapshot.hasData)
                      return const Center(
                        child: UniGridLoader(
                          title: 'Finding Coworkers',
                          subtitle: 'Loading user directory...',
                          showBackground: false,
                        ),
                      );

                    final users = snapshot.data!.docs
                        .map((doc) {
                          return AppUser.fromMap(
                              doc.data() as Map<String, dynamic>, doc.id);
                        })
                        .where((u) => u.id != appUser.id)
                        .toList();

                    final filteredUsers = users.where((u) {
                      return u.name.toLowerCase().contains(_searchQuery) ||
                          u.email.toLowerCase().contains(_searchQuery);
                    }).toList();

                    return ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage: user.photoUrl.startsWith('data:image')
                                ? MemoryImage(
                                    base64Decode(user.photoUrl.split(',').last))
                                : ((user.photoUrl.isNotEmpty && (!kIsWeb || user.photoUrl.contains('supabase')))
                                    ? NetworkImage(user.photoUrl)
                                    : null) as ImageProvider?,
                            child: (user.photoUrl.isEmpty || (kIsWeb && !user.photoUrl.contains('supabase') && !user.photoUrl.startsWith('data:image')))
                                ? Text(
                                    user.name.isNotEmpty ? user.name[0] : 'U')
                                : null,
                          ),
                          title: Text(
                              user.name.isNotEmpty ? user.name : 'Student',
                              style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(user.email,
                              style: TextStyle(color: AppColors.textSecondary)),
                          onTap: () {
                            // Pop search screen and open chat
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      PrivateChatScreen(recipient: user)),
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
        ),
      ),
    );
  }
}
