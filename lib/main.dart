
// JET VPN TV — پروژه کاملاً جدا از اپ موبایل
// فقط Android TV / Google TV | تونل کامل | اتصال هوشمند | ریموت
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kAppVersion = 'tv-1.0.0';
const String kApiBase = 'https://majid6064.ir/api.php';
const String kLogoUrl = 'https://majid6064.ir/logo.png';
const String kPingUrl = 'https://www.gstatic.com/generate_204';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JetVpnTvApp());
}

class JetVpnTvApp extends StatelessWidget {
  const JetVpnTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JET VPN TV',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE),
          secondary: Color(0xFF2DD4BF),
          surface: Color(0xFF151C2E),
        ),
        fontFamily: 'Tahoma',
        useMaterial3: true,
      ),
      home: const TvRoot(),
    );
  }
}

class TvServer {
  final String name;
  final String host;
  final int port;
  final String config;
  int ping; // >0 ok, -1 unknown, -2 fail

  TvServer({
    required this.name,
    required this.host,
    required this.port,
    required this.config,
    this.ping = -1,
  });

  factory TvServer.fromJson(Map<String, dynamic> j) => TvServer(
        name: '${j['name'] ?? 'سرور'}',
        host: '${j['host'] ?? ''}',
        port: int.tryParse('${j['port']}') ?? 443,
        config: '${j['config'] ?? ''}',
      );
}

enum TvPhase {
  idle,
  finding,
  connecting,
  connected,
  recovering,
}

class TvRoot extends StatefulWidget {
  const TvRoot({super.key});
  @override
  State<TvRoot> createState() => _TvRootState();
}

class _TvRootState extends State<TvRoot> {
  late final V2ray _v2ray = V2ray(onStatusChanged: _onStatus);

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _loginBtnFocus = FocusNode();
  final _connectFocus = FocusNode();
  final _logoutFocus = FocusNode();

  bool _booting = true;
  bool _loggedIn = false;
  bool _obscure = true;
  bool _busyLogin = false;
  String? _loginError;

  String? _user;
  String? _pass;
  List<TvServer> _servers = [];
  int _selected = 0;

  TvPhase _phase = TvPhase.idle;
  String _statusLine = 'آماده اتصال';
  int _activePing = -1;
  bool _userWantsOn = false;
  bool _verified = false;
  String? _coreState;
  int _recoverGen = 0;
  Timer? _recoverTimer;

