import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

class GovStatsTab extends StatefulWidget {
  const GovStatsTab({super.key});

  @override
  State<GovStatsTab> createState() => _GovStatsTabState();
}

class _GovStatsTabState extends State<GovStatsTab> {
  late Future<List<Map<String, dynamic>>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = _fetchReports();
  }

  Future<List<Map<String, dynamic>>> _fetchReports() async {
    final response = await http
        .get(Uri.parse(ApiConstants.govStatsEndpoint))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('정부 경제보고서를 불러오지 못했습니다.');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rawReports = decoded is Map<String, dynamic>
        ? decoded['reports']
        : <dynamic>[];
    return rawReports is List
        ? rawReports
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
  }

  Future<void> _refresh() async {
    setState(() {
      _reports = _fetchReports();
    });
    await _reports;
  }

  String _cleanContent(dynamic value) {
    final content = value?.toString() ?? '';
    return content.replaceAll(RegExp(r'\[cite:\s*\d+\]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09111F),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('정부 경제 정밀분석', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              '공식 보고서 기반 자동 브리핑',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reports,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4FD1C5)),
            );
          }
          if (snapshot.hasError) {
            return _buildStatus(
              icon: Icons.cloud_off_outlined,
              message: '정부 경제보고서를 불러오지 못했습니다.',
              buttonLabel: '다시 시도',
            );
          }

          final reports = snapshot.data ?? [];
          if (reports.isEmpty) {
            return _buildStatus(
              icon: Icons.account_balance_outlined,
              message: '아직 등록된 경제 정밀분석 보고서가 없습니다.',
              buttonLabel: '새로고침',
            );
          }

          return RefreshIndicator(
            color: const Color(0xFF4FD1C5),
            backgroundColor: const Color(0xFF132238),
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: reports.length,
              itemBuilder: (context, index) => _buildReportCard(reports[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatus({
    required IconData icon,
    required String message,
    required String buttonLabel,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 52),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF132238),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4FD1C5).withOpacity(0.18)),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: const Color(0xFF4FD1C5),
        collapsedIconColor: Colors.white54,
        title: Text(
          report['title']?.toString() ?? '제목 없음',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '공식 경제동향 · 자동 업데이트',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            child: MarkdownBody(
              data: _cleanContent(report['content']),
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: Colors.white70, height: 1.65),
                h1: const TextStyle(
                  color: Color(0xFF7DD3FC),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
                h2: const TextStyle(
                  color: Color(0xFF4FD1C5),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                a: const TextStyle(color: Color(0xFF7DD3FC)),
                listBullet: const TextStyle(color: Color(0xFF4FD1C5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
