import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';

class NewsTab extends StatefulWidget {
  const NewsTab({super.key});

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  List<Map<String, dynamic>> _news = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  Future<void> _fetchNews() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await http.get(Uri.parse(ApiConstants.newsEndpoint));
      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _errorMessage = '뉴스를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
        });
        return;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final rawNews = decoded is Map<String, dynamic> ? decoded['news'] : null;
      final news = rawNews is List
          ? rawNews
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _news = news;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '네트워크 상태를 확인한 뒤 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      appBar: AppBar(
        title: const Text(
          '마켓 인사이트',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: const Color(0xFF1E222D),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchNews,
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.amber),
      );
    }

    if (_errorMessage != null) {
      return _buildStatus(
        icon: Icons.cloud_off_outlined,
        message: _errorMessage!,
        actionLabel: '다시 시도',
      );
    }

    if (_news.isEmpty) {
      return _buildStatus(
        icon: Icons.newspaper_outlined,
        message: '아직 표시할 최신 뉴스가 없습니다.\n잠시 후 새로고침해주세요.',
        actionLabel: '새로고침',
      );
    }

    return RefreshIndicator(
      color: Colors.amber,
      onRefresh: _fetchNews,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _news.length,
        itemBuilder: (context, index) => _buildTossStyleCard(_news[index]),
      ),
    );
  }

  Widget _buildStatus({
    required IconData icon,
    required String message,
    required String actionLabel,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 52),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _fetchNews,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTossStyleCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item['category_display'] ?? '금융 뉴스',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                item['time_ago'] ?? '방금 전',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item['title'] ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item['summary'] ?? '',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${item['premium_metrics']?['badge'] ?? 'Yahoo Finance'} | ${item['premium_metrics']?['insight_score'] ?? '원문 제공'}",
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
              InkWell(
                onTap: () => _openSource(item['source_url']),
                child: const Text(
                  '더 보기 >',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSource(dynamic sourceUrl) async {
    final urlString = sourceUrl?.toString() ?? '';
    final url = Uri.tryParse(urlString);
    if (url != null && await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('연결 가능한 원본 링크가 없습니다.')));
    }
  }
}
