import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

class LocalhostWebViewPage extends StatefulWidget {
  const LocalhostWebViewPage({super.key});

  @override
  State<LocalhostWebViewPage> createState() => _LocalhostWebViewPageState();
}

class _LocalhostWebViewPageState extends State<LocalhostWebViewPage> {
  static const String kAssetRoot = 'assets/web'; // index.html + assets/
  HttpServer? _server;
  late final WebViewController _controller;
  int? _port;
  String _currentState = 'IDLE';
  bool _isMediaAttached = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
      _startServer();
    }
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  void _initWebView() {
    if (kIsWeb) return;
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (url) => debugPrint('[WEB] start $url'),
              onPageFinished: (url) => debugPrint('[WEB] finished $url'),
              onWebResourceError:
                  (e) => debugPrint(
                    '[WEB][err] code=${e.errorCode} type=${e.errorType} desc=${e.description}',
                  ),
            ),
          );

    _controller.addJavaScriptChannel(
      'LOG',
      onMessageReceived: (msg) => debugPrint('[console] ${msg.message}'),
    );
  }

  Future<void> _startServer() async {
    if (kIsWeb) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[SRV] http://127.0.0.1:$_port');

    unawaited(
      Future(() async {
        await for (final req in _server!) {
          try {
            final assetPath = _mapPath(req.uri.path);
            final data = await rootBundle.load(assetPath);
            req.response.headers.set(
              HttpHeaders.contentTypeHeader,
              _mimeFor(assetPath),
            );
            req.response.headers.set('Access-Control-Allow-Origin', '*');
            req.response.add(data.buffer.asUint8List());
            await req.response.close();
          } catch (e) {
            debugPrint('[SRV][404] ${req.uri.path} -> $e');
            req.response.statusCode = HttpStatus.notFound;
            req.response.write('404 Not Found');
            await req.response.close();
          }
        }
      }),
    );

    await _controller.loadRequest(
      Uri.parse('http://127.0.0.1:${_port!}/index.html'),
    );
    setState(() {});
  }

  String _mapPath(String urlPath) {
    String p = urlPath;
    if (p.isEmpty || p == '/' || p == '/index' || p == '/index.html') {
      p = 'index.html';
    } else if (p.startsWith('/')) {
      p = p.substring(1);
    }
    p = p.replaceAll('..', '');
    return '$kAssetRoot/$p';
  }

  String _mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html')) return 'text/html; charset=utf-8';
    if (p.endsWith('.js') || p.endsWith('.mjs'))
      return 'application/javascript; charset=utf-8';
    if (p.endsWith('.css')) return 'text/css; charset=utf-8';
    if (p.endsWith('.json')) return 'application/json; charset=utf-8';
    if (p.endsWith('.wasm')) return 'application/wasm';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.svg')) return 'image/svg+xml';
    if (p.endsWith('.ico')) return 'image/x-icon';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.wav')) return 'audio/wav';
    return 'application/octet-stream';
  }

  // ======= eventos mínimos =======
  void setWaveState(String state) {
    final script =
        'window.dispatchEvent(new CustomEvent("wave:setState",{detail:"$state"}))';
    if (!kIsWeb) _controller.runJavaScript(script);
    setState(() => _currentState = state);
  }

  Future<void> _ensureActiveAndAttachIfNeeded() async {
    // 1) desbloqueia AudioContext do VISUALIZER
    await _controller.runJavaScript(
      'window.dispatchEvent(new CustomEvent("wave:unlockAudio",{detail:{}}))',
    );

    // 2) força seguir o stream (não mic)
    await _controller.runJavaScript(
      'window.dispatchEvent(new CustomEvent("wave:setConfig",{detail:{mic:false}}))',
    );

    // 3) estado ACTIVE (a wave lê o analyser só aqui)
    await _controller.runJavaScript(
      'window.dispatchEvent(new CustomEvent("wave:setState",{detail:"ACTIVE"}))',
    );

    // 4) anexa mídia se ainda não anexamos
    if (!_isMediaAttached) {
      final url = 'http://127.0.0.1:${_port!}/assets/test-audio.mp3';
      await _controller.runJavaScript(
        'window.dispatchEvent(new CustomEvent("wave:attachMedia",{detail:{url:"$url",autoplay:false,loop:true,volume:1.0,crossOrigin:"anonymous"}}))',
      );
      setState(() => _isMediaAttached = true);
    }
  }

  Future<void> play() async {
    await _ensureActiveAndAttachIfNeeded();
    await _controller.runJavaScript(
      'window.dispatchEvent(new Event("wave:mediaPlay"))',
    );
  }

  Future<void> pause() async {
    await _controller.runJavaScript(
      'window.dispatchEvent(new Event("wave:mediaPause"))',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Localhost WebView - Sound Wave'),
        actions: [
          if (_port != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Text(
                  'Port: $_port',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // status
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  'State: $_currentState',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Media: ${_isMediaAttached ? 'Attached' : 'None'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_port != null)
                  Text(
                    'Server: 127.0.0.1:$_port',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
              ],
            ),
          ),

          // WebView
          Expanded(
            child:
                kIsWeb
                    ? const Center(child: Text('Mobile only'))
                    : (_port != null
                        ? WebViewWidget(controller: _controller)
                        : const Center(child: CircularProgressIndicator())),
          ),

          // ====== Controles mínimos (5 botões) ======
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => setWaveState('IDLE'),
                  child: const Text('Idle'),
                ),
                ElevatedButton(
                  onPressed: () => setWaveState('ACTIVE'),
                  child: const Text('Active'),
                ),
                ElevatedButton(
                  onPressed: () => setWaveState('PROCESSING'),
                  child: const Text('Processing'),
                ),
                ElevatedButton(onPressed: play, child: const Text('Play')),
                ElevatedButton(onPressed: pause, child: const Text('Pause')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
