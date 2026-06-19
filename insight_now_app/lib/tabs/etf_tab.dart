import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';
import '../screens/detail_screen.dart';

class EtfTab extends StatefulWidget {
  const EtfTab({super.key});
  @override
  State<EtfTab> createState() => _EtfTabState();
}

class _EtfTabState extends State<EtfTab> {
  List<dynamic> _etfs = [];
  bool _isLoading = true;

  final Stream<List<Map<String, dynamic>>> _etfStream = Supabase.instance.client
      .from('etf_registry')
      .stream(primaryKey: ['ticker']);

  @override
  void initState() {
    super.initState();
    _loadData();
    
    // 스트림이 감지되면 0.5초(500ms)만 기다렸다가 _loadData를 실행합니다.
    _etfStream.listen((data) async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _loadData();
      }
    });
  }

  Future<void> _loadData() async {
    try {
      final response = await http.get(Uri.parse(ApiConstants.etfEndpoint));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _etfs = json.decode(response.body);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _etfs.isEmpty
              ? const Center(child: Text("등록된 ETF가 없습니다.", style: TextStyle(color: Colors.white)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: _etfs.length,
                    itemBuilder: (context, index) {
                      final etf = _etfs[index];
                      final name = etf['name'] ?? (etf['etf_data']?['name'] ?? '정보 없음');
                      final price = etf['price'] ?? (etf['etf_data']?['price'] ?? '가격 정보 없음');

                      return ListTile(
                        title: Text(
                          '$name (${etf['ticker']})', 
                          style: const TextStyle(color: Colors.white, fontSize: 16)
                        ),
                        subtitle: Text(
                          '가격: $price', 
                          style: const TextStyle(color: Colors.redAccent, fontSize: 14)
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DetailScreen(etfData: etf),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}