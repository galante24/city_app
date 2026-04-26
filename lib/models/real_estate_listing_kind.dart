import 'package:flutter/material.dart';

/// Категории объявлений (кроме «Гараж» — отдельная таблица [garage_listings]).
enum RealEstateListingKind {
  dacha,
  house,
  apartment,
  land,
  commercial;

  static RealEstateListingKind? tryParseId(String id) {
    return switch (id) {
      'dacha' => RealEstateListingKind.dacha,
      'house' => RealEstateListingKind.house,
      'apartment' => RealEstateListingKind.apartment,
      'land' => RealEstateListingKind.land,
      'commercial' => RealEstateListingKind.commercial,
      _ => null,
    };
  }

  /// Имя таблицы в Supabase.
  String get tableName => switch (this) {
        RealEstateListingKind.dacha => 'dacha_listings',
        RealEstateListingKind.house => 'house_listings',
        RealEstateListingKind.apartment => 'apartment_listings',
        RealEstateListingKind.land => 'land_listings',
        RealEstateListingKind.commercial => 'commercial_listings',
      };

  /// Первая часть пути в bucket city_media (политики storage).
  String get storageFolder => switch (this) {
        RealEstateListingKind.dacha => 'dachas',
        RealEstateListingKind.house => 'houses',
        RealEstateListingKind.apartment => 'apartments',
        RealEstateListingKind.land => 'land_plots',
        RealEstateListingKind.commercial => 'commercial_listings',
      };

  String get listTitle => switch (this) {
        RealEstateListingKind.dacha => 'Дача',
        RealEstateListingKind.house => 'Дом',
        RealEstateListingKind.apartment => 'Квартира',
        RealEstateListingKind.land => 'Участок',
        RealEstateListingKind.commercial => 'Коммерческая',
      };

  String get detailAppBarTitle => listTitle;

  String get shareCategoryLabel => listTitle;

  String get addressFieldLabel => switch (this) {
        RealEstateListingKind.dacha => 'Адрес дачи',
        RealEstateListingKind.house => 'Адрес дома',
        RealEstateListingKind.apartment => 'Адрес квартиры',
        RealEstateListingKind.land => 'Адрес участка',
        RealEstateListingKind.commercial => 'Адрес объекта',
      };

  String get postCardSubtitle => switch (this) {
        RealEstateListingKind.dacha =>
          'Разместите объявление о даче: продажа или аренда',
        RealEstateListingKind.house =>
          'Разместите объявление о доме: продажа или аренда',
        RealEstateListingKind.apartment =>
          'Разместите объявление о квартире: продажа или аренда',
        RealEstateListingKind.land =>
          'Разместите объявление об участке: продажа или аренда',
        RealEstateListingKind.commercial =>
          'Разместите объявление о коммерческой недвижимости',
      };

  IconData get headerIcon => switch (this) {
        RealEstateListingKind.dacha => Icons.holiday_village_rounded,
        RealEstateListingKind.house => Icons.house_rounded,
        RealEstateListingKind.apartment => Icons.apartment_rounded,
        RealEstateListingKind.land => Icons.landscape_rounded,
        RealEstateListingKind.commercial => Icons.business_rounded,
      };

  Color get accentColor => switch (this) {
        RealEstateListingKind.dacha => const Color(0xFFC2185B),
        RealEstateListingKind.house => const Color(0xFF2E7D32),
        RealEstateListingKind.apartment => const Color(0xFFE65100),
        RealEstateListingKind.land => const Color(0xFFF9A825),
        RealEstateListingKind.commercial => const Color(0xFF5E35B1),
      };
}
