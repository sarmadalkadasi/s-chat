import 'package:flutter/material.dart';
import 'package:s_chat/models/menu_item.dart';

class ContextMenu extends StatefulWidget {
  final Widget child;
  final List<MenuItem> items;
  final bool showOnTap;

  const ContextMenu({
    super.key,
    required this.child,
    required this.items,
    this.showOnTap = true,
  });

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  Offset _tapPosition = Offset.zero;

  void _storePosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  void _showMenu(BuildContext context) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(_tapPosition.dx, _tapPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    final String? selectedValue = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 8,
      items: widget.items.map((item) {
        return PopupMenuItem<String>(
          value: item.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 20,
                color: item.isDestructive ? Colors.red : Colors.black87,
              ),
              const SizedBox(width: 12),
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 16,
                  color: item.isDestructive ? Colors.red : Colors.black87,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );

    if (selectedValue != null) {
      final selectedItem =
          widget.items.firstWhere((item) => item.id == selectedValue);
      selectedItem.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _storePosition,
      onTap: widget.showOnTap ? () => _showMenu(context) : null,
      onLongPress: widget.showOnTap ? null : () => _showMenu(context),
      child: widget.child,
    );
  }
}
