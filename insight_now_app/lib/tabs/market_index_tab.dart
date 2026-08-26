import 'dart:async';
import 'package:flutter/material.dart';

import '../constants/ad_config.dart';
import '../models/market_index.dart';
import '../screens/detail_screen.dart';
import '../services/ad_service.dart';
import '../services/api_service.dart';

// 고급스러운 다크 테마 색상
const Color backgroundColor = Color(0xFF0A192F); // 딥 네이비
const Color cardColor = Color(0xFF172A45); // 카드 배경색
const Color goldAccent = Color(0xFFD4AF37); // 골드 포인트

class MarketIndexTab extends StatefulWidget {
  const MarketIndexTab({super.key});

  @override
  State<MarketIndexTab> createState() => _MarketIndexTabState();
}

class _MarketIndexTabState extends State<MarketIndexTab>
    with SingleTickerProviderStateMixin {
  late Future<List<MarketIndex>> _marketData;
  late TabController _tabController;

  // 부드러운 스크롤을 위한 컨트롤러
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;

  // 게시글은 서버 API로 조회합니다. 직접 Supabase 스트림은 로그인 사용자별
  // RLS 정책에 따라 공개 레포트가 누락될 수 있으므로 사용하지 않습니다.
  late Future<List<dynamic>> _postsData;
  late final AdService _adService;

  @override
  void initState() {
    super.initState();
    _marketData = ApiService.fetchMarketIndices();
    _postsData = ApiService.fetchPosts();
    _tabController = TabController(length: 2, vsync: this);
    _adService = AdService();
    _adService.loadInterstitialAd(AdConfig.interstitialAdUnitId);

    // 0.05초마다 1픽셀씩 이동하는 기차 스크롤
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_scrollController.hasClients) {
        double maxScroll = _scrollController.position.maxScrollExtent;
        double currentScroll = _scrollController.offset;
        if (currentScroll >= maxScroll) {
          _scrollController.jumpTo(0);
        } else {
          _scrollController.jumpTo(currentScroll + 1.0);
        }
      }
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
                    backgroundColor.withOpacity(0.70),
                    backgroundColor.withOpacity(0.38),
                    backgroundColor.withOpacity(0.84),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 40.0),
              child: Column(
                children: [
                  // [부드럽게 흐르는 지수 카드 영역]
                  SizedBox(
                    height: 120,
                    child: FutureBuilder<List<MarketIndex>>(
                      future: _marketData,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting)
                          return const Center(
                            child: CircularProgressIndicator(color: goldAccent),
                          );
                        if (!snapshot.hasData || snapshot.data!.isEmpty)
                          return const Center(
                            child: Text(
                              "지수 데이터 없음",
                              style: TextStyle(color: Colors.white),
                            ),
                          );

                        return ListView.builder(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            final item =
                                snapshot.data![index % snapshot.data!.length];
                            return _buildMarketCard(item);
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 30),

                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1A2E).withOpacity(0.78),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF7DD3FC).withOpacity(0.30),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.auto_graph_rounded,
                          color: Color(0xFF4FD1C5),
                        ),
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
                                '지수 · 리포트 · 핵심 경제지표를 한눈에',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  TabBar(
                    controller: _tabController,
                    labelColor: goldAccent,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: goldAccent,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(text: "📜 일일 레포트"),
                      Tab(text: "💡 기초 지식"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildContentList("레포트"),
                        _buildContentList("기초 지식"),
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

  Widget _buildContentList(String type) {
    return FutureBuilder<List<dynamic>>(
      future: _postsData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: goldAccent),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: TextButton.icon(
              onPressed: _reloadPosts,
              icon: const Icon(Icons.refresh, color: goldAccent),
              label: const Text(
                '레포트를 불러오지 못했습니다. 다시 시도',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        final data = (snapshot.data ?? []).where((item) {
          final category = (item['category'] ?? '').toString().trim();
          return category == type;
        }).toList();

        if (data.isEmpty) {
          return Center(
            child: Text(
              '$type 카테고리에 글이 없습니다.',
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }

        return RefreshIndicator(
          color: goldAccent,
          backgroundColor: cardColor,
          onRefresh: _reloadPosts,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: data.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = data[index];
              return InkWell(
                onTap: () {
                  final postId = item['id']?.toString();
                  if (postId != null && postId.isNotEmpty) {
                    _openReportDetail(postId);
                  }
                },

                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: goldAccent.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: goldAccent),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] ?? '제목 없음',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['preview'] ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMarketCard(MarketIndex item) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldAccent.withOpacity(0.3)),
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
