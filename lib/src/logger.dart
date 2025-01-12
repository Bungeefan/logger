import 'filters/development_filter.dart';
import 'log_event.dart';
import 'log_filter.dart';
import 'log_level.dart';
import 'log_output.dart';
import 'log_printer.dart';
import 'output_event.dart';
import 'outputs/console_output.dart';
import 'printers/pretty_printer.dart';

typedef LogCallback = void Function(LogEvent event);

typedef OutputCallback = void Function(OutputEvent event);

/// Use instances of logger to send log messages to the [LogPrinter].
class Logger {
  /// The current logging level of the app.
  ///
  /// All logs with levels below this level will be omitted.
  static Level level = Level.trace;

  /// The current default implementation of log filter.
  static LogFilter Function() defaultFilter = () => DevelopmentFilter();

  /// The current default implementation of log printer.
  static LogPrinter Function() defaultPrinter = () => PrettyPrinter();

  /// The current default implementation of log output.
  static LogOutput Function() defaultOutput = () => ConsoleOutput();

  static final Set<LogCallback> _logCallbacks = {};

  static final Set<OutputCallback> _outputCallbacks = {};

  late final Future<void> _initialization;
  final LogFilter _filter;
  final LogPrinter _printer;
  final LogOutput _output;
  final String? _tag;
  bool _active = true;

  /// Create a new instance of Logger.
  ///
  /// You can provide a custom [printer], [filter] and [output]. Otherwise the
  /// defaults: [PrettyPrinter], [DevelopmentFilter] and [ConsoleOutput] will be
  /// used.
  Logger({
    LogFilter? filter,
    LogPrinter? printer,
    LogOutput? output,
    Level? level,
    String? tag,
  })  : _filter = filter ?? defaultFilter(),
        _printer = printer ?? defaultPrinter(),
        _output = output ?? defaultOutput(),
        _tag = tag {
    var filterInit = _filter.init();
    if (level != null) {
      _filter.level = level;
    }
    var printerInit = _printer.init();
    var outputInit = _output.init();
    _initialization = Future.wait([filterInit, printerInit, outputInit]);
  }

  /// Future indicating if the initialization of the
  /// logger components (filter, printer and output) has been finished.
  ///
  /// This is only necessary if your [LogFilter]/[LogPrinter]/[LogOutput]
  /// uses `async` in their `init` method.
  Future<void> get init => _initialization;

  /// Log a message at level [Level.verbose].
  @Deprecated(
      "[Level.verbose] is being deprecated in favor of [Level.trace], use [t] instead.")
  void v(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    t(message, time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.trace].
  void t(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    log(Level.trace, message,
        time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.debug].
  void d(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    log(Level.debug, message,
        time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.info].
  void i(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    log(Level.info, message,
        time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.warning].
  void w(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    log(Level.warning, message,
        time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.error].
  void e(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    log(Level.error, message,
        time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.wtf].
  @Deprecated(
      "[Level.wtf] is being deprecated in favor of [Level.fatal], use [f] instead.")
  void wtf(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    f(message, time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message at level [Level.fatal].
  void f(
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    log(Level.fatal, message,
        time: time, error: error, stackTrace: stackTrace, tag: tag);
  }

  /// Log a message with [level].
  void log(
    Level level,
    dynamic message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
    String? tag,
  }) {
    if (!_active) {
      throw ArgumentError('Logger has already been closed.');
    } else if (error != null && error is StackTrace) {
      throw ArgumentError('Error parameter cannot take a StackTrace!');
    } else if (level == Level.all) {
      throw ArgumentError('Log events cannot have Level.all');
      // ignore: deprecated_member_use_from_same_package
    } else if (level == Level.off || level == Level.nothing) {
      throw ArgumentError('Log events cannot have Level.off');
    }

    var logEvent = LogEvent(
      level,
      message,
      time: time,
      error: error,
      stackTrace: stackTrace,
      // individual log tag has higher priority than Logger tag
      tag: tag ?? _tag,
    );
    for (var callback in _logCallbacks) {
      callback(logEvent);
    }

    if (_filter.shouldLog(logEvent)) {
      var output = _printer.log(logEvent);

      if (output.isNotEmpty) {
        var outputEvent = OutputEvent(logEvent, output);
        // Issues with log output should NOT influence
        // the main software behavior.
        try {
          for (var callback in _outputCallbacks) {
            callback(outputEvent);
          }
          _output.output(outputEvent);
        } catch (e, s) {
          print(e);
          print(s);
        }
      }
    }
  }

  bool isClosed() {
    return !_active;
  }

  /// Closes the logger and releases all resources.
  Future<void> close() async {
    _active = false;
    await _filter.destroy();
    await _printer.destroy();
    await _output.destroy();
  }

  /// Register a [LogCallback] which is called for each new [LogEvent].
  static void addLogListener(LogCallback callback) {
    _logCallbacks.add(callback);
  }

  /// Removes a [LogCallback] which was previously registered.
  ///
  /// Returns whether the callback was successfully removed.
  static bool removeLogListener(LogCallback callback) {
    return _logCallbacks.remove(callback);
  }

  /// Register an [OutputCallback] which is called for each new [OutputEvent].
  static void addOutputListener(OutputCallback callback) {
    _outputCallbacks.add(callback);
  }

  /// Removes a [OutputCallback] which was previously registered.
  ///
  /// Returns whether the callback was successfully removed.
  static void removeOutputListener(OutputCallback callback) {
    _outputCallbacks.remove(callback);
  }
}
