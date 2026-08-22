import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRememberMe = false; // [추가됨] 로그인 상태 유지 체크박스 변수

  // [수정됨] async로 변경하여 비동기 처리
  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showErrorDialog("이메일과 비밀번호를 모두 입력해주세요.");
      return;
    }
    
    try {
      // [수정됨] 체크박스 상태(_isRememberMe)를 AuthProvider의 login 함수로 전달
      await Provider.of<AuthProvider>(context, listen: false)
          .login(
            _emailController.text,
            _passwordController.text,
            rememberMe: _isRememberMe,
          );
    } catch (e) {
      _showErrorDialog("로그인에 실패했습니다.");
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("로그인 실패"),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("로그인", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              TextField(
                controller: _emailController, 
                decoration: const InputDecoration(labelText: "이메일", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController, 
                decoration: const InputDecoration(labelText: "비밀번호", border: OutlineInputBorder()), 
                obscureText: true,
              ),
              // [추가됨] 로그인 상태 유지 체크박스 UI 부분
              CheckboxListTile(
                title: const Text("로그인 상태 유지"),
                value: _isRememberMe,
                onChanged: (value) => setState(() => _isRememberMe = value!),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _handleLogin,
                child: const Text("로그인"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterScreen()),
                  );
                },
                child: const Text("회원가입 하러가기"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}