import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:clock_in/services/timesheet_filler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

// Minimal workbook shaped like the timesheet template: one row per day of
// September 2026 (row 2 = Sep 1), date serials in column B
List<int> _workbook({Map<int, String> extraCells = const {}}) {
  final rows = StringBuffer();
  for (var day = 1; day <= 30; day++) {
    final r = day + 1;
    final serial = 46265 + day; // 2026-09-01 is 46266
    rows.write('<row r="$r"><c r="B$r" s="4"><v>$serial</v></c>'
        '${extraCells[r] ?? '<c r="C$r" s="46"/><c r="D$r" s="46"/>'}</row>');
  }

  final archive = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml',
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Timesheets 2026" sheetId="1" r:id="rId1"/></sheets>'
        '<definedNames/><calcPr/></workbook>'))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>'))
    ..addFile(ArchiveFile.string('xl/sharedStrings.xml',
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>Visual Expo Event</t></si></sst>'))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>$rows</sheetData></worksheet>'));
  return ZipEncoder().encodeBytes(archive);
}

// Sep 3: filled by hand, 08:00–16:30, with a note
const _handFilled = '<c r="C4" s="5"><v>0.3333333333333333</v></c>'
    '<c r="D4" s="5"><v>0.6875</v></c>'
    '<c r="E4" s="5" t="str"><f>D4-C4</f><v>08:30:00</v></c>'
    '<c r="F4" s="5"><v>0.020833333333333332</v></c>'
    '<c r="G4" s="5" t="str"><f>E4-F4</f><v>08:00:00</v></c>'
    '<c r="H4" s="2" t="s"><v>0</v></c>';

XmlDocument _part(List<int> xlsx, String name) => XmlDocument.parse(
    utf8.decode(ZipDecoder().decodeBytes(xlsx).findFile(name)!.content));

XmlElement? _cell(XmlDocument sheet, String ref) => sheet
    .findAllElements('c')
    .where((c) => c.getAttribute('r') == ref)
    .firstOrNull;

void main() {
  final xlsx = _workbook(extraCells: {4: _handFilled});

  test('fills an empty row with times, lunch and formulas styled like filled rows', () {
    final result = TimesheetFiller.fill(xlsx, [
      TimesheetEntry(date: DateTime(2026, 9, 10), start: '08:00', end: '17:15'),
    ]);
    expect(result.filled, ['2026-09-10']);
    expect(result.conflicts, isEmpty);

    final sheet = _part(result.bytes, 'xl/worksheets/sheet1.xml');
    expect(_cell(sheet, 'C11')!.innerText, '0.3333333333333333');
    expect(_cell(sheet, 'D11')!.innerText, (17.25 / 24).toString());
    expect(_cell(sheet, 'F11')!.innerText, (30 / 1440).toString());
    expect(_cell(sheet, 'E11')!.getElement('f')!.innerText, 'D11-C11');
    expect(_cell(sheet, 'G11')!.getElement('f')!.innerText, 'E11-F11');
    expect(_cell(sheet, 'C11')!.getAttribute('s'), '5');

    final workbook = _part(result.bytes, 'xl/workbook.xml');
    expect(workbook.findAllElements('calcPr').single.getAttribute('fullCalcOnLoad'), '1');
  });

  test('leaves rows with the same data alone without reporting them', () {
    final result = TimesheetFiller.fill(xlsx, [
      TimesheetEntry(date: DateTime(2026, 9, 3), start: '08:00', end: '16:30'),
    ]);
    expect(result.filled, isEmpty);
    expect(result.conflicts, isEmpty);
  });

  test('reports rows with different data and does not overwrite them', () {
    final result = TimesheetFiller.fill(xlsx, [
      TimesheetEntry(date: DateTime(2026, 9, 3), start: '08:00', end: '17:00',
          note: 'Overtime 18:00–19:00'),
    ]);
    expect(result.filled, isEmpty);
    expect(result.conflicts, [
      '2026-09-03: sheet 08:00–16:30, app 08:00–17:00',
      '2026-09-03: note not added, cell has "Visual Expo Event" (app: Overtime 18:00–19:00)',
    ]);
    final sheet = _part(result.bytes, 'xl/worksheets/sheet1.xml');
    expect(_cell(sheet, 'D4')!.innerText, '0.6875');
  });

  test('writes extra sessions as a note', () {
    final result = TimesheetFiller.fill(xlsx, [
      TimesheetEntry(date: DateTime(2026, 9, 6), note: 'Overtime 09:00–12:00'),
    ]);
    expect(result.filled, ['2026-09-06']);
    final sheet = _part(result.bytes, 'xl/worksheets/sheet1.xml');
    final note = _cell(sheet, 'H7')!;
    expect(note.getAttribute('t'), 'inlineStr');
    expect(note.innerText, 'Overtime 09:00–12:00');
    // Inserted after the existing cells of the row, keeping column order
    expect(note.parentElement!.childElements.last, note);
  });

  test('writes holidays across the time columns', () {
    final result = TimesheetFiller.fill(xlsx, [
      TimesheetEntry(date: DateTime(2026, 9, 14), holidayName: 'Show Day'),
    ]);
    expect(result.filled, ['2026-09-14']);
    final sheet = _part(result.bytes, 'xl/worksheets/sheet1.xml');
    expect(_cell(sheet, 'C15')!.innerText, 'Show Day');
    expect(sheet.findAllElements('mergeCell').single.getAttribute('ref'), 'C15:G15');
  });

  test('skips years without a sheet and keeps untouched parts intact', () {
    final result = TimesheetFiller.fill(xlsx, [
      TimesheetEntry(date: DateTime(2027, 1, 4), start: '08:00', end: '16:00'),
    ]);
    expect(result.filled, isEmpty);
    expect(result.skipped, ['2027: no "Timesheets 2027" sheet in the file']);

    final before = ZipDecoder().decodeBytes(xlsx);
    final after = ZipDecoder().decodeBytes(result.bytes);
    for (final file in before.files) {
      expect(after.findFile(file.name)!.content, file.content, reason: file.name);
    }
  });

  test('rejects files that are not xlsx', () {
    expect(() => TimesheetFiller.fill(utf8.encode('Date,Clock In'), const []),
        throwsA(isA<TimesheetException>()));
  });
}
