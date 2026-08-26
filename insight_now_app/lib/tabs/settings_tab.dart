import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../constants/api_constants.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _isRefreshing = false;
  Map<String, dynamic>? _automationStatus;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _loadAutomationStatus();
  }

  Future<void> _loadAutomationStatus() async {
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _statusError = null;
      });
    }

    try {
      final response = await http
          .get(Uri.parse('${ApiConstants.baseUrl}/api/automation/status'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('상태 조회 실패');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted) return;
      setState(() {
        _automationStatus = decoded is Map<String, dynamic> ? decoded : null;
        _isRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusError = '자동화 상태를 불러오지 못했습니다.';
        _isRefreshing = false;
      });
    }
  }

  Future<void> _clearLocalSettings() async {
    final confirmed = await _confirm(
      title: '화면 설정 초기화',
      message: '저장된 화면·학습 설정을 초기화합니다. 로그인 상태는 유지됩니다.',
      confirmLabel: '초기화',
    );
    if (!confirmed) return;

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith('settings_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('화면 설정을 초기화했습니다.')));
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: '로그아웃',
      message: '이 기기에서 현재 로그인 세션을 종료합니다.',
      confirmLabel: '로그아웃',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    await context.read<AuthProvider>().logout();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF172A45),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(
              message,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: destructive
                      ? const Color(0xFFE76F51)
                      : const Color(0xFF4FD1C5),
                  foregroundColor: const Color(0xFF071523),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081426),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF4FD1C5),
          onRefresh: _loadAutomationStatus,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _sectionTitle('데이터 운영'),
              const SizedBox(height: 8),
              _buildAutomationCard(),
              const SizedBox(height: 10),
              _buildActionTile(
                icon: Icons.refresh_rounded,
                iconColor: const Color(0xFF4FD1C5),
                title: '데이터 상태 새로고침',
                subtitle: '뉴스 · ETF · 정부 보고서 자동화 상태를 다시 확인합니다.',
                onTap: _isRefreshing ? null : _loadAutomationStatus,
                trailing: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF4FD1C5),
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8CA8C1),
                      ),
              ),
              const SizedBox(height: 22),
              _sectionTitle('앱 관리'),
              const SizedBox(height: 8),
              _buildActionTile(
                icon: Icons.tune_rounded,
                iconColor: const Color(0xFFFFD166),
                title: '화면 설정 초기화',
                subtitle: '저장된 학습·화면 설정을 기본값으로 되돌립니다.',
                onTap: _clearLocalSettings,
              ),
              const SizedBox(height: 10),
              _buildActionTile(
                icon: Icons.logout_rounded,
                iconColor: const Color(0xFFE76F51),
                title: '로그아웃',
                subtitle: '이 기기의 로그인 세션을 안전하게 종료합니다.',
                onTap: _logout,
              ),
              const SizedBox(height: 22),
              _sectionTitle('정보'),
              const SizedBox(height: 8),
              _buildInfoTile(Icons.language_rounded, '콘텐츠 언어', '한국어 금융 인사이트'),
              const SizedBox(height: 10),
              _buildInfoTile(
                Icons.info_outline_rounded,
                'Insight Now',
                '시장 데이터와 투자 학습을 위한 인사이트 앱',
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  '데이터는 자동 수집되며, 투자 판단의 책임은 사용자에게 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF7189A1),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF163A58), Color(0xFF10233B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF7DD3FC).withValues(alpha: 0.22),
        ),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Color(0x284FD1C5),
            child: Icon(
              Icons.settings_rounded,
              color: Color(0xFF7DECE2),
              size: 28,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '환경설정',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '자동화 상태와 내 기기 설정을 관리하세요.',
                  style: TextStyle(color: Color(0xFFB4C8DC), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF8CA8C1),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildAutomationCard() {
    if (_statusError != null) {
      return _buildActionTile(
        icon: Icons.cloud_off_rounded,
        iconColor: const Color(0xFFE76F51),
        title: '자동화 상태 확인 필요',
        subtitle: _statusError!,
        onTap: _loadAutomationStatus,
      );
    }

    final news = _automationStatus?['news'] as Map?;
    final etfs = _automationStatus?['etfs'] as Map?;
    final gov = _automationStatus?['government_reports'] as Map?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11223A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          _statusRow(Icons.newspaper_rounded, '뉴스', _jobText(news, '2시간 주기')),
          const Divider(height: 22, color: Colors.white12),
          _statusRow(Icons.pie_chart_rounded, 'ETF', _jobText(etfs, '6시간 주기')),
          const Divider(height: 22, color: Colors.white12),
          _statusRow(
            Icons.account_balance_rounded,
            '정부 보고서',
            _jobText(gov, '24시간 주기'),
          ),
        ],
      ),
    );
  }

  String _jobText(Map? job, String schedule) {
    final state = job?['state']?.toString();
    if (state == 'success') return '정상 · $schedule';
    if (state == 'running') return '갱신 중 · $schedule';
    if (state == 'failed') return '점검 필요 · $schedule';
    return '상태 확인 중 · $schedule';
  }

  Widget _statusRow(IconData icon, String title, String value) {
    final healthy = value.startsWith('정상');
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7DECE2), size: 20),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Icon(
          healthy ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: healthy ? const Color(0xFF4FD1C5) : const Color(0xFFFFD166),
          size: 16,
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: const TextStyle(color: Color(0xFF9CB4CC), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFF11223A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9CB4CC),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8CA8C1),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1E33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8CA8C1), size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Color(0xFF9CB4CC), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
