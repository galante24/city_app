/// Переключение вкладок главного экрана из маршрутов, открытых поверх [MainScaffold]
/// (например «Вакансии»), где нет доступа к состоянию табов.
class MainShellNavigation {
  MainShellNavigation._();

  static void Function(int index)? _onSelect;

  static void register(void Function(int index) select) {
    _onSelect = select;
  }

  static void unregister() {
    _onSelect = null;
  }

  static void goToTab(int index) {
    _onSelect?.call(index);
  }
}
