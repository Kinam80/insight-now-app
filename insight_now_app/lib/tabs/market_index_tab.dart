import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/ad_config.dart';
import '../models/market_index.dart';
import '../screens/detail_screen.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';

const Color backgroundColor = Color(0xFF0A192F);
const Color cardColor = Color(0xFF172A45);
const Color goldAccent = Color(0xFFD4AF37);
const Color mintAccent = Color(0xFF4FD1C5);

class MarketIndexTab extends StatefulWidget {
  const MarketIndexTab({super.key});

  @override
  State<MarketIndexTab> createState() => _MarketIndexTabState();
}

class _MarketIndexTabState extends State<MarketIndexTab>
    with SingleTickerProviderStateMixin {
  static const List<Map<String, String>> _knowledgeItems = [
    {
      'term': 'PBR',
      'subtitle': '주가순자산비율 · 기업 자산 대비 주가',
      'definition':
          'PBR(Price to Book Ratio)은 주가를 주당순자산가치(BPS)로 나눈 값입니다. 기업이 보유한 순자산과 비교해 시장이 해당 기업을 어느 정도로 평가하는지 가늠할 때 사용합니다.',
      'formula': 'PBR = 주가 ÷ 주당순자산가치(BPS)',
      'tip': '낮은 PBR만으로 저평가라고 단정할 수는 없습니다. 수익성·부채·산업 특성을 함께 확인하세요.',
      'icon': 'PBR',
    },
    {
      'term': 'PER',
      'subtitle': '주가수익비율 · 이익 대비 주가',
      'definition':
          'PER(Price Earnings Ratio)은 주가를 주당순이익(EPS)으로 나눈 값입니다. 현재 이익 기준으로 투자자가 기업 가치에 몇 배를 지불하고 있는지 보여줍니다.',
      'formula': 'PER = 주가 ÷ 주당순이익(EPS)',
      'tip': '성장 산업은 PER이 높을 수 있습니다. 동일 업종과 이익 성장률을 함께 비교하는 것이 중요합니다.',
      'icon': 'PER',
    },
    {
      'term': 'ROE',
      'subtitle': '자기자본이익률 · 자본 활용 효율',
      'definition':
          'ROE(Return on Equity)는 기업이 자기자본을 활용해 얼마나 효율적으로 이익을 냈는지 나타내는 지표입니다.',
      'formula': 'ROE = 당기순이익 ÷ 자기자본 × 100',
      'tip': '높은 ROE가 지속되는지, 부채를 과도하게 늘려 만든 수치인지 함께 점검해야 합니다.',
      'icon': 'ROE',
    },
    {
      'term': 'EPS',
      'subtitle': '주당순이익 · 주식 1주당 이익',
      'definition':
          'EPS(Earnings Per Share)는 기업의 순이익을 발행 주식 수로 나눈 값입니다. 이익 규모를 주식 수 기준으로 비교할 수 있게 해줍니다.',
      'formula': 'EPS = 당기순이익 ÷ 발행주식 수',
      'tip': 'EPS 증가 여부는 실적 성장의 핵심 신호이지만, 자사주 매입으로도 변화할 수 있습니다.',
      'icon': 'EPS',
    },
    {
      'term': '배당수익률',
      'subtitle': '배당금이 현재 주가에서 차지하는 비율',
      'definition':
          '배당수익률은 1년 동안 받는 주당 배당금을 현재 주가로 나눈 값입니다. 현금흐름 관점에서 종목을 살펴볼 때 유용합니다.',
      'formula': '배당수익률 = 주당배당금 ÷ 주가 × 100',
      'tip': '높은 배당수익률은 주가 하락의 결과일 수도 있으므로 배당성향과 현금흐름을 함께 보세요.',
      'icon': 'DIV',
    },
    {
      'term': 'ETF',
      'subtitle': '상장지수펀드 · 여러 자산에 분산 투자',
      'definition':
          'ETF(Exchange Traded Fund)는 특정 지수·산업·채권·원자재 등을 추종하며 거래소에서 주식처럼 매매하는 펀드입니다.',
      'formula': '확인 항목 = 추종지수 · 총보수 · 거래량 · 분배정책',
      'tip': '같은 테마 ETF라도 편입 종목과 보수가 다를 수 있으니 투자 전 구성과 추적 방식을 확인하세요.',
      'icon': 'ETF',
    },
  ];

  late Future<List<MarketIndex>> _marketData;
  late Future<List<dynamic>> _postsData;
  late TabController _tabController;
  late final AdService _adService;

  final ScrollController _scrollController = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _marketData = ApiService.fetchMarketIndices();
    _postsData = ApiService.fetchPosts();
    _tabController = TabController(length: 2, vsync: this);
    _adService = AdService();
    _adService.loadInterstitialAd(AdConfig.interstitialAdUnitId);

    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      if (maxScroll <= 0) return;
      _scrollController.jumpTo(
        currentScroll >= maxScroll ? 0 : currentScroll + 1.0,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _adService.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reloadPosts() async {
    setState(() {
      _postsData = ApiService.fetchPosts();
    });
    await _postsData;
  }

  void _openReportDetail(String postId) {
    _adService.showInterstitialAd(() {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DetailScreen(postId: postId)),
      );
    });
    _adService.loadInterstitialAd(AdConfig.interstitialAdUnitId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/market_hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    backgroundColor.withValues(alpha: 0.70),
                    backgroundColor.withValues(alpha: 0.38),
                    backgroundColor.withValues(alpha: 0.84),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                children: [
                  SizedBox(
                    height: 112,
                    child: FutureBuilder<List<MarketIndex>>(
                      future: _marketData,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: goldAccent),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text(
                              '지수 데이터를 불러오는 중입니다.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            final items = snapshot.data!;
                            return _buildMarketCard(
                              items[index % items.length],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildInsightHeader(),
                  const SizedBox(height: 10),
                  TabBar(
                    controller: _tabController,
                    labelColor: goldAccent,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: goldAccent,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                    tabs: const [
                      Tab(text: '🗓️ 일일 레포트'),
                      Tab(text: '💡 기초 지식'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDailyReportTimeline(),
                        _buildBasicKnowledge(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2E).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF7DD3FC).withValues(alpha: 0.30),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_graph_rounded, color: mintAccent),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '프리미엄 마켓 인사이트',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '최신 리포트와 꼭 알아야 할 투자 기초를 한곳에',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyReportTimeline() {
    return FutureBuilder<List<dynamic>>(
      future: _postsData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: goldAccent),
          );
        }
        if (snapshot.hasError) {
          return _buildRetryState('레포트를 불러오지 못했습니다. 다시 시도해 주세요.');
        }

        // /api/posts/는 공개 발행 레포트만 반환합니다. 카테고리 텍스트의
        // 인코딩 차이로 기존 레포트가 숨겨지지 않도록 목록 전체를 표시합니다.
        final reports = List<dynamic>.from(snapshot.data ?? []);
        // 서버가 created_at 우선 최신순으로 정렬하며, 구버전 서버 응답에도 안전하도록
        // 날짜 필드가 있을 때만 클라이언트에서 한 번 더 정렬합니다.
        if (reports.any((item) => _hasPostDate(item))) {
          reports.sort((a, b) => _postDate(b).compareTo(_postDate(a)));
        }

        if (reports.isEmpty) {
          return _buildRetryState('발행된 일일 레포트가 없습니다.');
        }

        return RefreshIndicator(
          color: goldAccent,
          backgroundColor: cardColor,
          onRefresh: _reloadPosts,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            itemCount: reports.length,
            separatorBuilder: (context, index) => const SizedBox(height: 2),
            itemBuilder: (context, index) => _buildTimelineReport(
              reports[index],
              isLast: index == reports.length - 1,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineReport(dynamic item, {required bool isLast}) {
    final date = _postDate(item);
    final postId = item['id']?.toString();
    final preview = (item['preview'] ?? item['summary'] ?? '').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: postId == null || postId.isEmpty
          ? null
          : () => _openReportDetail(postId),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 58,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: goldAccent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: goldAccent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Color(0xFFFFE08A),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${date.year}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        color: goldAccent.withValues(alpha: 0.34),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: goldAccent.withValues(alpha: 0.20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: goldAccent,
                          size: 17,
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'DAILY MARKET NOTE',
                          style: TextStyle(
                            color: Color(0xFFFFE08A),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white38,
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      (item['title'] ?? '제목 없음').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.35,
                        color: Colors.white,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicKnowledge() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: _knowledgeItems.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1A2E).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: mintAccent.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.school_rounded, color: mintAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '투자를 시작하기 전, 용어의 뜻과 해석 방법을 짧고 명확하게 익혀보세요.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final item = _knowledgeItems[index - 1];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showKnowledgeDetail(item),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: mintAccent.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 49,
                  height: 49,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mintAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    item['icon']!,
                    style: const TextStyle(
                      color: Color(0xFF7DECE2),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['term']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['subtitle']!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8CA8C1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showKnowledgeDetail(Map<String, String> item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF10233B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                item['term']!,
                style: const TextStyle(
                  color: Color(0xFF7DECE2),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item['subtitle']!,
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _knowledgeSection('무엇인가요?', item['definition']!),
              const SizedBox(height: 18),
              _knowledgeSection('계산식·확인 항목', item['formula']!, highlight: true),
              const SizedBox(height: 18),
              _knowledgeSection('실전 해석 팁', item['tip']!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _knowledgeSection(
    String title,
    String content, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? mintAccent.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? mintAccent.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFE08A),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            content,
            style: const TextStyle(
              color: Colors.white,
              height: 1.6,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, color: Colors.white38, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _reloadPosts,
              icon: const Icon(Icons.refresh_rounded, color: goldAccent),
              label: const Text(
                '새로고침',
                style: TextStyle(color: Color(0xFFFFE08A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasPostDate(dynamic item) {
    final raw =
        item['created_at'] ?? item['published_at'] ?? item['updated_at'];
    return DateTime.tryParse(raw?.toString() ?? '') != null;
  }

  DateTime _postDate(dynamic item) {
    final raw =
        item['created_at'] ?? item['published_at'] ?? item['updated_at'];
    return DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ??
        DateTime(1970);
  }

  Widget _buildMarketCard(MarketIndex item) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldAccent.withValues(alpha: 0.30)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.nation,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          Text(
            item.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.value,
            style: TextStyle(
              color: item.isUp ? Colors.redAccent : Colors.blueAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            item.change,
            style: TextStyle(
              color: item.isUp ? Colors.redAccent : Colors.blueAccent,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
