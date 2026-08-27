import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class DetailScreen extends StatefulWidget {
  final Map<String, dynamic>? etfData;
  final String? ticker;
  final String? postId;

  const DetailScreen({super.key, this.etfData, this.ticker, this.postId})
    : assert(etfData != null || ticker != null || postId != null);

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.etfData != null) {
      _data = widget.etfData;
      _isLoading = false;
    } else {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    final Uri url = widget.ticker != null
        ? Uri.parse('${ApiConstants.baseUrl}/api/etfs/${widget.ticker}')
        : Uri.parse('${ApiConstants.postsDetailEndpoint}${widget.postId}');

    try {
      final response = await http.get(url);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          setState(() {
            _data = decoded;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _errorMessage = '상세 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '네트워크 상태를 확인한 뒤 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('상세 정보')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('상세 정보')),
        backgroundColor: const Color(0xFF0A192F),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.amber, size: 48),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? '상세 정보를 불러오지 못했습니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _fetchDetail,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;
    final isEtf = widget.etfData != null || widget.ticker != null;
    final name = data['name'] ?? '종목명 없음';
    final ticker = (data['ticker'] ?? widget.ticker ?? '')
        .toString()
        .toUpperCase();
    final price = data['price'];
    final weight = data['weight'];
    final description =
        (data['description']?.toString().trim().isNotEmpty ?? false)
        ? data['description'].toString()
        : _fallbackEtfDescription(ticker, name.toString());
    final isLocked = !isEtf && data['is_locked'] == true;

    return Scaffold(
      appBar: AppBar(title: Text(isEtf ? '$name 상세' : '분석 상세')),
      backgroundColor: const Color(0xFF0A192F),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: isLocked
            ? _buildLockedContent(data)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEtf ? name : (data['title'] ?? '제목 없음'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),
                  if (isEtf)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticker,
                          style: const TextStyle(
                            color: Color(0xFF7DECE2),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '현재가: ${_formatEtfPrice(price, ticker)}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          weight == null || weight == 0
                              ? 'Yahoo Finance 자동 동기화 종목'
                              : '포트폴리오 비중: $weight%',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'ETF 상세 설명',
                          style: TextStyle(
                            color: Color(0xFFFFD166),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        MarkdownBody(
                          data: description,
                          styleSheet: _darkMarkdownStyleSheet(),
                        ),
                      ],
                    )
                  else
                    MarkdownBody(
                      data: data['content'] ?? '내용이 준비되지 않았습니다.',
                      styleSheet: _darkMarkdownStyleSheet(),
                    ),
                ],
              ),
      ),
    );
  }

  MarkdownStyleSheet _darkMarkdownStyleSheet() {
    const body = TextStyle(fontSize: 16, height: 1.65, color: Colors.white);
    return MarkdownStyleSheet(
      p: body,
      h1: const TextStyle(
        fontSize: 23,
        height: 1.35,
        color: Color(0xFFFFD166),
        fontWeight: FontWeight.w800,
      ),
      h2: const TextStyle(
        fontSize: 20,
        height: 1.4,
        color: Color(0xFF7DECE2),
        fontWeight: FontWeight.w800,
      ),
      h3: const TextStyle(
        fontSize: 18,
        height: 1.45,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      h4: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      h5: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      h6: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
      strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      em: const TextStyle(color: Color(0xFFB8C7DB)),
      listBullet: const TextStyle(color: Color(0xFFFFD166)),
      blockquote: const TextStyle(color: Color(0xFFB8C7DB), height: 1.6),
      tableHead: const TextStyle(
        color: Color(0xFFFFD166),
        fontWeight: FontWeight.w800,
      ),
      tableBody: const TextStyle(color: Colors.white),
      tableBorder: TableBorder.all(color: const Color(0xFF6E819C)),
    );
  }

  String _formatEtfPrice(dynamic rawPrice, String ticker) {
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse('$rawPrice');
    if (price == null) return '가격 업데이트 대기';
    final isKoreanTicker = RegExp(r'^\d{6}(?:\.K[QS])?$').hasMatch(ticker);
    final currency = isKoreanTicker ? '₩ ' : r'$ ';
    return '$currency${price.toStringAsFixed(price >= 100 ? 2 : 4)}';
  }

  String _fallbackEtfDescription(String ticker, String name) {
    return '''## $ticker ETF 한눈에 보기

**$name**은(는) 자동 동기화된 ETF입니다.

### 투자 전 확인하세요
- 어떤 지수·산업·자산을 추종하는지
- 총보수와 거래량이 적절한지
- 편입 종목과 분배 정책이 내 투자 목적에 맞는지

> 상세 설명은 다음 자동 갱신에서 최신 ETF 정보와 함께 보강됩니다.''';
  }

  Widget _buildLockedContent(Map<String, dynamic> data) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Colors.amber, size: 52),
            const SizedBox(height: 16),
            Text(
              data['title'] ?? '구독 전용 콘텐츠',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              data['message'] ?? '이 콘텐츠는 권한 확인 후 볼 수 있습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
