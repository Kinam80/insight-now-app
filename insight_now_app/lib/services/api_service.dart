import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/market_index.dart';
import '../constants/api_constants.dart';

class ApiService {
  // [공통 헤더 로직] 토큰을 찾아서 헤더에 실어줍니다.
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // 1. 시장 지표 데이터 호출
  static Future<List<MarketIndex>> fetchMarketIndices() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConstants.marketIndicesEndpoint),
        headers: await _getHeaders(),
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

    // 대표 코인 가격은 서버가 Yahoo Finance에서 자동 갱신합니다.
  static Future<List<MarketIndex>> fetchMarketCrypto() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConstants.marketCryptoEndpoint),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = json.decode(utf8.decode(response.bodyBytes));
        return body.map((dynamic item) => MarketIndex.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('대표 코인 데이터 호출 오류: $e');
    }
    return [];
  }

  // 2. 홈 화면의 공개 일일 레포트를 가져오는 함수

  static Future<List<dynamic>> fetchDailyReports() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConstants.reportsFeedEndpoint),
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final dynamic body = json.decode(utf8.decode(response.bodyBytes));
        if (body is Map && body['reports'] is List) {
          return List<dynamic>.from(body['reports'] as List);
        }
      }
    } catch (e) {
      print("일일 레포트 호출 오류: $e");
    }
    return [];
  }

  // 3. 서버에서 게시글 전체 데이터를 가져오는 함수
  static Future<List<dynamic>> fetchPosts() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConstants.postsEndpoint),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        // utf8.decode로 한글 깨짐 방지
        final dynamic body = json.decode(utf8.decode(response.bodyBytes));

        // 서버 응답이 {"posts": [...]} 형태일 경우
        if (body is Map && body.containsKey('posts')) {
          return body['posts'];
        }
        // 서버 응답이 바로 리스트인 경우
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
