import 'dart:async';

import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/network/cloudflare/cloudflare.dart';
import 'package:eros_fe/pages/login/view/webview_cookie_helper.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:eros_fe/widget/liquid_glass/liquid_glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 在 WebView 中完成 Cloudflare 质询，完成后自动返回 [CloudflareClearance]
class CloudflareChallengePage extends StatefulWidget {
  const CloudflareChallengePage({super.key, required this.url});

  final Uri url;

  @override
  State<CloudflareChallengePage> createState() =>
      _CloudflareChallengePageState();
}

class _CloudflareChallengePageState extends State<CloudflareChallengePage> {
  InAppWebViewController? _controller;
  Timer? _timer;
  bool _finished = false;
  bool _checking = false;
  bool _pageLoaded = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _check(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final InAppWebViewController? controller = _controller;
    if (_finished || _checking || !_pageLoaded || controller == null) {
      return;
    }
    _checking = true;
    try {
      if (await controller.isLoading()) {
        return;
      }
      final WebUri? current = await controller.getUrl();
      if (current == null || !current.scheme.startsWith('http')) {
        return;
      }
      final String? state = cleanJsString(
          await controller.evaluateJavascript(source: kCloudflarePageStateJs));
      logger.t('cloudflare page state: $state, $current');
      if (state != 'complete' && state != 'interactive') {
        return;
      }

      final String origin = '${widget.url.scheme}://${widget.url.host}/';
      final Map<String, String> cookies = await readWebViewCookies(<String>[
        origin,
        current.toString(),
      ]);
      final String? ua = await readWebViewUserAgent(controller);
      if (_finished || !mounted) {
        return;
      }
      _finished = true;
      _timer?.cancel();
      logger.d('cloudflare challenge passed: ${widget.url.host}');
      Navigator.of(context).pop(CloudflareClearance(
        host: widget.url.host,
        cookies: cookies,
        userAgent: ua,
      ));
    } catch (e, stack) {
      logger.e('cloudflare check error: $e\n$stack');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        middle: Text(l10n.cloudflare_verify),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _controller?.reload(),
          child: const Icon(CupertinoIcons.arrow_clockwise),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri.uri(widget.url)),
              initialSettings: InAppWebViewSettings(
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useHybridComposition: true,
                isInspectable: false,
              ),
              onWebViewCreated: (InAppWebViewController controller) {
                _controller = controller;
              },
              onProgressChanged: (_, int progress) {
                if (mounted) {
                  setState(() => _progress = progress / 100);
                }
              },
              onLoadStop: (InAppWebViewController controller, WebUri? url) {
                if (url != null && url.scheme.startsWith('http')) {
                  _pageLoaded = true;
                }
                _check();
              },
            ),
            if (_progress < 1.0)
              Align(
                alignment: Alignment.topCenter,
                child: _ProgressBar(progress: _progress),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(
                child: LiquidGlass(
                  borderRadius: const BorderRadius.all(Radius.circular(22)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(CupertinoIcons.checkmark_shield, size: 20),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          l10n.cloudflare_verify_tip,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: ColoredBox(color: CupertinoTheme.of(context).primaryColor),
      ),
    );
  }
}
