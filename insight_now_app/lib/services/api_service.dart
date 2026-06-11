import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/market_index.dart'; 
import '../constants/api_constants.dart'; 

class ApiService {
  
  // [공통 헤더 로직] 토큰을 찾아서 헤더에 실어줍니다.
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token'); // 저장된 토큰 가져오기
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token', // 토큰이 있으면 헤더 추가
    };
  }

  // 1. 시장 지표 데이터 호출
  static Future<List<MarketIndex>> fetchMarketIndices() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/market/indices'),
        headers: await _getHeaders(), // 수정: 헤더 포함
      );
      
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
      final response = await http.get(
        Uri.parse(ApiConstants.postsEndpoint),
        headers: await _getHeaders(), // 수정: 헤더 포함
      );
      
      if (response.statusCode == 200) {
        final dynamic body = json.decode(utf8.decode(response.bodyBytes));
        
        if (body is Map && body.containsKey('posts')) {
          return body['posts'];
        }
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