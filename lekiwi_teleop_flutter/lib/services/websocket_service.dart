import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _sendTimer;
  final _log = LogService.instance;
  static const _tag = 'WS';
  int _connectAttempt = 0;

  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();
  final StreamController<String?> _statusController = StreamController.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String?> get statusStream => _statusController.stream;

  bool get isConnected => _channel != null;

  // Training telemetry
  bool _trainingActive = false;
  bool get trainingActive => _trainingActive;
  final StreamController<bool> _trainingController = StreamController.broadcast();
  Stream<bool> get trainingStream => _trainingController.stream;

  // Bridge URL (configurable, persisted)
  String _bridgeUrl = 'ws://pbot.pullen.loc:30808';
  String get bridgeUrl => _bridgeUrl;

  static const String _prefKey = 'bridge_url';

  // Current velocity commands to send to Python
  double _xVel = 0.0;
  double _yVel = 0.0;
  double _thetaVel = 0.0;
  double _wristFlexVel = 0.0;

  // Manipulator joint velocities (6 joints)
  List<double> _manipulatorJointVel = List.filled(6, 0.0);

  // Speed limits
  static const double maxLinearVel = 0.25;
  static const double maxRotationVel = 60.0;
  static const double maxWristFlexVel = 1.0;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved != 'wss://pbot.pullen.loc' && saved != 'ws://pbot.pullen.loc') {
      _bridgeUrl = saved;
    }
    _log.i(_tag, 'loadSettings: url=$_bridgeUrl');
  }

  Future<void> setBridgeUrl(String url) async {
    _bridgeUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url);
  }

  Future<void> connect() async {
    await loadSettings();
    _connectAttempt = 0;
    _log.i(_tag, 'connect() called, url=$_bridgeUrl');
    _statusController.add('Connecting to $_bridgeUrl ...');
    _doConnect();
  }

  void _doConnect() async {
    _reconnectTimer?.cancel();
    _connectAttempt++;
    _log.i(_tag, '--- Connection attempt #$_connectAttempt ---');

    final uri = Uri.parse(_bridgeUrl);
    _log.i(_tag, 'Parsed URI: scheme=${uri.scheme} host=${uri.host} port=${uri.port}');

    // Network diagnostics on first attempt and every 10th
    if (_connectAttempt == 1 || _connectAttempt % 10 == 0) {
      await _logNetworkDiagnostics(uri.host);
    }

    // DNS resolution check
    try {
      final stopwatch = Stopwatch()..start();
      final addrs = await InternetAddress.lookup(uri.host);
      stopwatch.stop();
      _log.i(_tag, 'DNS resolved ${uri.host} -> ${addrs.map((a) => "${a.address} (${a.type.name})").join(", ")} (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      _log.e(_tag, 'DNS lookup FAILED for ${uri.host}: $e');
      // Try IPv4-only lookup as fallback
      try {
        final addrs4 = await InternetAddress.lookup(uri.host, type: InternetAddressType.IPv4);
        _log.i(_tag, 'IPv4-only lookup succeeded: ${addrs4.map((a) => a.address).join(", ")}');
      } catch (e4) {
        _log.e(_tag, 'IPv4-only lookup also FAILED: $e4');
      }
      // Try a known host to verify DNS works at all
      try {
        final google = await InternetAddress.lookup('google.com');
        _log.i(_tag, 'google.com resolves OK -> ${google.first.address} (DNS is working for public domains)');
      } catch (eg) {
        _log.e(_tag, 'google.com also FAILED -> DNS is completely broken: $eg');
      }
      _statusController.add('DNS failed: ${uri.host}');
      _scheduleReconnect();
      return;
    }

    // WebSocket connect
    try {
      _log.i(_tag, 'Opening WebSocket to $uri ...');
      _channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: const Duration(seconds: 10),
      );

      _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message);
            if (data['type'] == 'observation') {
              _messageController.add(data);
            }
          } catch (e) {
            _log.e(_tag, 'Decode error: $e');
          }
        },
        onDone: () {
          final code = _channel?.closeCode;
          final reason = _channel?.closeReason;
          _log.w(_tag, 'Stream onDone: closeCode=$code reason=$reason');
          _channel = null;
          _connectionController.add(false);
          _statusController.add('Disconnected (code=$code). Reconnecting...');
          _scheduleReconnect();
        },
        onError: (error, stackTrace) {
          _log.e(_tag, 'Stream onError: $error');
          _log.e(_tag, 'Stack: $stackTrace');
          _channel = null;
          _connectionController.add(false);
          _statusController.add('Error: $error');
          _scheduleReconnect();
        },
      );

      _connectionController.add(true);
      _statusController.add('Connected to $_bridgeUrl');
      _log.i(_tag, 'Connected successfully (attempt #$_connectAttempt)');
    } catch (e, st) {
      _log.e(_tag, 'Connect exception: $e');
      _log.e(_tag, 'Stack: $st');
      _statusController.add('Failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _log.i(_tag, 'Will reconnect in 3s...');
    _reconnectTimer = Timer(const Duration(seconds: 3), _doConnect);
  }

  Future<void> _logNetworkDiagnostics(String host) async {
    _log.i(_tag, '=== Network Diagnostics ===');
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      for (final iface in interfaces) {
        final addrs = iface.addresses.map((a) => '${a.address}(${a.type.name})').join(', ');
        _log.i(_tag, 'Interface: ${iface.name} -> $addrs');
      }
    } catch (e) {
      _log.e(_tag, 'Failed to list interfaces: $e');
    }

    // Test DNS for known hosts
    for (final testHost in [host, 'google.com', 'pihole.pullen.loc']) {
      try {
        final addrs = await InternetAddress.lookup(testHost);
        _log.i(_tag, 'DNS $testHost -> ${addrs.map((a) => a.address).join(", ")}');
      } catch (e) {
        _log.e(_tag, 'DNS $testHost -> FAILED: $e');
      }
    }
    _log.i(_tag, '=== End Diagnostics ===');
  }

  // Apply deadzone logic: 0-15% = 0, 15-30% = proportional 0-30%, 30%+ = actual
  double _applyDeadzone(double value) {
    final absValue = value.abs();
    if (absValue < 0.15) {
      return 0.0;
    } else if (absValue < 0.30) {
      // Scale from 0.15-0.30 range to 0.0-0.30 range
      final scaledValue = (absValue - 0.15) / 0.15 * 0.30;
      return value > 0 ? scaledValue : -scaledValue;
    } else {
      return value;
    }
  }

  // Send velocity commands to Python (from joystick input)
  void sendJoystickInput(double x, double y) {
    // Apply deadzone first
    final deadzoneX = _applyDeadzone(x);
    final deadzoneY = _applyDeadzone(y);
    
    // Convert joystick input (-1 to 1) to velocity commands
    // y controls forward/backward (x.vel), x controls left/right (y.vel)
    _xVel = deadzoneY * maxLinearVel; // Forward/backward
    _yVel = -deadzoneX * maxLinearVel; // Left/right (inverted for intuitive control)
    // Don't reset _thetaVel here - keep rotation independent
    
    _sendActionMessage();
  }

  // Send rotation and wrist flex commands (from right joystick)
  void sendArmRotationInput(double rotation, double wristFlex) {
    // Apply deadzone first
    final deadzoneRotation = _applyDeadzone(rotation);
    final deadzoneWristFlex = _applyDeadzone(wristFlex);
    
    // Fix inversion issues: negate both rotation and wrist flex
    _thetaVel = -deadzoneRotation * maxRotationVel; // Fix rotation inversion
    _wristFlexVel = -deadzoneWristFlex * maxWristFlexVel; // Fix wrist flex inversion
    _sendActionMessage();
  }

  // Send rotation command (from IMU)
  void sendRotationInput(double theta) {
    _thetaVel = theta * maxRotationVel;
    _sendActionMessage();
  }

  // Send manipulator joint input (for manipulator mode)
  void sendManipulatorJointInput(int jointIndex, double value) {
    if (jointIndex >= 0 && jointIndex < 6) {
      _manipulatorJointVel[jointIndex] = value; // Max speed is 1 as specified
      debugPrint('🦾 Joint $jointIndex = ${value.toStringAsFixed(2)} | All joints: ${_manipulatorJointVel.map((v) => v.toStringAsFixed(2)).join(", ")}');
      
      // Always send as action message (not manipulator_action)
      _sendActionMessage();
    }
  }

  // Update specific velocity component
  void updateXVel(double xVel) {
    _xVel = xVel;
    _sendActionMessage();
  }

  void updateYVel(double yVel) {
    _yVel = yVel;
    _sendActionMessage();
  }

  void updateThetaVel(double thetaVel) {
    _thetaVel = thetaVel;
    _sendActionMessage();
  }

  void updateWristFlexVel(double wristFlexVel) {
    _wristFlexVel = wristFlexVel;
    _sendActionMessage();
  }

  // Emergency stop - reset all velocities
  void sendEmergencyStop() {
    _xVel = 0.0;
    _yVel = 0.0;
    _thetaVel = 0.0;
    _wristFlexVel = 0.0;
    _manipulatorJointVel.fillRange(0, 6, 0.0);
    _sendActionMessage();
  }

  void _sendActionMessage() {
    if (!isConnected) return;
    
    // Check if any manipulator joints are active
    bool manipulatorActive = _manipulatorJointVel.any((vel) => vel != 0.0);
    
    final message = {
      'type': 'action',
      'x.vel': _xVel,
      'y.vel': _yVel,
      'theta.vel': _thetaVel,
      // Wrist flex: use manipulator if active, otherwise use base mode
      'wrist_flex.vel': manipulatorActive ? _manipulatorJointVel[3] : _wristFlexVel,
      // All manipulator joint velocities
      'shoulder_pan.vel': _manipulatorJointVel[0],
      'shoulder_lift.vel': _manipulatorJointVel[1],
      'elbow_flex.vel': _manipulatorJointVel[2],
      'wrist_roll.vel': _manipulatorJointVel[4],
      'gripper.vel': _manipulatorJointVel[5],
    };
    
    debugPrint('📤 Sending action: ${json.encode(message)}');
    _sendMessage(message);
  }

  void _sendManipulatorActionMessage() {
    // Remove this method - we don't need it anymore
    // Everything goes through _sendActionMessage()
  }

  void _sendMessage(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(json.encode(message));
    } catch (e) {
      _log.e(_tag, 'Send error: $e');
    }
  }

  void toggleTraining() {
    _trainingActive = !_trainingActive;
    _trainingController.add(_trainingActive);
    final msg = {'type': _trainingActive ? 'training_start' : 'training_stop'};
    _log.i(_tag, 'Training ${_trainingActive ? "STARTED" : "STOPPED"}');
    _sendMessage(msg);
  }

  void sendHome() {
    _log.i(_tag, 'Sending HOME command');
    _sendMessage({'type': 'home'});
  }

  Future<void> disconnect() async {
    _log.i(_tag, 'disconnect() called');
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _connectionController.add(false);
    _statusController.add('Disconnected');
    _log.i(_tag, 'Disconnected.');
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
    _statusController.close();
  }
} 