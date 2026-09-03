import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  final TextEditingController _liveInput = TextEditingController();
  Timer? _refreshTimer;
  Timer? _heartbeatTimer;
  WebSocketChannel? _liveChannel;
  StreamSubscription<dynamic>? _liveSubscription;
  String _filter = 'all';
  String _nickname = '투자러';
  bool _liveConnected = false;
  int _onlineCount = 0;
  List<_LiveMessage> _liveMessages = const [];
  _CommunityProfile _profile = const _CommunityProfile.empty();

  @override
  void initState() {
    super.initState();
    _snapshot = _fetchFeed();
    _initializeLiveLounge();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted) _reload(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _heartbeatTimer?.cancel();
    _liveSubscription?.cancel();
    _liveChannel?.sink.close();
    _liveInput.dispose();
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

  Future<void> _initializeLiveLounge() async {
    final preferences = await SharedPreferences.getInstance();
    final savedNickname = preferences.getString('moneytalk_nickname');
    if (savedNickname != null && savedNickname.length >= 2) {
      _nickname = savedNickname;
    }
    await Future.wait([_loadProfile(), _loadLiveHistory()]);
    _connectLiveLounge();
  }

  Future<void> _saveNickname(String nickname) async {
    final clean = nickname.trim();
    if (clean.length < 2) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('moneytalk_nickname', clean);
    if (!mounted) return;
    setState(() => _nickname = clean);
    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/api/chat/community/profile/${Uri.encodeComponent(_nickname)}',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && body is Map && body['profile'] is Map) {
        if (mounted) {
          setState(
            () => _profile = _CommunityProfile.fromJson(
              Map<String, dynamic>.from(body['profile'] as Map),
            ),
          );
        }
      }
    } catch (_) {
      // 포인트 카드 오류가 실시간 라운지 이용을 막지 않도록 조용히 재시도합니다.
    }
  }

  Future<void> _loadLiveHistory() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/api/chat/community/live/messages?limit=50',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && body is Map) {
        final rawMessages = body['messages'];
        if (mounted && rawMessages is List) {
          setState(() {
            _liveMessages = rawMessages
                .whereType<Map>()
                .map(
                  (item) =>
                      _LiveMessage.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList();
            _onlineCount =
                (body['online_count'] as num?)?.toInt() ?? _onlineCount;
          });
        }
      }
    } catch (_) {
      // 연결되면 WebSocket 초기 메시지로 다시 복원됩니다.
    }
  }

  Uri get _liveSocketUri {
    final base = Uri.parse(ApiConstants.baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/chat/community/live',
      query: null,
    );
  }

  void _connectLiveLounge() {
    _heartbeatTimer?.cancel();
    _liveSubscription?.cancel();
    _liveChannel?.sink.close();
    try {
      final channel = WebSocketChannel.connect(_liveSocketUri);
      _liveChannel = channel;
      _liveSubscription = channel.stream.listen(
        _handleLiveEvent,
        onError: (_) => _handleLiveDisconnect(),
        onDone: _handleLiveDisconnect,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleLiveEvent(dynamic rawEvent) {
    try {
      final event = jsonDecode(rawEvent.toString());
      if (event is! Map) return;
      final type = event['type']?.toString();
      if (type == 'connected') {
        final rawMessages = event['messages'];
        if (mounted) {
          setState(() {
            _liveConnected = true;
            _onlineCount = (event['online_count'] as num?)?.toInt() ?? 0;
            _liveMessages = rawMessages is List
                ? rawMessages
                      .whereType<Map>()
                      .map(
                        (item) => _LiveMessage.fromJson(
                          Map<String, dynamic>.from(item),
                        ),
                      )
                      .toList()
                : _liveMessages;
          });
        }
        _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
          _liveChannel?.sink.add(jsonEncode({'type': 'ping'}));
        });
      } else if (type == 'live_message' && event['message'] is Map) {
        final message = _LiveMessage.fromJson(
          Map<String, dynamic>.from(event['message'] as Map),
        );
        if (mounted) {
          setState(() {
            _liveMessages = [
              ..._liveMessages.where((item) => item.id != message.id),
              message,
            ];
            _onlineCount =
                (event['online_count'] as num?)?.toInt() ?? _onlineCount;
          });
        }
        if (message.nickname == _nickname) {
          _loadProfile();
          if (message.rewardPoints > 0 && mounted) {
            _showMessage(
              '머니 포인트 +${message.rewardPoints}P · ${message.profile.title}',
            );
          }
        }
      } else if (type == 'presence') {
        if (mounted) {
          setState(
            () => _onlineCount = (event['online_count'] as num?)?.toInt() ?? 0,
          );
        }
      } else if (type == 'error' && mounted) {
        _showMessage(event['message']?.toString() ?? '라운지 메시지를 전송하지 못했습니다.');
      }
    } catch (_) {
      // 형식이 맞지 않는 네트워크 이벤트는 무시합니다.
    }
  }

  void _handleLiveDisconnect() {
    _heartbeatTimer?.cancel();
    if (mounted) setState(() => _liveConnected = false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    Timer(const Duration(seconds: 4), () {
      if (mounted && !_liveConnected) _connectLiveLounge();
    });
  }

  Future<void> _sendLiveMessage() async {
    final body = _liveInput.text.trim();
    if (body.isEmpty) return;
    _liveInput.clear();
    final payload = {'type': 'send', 'nickname': _nickname, 'body': body};
    if (_liveConnected && _liveChannel != null) {
      _liveChannel!.sink.add(jsonEncode(payload));
      return;
    }
    try {
      final response = await http
          .post(
            Uri.parse(
              '${ApiConstants.baseUrl}/api/chat/community/live/messages',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'nickname': _nickname, 'body': body}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 300) throw Exception();
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final reward = decoded is Map && decoded['message'] is Map
          ? (decoded['message'] as Map)['reward']
          : null;
      final awarded = reward is Map
          ? (reward['awarded'] as num?)?.toInt() ?? 0
          : 0;
      if (awarded > 0 && mounted) {
        _showMessage('머니 포인트 +${awarded}P · 실시간 라운지 참여');
      }
      await _loadLiveHistory();
      await _loadProfile();
    } catch (_) {
      if (mounted) _showMessage('실시간 라운지에 메시지를 보내지 못했습니다.');
    }
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

  Future<void> _openDiscussion(_CommunityPost post) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DiscussionSheet(post: post, initialNickname: _nickname),
    );
    if (updated != null) {
      await _saveNickname(updated['nickname']?.toString() ?? _nickname);
      await _reload(silent: true);
      _showReward(updated['reward']);
    }
  }

  Future<void> _openComposer({String initialKind = 'proof'}) async {
    final posted = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ComposerSheet(initialKind: initialKind, initialNickname: _nickname),
    );
    if (posted != null) {
      await _saveNickname(posted['nickname']?.toString() ?? _nickname);
      await _reload(silent: true);
      _showReward(posted['reward']);
    }
  }

  void _showReward(dynamic reward) {
    if (reward is! Map) return;
    final awarded = (reward['awarded'] as num?)?.toInt() ?? 0;
    if (awarded <= 0) return;
    final title = reward['title']?.toString() ?? '새싹 개미';
    _showMessage('머니 포인트 +${awarded}P · $title');
  }

  Future<String?> _askNickname() async {
    final controller = TextEditingController(text: _nickname);
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
            onPressed: () async {
              final nickname = controller.text.trim();
              await _saveNickname(nickname);
              if (context.mounted) Navigator.pop(context, nickname);
            },
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
      resizeToAvoidBottomInset: true,
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildHero(feed),
                  const SizedBox(height: 16),
                  _buildLiveLounge(),
                  const SizedBox(height: 14),
                  _buildArcadeCard(),
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

  Widget _buildLiveLounge() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _mint.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _mint.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.forum_rounded, color: _mint, size: 19),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '불타는 개미 라운지',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '실시간 투자 대화 · 매수·매도 권유는 금지',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _liveStateBadge(),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              await _askNickname();
              await _loadProfile();
            },
            borderRadius: BorderRadius.circular(13),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Text(_profile.badge, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '$_nickname · ${_profile.title} · ${_profile.points}P',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.edit_rounded,
                    color: Colors.white38,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '머니 포인트는 현금화·양도·거래가 불가능한 명예·배지용 포인트입니다.',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: _liveMessages.isEmpty
                ? const Center(
                    child: Text(
                      '지금 라운지의 첫 대화를 시작해 보세요.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    reverse: true,
                    itemCount: _liveMessages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final message =
                          _liveMessages[_liveMessages.length - 1 - index];
                      return _buildLiveMessage(message);
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _liveInput,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendLiveMessage(),
                  maxLength: 300,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: _liveConnected
                        ? '지금 시장은 어떤가요?'
                        : '연결을 복구하는 중입니다…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sendLiveMessage,
                style: IconButton.styleFrom(
                  backgroundColor: _mint,
                  foregroundColor: const Color(0xFF102033),
                ),
                icon: const Icon(Icons.send_rounded, size: 19),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveStateBadge() {
    final label = _liveConnected ? 'LIVE $_onlineCount명' : '연결 중';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (_liveConnected ? _mint : Colors.white54).withValues(
          alpha: 0.14,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _liveConnected ? _mint : Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLiveMessage(_LiveMessage message) {
    final mine = message.nickname == _nickname;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 275),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: mine
              ? _mint.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${message.profile.badge} ${message.nickname} · ${message.profile.title}',
              style: TextStyle(
                color: mine ? _mint : _gold,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              message.body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openArcade() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PointArcadeSheet(initialNickname: _nickname),
    );
    await _loadProfile();
  }

  Widget _buildArcadeCard() {
    return InkWell(
      onTap: _openArcade,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3B275E), Color(0xFF172A46)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFC084FC).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFC084FC).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.casino_rounded,
                color: Color(0xFFE9D5FF),
                size: 27,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '머니 슬롯 · 포인트 놀이터',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '9칸 슬롯 · 드랍볼 · 동물 러닝 3종 게임',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '현금화·환전 불가 · 한 번 최대 20P',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Text(
                  '${_profile.points}P',
                  style: const TextStyle(
                    color: Color(0xFFF6C85F),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white60),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickAction(Icons.verified_rounded, '인증 올리기', 'proof', _gold),
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
              InkWell(
                onTap: () => _openDiscussion(post),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.white38,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.commentCount} 대화',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
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
  const _ComposerSheet({
    required this.initialKind,
    required this.initialNickname,
  });

  final String initialKind;
  final String initialNickname;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  late final TextEditingController _nickname;
  final _body = TextEditingController();
  final _ticker = TextEditingController();
  final _performance = TextEditingController();
  late String _kind;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _nickname = TextEditingController(text: widget.initialNickname);
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
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (mounted) {
        Navigator.pop(context, {
          'nickname': _nickname.text.trim(),
          'reward': decoded is Map ? decoded['reward'] : null,
        });
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

class _DiscussionSheet extends StatefulWidget {
  const _DiscussionSheet({required this.post, required this.initialNickname});

  final _CommunityPost post;
  final String initialNickname;

  @override
  State<_DiscussionSheet> createState() => _DiscussionSheetState();
}

class _DiscussionSheetState extends State<_DiscussionSheet> {
  late final TextEditingController _nickname;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _nickname.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nickname.text.trim().length < 2 || _comment.text.trim().isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/api/chat/community/comments'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'nickname': _nickname.text.trim(),
              'post_id': widget.post.id,
              'body': _comment.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 18));
      if (response.statusCode >= 300) {
        throw Exception();
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (mounted) {
        Navigator.pop(context, {
          'nickname': _nickname.text.trim(),
          'reward': decoded is Map ? decoded['reward'] : null,
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('대화를 남기지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 36, 12, bottom + 12),
      child: Material(
        color: const Color(0xFF10233B),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_rounded, color: Color(0xFF4FD1C5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.post.nickname}의 투자 이야기',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.post.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, height: 1.4),
                ),
              ),
              const Divider(color: Colors.white12, height: 24),
              Expanded(
                child: widget.post.comments.isEmpty
                    ? const Center(
                        child: Text(
                          '첫 번째 대화를 남겨 보세요.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.post.comments.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: Colors.white10, height: 20),
                        itemBuilder: (context, index) {
                          final comment = widget.post.comments[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${comment.nickname} · ${comment.timeAgo}',
                                style: const TextStyle(
                                  color: Color(0xFF4FD1C5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                comment.body,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.42,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              const Divider(color: Colors.white12, height: 20),
              TextField(
                controller: _nickname,
                maxLength: 18,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('표시 이름'),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      maxLength: 400,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('건설적인 대화를 남겨 주세요.'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _submitting ? null : _submit,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF6C85F),
                      foregroundColor: const Color(0xFF172030),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
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
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4FD1C5)),
      ),
      counterStyle: const TextStyle(color: Colors.white38),
      isDense: true,
    );
  }
}

class _PointArcadeSheet extends StatefulWidget {
  const _PointArcadeSheet({required this.initialNickname});

  final String initialNickname;

  @override
  State<_PointArcadeSheet> createState() => _PointArcadeSheetState();
}

class _PointArcadeSheetState extends State<_PointArcadeSheet> {
  static const _surface = Color(0xFF10233B);
  static const _mint = Color(0xFF4FD1C5);
  static const _gold = Color(0xFFF6C85F);
  static const _purple = Color(0xFFC084FC);

  late final String _nickname;
  _CommunityProfile _profile = const _CommunityProfile.empty();
  String _game = 'hub';
  int _wager = 5;
  bool _autoMode = false;
  bool _autoPlaying = false;
  bool _spinning = false;
  bool _loading = true;
  String _animal = '고양이';
  String? _message;
  int? _lastNet;
  List<String> _slotBoard = List<String>.filled(9, '🍒');
  List<Map<String, dynamic>> _path = const [];
  int _dropBucket = 0;
  String _dropLabel = '';
  List<Map<String, dynamic>> _runnerEvents = const [];
  bool _runnerGameOver = false;

  Timer? _animationTimer;

  @override
  void initState() {
    super.initState();
    _nickname = widget.initialNickname;
    _loadProfile();
  }

  @override
  void dispose() {
    _autoPlaying = false;
    _animationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${ApiConstants.baseUrl}/api/chat/community/game/profile/${Uri.encodeComponent(_nickname)}',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(_errorText(body, '포인트를 불러오지 못했습니다.'));
      }
      if (body is Map && body['profile'] is Map && mounted) {
        setState(() {
          _profile = _CommunityProfile.fromJson(
            Map<String, dynamic>.from(body['profile'] as Map),
          );
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = _cleanError(error);
        });
      }
    }
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  String _errorText(dynamic body, String fallback) {
    final detail = body is Map ? body['detail'] : null;
    if (detail is List) {
      return detail
          .map(
            (item) =>
                item is Map ? item['msg'] ?? item.toString() : item.toString(),
          )
          .join(' ');
    }
    if (detail is Map) return detail['msg']?.toString() ?? fallback;
    return detail?.toString() ?? fallback;
  }

  Future<Map<String, dynamic>> _requestGame(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final response = await http
        .post(
          Uri.parse(
            '${ApiConstants.baseUrl}/api/chat/community/game/$endpoint',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 300) {
      throw Exception(_errorText(body, '게임을 실행하지 못했습니다.'));
    }
    final game = body is Map && body['game'] is Map
        ? Map<String, dynamic>.from(body['game'] as Map)
        : <String, dynamic>{};
    if (game['profile'] is Map && mounted) {
      _profile = _CommunityProfile.fromJson(
        Map<String, dynamic>.from(game['profile'] as Map),
      );
    }

    return game;
  }

  Future<void> _runOnce() async {
    if (_spinning || _profile.points < _wager) return;
    setState(() {
      _spinning = true;
      _message = null;
      _lastNet = null;
    });
    try {
      late final Map<String, dynamic> game;
      if (_game == 'slot777') {
        game = await _requestGame('slot777', {
          'nickname': _nickname,
          'wager': _wager,
        });
        _animateSlot(
          game['board'] is List
              ? (game['board'] as List).map((item) => item.toString()).toList()
              : _slotBoard,
        );
      } else if (_game == 'dropball') {
        game = await _requestGame('dropball', {
          'nickname': _nickname,
          'wager': _wager,
        });
      } else {
        game = await _requestGame('runner', {
          'nickname': _nickname,
          'wager': _wager,
          'animal': _animal,
        });
      }
      if (!mounted) return;
      setState(() {
        _lastNet = (game['net'] as num?)?.toInt() ?? 0;
        if (_game == 'slot777') {
          _slotBoard = game['board'] is List
              ? (game['board'] as List).map((item) => item.toString()).toList()
              : _slotBoard;
          _message = _lastNet! > 0
              ? '+${_lastNet}P 획득 · ${game['multiplier'] ?? 0}배!'
              : '${_lastNet}P 정산되었습니다.';
        } else if (_game == 'dropball') {
          _path = game['path'] is List
              ? (game['path'] as List)
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList()
              : const [];
          _dropBucket = (game['bucket_index'] as num?)?.toInt() ?? 0;
          _dropLabel = game['bucket_label']?.toString() ?? '';
          _message =
              '${_dropLabel.isEmpty ? '결과' : _dropLabel} · ${_lastNet! >= 0 ? '+' : ''}${_lastNet}P';
        } else {
          _runnerEvents = game['events'] is List
              ? (game['events'] as List)
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList()
              : const [];
          _runnerGameOver = game['game_over'] == true;
          _message = _runnerGameOver
              ? '폭탄 상자에 닿았습니다. ${_lastNet}P 정산'
              : '${game['multiplier'] ?? 0}배 안전 돌파 · ${_lastNet! >= 0 ? '+' : ''}${_lastNet}P';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _message = _cleanError(error));
    } finally {
      _animationTimer?.cancel();
      _animationTimer = null;
      if (mounted) setState(() => _spinning = false);
    }
  }

  void _animateSlot(List<String> finalBoard) {
    final random = Random();
    _animationTimer?.cancel();
    _animationTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(
        () => _slotBoard = List.generate(
          9,
          (_) => const ['🍒', '🔔', '⭐', '💎', '7️⃣'][random.nextInt(5)],
        ),
      );
    });
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _slotBoard = finalBoard);
    });
  }

  Future<void> _startAuto() async {
    if (_autoPlaying || _profile.points < _wager) return;
    setState(() {
      _autoPlaying = true;
      _autoMode = true;
      _message = '자동 플레이를 시작했습니다.';
    });
    var rounds = 0;
    try {
      while (mounted &&
          _autoPlaying &&
          _profile.points >= _wager &&
          rounds < 100) {
        await _runOnce();
        rounds += 1;
        if (mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 420));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _autoPlaying = false;
          _message = _profile.points < _wager
              ? '포인트가 부족해 자동 플레이를 멈췄습니다.'
              : rounds >= 100
              ? '자동 플레이 100회가 끝났습니다. 계속하려면 다시 시작하세요.'
              : '자동 플레이를 멈췄습니다.';
        });
      }
    }
  }

  void _stopAuto() {
    if (mounted) setState(() => _autoPlaying = false);
  }

  void _selectGame(String game) => setState(() {
    _game = game;
    _message = null;
    _lastNet = null;
  });

  Future<void> _playWithWager(int amount) async {
    if (_spinning || _autoPlaying || _loading || _profile.points < amount) {
      return;
    }
    setState(() => _wager = amount);
    if (_autoMode) {
      await _startAuto();
    } else {
      await _runOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 22, 12, bottom + 12),
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(26),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: _game == 'hub' ? _buildHub() : _buildGame(),
          ),
        ),
      ),
    );
  }

  Widget _header(String title, IconData icon, {bool back = false}) {
    return Row(
      children: [
        if (back)
          IconButton(
            onPressed: () => _selectGame('hub'),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          ),
        Icon(icon, color: _purple),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _balance() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.account_balance_wallet_rounded,
          color: _gold,
          size: 18,
        ),
        const SizedBox(width: 7),
        const Text(
          '내 잔액',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          _loading ? '확인 중…' : '${_profile.points}P',
          style: const TextStyle(
            color: _gold,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _buildHub() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('머니 포인트 놀이터', Icons.casino_rounded),
          const Text(
            '3가지 게임 · 수동/자동 플레이',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _balance(),
          const SizedBox(height: 14),
          _gameCard(
            'slot777',
            '9칸 일확천금 777',
            '3×3 전체가 회전하는 클래식 슬롯',
            Icons.grid_view_rounded,
            const Color(0xFFC084FC),
            '88% 일반 보드 · 12% 당첨 보드',
          ),
          _gameCard(
            'dropball',
            '드랍볼 곱하기 파이낸스',
            '구슬 경로를 따라 배율 칸에 도착',
            Icons.sports_baseball_rounded,
            const Color(0xFF60A5FA),
            '꽝 40% · 1배 35% · 10배 1% 공개 확률',
          ),
          _gameCard(
            'runner',
            '동물 상자 러닝 배틀',
            '동물을 고르고 상자를 타이밍 돌파',
            Icons.pets_rounded,
            const Color(0xFF4FD1C5),
            '폭탄 상자 45% · 즉시 게임 오버',
          ),
          const SizedBox(height: 8),
          const Text(
            '현금화·환전·양도 불가 포인트 전용입니다. 하루 제한 없이 잔액 범위에서 이용하며, 한 번에 최대 20P입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _gameCard(
    String game,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    String rule,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () => _selectGame(game),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rule,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGame() {
    final title = _game == 'slot777'
        ? '9칸 일확천금 777'
        : _game == 'dropball'
        ? '드랍볼 곱하기 파이낸스'
        : '동물 상자 러닝 배틀';
    final icon = _game == 'slot777'
        ? Icons.grid_view_rounded
        : _game == 'dropball'
        ? Icons.sports_baseball_rounded
        : Icons.pets_rounded;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(title, icon, back: true),
          _balance(),
          const SizedBox(height: 12),
          if (_game == 'slot777')
            _slotView()
          else if (_game == 'dropball')
            _dropballView()
          else
            _runnerView(),
          const SizedBox(height: 12),
          if (_message != null)
            Center(
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: (_lastNet ?? 0) >= 0 ? _mint : const Color(0xFFFB7185),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 10),
          _modeControls(),
          const SizedBox(height: 8),
          _wagerControls(),
          const SizedBox(height: 12),
          if (_autoPlaying)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _stopAuto,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('자동 플레이 중지'),
              ),
            ),
          const SizedBox(height: 7),
          const Text(
            '결과는 서버에서 생성·정산됩니다. 게임 확률은 운영 화면의 공개 정책을 따릅니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _modeControls() => Row(
    children: [
      const Text(
        '플레이 모드',
        style: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      const SizedBox(width: 8),
      ChoiceChip(
        label: const Text('수동'),
        selected: !_autoMode,
        onSelected: _autoPlaying
            ? null
            : (_) => setState(() => _autoMode = false),
        selectedColor: _mint.withValues(alpha: 0.25),
        labelStyle: TextStyle(color: !_autoMode ? _mint : Colors.white60),
      ),
      const SizedBox(width: 7),
      ChoiceChip(
        label: const Text('자동'),
        selected: _autoMode,
        onSelected: _autoPlaying
            ? null
            : (_) => setState(() => _autoMode = true),
        selectedColor: _purple.withValues(alpha: 0.3),
        labelStyle: TextStyle(color: _autoMode ? _purple : Colors.white60),
      ),
    ],
  );

  Widget _wagerControls() {
    return Row(
      children: [1, 5, 10, 20]
          .map(
            (amount) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: amount == 20 ? 0 : 6),
                child: FilledButton(
                  onPressed:
                      _spinning ||
                          _autoPlaying ||
                          _loading ||
                          _profile.points < amount
                      ? null
                      : () => _playWithWager(amount),
                  style: FilledButton.styleFrom(
                    backgroundColor: amount == _wager
                        ? _purple
                        : Colors.white10,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: Text(
                    '${amount}P ${_autoMode ? '자동 시작' : '실행'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _slotView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF24173C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _purple.withValues(alpha: 0.35)),
          ),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: _slotBoard
                .map(
                  (symbol) => Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gold.withValues(alpha: 0.3)),
                    ),
                    child: Text(symbol, style: const TextStyle(fontSize: 30)),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '같은 심볼 3개가 한 줄이면 당첨 · 전체 확률표는 게임 안내에 공개',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _dropballView() => Column(
    children: [
      Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0C1C32),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF60A5FA).withValues(alpha: 0.35),
          ),
        ),
        child: Stack(
          children: [
            for (var row = 1; row < 8; row++)
              Positioned(
                top: row * 24.0,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    row + 1,
                    (_) => const Icon(
                      Icons.circle,
                      size: 5,
                      color: Colors.white30,
                    ),
                  ),
                ),
              ),
            if (_path.isNotEmpty)
              ..._path.map(
                (point) => Positioned(
                  left: ((point['x'] as num? ?? 50).toDouble() / 100) * 300,
                  top: ((point['y'] as num? ?? 50).toDouble() / 100) * 190,
                  child: const Icon(
                    Icons.circle,
                    size: 8,
                    color: Color(0xFF60A5FA),
                  ),
                ),
              ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    '꽝',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    '1배',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '2배',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '3배',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '5배',
                    style: TextStyle(color: Color(0xFFF6C85F), fontSize: 11),
                  ),
                  Text(
                    '10배',
                    style: TextStyle(color: Color(0xFFF6C85F), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      Text(
        _dropLabel.isEmpty
            ? '구슬이 경로를 따라 내려갑니다.'
            : '도착: $_dropLabel · ${_dropBucket + 1}번 구간',
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      ),
    ],
  );

  Widget _runnerView() => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ['고양이', '강아지', '여우', '토끼']
            .map(
              (animal) => ChoiceChip(
                label: Text(animal),
                selected: _animal == animal,
                onSelected: _spinning || _autoPlaying
                    ? null
                    : (_) => setState(() => _animal = animal),
                selectedColor: _mint.withValues(alpha: 0.25),
                labelStyle: TextStyle(
                  color: _animal == animal ? _mint : Colors.white60,
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 10),
      Container(
        height: 155,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF132A31),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _mint.withValues(alpha: 0.35)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 20,
              right: 20,
              bottom: 35,
              child: Container(height: 5, color: Colors.white24),
            ),
            Positioned(
              left: 32,
              bottom: 48,
              child: Text(
                _runnerGameOver
                    ? '💥'
                    : _animal == '고양이'
                    ? '🐈'
                    : _animal == '강아지'
                    ? '🐕'
                    : _animal == '여우'
                    ? '🦊'
                    : '🐇',
                style: const TextStyle(fontSize: 42),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Text(
                _runnerEvents.isEmpty
                    ? '상자를 터치할 타이밍을 잡아 보세요.'
                    : _runnerEvents
                          .map(
                            (event) => event['kind'] == 'bomb'
                                ? '💣'
                                : '${event['multiplier'] ?? 0}배',
                          )
                          .join('  →  '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Positioned(
              right: 28,
              bottom: 42,
              child: Text('📦  📦  📦', style: TextStyle(fontSize: 25)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        '안전 상자는 누적 배율, 폭탄 상자는 즉시 게임 오버입니다.',
        style: TextStyle(color: Colors.white54, fontSize: 10),
      ),
    ],
  );
}

class _CommunityProfile {
  const _CommunityProfile({
    required this.points,
    required this.level,
    required this.title,
    required this.badge,
    required this.nextLevelPoints,
  });

  const _CommunityProfile.empty()
    : points = 0,
      level = 1,
      title = '새싹 개미',
      badge = '🌱',
      nextLevelPoints = 60;

  final int points;
  final int level;
  final String title;
  final String badge;
  final int? nextLevelPoints;

  factory _CommunityProfile.fromJson(Map<String, dynamic> json) {
    return _CommunityProfile(
      points: (json['points'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? '새싹 개미',
      badge: json['badge']?.toString() ?? '🌱',
      nextLevelPoints: (json['next_level_points'] as num?)?.toInt(),
    );
  }
}

class _LiveMessage {
  const _LiveMessage({
    required this.id,
    required this.nickname,
    required this.body,
    required this.createdAt,
    required this.profile,
    required this.rewardPoints,
  });

  final String id;
  final String nickname;
  final String body;
  final DateTime? createdAt;
  final _CommunityProfile profile;
  final int rewardPoints;

  factory _LiveMessage.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profile'];
    return _LiveMessage(
      id: json['id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '익명 개미',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? '',
      )?.toLocal(),
      profile: rawProfile is Map
          ? _CommunityProfile.fromJson(Map<String, dynamic>.from(rawProfile))
          : const _CommunityProfile.empty(),
      rewardPoints: json['reward'] is Map
          ? ((json['reward'] as Map)['awarded'] as num?)?.toInt() ?? 0
          : 0,
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
    required this.comments,
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
  final List<_CommunityComment> comments;

  factory _CommunityPost.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'];
    final reactions = <String, int>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        reactions[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    final rawComments = json['comments'];
    final comments = rawComments is List
        ? rawComments
              .whereType<Map>()
              .map(
                (item) =>
                    _CommunityComment.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <_CommunityComment>[];
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
      comments: comments,
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

class _CommunityComment {
  const _CommunityComment({
    required this.id,
    required this.nickname,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String nickname;
  final String body;
  final DateTime? createdAt;

  factory _CommunityComment.fromJson(Map<String, dynamic> json) {
    return _CommunityComment(
      id: json['id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '익명 개미',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

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
