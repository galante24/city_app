import 'package:flutter/material.dart';

/// Основной цвет интерфейса
const Color kPrimaryBlue = Color(0xFF1976D2);

/// Акцент главного портала (активные табы, иконки на тёмном фоне).
const Color kPortalGold = Color(0xFFD4AF37);

/// Фоны главного портала в тёмной теме (`ShaderMask` у [шапка] — в виджете фона).
const String kPortalAssetBgBottom = 'assets/images/фон.png';
const String kPortalAssetBgHeader = 'assets/images/шапка.png';

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
