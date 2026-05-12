import 'package:drift/drift.dart';
import 'stocks_table.dart';

@DataClassName('StockSplitRow')
class StockSplits extends Table {
  TextColumn get id => text()();
  TextColumn get stockId =>
      text().references(Stocks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  IntColumn get fromShares => integer()();
  IntColumn get toShares => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
