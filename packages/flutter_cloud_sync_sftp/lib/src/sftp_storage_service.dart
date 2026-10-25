import 'dart:convert';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

/// SFTP implementation of the common cloud storage interface.
///
/// Each operation uses a short-lived SSH/SFTP session. This avoids keeping a
/// mobile connection alive while the app is backgrounded.
class SftpStorageService implements CloudStorageService {
  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;

  SftpStorageService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.remotePath,
  });

  Future<T> _withSftp<T>(Future<T> Function(SftpClient sftp) action) async {
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    SftpClient? sftp;
    try {
      sftp = await client.sftp();
      return await action(sftp);
    } finally {
      await sftp?.close();
      client.close();
      await client.done;
    }
  }

  @override
  Future<void> upload({
    required String path,
    required String data,
    Map<String, String>? metadata,
  }) => _run('Upload', (sftp) async {
        final fullPath = _filePath(path);
        await _ensureDirectory(sftp, _dirname(fullPath));
        final file = await sftp.open(
          fullPath,
          mode: SftpFileOpenMode.create |
              SftpFileOpenMode.write |
              SftpFileOpenMode.truncate,
        );
        try {
          await file.writeBytes(Uint8List.fromList(utf8.encode(data)));
        } finally {
          await file.close();
        }
      });

  @override
  Future<String?> download({required String path}) async {
    try {
      return await _withSftp((sftp) async {
        final file = await sftp.open(_filePath(path));
        try {
          return utf8.decode(await file.readBytes());
        } finally {
          await file.close();
        }
      });
    } catch (e) {
      if (_isMissing(e)) return null;
      throw CloudStorageException('Download failed: $e', e);
    }
  }

  @override
  Future<void> delete({required String path}) => _run('Delete', (sftp) async {
        try {
          await sftp.remove(_filePath(path));
        } catch (e) {
          if (!_isMissing(e)) rethrow;
        }
      });

  @override
  Future<List<CloudFile>> list({required String path}) =>
      _run('List', (sftp) async {
        final directory = _directoryPath(path);
        await _ensureDirectory(sftp, directory);
        final files = await sftp.listdir(directory);
        return files
            .where((file) => file.filename != '.' &&
                file.filename != '..' &&
                !file.attr.isDirectory &&
                !file.filename.endsWith('.metadata.json'))
            .map((file) => CloudFile(
                  name: file.filename,
                  path: _join(directory, file.filename),
                  size: file.attr.size,
                  lastModified: _dateFromSeconds(file.attr.modifyTime),
                  metadata: const {},
                ))
            .toList();
      });

  @override
  Future<bool> exists({required String path}) async {
    try {
      await _withSftp((sftp) => sftp.stat(_filePath(path)));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CloudFile?> getMetadata({required String path}) async {
    try {
      return await _withSftp((sftp) async {
        final fullPath = _filePath(path);
        final attrs = await sftp.stat(fullPath);
        return CloudFile(
          name: _basename(fullPath),
          path: fullPath,
          size: attrs.size,
          lastModified: _dateFromSeconds(attrs.modifyTime),
          metadata: const {},
        );
      });
    } catch (e) {
      if (_isMissing(e)) return null;
      throw CloudStorageException('Get metadata failed: $e', e);
    }
  }

  Future<void> _ensureDirectory(SftpClient sftp, String directory) async {
    final normalized = _normalize(directory);
    if (normalized == '.' || normalized == '/') return;

    var current = normalized.startsWith('/') ? '/' : '';
    for (final part in normalized.split('/').where((part) => part.isNotEmpty)) {
      current = current == '/' ? '/$part' : (current.isEmpty ? part : '$current/$part');
      try {
        final attrs = await sftp.stat(current);
        if (!attrs.isDirectory) {
          throw CloudStorageException('SFTP path is not a directory: $current');
        }
      } catch (e) {
        if (_isMissing(e)) {
          await sftp.mkdir(current);
        } else {
          rethrow;
        }
      }
    }
  }

  Future<T> _run<T>(String operation, Future<T> Function(SftpClient) action) async {
    try {
      return await _withSftp(action);
    } catch (e) {
      throw CloudStorageException('$operation failed: $e', e);
    }
  }

  String _filePath(String path) {
    final relative = path.replaceAll('\\', '/');
    if (relative.startsWith('/') || relative.split('/').contains('..')) {
      throw ArgumentError('Cloud path must be relative to the SFTP root');
    }
    return _join(_normalize(remotePath), relative);
  }

  String _directoryPath(String path) {
    if (path.isEmpty) return _normalize(remotePath);
    return _filePath(path);
  }

  String _normalize(String value) {
    final cleaned = value.trim().replaceAll('\\', '/');
    if (cleaned.isEmpty || cleaned == '.') return '.';
    if (cleaned.split('/').contains('..')) {
      throw ArgumentError('SFTP paths must not contain ..');
    }
    final absolute = cleaned.startsWith('/');
    final parts = cleaned.split('/').where((part) => part.isNotEmpty && part != '.');
    final result = parts.join('/');
    if (result.isEmpty) return absolute ? '/' : '.';
    return absolute ? '/$result' : result;
  }

  String _join(String base, String child) {
    if (child.isEmpty) return base;
    if (base == '.' || base.isEmpty) return child;
    if (base == '/') return '/$child';
    return '$base/$child';
  }

  String _dirname(String value) {
    final index = value.lastIndexOf('/');
    if (index < 0) return '.';
    if (index == 0) return '/';
    return value.substring(0, index);
  }

  String _basename(String value) => value.substring(value.lastIndexOf('/') + 1);

  DateTime? _dateFromSeconds(int? seconds) => seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

  bool _isMissing(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('no such file') ||
        message.contains('not found') ||
        message.contains('no such path') ||
        message.contains('ssh_fx_noent');
  }
}
