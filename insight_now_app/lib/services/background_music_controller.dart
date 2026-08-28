import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundMusicController extends ChangeNotifier {
  static const _enabledKey = 'settings_background_music_enabled';
  static const _assetPath = 'audio/insight_now_classical_ambience.mp3';

  final AudioPlayer _player = AudioPlayer();
  bool _enabled = true;
  bool _ready = false;
  bool _isPlaying = false;

  bool get enabled => _enabled;
  bool get ready => _ready;
  bool get isPlaying => _isPlaying;

  BackgroundMusicController() {
    _initialize();
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(0.16);
    _ready = true;
    notifyListeners();
    if (_enabled) {
      await _start();
    }
  }

  Future<void> toggle() => setEnabled(!_enabled);

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
    if (value) {
      await _start();
    } else {
      await _player.stop();
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> _start() async {
    try {
      await _player.play(AssetSource(_assetPath));
      _isPlaying = true;
    } catch (_) {
      _isPlaying = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
