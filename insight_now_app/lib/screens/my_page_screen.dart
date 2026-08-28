import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../constants/api_constants.dart';
import '../services/background_music_controller.dart';
import '../tabs/settings_tab.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  static const _background = Color(0xFF071221);
  static const _surface = Color(0xFF10233B);
  static const _gold = Color(0xFFF6C85F);
  static const _mint = Color(0xFF4FD1C5);

  _ProfileData _profile = const _ProfileData.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final nickname = preferences.getString('moneytalk_nickname') ?? '투자러';
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/api/chat/community/profile/${Uri.encodeComponent(nickname)}',
            ),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && body is Map && body['profile'] is Map) {
        _profile = _ProfileData.fromJson(
          Map<String, dynamic>.from(body['profile'] as Map),
          nickname,
        );
      }
    } catch (_) {
      // 네트워크 지연 시에도 마지막 기본 계급 정보를 유지합니다.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<BackgroundMusicController>();
    final nextPoints = _profile.nextLevelPoints;
    final progress = nextPoints == null || nextPoints <= 0
        ? 1.0
        : math.min(_profile.points / nextPoints, 1.0);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        elevation: 0,
        title: const Text(
          '내 투자 프로필',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: music.enabled ? '배경음 끄기' : '배경음 켜기',
            icon: Icon(
              music.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: music.enabled ? _gold : Colors.white54,
            ),
            onPressed: music.ready ? music.toggle : null,
          ),
          IconButton(
            tooltip: '환경설정',
            icon: const Icon(Icons.settings_rounded, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsTab()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _gold,
        backgroundColor: _surface,
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3552), Color(0xFF10233B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _gold.withValues(alpha: 0.38)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 172,
                      child: Center(child: CircularProgressIndicator(color: _gold)),
                    )
                  : Column(
                      children: [
                        Container(
                          width: 74,
                          height: 74,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold.withValues(alpha: 0.16),
                            border: Border.all(color: _gold.withValues(alpha: 0.62)),
                          ),
                          child: Text(_profile.badge, style: const TextStyle(fontSize: 34)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _profile.nickname,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Lv. ${_profile.level}  ·  ${_profile.title}',
                          style: const TextStyle(
                            color: Color(0xFFFFE08A),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.workspace_premium_rounded, color: _mint),
                            const SizedBox(width: 8),
                            const Text(
                              '머니 포인트',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            Text(
                              '${_profile.points} P',
                              style: const TextStyle(
                                color: _mint,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        if (nextPoints != null && nextPoints > 0) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              color: _gold,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '다음 계급까지 ${math.max(nextPoints - _profile.points, 0)} P',
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            _infoCard(
              icon: Icons.info_outline_rounded,
              title: '머니 포인트 안내',
              body: '글·댓글·라이브 참여로 쌓이는 명예·배지용 포인트입니다. 현금화, 양도, 거래는 할 수 없습니다.',
            ),
            const SizedBox(height: 12),
            _musicCard(music),
            const SizedBox(height: 12),
            _actionTile(
              icon: Icons.settings_rounded,
              title: '환경설정',
              subtitle: '자동화 상태와 앱 관리 기능을 확인합니다.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsTab()),
              ),
            ),
            const SizedBox(height: 12),
            _actionTile(
              icon: Icons.logout_rounded,
              title: '로그아웃',
              subtitle: '이 기기에서 안전하게 로그아웃합니다.',
              color: Colors.redAccent,
              onTap: () => Provider.of<AuthProvider>(context, listen: false).logout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _mint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _musicCard(BackgroundMusicController music) {
    return _actionTile(
      icon: music.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
      title: '클래식 배경음',
      subtitle: music.enabled ? '잔잔한 클래식 앰비언트 재생 중' : '배경음이 꺼져 있습니다.',
      trailing: Switch.adaptive(
        value: music.enabled,
        activeTrackColor: _gold,
        onChanged: music.ready ? music.setEnabled : null,
      ),
      onTap: music.ready ? music.toggle : null,
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color color = Colors.white,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.nickname,
    required this.points,
    required this.level,
    required this.title,
    required this.badge,
    required this.nextLevelPoints,
  });

  const _ProfileData.empty()
      : nickname = '투자러',
        points = 0,
        level = 1,
        title = '새싹 개미',
        badge = '🌱',
        nextLevelPoints = 60;

  final String nickname;
  final int points;
  final int level;
  final String title;
  final String badge;
  final int? nextLevelPoints;

  factory _ProfileData.fromJson(Map<String, dynamic> json, String nickname) {
    return _ProfileData(
      nickname: nickname,
      points: (json['points'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? '새싹 개미',
      badge: json['badge']?.toString() ?? '🌱',
      nextLevelPoints: (json['next_level_points'] as num?)?.toInt(),
    );
  }
}
