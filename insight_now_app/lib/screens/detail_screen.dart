import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DetailScreen extends StatefulWidget {
  final String postId;
  const DetailScreen({super.key, required this.postId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? _post;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPostDetail();
  }

  Future<void> _fetchPostDetail() async {
    final url = Uri.parse('https://insight-now-app.onrender.com/posts/${widget.postId}');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      setState(() {
        _post = json.decode(response.body);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("분석 상세")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // [나중에 광고 기능을 켤 때 이 로직을 사용하세요]
    // bool isLocked = _post?['is_locked'] ?? false; 
    bool isLocked = false; // 지금은 테스트를 위해 무조건 본문이 보이게 설정됨

    return Scaffold(
      appBar: AppBar(title: const Text("분석 상세")),
      backgroundColor: const Color(0xFF0A192F),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _post!['title'] ?? '제목 없음',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 20),
            
            // 광고 로직(isLocked)에 따라 본문 출력 여부 결정
            isLocked
                ? const Text("본문을 보려면 광고를 시청하세요.", style: TextStyle(color: Colors.white70))
                : Text(
                    _post!['content'] ?? '내용 없음',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
          ],
        ),
      ),
    );
  }
}