import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'liquid_glass.dart';

const double _kTopGap = 6;
const double _kMinBottomGap = 10;
const Cubic _kLiquidCurve = Cubic(0.2, 1.18, 0.32, 1.0);

/// iOS 26 风格的悬浮胶囊标签栏。
///
/// 继承 [CupertinoTabBar] 以便直接用于 [CupertinoTabScaffold]：
/// 背景透明（非 opaque），页面内容会延伸到标签栏下方，透过玻璃材质可见。
class LiquidGlassTabBar extends CupertinoTabBar {
  const LiquidGlassTabBar({
    super.key,
    required super.items,
    super.onTap,
    super.currentIndex,
    super.activeColor,
    super.iconSize = 24,
    this.barHeight = 62,
    this.horizontalMargin = 18,
    this.maxWidth = 560,
  }) : super(
          height: barHeight + _kTopGap + _kMinBottomGap,
          backgroundColor: const Color(0x00000000),
          border: null,
        );

  /// 胶囊本身的高度
  final double barHeight;
  final double horizontalMargin;

  /// 宽屏（iPad）上胶囊的最大宽度
  final double maxWidth;

  @override
  bool opaque(BuildContext context) => false;

  @override
  LiquidGlassTabBar copyWith({
    Key? key,
    List<BottomNavigationBarItem>? items,
    Color? backgroundColor,
    Color? activeColor,
    Color? inactiveColor,
    double? iconSize,
    double? height,
    Border? border,
    int? currentIndex,
    ValueChanged<int>? onTap,
  }) {
    return LiquidGlassTabBar(
      key: key ?? this.key,
      items: items ?? this.items,
      onTap: onTap ?? this.onTap,
      currentIndex: currentIndex ?? this.currentIndex,
      activeColor: activeColor ?? this.activeColor,
      iconSize: iconSize ?? this.iconSize,
      barHeight: barHeight,
      horizontalMargin: horizontalMargin,
      maxWidth: maxWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    // 有 Home Indicator 时胶囊略微下沉进安全区，与系统一致
    final double bottomGap = safeBottom > 0
        ? math.max(safeBottom - 12, _kMinBottomGap)
        : _kMinBottomGap + 4;

    final Color active = activeColor ?? CupertinoTheme.of(context).primaryColor;
    final Color inactive =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context)
            .withValues(alpha: 0.86);
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          horizontalMargin, _kTopGap, horizontalMargin, bottomGap),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(
            height: barHeight,
            child: LiquidGlass.capsule(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  const double inset = 4;
                  final double itemWidth = constraints.maxWidth / items.length;
                  final int index = currentIndex.clamp(0, items.length - 1);
                  return Stack(
                    children: <Widget>[
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 420),
                        curve: _kLiquidCurve,
                        left: itemWidth * index + inset,
                        top: inset,
                        bottom: inset,
                        width: itemWidth - inset * 2,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: const StadiumBorder(),
                            color: isDark
                                ? const Color(0x24FFFFFF)
                                : const Color(0x14000000),
                          ),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          for (int i = 0; i < items.length; i++)
                            Expanded(
                              child: _LiquidGlassTabItem(
                                item: items[i],
                                active: i == index,
                                activeColor: active,
                                inactiveColor: inactive,
                                iconSize: iconSize,
                                onTap: onTap == null ? null : () => onTap!(i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassTabItem extends StatelessWidget {
  const _LiquidGlassTabItem({
    required this.item,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.iconSize,
    this.onTap,
  });

  final BottomNavigationBarItem item;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? activeColor : inactiveColor;
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: active ? 1.0 : 0.94,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: const Duration(milliseconds: 220),
            builder: (BuildContext context, Color? value, Widget? child) {
              final Color c = value ?? color;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconTheme.merge(
                    data: IconThemeData(color: c, size: iconSize),
                    child: active ? item.activeIcon : item.icon,
                  ),
                  if (item.label != null && item.label!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label!,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.1,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w500,
                            color: c,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
