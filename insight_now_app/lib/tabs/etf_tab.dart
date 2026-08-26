import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../screens/detail_screen.dart';

class EtfTab extends StatefulWidget {
  const EtfTab({super.key});

  @override
  State<EtfTab> createState() => _EtfTabState();
}

class _EtfTabState extends State<EtfTab> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _etfs = [];
  String _searchQuery = '';
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _isLoading = _etfs.isEmpty;
      });
    }

    try {
      final response = await http
          .get(Uri.parse(ApiConstants.etfEndpoint))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('서버 응답 ${response.statusCode}');
      }

      final parsed = json.decode(response.body);
      if (parsed is! List) {
        throw const FormatException('ETF 목록 형식이 올바르지 않습니다.');
      }

      if (!mounted) return;
      setState(() {
        _etfs = parsed;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ETF 데이터를 불러오지 못했습니다.\n네트워크 상태를 확인한 뒤 다시 시도해 주세요.';
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filteredEtfs {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _etfs;
    return _etfs.where((item) {
      final ticker = (item['ticker'] ?? '').toString().toLowerCase();
      final name = (item['name'] ?? '').toString().toLowerCase();
      return ticker.contains(query) || name.contains(query);
    }).toList();
  }

  String _formatPrice(dynamic rawPrice, String ticker) {
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse('$rawPrice');
    if (price == null) return '가격 업데이트 대기';
    final precision = price >= 100 ? 2 : 4;
    final isKoreanTicker = RegExp(r'^\d{6}(?:\.K[QS])?$').hasMatch(ticker);
    final currency = isKoreanTicker ? '₩ ' : r'$ ';

    return '$currency${price.toStringAsFixed(precision)}';
  }

  @override
  Widget build(BuildContext context) {
    final filteredEtfs = _filteredEtfs;

    return Scaffold(
      backgroundColor: const Color(0xFF081426),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(filteredEtfs.length),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF55D8D3),
                      ),
                    )
                  : _errorMessage != null
                  ? _buildErrorState()
                  : _buildEtfList(filteredEtfs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int visibleCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF102C4A), const Color(0xFF081426)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF55D8D3).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.pie_chart_rounded,
                  color: Color(0xFF55D8D3),
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ETF 인사이트',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Yahoo Finance 기반 자동 동기화 유니버스',
                      style: TextStyle(color: Color(0xFF9CB4CC), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadData,
                tooltip: '새로고침',
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFB4C8DC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: const Color(0xFF55D8D3),
            decoration: InputDecoration(
              hintText: '티커 또는 ETF 이름 검색',
              hintStyle: const TextStyle(color: Color(0xFF7791AA)),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF8CA8C1),
              ),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF8CA8C1),
                      ),
                    ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFF55D8D3),
                  width: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.sync_rounded,
                color: Color(0xFF55D8D3),
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                '$visibleCount개 ETF 표시 중',
                style: const TextStyle(color: Color(0xFF9CB4CC), fontSize: 12),
              ),
              const Spacer(),
              const Text(
                '6시간 단위 갱신',
                style: TextStyle(color: Color(0xFF7791AA), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEtfList(List<dynamic> etfs) {
    if (etfs.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF55D8D3),
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: const [
            SizedBox(height: 130),
            Icon(Icons.search_off_rounded, color: Color(0xFF7791AA), size: 48),
            SizedBox(height: 14),
            Center(
              child: Text(
                '검색 조건에 맞는 ETF가 없습니다.',
                style: TextStyle(color: Color(0xFFB4C8DC), fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF55D8D3),
      onRefresh: _loadData,
      child: Scrollbar(
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: etfs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _buildEtfCard(etfs[index]),
        ),
      ),
    );
  }

  Widget _buildEtfCard(dynamic etf) {
    final ticker = (etf['ticker'] ?? '').toString().toUpperCase();
    final name = (etf['name'] ?? '이름 정보 없음').toString();
    final priceText = _formatPrice(etf['price'], ticker);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DetailScreen(etfData: etf)),
          );
        },
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF11223A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF55D8D3).withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  ticker.length > 4 ? ticker.substring(0, 4) : ticker,
                  style: const TextStyle(
                    color: Color(0xFF75ECE4),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticker,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF75ECE4),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '자동 갱신 · 상세 분석 보기',
                      style: TextStyle(color: Color(0xFF7791AA), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '최근가',
                    style: TextStyle(color: Color(0xFF7791AA), fontSize: 10),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    priceText,
                    style: const TextStyle(
                      color: Color(0xFFFFD166),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8CA8C1),
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFF8CA8C1),
              size: 46,
            ),
            const SizedBox(height: 14),
            Text(
              _errorMessage ?? 'ETF 데이터를 불러오지 못했습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB4C8DC), height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadData,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF55D8D3),
                foregroundColor: const Color(0xFF071523),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
