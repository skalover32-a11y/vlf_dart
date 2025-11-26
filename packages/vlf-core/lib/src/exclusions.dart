class Exclusions {
  List<String> siteExclusions;
  List<String> appExclusions;

  Exclusions({List<String>? siteExclusions, List<String>? appExclusions})
    : siteExclusions = siteExclusions ?? [],
      appExclusions = appExclusions ?? [];

  void addSite(String domain) {
    if (domain.isEmpty) return;
    siteExclusions.add(domain);
  }

  void editSite(int index, String domain) {
    if (index < 0 || index >= siteExclusions.length) return;
    siteExclusions[index] = domain;
  }

  void removeSite(int index) {
    if (index < 0 || index >= siteExclusions.length) return;
    siteExclusions.removeAt(index);
  }

  void addApp(String procName) {
    if (procName.isEmpty) return;
    appExclusions.add(procName);
  }

  void editApp(int index, String procName) {
    if (index < 0 || index >= appExclusions.length) return;
    appExclusions[index] = procName;
  }

  void removeApp(int index) {
    if (index < 0 || index >= appExclusions.length) return;
    appExclusions.removeAt(index);
  }

  Map<String, dynamic> toJson() => {
    'site_exclusions': siteExclusions,
    'app_exclusions': appExclusions,
  };

  static Exclusions fromJson(Map<String, dynamic> j) => Exclusions(
    siteExclusions: List<String>.from(j['site_exclusions'] ?? []),
    appExclusions: List<String>.from(j['app_exclusions'] ?? []),
  );
}
