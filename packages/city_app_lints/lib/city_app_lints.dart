import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/use_adaptive_image_lint.dart';

PluginBase createPlugin() => _CityAppLints();

class _CityAppLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => <LintRule>[
    const UseAdaptiveImageLint(),
  ];
}
