import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
  fatal,
}

class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  static const String _logFileName = 'gabay_debug.log';
  File? _logFile;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File('${directory.path}/$_logFileName');
      _isInitialized = true;
      
      // Write initial log entry
      await _writeToFile('=== Gabay Debug Session Started at ${DateTime.now()} ===\n');
    } catch (e) {
      developer.log('Failed to initialize debug logger: $e', name: 'DebugLogger');
    }
  }

  void debug(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.debug, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void info(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.info, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void warning(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.warning, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void fatal(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.fatal, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void _log(LogLevel level, String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    final levelStr = level.name.toUpperCase();
    final tagStr = tag != null ? '[$tag] ' : '';
    final logMessage = '[$timestamp] $levelStr $tagStr$message';
    
    // Always log to console in debug mode
    if (kDebugMode) {
      if (error != null) {
        developer.log(logMessage, name: 'Gabay', error: error, stackTrace: stackTrace);
      } else {
        developer.log(logMessage, name: 'Gabay');
      }
    }
    
    // Write to file
    _writeToFile(logMessage);
    
    if (error != null) {
      _writeToFile('Error: $error');
    }
    
    if (stackTrace != null) {
      _writeToFile('StackTrace: $stackTrace');
    }
    
    _writeToFile(''); // Add empty line for readability
  }

  Future<void> _writeToFile(String message) async {
    if (!_isInitialized || _logFile == null) return;
    
    try {
      await _logFile!.writeAsString('$message\n', mode: FileMode.append);
    } catch (e) {
      developer.log('Failed to write to log file: $e', name: 'DebugLogger');
    }
  }

  Future<String> getLogFilePath() async {
    if (!_isInitialized || _logFile == null) return '';
    return _logFile!.path;
  }

  Future<String> getLogContents() async {
    if (!_isInitialized || _logFile == null) return '';
    
    try {
      final exists = await _logFile!.exists();
      if (!exists) return 'No log file found.';
      
      return await _logFile!.readAsString();
    } catch (e) {
      return 'Error reading log file: $e';
    }
  }

  Future<void> clearLogs() async {
    if (!_isInitialized || _logFile == null) return;
    
    try {
      await _logFile!.writeAsString('');
      await _writeToFile('=== Logs Cleared at ${DateTime.now()} ===\n');
    } catch (e) {
      developer.log('Failed to clear logs: $e', name: 'DebugLogger');
    }
  }

  Future<void> logAppStart() async {
    await initialize();
    info('App starting up', tag: 'AppLifecycle');
    
    // Log system info
    if (kDebugMode) {
      debug('Debug mode enabled', tag: 'System');
      debug('Platform: ${Platform.operatingSystem}', tag: 'System');
      debug('Flutter version: ${Platform.environment['FLUTTER_VERSION'] ?? 'Unknown'}', tag: 'System');
    }
  }

  Future<void> logAppError(FlutterErrorDetails details) async {
    await initialize();
    
    fatal('Unhandled Flutter error', 
      tag: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack
    );
    
    // Also log additional context
    error('Library: ${details.library}');
    error('Context: ${details.context?.toString() ?? 'No context'}');
  }

  Future<void> logNetworkError(String url, String method, dynamic error, StackTrace? stackTrace) async {
    await initialize();
    
    error('Network request failed', 
      tag: 'Network',
      error: error,
      stackTrace: stackTrace
    );
    
    debug('URL: $url');
    debug('Method: $method');
  }

  Future<void> logSupabaseError(String operation, dynamic error, StackTrace? stackTrace) async {
    await initialize();
    
    error('Supabase operation failed', 
      tag: 'Supabase',
      error: error,
      stackTrace: stackTrace
    );
    
    debug('Operation: $operation');
  }
}

// Global logger instance
final logger = DebugLogger();
