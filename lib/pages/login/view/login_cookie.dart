import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/pages/login/view/login_page.dart';
import 'package:eros_fe/widget/liquid_glass/liquid_glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

import '../controller/login_controller.dart';

class LoginCookie extends GetView<LoginController> {
  const LoginCookie({super.key});

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(context);
    final Color primary = CupertinoTheme.of(context).primaryColor;
    final placeholderStyle = kTextStyle.copyWith(
      fontWeight: FontWeight.w400,
      color: CupertinoColors.placeholderText,
    );

    return CupertinoPageScaffold(
      backgroundColor: Colors.transparent,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Cookie Login'),
        backgroundColor: Colors.transparent,
        border: null,
      ),
      child: LoginGlassBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: LiquidGlass(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(36)),
                        padding: const EdgeInsets.all(22),
                        child: FaIcon(
                          FontAwesomeIcons.cookieBite,
                          size: 64,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    LiquidGlass(
                      borderRadius: const BorderRadius.all(Radius.circular(26)),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          CupertinoTextFormFieldRow(
                            controller: controller.idController,
                            style: kTextStyle,
                            placeholderStyle: placeholderStyle,
                            placeholder: 'ipb_member_id',
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            onEditingComplete: () =>
                                FocusScope.of(context).nextFocus(),
                          ),
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.only(left: 20),
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.separator, context),
                          ),
                          CupertinoTextFormFieldRow(
                            controller: controller.hashController,
                            style: kTextStyle,
                            placeholderStyle: placeholderStyle,
                            placeholder: 'ipb_pass_hash',
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                controller.pressLoginCookie(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GetBuilder<LoginController>(
                      builder: (logic) {
                        return LiquidGlassButton(
                          minSize: 50,
                          tint: primary.withValues(alpha: 0.82),
                          onPressed: logic.loadingLogin
                              ? null
                              : logic.pressLoginCookie,
                          child: logic.loadingLogin
                              ? const CupertinoActivityIndicator(
                                  color: CupertinoColors.white)
                              : Text(
                                  l10n.login,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.2,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: LiquidGlassButton(
                        onPressed: controller.readCookieFromClipboard,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.clipboard,
                                size: 18, color: primary),
                            const SizedBox(width: 8),
                            Text(
                              l10n.read_from_clipboard,
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
