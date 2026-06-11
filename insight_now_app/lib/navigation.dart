import 'package:flutter/material.dart';
import 'tabs/market_index_tab.dart';    // 1. 상단 슬라이더 시황
import 'tabs/news_tab.dart';            // 2. 토스 스타일 뉴스
import 'tabs/etf_tab.dart';             // 3. ETF 백과사전
import 'tabs/gov_stats_tab.dart';       // 4. 정부 지표/분석

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const GlobalMarketIndexTab(),
    const NewsTab(),
    const EtfTab(),
    const GovStatsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1E222D),
        selectedItemColor: Colors.amber[400],
        unselectedItemColor: Colors.grey[500],
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: '지수'),
          BottomNavigationBarItem(icon: Icon(Icons.newspaper), label: '뉴스'),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'ETF'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: '지표'),
        ],
      ),
    );
  }
}