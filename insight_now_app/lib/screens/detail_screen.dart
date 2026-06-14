import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/api_constants.dart';

class DetailScreen extends StatefulWidget {
  final String? ticker; // ETF용
  final String? postId; // 게시글용

  // 생성자 오버로딩: 둘 중 하나는 반드시 필요함
  const DetailScreen({super.key, this.ticker, this.postId}) 
      : assert(ticker != null || postId != null);

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    final String path = widget.ticker != null 
        ? '/etfs/${widget.ticker}' 
        : '/posts/${widget.postId}';
        
    final url = Uri.parse('${ApiConstants.baseUrl}$path');
    print("요청 URL: $url"); // 1. URL이 맞는지 확인

    try {
      final response = await http.get(url);
      print("응답 코드: ${response.statusCode}"); // 2. 서버가 응답을 주는지 확인
      print("응답 내용: ${response.body}");      // 3. 내용이 뭔지 확인

      if (response.statusCode == 200) {
        setState(() {
          _data = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        // 서버 응답이 200이 아니면 로딩을 멈추고 에러 표시
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("통신 에러: $e");
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

    // 데이터 표시 방식 분기
    bool isEtf = widget.ticker != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEtf ? "${widget.ticker} 상세" : "분석 상세")),
      backgroundColor: const Color(0xFF0A192F),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEtf ? "종목코드: ${widget.ticker}" : (_data!['title'] ?? '제목 없음'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 20),
            
            isEtf 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("현재가: ₩${_data?['price'] ?? '0'}", style: const TextStyle(fontSize: 18, color: Colors.greenAccent)),
                    Text("비중: ${_data?['weight'] ?? 0}%", style: const TextStyle(fontSize: 18, color: Colors.white70)),
                    const SizedBox(height: 10),
                    Text(_data?['description'] ?? '상세 설명 없음', style: const TextStyle(fontSize: 16, color: Colors.white)),
                  ],
                )
              : Text(_data!['content'] ?? '내용 없음', style: const TextStyle(fontSize: 16, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}