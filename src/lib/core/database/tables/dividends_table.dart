import 'package:drift/drift.dart';
import 'stocks_table.dart';
import 'decimal_converter.dart';

@DataClassName('DividendRow')
class Dividends extends Table {
  TextColumn get id => text()();
  TextColumn get stockId =>
      text().references(Stocks, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // 'paid' | 'expected'
  DateTimeColumn get date => dateTime()();
  TextColumn get amountPerShare => text().map(const DecimalConverter())();
  // null for 'expected' rows — calculated on read from current holdings
  TextColumn get totalAmount => text().nullable().map(const DecimalConverter())();
  TextColumn get currency => text()();
  TextColumn get withholdingTax =>
      text().nullable().map(const DecimalConverter())();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
