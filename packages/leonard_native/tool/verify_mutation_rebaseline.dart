import 'dart:io';

import 'package:xml/xml.dart';

const int _maximumUndetected = 214;

/// Verifies that a full mutation report is a string-excluded rebaseline.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run tool/verify_mutation_rebaseline.dart REPORT_DIRECTORY',
    );
    exitCode = 64;
    return;
  }

  try {
    final Directory reportDirectory = Directory(arguments.single);
    final _Score score = _parseScore(
      File(
        '${reportDirectory.path}/mutation-test-report.md',
      ).readAsStringSync(),
    );
    final List<_Survivor> survivors = _parseSurvivors(
      File(
        '${reportDirectory.path}/mutation-test-report.xml',
      ).readAsStringSync(),
    );

    final List<String> failures = <String>[];
    if (survivors.length != score.undetected) {
      failures.add(
        'XML has ${survivors.length} survivors but Markdown reports '
        '${score.undetected}',
      );
    }
    if (score.undetected > _maximumUndetected) {
      failures.add(
        'Markdown reports ${score.undetected} undetected mutations; '
        'expected fewer than 215',
      );
    }
    final List<_Survivor> stringInterior = survivors
        .where(
          (_Survivor survivor) =>
              _differenceIsInsideString(survivor.original, survivor.modified),
        )
        .toList();
    if (stringInterior.isNotEmpty) {
      failures.add(
        '${stringInterior.length} string-interior survivors remain '
        '(${stringInterior.first.location})',
      );
    }

    if (failures.isNotEmpty) {
      stderr.writeln('MUTATION_REBASELINE FAIL: ${failures.join('; ')}');
      exitCode = 1;
      return;
    }

    stdout.writeln(
      'MUTATION_REBASELINE PASS: ${score.total} mutants, '
      '${score.undetected} undetected, ${score.killedPercentage}% killed, '
      'rating ${score.rating}; 0 string-interior survivors; '
      '2026-08-01 542/215/60.33%/C is not comparable '
      '(string exclusion disabled); mutation_test 1.8.0 compile-error '
      'inflation remains.',
    );
  } on FileSystemException catch (error) {
    stderr.writeln('mutation rebaseline reports unavailable: ${error.message}');
    exitCode = 66;
  } on XmlParserException catch (error) {
    stderr.writeln('malformed mutation rebaseline report: $error');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('malformed mutation rebaseline report: ${error.message}');
    exitCode = 66;
  }
}

_Score _parseScore(String markdown) {
  final int total = _parseNonNegativeInt(
    _markdownValue(markdown, 'Mutations'),
    'Mutations',
  );
  final int undetected = _parseNonNegativeInt(
    _markdownValue(markdown, 'Undetected'),
    'Undetected',
  );
  final String undetectedPercentageText = _markdownValue(
    markdown,
    'Undetected%',
  );
  final RegExpMatch? percentageMatch = RegExp(
    r'^(\d+(?:\.\d+)?)%$',
  ).firstMatch(undetectedPercentageText);
  if (percentageMatch == null) {
    throw const FormatException('Undetected% is not a percentage');
  }
  final double undetectedPercentage = double.parse(percentageMatch.group(1)!);
  final String rating = _markdownValue(markdown, 'Quality Rating');

  if (total == 0) {
    throw const FormatException('Mutations must be greater than zero');
  }
  if (undetected > total) {
    throw const FormatException('Undetected exceeds Mutations');
  }
  final double expectedUndetectedPercentage = 100 * undetected / total;
  if (undetectedPercentage.toStringAsFixed(2) !=
      expectedUndetectedPercentage.toStringAsFixed(2)) {
    throw const FormatException(
      'Undetected% disagrees with Mutations and Undetected',
    );
  }
  if (rating.isEmpty) {
    throw const FormatException('Quality Rating is empty');
  }

  return _Score(
    total: total,
    undetected: undetected,
    killedPercentage: (100 - expectedUndetectedPercentage).toStringAsFixed(2),
    rating: rating,
  );
}

String _markdownValue(String markdown, String key) {
  final RegExp row = RegExp(
    '^\\|\\s*${RegExp.escape(key)}\\s*\\|\\s*([^|]+?)\\s*\\|\\s*\$',
    multiLine: true,
  );
  final List<RegExpMatch> matches = row.allMatches(markdown).toList();
  if (matches.length != 1) {
    throw FormatException('expected one Markdown $key row');
  }
  return matches.single.group(1)!.trim();
}

