import 'clash_config.dart' as legacy;
import 'vlf_models.dart';

/// Совместимый билдер для Clash Meta (mihomo), принимающий VlfRuntimeConfig
/// и генерирующий YAML, полностью эквивалентный текущей реализации.
class ClashConfigBuilder {
  final VlfRuntimeConfig runtime;
  const ClashConfigBuilder(this.runtime);

  Future<String> buildYaml() async {
    // Переводим VlfOutbound в vless URL, как использует текущая логика.
    final vlessUrl = runtime.outbound.toVlessUrl();
    final ru = runtime.routes.ruMode;
    final siteExcl = runtime.routes.domainExclusions;
    final appExcl = runtime.routes.appExclusions;

    if (runtime.mode == VlfWorkMode.proxy) {
      return legacy.buildClashConfigProxy(
        vlessUrl,
        ru,
        siteExcl,
        appExcl,
      );
    } else {
      return legacy.buildClashConfig(
        vlessUrl,
        ru,
        siteExcl,
        appExcl,
      );
    }
  }
}
