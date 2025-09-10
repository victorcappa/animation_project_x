import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart' as wk;

class SoundWaveWidget extends StatefulWidget {
  const SoundWaveWidget({super.key});

  @override
  State<SoundWaveWidget> createState() => SoundWaveWidgetState();
}

class SoundWaveWidgetState extends State<SoundWaveWidget> {
  late final WebViewController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final creationParams =
        (defaultTargetPlatform == TargetPlatform.iOS)
            ? wk.WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <wk.PlaybackMediaTypes>{},
            )
            : const PlatformWebViewControllerCreationParams();

    _controller =
        WebViewController.fromPlatformCreationParams(creationParams)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.transparent)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (url) async {
                await _dispatch('_wave:bridgeReady', {});
                setState(() => _loaded = true);
              },
            ),
          );

    await _controller.loadFlutterAsset('assets/web/index.html');
  }

  // ---------- PUBLIC API ----------
  Future<void> setWaveState(String state) async {
    if (!_loaded) return;
    await _dispatch('wave:setState', {'state': state});
  }

  /// Para asset local, use: 'asset:assets/wave/test-audio.mp3'
  Future<void> attachMedia(
    String url, {
    bool autoplay = false,
    bool loop = false,
    double volume = 1.0,
  }) async {
    if (!_loaded) return;

    String finalUrl = url;
    if (url.startsWith('asset:')) {
      final assetPath = url.substring('asset:'.length);
      final bytes = await rootBundle.load(assetPath);
      final b64 = base64Encode(bytes.buffer.asUint8List());
      finalUrl = 'data:audio/mpeg;base64,$b64'; // troque o mime se não for mp3
    }

    await _dispatch('wave:unlockAudio', {});
    await _dispatch('wave:attachMedia', {
      'url': finalUrl,
      'autoplay': autoplay,
      'loop': loop,
      'volume': volume,
    });
  }

  Future<void> playMedia() async {
    if (!_loaded) return;
    await _dispatch('wave:unlockAudio', {}); // garante AudioContext 'running'
    await _dispatch('wave:mediaPlay', {});
  }

  Future<void> pauseMedia() async {
    if (!_loaded) return;
    await _dispatch('wave:mediaPause', {});
  }

  Future<void> detachMedia() async {
    if (!_loaded) return;
    await _dispatch('wave:detachMedia', {});
  }

  // ---------- NOVO: helper de 1 clique para tocar o asset de teste ----------
  Future<void> playTestAsset() async {
    if (!_loaded) return;
    // 1) desbloqueia contexto
    await _dispatch('wave:unlockAudio', {});
    // 2) liga o estado ACTIVE (faz a wave ler o analyser)
    await _dispatch('wave:setState', {'state': 'ACTIVE'});
    // 3) anexa o asset embutido
    await attachMedia(
      'asset:assets/web/assets/test-audio.mp3',
      autoplay: true,
      loop: true,
      volume: 1.0,
    );
    // 4) play explícito (iOS às vezes precisa mesmo após autoplay)
    await _dispatch('wave:mediaPlay', {});
  }

  Future<void> _dispatch(String name, Map<String, dynamic> detail) async {
    final jsonStr = jsonEncode(detail);
    final script = """
      try {
        window.dispatchEvent(new CustomEvent('$name', { detail: $jsonStr }));
      } catch (e) { console.error('dispatch fail', e); }
    """;
    await _controller.runJavaScript(script);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: WebViewWidget(controller: _controller),
    );
  }
}
