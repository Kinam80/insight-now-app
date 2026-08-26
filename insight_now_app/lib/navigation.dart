import 'package:flutter/material.dart';

import 'tabs/community_tab.dart';
import 'tabs/etf_tab.dart';
import 'tabs/gov_stats_tab.dart';
import 'tabs/market_index_tab.dart';
import 'tabs/news_tab.dart';
import 'tabs/settings_tab.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const _background = Color(0xFF1E222D);
  static const _selected = Color(0xFFF6C85F);
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    MarketIndexTab(),
    NewsTab(),
    CommunityTab(),
    EtfTab(),
    GovStatsTab(),
    SettingsTab(),
  ];

  void _select(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                child: Container(
                  color: _background,
                  child: Row(
                    children: [
                      _navItem(0, Icons.analytics_rounded, '지수'),
                      _navItem(1, Icons.newspaper_rounded, '뉴스'),
                      const SizedBox(width: 74),
                      _navItem(3, Icons.pie_chart_rounded, 'ETF'),
                      _navItem(4, Icons.account_balance_rounded, '지표'),
                      _navItem(5, Icons.settings_rounded, '설정'),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -23,
                child: GestureDetector(
                  onTap: () => _select(2),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _selectedIndex == 2
                              ? _selected
                              : const Color(0xFF263A56),
                          border: Border.all(
                            color: const Color(0xFF0D1726),
                            width: 5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _selected.withValues(
                                alpha: _selectedIndex == 2 ? 0.35 : 0.12,
                              ),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.local_fire_department_rounded,
                          color: _selectedIndex == 2
                              ? const Color(0xFF182133)
                              : _selected,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '머니톡',
                        style: TextStyle(
                          color: _selectedIndex == 2
                              ? _selected
                              : Colors.grey[500],
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _select(index),
        child: Padding(
          padding: const EdgeInsets.only(top: 13, bottom: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? _selected : Colors.grey[500],
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _selected : Colors.grey[500],
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
