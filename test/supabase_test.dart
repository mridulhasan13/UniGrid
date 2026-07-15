import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:unigrid_app/services/supabase_config.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock SharedPreferences channel to avoid MissingPluginException in unit test environment
  const MethodChannel('plugins.flutter.io/shared_preferences')
      .setMockMethodCallHandler((MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, dynamic>{};
    }
    return null;
  });

  test('Verify Supabase connection and bucket access', () async {
    // Initialize Supabase client
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    final client = Supabase.instance.client;
    print('Supabase initialized with URL: \${SupabaseConfig.url}');

    try {
      // List the files in the bucket to verify access
      final List<FileObject> list = await client.storage.from(SupabaseConfig.bucket).list();
      print('✅ Supabase Connection Successful!');
      print('Bucket: \${SupabaseConfig.bucket}');
      print('Files found: \${list.length}');
      for (var file in list) {
        print('- \${file.name}');
      }
    } catch (e) {
      print('❌ Supabase Connection or Bucket list failed: \$e');
      fail('Supabase bucket access failed: \$e');
    }
  });
}
