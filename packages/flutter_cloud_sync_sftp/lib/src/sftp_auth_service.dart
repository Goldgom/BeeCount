import 'dart:async';

import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

/// SFTP has no application-level account API. The configured SSH user is
/// represented as a virtual cloud-sync user.
class SftpAuthService implements CloudAuthService {
  final String username;
  late final StreamController<CloudUser?> _controller;
  CloudUser? _currentUser;

  SftpAuthService(this.username) {
    _currentUser = CloudUser(id: username, email: '$username@sftp');
    _controller = StreamController<CloudUser?>.broadcast(
      onListen: () {
        final user = _currentUser;
        if (user != null) _controller.add(user);
      },
    );
  }

  @override
  Stream<CloudUser?> get authStateChanges => _controller.stream;

  @override
  Future<CloudUser?> get currentUser async => _currentUser;

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<CloudUser> signInWithEmail({
    required String email,
    required String password,
  }) => throw UnsupportedError('SFTP does not support email sign in');

  @override
  Future<CloudUser> signUpWithEmail({
    required String email,
    required String password,
  }) => throw UnsupportedError('SFTP does not support sign up');

  @override
  Future<void> sendPasswordResetEmail({required String email}) =>
      throw UnsupportedError('SFTP does not support password reset');

  @override
  Future<void> resendEmailVerification({required String email}) =>
      throw UnsupportedError('SFTP does not support email verification');

  void dispose() => _controller.close();
}
