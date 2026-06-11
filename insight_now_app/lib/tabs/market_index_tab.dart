import 'package:flutter/material.dart';
import '../models/market_index.dart';
import '../services/api_service.dart';

class MarketIndexTab extends StatefulWidget {
  const MarketIndexTab({super.key});

  @override
  State<MarketIndexTab> createState() => _MarketIndexTabState();
}

class _MarketIndexTabState extends State<MarketIndexTab> with SingleTickerProviderStateMixin {
  late Future<List<MarketIndex>> _marketData;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _marketData = ApiService.fetchMarketIndices();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 시장 지표 슬라이더
            SizedBox(
              height: 120,
              child: FutureBuilder<List<MarketIndex>>(
                future: _marketData,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("지수 데이터 없음"));
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) => _buildMarketCard(snapshot.data![index]),
                  );
                },
              ),
            ),
            
            // 2. 탭 바 (레포트 vs 기초 지식)
            TabBar(
              controller: _tabController,
              labelColor: Colors.black87,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.amber,
              indicatorWeight: 3,
              tabs: const [Tab(text: "일일 레포트"), Tab(text: "기초 지식")],
            ),
            
            // 3. 내용 영역
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
    );
  }

  // 게시판 리스트 생성기
  Widget _buildContentList(String type) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome, color: Colors.amber),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$type 콘텐츠 ${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text("전문가가 분석한 오늘의 핵심 포인트 미리보기...", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }

  // 지수 카드
  Widget _buildMarketCard(MarketIndex item) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [Text(item.nation), const SizedBox(width: 4), Text(item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 8),
          Text(item.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(item.change, style: TextStyle(fontSize: 12, color: item.isUp ? Colors.red : Colors.blue, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}