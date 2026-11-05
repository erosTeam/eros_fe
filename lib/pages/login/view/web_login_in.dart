import 'dart:async';

import 'package:eros_fe/const/const.dart';
import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/pages/login/view/webview_cookie_helper.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:eros_fe/widget/liquid_glass/liquid_glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 网页登录结果
class WebLoginResult {
  const WebLoginResult({required this.cookies, this.userAgent});

  /// e-hentai.org 域下的 cookie（含 ipb_member_id / ipb_pass_hash / cf_clearance 等）
  final Map<String, String> cookies;

  /// WebView 的真实 UA，cf_clearance 与其绑定
  final String? userAgent;
}

const List<String> _kEhCookieUrls = <String>[
  'https://e-hentai.org/',
  'https://forums.e-hentai.org/',
];

/// 旧的登录态，打开网页登录时清理，避免把失效的会话误判为登录成功
const List<String> _kStaleSessionCookies = <String>[
  'ipb_member_id',
  'ipb_pass_hash',
  'ipb_session_id',
  'igneous',
];

final RegExp _kMemberIdReg = RegExp(r'^\d+$');

bool isValidMemberId(String? memberId) =>
    memberId != null && _kMemberIdReg.hasMatch(memberId) && memberId != '0';

bool isValidPassHash(String? passHash) =>
    passHash != null &&
    passHash.isNotEmpty &&
    passHash != '0' &&
    passHash != 'deleted';

/// 通过 WebView 登录 E-Hentai 论坛
///
/// 不再依赖登录后跳转到某个固定地址，而是持续检查 WebView 中的 cookie，
/// 一旦出现有效的 ipb_member_id 与 ipb_pass_hash 即返回 [WebLoginResult]。
/// 论坛的 Cloudflare 质询也会在此页面中直接完成。
class WebLoginViewIn extends StatefulWidget {
  const WebLoginViewIn({super.key});

  @override
  State<WebLoginViewIn> createState() => _WebLoginViewInState();
}

class _WebLoginViewInState extends State<WebLoginViewIn> {
  final CookieManager _cookieManager = CookieManager.instance();

  InAppWebViewController? _controller;
  Timer? _timer;

  bool _ready = false;
  bool _finished = false;
  bool _checking = false;
  bool _showTip = true;
  double _progress = 0;

  /// 清理失败时用于识别旧会话
  String? _stalePassHash;
  int _loadCount = 0;

  Timer? _tipTimer;

  @override
  void initState() {
    super.initState();
    _prepare();
    _tipTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _showTip = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tipTimer?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      await Future.wait(<Future<void>>[
        for (final String url in _kEhCookieUrls)
          for (final String name in _kStaleSessionCookies)
            for (final String domain in <String>[
              '.e-hentai.org',
              Uri.parse(url).host,
            ])
              _cookieManager
                  .deleteCookie(url: WebUri(url), name: name, domain: domain)
                  .then((_) {}, onError: (Object e) {
                logger.d('delete cookie $name of $domain error: $e');
              }),
      ]).timeout(const Duration(seconds: 3));
    } catch (e) {
      logger.e('clear stale login cookies error: $e');
    }

    final Map<String, String> remain = await readWebViewCookies(_kEhCookieUrls);
    if (isValidMemberId(remain['ipb_member_id']) &&
        isValidPassHash(remain['ipb_pass_hash'])) {
      _stalePassHash = remain['ipb_pass_hash'];
    }

    if (!mounted) {
      return;
    }
    setState(() => _ready = true);
    _timer = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => _checkLogin(),
    );
  }

  Future<void> _checkLogin() async {
    if (_finished || _checking || !mounted) {
      return;
    }
    _checking = true;
    try {
      final Map<String, String> cookies =
          await readWebViewCookies(_kEhCookieUrls);
      final String? memberId = cookies['ipb_member_id'];
      final String? passHash = cookies['ipb_pass_hash'];
      if (!isValidMemberId(memberId) || !isValidPassHash(passHash)) {
        return;
      }

      // 旧会话没有清理掉时，需要用户真的提交过登录表单才接受
      if (_stalePassHash != null &&
          passHash == _stalePassHash &&
          _loadCount < 2) {
        return;
      }

      final String? ua = await readWebViewUserAgent(_controller);
      if (_finished || !mounted) {
        return;
      }
      _finished = true;
      _timer?.cancel();
      logger.d('web login success, memberId: $memberId');
      Navigator.of(context)
          .pop(WebLoginResult(cookies: cookies, userAgent: ua));
    } catch (e, stack) {
      logger.e('check web login error: $e\n$stack');
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.login_web),
        transitionBetweenRoutes: false,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _controller?.reload(),
          child: const Icon(CupertinoIcons.arrow_clockwise),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            if (_ready)
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(EHConst.URL_SIGN_IN)),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false,
                  useHybridComposition: true,
                  allowsInlineMediaPlayback: true,
                ),
                onWebViewCreated: (InAppWebViewController controller) {
                  _controller = controller;
                },
                onPermissionRequest: (controller, permissionRequest) async {
                  return PermissionResponse(
                      resources: permissionRequest.resources,
                      action: PermissionResponseAction.GRANT);
                },
                onProgressChanged: (_, int progress) {
                  if (mounted) {
                    setState(() => _progress = progress / 100);
                  }
                },
                onLoadStop: (InAppWebViewController controller, WebUri? uri) {
                  logger.d('web login page finished loading: $uri');
                  _loadCount++;
                  _checkLogin();
                },
                onUpdateVisitedHistory: (_, __, ___) => _checkLogin(),
              )
            else
              const Center(child: CupertinoActivityIndicator()),
            if (_ready && _progress < 1.0)
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 2,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _progress.clamp(0.0, 1.0),
                    child: ColoredBox(
                        color: CupertinoTheme.of(context).primaryColor),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showTip ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Center(
                    child: LiquidGlass(
                      borderRadius: const BorderRadius.all(Radius.circular(22)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(CupertinoIcons.lock_shield, size: 20),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              l10n.web_login_tip,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
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
