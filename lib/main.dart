import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api.dart';
import 'core/platform.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'pc/room_chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/threads_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never let one bad frame or async error close the app.
  FlutterError.onError = (d) => FlutterError.presentError(d);
  PlatformDispatcher.instance.onError = (e, s) => true; // an async error must never close the app
  ErrorWidget.builder = (d) => const SizedBox.shrink(); // no red error screen for a user
  await runZonedGuarded(() async {
    await Session.init();
    ThemeCtl.load();
    ThemeCtl.apply(WidgetsBinding.instance.platformDispatcher.platformBrightness);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarColor: Color(0xFF0A1030)));
    unawaited(Push.init().then((_) => Push.sync()));   // phone notifications (does nothing until the Firebase values are filled in)
    runApp(EmployeeChatApp());
  }, (e, s) {});
}

class EmployeeChatApp extends StatefulWidget {
  const EmployeeChatApp({super.key});
  @override
  State<EmployeeChatApp> createState() => _EmployeeChatAppState();
}

class _EmployeeChatAppState extends State<EmployeeChatApp> with WidgetsBindingObserver {
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
  void didChangePlatformBrightness() {
    if (ThemeCtl.mode == ThemeMode.system) ThemeCtl.apply(WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeCtl.tick,
      builder: (_, __, ___) => MaterialApp(
        title: 'MRT CRM',
        navigatorKey: Push.navKey,
        scaffoldMessengerKey: Push.messengerKey,
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        home: const _Boot(),
      ),
    );
  }
}

/// Decides the first screen: private room user -> their room; employee -> chats; else login.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final started = DateTime.now();
    Widget next = const LoginScreen();
    try {
      if (!Session.permsAsked) await Perms.askAll();
    } catch (_) {}
    try {
      final rt = Session.roomToken;
      final info = Session.roomInfo;
      if (rt != null && info != null) {
        PcApi.useGuest(rt);
        PcApi.roomId = (((info['room'] as Map?)?['id']) as num?)?.toInt() ?? 0;
        final r = await PcApi.get('me').timeout(Duration(seconds: 8));
        if (r.code == 401 || r.code == 403) {
          await Session.clearRoom();
          PcApi.forget();
        } else {
          next = RoomChatScreen(info: info);
        }
      } else if (Session.token != null) {
        next = const ThreadsScreen();
      }
    } catch (_) {
      // offline / slow server: still open the app (the screens retry by themselves)
      final info = Session.roomInfo;
      if (Session.roomToken != null && info != null) {
        next = RoomChatScreen(info: info);
      } else if (Session.token != null) {
        next = const ThreadsScreen();
      }
    }
    final left = 1800 - DateTime.now().difference(started).inMilliseconds;
    if (left > 0) await Future.delayed(Duration(milliseconds: left));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => next,
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      transitionDuration: Duration(milliseconds: 350),
    ));
    Push.sync();
    Future.delayed(Duration(milliseconds: 700), Push.openPending);
  }

  @override
  Widget build(BuildContext context) => _Splash();
}

/// Splash screen: always the same deep-blue premium look as the Android launch screen, so there is never a white flash.
class _Splash extends StatefulWidget {
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 1600))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _glow(Color c, double size, {double? top, double? left, double? right, double? bottom}) => Positioned(
        top: top, left: left, right: right, bottom: bottom,
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withAlpha(0)]))),
      );

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(parent: _c, curve: Interval(0, .6, curve: Curves.elasticOut));
    final fade = CurvedAnimation(parent: _c, curve: Interval(.35, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: Color(0xFF0A1030),
      body: Stack(children: [
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF070A1C), Color(0xFF0A1030), Color(0xFF0B1B3A)], begin: Alignment.topCenter, end: Alignment.bottomCenter)))),
        _glow(Color(0x552563EB), 460, top: -170, left: -150),
        _glow(Color(0x4422D3EE), 480, bottom: -190, right: -170),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(
              scale: pop,
              child: Container(
                width: 120,
                height: 120,
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(34), boxShadow: [BoxShadow(color: Color(0x662563EB), blurRadius: 40, offset: Offset(0, 16))]),
                child: Image.asset('assets/logo_icon.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.forum_rounded, color: Color(0xFF2563EB), size: 56)),
              ),
            ),
            SizedBox(height: 28),
            FadeTransition(
              opacity: fade,
              child: Column(children: [
                Text('MRT CRM', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white, decoration: TextDecoration.none)),
                SizedBox(height: 6),
                Text('MINDRIPPLE TECHNOLOGIES', style: TextStyle(fontSize: 12, letterSpacing: 2.6, color: Color(0xFF9AA1C9), decoration: TextDecoration.none)),
                SizedBox(height: 36),
                SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF22D3EE))),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
