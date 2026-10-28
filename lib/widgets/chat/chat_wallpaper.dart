import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Renders a WhatsApp/Telegram-style doodle pattern wallpaper for chat screens.
class ChatWallpaperWidget extends StatelessWidget {
  const ChatWallpaperWidget({
    super.key,
    required this.child,
    this.wallpaperAsset,
  });

  final Widget child;
  final String? wallpaperAsset;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0B141A) : const Color(0xFFE5DDD5);

    return Container(
      color: bgColor,
      child: Stack(
        children: [
          // Background doodle pattern
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.08 : 0.06,
              child: wallpaperAsset != null && wallpaperAsset!.isNotEmpty
                  ? Image.asset(
                      wallpaperAsset!,
                      repeat: ImageRepeat.repeat,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const CustomPaint(
                        painter: _DoodleWallpaperPainter(),
                      ),
                    )
                  : const CustomPaint(
                      painter: _DoodleWallpaperPainter(),
                    ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DoodleWallpaperPainter extends CustomPainter {
  const _DoodleWallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const double step = 60.0;
    for (double x = 10; x < size.width; x += step) {
      for (double y = 10; y < size.height; y += step) {
        final randomVal = (x * 31 + y * 17) % 5;
        canvas.save();
        canvas.translate(x, y);

        if (randomVal == 0) {
          // Speech bubble icon
          final rect = RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 18, 14),
            const Radius.circular(4),
          );
          canvas.drawRRect(rect, paint);
          final path = Path()
            ..moveTo(3, 14)
            ..lineTo(0, 18)
            ..lineTo(7, 14);
          canvas.drawPath(path, paint);
        } else if (randomVal == 1) {
          // Lock / Security icon
          final body = RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 6, 12, 10),
            const Radius.circular(2),
          );
          canvas.drawRRect(body, paint);
          canvas.drawArc(
            const Rect.fromLTWH(4, 1, 8, 10),
            math.pi,
            math.pi,
            false,
            paint,
          );
        } else if (randomVal == 2) {
          // Star / Sparkle icon
          canvas.drawLine(const Offset(8, 0), const Offset(8, 16), paint);
          canvas.drawLine(const Offset(0, 8), const Offset(16, 8), paint);
        } else if (randomVal == 3) {
          // Heart icon
          final path = Path()
            ..moveTo(8, 14)
            ..cubicTo(2, 8, 0, 4, 4, 1)
            ..cubicTo(7, -1, 8, 3, 8, 3)
            ..cubicTo(8, 3, 9, -1, 12, 1)
            ..cubicTo(16, 4, 14, 8, 8, 14);
          canvas.drawPath(path, paint);
        } else {
          // Smile / Circle
          canvas.drawCircle(const Offset(8, 8), 7, paint);
        }

        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