int _parseNonNegativeInt(String value, String key) {
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw FormatException('$key is not a non-negative integer');
  }
  return int.parse(value);
}

List<_Survivor> _parseSurvivors(String xml) {
  final XmlDocument document = XmlDocument.parse(xml);
  final XmlElement root = document.rootElement;
  if (root.name.local != 'undetected-mutations') {
    throw const FormatException('unexpected XML root element');
  }

  return root.findAllElements('mutation').map((XmlElement mutation) {
    final List<XmlElement> originals = mutation.childElements
        .where((XmlElement child) => child.name.local == 'original')
        .toList();
    final List<XmlElement> modified = mutation.childElements
        .where((XmlElement child) => child.name.local == 'modified')
        .toList();
    if (originals.length != 1 || modified.length != 1) {
      throw const FormatException(
        'each XML mutation needs one original and one modified element',
      );
    }
    final String original = originals.single.innerText;
    final String replacement = modified.single.innerText;
    _firstDifferingCodeUnit(original, replacement);
    XmlElement? file;
    for (final XmlElement ancestor in mutation.ancestorElements) {
      if (ancestor.name.local == 'file') {
        file = ancestor;
        break;
      }
    }
    final String fileName = file?.getAttribute('name') ?? '<unknown file>';
    final String line = mutation.getAttribute('line') ?? '?';
    return _Survivor(
      original: original,
      modified: replacement,
      location: '$fileName:$line',
    );
  }).toList();
}

bool _differenceIsInsideString(String original, String modified) {
  final int difference = _firstDifferingCodeUnit(original, modified);
  _StringOpening? opening;
  var raw = false;
  var index = 0;
  while (index < difference) {
    if (opening == null) {
      final int codeUnit = original.codeUnitAt(index);
      if ((codeUnit == _lowerR || codeUnit == _upperR) &&
          index + 1 < original.length) {
        final _StringOpening? rawOpening = _openingAt(original, index + 1);
        if (rawOpening != null) {
          opening = rawOpening;
          raw = true;
          index += rawOpening.width + 1;
          continue;
        }
      }
      final _StringOpening? regularOpening = _openingAt(original, index);
      if (regularOpening != null) {
        opening = regularOpening;
        raw = false;
        index += regularOpening.width;
        continue;
      }
      index++;
      continue;
    }

    if (!raw && original.codeUnitAt(index) == _backslash) {
      index += 2;
      continue;
    }
    if (_closesAt(original, index, opening)) {
      index += opening.width;
      opening = null;
      raw = false;
      continue;
    }
    index++;
  }
  return opening != null;
}

int _firstDifferingCodeUnit(String original, String modified) {
  final int sharedLength = original.length < modified.length
      ? original.length
      : modified.length;
  for (var index = 0; index < sharedLength; index++) {
    if (original.codeUnitAt(index) != modified.codeUnitAt(index)) {
      return index;
    }
  }
  if (original.length != modified.length) {
    return sharedLength;
  }
  throw const FormatException('XML mutation does not change its source line');
}

_StringOpening? _openingAt(String source, int index) {
  if (index >= source.length) {
    return null;
  }
  final int quote = source.codeUnitAt(index);
  if (quote != _singleQuote && quote != _doubleQuote) {
    return null;
  }
  final bool triple =
      index + 2 < source.length &&
      source.codeUnitAt(index + 1) == quote &&
      source.codeUnitAt(index + 2) == quote;
  return _StringOpening(quote: quote, width: triple ? 3 : 1);
}

bool _closesAt(String source, int index, _StringOpening opening) {
  if (index >= source.length || source.codeUnitAt(index) != opening.quote) {
    return false;
  }
  if (opening.width == 1) {
    return true;
  }
  return index + 2 < source.length &&
      source.codeUnitAt(index + 1) == opening.quote &&
      source.codeUnitAt(index + 2) == opening.quote;
}

const int _singleQuote = 0x27;
const int _doubleQuote = 0x22;
const int _backslash = 0x5c;
const int _lowerR = 0x72;
const int _upperR = 0x52;

class _Score {
  const _Score({
    required this.total,
    required this.undetected,
    required this.killedPercentage,
    required this.rating,
  });

  final int total;
  final int undetected;
  final String killedPercentage;
  final String rating;
}

class _Survivor {
  const _Survivor({
    required this.original,
    required this.modified,
    required this.location,
  });

  final String original;
  final String modified;
  final String location;
}

class _StringOpening {
  const _StringOpening({required this.quote, required this.width});

  final int quote;
  final int width;
}
