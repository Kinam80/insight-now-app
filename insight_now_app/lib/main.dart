import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 1. 필수 추가
import 'navigation.dart';
import 'auth_provider.dart';

// Supabase 접속 정보
const String supabaseUrl = 'https://ckzaqaxhzbqydiwrbkas.supabase.co'; 
const String supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNremFxYXhoemJxeWRpd3Jia2FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxMDQyNzAsImV4cCI6MjA5NDY4MDI3MH0.acAAQoLzzCraWiUl-hS3lMx0k1ndf0GSgpkoQVozQm0';

void main() async {
  // 2. 이게 있어야 비동기 초기화가 가능합니다.
  WidgetsFlutterBinding.ensureInitialized();

  // 3. 앱 실행 전 Supabase를 먼저 연결합니다.
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

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
        scaffoldBackgroundColor: const Color(0xFF111318),
        fontFamily: 'Pretendard',
      ),
      home: const AuthWrapper(),
    );
  }
}