import 'dart:convert';
import 'vlf_models.dart';

/// Минимальная заготовка конфигуратора для sing-box (Android ядро, будущая интеграция).
/// Пока реализует GLOBAL режим с одним VLESS outbound.
class SingboxConfigBuilder {
  final VlfRuntimeConfig runtime;
  const SingboxConfigBuilder(this.runtime);

  /// Возвращает Map, пригодный для сериализации в JSON.
  Map<String, dynamic> toMap() {
    final o = runtime.outbound;
    final outbound = {
      'type': 'vless',
      'tag': 'vlf-outbound',
      'server': o.server,
      'server_port': o.port,
      'uuid': o.uuid,
      if (o.flow != null && o.flow!.isNotEmpty) 'flow': o.flow,
      'tls': {
        'enabled': true,
        if (o.sni != null && o.sni!.isNotEmpty) 'server_name': o.sni,
        if (o.security == 'reality' && (o.publicKey?.isNotEmpty ?? false))
          'reality': {
            'public_key': o.publicKey,
            if (o.shortId?.isNotEmpty ?? false) 'short_id': o.shortId,
          },
        if (o.fingerprint?.isNotEmpty ?? false) 'client_fingerprint': o.fingerprint,
      },
    };

    // GLOBAL режим: все запросы идут через единственный outbound.
    return {
      'log': {'level': 'info'},
      'route': {
        'rules': [], // РФ-режим и исключения будут добавлены позже
        'final': 'vlf-outbound',
      },
      'outbounds': [outbound],
      // DNS пока упрощённо отключён или минимален; добавим позже при интеграции.
    };
  }

  String toJson() => jsonEncode(toMap());
}
