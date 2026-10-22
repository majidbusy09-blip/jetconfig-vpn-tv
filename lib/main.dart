// JET VPN TV — پروژه جدا از موبایل | تونل کامل | اتصال هوشمند
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

const String kAppVersion = 'tv-1.0.5';
const String kApiBase = 'https://majid6064.ir/api.php';
const String kLogoUrl = 'https://majid6064.ir/logo.png';
const String kPingUrl = 'https://www.gstatic.com/generate_204';
const String kUpdateMetaUrl = 'https://majid6064.ir/app_version_tv.json';
const int kVersionCode = 105;

// رنگ‌های برند جت
const Color kBg = Color(0xFF0A0E1A);
const Color kCard = Color(0xFF131B2E);
const Color kCyan = Color(0xFF00E5FF);
const Color kCyanDeep = Color(0xFF0052D4);
const Color kTeal = Color(0xFF00FFA3);
const Color kTealDeep = Color(0xFF008B74);

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
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kCyan,
          secondary: kTeal,
          surface: kCard,
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

enum TvPhase { idle, finding, connecting, connected, recovering }

class TvRoot extends StatefulWidget {
  const TvRoot({super.key});
  @override
  State<TvRoot> createState() => _TvRootState();
}

class _TvRootState extends State<TvRoot> with SingleTickerProviderStateMixin {
  late final V2ray _v2ray = V2ray(onStatusChanged: _onStatus);
  late final AnimationController _spin;

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
  int _pingedCount = 0;

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
    if (_verified && (st.contains('CONNECT') || st == 'CONNECTED')) return true;
    // بعضی باکس‌ها state دقیق نمی‌فرستند
    if (_verified && _phase == TvPhase.connected && _userWantsOn) return true;
    return false;
  }

  bool get _busy =>
      _phase == TvPhase.finding ||
      _phase == TvPhase.connecting ||
      _phase == TvPhase.recovering;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    void showKb() {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
    _userFocus.addListener(() {
      if (_userFocus.hasFocus) showKb();
    });
    _passFocus.addListener(() {
      if (_passFocus.hasFocus) showKb();
    });
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _connectFocus.requestFocus();
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
    _spin.dispose();
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

    if (st.contains('DISCONNECT') || st == 'IDLE' || st == 'STOPPED' || st == 'NONE') {
      setState(() {
        _verified = false;
        _activePing = -1;
        if (_phase == TvPhase.connected || _phase == TvPhase.connecting) {
          _phase = _userWantsOn ? TvPhase.recovering : TvPhase.idle;
          _statusLine = _userWantsOn ? 'در حال بازیابی اتصال…' : 'قطع شد';
        }
      });
      if (_userWantsOn) {
        _spin.repeat();
        _scheduleRecover('core_disconnect');
      } else {
        _spin.stop();
      }
      return;
    }

    if (st == 'CONNECTED' && prev != 'CONNECTED') {
      _verifyTunnel();
    }
  }

  Future<void> _verifyTunnel() async {
    try {
      final d = await _v2ray
          .getConnectedServerDelay(url: kPingUrl)
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (d >= 0 && d < 15000) {
        setState(() {
          _verified = true;
          _activePing = d;
          _phase = TvPhase.connected;
          _statusLine = 'متصل هستید';
        });
        _spin.repeat(); // چرخش آرام بعد از اتصال
        _spin.duration = const Duration(seconds: 8);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    // اگر هسته CONNECTED داد ولی delay نگرفت، باز هم وصل در نظر بگیر (مثل بعضی باکس‌ها)
    final st = (_coreState ?? '').toUpperCase();
    if (st == 'CONNECTED' && _userWantsOn) {
      setState(() {
        _verified = true;
        _phase = TvPhase.connected;
        _statusLine = 'متصل هستید';
      });
      _spin.duration = const Duration(seconds: 8);
      _spin.repeat();
      return;
    }
    if (_userWantsOn) {
      setState(() {
        _verified = false;
        _phase = TvPhase.recovering;
        _statusLine = 'این سرور پایدار نبود — امتحان سرور بعدی';
      });
      _scheduleRecover('verify_fail');
    }
  }

  void _scheduleRecover(String reason) {
    _recoverTimer?.cancel();
    final gen = ++_recoverGen;
    _recoverTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || gen != _recoverGen || !_userWantsOn) return;
      await _smartConnect(isRecovery: true);
    });
    debugPrint('tv recover: $reason');
  }


  Future<void> _upsertProfile(SharedPreferences prefs, String u, String p) async {
    final raw = prefs.getString('tv_profiles') ?? '[]';
    List list;
    try {
      list = json.decode(raw) as List;
    } catch (_) {
      list = [];
    }
    final filtered = list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => '${e['u']}' != u)
        .toList();
    filtered.insert(0, {'u': u, 'p': p});
    if (filtered.length > 12) {
      filtered.removeRange(12, filtered.length);
    }
    await prefs.setString('tv_profiles', json.encode(filtered));
  }

  Future<List<Map<String, String>>> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tv_profiles') ?? '[]';
    try {
      final list = json.decode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => {
                'u': '${e['u'] ?? ''}',
                'p': '${e['p'] ?? ''}',
              })
          .where((e) => e['u']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _switchProfile(String u, String p) async {
    _userWantsOn = false;
    _recoverTimer?.cancel();
    _spin.stop();
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {}
    final ok = await _login(u, p, silent: false);
    if (ok && mounted) {
      setState(() {
        _loggedIn = true;
        _phase = TvPhase.idle;
        _verified = false;
        _statusLine = 'اشتراک فعال شد — آماده اتصال';
        _userCtrl.text = u;
        _passCtrl.text = p;
      });
    }
  }

  Future<void> _showProfilesSheet() async {
    final profiles = await _loadProfiles();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اشتراک‌های ذخیره‌شده',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kCyan),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (profiles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('هنوز اشتراکی ذخیره نشده', textAlign: TextAlign.center),
                  ),
                ...profiles.map((pr) {
                  final active = pr['u'] == _user;
                  return ListTile(
                    leading: Icon(
                      active ? Icons.check_circle : Icons.person_outline,
                      color: active ? kTeal : Colors.white54,
                    ),
                    title: Text(pr['u']!, style: const TextStyle(fontSize: 16)),
                    subtitle: active ? const Text('فعال', style: TextStyle(color: kTeal)) : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (!active) await _switchProfile(pr['u']!, pr['p']!);
                    },
                  );
                }),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddProfileDialog();
                  },
                  child: const Text(
                    '＋ افزودن اشتراک جدید',
                    style: TextStyle(color: kCyan, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('بستن'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  Future<void> _showAddProfileDialog() async {
    final uCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    final uFocus = FocusNode();
    final pFocus = FocusNode();
    var obscure = true;
    String? err;
    var busy = false;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: kCard,
              title: const Text('افزودن اشتراک', style: TextStyle(color: kCyan)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: uCtrl,
                      focusNode: uFocus,
                      autofocus: true,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        labelText: 'نام کاربری',
                        border: OutlineInputBorder(),
                      ),
                      onTap: () =>
                          SystemChannels.textInput.invokeMethod('TextInput.show'),
                      onSubmitted: (_) => pFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pCtrl,
                      focusNode: pFocus,
                      obscureText: obscure,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                              obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setLocal(() => obscure = !obscure),
                        ),
                      ),
                      onTap: () =>
                          SystemChannels.textInput.invokeMethod('TextInput.show'),
                    ),
                    if (err != null) ...[
                      const SizedBox(height: 10),
                      Text(err!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('انصراف'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final u = uCtrl.text.trim();
                          final p = pCtrl.text.trim();
                          if (u.isEmpty || p.isEmpty) {
                            setLocal(
                                () => err = 'نام کاربری و رمز را وارد کنید');
                            return;
                          }
                          setLocal(() {
                            busy = true;
                            err = null;
                          });
                          final ok = await _login(u, p, silent: false);
                          if (!ctx.mounted) return;
                          if (ok) {
                            Navigator.pop(ctx);
                            if (mounted) {
                              setState(() {
                                _loggedIn = true;
                                _statusLine = 'اشتراک جدید فعال شد';
                                _phase = TvPhase.idle;
                              });
                            }
                          } else {
                            setLocal(() {
                              busy = false;
                              err = _loginError ?? 'ورود ناموفق';
                            });
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ورود و ذخیره',
                          style: TextStyle(color: kCyan)),
                ),
              ],
            );
          },
        );
      },
    );
    uCtrl.dispose();
    pCtrl.dispose();
    uFocus.dispose();
    pFocus.dispose();
  }

  Future<void> _checkUpdate({bool silent = true}) async {
    try {
      final res = await http
          .get(Uri.parse(kUpdateMetaUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final data = json.decode(res.body);
      if (data is! Map) return;
      final enabled = data['enabled'] == true;
      if (!enabled && silent) return;
      final remoteCode = int.tryParse('${data['version_code'] ?? data['versionCode'] ?? 0}') ?? 0;
      final remoteVer = '${data['version'] ?? ''}';
      final title = '${data['title'] ?? 'نسخه جدید JET VPN TV'}';
      final changelog = '${data['changelog'] ?? ''}';
      final urls = data['urls'];
      String apk = '';
      if (urls is Map) {
        apk = '${urls['arm64'] ?? urls['universal'] ?? ''}';
      }
      if (apk.isEmpty) {
        apk = '${data['apk_arm64'] ?? data['apk'] ?? ''}';
      }
      if (remoteCode <= kVersionCode) {
        if (!silent && mounted) {
          setState(() => _statusLine = 'برنامه به‌روز است ($kAppVersion)');
        }
        return;
      }
      if (!enabled && !silent) {
        if (mounted) setState(() => _statusLine = 'بروزرسانی از پنل خاموش است');
        return;
      }
      if (!mounted) return;
      final force = data['force'] == true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: Text(title, style: const TextStyle(color: kCyan)),
          content: Text(
            'نسخه جدید: $remoteVer\nنسخه فعلی: $kAppVersion'
            '${changelog.isNotEmpty ? '\n\n$changelog' : ''}',
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بعداً'),
              ),
            TextButton(
              onPressed: apk.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _downloadAndInstall(apk);
                    },
              child: const Text('دانلود و نصب', style: TextStyle(color: kCyan)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('update check: $e');
      if (!silent && mounted) {
        setState(() => _statusLine = 'بررسی بروزرسانی ممکن نشد');
      }
    }
  }

  Future<void> _downloadAndInstall(String url) async {
    if (!mounted) return;
    setState(() => _statusLine = 'در حال دانلود بروزرسانی…');
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        setState(() => _statusLine = 'دانلود ناموفق بود');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/jet_vpn_tv_update.apk');
      await file.writeAsBytes(res.bodyBytes, flush: true);
      if (!mounted) return;
      setState(() => _statusLine = 'دانلود شد — در حال باز کردن نصب…');
      final r = await OpenFilex.open(file.path);
      debugPrint('open apk: ${r.message}');
    } catch (e) {
      debugPrint('download: $e');
      if (mounted) {
        setState(() => _statusLine = 'خطا در دانلود یا نصب بروزرسانی');
      }
    }
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
          setState(() =>
              _loginError = '${data['msg'] ?? 'نام کاربری یا رمز اشتباه است'}');
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
      await _upsertProfile(prefs, username, password);
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
        _checkUpdate(silent: true);
      });
    }
  }

  Future<void> _logout() async {
    await _forceDisconnect(reason: 'logout');
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

  /// آماده‌سازی کانفیگ مثل موبایل (inbound محلی + sniffing)
  String _ensureLocalHttpInbound(String configJson) {
    try {
      final decoded = jsonDecode(configJson);
      if (decoded is! Map) return configJson;
      final map = Map<String, dynamic>.from(decoded);
      final inbounds = <dynamic>[];
      if (map['inbounds'] is List) {
        inbounds.addAll(List<dynamic>.from(map['inbounds'] as List));
      }
      bool hasHttp = false;
      bool hasSocks = false;
      for (final ib in inbounds) {
        if (ib is! Map) continue;
        final proto = '${ib['protocol'] ?? ''}'.toLowerCase();
        final port = ib['port'];
        if (proto == 'http' && (port == 10809 || port == '10809')) hasHttp = true;
        if (proto == 'socks') hasSocks = true;
      }
      if (!hasHttp) {
        inbounds.add({
          'tag': 'http-in-jet',
          'port': 10809,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {'timeout': 0, 'allowTransparent': false},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': false,
          },
        });
      }
      if (!hasSocks) {
        inbounds.add({
          'tag': 'socks-in-jet',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': false,
          },
        });
      }
      for (var i = 0; i < inbounds.length; i++) {
        final ib = inbounds[i];
        if (ib is! Map) continue;
        final m = Map<String, dynamic>.from(ib);
        final sniff = m['sniffing'];
        if (sniff is! Map || sniff['enabled'] != true) {
          m['sniffing'] = {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': false,
          };
          inbounds[i] = m;
        }
      }
      map['inbounds'] = inbounds;
      return jsonEncode(map);
    } catch (_) {
      return configJson;
    }
  }

  String _prepareConfig(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    if (s.startsWith('{')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          return _ensureLocalHttpInbound(
              jsonEncode(Map<String, dynamic>.from(decoded)));
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
        final full = parsed.getFullConfiguration();
        return _ensureLocalHttpInbound(full);
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
          .timeout(const Duration(milliseconds: 5000));
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

  /// پینگ همه سرورها + مرتب‌سازی بهینه
  Future<void> _pingAll() async {
    _pingedCount = 0;
    final total = _servers.length;
    if (mounted) {
      setState(() {
        _statusLine = 'در حال سنجش سرورها (۰ از $total)';
      });
    }
    await _mapConcurrent(_servers, 8, (s) async {
      final p = await _realPing(s);
      s.ping = p;
      _pingedCount++;
      if (mounted) {
        setState(() {
          _statusLine = 'در حال سنجش سرورها ($_pingedCount از $total)';
        });
      }
    });
    // امتیاز: پینگ واقعی؛ زیر ۳۰ms مشکوک (CDN دروغین)
    _servers.sort((a, b) {
      int score(TvServer s) {
        if (s.ping <= 0) return 999999;
        if (s.ping < 30) return 8000 + s.ping;
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
          _statusLine = 'مجوز VPN داده نشد. دوباره تلاش کنید و مجوز را بپذیرید';
          _userWantsOn = false;
        });
        _spin.stop();
      }
      return false;
    }
    // تونل کامل — لیست خالی = همه ترافیک
    await _v2ray.startV2Ray(
      remark: s.name,
      config: cfg,
      blockedApps: const <String>[],
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
          _statusLine = 'در حال دریافت فهرست سرورها';
        });
        final ok = await _login(_user!, _pass!, silent: true);
        if (!ok || _servers.isEmpty) {
          setState(() {
            _phase = TvPhase.idle;
            _statusLine = 'هیچ سروری برای این اشتراک پیدا نشد';
            _userWantsOn = false;
          });
          _spin.stop();
          return;
        }
      } else {
        return;
      }
    }

    setState(() {
      _phase = isRecovery ? TvPhase.recovering : TvPhase.finding;
      _statusLine =
          isRecovery ? 'در حال بازیابی…' : 'در حال یافتن بهترین سرور…';
      _verified = false;
    });
    _spin.duration = const Duration(seconds: 2);
    _spin.repeat();

    try {
      await _v2ray.stopV2Ray();
    } catch (_) {}

    // همه سرورها پینگ می‌شوند
    await _pingAll();
    final alive = _servers.where((s) => s.ping > 0).toList();
    // اگر هیچ پینگ زنده‌ای نبود، همه را به ترتیب امتحان کن
    final tryList = alive.isNotEmpty ? alive : List<TvServer>.from(_servers);

    if (tryList.isEmpty) {
      setState(() {
        _phase = TvPhase.idle;
        _statusLine = 'فهرست سرور خالی است';
        _userWantsOn = false;
      });
      _spin.stop();
      return;
    }

    final aliveN = alive.length;
    if (mounted) {
      setState(() {
        _statusLine = aliveN > 0
            ? 'یافت شد: $aliveN سرور مناسب — اتصال به بهترین…'
            : 'پینگ کامل نشد — تلاش روی فهرست سرورها…';
      });
    }

    // همهٔ کاندیدها را به‌ترتیب کیفیت امتحان کن (نه فقط ۵ تا)
    for (var i = 0; i < tryList.length; i++) {
      if (!_userWantsOn || !mounted) return;
      final s = tryList[i];
      final idx = _servers.indexOf(s);
      setState(() {
        _selected = idx >= 0 ? idx : 0;
        _phase = TvPhase.connecting;
        _statusLine = s.ping > 0
            ? 'اتصال به سرور ${i + 1} از ${tryList.length} — تأخیر ${s.ping} میلی‌ثانیه'
            : 'اتصال به سرور ${i + 1} از ${tryList.length}…';
      });
      try {
        final started = await _startServer(s);
        if (!started) {
          if (!_userWantsOn) return;
          continue;
        }
        // تا ~۱۰ ثانیه منتظر CONNECTED + verify
        for (var t = 0; t < 25; t++) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (!mounted || !_userWantsOn) return;
          if (_isOn) return;
          final st = (_coreState ?? '').toUpperCase();
          if (st == 'CONNECTED' && !_verified) {
            // فرصت به verify
            await Future.delayed(const Duration(milliseconds: 500));
            if (_isOn) return;
          }
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
        _statusLine = 'اتصال برقرار نشد. دوباره دکمه اتصال را بزنید';
        _userWantsOn = false;
      });
      _spin.stop();
    }
  }

  Future<void> _forceDisconnect({String reason = 'user'}) async {
    _userWantsOn = false;
    _recoverTimer?.cancel();
    _recoverGen++;
    if (mounted) {
      setState(() {
        _phase = TvPhase.idle;
        _verified = false;
        _activePing = -1;
        _coreState = 'DISCONNECTED';
        _statusLine = 'اتصال قطع شد';
      });
    }
    _spin.stop();
    try {
      await _v2ray.stopV2Ray().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('stopV2Ray: $e');
    }
  }

  Future<void> _toggle() async {
    // اگر وصل هستیم یا در حال اتصال → قطع؛ وگرنه اتصال هوشمند
    if (_isOn || _userWantsOn || _phase != TvPhase.idle) {
      await _forceDisconnect();
      return;
    }
    _userWantsOn = true;
    await _smartConnect();
  }

  /// حالت یوتیوب بدون تبلیغ: اولویت سرور آلبانی
  Future<void> _connectAlbaniaYoutube() async {
    if (_busy && _phase != TvPhase.idle) {
      await _forceDisconnect();
    }
    if (_servers.isEmpty && _user != null && _pass != null) {
      setState(() {
        _phase = TvPhase.finding;
        _statusLine = 'دریافت فهرست سرورها…';
      });
      await _login(_user!, _pass!, silent: true);
    }
    if (_servers.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine = 'سروری در اشتراک نیست';
        });
      }
      return;
    }

    bool isAlbania(TvServer s) {
      final n = s.name.toLowerCase();
      return n.contains('alban') ||
          n.contains('آلبانی') ||
          n.contains('البانی') ||
          n.contains('🇦🇱') ||
          n.contains(' al ') ||
          n.startsWith('al-') ||
          n.contains('-al-') ||
          n.contains('tirana');
    }

    final candidates = _servers.where(isAlbania).toList();
    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine =
              'سرور آلبانی در این اشتراک پیدا نشد. از اتصال هوشمند استفاده کنید.';
        });
      }
      return;
    }

    _userWantsOn = true;
    if (mounted) {
      setState(() {
        _phase = TvPhase.finding;
        _statusLine = 'یوتیوب بدون تبلیغ — سنجش سرور آلبانی…';
      });
    }
    _spin.duration = const Duration(seconds: 2);
    _spin.repeat();

    await _mapConcurrent(candidates, 6, (s) async {
      final p = await _realPing(s);
      s.ping = p;
    });

    candidates.sort((a, b) {
      final pa = a.ping > 0 ? a.ping : 999999;
      final pb = b.ping > 0 ? b.ping : 999999;
      return pa.compareTo(pb);
    });

    final alive = candidates.where((s) => s.ping > 0).toList();
    if (alive.isEmpty) {
      _userWantsOn = false;
      _spin.stop();
      if (mounted) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine =
              'سرور آلبانی الان پاسخ نداد. بعداً دوباره امتحان کنید یا اتصال هوشمند بزنید.';
        });
      }
      return;
    }

    // اتصال به بهترین آلبانی
    if (mounted) {
      setState(() {
        _phase = TvPhase.connecting;
        _statusLine =
            'اتصال به آلبانی برای یوتیوب… (${alive.first.ping} ms)';
        final idx = _servers.indexOf(alive.first);
        if (idx >= 0) _selected = idx;
      });
    }

    for (final s in alive) {
      if (!_userWantsOn) break;
      final ok = await _startServer(s);
      if (!ok) continue;
      // صبر برای status
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (_isOn) return;
        if (!_userWantsOn) return;
      }
      try {
        await _v2ray.stopV2Ray();
      } catch (_) {}
    }

    if (mounted && !_isOn) {
      _userWantsOn = false;
      _spin.stop();
      setState(() {
        _phase = TvPhase.idle;
        _statusLine = 'اتصال به سرور آلبانی برقرار نشد';
      });
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kCyan)),
      );
    }
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E1A), Color(0xFF0D1B2A), Color(0xFF0A0E1A)],
          ),
        ),
        child: SafeArea(
          child: _loggedIn ? _buildHome() : _buildLogin(),
        ),
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
              _logo(96),
              const SizedBox(height: 16),
              const Text(
                'JET VPN TV',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: kCyan,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ورود با حساب ربات · $kAppVersion',
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
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
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
                background: kCyan,
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
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
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

  Widget _logo(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: kCyan.withOpacity(0.35),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'logotype.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.network(
            kLogoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: kCard,
              child: Icon(Icons.rocket_launch_rounded, size: size * 0.5, color: kCyan),
            ),
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
      focusNode: FocusNode(skipTraversal: true),
      onFocusChange: (has) {
        if (has) {
          focus.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
          next.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        focusNode: focus,
        controller: controller,
        obscureText: obscure,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.next,
        enableInteractiveSelection: true,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: kCyan.withOpacity(0.8)),
          suffixIcon: trailing,
          filled: true,
          fillColor: kCard,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kCyan, width: 2),
          ),
        ),
        onTap: () {
          focus.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        },
        onSubmitted: (_) => next.requestFocus(),
      ),
    );
  }

  Widget _buildHome() {
    final name = _servers.isEmpty
        ? '—'
        : _servers[_selected.clamp(0, _servers.length - 1)].name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        children: [
          Row(
            children: [
              _logo(48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JET VPN',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: kCyan,
                      ),
                    ),
                    Text(
                      _user ?? '',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),
              _FocusBtn(
                focusNode: FocusNode(),
                onPressed: _showProfilesSheet,
                background: kCard,
                foreground: Colors.white70,
                minWidth: 100,
                minHeight: 44,
                child: const Text('اشتراک‌ها', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 8),
              _FocusBtn(
                focusNode: _logoutFocus,
                onPressed: _logout,
                background: kCard,
                foreground: Colors.white70,
                minWidth: 90,
                minHeight: 44,
                child: const Text('خروج', style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
          const Spacer(flex: 2),
          // دکمه دایره‌ای اتصال
          _CircularConnectBtn(
            focusNode: _connectFocus,
            onPressed: _toggle, // قطع همیشه فعال باشد
            isOn: _isOn || _phase == TvPhase.connected,
            busy: _busy && !_isOn,
            spin: _spin,
          ),
          const SizedBox(height: 28),
          Text(
            _buttonHint,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _isOn ? kTeal : Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _statusLine,
            style: const TextStyle(fontSize: 15, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _activePing > 0
                ? '$name  ·  $_activePing ms'
                : name,
            style: const TextStyle(fontSize: 13, color: Colors.white38),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          _FocusBtn(
            focusNode: FocusNode(),
            onPressed: _busy ? null : _connectAlbaniaYoutube,
            background: const Color(0xFF1A2332),
            foreground: Colors.white,
            minWidth: 280,
            minHeight: 48,
            child: const Text(
              '▶  تماشای یوتیوب بدون تبلیغ',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(flex: 1),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '🚀 اتصال سریع و پایدار روی تلویزیون · سرور هوشمند · تونل کامل
از ربات جت‌کانفیگ، همیشه آنلاین بمانید',
              style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            kAppVersion,
            style: const TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String get _buttonHint {
    switch (_phase) {
      case TvPhase.finding:
        return 'در حال یافتن بهترین سرور';
      case TvPhase.connecting:
        return 'در حال برقراری اتصال';
      case TvPhase.connected:
        return _isOn ? 'متصل هستید' : 'در حال برقراری اتصال';
      case TvPhase.recovering:
        return 'در حال بازیابی اتصال';
      case TvPhase.idle:
        return 'برای اتصال، دکمه را بزنید';
    }
  }
}

/// دکمه دایره‌ای برند جت با فوکوس ریموت
class _CircularConnectBtn extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback? onPressed;
  final bool isOn;
  final bool busy;
  final AnimationController spin;

  const _CircularConnectBtn({
    required this.focusNode,
    required this.onPressed,
    required this.isOn,
    required this.busy,
    required this.spin,
  });

  @override
  State<_CircularConnectBtn> createState() => _CircularConnectBtnState();
}

class _CircularConnectBtnState extends State<_CircularConnectBtn> {
  @override
  Widget build(BuildContext context) {
    final onColor = widget.isOn ? kTeal : kCyan;
    final deep = widget.isOn ? kTealDeep : kCyanDeep;

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
            scale: focused ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: SizedBox(
                width: 168,
                height: 168,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // حلقه چرخان
                    if (widget.busy || widget.isOn)
                      RotationTransition(
                        turns: widget.spin,
                        child: CustomPaint(
                          size: const Size(168, 168),
                          painter: _RingPainter(
                            color: onColor.withOpacity(0.85),
                            sweep: widget.isOn ? 0.35 : 0.55,
                          ),
                        ),
                      ),
                    // هاله
                    Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: onColor.withOpacity(focused ? 0.55 : 0.28),
                            blurRadius: focused ? 32 : 18,
                            spreadRadius: focused ? 4 : 1,
                          ),
                        ],
                      ),
                    ),
                    // بدنه دکمه
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [onColor, deep],
                        ),
                        border: Border.all(
                          color: focused ? Colors.white : Colors.white24,
                          width: focused ? 3.5 : 1.5,
                        ),
                      ),
                      child: Icon(
                        widget.isOn
                            ? Icons.power_settings_new_rounded
                            : Icons.power_settings_new_rounded,
                        size: 56,
                        color: Colors.black.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final double sweep;
  _RingPainter({required this.color, this.sweep = 0.4});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -1.2, sweep * 6.28, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color || old.sweep != sweep;
}

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
              borderRadius: BorderRadius.circular(16),
              elevation: focused ? 8 : 2,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  constraints: BoxConstraints(
                    minWidth: widget.minWidth,
                    minHeight: widget.minHeight,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: focused ? kCyan : Colors.transparent,
                      width: 2.5,
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
