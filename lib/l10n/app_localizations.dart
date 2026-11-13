import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Basirati'**
  String get appName;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Basirati AI Settings'**
  String get settingsDescription;

  /// No description provided for @cameraPermission.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required'**
  String get cameraPermission;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission denied'**
  String get cameraPermissionDenied;

  /// No description provided for @microphonePermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required for voice commands'**
  String get microphonePermission;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get cameraUnavailable;

  /// No description provided for @noCameraFound.
  ///
  /// In en, this message translates to:
  /// **'No camera was found'**
  String get noCameraFound;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @openSettingsMenu.
  ///
  /// In en, this message translates to:
  /// **'Open settings menu'**
  String get openSettingsMenu;

  /// No description provided for @openAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open App Settings'**
  String get openAppSettings;

  /// No description provided for @assistanceActive.
  ///
  /// In en, this message translates to:
  /// **'Assistance Active'**
  String get assistanceActive;

  /// No description provided for @obstacleAhead.
  ///
  /// In en, this message translates to:
  /// **'Obstacle ahead'**
  String get obstacleAhead;

  /// No description provided for @voiceAssistance.
  ///
  /// In en, this message translates to:
  /// **'Voice Assistance'**
  String get voiceAssistance;

  /// No description provided for @vibrationAlerts.
  ///
  /// In en, this message translates to:
  /// **'Vibration Alerts'**
  String get vibrationAlerts;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @objectPerson.
  ///
  /// In en, this message translates to:
  /// **'person'**
  String get objectPerson;

  /// No description provided for @objectBicycle.
  ///
  /// In en, this message translates to:
  /// **'bicycle'**
  String get objectBicycle;

  /// No description provided for @objectCar.
  ///
  /// In en, this message translates to:
  /// **'car'**
  String get objectCar;

  /// No description provided for @objectMotorcycle.
  ///
  /// In en, this message translates to:
  /// **'motorcycle'**
  String get objectMotorcycle;

  /// No description provided for @objectBus.
  ///
  /// In en, this message translates to:
  /// **'bus'**
  String get objectBus;

  /// No description provided for @objectTruck.
  ///
  /// In en, this message translates to:
  /// **'truck'**
  String get objectTruck;

  /// No description provided for @objectBench.
  ///
  /// In en, this message translates to:
  /// **'bench'**
  String get objectBench;

  /// No description provided for @objectBackpack.
  ///
  /// In en, this message translates to:
  /// **'backpack'**
  String get objectBackpack;

  /// No description provided for @objectHandbag.
  ///
  /// In en, this message translates to:
  /// **'handbag'**
  String get objectHandbag;

  /// No description provided for @objectSuitcase.
  ///
  /// In en, this message translates to:
  /// **'suitcase'**
  String get objectSuitcase;

  /// No description provided for @objectChair.
  ///
  /// In en, this message translates to:
  /// **'chair'**
  String get objectChair;

  /// No description provided for @objectCouch.
  ///
  /// In en, this message translates to:
  /// **'couch'**
  String get objectCouch;

  /// No description provided for @objectPottedPlant.
  ///
  /// In en, this message translates to:
  /// **'potted plant'**
  String get objectPottedPlant;

  /// No description provided for @objectDiningTable.
  ///
  /// In en, this message translates to:
  /// **'dining table'**
  String get objectDiningTable;

  /// No description provided for @objectBottle.
  ///
  /// In en, this message translates to:
  /// **'bottle'**
  String get objectBottle;

  /// No description provided for @objectCup.
  ///
  /// In en, this message translates to:
  /// **'cup'**
  String get objectCup;

  /// No description provided for @objectToilet.
  ///
  /// In en, this message translates to:
  /// **'toilet'**
  String get objectToilet;

  /// No description provided for @objectTv.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get objectTv;

  /// No description provided for @objectLaptop.
  ///
  /// In en, this message translates to:
  /// **'laptop'**
  String get objectLaptop;

  /// No description provided for @objectMouse.
  ///
  /// In en, this message translates to:
  /// **'mouse'**
  String get objectMouse;

  /// No description provided for @objectKeyboard.
  ///
  /// In en, this message translates to:
  /// **'keyboard'**
  String get objectKeyboard;

  /// No description provided for @objectCellPhone.
  ///
  /// In en, this message translates to:
  /// **'cell phone'**
  String get objectCellPhone;

  /// No description provided for @objectMicrowave.
  ///
  /// In en, this message translates to:
  /// **'microwave'**
  String get objectMicrowave;

  /// No description provided for @objectSink.
  ///
  /// In en, this message translates to:
  /// **'sink'**
  String get objectSink;

  /// No description provided for @objectRefrigerator.
  ///
  /// In en, this message translates to:
  /// **'refrigerator'**
  String get objectRefrigerator;

  /// No description provided for @objectBook.
  ///
  /// In en, this message translates to:
  /// **'book'**
  String get objectBook;

  /// No description provided for @objectClock.
  ///
  /// In en, this message translates to:
  /// **'clock'**
  String get objectClock;

  /// No description provided for @directionLeft.
  ///
  /// In en, this message translates to:
  /// **'on your left'**
  String get directionLeft;

  /// No description provided for @directionRight.
  ///
  /// In en, this message translates to:
  /// **'on your right'**
  String get directionRight;

  /// No description provided for @directionAhead.
  ///
  /// In en, this message translates to:
  /// **'ahead'**
  String get directionAhead;

  /// No description provided for @noObjectsDetected.
  ///
  /// In en, this message translates to:
  /// **'I don\'t see any objects'**
  String get noObjectsDetected;

  /// No description provided for @roomNumberNotReady.
  ///
  /// In en, this message translates to:
  /// **'Room number reading is not ready yet'**
  String get roomNumberNotReady;

  /// No description provided for @detectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Object detection could not start. Please try again.'**
  String get detectionUnavailable;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
