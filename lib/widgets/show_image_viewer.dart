import 'package:flutter/material.dart';
import 'package:s_chat/widgets/cached_media_image.dart';

void showImageViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withAlpha(210),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar with username and close button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Profile image card with Hero animation
            Hero(
              tag: imageUrl.isNotEmpty
                  ? 'bubble_avatar_$imageUrl'
                  : UniqueKey().toString(),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
                child: Container(
                  width: 340,
                  height: 340,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: imageUrl.isNotEmpty
                      ? CachedMediaImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: Center(
                            child: Text(
                              title.isNotEmpty ? title[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            title.isNotEmpty ? title[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
