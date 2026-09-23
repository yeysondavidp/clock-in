import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

// What the app knows about one day, ready to be written into the timesheet
class TimesheetEntry {
  final DateTime date;
  final String? start;       // 'HH:mm' of the regular session
  final String? end;
  final String? note;        // extra sessions, written to the notes column
  final String? holidayName; // only set for holidays on work days without sessions

  const TimesheetEntry({
    required this.date,
    this.start,
    this.end,
    this.note,
    this.holidayName,
  });

  bool get hasTimes => start != null && end != null;
}

class TimesheetResult {
  final Uint8List bytes;
  final List<String> filled;    // days written into empty rows
  final List<String> conflicts; // rows that already had different data, left untouched
  final List<String> skipped;   // days that could not be placed in the sheet

  const TimesheetResult(this.bytes, this.filled, this.conflicts, this.skipped);
}

class TimesheetException implements Exception {
  final String message;
  TimesheetException(this.message);

  @override
  String toString() => message;
}

// Fills a yearly timesheet workbook (one sheet per year named like
// "Timesheets 2026", one row per calendar day, date in column B).
// Only empty rows are written; rows that already hold data are compared
// and reported, never overwritten. The XML is edited in place so every
// other cell, sheet, format and formula is kept as it was.
class TimesheetFiller {
  static const _lunch = 30; // minutes, always deducted in this template

  // Column letters in the template
  static const _start = 'C', _end = 'D', _hours = 'E', _lunchCol = 'F',
      _total = 'G', _notes = 'H';
  static const _timeColumns = [_start, _end, _hours, _lunchCol, _total];

