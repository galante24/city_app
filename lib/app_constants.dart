import 'package:flutter/material.dart';

/// Основной цвет интерфейса
const Color kPrimaryBlue = Color(0xFF1976D2);

/// Акцент на тёмном фоне (табы, иконки портала).
const Color kPortalGold = Color(0xFFD4AF37);

/// Единый фон тёмной темы (полноэкранное изображение под контентом).
const String kDarkThemeBackgroundAsset = 'assets/images/themedark.png';

/// Фон светлой темы (подложка под весь UI).
const String kLightThemeBackgroundAsset = 'assets/images/whitetheme.jpg';

/// Фон экранов входа / регистрации (до сессии).
const String kAuthBackgroundAsset = 'assets/images/auth_bg.jpg';

/// Хвойно-зелёный акцент светлой темы (контрастный текст заголовков).
const Color kPineGreen = Color(0xFF1B4D3E);

const Color kPineGreenDark = Color(0xFF0F3429);

/// Неактивные иконки нижнего меню (оливково-серый).
const Color kNavOliveMuted = Color(0xFF7A8B78);

/// Мягкое изумрудное свечение (активная вкладка, чаты).
const Color kEmeraldGlow = Color(0xFF2E8B6E);

/// Для веба: явный fully-transparent ARGB.
const Color kScaffoldFullyTransparent = Color(0x00000000);

/// Фон скролла под «облачными» белыми карточками
const Color kAppScaffoldBg = Color(0xFFF8F9FA);
const double kScreenHorizontalPadding = 16.0;
const Color kAppTextPrimary = Color(0xFF1C1C1E);
const Color kAppTextSecondary = Color(0xFF6C6C70);
const Color kAppCardSurface = Color(0xFFFFFFFF);

/// Суффикс у поля «Квадратура» в формах недвижимости (в БД хранятся только цифры).
const String kListingFloorAreaDisplaySuffix = 'м³';

/// Строка для карточек / шаринга: «123 м³».
String listingFloorAreaWithSuffix(String digitsFromDb) {
  final String t = digitsFromDb.trim();
  if (t.isEmpty) {
    return '';
  }
  return '$t $kListingFloorAreaDisplaySuffix';
}
