import 'dart:convert';

import '../ansi_color.dart';
import '../log_event.dart';
import '../log_level.dart';
import '../log_printer.dart';

/// Outputs simple log messages:
/// ```
/// [E] Log message  ERROR: Error info
/// ```
class SimplePrinter extends LogPrinter {
  static final levelPrefixes = {
    Level.trace: '[T]',
    Level.debug: '[D]',
    Level.info: '[I]',
    Level.warning: '[W]',
    Level.error: '[E]',
    Level.fatal: '[FATAL]',
  };

  static final levelColors = {
    Level.trace: AnsiColor.fg(AnsiColor.grey(0.5)),
    Level.debug: const AnsiColor.none(),
    Level.info: const AnsiColor.fg(12),
    Level.warning: const AnsiColor.fg(208),
    Level.error: const AnsiColor.fg(196),
    Level.fatal: const AnsiColor.fg(199),
  };

  final bool printTime;
  final bool colors;

  SimplePrinter({this.printTime = false, this.colors = true});

  @override
  List<String> log(LogEvent event) {
    var messageStr = _stringifyMessage(event.message);
    var tagStr = event.tag != null ? '  [${event.tag}]' : '';
    var errorStr = event.error != null ? '  ERROR: ${event.error}' : '';
    var timeStr = printTime ? ' TIME: ${event.time.toIso8601String()}' : '';
    return ['${_labelFor(event.level)}$tagStr $timeStr $messageStr$errorStr'];
  }

  String _labelFor(Level level) {
    var prefix = levelPrefixes[level]!;
    var color = levelColors[level]!;

    return colors ? color(prefix) : prefix;
  }

  String _stringifyMessage(dynamic message) {
    final finalMessage = message is Function ? message() : message;
    if (finalMessage is Map || finalMessage is Iterable) {
      var encoder = const JsonEncoder.withIndent(null);
      return encoder.convert(finalMessage);
    } else {
      return finalMessage.toString();
    }
  }
}