  bool get _isOn {
    final st = (_coreState ?? '').toUpperCase();
    return _verified && st == 'CONNECTED';
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _v2ray.initialize(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
    } catch (e) {
      debugPrint('v2ray init: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final u = prefs.getString('tv_user');
    final p = prefs.getString('tv_pass');
    if (u != null && u.isNotEmpty && p != null && p.isNotEmpty) {
      _userCtrl.text = u;
      _passCtrl.text = p;
      final ok = await _login(u, p, silent: true);
      if (ok && mounted) {
        setState(() {
          _loggedIn = true;
          _booting = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _booting = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _userFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _recoverTimer?.cancel();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _loginBtnFocus.dispose();
    _connectFocus.dispose();
    _logoutFocus.dispose();
    super.dispose();
  }

  void _onStatus(V2RayStatus status) {
    if (!mounted) return;
    final prev = (_coreState ?? '').toUpperCase();
    _coreState = status.state;
    final st = (status.state ?? '').toUpperCase();

    if (st.contains('DISCONNECT') || st == 'IDLE' || st == 'STOPPED') {
      setState(() {
        _verified = false;
        _activePing = -1;
        if (_phase == TvPhase.connected || _phase == TvPhase.connecting) {
          _phase = _userWantsOn ? TvPhase.recovering : TvPhase.idle;
          _statusLine = _userWantsOn ? 'در حال بازیابی اتصال…' : 'قطع شد';
        }
      });
      if (_userWantsOn) _scheduleRecover('core_disconnect');
      return;
    }

    if (st == 'CONNECTED' && prev != 'CONNECTED') {
      _verifyTunnel();
    }
  }

  Future<void> _verifyTunnel() async {
    // تأیید سبک: تأخیر سرور متصل از هسته
    try {
      final d = await _v2ray
          .getConnectedServerDelay(url: kPingUrl)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (d >= 0 && d < 15000) {
        setState(() {
          _verified = true;
          _activePing = d;
          _phase = TvPhase.connected;
          _statusLine = 'متصل هستید';
        });
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    if (_userWantsOn) {
      setState(() {
        _verified = false;
        _phase = TvPhase.recovering;
        _statusLine = 'اتصال تأیید نشد — تلاش مجدد…';
      });
      _scheduleRecover('verify_fail');
    }
  }

  void _scheduleRecover(String reason) {
    _recoverTimer?.cancel();
    final gen = ++_recoverGen;
    _recoverTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || gen != _recoverGen || !_userWantsOn) return;
      await _smartConnect(isRecovery: true);
    });
    debugPrint('tv recover scheduled: $reason');
  }

  Future<bool> _login(String username, String password, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busyLogin = true;
        _loginError = null;
      });
    }
    try {
      final uri = Uri.parse(
        '$kApiBase?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        if (!silent) setState(() => _loginError = 'خطا در ارتباط با سرور');
        return false;
      }
      final data = json.decode(res.body);
      if (data is! Map || data['ok'] != true) {
        if (!silent) {
          setState(() => _loginError = '${data['msg'] ?? 'نام کاربری یا رمز اشتباه است'}');
        }
        return false;
      }
      final raw = (data['servers'] as List?) ?? [];
      final list = raw
          .whereType<Map>()
          .map((e) => TvServer.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.config.trim().isNotEmpty)
          .toList();
      if (list.isEmpty) {
        if (!silent) setState(() => _loginError = 'سروری برای این اشتراک یافت نشد');
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tv_user', username);
      await prefs.setString('tv_pass', password);
      if (!mounted) return false;
      setState(() {
        _user = username;
        _pass = password;
        _servers = list;
        _selected = 0;
        _loginError = null;
      });
      return true;
    } catch (e) {
      debugPrint('login: $e');
      if (!silent) setState(() => _loginError = 'خطا در اتصال به سرور');
      return false;
    } finally {
      if (mounted && !silent) setState(() => _busyLogin = false);
    }
  }

  Future<void> _doLogin() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text.trim();
    if (u.isEmpty || p.isEmpty) {
      setState(() => _loginError = 'نام کاربری و رمز را وارد کنید');
      return;
    }
    final ok = await _login(u, p);
    if (ok && mounted) {
      setState(() => _loggedIn = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connectFocus.requestFocus();
      });
    }
  }

  Future<void> _logout() async {
    _userWantsOn = false;
    _recoverTimer?.cancel();
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tv_user');
    await prefs.remove('tv_pass');
    if (!mounted) return;
    setState(() {
      _loggedIn = false;
      _servers = [];
      _user = null;
      _pass = null;
      _phase = TvPhase.idle;
      _verified = false;
      _statusLine = 'آماده اتصال';
      _loginError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _userFocus.requestFocus();
    });
  }

  String _prepareConfig(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    if (s.startsWith('{')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          return jsonEncode(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
      return s;
    }
    if (s.startsWith('vless://') ||
        s.startsWith('vmess://') ||
        s.startsWith('trojan://') ||
        s.startsWith('ss://')) {
      try {
        final parsed = V2ray.parseFromURL(s);
        return parsed.getFullConfiguration();
      } catch (_) {
        return s;
      }
    }
    return s;
  }

  Future<int> _realPing(TvServer s) async {
    try {
      final cfg = _prepareConfig(s.config);
      if (cfg.isEmpty) return -2;
      final d = await _v2ray
          .getServerDelay(config: cfg, url: kPingUrl)
          .timeout(const Duration(milliseconds: 4500));
      if (d < 0 || d > 12000) return -2;
      return d;
    } catch (_) {
      return -2;
    }
  }

  Future<void> _mapConcurrent(
    List<TvServer> items,
    int concurrency,
    Future<void> Function(TvServer) fn,
  ) async {
    if (items.isEmpty) return;
    var i = 0;
    Future<void> worker() async {
      while (true) {
        final idx = i++;
        if (idx >= items.length) break;
        await fn(items[idx]);
      }
    }

    final n = concurrency.clamp(1, items.length);
    await Future.wait(List.generate(n, (_) => worker()));
  }

  Future<void> _pingAll() async {
    await _mapConcurrent(_servers, 6, (s) async {
      final p = await _realPing(s);
      s.ping = p;
    });
    _servers.sort((a, b) {
      // پایداری: پینگ خیلی پایین مشکوک را عقب‌تر
      int score(TvServer s) {
        if (s.ping <= 0) return 999999;
        if (s.ping < 30) return 5000 + s.ping;
        return s.ping;
      }

      return score(a).compareTo(score(b));
    });
    if (mounted) setState(() {});
  }

  Future<bool> _startServer(TvServer s) async {
    final cfg = _prepareConfig(s.config);
    if (cfg.isEmpty) return false;
    final okPerm = await _v2ray.requestPermission();
    if (!okPerm) {
      if (mounted) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine = 'مجوز VPN تأیید نشد — با ریموت OK را بزنید';
        });
      }
      return false;
    }
    // تونل کامل دستگاه — بدون blockedApps
    await _v2ray.startV2Ray(
      remark: s.name,
      config: cfg,
      blockedApps: null,
      proxyOnly: false,
      notificationDisconnectButtonName: 'قطع',
    );
    return true;
  }

  Future<void> _smartConnect({bool isRecovery = false}) async {
    if (_servers.isEmpty) {
      if (_user != null && _pass != null) {
        setState(() {
          _phase = TvPhase.finding;
          _statusLine = 'بروزرسانی فهرست سرورها…';
        });
        final ok = await _login(_user!, _pass!, silent: true);
        if (!ok || _servers.isEmpty) {
          setState(() {
            _phase = TvPhase.idle;
            _statusLine = 'سروری در دسترس نیست';
            _userWantsOn = false;
          });
          return;
        }
      } else {
        return;
      }
    }

    setState(() {
      _phase = isRecovery ? TvPhase.recovering : TvPhase.finding;
      _statusLine = isRecovery
          ? 'در حال بازیابی اتصال…'
          : 'در حال یافتن بهترین سرور…';
      _verified = false;
    });

    try {
      await _v2ray.stopV2Ray();
    } catch (_) {}

    await _pingAll();
    final alive = _servers.where((s) => s.ping > 0).toList();
    final candidates = alive.isNotEmpty ? alive : List<TvServer>.from(_servers);

    if (candidates.isEmpty) {
      setState(() {
        _phase = TvPhase.idle;
        _statusLine = 'سرور زنده‌ای پیدا نشد';
        _userWantsOn = false;
      });
      return;
    }

    // حداکثر چند سرور اول را امتحان کن
    final tryList = candidates.take(5).toList();
    for (var i = 0; i < tryList.length; i++) {
      if (!_userWantsOn || !mounted) return;
      final s = tryList[i];
      setState(() {
        _selected = _servers.indexOf(s).clamp(0, _servers.length - 1);
        _phase = TvPhase.connecting;
        _statusLine = 'در حال اتصال… (${i + 1}/${tryList.length})';
      });
      try {
        final started = await _startServer(s);
        if (!started) continue;
        // منتظر verify از onStatus / timeout
        for (var t = 0; t < 20; t++) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (!mounted || !_userWantsOn) return;
          if (_isOn) return;
        }
        try {
          await _v2ray.stopV2Ray();
        } catch (_) {}
      } catch (e) {
        debugPrint('try server fail: $e');
        try {
          await _v2ray.stopV2Ray();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    if (_userWantsOn && !_isOn) {
      setState(() {
        _phase = TvPhase.idle;
        _statusLine = 'اتصال برقرار نشد — دوباره تلاش کنید';
        _userWantsOn = false;
      });
    }
  }

  Future<void> _toggle() async {
    if (_phase == TvPhase.finding ||
        _phase == TvPhase.connecting ||
        _phase == TvPhase.recovering) {
      return;
    }
    if (_isOn || _phase == TvPhase.connected) {
      _userWantsOn = false;
      _recoverTimer?.cancel();
      try {
        await _v2ray.stopV2Ray();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _phase = TvPhase.idle;
          _verified = false;
          _activePing = -1;
          _statusLine = 'قطع شد';
        });
      }
      return;
    }
    _userWantsOn = true;
    await _smartConnect();
  }

  String get _buttonLabel {
    switch (_phase) {
      case TvPhase.finding:
        return 'در حال یافتن بهترین سرور…';
      case TvPhase.connecting:
        return 'در حال اتصال…';
      case TvPhase.connected:
        return _isOn ? 'متصل هستید — قطع اتصال' : 'در حال اتصال…';
      case TvPhase.recovering:
        return 'در حال بازیابی اتصال…';
      case TvPhase.idle:
        return 'اتصال به JET VPN';
    }
  }

  Color get _buttonColor {
    if (_isOn) return const Color(0xFF2DD4BF);
    if (_phase == TvPhase.finding ||
        _phase == TvPhase.connecting ||
        _phase == TvPhase.recovering) {
      return const Color(0xFF38BDF8);
    }
    return const Color(0xFF6366F1);
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: _loggedIn ? _buildHome() : _buildLogin(),
      ),
    );
  }

  Widget _buildLogin() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  kLogoUrl,
                  width: 88,
                  height: 88,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.rocket_launch_rounded,
                    size: 72,
                    color: Color(0xFF22D3EE),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'JET VPN TV',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'ورود با حساب ربات · نسخه $kAppVersion',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 28),
              _tvField(
                focus: _userFocus,
                next: _passFocus,
                controller: _userCtrl,
                label: 'نام کاربری',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 14),
              _tvField(
                focus: _passFocus,
                next: _loginBtnFocus,
                controller: _passCtrl,
                label: 'رمز عبور',
                icon: Icons.lock_rounded,
                obscure: _obscure,
                trailing: IconButton(
                  focusNode: FocusNode(skipTraversal: true),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    color: Colors.white54,
                  ),
                ),
              ),
              if (_loginError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _loginError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              _FocusBtn(
                focusNode: _loginBtnFocus,
                onPressed: _busyLogin ? null : _doLogin,
                background: const Color(0xFF22D3EE),
                foreground: Colors.black87,
                minWidth: 280,
                minHeight: 56,
                child: _busyLogin
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : const Text(
                        'ورود',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 12),
              const Text(
                'با دکمه‌های جهت‌دار جابه‌جا شوید · OK برای انتخاب',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tvField({
    required FocusNode focus,
    required FocusNode next,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? trailing,
  }) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          next.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        focusNode: focus,
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: trailing,
          filled: true,
          fillColor: const Color(0xFF151C2E),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 2),
          ),
        ),
        onSubmitted: (_) => next.requestFocus(),
      ),
    );
  }

  Widget _buildHome() {
    final name = _servers.isEmpty
        ? '—'
        : _servers[_selected.clamp(0, _servers.length - 1)].name;
    final busy = _phase == TvPhase.finding ||
        _phase == TvPhase.connecting ||
        _phase == TvPhase.recovering;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  kLogoUrl,
                  width: 48,
                  height: 48,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.rocket_launch_rounded,
                    color: Color(0xFF22D3EE),
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JET VPN TV',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _user ?? '',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),
              _FocusBtn(
                focusNode: _logoutFocus,
                onPressed: _logout,
                background: const Color(0xFF1E293B),
                foreground: Colors.white70,
                minWidth: 120,
                minHeight: 44,
                child: const Text('خروج', style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
          const Spacer(),
          _FocusBtn(
            focusNode: _connectFocus,
            onPressed: busy ? null : _toggle,
            background: _buttonColor,
            foreground: Colors.black87,
            minWidth: 420,
            minHeight: 96,
            child: busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          _buttonLabel,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    _buttonLabel,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            _statusLine,
            style: const TextStyle(fontSize: 16, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _activePing > 0
                ? 'سرور: $name  ·  پینگ: $_activePing ms'
                : 'سرور: $name',
            style: const TextStyle(fontSize: 14, color: Colors.white38),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          const Text(
            'تونل کامل دستگاه · انتخاب خودکار بهترین سرور',
            style: TextStyle(color: Colors.white30, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            kAppVersion,
            style: const TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// دکمه با فوکوس واضح برای ریموت
class _FocusBtn extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback? onPressed;
  final Widget child;
  final Color background;
  final Color foreground;
  final double minWidth;
  final double minHeight;

  const _FocusBtn({
    required this.focusNode,
    required this.onPressed,
    required this.child,
    required this.background,
    required this.foreground,
    required this.minWidth,
    required this.minHeight,
  });

  @override
  State<_FocusBtn> createState() => _FocusBtnState();
}

class _FocusBtnState extends State<_FocusBtn> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (widget.onPressed == null) return KeyEventResult.ignored;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedScale(
            scale: focused ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Material(
              color: widget.background,
              borderRadius: BorderRadius.circular(20),
              elevation: focused ? 10 : 2,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: BoxConstraints(
                    minWidth: widget.minWidth,
                    minHeight: widget.minHeight,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: focused ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: widget.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
