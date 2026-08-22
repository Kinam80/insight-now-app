import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart'; // [중요] 프로젝트 구조에 따라 경로 확인!

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("마이페이지"),
        backgroundColor: const Color(0xFF1E222D),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_pin, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            const Text("사용자님, 환영합니다!", style: TextStyle(fontSize: 18)),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
onPressed: () {
                Provider.of<AuthProvider>(context, listen: false).logout();
              },
              child: const Text("로그아웃", style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}