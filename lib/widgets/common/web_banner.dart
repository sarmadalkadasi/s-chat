import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'web_banner_impl.dart';

/// Yellow "download the Android app" banner shown only on web.
/// Wrap your top-level screen with this widget.
class WebBannerScaffold extends StatefulWidget {
  const WebBannerScaffold({super.key, required this.child});

  final Widget child;

  @override
  State<WebBannerScaffold> createState() => _WebBannerScaffoldState();
}

class _WebBannerScaffoldState extends State<WebBannerScaffold> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissed) return widget.child;

    return Column(
      children: [
        _AndroidBanner(onDismiss: () => setState(() => _dismissed = true)),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _AndroidBanner extends StatelessWidget {
  const _AndroidBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final info = apkInfoForDevice();

    return Material(
      color: const Color(0xFFFFF176),
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 20, color: Color(0xFF5D4037)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This web version has limited features. '
                  'For the best experience, download the Android app.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF212121)),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF075E54),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: const StadiumBorder(),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => launchApkDownload(info.url),
                child: Text(info.label,
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: Color(0xFF757575)),
                tooltip: 'Dismiss',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
