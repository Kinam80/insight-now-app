import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF111318), // 💡 억대 자산가 전용 럭셔리 다크 리치 테마
        fontFamily: 'Pretendard',
      ),
      home: const AuthWrapper(),
    );
  }
}

// --- 인증 상태 관리 및 API 통신 (Provider) ---
class AuthProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  String? _token;
  bool _isLoading = true;

  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null;

  AuthProvider() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    _token = await _storage.read(key: 'access_token');
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('http://127.0.0.1:8000/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'];
        await _storage.write(key: 'access_token', value: _token);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('로그인 에러: $e');
    }
    return false;
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: 'access_token');
    notifyListeners();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF111318),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }
    return auth.isAuthenticated ? const MainNavigationScreen() : const LoginScreen();
  }
}

// --- 화면 1: 로그인 스크린 ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'test@test.com');
  final _passwordController = TextEditingController(text: 'test1234');
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2330),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(0, 15),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('👑', style: TextStyle(fontSize: 44), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'INSIGHT NOW',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'VIP 인텔리전스 자산 관리 플랫폼',
                style: TextStyle(fontSize: 13, color: Colors.amber, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'VIP 인증 계정 (Email)',
                  labelStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.amber)),
                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '보안 비밀번호',
                  labelStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.amber)),
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.amber[400],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _isSubmitting ? null : _handleLogin,
                child: _isSubmitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Color(0xFF111318), strokeWidth: 2))
                    : const Text('프리미엄 라운지 입장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111318))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    setState(() => _isSubmitting = true);
    final success = await context.read<AuthProvider>().login(_emailController.text, _passwordController.text);
    setState(() => _isSubmitting = false);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.redAccent, content: Text('인증 실패! 계정 보안 정보를 다시 확인해 주세요.', style: TextStyle(color: Colors.white)))
      );
    }
  }
}

// --- 🛠️ 4대 영역 통제 통합 네비게이션 센터 ---
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const GlobalMarketIndexTab(), // 1. 주요 지수 실시간 시황판
    const NewsTab(),              // 2. 실시간 마켓 리포트
    const PostsTab(),             // 3. 독점 프리미엄 분석
    const VIPLiveChatTab(),       // 4. 가입자 실시간 채팅방
  ];

  final List<String> _titles = [
    '📈 GLOBAL 시황 전광판',
    '📰 실시간 마켓 리포트',
    '💎 독점 프리미엄 분석',
    '💬 VIP 전용 실시간 소통방'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      appBar: AppBar(
        title: Text(_titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white, letterSpacing: 0.5)),
        backgroundColor: const Color(0xFF1E222D),
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.grey),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF1E222D),
        selectedItemColor: Colors.amber[400], // VIP 전용 프리미엄 골드 포인트 테마
        unselectedItemColor: Colors.grey[500],
        currentIndex: _selectedIndex,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), activeIcon: Icon(Icons.analytics), label: '시장지수'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt_outlined), activeIcon: Icon(Icons.bolt), label: '마켓리포트'),
          BottomNavigationBarItem(icon: Icon(Icons.workspace_premium_outlined), activeIcon: Icon(Icons.workspace_premium), label: '독점분석'),
          BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), activeIcon: Icon(Icons.forum), label: '실시간챗'),
        ],
      ),
    );
  }
}

