import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Public native client. No credentials ever enter provider JSON, backups or logs.
class TokenNestAuthService {
  static const issuer = 'https://openai.goldgom.top';
  static const apiBase = '$issuer/v1';
  static const clientId = String.fromEnvironment('TOKENNEST_CLIENT_ID',
      defaultValue: 'tnc_beecount');
  static const redirectUri = 'beecount.oauth://oauth/callback';
  static const providerId = 'tokennest_oauth';
  static const _storageKey = 'tokennest_oauth_v1';
  static final instance = TokenNestAuthService();

  final Future<String?> Function() _read;
  final Future<void> Function(String?) _write;
  final Future<bool> Function(Uri) _launch;
  final http.Client _http;
  final DateTime Function() _now;
  Future<void> _tail = Future.value();
  Future<String>? _refresh;
  _PendingLogin? _pending;
  int _generation = 0;

  TokenNestAuthService({
    Future<String?> Function()? read,
    Future<void> Function(String?)? write,
    Future<bool> Function(Uri)? launch,
    http.Client? client,
    DateTime Function()? now,
  })  : _read = read ?? (() => _storage.read(key: _storageKey)),
        _write = write ??
            ((value) => value == null
                ? _storage.delete(key: _storageKey)
                : _storage.write(key: _storageKey, value: value)),
        _launch = launch ??
            ((url) => launchUrl(url, mode: LaunchMode.externalApplication)),
        _http = client ?? http.Client(),
        _now = now ?? DateTime.now;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> get isSignedIn async => (await _read()) != null;

  static bool isOAuthCallback(Uri uri) => uri.scheme == 'beecount.oauth';

  static String _random() => base64UrlEncode(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');

  static String challenge(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  static bool _sameState(String left, String right) {
    var difference = left.length ^ right.length;
    for (var i = 0; i < left.length; i++) {
      difference |=
          left.codeUnitAt(i) ^ (i < right.length ? right.codeUnitAt(i) : 0);
    }
    return difference == 0;
  }

  Future<void> signIn() async {
    cancelSignIn();
    final pending = _PendingLogin(
        _random(), _random(), _now().add(const Duration(minutes: 5)));
    _pending = pending;
    final generation = ++_generation;
    // Attach the error handler before browser launch (cancel can happen during launch).
    final completion = pending.result.future;
    final observed = completion.then((_) => true, onError: (Object _) => false);
    pending.timer =
        Timer(const Duration(minutes: 5), () => cancelSignIn('登录已过期，请重试'));
    try {
      final url =
          Uri.parse('$issuer/oauth/authorize').replace(queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': 'api offline_access',
        'state': pending.state,
        'code_challenge': challenge(pending.verifier),
        'code_challenge_method': 'S256',
      });
      if (!await _launch(url)) throw const TokenNestAuthException('无法打开系统浏览器');
      await observed;
      await completion;
      if (generation != _generation) {
        throw const TokenNestAuthException('登录已取消');
      }
    } catch (error) {
      if (identical(_pending, pending)) cancelSignIn();
      if (error is TokenNestAuthException) rethrow;
      throw const TokenNestAuthException('TokenNest 登录失败，请重试');
    } finally {
      pending.timer?.cancel();
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void cancelSignIn([String message = '登录已取消']) {
    _generation++;
    final pending = _pending;
    _pending = null;
    pending?.timer?.cancel();
    if (pending != null && !pending.result.isCompleted) {
      pending.result.completeError(TokenNestAuthException(message));
    }
  }

  /// Main's deep-link dispatcher must call this BEFORE any URL logging.
  Future<void> handleCallback(Uri uri) async {
    final pending = _pending;
    if (pending == null || pending.claimed) return;
    final expected = Uri.parse(redirectUri);
    if (uri.scheme != expected.scheme ||
        uri.authority != expected.authority ||
        uri.path != expected.path ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.queryParametersAll['state']?.length != 1 ||
        !_sameState(pending.state, uri.queryParameters['state'] ?? '')) {
      return;
    }
    if (!_now().isBefore(pending.expires)) {
      cancelSignIn('登录已过期，请重试');
      return;
    }
    pending.claimed = true; // consume once, including denial
    final generation = _generation;
    try {
      if (uri.queryParameters.containsKey('error')) {
        throw const TokenNestAuthException('TokenNest 授权已拒绝');
      }
      final code = uri.queryParameters['code'];
      if (code == null ||
          code.isEmpty ||
          uri.queryParametersAll['code']?.length != 1) {
        throw const TokenNestAuthException('授权回调无效');
      }
      final tokens = await _requestTokens({
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code': code,
        'code_verifier': pending.verifier,
      });
      await _serial(() async {
        if (generation != _generation) {
          throw const TokenNestAuthException('登录已取消');
        }
        await _write(jsonEncode(tokens));
        if (generation != _generation) {
          await _write(null);
          throw const TokenNestAuthException('登录已取消');
        }
      });
      if (!pending.result.isCompleted) pending.result.complete();
    } catch (error) {
      if (!pending.result.isCompleted) {
        pending.result.completeError(error is TokenNestAuthException
            ? error
            : const TokenNestAuthException('TokenNest 登录失败，请重试'));
      }
    }
  }

  Future<Map<String, dynamic>> _requestTokens(
      Map<String, String> fields) async {
    http.Response response;
    try {
      final request =
          http.Request('POST', Uri.parse('$issuer/api/oauth2/token'))
            ..followRedirects = false
            ..headers['Accept'] = 'application/json'
            ..bodyFields = fields;
      response = await http.Response.fromStream(
              await _http.send(request).timeout(const Duration(seconds: 20)))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Never retry a refresh: a lost response may already have rotated the token.
      throw const TokenNestAuthException('授权请求中断，请重新登录');
    }
    if (response.statusCode != 200) {
      throw TokenNestAuthException(
          'TokenNest 授权失败（HTTP ${response.statusCode}），请重新登录');
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['token_type'] != 'Bearer' ||
          json['access_token'] is! String ||
          (json['access_token'] as String).isEmpty ||
          json['expires_in'] is! num ||
          (json['expires_in'] as num) <= 0 ||
          json['refresh_token'] is! String ||
          (json['refresh_token'] as String).isEmpty ||
          !(json['scope'] as String).split(' ').contains('api')) {
        throw const FormatException();
      }
      return {
        'access_token': json['access_token'],
        'refresh_token': json['refresh_token'],
        'expires_at': _now().millisecondsSinceEpoch +
            (json['expires_in'] as num).toInt() * 1000
      };
    } catch (_) {
      throw const TokenNestAuthException('TokenNest 授权响应无效，请重新登录');
    }
  }

  Future<String> accessToken() {
    final existing = _refresh;
    if (existing != null) return existing;
    final generation = _generation;
    final future = _serial(() async {
      if (generation != _generation) {
        throw const TokenNestAuthException('登录状态已改变');
      }
      final raw = await _read();
      if (raw == null) throw const TokenNestAuthException('请先登录 TokenNest');
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (generation != _generation) {
        throw const TokenNestAuthException('登录状态已改变');
      }
      if ((saved['expires_at'] as int) >
          _now().millisecondsSinceEpoch + 60000) {
        return saved['access_token'] as String;
      }
      Map<String, dynamic> tokens;
      try {
        tokens = await _requestTokens({
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': saved['refresh_token'] as String
        });
      } catch (_) {
        // Ambiguous network failures must not reuse an already consumed refresh token.
        await _write(null);
        rethrow;
      }
      if (generation != _generation) {
        throw const TokenNestAuthException('登录状态已改变');
      }
      try {
        await _write(jsonEncode(tokens)); // one atomic secure-storage record
      } catch (_) {
        await _write(null);
        throw const TokenNestAuthException('安全保存授权失败，请重新登录');
      }
      if (generation != _generation) {
        await _write(null);
        throw const TokenNestAuthException('登录状态已改变');
      }
      return tokens['access_token'] as String;
    });
    _refresh = future;
    future.then<void>((_) {
      if (identical(_refresh, future)) _refresh = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_refresh, future)) _refresh = null;
    });
    return future;
  }

