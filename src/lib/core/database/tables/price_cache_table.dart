import 'package:drift/drift.dart';
import 'stocks_table.dart';
import 'decimal_converter.dart';

@DataClassName('PriceCacheRow')
class PriceCache extends Table {
  // stock_id is both PK and FK — one row per stock
  TextColumn get stockId =>
      text().references(Stocks, #id, onDelete: KeyAction.cascade)();
  TextColumn get price => text().map(const DecimalConverter())();
  TextColumn get currency => text()();
  DateTimeColumn get fetchedAt => dateTime()();
  BoolColumn get manualOverride =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {stockId};
}
