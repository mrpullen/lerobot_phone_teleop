import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry(this.level, this.tag, this.message) : timestamp = DateTime.now();

  String get formatted {
    final ts = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    final lvl = level.name.toUpperCase().padRight(5);
    return '[$ts] $lvl [$tag] $message';
  }
}

class LogService {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;
  LogService._();

  static const int maxEntries = 500;
  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<LogEntry> _controller = StreamController.broadcast();

  Stream<LogEntry> get stream => _controller.stream;
  List<LogEntry> get entries => _entries.toList();

  void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(level, tag, message);
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    _controller.add(entry);
    debugPrint(entry.formatted);
  }

  void d(String tag, String message) => _add(LogLevel.debug, tag, message);
  void i(String tag, String message) => _add(LogLevel.info, tag, message);
  void w(String tag, String message) => _add(LogLevel.warn, tag, message);
  void e(String tag, String message) => _add(LogLevel.error, tag, message);

  void clear() => _entries.clear();
}
