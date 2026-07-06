import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:unigrid_app/firebase_options.dart';

void main() {
  test('Query Firestore Schedule', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Initialize Firebase for the test
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print("Querying Firestore 'schedule' collection...");
    
    // Retrieve the schedule documents
    final snapshot = await FirebaseFirestore.instance.collection('schedule').get();
    
    print("Total documents found: ${snapshot.docs.length}");
    for (var doc in snapshot.docs) {
      print("Doc ID: ${doc.id} => ${doc.data()}");
    }
  });
}
