import 'package:flutter/material.dart';
import 'package:btmu/app/theme/btt_theme.dart';

class BttLogoMark extends StatelessWidget {
  final double size;
  final bool rounded;

  const BttLogoMark({
    super.key,
    this.size = 40,
    this.rounded = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = Image.asset(
      'assets/images/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: BttColors.bgElevated,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          color: BttColors.accentViolet,
          size: size * 0.55,
        ),
      ),
    );
    if (!rounded) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: child,
    );
  }
}
