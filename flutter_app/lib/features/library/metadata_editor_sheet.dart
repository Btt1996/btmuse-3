import 'package:flutter/material.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/data/models/track.dart';

class MetadataEditorSheet extends StatefulWidget {
  final Track track;
  final Future<void> Function(Track updated) onSave;

  const MetadataEditorSheet({
    super.key,
    required this.track,
    required this.onSave,
  });

  @override
  State<MetadataEditorSheet> createState() => _MetadataEditorSheetState();
}

class _MetadataEditorSheetState extends State<MetadataEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;
  late final TextEditingController _genreCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.track.title);
    _artistCtrl = TextEditingController(text: widget.track.artist);
    _albumCtrl = TextEditingController(text: widget.track.album);
    _genreCtrl = TextEditingController(text: widget.track.genre ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit Track Metadata', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artistCtrl,
            decoration: const InputDecoration(labelText: 'Artist'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _albumCtrl,
            decoration: const InputDecoration(labelText: 'Album'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _genreCtrl,
            decoration: const InputDecoration(labelText: 'Genre (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final updated = widget.track.copyWith(
                      title: _titleCtrl.text.trim().isEmpty
                          ? widget.track.title
                          : _titleCtrl.text.trim(),
                      artist: _artistCtrl.text.trim().isEmpty
                          ? widget.track.artist
                          : _artistCtrl.text.trim(),
                      album: _albumCtrl.text.trim().isEmpty
                          ? 'Single'
                          : _albumCtrl.text.trim(),
                      genre: _genreCtrl.text.trim().isEmpty ? null : _genreCtrl.text.trim(),
                    );
                    await widget.onSave(updated);
                    if (context.mounted) Navigator.of(context).pop();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: BttColors.cyanAccent,
              foregroundColor: BttColors.bgObsidian,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_saving ? 'Saving...' : 'Save Changes'),
          ),
        ],
      ),
    );
  }
}
