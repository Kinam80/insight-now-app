import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/api_constants.dart';

class DetailScreen extends StatefulWidget {
  final Map<String, dynamic>? etfData; // ETF 데이터를 통째로 받음
  final String? ticker; // ETF용 (기존 호환성 유지)
  final String? postId; // 게시글용

  // 생성자: ticker/postId가 없더라도 etfData가 들어오면 허용하도록 수정
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
    // 데이터가 이미 들어왔다면 로딩할 필요 없음
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
    // 데이터 꺼내기 (etfData가 우선, 없으면 _data에서 추출)
    final name = _data?['name'] ?? '종목명 없음';
    final price = _data?['price'] ?? 0;
    final weight = _data?['weight'] ?? 0;
    final desc = _data?['description'] ?? '상세 설명 없음';

    return Scaffold(
      appBar: AppBar(title: Text(isEtf ? "$name 상세" : "분석 상세")),
      backgroundColor: const Color(0xFF0A192F),
      body: Padding(
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
                    Text(desc, style: const TextStyle(fontSize: 16, color: Colors.white)),
                  ],
                )
              : Text(_data!['content'] ?? '내용 없음', style: const TextStyle(fontSize: 16, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}