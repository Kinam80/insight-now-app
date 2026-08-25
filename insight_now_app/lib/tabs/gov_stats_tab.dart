import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GovStatsTab extends StatefulWidget {
  const GovStatsTab({super.key});
  @override
  State<GovStatsTab> createState() => _GovStatsTabState();
}

class _GovStatsTabState extends State<GovStatsTab> {
  final _supabase = Supabase.instance.client;

  String _cleanContent(dynamic value) {
    final content = value?.toString() ?? '';
    return content.replaceAll(RegExp(r'\[cite:\s*\d+\]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('gov_stats')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final stats = snapshot.data!;

          return ListView.builder(
            itemCount: stats.length,
            itemBuilder: (context, index) {
              final stat = stats[index];
              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ExpansionTile(
                  title: Text(
                    stat['title'] ?? '제목 없음',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: MarkdownBody(
                        data: _cleanContent(stat['content']),
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(color: Colors.white70),
                          h1: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 20,
                          ),
                          h2: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 18,
                          ),
                          listBullet: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
