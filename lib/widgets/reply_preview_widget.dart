import 'package:flutter/material.dart';

class ReplyPreviewWidget extends StatelessWidget {
  const ReplyPreviewWidget({
    super.key,
    required this.username,
    required this.text,
    this.onCancel,
    this.isMe = false,
    this.onTap,
  });

  final String username;
  final String text;
  final VoidCallback? onCancel;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBanner = onCancel != null;

    final primaryColor = isMe
        ? Colors.white
        : theme.colorScheme.primary;
    final backgroundColor = isBanner
        ? theme.colorScheme.primaryContainer
        : (isMe
            ? Colors.black.withAlpha(35)
            : theme.colorScheme.surfaceContainerHighest.withAlpha(180));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: EdgeInsets.only(
          bottom: isBanner ? 0.0 : 6.0,
          top: isBanner ? 0.0 : 2.0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 3.5,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      username.isNotEmpty ? username : 'Reply',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.0,
                        color: isMe
                            ? theme.colorScheme.onPrimary.withAlpha(220)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBanner)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
