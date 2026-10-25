import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:beecount/ai/providers/tokennest_auth_service.dart';
import 'package:beecount/ai/providers/ai_provider_config.dart';

void main() {
  late String? stored;
  late Uri authorization;
  late TokenNestAuthService auth;
  late int exchanges;
  late int refreshes;
  late DateTime now;
  late Future<http.Response> Function(http.Request) respond;
  Map<String, dynamic> tokens(String suffix) => {
        'access_token': 'access-$suffix',
        'refresh_token': 'refresh-$suffix',
        'token_type': 'Bearer',
        'expires_in': 120,
        'scope': 'api offline_access',
      };

  setUp(() {
    stored = null;
    exchanges = 0;
    refreshes = 0;
    now = DateTime(2026, 10, 25);
    respond = (request) async {
      expect(request.url.origin, TokenNestAuthService.issuer);
      expect(request.followRedirects, isFalse);
      final body = request.bodyFields;
      expect(body.containsKey('client_secret'), isFalse);
      if (request.url.path.endsWith('/revoke')) return http.Response('', 200);
      expect(body['client_id'], 'tnc_beecount');
      if (body['grant_type'] == 'refresh_token') {
        refreshes++;
        expect(body['refresh_token'], 'refresh-initial');
        return http.Response(jsonEncode(tokens('rotated')), 200);
      }
      exchanges++;
      expect(body['redirect_uri'], TokenNestAuthService.redirectUri);
      expect(TokenNestAuthService.challenge(body['code_verifier']!),
          authorization.queryParameters['code_challenge']);
      return http.Response(jsonEncode(tokens('initial')), 200);
    };
    auth = TokenNestAuthService(
        read: () async => stored,
        write: (value) async {
          stored = value;
        },
        now: () => now,
        launch: (uri) async {
          authorization = uri;
          return true;
        },
        client: MockClient((request) => respond(request)));
  });

  Future<void> callback({String? state, String? base}) =>
      auth.handleCallback(Uri.parse(base ?? TokenNestAuthService.redirectUri)
          .replace(queryParameters: {
        'code': 'test-code',
        'state': state ?? authorization.queryParameters['state']!,
      }));

  Future<void> login() async {
    final signing = auth.signIn();
    await callback();
    await signing;
  }

  test('RFC7636 S256 reference vector', () {
    expect(
        TokenNestAuthService.challenge(
            'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });

  test(
      'public client code exchange and reject wrong state/origin/path then consume once',
      () async {
    final signing = auth.signIn();
    expect(authorization.queryParameters['scope'], 'api offline_access');
    expect(authorization.queryParameters['code_challenge_method'], 'S256');
    await callback(state: 'forged-state');
    await callback(base: 'beecount.oauth://evil/callback');
    await callback(base: 'beecount.oauth://oauth/callback/extra');
    expect(exchanges, 0);
    await callback();
    await signing;
    await callback();
    expect(exchanges, 1);
    expect(await auth.accessToken(), 'access-initial');
  });

  test('denial validates state and does not exchange', () async {
    final signing = auth.signIn();
    final result = expectLater(signing, throwsA(isA<TokenNestAuthException>()));
    await auth.handleCallback(
        Uri.parse(TokenNestAuthService.redirectUri).replace(queryParameters: {
      'state': authorization.queryParameters['state']!,
      'error': 'access_denied',
    }));
    await result;
    expect(exchanges, 0);
    expect(stored, isNull);
  });

  test('cancel and expired flows cannot write credentials', () async {
    final signing = auth.signIn();
    final result = expectLater(signing, throwsA(isA<TokenNestAuthException>()));
    auth.cancelSignIn();
    await callback();
    await result;
    expect(stored, isNull);
    final expired = auth.signIn();
    final expiry = expectLater(expired, throwsA(isA<TokenNestAuthException>()));
    now = now.add(const Duration(minutes: 6));
    await callback();
    await expiry;
    expect(exchanges, 0);
  });

  test('simultaneous access refreshes exactly once and persists rotation',
      () async {
    await login();
    now = now.add(const Duration(minutes: 2));
    final results =
        await Future.wait(List.generate(8, (_) => auth.accessToken()));
    expect(results.toSet(), {'access-rotated'});
    expect(refreshes, 1);
    expect(jsonDecode(stored!)['refresh_token'], 'refresh-rotated');
    await auth.signOut();
    expect(stored, isNull);
    await expectLater(
        auth.accessToken(), throwsA(isA<TokenNestAuthException>()));
  });

  test('logout wins over in-flight refresh without credential resurrection',
      () async {
    await login();
    now = now.add(const Duration(minutes: 2));
    final response = Completer<http.Response>();
    final reached = Completer<void>();
    respond = (request) async {
      if (request.url.path.endsWith('/revoke')) return http.Response('', 200);
      reached.complete();
      return response.future;
    };
    final refreshing = auth.accessToken();
    final failed =
        expectLater(refreshing, throwsA(isA<TokenNestAuthException>()));
    await reached.future;
    final logout = auth.signOut();
    response.complete(http.Response(jsonEncode(tokens('rotated')), 200));
    await failed;
    await logout;
    expect(stored, isNull);
  });

  test('ambiguous refresh failure clears credentials and cannot replay',
      () async {
    await login();
    now = now.add(const Duration(minutes: 2));
    var requests = 0;
    respond = (_) async {
      requests++;
      throw http.ClientException('network');
    };
    await expectLater(
        auth.accessToken(), throwsA(isA<TokenNestAuthException>()));
    expect(stored, isNull);
    await expectLater(
        auth.accessToken(), throwsA(isA<TokenNestAuthException>()));
    expect(requests, 1);
  });

  test('provider serialization never exports an OAuth token', () {
    final config = AIServiceProviderConfig(
        id: 'tokennest_oauth',
        name: 'TokenNest',
        apiKey: 'must-not-export',
        createdAt: now);
    expect(config.toJson()['apiKey'], '');
    expect(
        AIServiceProviderConfig.fromJson(
            {...config.toJson(), 'apiKey': 'injected'}).apiKey,
        '');
  });
}
