import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import 'log_viewer_widget.dart';

class ConnectionWidget extends StatelessWidget {
  final WebSocketService webSocketService;

  const ConnectionWidget({
    super.key,
    required this.webSocketService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: webSocketService.connectionStream,
      initialData: false,
      builder: (context, connectionSnapshot) {
        final isConnected = connectionSnapshot.data ?? false;

        if (isConnected) {
          // Show minimal connected indicator with settings access
          return GestureDetector(
            onTap: () => _showSettingsDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.green.shade400, size: 10),
                  const SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: TextStyle(color: Colors.green.shade300, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => showLogViewer(context),
                    child: Icon(Icons.article_outlined, color: Colors.green.shade400, size: 16),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withOpacity(0.1),
            border: Border.all(
              color: Colors.blue.shade300.withOpacity(0.3),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _buildConnectingWidget(context),
        );
      },
    );
  }

  Widget _buildConnectingWidget(BuildContext context) {
    return StreamBuilder<String?>(
      stream: webSocketService.statusStream,
      builder: (context, statusSnapshot) {
        final status = statusSnapshot.data ?? 'Initializing...';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade300),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.blue.shade300,
                  ),
                ),
                Text(
                  webSocketService.bridgeUrl,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.blue.shade200,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _showSettingsDialog(context),
              child: Icon(Icons.settings, color: Colors.blue.shade300, size: 20),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => showLogViewer(context),
              child: Icon(Icons.article_outlined, color: Colors.blue.shade300, size: 20),
            ),
          ],
        );
      },
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final controller = TextEditingController(text: webSocketService.bridgeUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bridge URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'ws://pbot.pullen.loc:30808',
            labelText: 'WebSocket URL',
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await webSocketService.setBridgeUrl(url);
                await webSocketService.disconnect();
                webSocketService.connect();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save & Reconnect'),
          ),
        ],
      ),
    );
  }
} 