import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Запрещает прямые [Image.network] / [Image.asset] вне реализации [AdaptiveImage].
class UseAdaptiveImageLint extends DartLintRule {
  const UseAdaptiveImageLint() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'use_adaptive_image',
    problemMessage:
        'Используй AdaptiveImage / AdaptiveImage.fromSource вместо Image.network или Image.asset.',
    correctionMessage: 'См. docs/IMAGE_GUIDELINES.md',
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final String normalizedPath = resolver.path.replaceAll(r'\', '/');

    if (normalizedPath.endsWith('lib/widgets/adaptive_image.dart')) {
      return;
    }
    if (normalizedPath.contains('/packages/city_app_lints/')) {
      return;
    }

    context.registry.addInstanceCreationExpression((
      InstanceCreationExpression node,
    ) {
      final NamedType named = node.constructorName.type;
      if (named.name2.lexeme != 'Image') {
        return;
      }
      final String? ctor = node.constructorName.name?.name;
      if (ctor != 'network' && ctor != 'asset') {
        return;
      }
      reporter.atNode(node, code);
    });
  }
}
