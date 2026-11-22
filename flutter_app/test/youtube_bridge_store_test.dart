import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:btmu/core/storage/secure_credentials_store.dart';

// Phase 4, item 21: the self-hosted YouTube bridge URL setting.
// The bridge URL lives in SharedPreferences like the X2 backend URL
// (it is a server address the user typed, not a secret). No device APIs.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('bridge URL defaults to empty (no bridge configured)', () async {
    final store = SecureCredentialsStore();
    expect(await store.getYoutubeBridgeUrl(), '');
  });

  test('bridge URL round-trips and trailing slashes are normalized', () async {
    final store = SecureCredentialsStore();
    await store.setYoutubeBridgeUrl('http://192.168.1.10:8000/');
    expect(await store.getYoutubeBridgeUrl(), 'http://192.168.1.10:8000');
  });

  test('clearing the bridge URL removes it', () async {
    final store = SecureCredentialsStore();
    await store.setYoutubeBridgeUrl('https://bridge.example.org');
    expect(await store.getYoutubeBridgeUrl(), 'https://bridge.example.org');
    await store.setYoutubeBridgeUrl('');
    expect(await store.getYoutubeBridgeUrl(), '');
    await store.setYoutubeBridgeUrl('   ');
    expect(await store.getYoutubeBridgeUrl(), '');
  });
}
