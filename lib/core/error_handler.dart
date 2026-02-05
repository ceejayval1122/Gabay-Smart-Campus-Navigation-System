import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'debug_logger.dart';

class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  void initialize() {
    // Set up global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      logger.logAppError(details);
      
      // In debug mode, show the default error widget
      if (kDebugMode) {
        FlutterError.presentError(details);
      } else {
        // In release mode, you might want to send this to a crash reporting service
        _handleReleaseError(details);
      }
    };

    // Handle uncaught async errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PlatformDispatcher.instance.onError = (error, stack) {
        logger.fatal('Uncaught async error', 
          tag: 'AsyncError',
          error: error,
          stackTrace: stack
        );
        
        // In release mode, you might want to send this to a crash reporting service
        if (!kDebugMode) {
          _handleReleaseError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Async Error',
            context: ErrorDescription('Uncaught async error'),
          ));
        }
        
        return true; // Prevent the error from propagating
      };
    });
  }

  void _handleReleaseError(FlutterErrorDetails details) {
    // In release mode, you could send errors to a service like Sentry, Firebase Crashlytics, etc.
    // For now, just log it
    logger.logAppError(details);
  }

  static void handleException(dynamic exception, {String? context, StackTrace? stackTrace}) {
    logger.error('Exception handled', 
      tag: context ?? 'ExceptionHandler',
      error: exception,
      stackTrace: stackTrace
    );
  }

  static void handleNetworkError(dynamic error, String url, {String? method}) {
    logger.logNetworkError(url, method ?? 'GET', error, StackTrace.current);
  }

  static void handleSupabaseError(dynamic error, String operation, {StackTrace? stackTrace}) {
    logger.logSupabaseError(operation, error, stackTrace ?? StackTrace.current);
  }

  static Widget buildErrorWidget(FlutterErrorDetails details) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1E2931),
        appBar: AppBar(
          title: const Text('Error Occurred'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'An error occurred while running the app:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                details.exception.toString(),
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              if (details.context != null)
                Text(
                  details.context.toString(),
                  style: const TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 16),
              const Text(
                'Stack Trace:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    details.stack?.toString() ?? 'No stack trace available',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).maybePop();
                    },
                    child: const Text('Go Back'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom error widget for better debugging
class _GabayErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;

  const _GabayErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return ErrorHandler.buildErrorWidget(details);
  }
}
