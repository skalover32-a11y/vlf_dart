import 'dart:io';
import 'package:vlf_dart/subscription_decoder.dart';

Future<void> main(List<String> args) async {
  final url = 'https://troynichek-live.ru/subvlftun/f761a39dd58742ba91f20462398edc25';
  print('Testing parser for: $url');
  try {
    final vless = await extractVlessFromAny(url);
    print('Parser result:\n$vless');
  } catch (e, st) {
    print('Parser error: $e');
    print(st);
  }
}
