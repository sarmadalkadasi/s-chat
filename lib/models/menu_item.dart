import 'package:flutter/material.dart';

class MenuItem {
  const MenuItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
}