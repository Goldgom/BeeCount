import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import 'sftp_auth_service.dart';
import 'sftp_storage_service.dart';

/// Cloud-sync provider backed by an SSH server's SFTP directory.
class SftpProvider implements CloudProvider {
  SftpAuthService? _authService;
  SftpStorageService? _storageService;

  @override
  String get providerId => 'sftp';

  @override
  String get providerName => 'SFTP';

  @override
  CloudAuthService get auth => _authService ??
      (throw CloudConfigurationException(
          'Provider not initialized. Call initialize() first.'));

  @override
  CloudStorageService get storage => _storageService ??
      (throw CloudConfigurationException(
          'Provider not initialized. Call initialize() first.'));

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    if (!validateConfig(config)) {
      throw CloudConfigurationException(
          'Invalid SFTP configuration. Required keys: host, username, password');
    }

    final host = (config['host'] as String).trim();
    final username = (config['username'] as String).trim();
    final password = config['password'] as String;
    final port = config['port'] as int? ?? 22;
    final remotePath = config['remotePath'] as String? ?? '/';

    _authService = SftpAuthService(username);
    _storageService = SftpStorageService(
      host: host,
      port: port,
      username: username,
      password: password,
      remotePath: remotePath,
    );
  }

  @override
  bool validateConfig(Map<String, dynamic> config) {
    final host = config['host'];
    final username = config['username'];
    final password = config['password'];
    final port = config['port'];
    return host is String && host.trim().isNotEmpty &&
        username is String && username.trim().isNotEmpty &&
        password is String && password.isNotEmpty &&
        (port == null || (port is int && port >= 1 && port <= 65535)) &&
        (config['remotePath'] == null || config['remotePath'] is String);
  }

  @override
  Future<void> dispose() async {
    _authService?.dispose();
    _authService = null;
    _storageService = null;
  }
}
