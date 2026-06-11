class ApiConstants {
  // ✅ Render 클라우드 서버 (24시간 운영)
  static const String baseUrl = 'https://insight-now-app.onrender.com';
  static const String wsUrl = 'wss://insight-now-app.onrender.com';

  // --- 🆕 신규 탭용 API (Phase 2, 3, 4) ---
  static const String newsEndpoint = '$baseUrl/news/';
  static const String etfEndpoint = '$baseUrl/etfs';
  static const String govStatsEndpoint = '$baseUrl/gov-stats';

  // --- 기존 API ---
  // 인증 API
  static const String loginEndpoint = '$baseUrl/auth/login';
  static const String registerEndpoint = '$baseUrl/auth/register';

  // 뉴스 관련 (기존 로직 유지)
  static const String newsLatestEndpoint = '$baseUrl/news/latest';
  static const String newsDetailEndpoint = '$baseUrl/news/';

  // 분석 글 API
  static const String postsEndpoint = '$baseUrl/posts/';
  static const String postsDetailEndpoint = '$baseUrl/posts/';
  static const String createPostEndpoint = '$baseUrl/posts/admin/create';

  // 결제 API
  static const String confirmPaymentEndpoint = '$baseUrl/payments/confirm';
  static const String getPaymentHistoryEndpoint = '$baseUrl/payments/my';

  // 관리자 API
  static const String adminStatsEndpoint = '$baseUrl/admin/stats';
  static const String adminPostsDetailEndpoint = '$baseUrl/admin/posts-detail';

  // WebSocket
  static const String chatSocket = '$wsUrl/ws/chat';
}