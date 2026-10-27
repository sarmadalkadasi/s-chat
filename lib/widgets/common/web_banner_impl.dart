// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ApkInfo {
  final String url;
  final String label;
  const ApkInfo(this.url, this.label);
}

/// Detects Android version from the browser user-agent and returns the
/// appropriate APK URL and button label.
ApkInfo apkInfoForDevice() {
  final ua = html.window.navigator.userAgent;
  final isAndroid = RegExp(r'Android', caseSensitive: false).hasMatch(ua);

  if (isAndroid) {
    final match = RegExp(r'Android\s([\d.]+)').firstMatch(ua);
    final version = match != null ? double.tryParse(match.group(1)!) ?? 0 : 0;
    if (version >= 8) {
      return const ApkInfo('apks/s_chat-8.apk', '⬇ Download (Android 8+)');
    } else {
      return const ApkInfo('apks/s_chat-7.apk', '⬇ Download (Android 7)');
    }
  }

  // Non-Android browser: default to modern APK
  return const ApkInfo('apks/s_chat-8.apk', '⬇ Download Android App');
}

/// Triggers a file download in the browser.
void launchApkDownload(String url) {
  html.AnchorElement(href: url)
    ..setAttribute('download', '')
    ..click();
}
