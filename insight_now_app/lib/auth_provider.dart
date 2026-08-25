import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/api_constants.dart';
import 'navigation.dart';
import 'screens/login_screen.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isInitializing = true;
  String? _token;

  bool get isAuthenticated => _isAuthenticated;
  bool get isInitializing => _isInitializing;
  String? get token => _token;

  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        _isAuthenticated = true;
      }
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    String? accessToken;

    // 기존 FastAPI 로그인 응답을 우선 사용합니다.
    try {
      final response = await http.post(
        Uri.parse(ApiConstants.loginEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        accessToken = data['access_token'] as String?;
      }
    } catch (_) {
      // 배포 API가 일시적으로 응답하지 않아도 Supabase 인증을 시도합니다.
    }

    // FastAPI의 저장 해시가 오래된 경우에도 Supabase Auth 로그인은 계속 지원합니다.
    if (accessToken == null || accessToken.isEmpty) {
      final authResponse = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      accessToken = authResponse.session?.accessToken;
    }

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('로그인 토큰이 없습니다.');
    }

    _token = accessToken;
    _isAuthenticated = true;

    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString('auth_token', accessToken);
    } else {
      await prefs.remove('auth_token');
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _isAuthenticated = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AuthProvider>().restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return auth.isAuthenticated
            ? const MainNavigationScreen()
            : const LoginScreen();
      },
    );
  }
}
