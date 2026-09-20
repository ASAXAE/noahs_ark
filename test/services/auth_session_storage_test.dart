import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/models/auth_tokens.dart';
import 'package:noahs_ark_app/services/auth_session_storage.dart';

void main() {
  late AuthSessionStorage sessionStorage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});

    sessionStorage = AuthSessionStorage(storage: const FlutterSecureStorage());
  });

  test('saves and restores a complete token bundle', () async {
    final original = AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      refreshTokenExpiresAt: DateTime.utc(2026, 10, 20, 10),
    );

    await sessionStorage.saveTokens(original);

    final restored = await sessionStorage.readTokens();

    expect(restored, isNotNull);
    expect(restored!.accessToken, original.accessToken);
    expect(restored.refreshToken, original.refreshToken);
    expect(restored.refreshTokenExpiresAt, original.refreshTokenExpiresAt);
  });

  test('reads a legacy access token during migration', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_access_token': 'legacy-access-token',
    });

    sessionStorage = AuthSessionStorage(storage: const FlutterSecureStorage());

    expect(await sessionStorage.readAccessToken(), 'legacy-access-token');

    expect(await sessionStorage.readTokens(), isNull);
  });

  test('deletes both current and legacy session data', () async {
    await sessionStorage.saveTokens(
      AuthTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        refreshTokenExpiresAt: DateTime.utc(2026, 10, 20, 10),
      ),
    );

    await sessionStorage.deleteAccessToken();

    expect(await sessionStorage.readTokens(), isNull);

    expect(await sessionStorage.readAccessToken(), isNull);
  });

  test('removes a malformed stored session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token_bundle': '{invalid-json',
    });

    sessionStorage = AuthSessionStorage(storage: const FlutterSecureStorage());

    expect(await sessionStorage.readTokens(), isNull);

    const rawStorage = FlutterSecureStorage();

    expect(await rawStorage.read(key: 'auth_token_bundle'), isNull);
  });
}
