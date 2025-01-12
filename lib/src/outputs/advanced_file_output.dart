import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log_level.dart';
import '../log_output.dart';
import '../output_event.dart';

extension _NumExt on num {
  String toDigits(int digits) => toString().padLeft(digits, '0');
}

/// Accumulates logs in a buffer to reduce frequent disk, writes while optionally
/// switching to a new log file if it reaches a certain size.
///
/// [AdvancedFileOutput] offer various improvements over the original
/// [FileOutput]:
/// * Managing an internal buffer which collects the logs and only writes
/// them after a certain period of time to the disk.
/// * Dynamically switching log files instead of using a single one specified
/// by the user, when the current file reaches a specified size limit (optionally).
///
/// The buffered output can significantly reduce the
/// frequency of file writes, which can be beneficial for (micro-)SD storage
/// and other types of low-cost storage (e.g. on IoT devices). Specific log
/// levels can trigger an immediate flush, without waiting for the next timer
/// tick.
///
/// New log files are created when the current file reaches the specified size
/// limit. This is useful for writing "archives" of telemetry data and logs
/// while keeping them structured.
class AdvancedFileOutput extends LogOutput {
  /// Creates a buffered file output.
  ///
  /// By default, the log is buffered until either the [maxBufferSize] has been
  /// reached, the timer controlled by [maxDelay] has been triggered or an
  /// [OutputEvent] contains a [writeImmediately] log level.
  ///
  /// [maxFileSizeKB] controls the log file rotation. The output automatically
  /// switches to a new log file as soon as the current file exceeds it.
  /// Use -1 to disable log rotation.
  ///
  /// [maxDelay] describes the maximum amount of time before the buffer has to be
  /// written to the file.
  ///
  /// Any log levels that are specified in [writeImmediately] trigger an immediate
  /// flush to the disk ([Level.warning], [Level.error] and [Level.fatal] by default).
  ///
  /// [path] is either treated as directory for rotating or as target file name,
  /// depending on [maxFileSizeKB].
  ///
  /// [maxRotatedFilesCount] controls the number of rotated files to keep. By default
  /// is null, which means no limit.
  /// If set to a positive number, the output will keep the last
  /// [maxRotatedFilesCount] files. The deletion step will be executed by sorting
  /// files following the [fileSorter] ascending strategy and keeping the last files.
  /// The [latestFileName] will not be counted. The default [fileSorter] strategy is
  /// sorting by last modified date, beware that could be not reliable in some
  /// platforms and/or filesystems.
  AdvancedFileOutput({
    required String path,
    bool overrideExisting = false,
    Encoding encoding = utf8,
    List<Level>? writeImmediately,
    Duration maxDelay = const Duration(seconds: 2),
    int maxBufferSize = 2000,
    int maxFileSizeKB = 1024,
    String latestFileName = 'latest.log',
    String Function(DateTime timestamp)? fileNameFormatter,
    int? maxRotatedFilesCount,
    Comparator<File>? fileSorter,
    Duration fileUpdateDuration = const Duration(minutes: 1),
  })  : _path = path,
        _overrideExisting = overrideExisting,
        _encoding = encoding,
        _maxDelay = maxDelay,
        _maxFileSizeKB = maxFileSizeKB,
        _maxBufferSize = maxBufferSize,
        _fileNameFormatter = fileNameFormatter ?? _defaultFileNameFormat,
        _writeImmediately = writeImmediately ??
            [
              Level.error,
              Level.fatal,
              Level.warning,
              // ignore: deprecated_member_use_from_same_package
              Level.wtf,
            ],
        _maxRotatedFilesCount = maxRotatedFilesCount,
        _fileSorter = fileSorter ?? _defaultFileSorter,
        _fileUpdateDuration = fileUpdateDuration,
        _file = maxFileSizeKB > 0 ? File('$path/$latestFileName') : File(path);

  /// Logs directory path by default, particular log file path if [_maxFileSizeKB] is 0.
  final String _path;

  final bool _overrideExisting;
  final Encoding _encoding;

  final List<Level> _writeImmediately;
  final Duration _maxDelay;
  final int _maxFileSizeKB;
  final int _maxBufferSize;
  final String Function(DateTime timestamp) _fileNameFormatter;
  final int? _maxRotatedFilesCount;
  final Comparator<File> _fileSorter;
  final Duration _fileUpdateDuration;

