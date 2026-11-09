// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Basirati';

  @override
  String get settings => 'Settings';

  @override
  String get settingsDescription => 'Basirati AI Settings';

  @override
  String get cameraPermission => 'Camera permission is required';

  @override
  String get cameraPermissionDenied => 'Camera permission denied';

  @override
  String get microphonePermission => 'Microphone permission is required for voice commands';

  @override
  String get cameraUnavailable => 'Camera unavailable';

  @override
  String get noCameraFound => 'No camera was found';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get openSettingsMenu => 'Open settings menu';

  @override
  String get openAppSettings => 'Open App Settings';

  @override
  String get assistanceActive => 'Assistance Active';

  @override
  String get obstacleAhead => 'Obstacle ahead';

  @override
  String get voiceAssistance => 'Voice Assistance';

  @override
  String get vibrationAlerts => 'Vibration Alerts';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get arabic => 'Arabic';
}
