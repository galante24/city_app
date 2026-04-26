/// OpenWeatherMap: https://openweathermap.org/api (бесплатный tier).
///
/// Ключ при сборке (любой вариант):
/// - `flutter run --dart-define=OPENWEATHER_API_KEY=ваш_ключ`
/// - или скопируйте `api_keys.example.json` → `api_keys.json` в корне репо и:
///   `flutter run --dart-define-from-file=api_keys.json`
/// (`api_keys.json` в .gitignore — не коммитьте.)
/// Для смены ключа: `--dart-define=OPENWEATHER_API_KEY=...` (переопределяет значение ниже).
const String kOpenWeatherApiKey = String.fromEnvironment(
  'OPENWEATHER_API_KEY',
  // Вшито для работы погоды в релизе без отдельной сборки; при публикации кода смените в OWM и задайте define.
  defaultValue: '9fd13b370125fbaf4ead456fdb6c46da',
);

/// Лесосибирск (для 2.5 /weather и /forecast — `lat` и `lon`)
const double kWeatherLat = 58.23;
const double kWeatherLon = 92.48;

const String kWeatherCityNameRu = 'Лесосибирск';
