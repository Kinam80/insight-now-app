import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../screens/detail_screen.dart'; // DetailScreen 파일 경로에 맞게 확인하세요

class EtfTab extends StatefulWidget {
  const EtfTab({super.key});
  @override
  State<EtfTab> createState() => _EtfTabState();
}

class _EtfTabState extends State<EtfTab> {
  Future<List<dynamic>> fetchEtfData() async {
    final response = await http.get(Uri.parse(ApiConstants.etfEndpoint));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('데이터 로드 실패');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<dynamic>>(
        future: fetchEtfData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text("데이터를 불러올 수 없습니다.", style: TextStyle(color: Colors.white)));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("등록된 ETF가 없습니다.", style: TextStyle(color: Colors.white)));
          }

          final etfs = snapshot.data!;
          return ListView.builder(
            itemCount: etfs.length,
            itemBuilder: (context, index) {
              final etf = etfs[index];
              return ListTile(
                title: Text(etf['ticker'] ?? 'N/A', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('비중: ${etf['weight'] ?? 0}%', style: const TextStyle(color: Colors.grey)),
                trailing: Text('₩${(etf['price'] ?? 0).toString()}', style: const TextStyle(color: Colors.greenAccent)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DetailScreen(ticker: etf['ticker']),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}