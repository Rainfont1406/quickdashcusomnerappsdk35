import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';

class Styles {
  static ThemeData themeData(bool isDarkTheme, BuildContext context) {
    return ThemeData(
      useMaterial3: false,
      scaffoldBackgroundColor: isDarkTheme?AppThemeData.surfaceDark:AppThemeData.surface,
      primaryColor: isDarkTheme ? AppThemeData.primary500 : AppThemeData.primary500,
      indicatorColor: isDarkTheme ? const Color(0xff0E1D36) : const Color(0xffCBDCF8),
      hintColor: isDarkTheme ? Colors.white38 : Colors.black38,
      highlightColor: isDarkTheme ? Colors.white38 : Colors.black38,
      disabledColor: Colors.grey,
      iconTheme: IconThemeData(color: isDarkTheme ? Colors.white : Colors.black),
      cardColor: isDarkTheme ? const Color(0xFF151515) : Colors.white,
      canvasColor: isDarkTheme ? Colors.black : Colors.grey[50],
      brightness: isDarkTheme ? Brightness.dark : Brightness.light,
      bottomSheetTheme: isDarkTheme ? BottomSheetThemeData(backgroundColor: Colors.grey.shade900) : const BottomSheetThemeData(backgroundColor: Colors.white),
      buttonTheme: Theme.of(context).buttonTheme.copyWith(colorScheme: isDarkTheme ? const ColorScheme.dark() : const ColorScheme.light()),
      appBarTheme: isDarkTheme
          ? AppBarTheme(backgroundColor: AppThemeData.surfaceDark, centerTitle: true, iconTheme: IconThemeData(color: Colors.white), elevation: 0)
          : AppBarTheme(
              titleTextStyle: TextStyle(color: Colors.white, fontFamily: AppThemeData.semiBold),
              backgroundColor: AppThemeData.primary500,
              centerTitle: true,
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 0),
      textSelectionTheme: TextSelectionThemeData(selectionColor: isDarkTheme ? Colors.white : Colors.black),
      fontFamily: AppThemeData.regular,
      fontFamilyFallback: [
        AppThemeData.regular,
        AppThemeData.medium,
        AppThemeData.semiBold,
        AppThemeData.bold,
      ],
    );
  }
}
