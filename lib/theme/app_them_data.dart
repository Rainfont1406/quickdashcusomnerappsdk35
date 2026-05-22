import 'package:flutter/material.dart';

class AppThemeData {
  // Primary Color Scale — Purple (QuickDash brand)
  static const Color primary50 = Color(0xFFF5F3FF);
  static const Color primary100 = Color(0xFFEDE9FE);
  static const Color primary200 = Color(0xFFDDD6FE);
  static Color primary300 = Color(0xFFC4B5FD); // mutable — overwritten from Firestore
  static const Color primary400 = Color(0xFFA78BFA);
  static const Color primary500 = Color(0xFF7C3AED); // main brand purple
  static const Color primary600 = Color(0xFF6D28D9);
  static const Color primary700 = Color(0xFF5B21B6);
  static const Color primary800 = Color(0xFF4C1D95);
  static const Color primary900 = Color(0xFF2E1065);

  // Orange Accent Scale — for offers, discounts, pricing & promotional CTAs
  static const Color accent50 = Color(0xFFFFF7ED);
  static const Color accent100 = Color(0xFFFFEDD5);
  static const Color accent200 = Color(0xFFFED7AA);
  static const Color accent300 = Color(0xFFFDBA74);
  static const Color accent400 = Color(0xFFFB923C);
  static const Color accent500 = Color(0xFFF97316); // main orange accent
  static const Color accent600 = Color(0xFFEA580C);

  // New Neutral Color Scale from UI Guidelines
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFFAFAFA);
  static const Color neutral100 = Color(0xFFF5F5F5);
  static const Color neutral200 = Color(0xFFE5E5E5);
  static const Color neutral300 = Color(0xFFD4D4D4);
  static const Color neutral400 = Color(0xFFA3A3A3);
  static const Color neutral500 = Color(0xFF737373);
  static const Color neutral600 = Color(0xFF525252);
  static const Color neutral700 = Color(0xFF404040);
  static const Color neutral800 = Color(0xFF262626);
  static const Color neutral900 = Color(0xFF171717);
  static const Color neutral950 = Color(0xFF0A0A0A);

  // New Dark Mode Colors from UI Guidelines
  static const Color darkBgPrimary = Color(0xFF0A0A0A);
  static const Color darkBgSecondary = Color(0xFF171717);
  static const Color darkBgTertiary = Color(0xFF262626);
  static const Color darkTextPrimary = Color(0xFFFAFAFA);
  static const Color darkTextSecondary = Color(0xFFD4D4D4);
  static const Color darkTextTertiary = Color(0xFFA3A3A3);
  static const Color darkBorderPrimary = Color(0xFF404040);
  static const Color darkBorderSecondary = Color(0xFF262626);

  // New Semantic Colors from UI Guidelines
  static const Color error500 = Color(0xFFEF4444);

  static const Color surface = Color(0xFFF9FAFB);
  static const Color surfaceDark = Color(0xFF030712);

  static const Color info50 = Color(0xFFE5F9FF);
  static const Color info100 = Color(0xFFACECFF);
  static const Color info200 = Color(0xFF72DEFF);
  static const Color info300 = Color(0xFF38D0FF);
  static const Color info400 = Color(0xFF2692B2);
  static const Color info500 = Color(0xFF135366);
  static const Color info600 = Color(0xFF00141A);

  static const Color danger50 = Color(0xFFFFE5E6);
  static const Color danger100 = Color(0xFFFFACAE);
  static const Color danger200 = Color(0xFFFF7277);
  static const Color danger300 = Color(0xFFFF3840);
  static const Color danger400 = Color(0xFFB2262B);
  static const Color danger500 = Color(0xFF661316);
  static const Color danger600 = Color(0xFF1A0001);

  static const Color secondary50 = Color(0xFFEBE5FF);
  static const Color secondary100 = Color(0xFFC0ABFF);
  static const Color secondary200 = Color(0xFF9472FF);
  static const Color secondary300 = Color(0xFF6839FF);
  static const Color secondary400 = Color(0xFF4826B2);
  static const Color secondary500 = Color(0xFF271366);
  static const Color secondary600 = Color(0xFF06001A);

  static const Color success50 = Color(0xFFE5FFF5);
  static const Color success100 = Color(0xFFA1FFD9);
  static const Color success200 = Color(0xFF5DFFBE);
  static const Color success300 = Color(0xFF19FFA3);
  static const Color success400 = Color(0xFF10B271);
  static const Color success500 = Color(0xFF086640);
  static const Color success600 = Color(0xFF001A0F);


  static const Color warning50 = Color(0xFFFFF8E5);
  static const Color warning100 = Color(0xFFFFE9AB);
  static const Color warning200 = Color(0xFFFFDA72);
  static const Color warning300 = Color(0xFFFFCB39);
  static const Color warning400 = Color(0xFFB28D26);
  static const Color warning500 = Color(0xFF665013);
  static const Color warning600 = Color(0xFF191200);


  static const Color mostlywhite = Color(0xFFF48F24);
  static const Color grey50 = Color(0xFFFFFFFF);
  static const Color grey100 = Color(0xFFF3F4F6);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey300 = Color(0xFFD1D5DB);
  static const Color grey400 = Color(0xFF9CA3AF);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey600 = Color(0xFF4B5563);
  static const Color grey700 = Color(0xFF374151);
  static const Color grey800 = Color(0xFF1F2937);
  static const Color grey900 = Color(0xFF111827);


  static const String regular = 'RadioCanadaBig-Regular';
  static const String medium = 'RadioCanadaBig-Medium';
  static const String bold = 'RadioCanadaBig-Bold';
  static const String semiBold = 'RadioCanadaBig-SemiBold';
}
