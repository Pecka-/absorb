import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';

class LogService {
  static final LogService _instance = LogService._();
  factory LogService() => _instance;
  LogService._();

  static const supportEmail = 'barnabas.absorb@gmail.com';

  File? _logFile;
  bool _enabled = false;
  DebugPrintCallback? _originalDebugPrint;

  bool get enabled => _enabled;

  /// Call once at startup. If [loggingEnabled] is true, sets up the log file
  /// and overrides [debugPrint] to capture all output.
  Future<void> init(bool loggingEnabled) async {
    _enabled = loggingEnabled;
    if (!_enabled) return;

    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/absorb_logs.txt');

    // Rotate: if file > 1MB, keep the last 512KB
    if (await _logFile!.exists()) {
      final size = await _logFile!.length();
      if (size > 1024 * 1024) {
        final contents = await _logFile!.readAsString();
        await _logFile!.writeAsString(
          contents.substring(contents.length - (512 * 1024)),
        );
      }
    }

    // Session header
    final now = DateTime.now().toIso8601String();
    await _logFile!.writeAsString(
      '\n=== Session started $now ===\n',
      mode: FileMode.append,
    );

    // Override debugPrint globally
    _originalDebugPrint = debugPrint;
    debugPrint = _interceptedDebugPrint;
  }

  void _interceptedDebugPrint(String? message, {int? wrapWidth}) {
    _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    if (_logFile != null && message != null) {
      final ts = DateTime.now().toIso8601String();
      _logFile!.writeAsStringSync(
        '[$ts] $message\n',
        mode: FileMode.append,
      );
    }
  }

  /// Write a log entry directly (for error handlers that bypass debugPrint).
  void log(String message) {
    if (_logFile != null) {
      final ts = DateTime.now().toIso8601String();
      _logFile!.writeAsStringSync(
        '[$ts] $message\n',
        mode: FileMode.append,
      );
    }
  }

  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }

  /// Build device info string used by both email methods.
  String _deviceInfo({String? serverVersion}) {
    final buf = StringBuffer()
      ..writeln('App Version: ${ApiService.appVersion}')
      ..writeln('Device: ${ApiService.deviceManufacturer} ${ApiService.deviceModel}')
      ..writeln('Device ID: ${ApiService.deviceId}');
    if (serverVersion != null) {
      buf.writeln('Server Version: $serverVersion');
    }
    buf.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    return buf.toString();
  }

  /// Share log file as attachment via share sheet with device info.
  Future<void> shareLogs({String? serverVersion}) async {
    final info = _deviceInfo(serverVersion: serverVersion);

    final hasFile =
        _logFile != null && await _logFile!.exists() && await _logFile!.length() > 0;

    if (hasFile) {
      await Share.shareXFiles(
        [XFile(_logFile!.path)],
        subject: 'Absorb Log Report',
        text: 'Send to: $supportEmail\n\n$info',
      );
    } else {
      await Share.share(
        'Send to: $supportEmail\n\n$info\n(No log file found — is logging enabled?)',
        subject: 'Absorb Log Report',
      );
    }
  }

  /// Open a mailto: link with device info (no logs) for general contact.
  Future<void> contactEmail({String? serverVersion}) async {
    final info = _deviceInfo(serverVersion: serverVersion);
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: _encodeMailtoQuery({
        'subject': 'Absorb Feedback',
        'body': info,
      }),
    );
    await launchUrl(uri);
  }

  String _encodeMailtoQuery(Map<String, String> params) {
    return params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
