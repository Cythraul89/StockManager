import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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

// Stateless WebDAV client. Callers are responsible for supplying and persisting
// the pinnedFingerprint (stored in the settings table, not the Keychain).
class NextcloudService {
  const NextcloudService();

  // Resolves a caller-supplied path to a full DAV request path. Paths already
  // carrying the /remote.php/ prefix (e.g. hrefs returned by PROPFIND) pass
  // through unchanged; bare paths are prefixed with the user's DAV root. The
  // username is percent-encoded — Nextcloud allows '@' and spaces in it.
  static String _davPath(String username, String remotePath) {
    if (remotePath.startsWith('/remote.php/')) return remotePath;
    final davBase = '/remote.php/dav/files/${Uri.encodeComponent(username)}';
    return remotePath.startsWith('/')
        ? '$davBase$remotePath'
        : '$davBase/$remotePath';
  }

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
        return false;
      };
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      await req.close();
    } catch (e) {
      if (info == null) rethrow;
    } finally {
      client.close();
    }
    return info;
  }

  Future<void> verifyCredentials({
    required String serverUrl,
    required String username,
    required String password,
    String? pinnedFingerprint,
  }) async {
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: pinnedFingerprint,
    );
    try {
      await client.request<String>(
        _davPath(username, '/'),
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

  Future<void> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    required Uint8List bytes,
    String? pinnedFingerprint,
  }) async {
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: pinnedFingerprint,
    );

    final fullPath = _davPath(username, remotePath);

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

  Future<void> upload({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    required Uint8List bytes,
    required String contentType,
    String? pinnedFingerprint,
  }) async {
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: pinnedFingerprint,
    );

    final response = await client.put(
      _davPath(username, remotePath),
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

  Future<List<String>> listFiles({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    String? pinnedFingerprint,
  }) async {
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: pinnedFingerprint,
    );

    final response = await client.request<String>(
      _davPath(username, remotePath),
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
      return RegExp(r'<[^:]*:href>([^<]+)<')
          .allMatches(body)
          .map((m) => m.group(1)!.trim())
          .toList();
    }
  }

  Future<void> delete({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    String? pinnedFingerprint,
  }) async {
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: pinnedFingerprint,
    );
    await client.delete(_davPath(username, remotePath));
  }

  Future<Uint8List> downloadFile({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    String? pinnedFingerprint,
  }) async {
    final client = _buildClient(
      serverUrl: serverUrl,
      username: username,
      password: password,
      pinnedFingerprint: pinnedFingerprint,
    );
    final response = await client.get<List<int>>(
      _davPath(username, remotePath),
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw NextcloudException('Download failed: HTTP ${response.statusCode}');
    }
    return Uint8List.fromList(response.data ?? []);
  }

  Future<RemoteBackupInfo?> findLatestBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    String? pinnedFingerprint,
  }) async {
    List<String> hrefs;
    try {
      hrefs = await listFiles(
        serverUrl: serverUrl,
        username: username,
        password: password,
        remotePath: remotePath,
        pinnedFingerprint: pinnedFingerprint,
      );
    } catch (_) {
      return null;
    }

    // Matches legacy date-only (YYYY-MM-DD) and current datetime (YYYY-MM-DDTHH-MM-SSZ) formats.
    final pattern = RegExp(r'stockmanager_backup_(\d{4}-\d{2}-\d{2}(?:T\d{2}-\d{2}-\d{2}Z)?)\.zip$');
    DateTime? latestDate;
    String? latestHref;

    for (final href in hrefs) {
      final decoded = Uri.decodeFull(href);
      final match = pattern.firstMatch(decoded);
      if (match == null) continue;
      final date = _parseBackupTimestamp(match.group(1)!);
      if (date == null) continue;
      if (latestDate == null || date.isAfter(latestDate)) {
        latestDate = date;
        latestHref = href;
      }
    }

    if (latestDate == null || latestHref == null) return null;
    return RemoteBackupInfo(remotePath: latestHref, backupDate: latestDate);
  }

  static DateTime? _parseBackupTimestamp(String s) {
    if (s.contains('T')) {
      final normalized = s.replaceAllMapped(
        RegExp(r'T(\d{2})-(\d{2})-(\d{2})Z'),
        (m) => 'T${m[1]}:${m[2]}:${m[3]}Z',
      );
      return DateTime.tryParse(normalized);
    }
    return DateTime.tryParse(s);
  }

  static String _certFingerprint(Uint8List derBytes) {
    final digest = sha256.convert(derBytes);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }
}
