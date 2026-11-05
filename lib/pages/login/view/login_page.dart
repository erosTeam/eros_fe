import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/widget/liquid_glass/liquid_glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

import '../controller/login_controller.dart';

/// Liquid Glass 风格的登录页背景：柔和的彩色光斑，让玻璃材质有内容可以折射
class LoginGlassBackground extends StatelessWidget {
  const LoginGlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final Color base = CupertinoDynamicColor.resolve(
        CupertinoColors.systemGroupedBackground, context);
    Widget blob(Alignment alignment, Color color, double size) {
      return Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                color.withValues(alpha: isDark ? 0.55 : 0.45),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          blob(const Alignment(-1.2, -0.9), CupertinoColors.systemBlue, 420),
          blob(const Alignment(1.3, -0.4), CupertinoColors.systemPurple, 360),
          blob(const Alignment(-0.6, 1.1), CupertinoColors.systemTeal, 380),
          child,
        ],
      ),
    );
  }
}

class LoginPage extends GetView<LoginController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(context);
    final placeholderStyle = kTextStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: CupertinoColors.placeholderText,
    );
    final Color primary = CupertinoTheme.of(context).primaryColor;

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l10n.user_login),
        backgroundColor: Colors.transparent,
        border: null,
      ),
      child: LoginGlassBackground(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: LiquidGlass(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(36)),
                        padding: const EdgeInsets.all(22),
                        child: FaIcon(
                          FontAwesomeIcons.circleUser,
                          size: 64,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 网页登录：可以直接完成 Cloudflare 验证，最可靠
                    if (GetPlatform.isMobile) ...<Widget>[
                      _PrimaryGlassButton(
                        icon: FontAwesomeIcons.earthAmericas,
                        label: l10n.login_web,
                        onPressed: controller.handOnWeblogin,
                      ),
                      const SizedBox(height: 28),
                    ],

                    LiquidGlass(
                      borderRadius: const BorderRadius.all(Radius.circular(26)),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: <Widget>[
                          CupertinoTextFormFieldRow(
                            controller: controller.usernameController,
                            style: kTextStyle,
                            placeholderStyle: placeholderStyle,
                            prefix: Row(
                              children: [
                                const FaIcon(
                                  FontAwesomeIcons.user,
                                  size: 18,
                                ).paddingOnly(right: 12.0),
                                Text(l10n.user_name),
                              ],
                            ),
                            textAlign: TextAlign.right,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[
                              AutofillHints.username
                            ],
                            onEditingComplete: () {
                              FocusScope.of(context)
                                  .requestFocus(controller.nodePwd);
                            },
                          ),
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.only(left: 20),
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.separator, context),
                          ),
                          GetBuilder<LoginController>(
                            builder: (logic) {
                              return CupertinoTextFormFieldRow(
                                controller: controller.passwdController,
                                style: kTextStyle,
                                placeholderStyle: placeholderStyle,
                                prefix: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: logic.switchObscure,
                                      child: FaIcon(
                                        logic.obscurePasswd
                                            ? FontAwesomeIcons.eyeSlash
                                            : FontAwesomeIcons.eye,
                                        size: 18,
                                      ).paddingOnly(right: 12.0),
                                    ),
                                    Text(l10n.passwd),
                                  ],
                                ),
                                textAlign: TextAlign.right,
                                obscureText: logic.obscurePasswd,
                                focusNode: logic.nodePwd,
                                textInputAction: TextInputAction.done,
                                autofillHints: const <String>[
                                  AutofillHints.password
                                ],
                                onFieldSubmitted: (_) => logic.pressLogin(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GetBuilder<LoginController>(
                      builder: (logic) {
                        return LiquidGlassButton(
                          minSize: 50,
                          onPressed:
                              logic.loadingLogin ? null : logic.pressLogin,
                          child: logic.loadingLogin
                              ? const CupertinoActivityIndicator()
                              : Text(
                                  l10n.login,
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.2,
                                    color: primary,
                                  ),
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: LiquidGlassButton(
                        onPressed: controller.hanOnCookieLogin,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            FaIcon(FontAwesomeIcons.cookieBite,
                                size: 18, color: primary),
                            const SizedBox(width: 8),
                            Text(
                              'Cookie',
                              style: TextStyle(fontSize: 15, color: primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryGlassButton extends StatelessWidget {
  const _PrimaryGlassButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color primary = CupertinoTheme.of(context).primaryColor;
    return LiquidGlassButton(
      minSize: 54,
      tint: primary.withValues(alpha: 0.82),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FaIcon(icon, size: 20, color: CupertinoColors.white),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                height: 1.2,
                color: CupertinoColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
