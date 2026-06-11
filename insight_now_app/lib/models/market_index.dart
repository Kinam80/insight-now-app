// lib/models/market_index.dart
class MarketIndex {
  final String name;
  final String value;
  final String change;
  final bool isUp;
  final String nation;

  MarketIndex({required this.name, required this.value, required this.change, required this.isUp, required this.nation});

  factory MarketIndex.fromJson(Map<String, dynamic> json) {
    return MarketIndex(
      name: json['name'] ?? '',
      value: json['value'] ?? '0.00',
      change: json['change'] ?? '0.00%',
      isUp: json['isUp'] ?? false,
      nation: json['nation'] ?? '',
    );
  }
}