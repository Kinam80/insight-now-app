import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../constants/api_constants.dart';

class NewsTab extends StatefulWidget {
  const NewsTab({super.key});

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  List _news = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  Future<void> _fetchNews() async {
    try {
      final res = await http.get(Uri.parse(ApiConstants.newsEndpoint));
      if (res.statusCode == 200 && mounted) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        
        // 🚀 추가: 서버 응답 확인용 로그
        print("서버 응답 데이터: ${data['news']}");
        
        setState(() {
          _news = data['news'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF111318), 
        body: Center(child: CircularProgressIndicator(color: Colors.amber))
      );
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      appBar: AppBar(
        title: const Text('마켓 인사이트', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: const Color(0xFF1E222D),
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _news.length,
        itemBuilder: (context, i) => _buildTossStyleCard(_news[i]),
      ),
    );
  }

  Widget _buildTossStyleCard(Map item) {
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
              Text(item['category_display'] ?? '금융 뉴스', 
                   style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              Text(item['time_ago'] ?? '방금 전', 
                   style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(item['title'] ?? '', 
               style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 8),
          Text(item['summary'] ?? '', 
               style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
               maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                child: Text("${item['premium_metrics']?['badge'] ?? 'HOT'} | 신뢰도 ${item['premium_metrics']?['insight_score'] ?? '85%'}", 
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ),
              InkWell(
                onTap: () async {
                  // 수정됨: DB의 source_url을 사용하되, 없을 경우를 대비해 빈 문자열이나 오류 처리를 고려
                  final urlString = item['source_url']; 
                  if (urlString != null && urlString.isNotEmpty) {
                    final url = Uri.parse(urlString);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  } else {
                    // 링크가 없는 경우 사용자에게 알림을 줄 수 있음
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('연결 가능한 원본 링크가 없습니다.')),
                    );
                  }
                },
                child: const Text('더 보기 >', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              )
            ],
          )
        ],
      ),
    );
  }
}