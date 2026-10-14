import 'package:flutter/material.dart';
import 'package:s_chat/widgets/show_user_image_viewer.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.time,
    required this.uname,
    required this.userImage,
    required this.showAvatar,
    this.showName,
  });

  final String message;
  final bool isMe;
  final String time;
  final String uname;
  final String userImage;
  final bool showAvatar;
  final bool? showName;

  @override
  Widget build(BuildContext context) {
    return Row(
      // Sent messages align right, received align left
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      // Aligns the avatar at the bottom-left edge of the text block (Telegram style)
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // --- RECEIVED MESSAGES AVATAR SIDE ---
        if (!isMe) ...[
          const SizedBox(width: 8), // Margin from screen edge
          if (showAvatar)
            Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(2.0), // Gap between ring and avatar
              decoration: BoxDecoration(
                shape: BoxShape
                    .circle, // Using circular ring wrapper for smooth aesthetics
                border: Border.all(
                  color: Colors
                      .greenAccent
                      .shade400, // Active green ring (set to transparent if offline)
                  width: 1.5,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(100),
                onTap: () =>
                  showUserImageViewer(
                    context,
                    imageUrl: userImage,
                    title: uname,
                  ),
                child: Hero(
                  tag: userImage.isNotEmpty ? 'bubble_avatar_$userImage' : UniqueKey().toString(),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      image: userImage.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(userImage),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: userImage.isEmpty
                        ? Center(
                            child: Text(
                              uname.isNotEmpty ? uname[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            )
          else
            // Critical placeholder box keeping messages perfectly aligned
            // Match the exact 38px width of your new custom ring setup
            const SizedBox(width: 28),

          const SizedBox(width: 8), // Space between avatar layout and bubble
        ],

        // --- MESSAGE CONTAINER BUBBLE ---
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.70,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18.0),
                topRight: const Radius.circular(18.0),
                bottomLeft: Radius.circular(isMe ? 18.0 : 4.0),
                bottomRight: Radius.circular(isMe ? 4.0 : 18.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(240),
                  blurRadius: 4.0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start, // Align internal text nicely
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only show user names on group entries if it's the start of a block
                if (!isMe && (showName ?? showAvatar)) ...[
                  Text(
                    uname,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  message,
                  softWrap: true,
                  style: TextStyle(
                    color: isMe
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSecondaryContainer,
                    fontSize: 15.0,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                // Align time cleanly to bottom right of bubble context
                Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: Text(
                    time,
                    style: TextStyle(
                      color: isMe
                          ? Theme.of(
                              context,
                            ).colorScheme.onPrimary.withAlpha(237)
                          : Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer.withAlpha(240),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Extra margin padding space for your own sent messages
        if (isMe) const SizedBox(width: 8),
      ],
    );
  }
}