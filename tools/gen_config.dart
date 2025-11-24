import 'dart:io';
import 'dart:convert';
import 'package:vlf_dart/singbox_config_clean.dart' as sc;

Future<void> main() async {
  final vless =
      'vless://cc0bf5d6-f57d-4969-ae07-5954b5aeac64@troynichek-live.ru:10745';
  final cfg = await sc.buildSingboxConfig(
    vless,
    false,
    <String>[],
    <String>[],
    resolveToIp: true,
  );
  final out = File('config_test.json');
  out.writeAsStringSync(JsonEncoder.withIndent('  ').convert(cfg), flush: true);
  print('Wrote config_test.json');
  print('dns.servers:');
  print(JsonEncoder.withIndent('  ').convert(cfg['dns']));
}
