import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/extension.dart';
import 'package:eros_fe/network/dio_interceptor/domain_fronting/domain_fronting.dart';
import 'package:eros_fe/pages/login/view/cloudflare_challenge_page.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart' hide FormData, Response;

/// E-Hentai 论坛（登录、用户信息、里站授权 remoteapi）目前处于 Cloudflare
/// 托管质询之后。Dio 无法执行质询脚本，因此需要在 WebView 中完成验证，
/// 再把 WebView 的 `cf_clearance` 与 User-Agent 同步给 Dio。

const String kCfClearance = 'cf_clearance';
const String kCfDuid = 'cf_duid';

/// 根域名，如 forums.e-hentai.org -> e-hentai.org
String cfRootDomain(String host) {
  final parts = host.toLowerCase().split('.');
  if (parts.length <= 2) {
    return host.toLowerCase();
  }
  return parts.sublist(parts.length - 2).join('.');
}

/// 是否为 E-Hentai 的域名（cf_clearance 存在 User 上）
bool isEhentaiHost(String host) {
  final h = host.toLowerCase();
  return h == 'e-hentai.org' || h.endsWith('.e-hentai.org');
}

/// 是否为 E-Hentai / ExHentai 的域名
bool isEhSiteHost(String host) {
  final h = host.toLowerCase();
  return isEhentaiHost(h) || h == 'exhentai.org' || h.endsWith('.exhentai.org');
}

/// 请求真实的 host（兼容域名前置）
String requestHost(RequestOptions options) {
  return DomainFronting.getRawOptions(options).uri.host;
}

bool _isChallengeHtml(String html) {
  return html.contains('<title>Just a moment...</title>') ||
      html.contains('challenges.cloudflare.com/cdn-cgi/challenge-platform') ||
      html.contains('/cdn-cgi/challenge-platform/') ||
      html.contains('window._cf_chl_opt');
}

/// 判断响应是否为 Cloudflare 质询页
bool isCloudflareChallenge(Response<dynamic>? response) {
  if (response == null) {
    return false;
  }
  final int status = response.statusCode ?? 0;
  if (status != 403 && status != 503) {
    return false;
  }

  final String? mitigated = response.headers.value('cf-mitigated');
  if (mitigated != null && mitigated.toLowerCase() == 'challenge') {
    return true;
  }

  final String server =
      response.headers.value(HttpHeaders.serverHeader)?.toLowerCase() ?? '';
  if (!server.contains('cloudflare')) {
    return false;
  }

  final dynamic data = response.data;
  if (data is String) {
    return _isChallengeHtml(data);
  }
  return false;
}

/// Cloudflare 质询未通过
class CloudflareChallengeException implements Exception {
  CloudflareChallengeException(this.uri);

  final Uri uri;

  String get message =>
      'Cloudflare verification required for ${uri.host}, please try again';

  @override
  String toString() => message;
}

/// WebView 验证后得到的结果
class CloudflareClearance {
  const CloudflareClearance({
    required this.host,
    required this.cookies,
    this.userAgent,
  });

  final String host;
  final Map<String, String> cookies;
  final String? userAgent;
}

/// 负责弹出 WebView 解决 Cloudflare 质询，同时只会存在一个验证页面
class CloudflareSolver {
  CloudflareSolver._();

  static final CloudflareSolver instance = CloudflareSolver._();

  /// 用户取消/验证失败后，在此时间内不再自动弹出验证页面
  static const Duration failureCooldown = Duration(seconds: 30);

  Future<bool>? _pending;
  final Map<String, DateTime> _lastFailure = <String, DateTime>{};

  /// 非 e-hentai.org 根域名的 cf cookie（仅内存保存）
  final Map<String, Map<String, String>> _extraClearance =
      <String, Map<String, String>>{};

  bool get isSolving => _pending != null;

  Map<String, String>? extraCookiesFor(String host) {
    if (isEhentaiHost(host)) {
      return null;
    }
    return _extraClearance[cfRootDomain(host)];
  }

  void clear() {
    _extraClearance.clear();
    _lastFailure.clear();
  }

  bool get _canPresent {
    if (!GetPlatform.isIOS && !GetPlatform.isAndroid) {
      return false;
    }
    if (Get.key.currentState == null) {
      return false;
    }
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// 打开验证页面，返回是否通过验证
  Future<bool> solve(Uri uri) {
    final pending = _pending;
    if (pending != null) {
      return pending;
    }

    final String root = cfRootDomain(uri.host);
    final DateTime? lastFailure = _lastFailure[root];
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < failureCooldown) {
      logger.d('cloudflare: skip solve $uri, in cooldown');
      return Future<bool>.value(false);
    }

    if (!_canPresent) {
      return Future<bool>.value(false);
    }

    final future = _present(uri).then((bool ok) {
      if (ok) {
        _lastFailure.remove(root);
      } else {
        _lastFailure[root] = DateTime.now();
      }
      return ok;
    }).whenComplete(() => _pending = null);
    _pending = future;
    return future;
  }