  final File _file;
  IOSink? _sink;
  Timer? _bufferFlushTimer;
  Timer? _targetFileUpdater;

  final List<OutputEvent> _buffer = [];

  bool get _rotatingFilesMode => _maxFileSizeKB > 0;

  /// Formats the file with a full date string.
  ///
  /// Example:
  /// * `2024-01-01-10-05-02-123.log`
  static String _defaultFileNameFormat(DateTime t) {
    return '${t.year}-${t.month.toDigits(2)}-${t.day.toDigits(2)}'
        '-${t.hour.toDigits(2)}-${t.minute.toDigits(2)}-${t.second.toDigits(2)}'
        '-${t.millisecond.toDigits(3)}.log';
  }

  /// Sort files by their last modified date.
  /// This behaviour is inspired by the Log4j PathSorter.
  ///
  /// This method fulfills the requirements of the [Comparator] interface.
  static int _defaultFileSorter(File a, File b) {
    return a.lastModifiedSync().compareTo(b.lastModifiedSync());
  }

  @override
  Future<void> init() async {
    if (_rotatingFilesMode) {
      final dir = Directory(_path);
      // We use sync directory check to avoid losing potential initial boot logs
      // in early crash scenarios.
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      _targetFileUpdater = Timer.periodic(
        _fileUpdateDuration,
        (_) => _updateTargetFile(),
      );
    }

    _bufferFlushTimer = Timer.periodic(_maxDelay, (_) => _flushBuffer());
    await _openSink();
    if (_rotatingFilesMode) {
      await _updateTargetFile(); // Run first check without waiting for timer tick
    }
  }

  @override
  void output(OutputEvent event) {
    _buffer.add(event);
    // If event level is present in writeImmediately, flush the complete buffer
    // along with any other possible elements that accumulated since
    // the last timer tick. Additionally, if the buffer is full.
    if (_buffer.length > _maxBufferSize ||
        _writeImmediately.contains(event.level)) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    if (_sink == null) return; // Wait until _sink becomes available
    for (final event in _buffer) {
      _sink?.writeAll(event.lines, Platform.isWindows ? '\r\n' : '\n');
      _sink?.writeln();
    }
    _buffer.clear();
  }

  Future<void> _updateTargetFile() async {
    try {
      if (await _file.exists() &&
          await _file.length() > _maxFileSizeKB * 1024) {
        // Rotate the log file
        await _closeSink();
        await _file.copy('$_path/${_fileNameFormatter(DateTime.now())}');
        await _deleteRotatedFiles();
        // Clear contents of "latest"
        await _file.writeAsString("", mode: FileMode.write, flush: true);
        await _openSink();
      }
    } catch (e, s) {
      print(e);
      print(s);
      // Try creating another file and working with it
      await _closeSink();
      await _openSink();
    }
  }

  Future<void> _openSink() async {
    _sink = _file.openWrite(
      mode: _overrideExisting ? FileMode.writeOnly : FileMode.writeOnlyAppend,
      encoding: _encoding,
    );
  }

  Future<void> _closeSink() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null; // Explicitly set null until assigned again
  }

  Future<void> _deleteRotatedFiles() async {
    // If maxRotatedFilesCount is not set, keep all files
    if (_maxRotatedFilesCount == null) return;

    final dir = Directory(_path);
    final files = dir
        .listSync()
        .whereType<File>()
        // Filter out the latest file
        .where((f) => f.path != _file.path)
        .toList();

    // If the number of files is less than the limit, don't delete anything
    if (files.length <= _maxRotatedFilesCount!) return;

    files.sort(_fileSorter);

    final filesToDelete =
        files.sublist(0, files.length - _maxRotatedFilesCount!);
    for (final file in filesToDelete) {
      try {
        await file.delete();
      } catch (e, s) {
        print('Failed to delete file: $e');
        print(s);
      }
    }
  }

  @override
  Future<void> destroy() async {
    _bufferFlushTimer?.cancel();
    _targetFileUpdater?.cancel();
    try {
      _flushBuffer();
    } catch (e, s) {
      print('Failed to flush buffer before closing the logger: $e');
      print(s);
    }
    await _closeSink();
  }
}
