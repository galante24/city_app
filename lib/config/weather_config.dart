/// OpenWeatherMap: https://openweathermap.org/api (бесплатный tier).
///
/// Ключ **не** хранить в исходниках: задайте в `api_keys.json` (см. `api_keys.example.json`) и
/// запускайте с `flutter run --dart-define-from-file=api_keys.json` (уже в `.vscode/launch.json`).
/// Либо: `flutter run --dart-define=OPENWEATHER_API_KEY=...`
const String kOpenWeatherApiKey = String.fromEnvironment(
  'OPENWEATHER_API_KEY',
  defaultValue: '',
);

/// Лесосибирск, центр (~58.23°N, 92.50°E) — One Call / 2.5 `lat` & `lon`
const double kWeatherLat = 58.2333;
const double kWeatherLon = 92.5000;

const String kWeatherCityNameRu = 'Лесосибирск';
