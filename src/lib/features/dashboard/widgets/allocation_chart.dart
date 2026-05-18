import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/models/asset_type.dart';
import '../dashboard_provider.dart';

enum _View { holdings, type }

class AllocationChart extends StatefulWidget {
  const AllocationChart({super.key, required this.summary});

  final PortfolioSummary summary;

  @override
  State<AllocationChart> createState() => _AllocationChartState();
}

class _AllocationChartState extends State<AllocationChart> {
  int? _touched;
  _View _view = _View.holdings;

  // Palette for the Holdings view (index-based).
  static const _holdingPalette = [
    Color(0xFF4C7CE5),
    Color(0xFF2DB87D),
    Color(0xFFE5A23C),
    Color(0xFFE55C5C),
    Color(0xFF9C6DE5),
    Color(0xFF36B8C8),
    Color(0xFFE5784C),
    Color(0xFF73B83E),
  ];

  // Fixed colours per asset type for the Type view.
  static const _typeColor = {
    AssetType.stock: Color(0xFF4C7CE5),
    AssetType.etf: Color(0xFF2DB87D),
    AssetType.etc: Color(0xFFE5784C),
    AssetType.fund: Color(0xFF9C6DE5),
    AssetType.bond: Color(0xFFE5A23C),
    AssetType.warrant: Color(0xFF8E8E8E),
    AssetType.other: Color(0xFFB0B0B0),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final priced = widget.summary.stockItems
        .where((i) =>
            i.hasPrice && !i.missingRate && i.currentValue > Decimal.zero)
        .toList()
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    if (priced.isEmpty) return const SizedBox.shrink();

    final slices =
        _view == _View.holdings ? _holdingSlices(priced) : _typeSlices(priced);
    final total = slices.fold(Decimal.zero, (s, sl) => s + sl.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Allocation', style: theme.textTheme.titleMedium),
                const Spacer(),
                SegmentedButton<_View>(
                  segments: const [
                    ButtonSegment(
                      value: _View.holdings,
                      label: Text('Holdings'),
                    ),
                    ButtonSegment(
                      value: _View.type,
                      label: Text('Type'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) =>
                      setState(() {
                        _view = s.first;
                        _touched = null;
                      }),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          setState(() {
                            _touched = event.isInterestedForInteractions
                                ? response
                                    ?.touchedSection
                                    ?.touchedSectionIndex
                                : null;
                          });
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 2,
                      centerSpaceRadius: 38,
                      sections: List.generate(slices.length, (i) {
                        final isTouched = i == _touched;
                        return PieChartSectionData(
                          value: slices[i].value.toDouble(),
                          color: slices[i].color,
                          radius: isTouched ? 56 : 46,
                          showTitle: false,
                        );
                      }),
                    ),
                    duration: const Duration(milliseconds: 150),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _buildLegend(context, slices, total)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_Slice> _holdingSlices(List<StockSummaryItem> priced) {
    const maxSlices = 7;
    final slices = <_Slice>[];
    for (var i = 0; i < priced.length && i < maxSlices; i++) {
      slices.add(_Slice(
        label: priced[i].stock.symbol,
        value: priced[i].currentValue,
        color: _holdingPalette[i % _holdingPalette.length],
      ));
    }
    if (priced.length > maxSlices) {
      final rest = priced
          .skip(maxSlices)
          .fold(Decimal.zero, (sum, it) => sum + it.currentValue);
      slices.add(_Slice(
        label: 'Others',
        value: rest,
        color: _holdingPalette[maxSlices % _holdingPalette.length],
      ));
    }
    return slices;
  }

  List<_Slice> _typeSlices(List<StockSummaryItem> priced) {
    final totals = <AssetType, Decimal>{};
    for (final item in priced) {
      final t = item.stock.assetType;
      totals[t] = (totals[t] ?? Decimal.zero) + item.currentValue;
    }
    return (totals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => _Slice(
              label: e.key.label,
              value: e.value,
              color: _typeColor[e.key] ?? const Color(0xFFB0B0B0),
            ))
        .toList();
  }

  Widget _buildLegend(
      BuildContext context, List<_Slice> slices, Decimal total) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: slices.map((sl) {
        final pct = total > Decimal.zero
            ? (sl.value.toRational() /
                    total.toRational() *
                    Decimal.fromInt(100).toRational())
                .toDecimal(scaleOnInfinitePrecision: 1)
            : Decimal.zero;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: sl.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sl.label,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Slice {
  const _Slice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final Decimal value;
  final Color color;
}
