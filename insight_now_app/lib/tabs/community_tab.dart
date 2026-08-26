import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF071221);
  static const _surface = Color(0xFF10233B);
  static const _gold = Color(0xFFF6C85F);
  static const _mint = Color(0xFF4FD1C5);

  late Future<_CommunitySnapshot> _snapshot;
  Timer? _refreshTimer;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _snapshot = _fetchFeed();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) _reload(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<_CommunitySnapshot> _fetchFeed() async {
    final response = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}/api/chat/community/feed?limit=40'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw Exception('커뮤니티 피드를 불러오지 못했습니다.');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw Exception('커뮤니티 응답 형식이 올바르지 않습니다.');
    }
    return _CommunitySnapshot.fromJson(body);
  }

  Future<void> _reload({bool silent = false}) async {
    setState(() => _snapshot = _fetchFeed());
    try {
      await _snapshot;
    } catch (_) {
      if (!silent && mounted) {
        _showMessage('새로운 글을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    }
  }

  Future<void> _react(_CommunityPost post, String reaction) async {
    final nickname = await _askNickname();
    if (nickname == null) return;
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/api/chat/community/reactions'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'nickname': nickname,
              'post_id': post.id,
              'reaction': reaction,
            }),
          )
          .timeout(const Duration(seconds: 18));
      if (response.statusCode >= 300) throw Exception();
      await _reload(silent: true);
    } catch (_) {
      if (mounted) _showMessage('반응을 남기지 못했습니다.');
    }
  }

  Future<void> _openComposer({String initialKind = 'proof'}) async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposerSheet(initialKind: initialKind),
    );
    if (posted == true) await _reload(silent: true);
  }

  Future<String?> _askNickname() async {
    final controller = TextEditingController(text: '투자러');
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('표시 이름', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 18,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '예: 상승장_사령관',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return nickname == null || nickname.length < 2 ? null : nickname;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComposer,
        backgroundColor: _gold,
        foregroundColor: const Color(0xFF172030),
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text(
          '인증 올리기',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<_CommunitySnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            final feed = snapshot.data ?? const _CommunitySnapshot.empty();
            return RefreshIndicator(
              color: _mint,
              backgroundColor: _surface,
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                children: [
                  _buildHero(feed),
                  const SizedBox(height: 16),
                  _buildQuickActions(),
                  const SizedBox(height: 20),
                  _buildFilter(),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 88),
                      child: Center(
                        child: CircularProgressIndicator(color: _gold),
                      ),
                    )
                  else if (snapshot.hasError)
                    _buildError()
                  else if (_visiblePosts(feed.posts).isEmpty)
                    _buildEmpty()
                  else
                    ..._visiblePosts(feed.posts).map(_buildPost),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(_CommunitySnapshot feed) {
    final champion = feed.hallOfFame.isEmpty ? null : feed.hallOfFame.first;
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF153A5B), Color(0xFF132238), Color(0xFF1C3450)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: _gold),
              SizedBox(width: 8),
              Text(
                '머니톡',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              _AutoBadge(),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '수익은 인증하고, 인사이트는 남기고,\n함께 다음 기회를 기록하세요.',
            style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: _gold),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    champion == null
                        ? '이번 주 첫 명예의 전당 주인공이 되어 보세요.'
                        : '이번 주 리더 · ${champion.nickname} ${champion.performanceLabel}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickAction(Icons.verified_rounded, '수익 인증', 'proof', _gold),
        const SizedBox(width: 10),
        _quickAction(Icons.explore_rounded, '오늘의 예측', 'prediction', _mint),
        const SizedBox(width: 10),
        _quickAction(
          Icons.forum_rounded,
          '개미 라운지',
          'lounge',
          const Color(0xFF7DD3FC),
        ),
      ],
    );
  }

  Widget _quickAction(IconData icon, String label, String kind, Color color) {
    return Expanded(
      child: InkWell(
        onTap: () => _openComposer(initialKind: kind),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 7),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.26)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilter() {
    final options = const [
      ('all', '전체'),
      ('proof', '인증'),
      ('prediction', '예측'),
      ('lounge', '라운지'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = _filter == option.$1;
          return ChoiceChip(
            label: Text(option.$2),
            selected: selected,
            onSelected: (_) => setState(() => _filter = option.$1),
            selectedColor: _gold.withValues(alpha: 0.21),
            backgroundColor: _surface,
            side: BorderSide(color: selected ? _gold : Colors.white12),
            labelStyle: TextStyle(
              color: selected ? _gold : Colors.white60,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  List<_CommunityPost> _visiblePosts(List<_CommunityPost> posts) {
    return _filter == 'all'
        ? posts
        : posts.where((post) => post.kind == _filter).toList();
  }

  Widget _buildPost(_CommunityPost post) {
    final config = _kindConfig(post.kind);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: config.color.withValues(alpha: 0.18),
                child: Icon(config.icon, color: config.color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${config.label} · ${post.timeAgo}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.ticker != null)
                _pill(post.ticker!, const Color(0xFF7DD3FC)),
              if (post.performance != null) ...[
                const SizedBox(width: 6),
                _pill(
                  post.performanceLabel,
                  post.performance! >= 0 ? _mint : const Color(0xFFFB7185),
                ),
              ],
            ],
          ),
          const SizedBox(height: 13),
          Text(
            post.body,
            style: const TextStyle(
              color: Colors.white,
              height: 1.52,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              _reactionButton(post, '🔥', '대박'),
              const SizedBox(width: 7),
              _reactionButton(post, '👏', '응원'),
              const SizedBox(width: 7),
              _reactionButton(post, '📌', '저장'),
              const Spacer(),
              Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white38,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${post.commentCount}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reactionButton(_CommunityPost post, String emoji, String label) {
    final count = post.reactions[emoji] ?? 0;
    return InkWell(
      onTap: () => _react(post, emoji),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$emoji $count',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 68),
      child: Column(
        children: [
          const Icon(Icons.groups_rounded, color: Colors.white24, size: 58),
          const SizedBox(height: 14),
          const Text(
            '첫 번째 투자 이야기를 남겨 보세요.',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '수익 인증, 종목 관찰, 시장 생각을 안전하게 공유할 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 68),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 52),
          const SizedBox(height: 14),
          const Text(
            '커뮤니티를 준비 중입니다.',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  _KindConfig _kindConfig(String kind) {
    switch (kind) {
      case 'proof':
        return const _KindConfig('수익 인증', Icons.verified_rounded, _gold);
      case 'prediction':
        return const _KindConfig('오늘의 예측', Icons.explore_rounded, _mint);
      default:
        return const _KindConfig(
          '개미 라운지',
          Icons.forum_rounded,
          Color(0xFF7DD3FC),
        );
    }
  }
}

class _AutoBadge extends StatelessWidget {
  const _AutoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF4FD1C5).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Text(
        'LIVE · 45초 갱신',
        style: TextStyle(
          color: Color(0xFF4FD1C5),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({required this.initialKind});

  final String initialKind;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  final _nickname = TextEditingController(text: '투자러');
  final _body = TextEditingController();
  final _ticker = TextEditingController();
  final _performance = TextEditingController();
  late String _kind;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _body.dispose();
    _ticker.dispose();
    _performance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nickname.text.trim().length < 2 || _body.text.trim().isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final performance = double.tryParse(
        _performance.text.replaceAll('%', '').trim(),
      );
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/api/chat/community/posts'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'nickname': _nickname.text.trim(),
              'kind': _kind,
              'body': _body.text.trim(),
              'ticker': _ticker.text.trim().isEmpty
                  ? null
                  : _ticker.text.trim(),
              'performance': _kind == 'proof' ? performance : null,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 300) {
        throw Exception();
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글을 올리지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      child: Material(
        color: const Color(0xFF10233B),
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '머니톡에 기록하기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '수익과 예측은 자랑하되, 타인의 판단을 존중해 주세요.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  dropdownColor: const Color(0xFF18304D),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('글 종류'),
                  items: const [
                    DropdownMenuItem(value: 'proof', child: Text('수익 인증')),
                    DropdownMenuItem(
                      value: 'prediction',
                      child: Text('오늘의 예측'),
                    ),
                    DropdownMenuItem(value: 'lounge', child: Text('개미 라운지')),
                  ],
                  onChanged: (value) =>
                      setState(() => _kind = value ?? 'lounge'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nickname,
                  maxLength: 18,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('표시 이름'),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ticker,
                        maxLength: 16,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration('종목 코드 · 선택'),
                      ),
                    ),
                    if (_kind == 'proof') ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 112,
                        child: TextField(
                          controller: _performance,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('수익률 %'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _body,
                  maxLines: 5,
                  maxLength: 700,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(
                    '오늘의 투자 기록을 남겨 보세요.',
                  ).copyWith(alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF6C85F),
                      foregroundColor: const Color(0xFF172030),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.publish_rounded),
                    label: Text(
                      _submitting ? '올리는 중...' : '머니톡에 올리기',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFF6C85F)),
      ),
      counterStyle: const TextStyle(color: Colors.white38),
    );
  }
}

class _CommunitySnapshot {
  const _CommunitySnapshot({required this.posts, required this.hallOfFame});
  const _CommunitySnapshot.empty() : posts = const [], hallOfFame = const [];

  final List<_CommunityPost> posts;
  final List<_CommunityPost> hallOfFame;

  factory _CommunitySnapshot.fromJson(Map<String, dynamic> json) {
    List<_CommunityPost> parse(dynamic value) => value is List
        ? value
              .whereType<Map>()
              .map(
                (item) =>
                    _CommunityPost.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const [];
    return _CommunitySnapshot(
      posts: parse(json['posts']),
      hallOfFame: parse(json['hall_of_fame']),
    );
  }
}

class _CommunityPost {
  const _CommunityPost({
    required this.id,
    required this.kind,
    required this.nickname,
    required this.body,
    required this.ticker,
    required this.performance,
    required this.createdAt,
    required this.reactions,
    required this.commentCount,
  });

  final String id;
  final String kind;
  final String nickname;
  final String body;
  final String? ticker;
  final double? performance;
  final DateTime? createdAt;
  final Map<String, int> reactions;
  final int commentCount;

  factory _CommunityPost.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'];
    final reactions = <String, int>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        reactions[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return _CommunityPost(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'lounge',
      nickname: json['nickname']?.toString() ?? '익명 개미',
      body: json['body']?.toString() ?? '',
      ticker: json['ticker']?.toString(),
      performance: (json['performance'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? '',
      )?.toLocal(),
      reactions: reactions,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
    );
  }

  String get performanceLabel => performance == null
      ? ''
      : '${performance! >= 0 ? '+' : ''}${performance!.toStringAsFixed(1)}%';

  String get timeAgo {
    if (createdAt == null) return '방금 전';
    final difference = DateTime.now().difference(createdAt!);
    if (difference.inDays > 0) return '${difference.inDays}일 전';
    if (difference.inHours > 0) return '${difference.inHours}시간 전';
    if (difference.inMinutes > 0) return '${difference.inMinutes}분 전';
    return '방금 전';
  }
}

class _KindConfig {
  const _KindConfig(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}
