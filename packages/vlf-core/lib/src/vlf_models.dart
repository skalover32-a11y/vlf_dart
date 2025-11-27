/// Общие модельные сущности для описания конфигурации VLF.

class VlfOutbound {
  final String server;
  final int port;
  final String uuid;
  final String? flow;
  final String? security; // e.g. 'reality'
  final String? fingerprint; // fp
  final String? publicKey; // pbk
  final String? shortId; // sid
  final String? sni;

  const VlfOutbound({
    required this.server,
    required this.port,
    required this.uuid,
    this.flow,
    this.security,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.sni,
  });

  /// Утилита: построить VLESS URL, эквивалентный текущей модели.
  String toVlessUrl() {
    final qp = <String, String>{};
    if (flow != null && flow!.isNotEmpty) qp['flow'] = flow!;
    if (security != null && security!.isNotEmpty) qp['security'] = security!;
    if (fingerprint != null && fingerprint!.isNotEmpty) qp['fp'] = fingerprint!;
    if (publicKey != null && publicKey!.isNotEmpty) qp['pbk'] = publicKey!;
    if (shortId != null && shortId!.isNotEmpty) qp['sid'] = shortId!;
    if (sni != null && sni!.isNotEmpty) qp['sni'] = sni!;
    final query = qp.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final q = query.isEmpty ? '' : '?$query';
    return 'vless://$uuid@$server:$port$q';
  }
}

enum VlfWorkMode { tun, proxy }

class VlfRouteConfig {
  final bool ruMode;
  final List<String> domainExclusions;
  final List<String> appExclusions;

  const VlfRouteConfig({
    required this.ruMode,
    required this.domainExclusions,
    required this.appExclusions,
  });
}

class VlfRuntimeConfig {
  final VlfOutbound outbound;
  final VlfWorkMode mode;
  final VlfRouteConfig routes;

  const VlfRuntimeConfig({
    required this.outbound,
    required this.mode,
    required this.routes,
  });
}
