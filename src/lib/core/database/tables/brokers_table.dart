import 'package:drift/drift.dart';

@DataClassName('BrokerRow')
class Brokers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