  /// Always remove local credentials, even if revocation is unavailable.
  Future<void> signOut() async {
    cancelSignIn();
    await _serial(() async {
      final raw = await _read();
      await _write(null);
      if (raw == null) return;
      try {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        final request =
            http.Request('POST', Uri.parse('$issuer/api/oauth2/revoke'))
              ..followRedirects = false
              ..bodyFields = {'token': saved['refresh_token'] as String};
        final response = await http.Response.fromStream(
                await _http.send(request).timeout(const Duration(seconds: 20)))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) throw const FormatException();
      } catch (_) {
        throw const TokenNestAuthException(
            '已清除本机登录；远端撤销失败，请在 TokenNest 授权管理中撤销 BeeCount');
      }
    });
  }

  Future<List<String>> models() async {
    try {
      final request = http.Request('GET', Uri.parse('$apiBase/models'))
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer ${await accessToken()}';
      final response = await http.Response.fromStream(
              await _http.send(request).timeout(const Duration(seconds: 20)))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw const FormatException();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['data'] as List)
          .map((e) => (e as Map)['id'] as String)
          .toSet()
          .toList()
        ..sort();
    } on TokenNestAuthException {
      rethrow;
    } catch (_) {
      throw const TokenNestAuthException('无法加载模型，请检查网络或重新登录');
    }
  }
}

class _PendingLogin {
  final String state;
  final String verifier;
  final DateTime expires;
  final result = Completer<void>();
  Timer? timer;
  bool claimed = false;
  _PendingLogin(this.state, this.verifier, this.expires);
}

class TokenNestAuthException implements Exception {
  final String message;
  const TokenNestAuthException(this.message);
  @override
  String toString() => message;
}
