import 'dart:convert';
import 'dart:io';

import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/index.dart';
import 'package:eros_fe/network/api.dart';
import 'package:eros_fe/network/cloudflare/cloudflare.dart';
import 'package:eros_fe/network/request.dart';
import 'package:eros_fe/pages/login/view/login_cookie.dart';
import 'package:eros_fe/pages/login/view/web_login_in.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

const TextStyle kTextStyle = TextStyle(
  fontSize: 18,
  textBaseline: TextBaseline.alphabetic,
  height: 1.2,
);

class LoginController extends GetxController {
  final FocusNode nodePwd = FocusNode();

  //账号的控制器
  final TextEditingController usernameController = TextEditingController();

  //密码的控制器
  final TextEditingController passwdController = TextEditingController();

  // ibp_member_id
  final TextEditingController idController = TextEditingController();

  // ibp_pass_hash
  final TextEditingController hashController = TextEditingController();

  // igneous
  // final TextEditingController igneousController = TextEditingController();

  final UserController userController = Get.find();

  bool loadingLogin = false;

  bool obscurePasswd = true;

  /// 用户登录
  Future<void> pressLogin() async {
    if (loadingLogin) {
      return;
    }

    loggerNoStack.i({'username': usernameController.text});

    if (usernameController.text.isEmpty || passwdController.text.isEmpty) {
      showToast('username or password is empty');
      return;
    } else {
      loadingLogin = true;
      update();
    }

    FocusScope.of(Get.context!).requestFocus(FocusNode());
    User? user;
    try {
      user = await userLogin(usernameController.text, passwdController.text);
      logger.d('user: ${user?.toJson()}');
    } catch (e, stack) {
      logger.e('password login error: $e\n$stack');
    } finally {
      loadingLogin = false;
      update();
    }

    final memberId = user?.memberId?.trim();
    final passHash = user?.passHash?.trim();
    if (user == null ||
        !isValidMemberId(memberId) ||
        !isValidPassHash(passHash)) {
      // 论坛登录现在需要 Cloudflare / 验证码，账号密码登录经常失败
      showToast(L10n.current.login_failed_try_web);
      return;
    }

    // 合并到当前用户，保留 Cloudflare 验证得到的 cf_clearance 与 UA
    userController.user(userController.user.value.copyWith(
      username: usernameController.text.oN,
      memberId: memberId!.oN,
      passHash: passHash!.oN,
      igneous: _validIgneous(user.igneous)?.oN,
      hathPerks: user.hathPerks?.oN,
      sk: user.sk?.oN,
    ));

    _afterLogin(memberId);
    Get.back();
  }

  // cookie登陆
  Future<void> pressLoginCookie() async {
    if (loadingLogin) {
      return;
    }

    final memberId = idController.text.trim();
    final passHash = hashController.text.trim();
    // final igneous = igneousController.text.trim();

    if (memberId.isEmpty || passHash.isEmpty) {
      showToast('ibp_member_id or ibp_pass_hash is empty');
      return;
    } else if (!isValidMemberId(memberId) || !isValidPassHash(passHash)) {
      showToast('ibp_member_id or ibp_pass_hash is invalid');
      return;
    } else {
      loadingLogin = true;
      update();
    }

    FocusScope.of(Get.context!).requestFocus(FocusNode());

    final List<Cookie> cookies = <Cookie>[
      Cookie('ipb_member_id', memberId),
      Cookie('ipb_pass_hash', passHash),
      // if (igneous.isNotEmpty) Cookie('igneous', igneous),
    ];

    // final PersistCookieJar cookieJar = await Api.cookieJar;

    // 设置EH的cookie
    // cookieJar.saveFromResponse(Uri.parse(EHConst.EH_BASE_URL), cookies);

    final user = userController.user.value.copyWith(
      username: '${memberId.substring(0, 1)}****'.oN,
      memberId: memberId.oN,
      passHash: _getCookiesValue(cookies, 'ipb_pass_hash')?.oN,
      igneous: _getCookiesValue(cookies, 'igneous')?.oN,
      hathPerks: _getCookiesValue(cookies, 'hath_perks')?.oN,
      sk: _getCookiesValue(cookies, 'sk')?.oN,
    );

    logger.d('user ${user.toJson()}');

    userController.user(user);

    // 用户信息在论坛上，可能被 Cloudflare 拦截，获取失败不影响登录
    final bool infoOk = await asyncGetUserInfo(memberId);
    loadingLogin = false;
    update();
    if (!infoOk) {
      showToast(L10n.current.fetch_user_info_failed);
    }

    Get.back(result: true);
  }

