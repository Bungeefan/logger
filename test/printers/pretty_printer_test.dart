import 'package:logger/logger.dart';
import 'package:test/test.dart';

void main() {
  String readMessage(List<String> log) {
    return log.reduce((acc, val) => "$acc\n$val");
  }

  test('should print an emoji when option is enabled', () {
    final expectedMessage = 'some message with an emoji';
    final emojiPrettyPrinter = PrettyPrinter(printEmojis: true);

    final event = LogEvent(
      Level.debug,
      expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );

    final actualLog = emojiPrettyPrinter.log(event);
    final actualLogString = readMessage(actualLog);
    expect(actualLogString,
        contains(PrettyPrinter.defaultLevelEmojis[Level.debug]));
    expect(actualLogString, contains(expectedMessage));
  });

  test('should print a tag', () {
    final expectedMessage = 'some message with a tag';
    final printer = PrettyPrinter();

    final event = LogEvent(Level.debug, expectedMessage,
        error: 'some error', stackTrace: StackTrace.current, tag: 'SomeTag');

    final actualLog = printer.log(event);
    final actualLogString = readMessage(actualLog);
    expect(actualLogString, contains('SomeTag'));
    expect(actualLogString, contains(expectedMessage));
  });

  test('should print custom emoji or fallback', () {
    final expectedMessage = 'some message with an emoji';
    final emojiPrettyPrinter = PrettyPrinter(
      printEmojis: true,
      levelEmojis: {
        Level.debug: '🧵',
      },
    );

    final firstEvent = LogEvent(
      Level.debug,
      expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );
    final emojiLogString = readMessage(emojiPrettyPrinter.log(firstEvent));
    expect(
      emojiLogString,
      contains(
          '${emojiPrettyPrinter.levelEmojis![Level.debug]!} $expectedMessage'),
    );

    final secondEvent = LogEvent(
      Level.info,
      expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );
    final fallbackEmojiLogString =
        readMessage(emojiPrettyPrinter.log(secondEvent));
    expect(
      fallbackEmojiLogString,
      contains(
          '${PrettyPrinter.defaultLevelEmojis[Level.info]!} $expectedMessage'),
    );
  });

  test('should print custom color or fallback', () {
    final expectedMessage = 'some message with a color';
    final coloredPrettyPrinter = PrettyPrinter(
      colors: true,
      levelColors: {
        Level.debug: const AnsiColor.fg(50),
      },
    );

    final firstEvent = LogEvent(
      Level.debug,
      expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );
    final coloredLogString = readMessage(coloredPrettyPrinter.log(firstEvent));
    expect(coloredLogString, contains(expectedMessage));
    expect(
      coloredLogString,
      startsWith(coloredPrettyPrinter.levelColors![Level.debug]!.toString()),
    );

    final secondEvent = LogEvent(
      Level.info,
      expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );
    final fallbackColoredLogString =
        readMessage(coloredPrettyPrinter.log(secondEvent));
    expect(fallbackColoredLogString, contains(expectedMessage));
    expect(
      fallbackColoredLogString,
      startsWith(PrettyPrinter.defaultLevelColors[Level.info]!.toString()),
    );
  });

  test('deal with string type message', () {
    final prettyPrinter = PrettyPrinter();
    final expectedMessage = 'normally computed message';
    final withFunction = LogEvent(
      Level.debug,
      expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );

    final actualLog = prettyPrinter.log(withFunction);
    final actualLogString = readMessage(actualLog);

    expect(
      actualLogString,
      contains(expectedMessage),
    );
  });

  test('deal with Map type message', () {
    final prettyPrinter = PrettyPrinter();
    final expectedMsgMap = {'foo': 123, 1: 2, true: 'false'};
    var withMap = LogEvent(
      Level.debug,
      expectedMsgMap,
      error: 'some error',
      stackTrace: StackTrace.current,
    );

    final actualLog = prettyPrinter.log(withMap);
    final actualLogString = readMessage(actualLog);
    for (var expectedMsg in expectedMsgMap.entries) {
      expect(
        actualLogString,
        contains('${expectedMsg.key}: ${expectedMsg.value}'),
      );
    }
  });

  test('deal with Iterable type message', () {
    final prettyPrinter = PrettyPrinter();
    final expectedMsgItems = ['first', 'second', 'third', 'last'];
    var withIterable = LogEvent(
      Level.debug,
      ['first', 'second', 'third', 'last'],
      error: 'some error',
      stackTrace: StackTrace.current,
    );
    final actualLog = prettyPrinter.log(withIterable);
    final actualLogString = readMessage(actualLog);
    for (var expectedMsg in expectedMsgItems) {
      expect(
        actualLogString,
        contains(expectedMsg),
      );
    }
  });

  test('deal with Function type message', () {
    final prettyPrinter = PrettyPrinter();
    final expectedMessage = 'heavily computed very pretty Message';
    final withFunction = LogEvent(
      Level.debug,
      () => expectedMessage,
      error: 'some error',
      stackTrace: StackTrace.current,
    );

    final actualLog = prettyPrinter.log(withFunction);
    final actualLogString = readMessage(actualLog);

    expect(
      actualLogString,
      contains(expectedMessage),
    );
  });

  test('stackTraceBeginIndex', () {
    final prettyPrinter = PrettyPrinter(
      stackTraceBeginIndex: 2,
    );
    final withFunction = LogEvent(
      Level.debug,
      "some message",
      error: 'some error',
      stackTrace: StackTrace.current,
    );

    final actualLog = prettyPrinter.log(withFunction);
    final actualLogString = readMessage(actualLog);

    expect(
      actualLogString,
      allOf([
        isNot(contains("#0   ")),
        isNot(contains("#1   ")),
        contains("#2   "),
      ]),
    );
  });
}
