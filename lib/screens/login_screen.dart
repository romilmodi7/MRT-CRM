import 'package:flutter/material.dart';
import '../core/push.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../pc/room_chat_screen.dart';
import 'threads_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _u = TextEditingController();
  final _p = TextEditingController();
  final _code = TextEditingController();
  bool _needCode = false, _busy = false, _show = false;
  String _err = '';
  late final AnimationController _a = AnimationController(vsync: this, duration: Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!Session.permsAsked && mounted) await _askPerms();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    _u.dispose();
    _p.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _askPerms() async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: C.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Allow access'),
        content: Text('So chat works fully, the app can ask for: notifications, photos & videos, camera, microphone and location.\n\nNothing is shared or backed up unless you switch it on yourself.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Later')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Allow', style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (go == true) {
      await Perms.askAll();
    } else {
      await Session.setPermsAsked();
    }
  }

  Future<void> _login() async {
    final u = _u.text.trim(), p = _p.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _err = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    final r = await Api.login(u, p, _needCode ? _code.text.trim() : null);
    if (!mounted) return;
    if (r.ok && r.data is Map && (r.data as Map)['token'] != null) {
      final d = r.data as Map;
      final me = d['me'];
      final name = me is Map ? (me['name'] ?? me['username'] ?? u).toString() : u;
      await Session.save(d['token'].toString(), name);
      await Session.clearRoom();
      Push.sync();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ThreadsScreen()));
      return;
    }
    if (r.needCode) {
      setState(() {
        _needCode = true;
        _busy = false;
        _err = r.msg;
      });
      return;
    }
    // not an employee? maybe a private-room login (username + password of one chat)
    if (r.code == 401 || r.code == 422) {
      final rr = await PcApi.roomLogin(u, p);
      if (!mounted) return;
      if (rr.ok && rr.data is Map) {
        final d = Map<String, dynamic>.from(rr.data as Map);
        final tok = d.remove('token').toString();
        await Session.saveRoom(tok, d);
        PcApi.useGuest(tok);
        PcApi.roomId = ((d['room'] as Map)['id'] as num).toInt();
        Push.sync();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => RoomChatScreen(info: d)));
        return;
      }
      setState(() {
        _busy = false;
        _err = 'Wrong username or password.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _err = r.msg;
    });
  }

  Widget _stag(double from, Widget child) => AnimatedBuilder(
        animation: _a,
        builder: (_, c) {
          final t = Curves.easeOutCubic.transform(((_a.value - from) / (1 - from)).clamp(0.0, 1.0));
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 28 * (1 - t)), child: c));
        },
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _stag(0.0, Container(
                    width: 92, height: 92,
                    decoration: BoxDecoration(
                      gradient: C.grad,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: Color(0x667C6CFF), blurRadius: 36, offset: Offset(0, 14))],
                    ),
                    child: Icon(Icons.forum_rounded, color: Colors.white, size: 46),
                  )),
                  SizedBox(height: 22),
                  _stag(0.15, Text('Welcome back', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5))),
                  SizedBox(height: 6),
                  _stag(0.22, Text('Sign in to continue', style: TextStyle(color: C.muted, fontSize: 15))),
                  SizedBox(height: 30),
                  _stag(0.32, TextField(
                    controller: _u,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(hintText: 'Username', prefixIcon: Icon(Icons.person_outline_rounded, color: C.hint)),
                  )),
                  SizedBox(height: 14),
                  _stag(0.4, TextField(
                    controller: _p,
                    obscureText: !_show,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: _needCode ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) => _needCode ? null : _login(),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: C.hint),
                      suffixIcon: IconButton(onPressed: () => setState(() => _show = !_show), icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: C.hint)),
                    ),
                  )),
                  AnimatedSize(
                    duration: Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    child: _needCode
                        ? Padding(
                            padding: EdgeInsets.only(top: 14),
                            child: TextField(
                              controller: _code,
                              keyboardType: TextInputType.number,
                              maxLength: 8,
                              onSubmitted: (_) => _login(),
                              decoration: InputDecoration(hintText: '6-digit authenticator code', counterText: '', prefixIcon: Icon(Icons.shield_outlined, color: C.hint)),
                            ),
                          )
                        : SizedBox(width: double.infinity),
                  ),
                  AnimatedSize(
                    duration: Duration(milliseconds: 200),
                    child: _err.isEmpty
                        ? SizedBox(width: double.infinity)
                        : Padding(
                            padding: EdgeInsets.only(top: 14),
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Color(0x22FF5D6C), borderRadius: BorderRadius.circular(14)),
                              child: Text(_err, style: TextStyle(color: Color(0xFFFFB3BB))),
                            ),
                          ),
                  ),
                  SizedBox(height: 22),
                  _stag(0.5, GradientButton(label: _needCode ? 'Verify & sign in' : 'Sign in', busy: _busy, onTap: _login)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
