import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

/// iOS 26 风格的 Liquid Glass 材质。
///
/// Flutter 没有系统的 Liquid Glass 实现，这里使用
/// 背景模糊 + 饱和度增强（vibrancy）+ 半透明着色 + 镜面高光描边 + 柔和阴影
/// 组合模拟，配合连续曲率圆角（superellipse）贴近系统观感。
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blurSigma = 18,
    this.saturation = 1.8,
    this.tint,
    this.padding,
    this.shadow = true,
    this.rim = true,
  }) : capsule = false;

  /// 胶囊形状（圆角半径随高度自适应）
  const LiquidGlass.capsule({
    super.key,
    required this.child,
    this.blurSigma = 18,
    this.saturation = 1.8,
    this.tint,
    this.padding,
    this.shadow = true,
    this.rim = true,
  })  : borderRadius = BorderRadius.zero,
        capsule = true;

  final Widget child;
  final BorderRadius borderRadius;
  final bool capsule;
  final double blurSigma;
  final double saturation;
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final bool rim;

  static Color defaultTint(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return isDark ? const Color(0x661C1C1E) : const Color(0x73FFFFFF);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final Color baseTint = tint ?? defaultTint(context);

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    final Widget glass = ClipRSuperellipse(
      clipper: _GlassClipper(borderRadius: borderRadius, capsule: capsule),
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ColorFilter.matrix(_saturationMatrix(saturation)),
          inner: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: TileMode.mirror,
          ),
        ),
        child: CustomPaint(
          foregroundPainter: rim
              ? _GlassRimPainter(
                  borderRadius: borderRadius,
                  capsule: capsule,
                  isDark: isDark,
                )
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  _shift(baseTint, isDark ? 0.04 : 0.10),
                  baseTint,
                  _shift(baseTint, isDark ? -0.02 : -0.04),
                ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
            ),
            child: content,
          ),
        ),
      ),
    );

    if (!shadow) {
      return glass;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: capsule
            ? const BorderRadius.all(Radius.circular(999))
            : borderRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color:
                const Color(0xFF000000).withValues(alpha: isDark ? 0.30 : 0.08),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: glass,
    );
  }

  static Color _shift(Color color, double amount) {
    final double alpha = (color.a + amount).clamp(0.0, 1.0);
    return color.withValues(alpha: alpha);
  }

  static List<double> _saturationMatrix(double s) {
    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;
    final double sr = (1 - s) * lr;
    final double sg = (1 - s) * lg;
    final double sb = (1 - s) * lb;
    return <double>[
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}

BorderRadius _effectiveRadius(BorderRadius radius, bool capsule, Size size) {
  final double max = size.shortestSide / 2;
  if (capsule) {
    return BorderRadius.all(Radius.circular(max));
  }
  Radius clamp(Radius r) => Radius.elliptical(
      r.x.clamp(0.0, max).toDouble(), r.y.clamp(0.0, max).toDouble());
  return BorderRadius.only(
    topLeft: clamp(radius.topLeft),
    topRight: clamp(radius.topRight),
    bottomLeft: clamp(radius.bottomLeft),
    bottomRight: clamp(radius.bottomRight),
  );
}

class _GlassClipper extends CustomClipper<RSuperellipse> {
  const _GlassClipper({required this.borderRadius, required this.capsule});

  final BorderRadius borderRadius;
  final bool capsule;

  @override
  RSuperellipse getClip(Size size) {
    return _effectiveRadius(borderRadius, capsule, size)
        .toRSuperellipse(Offset.zero & size);
  }

  @override
  bool shouldReclip(covariant _GlassClipper oldClipper) {
    return oldClipper.borderRadius != borderRadius ||
        oldClipper.capsule != capsule;
  }
}

/// 镜面高光描边：左上亮、右下弱，模拟玻璃边缘的折射高光
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter({
    required this.borderRadius,
    required this.capsule,
    required this.isDark,
  });

  final BorderRadius borderRadius;
  final bool capsule;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect inner = rect.deflate(0.5);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: isDark ? 0.34 : 0.85),
          const Color(0xFFFFFFFF).withValues(alpha: isDark ? 0.06 : 0.20),
          const Color(0xFFFFFFFF).withValues(alpha: isDark ? 0.16 : 0.45),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRSuperellipse(
        _effectiveRadius(borderRadius, capsule, inner.size)
            .toRSuperellipse(inner),
        paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.capsule != capsule ||
        oldDelegate.isDark != isDark;
  }
}

/// Liquid Glass 风格按钮（胶囊 / 圆形），用于导航栏和浮动操作
class LiquidGlassButton extends StatefulWidget {
  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.minSize = 44,
    this.tint,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double minSize;
  final Color? tint;

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 150),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.minSize,
                minWidth: widget.minSize,
              ),
              child: LiquidGlass.capsule(
                tint: widget.tint,
                shadow: false,
                padding: widget.padding,
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
