import 'package:drift/drift.dart';
import 'decimal_converter.dart';

@DataClassName('SettingsRow')
class Settings extends Table {
  // Always a single row with id = 1
  IntColumn get id => integer()();
  TextColumn get preferredCurrency =>
      text().withDefault(const Constant('EUR'))();
  TextColumn get nextcloudUrl => text().nullable()();
  TextColumn get nextcloudUsername => text().nullable()();
  TextColumn get nextcloudPath =>
      text().withDefault(const Constant('/StockManager/'))();
  // 'system' | 'light' | 'dark'
  TextColumn get theme => text().withDefault(const Constant('system'))();
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(true))();
  TextColumn get priceAlertThresholdPct =>
      text().map(const DecimalConverter()).withDefault(const Constant('5'))();
  IntColumn get dividendAlertDays => integer().withDefault(const Constant(3))();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  // How many previous ODS exports to keep on Nextcloud (0 = keep all)
  IntColumn get nextcloudKeepExports =>
      integer().withDefault(const Constant(5))();
  // ChartRange.label stored as text, e.g. '1M', '1Y'
  TextColumn get sparklineRange =>
      text().withDefault(const Constant('1M'))();
  // 'yahoo' | 'finnhub'
  TextColumn get marketDataProvider =>
      text().withDefault(const Constant('yahoo'))();

  @override
  Set<Column> get primaryKey => {id};
}
