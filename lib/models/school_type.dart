enum SchoolType {
  undergrad,
  graduate;

  String get label {
    switch (this) {
      case SchoolType.undergrad:
        return '南京大学本科生';
      case SchoolType.graduate:
        return '南京大学研究生';
    }
  }

  String get shortLabel {
    switch (this) {
      case SchoolType.undergrad:
        return '本科生';
      case SchoolType.graduate:
        return '研究生';
    }
  }

  String get storageValue {
    switch (this) {
      case SchoolType.undergrad:
        return 'undergrad';
      case SchoolType.graduate:
        return 'graduate';
    }
  }

  String get appShowUrl {
    switch (this) {
      case SchoolType.undergrad:
        return 'https://ehall.nju.edu.cn/appShow?appId=4770397878132218';
      case SchoolType.graduate:
        return 'https://ehall.nju.edu.cn/appShow?appId=4979568947762216';
    }
  }

  bool get supportsFinalExams => this == SchoolType.undergrad;

  static SchoolType fromStorageValue(String? value) {
    if (value == 'graduate') {
      return SchoolType.graduate;
    }
    return SchoolType.undergrad;
  }
}
