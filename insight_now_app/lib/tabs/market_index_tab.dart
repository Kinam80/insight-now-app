import 'dart:async';
import 'package:flutter/material.dart';
import '../models/market_index.dart';
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

class _MarketIndexTabState extends State<MarketIndexTab> with SingleTickerProviderStateMixin {
  late Future<List<MarketIndex>> _marketData;
  late Future<List<dynamic>> _allPosts;
  late TabController _tabController;
  
  // 부드러운 스크롤을 위한 컨트롤러
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _marketData = ApiService.fetchMarketIndices();
    _allPosts = ApiService.fetchPosts();
    _tabController = TabController(length: 2, vsync: this);

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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
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
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: goldAccent));
                    if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("지수 데이터 없음", style: TextStyle(color: Colors.white)));
                    
                    return ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final item = snapshot.data![index % snapshot.data!.length];
                        return _buildMarketCard(item);
                      },
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 30),
              
              // [고급스러운 헤더 문구]
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.diamond, color: goldAccent),
                      SizedBox(width: 10),
                      Text("권기태 금융전문가 인사이트", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),

              TabBar(
                controller: _tabController,
                labelColor: goldAccent,
                unselectedLabelColor: Colors.white54,
                indicatorColor: goldAccent,
                indicatorWeight: 3,
                tabs: const [Tab(text: "📜 일일 레포트"), Tab(text: "💡 기초 지식")],
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
    );
  }

  Widget _buildContentList(String type) {
    return FutureBuilder<List<dynamic>>(
      future: _allPosts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: goldAccent));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("데이터가 없습니다.", style: TextStyle(color: Colors.white54)));

        final data = snapshot.data!; 

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = data[index];
            return Container(
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
                        Text(item['title'] ?? '제목 없음', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(item['preview'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
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
          Text(item.nation, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 5),
          Text(item.value, style: TextStyle(color: item.isUp ? Colors.redAccent : Colors.blueAccent, fontWeight: FontWeight.bold)),
          Text(item.change, style: TextStyle(color: item.isUp ? Colors.redAccent : Colors.blueAccent, fontSize: 11)),
        ],
      ),
    );
  }
}