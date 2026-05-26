import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/features/settings/parsers/flatex_order_parser.dart';

// The parser skips the first line as a header regardless of its content.
const _header =
    'Kategorie;Name;ISIN/WKN;Art;Handelsplatz;Auftragsnummer;Datum/Uhrzeit;'
    'Status;Menge;Einheit;Ausführungspreis;Ausführungswährung;Limit;Limit-Währung;Stop';

String csv(List<String> rows) => '$_header\n${rows.join('\n')}';

void main() {
  group('Regular limit buy', () {
    test('imports with limit price from col 12', () {
      final result = FlatexOrderParser.parse(csv([
        'Aktie;Allianz SE;DE0008404005;Kauf;XETRA;OR001;'
            '15.01.2024 / 10:00:00;Ausgeführt;10;Stück;;EUR;200,00;EUR;',
      ]));
      expect(result.importable.length, 1);
      expect(result.importable.first.shares.toDouble(), 10.0);
      expect(result.importable.first.pricePerShare.toDouble(), 200.0);
      expect(result.importable.first.currency, 'EUR');
    });
  });

  group('KVG savings-plan rows', () {
    // Full 15-column row (trailing empty cols present)
    test('EUR-unit, 15 cols (trailing ;;;;)', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares Core MSCI World;IE00B4L5Y983;Kauf;KVG;OR002;'
            '15.01.2024 / 09:00:00;Ausgeführt;50,00;EUR;100,00;EUR;;;',
      ]));
      expect(result.importable.length, 1,
          reason: 'EUR-unit KVG with trailing cols should import');
      if (result.importable.isNotEmpty) {
        expect(result.importable.first.shares.toDouble(), closeTo(0.5, 1e-6));
        expect(result.importable.first.pricePerShare.toDouble(), 100.0);
        expect(result.importable.first.currency, 'EUR');
      }
    });

    // 12-column row — Flatex omits trailing empty cols for savings-plan rows
    test('EUR-unit, 12 cols (no trailing ;;;;)', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares Core MSCI World;IE00B4L5Y983;Kauf;KVG;OR002;'
            '15.01.2024 / 09:00:00;Ausgeführt;50,00;EUR;100,00;EUR',
      ]));
      expect(result.importable.length, 1,
          reason: 'EUR-unit KVG without trailing cols must import');
      if (result.importable.isNotEmpty) {
        expect(result.importable.first.shares.toDouble(), closeTo(0.5, 1e-6));
        expect(result.importable.first.pricePerShare.toDouble(), 100.0);
      }
    });

    // Stück-unit variant (menge = share count, exec price in col 10)
    test('Stück-unit, 15 cols', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares Core MSCI World;IE00B4L5Y983;Kauf;KVG;OR003;'
            '15.01.2024 / 09:00:00;Ausgeführt;0,50;Stück;100,00;EUR;;;',
      ]));
      expect(result.importable.length, 1);
      if (result.importable.isNotEmpty) {
        expect(result.importable.first.shares.toDouble(), closeTo(0.5, 1e-6));
        expect(result.importable.first.pricePerShare.toDouble(), 100.0);
      }
    });

    test('Stück-unit, 12 cols (no trailing ;;;;)', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares Core MSCI World;IE00B4L5Y983;Kauf;KVG;OR003;'
            '15.01.2024 / 09:00:00;Ausgeführt;0,50;Stück;100,00;EUR',
      ]));
      expect(result.importable.length, 1,
          reason: 'Stück KVG without trailing cols must import');
    });

    // German decimal thousands separator
    test('German decimal thousands separator in menge', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares Core MSCI World;IE00B4L5Y983;Kauf;KVG;OR004;'
            '15.01.2024 / 09:00:00;Ausgeführt;1.000,00;EUR;500,00;EUR;;;',
      ]));
      expect(result.importable.length, 1);
      if (result.importable.isNotEmpty) {
        // shares = 1000 / 500 = 2
        expect(result.importable.first.shares.toDouble(), closeTo(2.0, 1e-6));
      }
    });
  });

  group('Bruchstücke (fractional fill)', () {
    test('EUR-unit Bruchstück derives shares from amount / price', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares World;IE00B4L5Y983;Kauf;XETRA;OR005;'
            '15.01.2024 / 14:00:00;Ausgeführt;25,00;EUR;98,50;EUR;;;',
      ]));
      expect(result.importable.length, 1);
      if (result.importable.isNotEmpty) {
        expect(result.importable.first.shares.toDouble(),
            closeTo(25.0 / 98.5, 1e-4));
      }
    });
  });

  group('Skip counters', () {
    test('non-executed rows increment skippedNotExecuted', () {
      final result = FlatexOrderParser.parse(csv([
        'Aktie;Allianz SE;DE0008404005;Kauf;XETRA;OR006;'
            '15.01.2024 / 10:00:00;Offen;10;Stück;;EUR;200,00;EUR;',
      ]));
      expect(result.skippedNotExecuted, 1);
      expect(result.importable, isEmpty);
    });

    test('empty-unit rows increment skippedFractional', () {
      final result = FlatexOrderParser.parse(csv([
        'Aktie;Allianz SE;DE0008404005;Kauf;XETRA;OR007;'
            '15.01.2024 / 10:00:00;Ausgeführt;10;;EUR;EUR;200,00;EUR;',
      ]));
      expect(result.skippedFractional, 1);
    });

    test('rows with no price increment skippedNoPrice', () {
      final result = FlatexOrderParser.parse(csv([
        'Aktie;Allianz SE;DE0008404005;Kauf;XETRA;OR008;'
            '15.01.2024 / 10:00:00;Ausgeführt;10;Stück;;;;',
      ]));
      expect(result.skippedNoPrice, 1);
    });
  });

  group('ISIN/WKN combined field', () {
    test('splits ISIN/WKN and uses ISIN', () {
      final result = FlatexOrderParser.parse(csv([
        'ETF;iShares Core MSCI World;IE00B4L5Y983/A1JX51;Kauf;KVG;OR009;'
            '15.01.2024 / 09:00:00;Ausgeführt;50,00;EUR;100,00;EUR;;;',
      ]));
      expect(result.importable.length, 1);
      if (result.importable.isNotEmpty) {
        expect(result.importable.first.isin, 'IE00B4L5Y983');
      }
    });
  });
}
