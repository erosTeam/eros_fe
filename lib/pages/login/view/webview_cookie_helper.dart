import 'package:eros_fe/utils/logger.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 去掉 evaluateJavascript 返回值两端可能存在的引号
String? cleanJsString(dynamic value) {
  if (value == null) {
    return null;
  }
  final String str = value.toString().trim();
  if (str.isEmpty || str == 'null') {
    return null;
  }
  return str.replaceAll(RegExp(r'^"|"$'), '');
}

/// 读取 WebView 中若干地址下的 cookie，后面的地址同名 cookie 覆盖前面的
Future<Map<String, String>> readWebViewCookies(List<String> urls) async {
  final CookieManager cookieManager = CookieManager.instance();
  final Map<String, String> result = <String, String>{};
  for (final String url in urls) {
    try {
      final List<Cookie> cookies =
          await cookieManager.getCookies(url: WebUri(url));
      for (final Cookie cookie in cookies) {
        final String value = '${cookie.value ?? ''}'.trim();
        if (cookie.name.isEmpty) {
          continue;
        }
        result[cookie.name] = value;
      }
    } catch (e, stack) {
      logger.e('read webview cookies of $url error: $e\n$stack');
    }
  }
  return result;
}

/// WebView 当前真实的 User-Agent，用于与 cf_clearance 保持一致
Future<String?> readWebViewUserAgent(InAppWebViewController? controller) async {
  String? ua;
  if (controller != null) {
    try {
      ua = cleanJsString(
          await controller.evaluateJavascript(source: 'navigator.userAgent'));
    } catch (e) {
      logger.e('get navigator.userAgent error: $e');
    }
  }
  if (ua == null || ua.isEmpty) {
    try {
      ua = cleanJsString(await InAppWebViewController.getDefaultUserAgent());
    } catch (e) {
      logger.e('getDefaultUserAgent error: $e');
    }
  }
  return ua;
}

/// 页面是否仍是 Cloudflare 质询页面
const String kCloudflarePageStateJs = '''
(function () {
  try {
    if (window._cf_chl_opt) return 'challenge';
    if (document.getElementById('challenge-form') ||
        document.getElementById('challenge-stage') ||
        document.getElementById('challenge-running') ||
        document.getElementById('cf-challenge-running')) return 'challenge';
    var t = document.title || '';
    if (t === 'Just a moment...' || t.indexOf('Attention Required') === 0) return 'challenge';
    return document.readyState || 'unknown';
  } catch (e) {
    return 'error';
  }
})();
''';
