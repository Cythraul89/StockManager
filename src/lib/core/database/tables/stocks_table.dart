import 'package:drift/drift.dart';
import 'brokers_table.dart';

@DataClassName('StockRow')
class Stocks extends Table {
  TextColumn get id => text()();
  TextColumn get brokerId =>
      text().references(Brokers, #id, onDelete: KeyAction.restrict)();
  TextColumn get isin => text().unique()();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  TextColumn get exchange => text()();
  TextColumn get currency => text()();
  BoolColumn get dripEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get assetType =>
      text().withDefault(const Constant('stock'))();

  @override
  Set<Column> get primaryKey => {id};
}
