import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List _messages = [];

  // 서버에서 데이터 가져오기
  Future<void> _fetchMessages() async {
    final response = await http.get(Uri.parse('https://insight-now-app.onrender.com/chat/messages'));
    if (response.statusCode == 200) {
      setState(() {
        _messages = json.decode(response.body);
      });
    }
  }

  // 메시지 전송
  Future<void> _sendMessage() async {
    await http.post(
      Uri.parse('https://insight-now-app.onrender.com/chat/messages'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({"email": "user@test.com", "content": _controller.text}),
    );
    _controller.clear();
    _fetchMessages();
  }

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("실시간 채팅")),
      body: Column(
        children: [
          Expanded(child: ListView.builder(
            itemCount: _messages.length,
            itemBuilder: (context, index) => ListTile(title: Text(_messages[index]['content'])),
          )),
          TextField(controller: _controller, decoration: InputDecoration(suffixIcon: IconButton(icon: Icon(Icons.send), onPressed: _sendMessage))),
        ],
      ),
    );
  }
}