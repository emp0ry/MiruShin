import 'package:flutter/material.dart';

class AppNavigationItem {
  const AppNavigationItem({
    required this.path,
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
}