// --- 📈 [1번 탭] 글로벌 금융 지수 실시간 시황판 ---
class GlobalMarketIndexTab extends StatelessWidget {
  const GlobalMarketIndexTab({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> indices = [
      {'name': '코스피 (KOSPI)', 'value': '2,684.52', 'change': '+1.24%', 'isUp': true, 'nation': '🇰🇷'},
      {'name': '코스닥 (KOSDAQ)', 'value': '865.10', 'change': '-0.45%', 'isUp': false, 'nation': '🇰🇷'},
      {'name': '나스닥 종합 (NASDAQ)', 'value': '16,920.72', 'change': '+2.11%', 'isUp': true, 'nation': '🇺🇸'},
      {'name': 'S&P 500', 'value': '5,304.72', 'change': '+0.88%', 'isUp': true, 'nation': '🇺🇸'},
      {'name': '원·달러 환율 (USD/KRW)', 'value': '1,372.50', 'change': '+4.20원', 'isUp': true, 'nation': '💱'},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('🔴 LIVE GLOBAL MARKET TICKER', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemCount: indices.length,
          itemBuilder: (context, i) {
            final idx = indices[i];
            final color = idx['isUp'] ? Colors.redAccent : Colors.blueAccent;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(idx['nation'], style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(idx['name'], style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(idx['value'], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(idx['change'], style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF232733),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.2)),
          ),
          child: const Row(
            children: [
              Text('💡', style: TextStyle(fontSize: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '현재 실시간 원시 데이터 통신망이 정상 가동 중입니다. 세부 반도체 테마 및 M&A 일정 관련 수혜 종목 모니터링은 독점 분석 탭을 참조하십시오.',
                  style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}

// --- 📰 [2번 탭] 최고급 실시간 마켓 리포트 목록 ---
class NewsTab extends StatefulWidget {
  const NewsTab({super.key});

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  List _news = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  Future<void> _fetchNews() async {
    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:8000/news/'));
      if (res.statusCode == 200) {
        final Map<String, dynamic> decodedData = jsonDecode(res.body);
        setState(() {
          _news = decodedData['news'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.amber));
    if (_news.isEmpty) return const Center(child: Text('현재 실시간 럭셔리 인사이틀 정보가 공백 상태입니다.', style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _news.length,
      itemBuilder: (context, i) {
        final item = _news[i];
        final metrics = item['premium_metrics'] ?? {};
        final bool isPremiumBadge = metrics['badge'] == 'PREMIUM';

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.03)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item['category_display'] ?? '🎯 마켓 브리핑',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPremiumBadge ? const Color(0x22FFB300) : const Color(0x222196F3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        metrics['badge'] ?? 'HOT',
                        style: TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.w900, 
                          color: isPremiumBadge ? Colors.amber[300] : Colors.blue[300],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item['title'] ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  item['summary'] ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.white60, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Divider(height: 24, thickness: 0.5, color: Colors.white12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text('중요도 ${metrics['importance'] ?? '🔥'}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        const SizedBox(width: 12),
                        Text('AI 신뢰도: ${metrics['insight_score'] ?? '90%'}', style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Text(
                      item['time_ago'] ?? '실시간',
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- 💎 [3번 탭] 전문가 유료 분석 글 목록 ---
class PostsTab extends StatefulWidget {
  const PostsTab({super.key});

  @override
  State<PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<PostsTab> {
  List _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:8000/posts/'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _posts = data['posts'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.amber));
    if (_posts.isEmpty) return const Center(child: Text('발행된 독점 분석 보고서가 없습니다.', style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _posts.length,
      itemBuilder: (context, i) {
        final post = _posts[i];
        final bool isPaid = post['access_type'] == 'paid_single';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.03)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Icon(
              isPaid ? Icons.workspace_premium_rounded : Icons.lock_open_rounded,
              color: isPaid ? Colors.amber : Colors.greenAccent,
              size: 28,
            ),
            title: Text(post['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(post['preview'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ),
            trailing: isPaid
                ? Text('${post['single_price']}원', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 14))
                : const Text('VIP 무료', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            onTap: () => _openPostDetail(post),
          ),
        );
      },
    );
  }

  void _openPostDetail(Map post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );
  }
}

// --- 💬 [4번 탭] VIP 회원 실시간 대화방 (완벽 독립 버전) ---
class VIPLiveChatTab extends StatefulWidget {
  const VIPLiveChatTab({super.key});

  @override
  State<VIPLiveChatTab> createState() => _VIPLiveChatTabState();
}

class _VIPLiveChatTabState extends State<VIPLiveChatTab> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, String>> liveMessages = [
    {'user': '자산운용가K', 'msg': '엔비디아 시외 폭등 나오네요. 내일 국내 디자인하우스 테마 수급 체크해야 합니다.'},
    {'user': '테헤란로고래', 'msg': '에이직랜드랑 가온칩스 아침 시초가 갭상승 자리 무조건 나오겠네요.'},
    {'user': '리서치센터장', 'msg': '환율이 1,370원 선 무너지지 않으면 외인 매도세 보수적으로 대응하시는 걸 추천합니다.'},
    {'user': '형님(VIP)', 'msg': '실시간 마켓 리포트 속보 보고 후성 정리 타이밍 대기 중입니다.'},
  ];

  void _executeSend() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      liveMessages.add({
        'user': '형님(VIP)',
        'msg': text,
      });
    });

    _chatController.clear();

    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          color: const Color(0xFF151821),
          child: const Row(
            children: [
              Icon(Icons.radio_button_checked, color: Colors.redAccent, size: 16),
              SizedBox(width: 8),
              Text('VIP 실시간 세션 연결됨 (온라인 124명)', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: liveMessages.length,
            itemBuilder: (context, i) {
              final chat = liveMessages[i];
              final isMe = chat['user']!.contains('형님');
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.amber[400] : const Color(0xFF1E222D),
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                      bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chat['user']!, style: TextStyle(color: isMe ? const Color(0xFF111318) : Colors.amber[300], fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(chat['msg']!, style: TextStyle(color: isMe ? const Color(0xFF111318) : Colors.white, fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Color(0xFF1E222D), border: Border(top: BorderSide(color: Colors.white12))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _executeSend(),
                  decoration: const InputDecoration(
                    hintText: '실시간 거시 경제 정보 공유하기...',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.amber), 
                onPressed: _executeSend,
              ),
            ],
          ),
        )
      ],
    );
  }
}

// --- 📄 화면 3: 프리미엄 상세 보기 및 결제 통합 모달 센터 (단일 통합 클래스) ---
class PostDetailScreen extends StatelessWidget {
  final Map post;
  const PostDetailScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    // 유료 단건 글이고 아직 구매 안 한 경우 잠금 처리
    final bool isLocked = post['access_type'] == 'paid_single' && post['is_purchased'] == false;

    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      appBar: AppBar(
        title: const Text('PREMIUM REPORT', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)),
        backgroundColor: const Color(0xFF1E222D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
              child: const Text('PREMIUM', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            Text(post['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1.3)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(post['author'] ?? '리서치센터', style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text('VIP 전용 리포트 발송일: ${post['published_at']?.substring(0, 10) ?? post['date'] ?? ''}', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const Divider(height: 40, thickness: 1, color: Colors.white12),
            if (isLocked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF231E18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.lock_clock_rounded, size: 56, color: Colors.amber[400]),
                    const SizedBox(height: 16),
                    const Text('VIP 단건 제한 독점 프리미엄 분석입니다.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.amber), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('기관 투자자급 심층 마켓 기밀 내용을 열람하시려면 아래 결제를 진행해 주세요.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[400],
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () => _showPaymentModal(context),
                      child: Text('${post['single_price'] ?? '10,000'}원 결제 후 즉시 열람', style: const TextStyle(color: Color(0xFF111318), fontWeight: FontWeight.bold, fontSize: 15)),
                    )
                  ],
                ),
              )
            ] else ...[
              Text(post['content'] ?? '상세 리포트 내용을 불러올 수 없습니다.', style: const TextStyle(fontSize: 16, height: 1.8, color: Colors.white70)),
            ]
          ],
        ),
      ),
    );
  }

  void _showPaymentModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(32),
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '💳 토스페이먼츠 프리미엄 결제 연동', 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '선택하신 리포트: ${post['title']}',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '결제 금액: ${post['single_price'] ?? '10,000'}원',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0054F3), // 토스페이 시그니처 블루 컬러
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(context); // 모달창 닫기
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.blueAccent,
                      content: Text('토스페이먼츠 라이브 테스트 결제 게이트웨이를 호출합니다.', style: TextStyle(color: Colors.white)),
                    ),
                  );
                },
                child: const Text('토스페이로 안전하게 결제하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('결제 취소하고 돌아가기', style: TextStyle(color: Colors.white30)),
              )
            ],
          ),
        );
      },
    );
  }
}