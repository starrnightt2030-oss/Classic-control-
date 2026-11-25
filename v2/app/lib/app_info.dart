/// App identity shown in the intro, «عن التطبيق» and exported sheets.
class AppInfo {
  static const brandEn = 'Control Academy';
  static const brandAr = 'أكاديمية التحكم الكهربائي';
  static const product = 'Classic Control Lab';
  static const version = '2.3.0';
  static const build = 'نسخة تجريبية';

  /// CI build number (`--dart-define=APP_BUILD=N`); 0 in development builds
  static const buildNumber = int.fromEnvironment('APP_BUILD');
  static const developer = 'Mohamed-Eldawly';
  static const organization = 'مركز تدريب شركة ترسانة الإسكندرية';
  static const organizationEn = 'Alexandria Shipyard · Training Center';
  static const orgLogo = 'assets/images/org_logo.webp';
}
