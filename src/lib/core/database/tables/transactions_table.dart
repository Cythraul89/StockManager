import 'package:drift/drift.dart';
import 'stocks_table.dart';
import 'decimal_converter.dart';

@DataClassName('TransactionRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get stockId =>
      text().references(Stocks, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // 'buy' | 'sell'
  DateTimeColumn get executedAt => dateTime()();
  TextColumn get shares => text().map(const DecimalConverter())();
  TextColumn get pricePerShare => text().map(const DecimalConverter())();
  TextColumn get currency => text()();
  TextColumn get fees =>
      text().map(const DecimalConverter()).withDefault(const Constant('0'))();
  TextColumn get notes => text().nullable()();
  TextColumn get externalRef => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
