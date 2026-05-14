import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:xml/xml.dart';

class NextcloudException implements Exception {
  const NextcloudException(this.message);
  final String message;
  @override
  String toString() => 'NextcloudException: $message';
}

class RemoteBackupInfo {
  const RemoteBackupInfo({required this.remotePath, required this.backupDate});
  final String remotePath;
  final DateTime backupDate;
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

  // Build a Dio client. baseUrl uses only the server origin (scheme + host + port)
  // so that absolute DAV paths (/remote.php/dav/…) resolve correctly even when
  // serverUrl itself contains a sub-path.
  Dio _buildClient({
    required String serverUrl,
    required String username,
    required String password,
    String? pinnedFingerprint,
  }) {
    final origin = Uri.parse(serverUrl).origin;
    final dio = Dio(
      BaseOptions(
        baseUrl: origin,
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
  // Returns null when the certificate is trusted by the OS (no action needed).
  // Throws for pre-TLS failures (network error, DNS, timeout).
  Future<CertificateInfo?> fetchCertificateInfo(String serverUrl) async {
    CertificateInfo? info;
    final uri = Uri.parse(serverUrl);
    final client = HttpClient();
    try {
      client.badCertificateCallback = (cert, host, port) {
        info = CertificateInfo(
          fingerprint: _certFingerprint(cert.der),
          subject: cert.subject,
          issuer: cert.issuer,
          validUntil: cert.endValidity,
        );
        return false; // reject — we only wanted the info
      };
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      await req.close();
    } catch (e) {
      // If badCertificateCallback fired, info is set — this is the expected
      // TLS rejection path. Any other error is a real network failure.
      if (info == null) rethrow;
    } finally {
      client.close();
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
    // Dio throws DioException on 4xx/5xx, so we catch and translate to a
    // NextcloudException with a human-readable message.
    try {
      await client.request<String>(
        '/remote.php/dav/files/$username/',
        options: Options(method: 'PROPFIND', headers: {'Depth': '0'}),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw NextcloudException('Authentication failed (HTTP $code)');
      }
      rethrow;
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

    throw NextcloudException('Upload failed: HTTP ${response.statusCode}');
  }

  // List files at [remotePath] via PROPFIND (WebDAV).
  // [remotePath] is a logical path (e.g. '/StockManager/'); the DAV base
  // (/remote.php/dav/files/<username>) is prepended automatically.
  // Returns server-relative href strings as found in the XML response.
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

    final davBase = '/remote.php/dav/files/$username';
    final fullPath = remotePath.startsWith('/')
        ? '$davBase$remotePath'
        : '$davBase/$remotePath';

    final response = await client.request<String>(
      fullPath,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1'},
      ),
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      throw NextcloudException('PROPFIND failed: HTTP ${response.statusCode}');
    }

    final body = response.data ?? '';
    try {
      final doc = XmlDocument.parse(body);
      return doc
          .findAllElements('href', namespace: 'DAV:')
          .map((e) => e.innerText.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      // Fall back to regex if the server returns non-standard XML.
      return RegExp(r'<[^:]*:href>([^<]+)<')
          .allMatches(body)
          .map((m) => m.group(1)!.trim())
          .toList();
    }
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

  // Download [remotePath] and return its raw bytes.
  Future<Uint8List> downloadFile({
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
    final response = await client.get<List<int>>(
      remotePath,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw NextcloudException('Download failed: HTTP ${response.statusCode}');
    }
    return Uint8List.fromList(response.data ?? []);
  }

  // Find the most recent stockmanager_backup_*.zip in [remotePath].
  // [remotePath] is a logical path; the DAV base is handled by listFiles.
  // Returns null if the directory is empty or unreachable.
  Future<RemoteBackupInfo?> findLatestBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
  }) async {
    List<String> hrefs;
    try {
      hrefs = await listFiles(
        serverUrl: serverUrl,
        username: username,
        password: password,
        remotePath: remotePath,
      );
    } catch (_) {
      return null;
    }

    final pattern = RegExp(r'stockmanager_backup_(\d{4}-\d{2}-\d{2})\.zip$');
    DateTime? latestDate;
    String? latestHref;

    for (final href in hrefs) {
      final decoded = Uri.decodeFull(href);
      final match = pattern.firstMatch(decoded);
      if (match == null) continue;
      final date = DateTime.tryParse(match.group(1)!);
      if (date == null) continue;
      if (latestDate == null || date.isAfter(latestDate)) {
        latestDate = date;
        latestHref = href;
      }
    }

    if (latestDate == null || latestHref == null) return null;
    return RemoteBackupInfo(remotePath: latestHref, backupDate: latestDate);
  }

  static String _certFingerprint(Uint8List derBytes) {
    final digest = sha256.convert(derBytes);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }
}
