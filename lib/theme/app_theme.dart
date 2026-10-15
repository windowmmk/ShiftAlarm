import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 是否支援原生 Android 鬧鐘與系統權限（iOS / Web 平台不支援，隱藏相關介面）
bool get isNativeAlarmSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 時段 Design Tokens（底色 / 文字 / 邊框色）
/// 用法：`Theme.of(context).extension<ShiftTokens>()!`
@immutable
class ShiftTokens extends ThemeExtension<ShiftTokens> {
  // ── 時段四色：底 / 字 / 邊 ──────────────────────────────
  final Color slot00Bg;
  final Color slot00Fg;
  final Color slot00Border;
  final Color slot06Bg;
  final Color slot06Fg;
  final Color slot06Border;
  final Color slot12Bg;
  final Color slot12Fg;
  final Color slot12Border;
  final Color slot18Bg;
  final Color slot18Fg;
  final Color slot18Border;

  // ── Fluent 中性色 ─────────────────────────────────────
  final Color neutralBg; // #FFFFFF
  final Color neutralBg2; // #F5F5F5
  final Color neutralFg; // #242424
  final Color neutralFg2; // #616161
  final Color neutralStroke; // #D1D1D1
  final Color brand; // #0078D4
  final Color danger; // #BC2F32

  // ── 字級 ──────────────────────────────────────────────
  final double fontCaption; // 12
  final double fontBody; // 14
  final double fontSubtitle; // 20
  final double fontTitle; // 28

  const ShiftTokens({
    this.slot00Bg = const Color(0xFFFEF9C3),
    this.slot00Fg = const Color(0xFF854D0E),
    this.slot00Border = const Color(0xFFFDE68A),
    this.slot06Bg = const Color(0xFFFDF2F8),
    this.slot06Fg = const Color(0xFF9D174D),
    this.slot06Border = const Color(0xFFF9A8D4),
    this.slot12Bg = const Color(0xFFFBCFE8),
    this.slot12Fg = const Color(0xFF831843),
    this.slot12Border = const Color(0xFFF9A8D4),
    this.slot18Bg = const Color(0xFFEDE9FE),
    this.slot18Fg = const Color(0xFF5B21B6),
    this.slot18Border = const Color(0xFFC4B5FD),
    this.neutralBg = const Color(0xFFFFFFFF),
    this.neutralBg2 = const Color(0xFFF6F8FA),
    this.neutralFg = const Color(0xFF1F2328),
    this.neutralFg2 = const Color(0xFF656D76),
    this.neutralStroke = const Color(0xFFD0D7DE),
    this.brand = const Color(0xFF0969DA),
    this.danger = const Color(0xFFCF222E),
    this.fontCaption = 12,
    this.fontBody = 14,
    this.fontSubtitle = 20,
    this.fontTitle = 28,
  });

  /// 按開工鐘點取時段色：00–06 / 06–12 / 12–18 / 18–00
  SlotColors slotForHour(int hour) {
    if (hour < 6) return SlotColors(slot00Bg, slot00Fg, slot00Border);
    if (hour < 12) return SlotColors(slot06Bg, slot06Fg, slot06Border);
    if (hour < 18) return SlotColors(slot12Bg, slot12Fg, slot12Border);
    return SlotColors(slot18Bg, slot18Fg, slot18Border);
  }

  /// 按 "HH:mm" 取時段色
  SlotColors slotForTime(String hhmm) {
    final hour = int.tryParse(hhmm.split(':').firstOrNull ?? '') ?? 0;
    return slotForHour(hour.clamp(0, 23));
  }

