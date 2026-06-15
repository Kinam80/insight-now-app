class ApiConstants {
  static const String baseUrl = 'https://insight-now-app.onrender.com';
  static const String wsUrl = 'wss://insight-now-app.onrender.com';

  // --- 🆕 신규 탭용 API ---
  static const String newsEndpoint = '$baseUrl/api/news/';
  static const String etfEndpoint = '$baseUrl/api/etf/list'; // etf/list로 수정
  static const String marketIndicesEndpoint = '$baseUrl/api/market/indices'; // 추가된 항목
  static const String govStatsEndpoint = '$baseUrl/api/gov-stats';

  // --- 인증 API ---
  static const String loginEndpoint = '$baseUrl/api/auth/login';
  static const String registerEndpoint = '$baseUrl/api/auth/register';

  // --- 뉴스 관련 ---
  static const String newsLatestEndpoint = '$baseUrl/api/news/latest';
  static const String newsDetailEndpoint = '$baseUrl/api/news/';

  // --- 분석 글 API ---
  static const String postsEndpoint = '$baseUrl/api/posts/'; // /api 추가
  static const String postsDetailEndpoint = '$baseUrl/api/posts/';
  static const String createPostEndpoint = '$baseUrl/api/posts/admin/create';

  // --- 결제 API ---
  static const String confirmPaymentEndpoint = '$baseUrl/api/payments/confirm';
  static const String getPaymentHistoryEndpoint = '$baseUrl/api/payments/my'; // /api 추가

  // --- 관리자 API ---
  static const String adminStatsEndpoint = '$baseUrl/api/admin/stats'; // /api 추가
  static const String adminPostsDetailEndpoint = '$baseUrl/api/admin/posts-detail';

  // --- WebSocket ---
  static const String chatSocket = '$wsUrl/api/ws/chat'; // /api 추가 (라우터 설정 확인 필요)
}