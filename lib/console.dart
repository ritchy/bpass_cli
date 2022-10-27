import 'dart:io';

class Console {
  static ConsoleLevel level = ConsoleLevel.NORMAL;

  static warning(String message, {bool newline = true}) {
    if (level >= ConsoleLevel.WARNING) {
      write(message, newline);
    }
  }

  static minimal(String message, {bool newline = true}) {
    if (level >= ConsoleLevel.MINIMAL) {
      write(message, newline);
    }
  }

  static normal(String message, {bool newline = true}) {
    if (level >= ConsoleLevel.NORMAL) {
      write(message, newline);
    }
  }

  static verbose(String message, {bool newline = true}) {
    if (level >= ConsoleLevel.VERBOSE) {
      write(message, newline);
    }
  }

  static write(String message, bool newline) {
    if (newline) {
      stdout.writeln(message);
    } else {
      stdout.write(message);
    }
  }

  static bool prompt(String message) {
    stdout.write(message);
    stdin.lineMode = false;
    final byte = stdin.readByteSync();
    String input = String.fromCharCode(byte);
    stdout.writeln();
    if (input.isNotEmpty && input.toLowerCase().startsWith("y")) {
      return true;
    } else {
      return false;
    }
  }
}

class ConsoleLevel implements Comparable<ConsoleLevel> {
  final String name;

  /// Unique value for this level. Used to order levels, so filtering can
  /// exclude messages whose level is under certain value.
  final int value;

  const ConsoleLevel(this.name, this.value);

  static const ConsoleLevel NONE = ConsoleLevel('NONE', 0);
  static const ConsoleLevel WARNING = ConsoleLevel('WARNING', 10);
  static const ConsoleLevel MINIMAL = ConsoleLevel('MINIMAL', 20);
  static const ConsoleLevel NORMAL = ConsoleLevel('NORMAL', 30);
  static const ConsoleLevel VERBOSE = ConsoleLevel('VERBOSE', 40);

  @override
  bool operator ==(Object other) =>
      other is ConsoleLevel && value == other.value;

  bool operator <(ConsoleLevel other) => value < other.value;

  bool operator <=(ConsoleLevel other) => value <= other.value;

  bool operator >(ConsoleLevel other) => value > other.value;

  bool operator >=(ConsoleLevel other) => value >= other.value;

  @override
  int compareTo(ConsoleLevel other) => value - other.value;

  @override
  int get hashCode => value;

  @override
  String toString() => name;
}
