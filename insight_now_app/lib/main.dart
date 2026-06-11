import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'navigation.dart'; // 곧 만들 파일
import 'auth_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Insight Now Premium',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF111318), // 럭셔리 다크 테마
        fontFamily: 'Pretendard',
      ),
      home: const AuthWrapper(),
    );
  }
}