  @override
  ShiftTokens copyWith({
    Color? slot00Bg,
    Color? slot00Fg,
    Color? slot00Border,
    Color? slot06Bg,
    Color? slot06Fg,
    Color? slot06Border,
    Color? slot12Bg,
    Color? slot12Fg,
    Color? slot12Border,
    Color? slot18Bg,
    Color? slot18Fg,
    Color? slot18Border,
    Color? neutralBg,
    Color? neutralBg2,
    Color? neutralFg,
    Color? neutralFg2,
    Color? neutralStroke,
    Color? brand,
    Color? danger,
    double? fontCaption,
    double? fontBody,
    double? fontSubtitle,
    double? fontTitle,
  }) {
    return ShiftTokens(
      slot00Bg: slot00Bg ?? this.slot00Bg,
      slot00Fg: slot00Fg ?? this.slot00Fg,
      slot00Border: slot00Border ?? this.slot00Border,
      slot06Bg: slot06Bg ?? this.slot06Bg,
      slot06Fg: slot06Fg ?? this.slot06Fg,
      slot06Border: slot06Border ?? this.slot06Border,
      slot12Bg: slot12Bg ?? this.slot12Bg,
      slot12Fg: slot12Fg ?? this.slot12Fg,
      slot12Border: slot12Border ?? this.slot12Border,
      slot18Bg: slot18Bg ?? this.slot18Bg,
      slot18Fg: slot18Fg ?? this.slot18Fg,
      slot18Border: slot18Border ?? this.slot18Border,
      neutralBg: neutralBg ?? this.neutralBg,
      neutralBg2: neutralBg2 ?? this.neutralBg2,
      neutralFg: neutralFg ?? this.neutralFg,
      neutralFg2: neutralFg2 ?? this.neutralFg2,
      neutralStroke: neutralStroke ?? this.neutralStroke,
      brand: brand ?? this.brand,
      danger: danger ?? this.danger,
      fontCaption: fontCaption ?? this.fontCaption,
      fontBody: fontBody ?? this.fontBody,
      fontSubtitle: fontSubtitle ?? this.fontSubtitle,
      fontTitle: fontTitle ?? this.fontTitle,
    );
  }

  @override
  ShiftTokens lerp(ThemeExtension<ShiftTokens>? other, double t) {
    if (other is! ShiftTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ShiftTokens(
      slot00Bg: l(slot00Bg, other.slot00Bg),
      slot00Fg: l(slot00Fg, other.slot00Fg),
      slot00Border: l(slot00Border, other.slot00Border),
      slot06Bg: l(slot06Bg, other.slot06Bg),
      slot06Fg: l(slot06Fg, other.slot06Fg),
      slot06Border: l(slot06Border, other.slot06Border),
      slot12Bg: l(slot12Bg, other.slot12Bg),
      slot12Fg: l(slot12Fg, other.slot12Fg),
      slot12Border: l(slot12Border, other.slot12Border),
      slot18Bg: l(slot18Bg, other.slot18Bg),
      slot18Fg: l(slot18Fg, other.slot18Fg),
      slot18Border: l(slot18Border, other.slot18Border),
      neutralBg: l(neutralBg, other.neutralBg),
      neutralBg2: l(neutralBg2, other.neutralBg2),
      neutralFg: l(neutralFg, other.neutralFg),
      neutralFg2: l(neutralFg2, other.neutralFg2),
      neutralStroke: l(neutralStroke, other.neutralStroke),
      brand: l(brand, other.brand),
      danger: l(danger, other.danger),
      fontCaption: fontCaption + (other.fontCaption - fontCaption) * t,
      fontBody: fontBody + (other.fontBody - fontBody) * t,
      fontSubtitle: fontSubtitle + (other.fontSubtitle - fontSubtitle) * t,
      fontTitle: fontTitle + (other.fontTitle - fontTitle) * t,
    );
  }
}

/// 一組時段色
@immutable
class SlotColors {
  final Color bg;
  final Color fg;
  final Color border;
  const SlotColors(this.bg, this.fg, this.border);
}

/// 方便取用
extension ShiftTokensContext on BuildContext {
  ShiftTokens get tokens => Theme.of(this).extension<ShiftTokens>()!;
}

ThemeData buildAppTheme() {
  const t = ShiftTokens();
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: t.neutralBg,
    colorScheme: ColorScheme.light(
      primary: t.brand,
      onPrimary: Colors.white,
      secondary: t.brand,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE8F1FC), // 消除 M3 預設薄荷青，鎖定冷淡冰藍
      onSecondaryContainer: t.brand,
      surface: t.neutralBg,
      onSurface: t.neutralFg,
      surfaceContainerHighest: t.neutralBg2,
      outline: t.neutralStroke,
      outlineVariant: const Color(0xFFE1E4E8),
      error: t.danger,
      onError: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.neutralBg,
      foregroundColor: t.neutralFg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: t.neutralFg,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: t.neutralFg),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      height: 64,
      indicatorColor: const Color(0xFFE8F1FC),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: t.brand, size: 24);
        }
        return IconThemeData(color: t.neutralFg2, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: t.brand,
          );
        }
        return TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: t.neutralFg2,
        );
      }),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.neutralStroke, width: 1),
      ),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: t.neutralFg,
      ),
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.neutralStroke, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: t.brand,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: t.neutralStroke, width: 1),
        foregroundColor: t.neutralFg,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        foregroundColor: t.brand,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.neutralBg2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.neutralStroke, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.neutralStroke, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.brand, width: 1.5),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: t.neutralStroke,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide.none,
      showCheckmark: false,
    ),
    extensions: const [ShiftTokens()],
  );
}
