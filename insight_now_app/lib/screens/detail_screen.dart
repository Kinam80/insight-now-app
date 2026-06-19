import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart'; // 1. 패키지 임포트 추가
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
    final String path = widget.ticker != null 
        ? '/etfs/${widget.ticker}' 
        : '/posts/${widget.postId}';
        
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _data = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("상세 정보")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    bool isEtf = widget.etfData != null || widget.ticker != null;
    final name = _data?['name'] ?? '종목명 없음';
    final price = _data?['price'] ?? 0;
    final weight = _data?['weight'] ?? 0;
    final desc = _data?['description'] ?? '상세 설명 없음';

    return Scaffold(
      appBar: AppBar(title: Text(isEtf ? "$name 상세" : "분석 상세")),
      backgroundColor: const Color(0xFF0A192F),
      // 2. SingleChildScrollView로 감싸서 내용이 길어도 스크롤 가능하게 수정
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEtf ? name : (_data!['title'] ?? '제목 없음'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 20),
            
            isEtf 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("현재가: ₩$price", style: const TextStyle(fontSize: 18, color: Colors.greenAccent)),
                    Text("비중: $weight%", style: const TextStyle(fontSize: 18, color: Colors.white70)),
                    const SizedBox(height: 10),
                    // 3. MarkdownBody 적용: 마크다운 텍스트를 자동으로 예쁘게 랜더링
                    MarkdownBody(
                      data: desc, 
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 16, color: Colors.white),
                        h1: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                )
              // 4. 일반 게시글도 MarkdownBody로 통일 (일관성 유지)
              : MarkdownBody(
                  data: _data!['content'] ?? '내용 없음',
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}