  static TimesheetResult fill(List<int> xlsx, List<TimesheetEntry> entries) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(xlsx);
    } catch (_) {
      throw TimesheetException('The selected file is not a valid .xlsx file.');
    }

    final workbook = _parse(archive, 'xl/workbook.xml');
    final rels = _parse(archive, 'xl/_rels/workbook.xml.rels');
    final strings = _sharedStrings(archive);

    final filled = <String>[];
    final conflicts = <String>[];
    final skipped = <String>[];
    final changed = <String, XmlDocument>{};

    final byYear = <int, List<TimesheetEntry>>{};
    for (final e in entries) {
      byYear.putIfAbsent(e.date.year, () => []).add(e);
    }

    for (final year in byYear.keys) {
      final path = _sheetPath(workbook, rels, year);
      if (path == null) {
        skipped.add('$year: no "Timesheets $year" sheet in the file');
        continue;
      }
      final sheet = _Sheet(_parse(archive, path), strings);

      for (final entry in byYear[year]!) {
        final label = _label(entry.date);
        final row = sheet.rowFor(entry.date);
        if (row == null) {
          skipped.add('$label: date not found in the sheet');
          continue;
        }
        final outcome = entry.hasTimes || entry.note != null
            ? sheet.writeTimes(row, entry)
            : sheet.writeHoliday(row, entry.holidayName!);
        if (outcome.wrote) filled.add(label);
        conflicts.addAll(outcome.conflicts.map((c) => '$label: $c'));
      }
      if (sheet.modified) changed[path] = sheet.doc;
    }

    if (changed.isNotEmpty) {
      _recalculateOnLoad(workbook);
      changed['xl/workbook.xml'] = workbook;
    }

    // Rebuild the zip, replacing only the parts that changed. Unchanged parts
    // are copied from their decompressed content: reusing the decoded entries
    // as-is makes the encoder deflate already-compressed data again.
    final out = Archive();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final doc = changed[file.name];
      out.addFile(ArchiveFile.bytes(file.name,
          doc == null ? file.content : utf8.encode(doc.toXmlString())));
    }
    return TimesheetResult(
        ZipEncoder().encodeBytes(out), filled, conflicts, skipped);
  }

  static XmlDocument _parse(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) {
      throw TimesheetException('The selected file is not a valid .xlsx file.');
    }
    return XmlDocument.parse(utf8.decode(file.content));
  }

  static List<String> _sharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    return XmlDocument.parse(utf8.decode(file.content))
        .findAllElements('si')
        .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  }

  // Sheet names vary between years ("Timesheets 2026", "Tïmesheets 2024"),
  // so match on the year after "sheets"
  static String? _sheetPath(XmlDocument workbook, XmlDocument rels, int year) {
    final pattern = RegExp('sheets?\\s*$year\\s*\$', caseSensitive: false);
    final sheet = workbook.findAllElements('sheet').where(
        (s) => pattern.hasMatch(s.getAttribute('name') ?? '')).firstOrNull;
    if (sheet == null) return null;

    final id = sheet.getAttribute('r:id');
    final target = rels
        .findAllElements('Relationship')
        .where((r) => r.getAttribute('Id') == id)
        .firstOrNull
        ?.getAttribute('Target');
    if (target == null) return null;
    return target.startsWith('/') ? target.substring(1) : 'xl/$target';
  }

  // Cached results of the formulas are dropped for the rows we touch,
  // so ask Excel / Sheets to recompute everything when opening the file
  static void _recalculateOnLoad(XmlDocument workbook) {
    final root = workbook.rootElement;
    var calcPr = root.getElement('calcPr');
    if (calcPr == null) {
      calcPr = XmlElement(XmlName('calcPr'));
      final anchor = root.getElement('definedNames') ?? root.getElement('sheets');
      final index = anchor == null ? root.children.length : root.children.indexOf(anchor) + 1;
      root.children.insert(index, calcPr);
    }
    calcPr.setAttribute('fullCalcOnLoad', '1');
  }

  static String _label(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // 'HH:mm' → fraction of a day, the way spreadsheets store times
  static double _toFraction(String time) {
    final parts = time.split(':');
    return (int.parse(parts[0]) * 60 + int.parse(parts[1])) / 1440;
  }

  static String _formatMinutes(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

class _Outcome {
  final bool wrote;
  final List<String> conflicts;
  const _Outcome(this.wrote, [this.conflicts = const []]);
}

class _Sheet {
  final XmlDocument doc;
  final List<String> strings;
  final Map<int, XmlElement> _rowsBySerial = {};
  final List<XmlElement> _rows;
  bool modified = false;

  _Sheet(this.doc, this.strings)
      : _rows = doc.findAllElements('row').toList() {
    for (final row in _rows) {
      final serial = double.tryParse(_cell(row, 'B')?.getElement('v')?.innerText ?? '');
      if (serial != null) _rowsBySerial[serial.floor()] = row;
    }
  }

  static final _epoch = DateTime.utc(1899, 12, 30);

  XmlElement? rowFor(DateTime date) => _rowsBySerial[
      DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays];

  int _rowNumber(XmlElement row) => int.parse(row.getAttribute('r')!);

  // ─── WRITING ────────────────────────────────────────────

  _Outcome writeTimes(XmlElement row, TimesheetEntry entry) {
    final conflicts = <String>[];
    var wrote = false;

    if (entry.hasTimes) {
      final start = _value(row, TimesheetFiller._start);
      final end = _value(row, TimesheetFiller._end);

      if (start == null && end == null) {
        _fillTimes(row, entry.start!, entry.end!);
        wrote = true;
      } else {
        final sheetText = start is int && end is int
            ? '${TimesheetFiller._formatMinutes(start)}–${TimesheetFiller._formatMinutes(end)}'
            : '"${start ?? end}"';
        final appText = '${entry.start}–${entry.end}';
        if (sheetText != appText) conflicts.add('sheet $sheetText, app $appText');
      }
    }

    if (entry.note != null) {
      final existing = _value(row, TimesheetFiller._notes);
      if (existing == null) {
        _setText(row, TimesheetFiller._notes, entry.note!,
            style: _cell(row, TimesheetFiller._notes)?.getAttribute('s'));
        wrote = true;
      } else if (existing != entry.note) {
        conflicts.add('note not added, cell has "$existing" (app: ${entry.note})');
      }
    }

    return _Outcome(wrote, conflicts);
  }

  _Outcome writeHoliday(XmlElement row, String name) {
    if (TimesheetFiller._timeColumns.any((col) => _value(row, col) != null)) {
      final existing = _value(row, TimesheetFiller._start);
      return existing == name
          ? const _Outcome(false)
          : _Outcome(false, ['holiday "$name" not added, row already has data']);
    }

    final template = _nearestRowAbove(row, (r) =>
        _value(r, TimesheetFiller._start) is String && _isMerged(r));
    final n = _rowNumber(row);

    _copyStyles(template, row, TimesheetFiller._timeColumns);
    for (final col in TimesheetFiller._timeColumns.skip(1)) {
      _clear(row, col);
    }
    _setText(row, TimesheetFiller._start, name,
        style: _cell(row, TimesheetFiller._start)?.getAttribute('s'));
    _merge('${TimesheetFiller._start}$n:${TimesheetFiller._total}$n');
    modified = true;
    return const _Outcome(true);
  }

  void _fillTimes(XmlElement row, String start, String end) {
    final n = _rowNumber(row);
    // Match the look of the days already filled in by hand
    final template = _nearestRowAbove(row, (r) => _value(r, TimesheetFiller._start) is int);
    _copyStyles(template, row, TimesheetFiller._timeColumns);

    _setNumber(row, TimesheetFiller._start, TimesheetFiller._toFraction(start));
    _setNumber(row, TimesheetFiller._end, TimesheetFiller._toFraction(end));
    _setNumber(row, TimesheetFiller._lunchCol, TimesheetFiller._lunch / 1440);
    _setFormula(row, TimesheetFiller._hours, '${TimesheetFiller._end}$n-${TimesheetFiller._start}$n');
    _setFormula(row, TimesheetFiller._total, '${TimesheetFiller._hours}$n-${TimesheetFiller._lunchCol}$n');
    modified = true;
  }

  // ─── CELLS ──────────────────────────────────────────────

  XmlElement? _cell(XmlElement row, String col) {
    final ref = '$col${row.getAttribute('r')}';
    return row.findElements('c').where((c) => c.getAttribute('r') == ref).firstOrNull;
  }

  // Cell content: minutes of the day for numbers, text for strings, null if
  // empty. Formulas don't count as data: they are part of the template.
  Object? _value(XmlElement row, String col) {
    final cell = _cell(row, col);
    if (cell == null || cell.getElement('f') != null) return null;
    final type = cell.getAttribute('t');
    if (type == 'inlineStr') {
      final text = cell.findAllElements('t').map((t) => t.innerText).join();
      return text.trim().isEmpty ? null : text;
    }
    final raw = cell.getElement('v')?.innerText;
    if (raw == null || raw.trim().isEmpty) return null;
    if (type == 's') {
      final index = int.tryParse(raw);
      final text = index != null && index < strings.length ? strings[index] : raw;
      return text.trim().isEmpty ? null : text;
    }
    if (type == 'str' || type == 'b' || type == 'e') return raw;
    final number = double.tryParse(raw);
    if (number == null) return raw;
    return ((number - number.floor()) * 1440).round() % 1440;
  }

  XmlElement _cellOrCreate(XmlElement row, String col) {
    final existing = _cell(row, col);
    if (existing != null) return existing;

    final cell = XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), '$col${row.getAttribute('r')}')]);
    // Cells must stay in column order within the row
    final after = row.findElements('c').where((c) =>
        _columnIndex(c.getAttribute('r')!) > _columnIndex(col)).firstOrNull;
    if (after == null) {
      row.children.add(cell);
    } else {
      row.children.insert(row.children.indexOf(after), cell);
    }
    return cell;
  }

  // Empties the cell's content but keeps its style
  void _reset(XmlElement cell) {
    cell.children.clear();
    cell.removeAttribute('t');
  }

  void _clear(XmlElement row, String col) {
    final cell = _cell(row, col);
    if (cell != null) _reset(cell);
  }

  void _setNumber(XmlElement row, String col, double value) {
    final cell = _cellOrCreate(row, col);
    _reset(cell);
    cell.children.add(XmlElement(XmlName('v'), [], [XmlText(value.toString())]));
  }

  // Keeps an existing formula (it may be part of a shared one) and only
  // drops its stale cached value; writes a plain formula otherwise
  void _setFormula(XmlElement row, String col, String formula) {
    final cell = _cellOrCreate(row, col);
    final existing = cell.getElement('f');
    _reset(cell);
    cell.children.add(existing ?? XmlElement(XmlName('f'), [], [XmlText(formula)]));
  }

  void _setText(XmlElement row, String col, String text, {String? style}) {
    final cell = _cellOrCreate(row, col);
    _reset(cell);
    if (style != null) cell.setAttribute('s', style);
    cell.setAttribute('t', 'inlineStr');
    cell.children.add(XmlElement(XmlName('is'), [], [
      XmlElement(XmlName('t'), [XmlAttribute(XmlName('xml:space'), 'preserve')], [XmlText(text)]),
    ]));
    modified = true;
  }

  void _copyStyles(XmlElement? from, XmlElement to, List<String> columns) {
    if (from == null) return;
    for (final col in columns) {
      final style = _cell(from, col)?.getAttribute('s');
      if (style != null) _cellOrCreate(to, col).setAttribute('s', style);
    }
  }

  XmlElement? _nearestRowAbove(XmlElement row, bool Function(XmlElement) test) {
    for (var i = _rows.indexOf(row) - 1; i >= 0; i--) {
      if (test(_rows[i])) return _rows[i];
    }
    return null;
  }

  // ─── MERGED CELLS ───────────────────────────────────────

  bool _isMerged(XmlElement row) {
    final ref = '${TimesheetFiller._start}${row.getAttribute('r')}';
    return doc.findAllElements('mergeCell')
        .any((m) => (m.getAttribute('ref') ?? '').startsWith('$ref:'));
  }

  void _merge(String ref) {
    final root = doc.rootElement;
    var merges = root.getElement('mergeCells');
    if (merges == null) {
      merges = XmlElement(XmlName('mergeCells'));
      // mergeCells goes right after sheetData (or sheetProtection etc. if present)
      final anchor = root.getElement('sheetData')!;
      var index = root.children.indexOf(anchor) + 1;
      for (final name in ['sheetCalcPr', 'sheetProtection', 'protectedRanges',
          'scenarios', 'autoFilter', 'sortState', 'dataConsolidate', 'customSheetViews']) {
        final e = root.getElement(name);
        if (e != null) index = root.children.indexOf(e) + 1;
      }
      root.children.insert(index, merges);
    }
    if (merges.findElements('mergeCell').any((m) => m.getAttribute('ref') == ref)) return;
    merges.children.add(XmlElement(XmlName('mergeCell'), [XmlAttribute(XmlName('ref'), ref)]));
    merges.setAttribute('count', merges.findElements('mergeCell').length.toString());
  }

  static int _columnIndex(String ref) {
    var index = 0;
    for (final ch in ref.codeUnits) {
      if (ch < 65 || ch > 90) break;
      index = index * 26 + (ch - 64);
    }
    return index;
  }
}
