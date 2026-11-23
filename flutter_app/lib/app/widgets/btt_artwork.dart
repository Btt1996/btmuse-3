import 'dart:io';
import 'package:flutter/material.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_logo_mark.dart';

class BttArtwork extends StatelessWidget {
  final String? artworkPath;
  final String? artworkUrl;
  final double size;
  final double radius;

  const BttArtwork({
    super.key,
    this.artworkPath,
    this.artworkUrl,
    this.size = 52,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (artworkPath != null && artworkPath!.isNotEmpty && File(artworkPath!).existsSync()) {
      inner = Image.file(
        File(artworkPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    } else if (artworkUrl != null && artworkUrl!.startsWith('http')) {
      inner = Image.network(
        artworkUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      inner = _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: BttColors.bgElevated,
        child: inner,
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141D2E), Color(0xFF090E16)],
        ),
      ),
      alignment: Alignment.center,
      child: BttLogoMark(size: size * 0.65, rounded: false),
    );
  }
}
