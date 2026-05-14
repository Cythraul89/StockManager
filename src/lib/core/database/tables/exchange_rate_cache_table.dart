import 'package:drift/drift.dart';
import 'decimal_converter.dart';

@DataClassName('ExchangeRateCacheRow')
class ExchangeRateCache extends Table {
  TextColumn get base => text()();
  TextColumn get target => text()();
  TextColumn get rate => text().map(const DecimalConverter())();
  DateTimeColumn get fetchedAt => dateTime()();
  // when true, the TTL is bypassed — user-set rate used until removed
  BoolColumn get manualOverride =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {base, target};
}
