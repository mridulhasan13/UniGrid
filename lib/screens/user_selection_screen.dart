import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../widgets/unigrid_loader.dart';
import 'private_chat_screen.dart';

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
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search by name or email...',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                        .toList()
                      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                    final filteredUsers = users.where((u) {
                      return u.name.toLowerCase().contains(_searchQuery) ||
                          u.email.toLowerCase().contains(_searchQuery);
                    }).toList();

                    return ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(0.2),
                            ),
                            child: ClipOval(
                              child: user.photoUrl.startsWith('data:image')
                                  ? Image.memory(
                                      base64Decode(user.photoUrl.split(',').last),
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    )
                                  : (user.photoUrl.isNotEmpty
                                      ? Image.network(
                                          user.photoUrl,
                                          width: 40,
                                          height: 40,
                                          cacheWidth: 100,
                                          cacheHeight: 100,
                                          gaplessPlayback: true,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(
                                              child: Text(
                                                user.name.isNotEmpty ? user.name[0] : 'U',
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
                                            user.name.isNotEmpty ? user.name[0] : 'U',
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )),
                            ),
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
