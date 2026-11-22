import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:safenetic_app/firebase_option.dart';
import 'package:safenetic_app/providers/theme_provider.dart';
import 'package:safenetic_app/providers/settings_provider.dart';
import 'package:safenetic_app/router/app_router.dart';
import 'package:safenetic_app/theme/app_theme.dart';
import 'package:safenetic_app/services/background_service.dart';
import 'package:safenetic_app/services/guardian_fcm_service.dart';
import 'package:safenetic_app/screens/sos_incoming_alert_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // step 1: check if firebase is already running
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // step 2: if it says duplicate error, just ignore it.
    if (!e.toString().contains('duplicate') &&
        !e.toString().contains('already exists')) {
      runApp(const ErrorApp(
        errorMessage: 'Unable to start SafeNetic. Please try again later.',
      ));
      return;
    }
  }

  // step 3: setup the background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // step 4: setting up local notifications
  const AndroidInitializationSettings androidInitSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInitSettings);
  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('Notification tapped: ${response.payload}');
      if (response.payload != null && response.payload!.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const SosIncomingAlertScreen(
              userName: 'Protected User',
              alertType: 'manual',
            ),
          ),
        );
      }
    },
  );

  // step 5: start guardian fcm
  await GuardianFcmService.instance.initialize(flutterLocalNotificationsPlugin);

  // step 6: check if user did the onboarding yet
  await initOnboardingState();

  // step 7: start the background service to keep it running
  await BackgroundServiceManager().initialize();

  // step 8: get the device token for firestore
  await GuardianFcmService.instance.registerDeviceToken();

  // step 9: finally run my app
  runApp(const SafeNeticApp());
}

class SafeNeticApp extends StatefulWidget {
  const SafeNeticApp({super.key});

  @override
  State<SafeNeticApp> createState() => _SafeNeticAppState();
}

class _SafeNeticAppState extends State<SafeNeticApp>
    with WidgetsBindingObserver {
  DateTime? _lastPausedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      FirebaseAuth.instance.signOut();
    } else if (state == AppLifecycleState.paused) {
      _lastPausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_lastPausedTime != null) {
        final diff = DateTime.now().difference(_lastPausedTime!);
        if (diff.inMinutes >= 15) {
          FirebaseAuth.instance.signOut();
        }
        _lastPausedTime = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp.router(
            title: 'SafeNetic',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            routerConfig: appRouter,
            scaffoldMessengerKey: scaffoldMessengerKey,
          );
        },
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String errorMessage;

  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 20),
                const Text(
                  "Firebase Init Failed",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
