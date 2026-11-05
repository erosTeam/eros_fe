import 'package:eros_fe/pages/tab/controller/tabhome_controller.dart';
import 'package:eros_fe/widget/liquid_glass/liquid_glass_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

class TabHomeSmall extends GetView<TabHomeController> {
  const TabHomeSmall({super.key});
  @override
  Widget build(BuildContext context) {
    controller.init(inContext: context);

    return Obx(() => CupertinoTabScaffold(
          controller: controller.tabController,
          // iOS 26 Liquid Glass 风格的悬浮标签栏，内容延伸到标签栏下方
          tabBar: LiquidGlassTabBar(
            items: controller.listBottomNavigationBarItem,
            onTap: controller.onTap,
          ),
          tabBuilder: (BuildContext context, int index) {
            return CupertinoTabView(
              builder: (BuildContext context) {
                return controller.viewList[index];
              },
            );
          },
        ));
  }
}
