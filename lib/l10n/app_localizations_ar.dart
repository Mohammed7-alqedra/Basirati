// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'بصيرتي';

  @override
  String get settings => 'الإعدادات';

  @override
  String get settingsDescription => 'إعدادات بصيرتي AI';

  @override
  String get cameraPermission => 'يلزم منح إذن استخدام الكاميرا';

  @override
  String get cameraPermissionDenied => 'تم رفض إذن الكاميرا';

  @override
  String get microphonePermission => 'يلزم منح إذن استخدام الميكروفون للأوامر الصوتية';

  @override
  String get cameraUnavailable => 'الكاميرا غير متاحة';

  @override
  String get noCameraFound => 'لم يتم العثور على كاميرا';

  @override
  String get tryAgain => 'حاول مرة أخرى';

  @override
  String get openSettingsMenu => 'فتح قائمة الإعدادات';

  @override
  String get openAppSettings => 'فتح إعدادات التطبيق';

  @override
  String get assistanceActive => 'المساعدة مفعّلة';

  @override
  String get obstacleAhead => 'يوجد عائق أمامك';

  @override
  String get voiceAssistance => 'المساعدة الصوتية';

  @override
  String get vibrationAlerts => 'تنبيهات الاهتزاز';

  @override
  String get language => 'اللغةx';

  @override
  String get english => 'الإنجليزية';

  @override
  String get arabic => 'العربية';
}
