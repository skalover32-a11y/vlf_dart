class Profile {
  String name;
  String url;
  String ptype;
  String address;
  String remark;

  Profile(
    this.name,
    this.url, {
    this.ptype = 'VLESS',
    this.address = '',
    this.remark = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'ptype': ptype,
    'address': address,
    'remark': remark,
  };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
    j['name'] ?? 'Без имени',
    j['url'] ?? '',
    ptype: j['ptype'] ?? 'VLESS',
    address: j['address'] ?? '',
    remark: j['remark'] ?? '',
  );
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