  Future<bool> _present(Uri uri) async {
    try {
      final result = await Get.to<CloudflareClearance>(
        () => CloudflareChallengePage(url: uri),
        preventDuplicates: false,
        fullscreenDialog: true,
      );
      if (result == null) {
        return false;
      }
      applyClearance(result);
      return true;
    } catch (e, stack) {
      logger.e('cloudflare solve error: $e\n$stack');
      return false;
    }
  }

  /// 把 WebView 里得到的 cf cookie 与 UA 同步到 Dio 使用的用户信息上
  void applyClearance(CloudflareClearance clearance) {
    final UserController userController = Get.find();
    final String? clearanceValue = clearance.cookies[kCfClearance];
    final String? duid = clearance.cookies[kCfDuid];
    final String? ua = clearance.userAgent;

    if (isEhentaiHost(clearance.host)) {
      userController.user(userController.user.value.copyWith(
        cfClearance: clearanceValue.oN,
        cfDuid: duid?.oN,
        userAgent: (ua != null && ua.isNotEmpty) ? ua.oN : null,
      ));
    } else {
      final cfCookies = <String, String>{
        if (clearanceValue != null && clearanceValue.isNotEmpty)
          kCfClearance: clearanceValue,
        if (duid != null && duid.isNotEmpty) kCfDuid: duid,
      };
      _extraClearance[cfRootDomain(clearance.host)] = cfCookies;
      if (ua != null && ua.isNotEmpty) {
        userController
            .user(userController.user.value.copyWith(userAgent: ua.oN));
      }
    }
    logger.d('cloudflare clearance applied for ${clearance.host}');
  }
}

/// 检测 Cloudflare 质询，自动弹出 WebView 验证后重试一次
class CloudflareInterceptor extends Interceptor {
  CloudflareInterceptor(this._dio);

  final Dio _dio;

  static const String kRetriedKey = 'cloudflareRetried';

  /// 设置后遇到质询不弹出验证页面，直接返回错误
  static const String kSilentKey = 'cloudflareSilent';

  bool _shouldHandle(Response<dynamic>? response) {
    if (response == null) {
      return false;
    }
    final RequestOptions options = response.requestOptions;
    if (options.extra[kRetriedKey] == true) {
      return false;
    }
    if (!isEhSiteHost(requestHost(options))) {
      return false;
    }
    return isCloudflareChallenge(response);
  }

  Future<Response<dynamic>?> _solveAndRetry(
      Response<dynamic> challenged) async {
    final RequestOptions raw =
        DomainFronting.getRawOptions(challenged.requestOptions);
    // 发生重定向时（如 exhentai -> forums remoteapi）真正被质询的是最终地址
    final Uri realUri = challenged.realUri;
    final bool redirected = realUri.host.isNotEmpty &&
        realUri.host != raw.uri.host &&
        isEhSiteHost(realUri.host);
    final Uri uri = redirected ? realUri : raw.uri;
    // 非 GET 请求不能在 WebView 中直接打开，打开站点首页完成验证
    final Uri challengeUri = redirected || raw.method.toUpperCase() == 'GET'
        ? uri
        : Uri(scheme: uri.scheme, host: uri.host, path: '/');

    if (raw.extra[kSilentKey] == true) {
      return null;
    }

    final bool solved = await CloudflareSolver.instance.solve(challengeUri);
    if (!solved) {
      return null;
    }

    // Cookie 会由 CookieManager 与 EhCookieInterceptor 重新生成（带上新的 cf_clearance）
    final headers = Map<String, dynamic>.fromEntries(raw.headers.entries.where(
        (e) => e.key.toLowerCase() != HttpHeaders.cookieHeader.toLowerCase()));
    // FormData 只能发送一次，重试时需要复制
    final dynamic data =
        raw.data is FormData ? (raw.data as FormData).clone() : raw.data;
    final RequestOptions retryOptions = raw.copyWith(
      data: data,
      headers: headers,
      extra: <String, dynamic>{...raw.extra, kRetriedKey: true}
        ..remove('domainFrontingRawOptions'),
    );
    try {
      return await _dio.fetch<dynamic>(retryOptions);
    } on DioException catch (e) {
      logger.e('cloudflare retry failed: $e');
      return e.response;
    }
  }

  @override
  Future<void> onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) async {
    // 部分请求自定义了 validateStatus，403 也会走到这里
    if (!_shouldHandle(response)) {
      handler.next(response);
      return;
    }
    final retried = await _solveAndRetry(response);
    handler.next(retried ?? response);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.type != DioExceptionType.badResponse ||
        !_shouldHandle(err.response)) {
      handler.next(err);
      return;
    }

    final retried = await _solveAndRetry(err.response!);
    final int status = retried?.statusCode ?? 0;
    if (retried != null &&
        !isCloudflareChallenge(retried) &&
        status >= 200 &&
        status < 400) {
      handler.resolve(retried);
      return;
    }

    handler.next(err.copyWith(
      error: CloudflareChallengeException(
          DomainFronting.getRawOptions(err.requestOptions).uri),
      message: 'Cloudflare challenge',
    ));
  }
}
