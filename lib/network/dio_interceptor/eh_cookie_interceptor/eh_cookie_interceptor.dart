import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/extension.dart';
import 'package:eros_fe/network/cloudflare/cloudflare.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:get/get.dart' hide Response;

/// 登录凭证相关的 cookie，只以 [UserController.user] 为准
const List<String> _kCredentialCookies = <String>[
  'ipb_member_id',
  'ipb_pass_hash',
  'igneous',
];

class EhCookieInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final String host = requestHost(options);
      // 账号 cookie 只发送给 E-Hentai / ExHentai，
      // 避免泄露给 GitHub、翻译数据库代理等第三方域名
      if (!isEhSiteHost(host)) {
        handler.next(options);
        return;
      }

      final UserController userController = Get.find();
      final user = userController.user.value;

      // 使用通过 Cloudflare 验证时 WebView 的 UA，保证 cf_clearance 有效
      final userAgent = user.userAgent;
      if (userAgent != null && userAgent.isNotEmpty) {
        options.headers[HttpHeaders.userAgentHeader] = userAgent;
      }

      final cookieHeader =
          options.headers[HttpHeaders.cookieHeader] as String? ?? '';
      logger.t('${options.uri} before checkCookies:$cookieHeader');
      final Map<String, String> cookies = parseCookieHeader(cookieHeader);

      checkCookies(cookies, host);
      logger.t('after checkCookies:$cookies');

      saveCookieToUser(cookies);

      options.headers[HttpHeaders.cookieHeader] = getCookies(cookies);
    } catch (e, stack) {
      logger.e('$e\n$stack');
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      _saveCookies(response);
    } catch (e, stack) {
      // 解析 Set-Cookie 失败不应导致整个请求失败
      logger.e('save cookies error: $e\n$stack');
    }
    handler.next(response);
  }

  // 保存cookie
  void _saveCookies(Response response) {
    final List<String>? setCookiesFromResponse =
        response.headers[HttpHeaders.setCookieHeader];
    if (setCookiesFromResponse == null || setCookiesFromResponse.isEmpty) {
      return;
    }

    logger.t('set-cookie:$setCookiesFromResponse');
    final Map<String, String> setCookies =
        parseSetCookieHeaders(setCookiesFromResponse);
    logger.d('_set setCookiesFromResponse $setCookies');

    final String host = requestHost(response.requestOptions);
    if (!isEhSiteHost(host)) {
      return;
    }
    // 只接受 e-hentai.org 返回的 cf cookie（User 上的 cf_clearance 属于 e-hentai.org）
    if (!isEhentaiHost(host)) {
      setCookies
        ..remove(kCfClearance)
        ..remove(kCfDuid);
    }
    saveCookieToUser(setCookies, fromResponse: true);
  }

  static String getCookies(Map<String, String> cookies) {
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 解析请求头里的 Cookie，忽略无法解析的片段
  static Map<String, String> parseCookieHeader(String header) {
    final Map<String, String> cookies = <String, String>{};
    for (final String part in header.split(';')) {
      final int index = part.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final String name = part.substring(0, index).trim();
      if (name.isEmpty) {
        continue;
      }
      cookies[name] = part.substring(index + 1).trim();
    }
    return cookies;
  }

  /// 解析 Set-Cookie，兼容多个 cookie 被合并成一行（逗号分隔）的情况，
  /// 已过期（删除）的 cookie 会被忽略
  static Map<String, String> parseSetCookieHeaders(List<String> headers) {
    final RegExp splitReg = RegExp(r',(?=\s*[^;,=\s]+=)');
    final Map<String, String> cookies = <String, String>{};
    for (final String header in headers) {
      for (final String setCookie in header.split(splitReg)) {
        final List<String> segments = setCookie.split(';');
        final String pair = segments.first;
        final int index = pair.indexOf('=');
        if (index <= 0) {
          continue;
        }
        final String name = pair.substring(0, index).trim();
        final String value = pair.substring(index + 1).trim();
        if (name.isEmpty) {
          continue;
        }
        if (_isExpired(segments.skip(1))) {
          continue;
        }
        cookies[name] = value;
      }
    }
    return cookies;
  }

  static bool _isExpired(Iterable<String> attributes) {
    for (final String attr in attributes) {
      final int index = attr.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final String name = attr.substring(0, index).trim().toLowerCase();
      final String value = attr.substring(index + 1).trim();
      if (name == 'max-age') {
        final int? maxAge = int.tryParse(value);
        if (maxAge != null && maxAge <= 0) {
          return true;
        }
      } else if (name == 'expires') {
        try {
          if (HttpDate.parse(value).isBefore(DateTime.now())) {
            return true;
          }
        } catch (_) {}
      }
    }
    return false;
  }

  static String? getCookiesValue(Map<String, String> cookies, String name) {
    return cookies[name];
  }

  // 检查并处理cookie
  void checkCookies(Map<String, String> cookies, String host) {
    final UserController userController = Get.find();

    cookies['nw'] = '1';

    final user = userController.user.value;

    if (isEhentaiHost(host)) {
      updateCookie(cookies, kCfClearance, user.cfClearance);
      updateCookie(cookies, kCfDuid, user.cfDuid);
    } else {
      final extra = CloudflareSolver.instance.extraCookiesFor(host);
      extra?.forEach((key, value) => updateCookie(cookies, key, value));
    }

    if (!userController.isLogin) {
      // 已退出登录时 CookieJar 中可能仍残留旧账号的 cookie，不能再发送
      _kCredentialCookies.forEach(cookies.remove);
      return;
    }

    updateCookie(cookies, 'ipb_member_id', user.memberId);
    updateCookie(cookies, 'ipb_pass_hash', user.passHash);
    updateCookie(cookies, 'igneous', user.igneous);
    updateCookie(cookies, 'hath_perks', user.hathPerks);
    updateCookie(cookies, 'sk', user.sk);
    updateCookie(cookies, 'star', user.star);
    updateCookie(cookies, 'yay', user.yay);
    updateCookie(cookies, 'iq', user.iq);
  }

  void updateCookie(Map<String, String> cookies, String name, String? value) {
    if (value != null && value.isNotEmpty) {
      cookies[name] = value;
    }
  }

  static bool _isInvalidValue(String? value) =>
      value == null || value.isEmpty || value == '0' || value == 'deleted';

  /// 将 cookie 同步到用户信息
  ///
  /// 登录凭证只会从服务器响应中更新（如账号密码登录），
  /// 不会从请求的 CookieJar 中回写，避免退出登录后被旧 cookie 重新"登录"
  void saveCookieToUser(Map<String, String> cookies,
      {bool fromResponse = false}) {
    final UserController userController = Get.find();
    if (!fromResponse && !userController.isLogin) {
      return;
    }

    final String? memberId = getCookiesValue(cookies, 'ipb_member_id');
    final String? passHash = getCookiesValue(cookies, 'ipb_pass_hash');
    final String? igneous = getCookiesValue(cookies, 'igneous');
    final String newSk = getCookiesValue(cookies, 'sk') ?? '';
    final String? cfClearance =
        fromResponse ? getCookiesValue(cookies, kCfClearance) : null;
    final String? cfDuid =
        fromResponse ? getCookiesValue(cookies, kCfDuid) : null;

    userController.user(userController.user.value.copyWith(
      memberId:
          fromResponse && !_isInvalidValue(memberId) ? memberId?.oN : null,
      passHash:
          fromResponse && !_isInvalidValue(passHash) ? passHash?.oN : null,
      igneous: fromResponse && !_isInvalidValue(igneous) && igneous != 'mystery'
          ? igneous?.oN
          : null,
      hathPerks: getCookiesValue(cookies, 'hath_perks')?.oN,
      sk: newSk.isNotEmpty ? newSk.oN : null,
      star: getCookiesValue(cookies, 'star')?.oN,
      yay: getCookiesValue(cookies, 'yay')?.oN,
      iq: getCookiesValue(cookies, 'iq')?.oN,
      cfClearance:
          cfClearance != null && cfClearance.isNotEmpty ? cfClearance.oN : null,
      cfDuid: cfDuid != null && cfDuid.isNotEmpty ? cfDuid.oN : null,
    ));

    logger.t('user: ${userController.user.value.toJson()}');
  }
}
