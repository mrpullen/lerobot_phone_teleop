import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';

class LogViewerWidget extends StatefulWidget {
  const LogViewerWidget({super.key});

  @override
  State<LogViewerWidget> createState() => _LogViewerWidgetState();
}

class _LogViewerWidgetState extends State<LogViewerWidget> {
  final _scrollController = ScrollController();
  late final StreamSubscription<LogEntry> _sub;
  List<LogEntry> _entries = [];
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _entries = LogService.instance.entries;
    _sub = LogService.instance.stream.listen((_) {
      if (mounted) {
        setState(() => _entries = LogService.instance.entries);
        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey.shade500;
      case LogLevel.info:
        return Colors.cyan.shade300;
      case LogLevel.warn:
        return Colors.orange.shade300;
      case LogLevel.error:
        return Colors.red.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Row(
          children: [
            const Text('Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Text('${_entries.length} entries',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                  size: 18),
              tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
              onPressed: () => setState(() => _autoScroll = !_autoScroll),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy all logs',
              onPressed: () {
                final text = _entries.map((e) => e.formatted).join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied'), duration: Duration(seconds: 1)),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Clear',
              onPressed: () {
                LogService.instance.clear();
                setState(() => _entries = []);
              },
            ),
          ],
        ),
        const Divider(height: 1),
        // Log list
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('No logs yet', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
                      child: Text(
                        e.formatted,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: _levelColor(e.level),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Shows a full-screen log viewer dialog
void showLogViewer(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(12),
        child: const LogViewerWidget(),
      ),
    ),
  );
}
