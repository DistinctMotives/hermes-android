import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/remote_files_client.dart';
import '../theme/hermes_theme.dart';
import '../widgets/hermes_components.dart';

class FilesScreen extends StatefulWidget {
  final RemoteFilesDataSource files;
  final ValueChanged<String>? onAddToChat;
  final Future<void> Function(RemoteFileDownload download)? onSaveDownload;

  const FilesScreen({
    required this.files,
    this.onAddToChat,
    this.onSaveDownload,
    super.key,
  });

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  RemoteDirectory? _root;
  String? _path;
  List<RemoteFileEntry> _entries = const [];
  RemoteFileEntry? _selected;
  RemoteTextPreview? _preview;
  Object? _error;
  bool _loading = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoot());
  }

  Future<void> _loadRoot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await widget.files.defaultDirectory();
      if (!mounted) return;
      _root = root;
      await _openDirectory(root.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _openDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      _preview = null;
    });
    try {
      final entries = await widget.files.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _path = path;
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _openFile(RemoteFileEntry entry) async {
    setState(() {
      _selected = entry;
      _preview = null;
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.files.readText(entry.path);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  String? get _parentPath {
    final path = _path;
    final root = _root?.path;
    if (path == null || root == null || path == root) return null;
    final separator = path.lastIndexOf('/');
    if (separator <= 0) return '/';
    return path.substring(0, separator);
  }

  void _back() {
    if (_selected != null) {
      setState(() {
        _selected = null;
        _preview = null;
        _error = null;
      });
      return;
    }
    final parent = _parentPath;
    if (parent != null) {
      unawaited(_openDirectory(parent));
      return;
    }
    Navigator.maybePop(context);
  }

  Future<void> _download() async {
    final selected = _selected;
    if (selected == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final download = await widget.files.download(selected.path);
      final saver = widget.onSaveDownload;
      if (saver != null) {
        await saver(download);
      } else {
        await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${download.filename}',
          fileName: download.filename,
          bytes: download.bytes,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${download.filename} downloaded')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $error')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _directoryBody() {
    if (_entries.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.folder_open_outlined,
          title: 'Folder is empty',
          message: 'There are no visible files in this server folder.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _openDirectory(_path!),
      child: ListView.separated(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: HermesSpacing.sm),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return HermesCard(
            padding: const EdgeInsets.symmetric(
              horizontal: HermesSpacing.lg,
              vertical: HermesSpacing.md,
            ),
            onTap: () => entry.isDirectory
                ? unawaited(_openDirectory(entry.path))
                : unawaited(_openFile(entry)),
            child: Row(
              children: [
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  color: HermesTokens.of(context).accent,
                ),
                const SizedBox(width: HermesSpacing.md),
                Expanded(child: Text(entry.name)),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _previewBody() {
    final selected = _selected!;
    final preview = _preview;
    final tokens = HermesTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(HermesSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(selected.name, style: tokens.typography.section),
          const SizedBox(height: HermesSpacing.sm),
          Wrap(
            spacing: HermesSpacing.sm,
            runSpacing: HermesSpacing.sm,
            children: [
              if (preview != null)
                StatusChip(status: HermesStatus.idle, label: preview.language),
              if (preview?.truncated == true)
                const StatusChip(
                  status: HermesStatus.blocked,
                  label: 'Preview truncated',
                ),
            ],
          ),
          const SizedBox(height: HermesSpacing.lg),
          Expanded(
            child: HermesCard(
              child: SingleChildScrollView(
                child: SelectableText(
                  preview?.binary == true
                      ? 'Binary preview is unavailable. Download the file to open it.'
                      : preview?.text ?? 'Preview unavailable',
                  style: tokens.typography.body.copyWith(
                    fontFamily: 'monospace',
                    color: tokens.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: HermesSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download'),
                ),
              ),
              if (widget.onAddToChat != null) ...[
                const SizedBox(width: HermesSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onAddToChat!(selected.path);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('File reference added to chat'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Add to chat'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingSkeleton(rows: 6);
    if (_error != null) {
      return Center(
        child: ErrorState(
          title: _selected == null
              ? 'Could not load files'
              : 'Could not preview file',
          message: 'Check the Dashboard connection and try again.',
          onRetry: _selected == null
              ? () => unawaited(
                  _path == null ? _loadRoot() : _openDirectory(_path!),
                )
              : () => unawaited(_openFile(_selected!)),
        ),
      );
    }
    return _selected == null ? _directoryBody() : _previewBody();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back)),
      title: const Text('Files'),
      bottom: _selected == null && _path != null
          ? PreferredSize(
              preferredSize: const Size.fromHeight(42),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _path!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_root?.branch != null)
                      StatusChip(
                        status: HermesStatus.idle,
                        label: _root!.branch,
                      ),
                  ],
                ),
              ),
            )
          : null,
    ),
    body: _body(),
  );
}
