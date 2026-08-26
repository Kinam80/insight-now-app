import 'package:flutter/foundation.dart';

class AdConfig {
  const AdConfig._();

  // 출시 빌드에서는 --dart-define=ADMOB_INTERSTITIAL_AD_UNIT_ID=... 로 주입합니다.
  static const String _configuredInterstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_AD_UNIT_ID',
  );

  // Google 제공 테스트 광고 ID는 디버그 빌드에만 사용합니다.
  static const String _debugInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';

  static String get interstitialAdUnitId {
    if (_configuredInterstitialId.isNotEmpty) {
      return _configuredInterstitialId;
    }
    return kDebugMode ? _debugInterstitialId : '';
  }
}
