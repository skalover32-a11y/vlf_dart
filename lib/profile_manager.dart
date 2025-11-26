class Profile {
  String name;
  String url;
  String ptype;
  String address;
  String remark;
  String source;
  DateTime? lastUpdatedAt;

  Profile(
    this.name,
    this.url, {
    this.ptype = 'VLESS',
    this.address = '',
    this.remark = '',
    this.source = '',
    this.lastUpdatedAt,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'ptype': ptype,
    'address': address,
    'remark': remark,
    'source': source,
    'last_updated_at': lastUpdatedAt?.toIso8601String(),
  };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
    j['name'] ?? 'Без имени',
    j['url'] ?? '',
    ptype: j['ptype'] ?? 'VLESS',
    address: j['address'] ?? '',
    remark: j['remark'] ?? '',
    source: j['source'] ?? '',
    lastUpdatedAt: _parseDate(j['last_updated_at']),
  );

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class ProfileManager {
  List<Profile> profiles = [];

  void add(Profile p) => profiles.add(p);
  void removeAt(int idx) {
    if (idx < 0 || idx >= profiles.length) return;
    profiles.removeAt(idx);
  }

  void editAt(int idx, Profile p) {
    if (idx < 0 || idx >= profiles.length) return;
    profiles[idx] = p;
  }

  Map<String, dynamic> toJson() => {
    'profiles': profiles.map((p) => p.toJson()).toList(),
  };

  void loadFromJsonList(List<dynamic> list) {
    profiles = list
        .map((e) => Profile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
