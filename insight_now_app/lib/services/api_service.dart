// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_index.dart'; 
import '../constants/api_constants.dart'; 

class ApiService {
  
  // 1. 시장 지표 데이터를 가져오는 함수
  static Future<List<MarketIndex>> fetchMarketIndices() async {
    try {
      final response = await http.get(Uri.parse('${ApiConstants.baseUrl}/market/indices'));
      
      if (response.statusCode == 200) {
        List<dynamic> body = json.decode(utf8.decode(response.bodyBytes));
        return body.map((dynamic item) => MarketIndex.fromJson(item)).toList();
      }
    } catch (e) {
      print("❌ 시장 데이터 호출 오류: $e");
    }
    return []; 
  }

  // 2. 서버에서 게시글 전체 데이터를 가져오는 함수
  static Future<List<dynamic>> fetchPosts() async {
    try {
      // ApiConstants에 정의된 postsEndpoint를 정확히 사용합니다.
      final response = await http.get(Uri.parse(ApiConstants.postsEndpoint));
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(utf8.decode(response.bodyBytes));
        
        // 서버 응답 구조 확인 (서버가 {'posts': [...]} 형태로 준다고 가정)
        if (body is Map && body.containsKey('posts')) {
          return body['posts'];
        }
        // 응답이 바로 리스트인 경우를 대비
        return body is List ? body : [];
      } else {
        print("❌ 서버 응답 오류: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ 게시글 데이터 호출 오류: $e");
    }
    return []; 
  }
}