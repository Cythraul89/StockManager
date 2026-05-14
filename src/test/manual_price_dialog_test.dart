import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_manager/features/stocks/widgets/manual_price_dialog.dart';

Widget _app({
  required String initialCurrency,
  required void Function(({String currency, Decimal price})?) onResult,
}) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () async {
          final result = await showDialog<({String currency, Decimal price})>(
            context: ctx,
            builder: (_) =>
                ManualPriceDialog(initialCurrency: initialCurrency),
          );
          onResult(result);
        },
        child: const Text('Open'),
      ),
    ),
  );
}

void main() {
  group('ManualPriceDialog', () {
    testWidgets('shows title and initial currency', (tester) async {
      await tester.pumpWidget(_app(initialCurrency: 'EUR', onResult: (_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Set manual price'), findsOneWidget);
      expect(find.text('EUR'), findsAtLeastNWidgets(1));
    });

    testWidgets('Cancel closes dialog and returns null', (tester) async {
      // Sentinel value — will only be overwritten if onResult is called.
      ({String currency, Decimal price})? result =
          (currency: 'sentinel', price: Decimal.zero);
      await tester.pumpWidget(
          _app(initialCurrency: 'EUR', onResult: (r) => result = r));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Set manual price'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('Save with empty price shows validation error', (tester) async {
      await tester.pumpWidget(_app(initialCurrency: 'EUR', onResult: (_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a positive number'), findsOneWidget);
      expect(find.text('Set manual price'), findsOneWidget); // dialog stays open
    });

    testWidgets('Save with zero price shows validation error', (tester) async {
      await tester.pumpWidget(_app(initialCurrency: 'EUR', onResult: (_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a positive number'), findsOneWidget);
    });

    testWidgets('Save with negative price shows validation error',
        (tester) async {
      await tester.pumpWidget(_app(initialCurrency: 'EUR', onResult: (_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '-5');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a positive number'), findsOneWidget);
    });

    testWidgets('Save with valid price closes dialog and returns record',
        (tester) async {
      ({String currency, Decimal price})? result;
      await tester.pumpWidget(
          _app(initialCurrency: 'EUR', onResult: (r) => result = r));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '42.50');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Set manual price'), findsNothing);
      expect(result?.price, Decimal.parse('42.50'));
      expect(result?.currency, 'EUR');
    });

    testWidgets('error text clears when user types', (tester) async {
      await tester.pumpWidget(_app(initialCurrency: 'USD', onResult: (_) {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Trigger error
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a positive number'), findsOneWidget);

      // Start typing — error should disappear
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      expect(find.text('Enter a positive number'), findsNothing);
    });

    testWidgets('Save uses updated currency from dropdown', (tester) async {
      ({String currency, Decimal price})? result;
      await tester.pumpWidget(
          _app(initialCurrency: 'EUR', onResult: (r) => result = r));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Open the currency dropdown and select USD
      await tester.tap(find.text('EUR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '100');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result?.currency, 'USD');
      expect(result?.price, Decimal.parse('100'));
    });
  });
}
