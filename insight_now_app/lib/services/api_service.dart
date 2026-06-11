// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_index.dart'; // 방금 만든 모델
import '../constants/api_constants.dart'; // 기존에 가지고 계신 상수 파일

class ApiService {
  // 시장 지표 데이터를 가져오는 상담원 함수
  static Future<List<MarketIndex>> fetchMarketIndices() async {
    try {
      // 이제 여기에 추가만 하시면 됩니다!
      final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/market/indices'));
      
      if (response.statusCode == 200) {
        List<dynamic> body = json.decode(response.body);
        return body.map((dynamic item) => MarketIndex.fromJson(item)).toList();
      }
    } catch (e) {
      print("❌ 시장 데이터 호출 오류: $e");
    }
    return []; // 오류 발생 시 빈 리스트 반환 (앱이 안 죽게 방어)
  }
}