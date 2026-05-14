import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NextcloudException implements Exception {
  const NextcloudException(this.message);
  final String message;
  @override
  String toString() => 'NextcloudException: $message';
}

class CertificateInfo {
  const CertificateInfo({
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    required this.validUntil,
  });

  final String fingerprint;
  final String subject;
  final String issuer;
  final DateTime validUntil;
}

class NextcloudService {
  NextcloudService(this._secureStorage);

  final FlutterSecureStorage _secureStorage;

  static const _fingerprintKey = 'nextcloud_cert_fingerprint';

  Dio _buildClient({
    required String serverUrl,
    required String username,
    required String password,
    String? pinnedFingerprint,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: serverUrl,
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    if (pinnedFingerprint != null) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) {
          final fingerprint = _certFingerprint(cert.der);
          return fingerprint == pinnedFingerprint;
        };
        return client;
      };
    }

    return dio;
  }

  // First-connection: fetch the server certificate fingerprint for user approval.
  Future<CertificateInfo?> fetchCertificateInfo(String serverUrl) async {
    CertificateInfo? info;
    final uri = Uri.parse(serverUrl);

    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) {
        info = CertificateInfo(
          fingerprint: _certFingerprint(cert.der),
          subject: cert.subject,
          issuer: cert.issuer,
          validUntil: cert.endValidity,
        );
        return false; // reject — we only wanted the info
      };
      final conn = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      await conn.close();
      client.close();
    } catch (_) {
      // expected — certificate was rejected after inspection
    }

    return info;
  }

  // Persist a trusted fingerprint in secure storage.
  Future<void> pinCertificate(String fingerprint) =>
      _secureStorage.write(key: _fingerprintKey, value: fingerprint);

  Future<void> unpinCertificate() =>
      _secureStorage.delete(key: _fingerprintKey);

  Future<String?> getPinnedFingerprint() =>
      _secureStorage.read(key: _fingerprintKey);

  // Verify that [username]/[password] are accepted by the server.
  // Throws [NextcloudException] on auth failure or network error.
  Future<void> verifyCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final fingerprint = await getPinnedFingerprint();
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: fingerprint,
    );
    // PROPFIND to the user's DAV root — always present for valid credentials.
    final response = await client.request<String>(
      '/remote.php/dav/files/$username/',
      options: Options(method: 'PROPFIND', headers: {'Depth': '0'}),
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw NextcloudException(
          'Authentication failed: HTTP ${response.statusCode}');
    }
  }

  // Upload a ZIP backup to [remotePath], creating the parent directory if needed.
  Future<void> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    required Uint8List bytes,
  }) async {
    final fingerprint = await getPinnedFingerprint();
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: fingerprint,
    );

    final davBase = '/remote.php/dav/files/$username';
    final fullPath = remotePath.startsWith('/')
        ? '$davBase$remotePath'
        : '$davBase/$remotePath';

    // Ensure parent directory exists (MKCOL; 405 = already exists, ignore it).
    final slash = fullPath.lastIndexOf('/');
    if (slash > 0) {
      final dir = fullPath.substring(0, slash + 1);
      try {
        await client.request<void>(dir, options: Options(method: 'MKCOL'));
      } on DioException catch (e) {
        if (e.response?.statusCode != 405) rethrow;
      }
    }

    final response = await client.put(
      fullPath,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'Content-Type': 'application/zip',
          'Content-Length': bytes.length,
        },
      ),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw NextcloudException('Upload failed: HTTP ${response.statusCode}');
    }
  }

  // Upload [bytes] to [remotePath] via WebDAV PUT.
  Future<void> upload({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final fingerprint = await getPinnedFingerprint();
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: fingerprint,
    );

    final response = await client.put(
      remotePath,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length,
        },
      ),
    );

    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      return;
    }

    throw NextcloudException(
        'Upload failed: HTTP ${response.statusCode}');
  }

  // List files at [remotePath] via PROPFIND (WebDAV).
  Future<List<String>> listFiles({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final fingerprint = await getPinnedFingerprint();
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: fingerprint,
    );

    final response = await client.request<String>(
      remotePath,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1'},
      ),
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      throw NextcloudException('PROPFIND failed: HTTP ${response.statusCode}');
    }

    final body = response.data ?? '';
    // Extract <d:href> values — simple regex extraction avoids xml dependency here.
    final hrefs = RegExp(r'<[^:]*:href>([^<]+)<')
        .allMatches(body)
        .map((m) => m.group(1)!.trim())
        .toList();
    return hrefs;
  }

  // Delete [remotePath] via WebDAV DELETE.
  Future<void> delete({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    final fingerprint = await getPinnedFingerprint();
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: fingerprint,
    );
    await client.delete(remotePath);
  }

  static String _certFingerprint(Uint8List derBytes) {
    final digest = sha256.convert(derBytes);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }
}
