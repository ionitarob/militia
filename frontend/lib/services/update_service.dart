import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _manifestUrl =
    'https://imliti-scrapes-340303438174.s3.eu-west-3.amazonaws.com/app/latest.json';

class UpdateInfo {
  final String version;
  final String notes;
  final String downloadUrl;
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
  });
}

class UpdateService {
  /// Returns null when up to date, or [UpdateInfo] when a newer version exists.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final manifest = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = manifest['version'] as String;
      if (!_isNewer(latest, info.version)) return null;

      final platformKey = Platform.isWindows ? 'windows' : 'macos';
      final url = manifest[platformKey] as String?;
      if (url == null) return null;

      return UpdateInfo(
        version: latest,
        notes: manifest['notes'] as String? ?? '',
        downloadUrl: url,
      );
    } catch (_) {
      return null; // Network failure → proceed normally
    }
  }

  Future<void> downloadAndApply(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final tmp = await getTemporaryDirectory();
    final zipPath = p.join(tmp.path, 'imliti_update.zip');
    final extractDir = Directory(p.join(tmp.path, 'imliti_new'));

    if (extractDir.existsSync()) extractDir.deleteSync(recursive: true);
    extractDir.createSync(recursive: true);

    // ── Download (0 – 80 %) ───────────────────────────────────────────────────
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await client.send(request);
      final total = response.contentLength ?? 0;
      var received = 0;

      final sink = File(zipPath).openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total * 0.8);
      }
      await sink.close();
    } finally {
      client.close();
    }

    // ── Extract (80 – 95 %) ───────────────────────────────────────────────────
    onProgress?.call(0.82);
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = p.join(extractDir.path, entry.name);
      if (entry.isFile) {
        Directory(p.dirname(outPath)).createSync(recursive: true);
        await File(outPath).writeAsBytes(entry.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
    await File(zipPath).delete();
    onProgress?.call(0.95);

    // ── Launch updater and exit ───────────────────────────────────────────────
    final exePath = Platform.resolvedExecutable;
    final installDir = File(exePath).parent.path;

    if (Platform.isWindows) {
      await _applyWindows(extractDir.path, installDir, p.basename(exePath), tmp.path);
    } else if (Platform.isMacOS) {
      await _applyMacOS(extractDir.path, tmp.path);
    }
  }

  // ── Windows ──────────────────────────────────────────────────────────────────

  Future<void> _applyWindows(
    String extractDir,
    String installDir,
    String exeName,
    String tmpDir,
  ) async {
    final batchPath = p.join(tmpDir, 'imliti_update.bat');
    final vbsPath = p.join(tmpDir, 'imliti_update.vbs');
    final exeNoExt = p.basenameWithoutExtension(exeName);

    // Batch: waits for the app to exit, copies new files, relaunches.
    // Uses ping for cross-version sleep (no interactive console needed).
    File(batchPath).writeAsStringSync(
      '@echo off\r\n'
      'ping -n 5 127.0.0.1 >nul 2>&1\r\n'
      'taskkill /F /IM "$exeNoExt.exe" >nul 2>&1\r\n'
      'ping -n 3 127.0.0.1 >nul 2>&1\r\n'
      ':retry\r\n'
      'xcopy /E /H /R /Y "$extractDir\\*" "$installDir\\" >nul 2>&1\r\n'
      'if not errorlevel 1 goto launch\r\n'
      'ping -n 2 127.0.0.1 >nul 2>&1\r\n'
      'goto retry\r\n'
      ':launch\r\n'
      'start "" "$installDir\\$exeName"\r\n'
      'del "%~f0"\r\n',
    );

    // Flutter wraps its process in a Windows Job Object (KILL_ON_JOB_CLOSE),
    // so any child launched with CreateProcess is killed when the app exits.
    // wscript.exe's WScript.Shell.Run uses ShellExecute internally, which
    // creates the target process OUTSIDE the parent's Job Object — it survives.
    // Chr(34) = " — avoids VBScript quote-escaping issues with paths with spaces.
    File(vbsPath).writeAsStringSync(
      'Dim q\r\n'
      'q = Chr(34)\r\n'
      'CreateObject("WScript.Shell").Run "cmd /c " & q & "$batchPath" & q, 0, False\r\n',
    );

    await Process.start('wscript.exe', ['/nologo', vbsPath]);
    await Future.delayed(const Duration(milliseconds: 800));
    exit(0);
  }

  // ── macOS ─────────────────────────────────────────────────────────────────────

  Future<void> _applyMacOS(String extractDir, String tmpDir) async {
    // Platform.resolvedExecutable = /path/to/IMLiti.app/Contents/MacOS/imliti
    // Go 3 levels up to reach the .app bundle.
    final exe = File(Platform.resolvedExecutable);
    final appBundle = exe.parent.parent.parent.path; // e.g. /Applications/IMLiti.app
    final appName = p.basename(appBundle);            // IMLiti.app
    final appParent = p.dirname(appBundle);           // /Applications

    final scriptPath = p.join(tmpDir, 'imliti_update.sh');
    File(scriptPath).writeAsStringSync('''
#!/bin/bash
sleep 2
rm -rf "$appBundle"
cp -R "$extractDir/$appName" "$appParent/"
open "$appBundle"
rm -rf "$extractDir"
rm -- "\$0"
''');
    await Process.run('chmod', ['+x', scriptPath]);
    await Process.start('bash', [scriptPath], mode: ProcessStartMode.detached);
    exit(0);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  bool _isNewer(String a, String b) {
    List<int> parse(String v) =>
        v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final av = parse(a);
    final bv = parse(b);
    for (var i = 0; i < av.length && i < bv.length; i++) {
      if (av[i] > bv[i]) return true;
      if (av[i] < bv[i]) return false;
    }
    return av.length > bv.length;
  }
}