  /// 网页登陆
  Future<void> handOnWeblogin() async {
    if (!GetPlatform.isIOS && !GetPlatform.isAndroid) {
      showToast('Platform not yet supported');
      return;
    }

    final result = await Get.toNamed(
      EHRoutes.webLogin,
      preventDuplicates: false,
    );

    if (result is! WebLoginResult) {
      return;
    }

    final Map<String, String> cookies = result.cookies;
    final memberId = cookies['ipb_member_id']?.trim();
    final passHash = cookies['ipb_pass_hash']?.trim();
    logger.d('web login memberId: $memberId');

    if (!isValidMemberId(memberId) || !isValidPassHash(passHash)) {
      showToast(L10n.current.login_failed_try_web);
      return;
    }

    final String? cfClearance = cookies[kCfClearance];
    final String? userAgent = result.userAgent;

    final user = userController.user.value.copyWith(
      username: '${memberId!.substring(0, 1)}****'.oN,
      memberId: memberId.oN,
      passHash: passHash!.oN,
      igneous: _validIgneous(cookies['igneous'])?.oN,
      hathPerks: cookies['hath_perks']?.oN,
      sk: cookies['sk']?.oN,
      star: cookies['star']?.oN,
      // cf_clearance 与 UA 必须成对更新，否则会被 Cloudflare 反复质询
      cfClearance: (cfClearance != null && cfClearance.isNotEmpty)
          ? cfClearance.oN
          : null,
      cfDuid: cookies[kCfDuid]?.oN,
      userAgent:
          (userAgent != null && userAgent.isNotEmpty) ? userAgent.oN : null,
    );

    logger.d('>>>>>>>>>>>>>>>> user ${user.toJson()}');

    userController.user(user);
    showToast(L10n.current.login_success);

    _afterLogin(memberId);
    Get.back();
  }

  /// 登录后的后台任务，失败不影响登录状态
  void _afterLogin(String memberId) {
    Api.selEhProfile().catchError((Object e, StackTrace stack) {
      logger.e('selEhProfile error: $e\n$stack');
      return null;
    });
    asyncGetUserInfo(memberId).then((bool ok) {
      if (!ok) {
        showToast(L10n.current.fetch_user_info_failed);
      }
    });
  }

  String? _validIgneous(String? igneous) {
    if (igneous == null ||
        igneous.isEmpty ||
        igneous == 'mystery' ||
        igneous == 'deleted') {
      return null;
    }
    return igneous;
  }

  /// 获取昵称和头像，返回是否成功
  Future<bool> asyncGetUserInfo([String? memberId]) async {
    memberId ??= userController.user.value.memberId;
    if (memberId == null || memberId.isEmpty) {
      return false;
    }
    logger.d('异步获取昵称和头像');
    try {
      final User? info = await getUserInfo(memberId);
      if (info == null) {
        return false;
      }
      userController.user(userController.user.value.copyWith(
        nickName: info.nickName?.oN,
        avatarUrl: info.avatarUrl?.oN,
      ));
      userController.update();
      return true;
    } catch (e, stack) {
      logger.e('get user info error: $e\n$stack');
      return false;
    }
  }

  Future<void> readCookieFromClipboard() async {
    final kMatchMenberId = RegExp(r'^\d+$');
    final kMatchPassHash = RegExp(r'^[\da-f]{32}$');
    // final kMatchIgneous = RegExp(r'^[\da-f]+$');

    final String clipText =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    // logger.d('Clipboard:\n' + _clipText);
    if (!clipText.contains('{')) {
      final textArray = clipText.split(RegExp(r'[\s:;&=]'));
      logger.d('textArray:$textArray');
      for (final text in textArray) {
        if (kMatchMenberId.hasMatch(text)) {
          logger.d('id:$text');
          idController.text = text;
          continue;
        }
        if (kMatchPassHash.hasMatch(text)) {
          logger.d('passHash:$text');
          hashController.text = text;
          continue;
        }
        // if (kMatchIgneous.hasMatch(text)) {
        //   logger.d('igneous:$text');
        //   igneousController.text = text;
        // }
      }
      return;
    }

    try {
      final jsonObj = jsonDecode(clipText);
      final cookieList = jsonObj as List;
      final cookieMap = <String, String>{};
      for (final cookie in cookieList) {
        final _cookieMap = cookie as Map<String, dynamic>;
        final _name = _cookieMap['name'] as String;
        final _value = _cookieMap['value'] as String;
        cookieMap[_name] = _value;
      }
      idController.text = cookieMap['ipb_member_id'] ?? '';
      hashController.text = cookieMap['ipb_pass_hash'] ?? '';
      // igneousController.text = cookieMap['igneous'] ?? '';
    } catch (e) {
      logger.e('$e');
    }
  }

  String? _getCookiesValue(List<Cookie> cookies, String name) {
    return cookies.firstWhereOrNull((e) => e.name == name)?.value;
  }

  void switchObscure() {
    obscurePasswd = !obscurePasswd;
    update();
  }

  Future<void> hanOnCookieLogin() async {
    final result = await Get.to(() => const LoginCookie());
    if (result != null && result is bool && result) {
      Api.selEhProfile();
      Get.back();
    }
  }
}
