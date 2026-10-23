// JET VPN TV — پروژه جدا از موبایل | تونل کامل | اتصال هوشمند
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

const String kAppVersion = 'tv-1.0.10';
const String kApiBase = 'https://majid6064.ir/api.php';
const String kLogoUrl = 'https://majid6064.ir/logo.png';
const String kPingUrl = 'https://www.gstatic.com/generate_204';
const String kUpdateMetaUrl = 'https://majid6064.ir/app_version_tv.json';
const int kVersionCode = 110;
const String kApkChannel = 'arm32';

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
  bool _showSplash = true;
  VideoPlayerController? _splashVideo;
  bool _splashReady = false;
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
  String _quotaLine = '';
  int _activePing = -1;
  bool _userWantsOn = false;
  bool _verified = false;
  String? _coreState;
  int _recoverGen = 0;
  int _connectGen = 0;
  bool _switchingServers = false;
  Timer? _recoverTimer;

  bool get _isOn {
    if (!_verified || !_userWantsOn) return false;
    if (_phase == TvPhase.connected) return true;
    return _statusMeansConnected(_coreState);
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
    _startSplash();
    _init();
  }

  Future<void> _startSplash() async {
    try {
      final c = VideoPlayerController.asset('start.mp4');
      _splashVideo = c;
      await c.initialize();
      if (!mounted) return;
      await c.setLooping(false);
      await c.setVolume(1.0);
      setState(() => _splashReady = true);
      await c.play();
      // حداکثر ~۴.۵ ثانیه یا پایان ویدیو
      c.addListener(() {
        final v = _splashVideo;
        if (v == null || !v.value.isInitialized) return;
        if (v.value.position >= v.value.duration - const Duration(milliseconds: 200)) {
          _endSplash();
        }
      });
      Future.delayed(const Duration(milliseconds: 4500), _endSplash);
    } catch (e) {
      debugPrint('splash video: $e');
      _endSplash();
    }
  }

  void _endSplash() {
    if (!mounted || !_showSplash) return;
    setState(() => _showSplash = false);
    try {
      _splashVideo?.pause();
    } catch (_) {}
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
    try {
      _splashVideo?.dispose();
    } catch (_) {}
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _loginBtnFocus.dispose();
    _connectFocus.dispose();
    _logoutFocus.dispose();
    super.dispose();
  }

  bool _statusMeansConnected(String? state) {
    final s = (state ?? '').toUpperCase().trim();
    if (s.isEmpty) return false;
    if (s.contains('DISCONNECT')) return false;
    if (s == 'CONNECTED') return true;
    // بعضی بیلدها فقط CONNECT می‌فرستند
    if (s == 'CONNECT') return true;
    return false;
  }

  bool _statusMeansDisconnected(String? state) {
    final s = (state ?? '').toUpperCase().trim();
    return s.contains('DISCONNECT') ||
        s == 'IDLE' ||
        s == 'STOPPED' ||
        s == 'NONE' ||
        s == 'DISCONNECTED';
  }

  void _onStatus(V2RayStatus status) {
    if (!mounted) return;
    final prev = (_coreState ?? '').toUpperCase();
    _coreState = status.state;
    final st = (status.state ?? '').toUpperCase();

    // هنگام تعویض عمدی سرور، DISCONNECT را نادیده بگیر تا حلقه بازیابی ساخته نشود
    if (_switchingServers) return;

    if (_statusMeansDisconnected(st)) {
      // فقط اگر واقعاً وصل بودیم و کاربر هنوز می‌خواهد وصل بماند → بازیابی
      final wasConnected = _verified && _phase == TvPhase.connected;
      if (wasConnected && _userWantsOn) {
        setState(() {
          _verified = false;
          _activePing = -1;
          _phase = TvPhase.recovering;
          _statusLine = 'قطع شد — در حال بازیابی…';
        });
        _scheduleRecover('core_disconnect');
      } else if (!_userWantsOn) {
        setState(() {
          _verified = false;
          _activePing = -1;
          if (_phase != TvPhase.finding && _phase != TvPhase.connecting) {
            _phase = TvPhase.idle;
          }
        });
      }
      return;
    }

    if (_statusMeansConnected(st) && !_statusMeansConnected(prev)) {
      if (_userWantsOn &&
          (_phase == TvPhase.connecting ||
              _phase == TvPhase.recovering ||
              _phase == TvPhase.finding)) {
        _markConnected();
      }
    }
  }

  void _markConnected({int? pingMs}) {
    if (!mounted || !_userWantsOn) return;
    setState(() {
      _verified = true;
      _phase = TvPhase.connected;
      _switchingServers = false;
      if (pingMs != null && pingMs > 0) _activePing = pingMs;
      _statusLine = _activePing > 0
          ? 'متصل هستید · $_activePing ms'
          : 'متصل هستید';
    });
    _spin.duration = const Duration(seconds: 8);
    if (!_spin.isAnimating) _spin.repeat();
    // پینگ تأخیر فقط برای نمایش — قطع نمی‌کند
    _measureActivePing();
  }

  Future<void> _measureActivePing() async {
    try {
      final d = await _v2ray
          .getConnectedServerDelay(url: kPingUrl)
          .timeout(const Duration(seconds: 8));
      if (!mounted || !_userWantsOn || !_verified) return;
      if (d >= 0 && d < 20000) {
        setState(() {
          _activePing = d;
          _statusLine = 'متصل هستید · $d ms';
        });
      }
    } catch (_) {}
  }

  void _scheduleRecover(String reason) {
    _recoverTimer?.cancel();
    // وسط پیدا کردن/اتصال سرور، بازیابی جدا راه نینداز
    if (_phase == TvPhase.finding ||
        _phase == TvPhase.connecting ||
        _switchingServers) {
      debugPrint('tv recover skipped ($reason) phase=$_phase');
      return;
    }
    final gen = ++_recoverGen;
    _recoverTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || gen != _recoverGen || !_userWantsOn) return;
      if (_verified && _statusMeansConnected(_coreState)) return;
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

  // ---------- بروزرسانی پایدار APK (مثل موبایل) ----------
  static const String _kUpPath = 'tv_update_apk_path';
  static const String _kUpVer = 'tv_update_apk_version';
  static const String _kUpCode = 'tv_update_apk_version_code';
  static const String _kUpChannel = 'tv_update_apk_channel';
  static const String _kUpSize = 'tv_update_apk_size';
  static const String _kUpUrl = 'tv_update_apk_url';

  Future<Directory> _updateStorageDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _clearPendingUpdatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUpPath);
    await prefs.remove(_kUpVer);
    await prefs.remove(_kUpCode);
    await prefs.remove(_kUpChannel);
    await prefs.remove(_kUpSize);
    await prefs.remove(_kUpUrl);
  }

  Future<void> _savePendingUpdate({
    required String path,
    required String version,
    required int versionCode,
    required String channel,
    required int size,
    required String url,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUpPath, path);
    await prefs.setString(_kUpVer, version);
    await prefs.setInt(_kUpCode, versionCode);
    await prefs.setString(_kUpChannel, channel);
    await prefs.setInt(_kUpSize, size);
    await prefs.setString(_kUpUrl, url);
  }

  Future<Map<String, dynamic>?> _loadPendingUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kUpPath);
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    if (!await f.exists()) {
      await _clearPendingUpdatePrefs();
      return null;
    }
    final len = await f.length();
    final expected = prefs.getInt(_kUpSize) ?? 0;
    if (len < 1000 || (expected > 0 && len < expected * 0.95)) {
      try {
        await f.delete();
      } catch (_) {}
      await _clearPendingUpdatePrefs();
      return null;
    }
    final code = prefs.getInt(_kUpCode) ?? 0;
    if (code > 0 && kVersionCode >= code) {
      try {
        await f.delete();
      } catch (_) {}
      await _clearPendingUpdatePrefs();
      return null;
    }
    return {
      'path': path,
      'version': prefs.getString(_kUpVer) ?? '',
      'version_code': code,
      'channel': prefs.getString(_kUpChannel) ?? kApkChannel,
      'size': len,
      'url': prefs.getString(_kUpUrl) ?? '',
    };
  }

  String _fmtMb(int bytes) {
    if (bytes <= 0) return '0';
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }

  Future<void> _installApkFile(String path) async {
    try {
      final r = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      debugPrint('open apk: ${r.type} ${r.message}');
      if (mounted) {
        setState(() => _statusLine = 'نصب را در پنجره سیستم تأیید کنید');
      }
    } catch (e) {
      debugPrint('install open: $e');
      if (mounted) {
        setState(() => _statusLine = 'باز کردن فایل نصب ممکن نشد');
      }
    }
  }

  Future<void> _checkUpdate({bool silent = true}) async {
    try {
      // اگر فایل از قبل دانلود شده، همان را پیشنهاد بده
      final pending = await _loadPendingUpdate();
      if (pending != null && !silent) {
        final pVer = '${pending['version']}';
        final pCode = pending['version_code'] as int;
        final pSize = pending['size'] as int;
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kCard,
            title: const Text('فایل بروزرسانی آماده است',
                style: TextStyle(color: kCyan)),
            content: Text(
              'نسخه $pVer (کد $pCode) قبلاً دانلود شده.\n'
              'حجم: ${_fmtMb(pSize)} مگابایت\n\n'
              'می‌توانید همین الان نصب کنید؛ نیازی به دانلود مجدد نیست.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بعداً'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _deletePendingUpdateFile();
                  if (mounted) {
                    setState(() => _statusLine = 'فایل بروزرسانی حذف شد');
                  }
                },
                child: const Text('حذف فایل',
                    style: TextStyle(color: Colors.redAccent)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _installApkFile(pending['path'] as String);
                },
                child: const Text('نصب', style: TextStyle(color: kCyan)),
              ),
            ],
          ),
        );
        return;
      }

      final res = await http
          .get(Uri.parse(kUpdateMetaUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (!silent && mounted) {
          setState(() => _statusLine = 'سرور بروزرسانی پاسخ نداد');
        }
        return;
      }
      final data = json.decode(res.body);
      if (data is! Map) return;
      final enabled = data['enabled'] == true;
      if (!enabled && silent) return;

      final remoteCode =
          int.tryParse('${data['version_code'] ?? data['versionCode'] ?? 0}') ??
              0;
      final remoteVer = '${data['version'] ?? ''}';
      final title = '${data['title'] ?? 'نسخه جدید JET VPN TV'}';
      final changelog = '${data['changelog'] ?? ''}';
      final urls = data['urls'];
      String apk = '';
      if (urls is Map) {
        apk =
            '${urls['arm32'] ?? urls['armeabi-v7a'] ?? urls['arm64'] ?? urls['universal'] ?? ''}';
      }
      if (apk.isEmpty) {
        apk = '${data['apk_arm32'] ?? data['apk_arm64'] ?? data['apk'] ?? ''}';
      }

      // pending با همان version_code
      if (pending != null && (pending['version_code'] as int) == remoteCode) {
        if (!silent && mounted) {
          setState(() => _statusLine = 'فایل نسخه $remoteVer آماده نصب است');
        }
        return;
      }

      if (remoteCode <= kVersionCode) {
        if (!silent && mounted) {
          setState(() => _statusLine = 'برنامه به‌روز است ($kAppVersion)');
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: kCard,
              title: const Text('همه‌چیز به‌روز است ✅',
                  style: TextStyle(color: kTeal)),
              content: Text(
                'نسخه $kAppVersion روی دستگاه شما آخرین نسخه است.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('باشه', style: TextStyle(color: kCyan)),
                ),
              ],
            ),
          );
        }
        return;
      }
      if (!enabled && !silent) {
        if (mounted) {
          setState(() => _statusLine = 'بروزرسانی از پنل خاموش است');
        }
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
            '${changelog.isNotEmpty ? '\n\n$changelog' : ''}\n\n'
            'فایل بعد از دانلود نگه داشته می‌شود تا بتوانید بعداً نصب کنید.',
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
                      await _startApkDownload(
                        apkUrl: apk,
                        remoteVer: remoteVer,
                        remoteCode: remoteCode,
                      );
                    },
              child: const Text('دانلود و نصب',
                  style: TextStyle(color: kCyan)),
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

  Future<void> _deletePendingUpdateFile() async {
    final info = await _loadPendingUpdate();
    if (info != null) {
      try {
        final f = File(info['path'] as String);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _clearPendingUpdatePrefs();
  }

  Future<void> _startApkDownload({
    required String apkUrl,
    required String remoteVer,
    required int remoteCode,
  }) async {
    if (!mounted) return;

    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('در حال آماده‌سازی…');
    var cancelled = false;
    http.Client? client;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: kCard,
          title: const Text(
            'دانلود بروزرسانی',
            style: TextStyle(color: kCyan, fontWeight: FontWeight.bold),
          ),
          content: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, st, __) {
              return ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, p, __) {
                  final pct = (p * 100).clamp(0, 100).toStringAsFixed(0);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(st,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: p > 0 && p < 1 ? p : (p >= 1 ? 1.0 : null),
                          minHeight: 10,
                          backgroundColor: Colors.white12,
                          color: kCyan,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        p > 0 ? '$pct٪' : '…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'فایل در حافظه اپ ذخیره می‌شود.\n'
                        'اگر الان نصب نکردید، از «آپدیت اپ» دوباره نصب کنید.',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 12, height: 1.4),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                try {
                  client?.close();
                } catch (_) {}
                Navigator.pop(ctx);
              },
              child: const Text('انصراف',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );

    File? file;
    try {
      status.value = 'در حال دانلود از سرور…';
      final dir = await _updateStorageDir();
      final safeVer = remoteVer.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      file = File('${dir.path}/jetvpn_tv_${safeVer}_$kApkChannel.apk');

      try {
        await for (final entity in dir.list()) {
          if (entity is File &&
              entity.path.endsWith('.apk') &&
              entity.path != file.path) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}

      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      client = http.Client();
      final req = http.Request('GET', Uri.parse(apkUrl));
      req.headers['User-Agent'] = 'JET-VPN-TV-Updater/$kAppVersion';
      final streamed =
          await client.send(req).timeout(const Duration(minutes: 15));
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      final total = streamed.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in streamed.stream) {
        if (cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress.value = (received / total).clamp(0.0, 1.0);
          status.value =
              'دانلود… ${(progress.value * 100).toStringAsFixed(0)}٪  ·  ${_fmtMb(received)} / ${_fmtMb(total)} مگ';
        } else {
          status.value = 'دانلود… ${_fmtMb(received)} مگابایت';
        }
      }
      await sink.flush();
      await sink.close();

      if (cancelled) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        if (mounted) {
          setState(() => _statusLine = 'دانلود لغو شد');
        }
        return;
      }

      final size = await file.length();
      if (size < 1000) throw Exception('فایل خیلی کوچک است');

      await _savePendingUpdate(
        path: file.path,
        version: remoteVer,
        versionCode: remoteCode,
        channel: kApkChannel,
        size: size,
        url: apkUrl,
      );

      progress.value = 1;
      status.value = 'دانلود کامل شد · ${_fmtMb(size)} مگابایت';

      if (mounted) {
        // بستن دیالوگ پیشرفت
        Navigator.of(context, rootNavigator: true).pop();
        setState(() =>
            _statusLine = 'دانلود شد — می‌توانید نصب کنید یا بعداً از آپدیت اپ');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kCard,
            title: const Text('دانلود تمام شد',
                style: TextStyle(color: kTeal)),
            content: Text(
              'نسخه $remoteVer ذخیره شد (${_fmtMb(size)} مگ).\n\n'
              'اگر الان نصب نکنید، فایل می‌ماند و از «آپدیت اپ» دوباره نصب می‌شود.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بعداً'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _installApkFile(file!.path);
                },
                child: const Text('نصب الان',
                    style: TextStyle(color: kCyan)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('tv apk download: $e');
      try {
        if (file != null && await file.exists()) {
          // اگر ناقص بود پاک کن مگر نزدیک کامل
          final len = await file.length();
          if (len < 10000) await file.delete();
        }
      } catch (_) {}
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        setState(() => _statusLine = 'خطا در دانلود بروزرسانی');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: kCard,
            title: const Text('خطای دانلود',
                style: TextStyle(color: Colors.redAccent)),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('باشه'),
              ),
            ],
          ),
        );
      }
    } finally {
      try {
        client?.close();
      } catch (_) {}
      progress.dispose();
      status.dispose();
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
      final expire = '${data['expire_days'] ?? data['expire'] ?? ''}'.trim();
      final rem = '${data['remaining_gb'] ?? ''}'.trim();
      final used = '${data['used_gb'] ?? ''}'.trim();
      final total = '${data['total_gb'] ?? ''}'.trim();
      final parts = <String>[];
      if (rem.isNotEmpty && rem != 'null') {
        parts.add('مانده: $rem گیگ');
      } else if (total.isNotEmpty && total != 'null') {
        parts.add('حجم: $total گیگ');
      }
      if (used.isNotEmpty && used != 'null') parts.add('مصرف: $used');
      if (expire.isNotEmpty && expire != 'null') parts.add(expire);
      final quota = parts.join(' · ');

      setState(() {
        _user = username;
        _pass = password;
        _servers = list;
        _selected = 0;
        _loginError = null;
        _quotaLine = quota;
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

  /// مرحله ۱ — TCP سریع (مثل موبایل)
  Future<int> _tcpPing(String host, int port) async {
    if (host.isEmpty || port <= 0) return -2;
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1200),
      );
      socket.destroy();
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      if (ms <= 0) return 1;
      if (ms > 8000) return -2;
      return ms;
    } catch (_) {
      return -2;
    }
  }

  /// مرحله ۲ — تأخیر واقعی از هسته
  Future<int> _realPing(TvServer s) async {
    try {
      final cfg = _prepareConfig(s.config);
      if (cfg.isEmpty) return -2;
      final d = await _v2ray
          .getServerDelay(config: cfg, url: kPingUrl)
          .timeout(const Duration(milliseconds: 6000));
      if (d < 0 || d > 15000) return -2;
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

  /// پینگ دو مرحله‌ای مثل اپ موبایل + مرتب‌سازی
  Future<void> _pingAll() async {
    _pingedCount = 0;
    final total = _servers.length;
    if (total == 0) return;
    if (mounted) {
      setState(() => _statusLine = 'پینگ سریع (۱/$total)…');
    }

    // مرحله ۱: TCP موازی
    await Future.wait(_servers.map((s) async {
      final p = await _tcpPing(s.host, s.port);
      s.ping = p;
      _pingedCount++;
      if (mounted && _pingedCount % 4 == 0) {
        setState(() {
          _statusLine = 'پینگ سریع ($_pingedCount از $total)';
        });
      }
    }));

    if (!mounted) return;

    // مرحله ۲: فقط سرورهای TCP زنده
    final candidates = _servers.where((s) => s.ping > 0).toList();
    if (mounted) {
      setState(() {
        _statusLine = candidates.isEmpty
            ? 'پینگ واقعی…'
            : 'پینگ واقعی (۰ از ${candidates.length})…';
      });
    }
    var done = 0;
    if (candidates.isNotEmpty) {
      await _mapConcurrent(candidates, 4, (s) async {
        final real = await _realPing(s);
        s.ping = real;
        done++;
        if (mounted && done % 2 == 0) {
          setState(() {
            _statusLine = 'پینگ واقعی ($done از ${candidates.length})';
          });
        }
      });
    }

    // امتیاز: پینگ واقعی؛ زیر ۳۰ms مشکوک
    _servers.sort((a, b) {
      int score(TvServer s) {
        if (s.ping <= 0) return 999999;
        if (s.ping < 30) return 5000 + s.ping;
        return s.ping;
      }

      return score(a).compareTo(score(b));
    });
    if (mounted) setState(() {});
  }

  Future<bool> _startServer(TvServer s, {required int gen}) async {
    if (gen != _connectGen || !_userWantsOn) return false;
    final cfg = _prepareConfig(s.config);
    if (cfg.isEmpty) return false;
    final okPerm = await _v2ray.requestPermission();
    if (!okPerm) {
      if (mounted && gen == _connectGen) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine = 'مجوز VPN داده نشد. دوباره تلاش کنید.';
          _userWantsOn = false;
        });
        _spin.stop();
      }
      return false;
    }
    if (gen != _connectGen || !_userWantsOn) return false;
    await _v2ray.startV2Ray(
      remark: s.name,
      config: cfg,
      blockedApps: const <String>[],
      proxyOnly: false,
      notificationDisconnectButtonName: 'قطع',
    );
    return true;
  }

  Future<bool> _waitConnected(int gen, {int seconds = 12}) async {
    final steps = seconds * 2;
    for (var i = 0; i < steps; i++) {
      if (!mounted || gen != _connectGen || !_userWantsOn) return false;
      if (_verified && _statusMeansConnected(_coreState)) return true;
      if (_statusMeansConnected(_coreState)) {
        _markConnected();
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// اتصال به بهترین سرورهای زنده‌شده (کم‌پینگ اول) — بدون شلّیک بی‌وقفه
  Future<bool> _tryConnectList(
    List<TvServer> tryList, {
    required int gen,
    int maxTries = 6,
  }) async {
    final n = tryList.length < maxTries ? tryList.length : maxTries;
    for (var i = 0; i < n; i++) {
      if (!mounted || gen != _connectGen || !_userWantsOn) return false;
      final s = tryList[i];
      final idx = _servers.indexOf(s);
      if (mounted) {
        setState(() {
          _selected = idx >= 0 ? idx : 0;
          _phase = TvPhase.connecting;
          _statusLine = s.ping > 0
              ? 'اتصال به بهترین سرور (${i + 1}/$n) · ${s.ping} ms'
              : 'اتصال (${i + 1}/$n)…';
        });
      }

      _switchingServers = true;
      try {
        await _v2ray.stopV2Ray().timeout(const Duration(seconds: 2));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
      _switchingServers = false;

      if (gen != _connectGen || !_userWantsOn) return false;

      try {
        final started = await _startServer(s, gen: gen);
        if (!started) continue;
        final ok = await _waitConnected(gen, seconds: 12);
        if (ok) {
          if (s.ping > 0 && mounted) {
            setState(() => _activePing = s.ping);
          }
          return true;
        }
      } catch (e) {
        debugPrint('try server: $e');
      }

      _switchingServers = true;
      try {
        await _v2ray.stopV2Ray().timeout(const Duration(seconds: 2));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
      _switchingServers = false;
    }
    return false;
  }

  /// بروزرسانی لیست سرورها از ربات (دستی یا خودکار)
  Future<bool> _refreshSubscription({bool quiet = false}) async {
    if (_user == null || _pass == null) {
      if (!quiet && mounted) {
        setState(() => _statusLine = 'اول وارد حساب شوید');
      }
      return false;
    }
    if (!quiet && mounted) {
      setState(() {
        _phase = TvPhase.finding;
        _statusLine = 'در حال بروزرسانی اشتراک…';
      });
    }
    final ok = await _login(_user!, _pass!, silent: true);
    if (!mounted) return ok;
    if (ok) {
      if (!quiet) {
        setState(() {
          _statusLine =
              'اشتراک بروز شد · ${_servers.length} سرور آماده';
          if (_phase == TvPhase.finding) _phase = TvPhase.idle;
        });
      }
      return true;
    }
    if (!quiet) {
      setState(() {
        _statusLine = 'بروزرسانی اشتراک ناموفق بود';
        if (_phase == TvPhase.finding) _phase = TvPhase.idle;
      });
    }
    return false;
  }

  Future<void> _smartConnect({bool isRecovery = false, bool didRefresh = false}) async {
    final gen = isRecovery ? _connectGen : ++_connectGen;
    if (!isRecovery) {
      _recoverTimer?.cancel();
      _recoverGen++;
    }

    if (_servers.isEmpty) {
      if (_user != null && _pass != null) {
        if (mounted) {
          setState(() {
            _phase = TvPhase.finding;
            _statusLine = 'دریافت فهرست سرورها…';
          });
        }
        final ok = await _login(_user!, _pass!, silent: true);
        if (!ok || _servers.isEmpty) {
          if (mounted && gen == _connectGen) {
            setState(() {
              _phase = TvPhase.idle;
              _statusLine = 'هیچ سروری برای این اشتراک پیدا نشد';
              _userWantsOn = false;
            });
            _spin.stop();
          }
          return;
        }
      } else {
        return;
      }
    }

    if (mounted && gen == _connectGen) {
      setState(() {
        _phase = isRecovery ? TvPhase.recovering : TvPhase.finding;
        _statusLine =
            isRecovery ? 'بازیابی اتصال…' : 'پینگ دو مرحله‌ای سرورها…';
        _verified = false;
      });
    }
    _spin.duration = const Duration(seconds: 2);
    _spin.repeat();

    _switchingServers = true;
    try {
      await _v2ray.stopV2Ray().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _switchingServers = false;

    if (gen != _connectGen || !_userWantsOn) return;

    await _pingAll();
    if (gen != _connectGen || !_userWantsOn) return;

    var alive = _servers.where((s) => s.ping > 0).toList();
    // اگر هیچ زنده نبود → یک‌بار رفرش اشتراک
    if (alive.isEmpty && !didRefresh && _user != null && _pass != null) {
      if (mounted) {
        setState(() => _statusLine = 'سرور زنده نبود — بروزرسانی اشتراک…');
      }
      final refreshed = await _refreshSubscription(quiet: true);
      if (refreshed && gen == _connectGen && _userWantsOn) {
        await _smartConnect(isRecovery: isRecovery, didRefresh: true);
        return;
      }
    }

    alive = _servers.where((s) => s.ping > 0).toList();
    final tryList = alive.isNotEmpty ? alive : List<TvServer>.from(_servers);

    if (tryList.isEmpty) {
      if (mounted && gen == _connectGen) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine = 'فهرست سرور خالی است';
          _userWantsOn = false;
        });
        _spin.stop();
      }
      return;
    }

    if (mounted && gen == _connectGen) {
      setState(() {
        _statusLine = alive.isNotEmpty
            ? 'بهترین پینگ: ${alive.first.ping} ms — در حال اتصال…'
            : 'تلاش اتصال بدون پینگ معتبر…';
      });
    }

    final ok = await _tryConnectList(tryList, gen: gen, maxTries: 8);
    if (ok) return;

    // شکست همه → رفرش یک‌بار
    if (!didRefresh && _user != null && _pass != null && _userWantsOn && gen == _connectGen) {
      if (mounted) {
        setState(() => _statusLine = 'بروزرسانی اشتراک و تلاش دوباره…');
      }
      final refreshed = await _refreshSubscription(quiet: true);
      if (refreshed && _userWantsOn && gen == _connectGen) {
        await _smartConnect(isRecovery: true, didRefresh: true);
        return;
      }
    }

    if (!mounted || gen != _connectGen) return;
    if (_userWantsOn && !_verified) {
      setState(() {
        _phase = TvPhase.idle;
        _statusLine = 'اتصال برقرار نشد. دوباره امتحان کنید';
        _userWantsOn = false;
        _switchingServers = false;
      });
      _spin.stop();
    }
  }

  Future<void> _forceDisconnect({String reason = 'user'}) async {
    _userWantsOn = false;
    _recoverTimer?.cancel();
    _recoverGen++;
    _connectGen++; // باطل کردن حلقه اتصال در جریان
    _switchingServers = true;
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
    _switchingServers = false;
  }

  Future<void> _toggle() async {
    if (_isOn ||
        _userWantsOn ||
        _phase == TvPhase.connecting ||
        _phase == TvPhase.finding ||
        _phase == TvPhase.recovering) {
      await _forceDisconnect();
      return;
    }
    _userWantsOn = true;
    await _smartConnect();
  }

  /// یوتیوب بدون تبلیغ: پینگ دو مرحله‌ای فقط روی آلبانی / NO ADS
  Future<void> _connectAlbaniaYoutube() async {
    if (_isOn ||
        _phase == TvPhase.connecting ||
        _phase == TvPhase.finding ||
        _phase == TvPhase.recovering) {
      await _forceDisconnect();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (_servers.isEmpty && _user != null && _pass != null) {
      if (mounted) {
        setState(() {
          _phase = TvPhase.finding;
          _statusLine = 'دریافت فهرست سرورها…';
        });
      }
      await _login(_user!, _pass!, silent: true);
    }

    bool isAlbania(TvServer s) {
      final n = s.name.toLowerCase();
      return n.contains('alban') ||
          n.contains('آلبانی') ||
          n.contains('البانی') ||
          n.contains('🇦🇱') ||
          n.contains('no ads') ||
          n.contains('noads') ||
          n.contains('no-ads') ||
          n.contains('بدون تبلیغ') ||
          n.contains('tirana');
    }

    final candidates = _servers.where(isAlbania).toList();
    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = TvPhase.idle;
          _statusLine = 'سرور آلبانی / بدون‌تبلیغ در اشتراک نیست';
        });
      }
      return;
    }

    final gen = ++_connectGen;
    _userWantsOn = true;
    _recoverTimer?.cancel();
    if (mounted) {
      setState(() {
        _phase = TvPhase.finding;
        _verified = false;
        _statusLine = 'یوتیوب — پینگ سرور آلبانی…';
      });
    }
    _spin.duration = const Duration(seconds: 2);
    _spin.repeat();

    // پینگ دو مرحله‌ای فقط روی کاندیدها
    await Future.wait(candidates.map((s) async {
      final tcp = await _tcpPing(s.host, s.port);
      s.ping = tcp;
    }));
    final tcpOk = candidates.where((s) => s.ping > 0).toList();
    final forReal = tcpOk.isNotEmpty ? tcpOk : candidates;
    await _mapConcurrent(forReal, 3, (s) async {
      if (s.ping <= 0) return; // فقط TCP سبز
      final real = await _realPing(s);
      if (real > 0) s.ping = real;
    });
    // اگر real همه را کشت، از TCP نگه دار
    candidates.sort((a, b) {
      final pa = a.ping > 0 ? a.ping : 999999;
      final pb = b.ping > 0 ? b.ping : 999999;
      return pa.compareTo(pb);
    });

    final alive = candidates.where((s) => s.ping > 0).toList();
    final tryList = alive.isNotEmpty ? alive : candidates;

    if (mounted && gen == _connectGen) {
      setState(() {
        _statusLine = alive.isNotEmpty
            ? 'آلبانی ${alive.first.ping} ms — اتصال…'
            : 'تلاش اتصال به آلبانی…';
      });
    }

    final ok = await _tryConnectList(tryList, gen: gen, maxTries: 5);
    if (ok) {
      if (mounted) {
        setState(() => _statusLine = 'متصل به آلبانی — مناسب یوتیوب');
      }
      return;
    }

    if (mounted && gen == _connectGen) {
      _userWantsOn = false;
      _spin.stop();
      setState(() {
        _phase = TvPhase.idle;
        _statusLine = 'الان به آلبانی وصل نشد. اتصال هوشمند را بزنید.';
        _switchingServers = false;
      });
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.escape)) {
              _endSplash();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: _endSplash,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_splashReady && _splashVideo != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _splashVideo!.value.size.width,
                      height: _splashVideo!.value.size.height,
                      child: VideoPlayer(_splashVideo!),
                    ),
                  )
                else
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: kCyan),
                        SizedBox(height: 16),
                        Text(
                          'JET VPN',
                          style: TextStyle(
                              color: kCyan, fontSize: 22, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
                const Positioned(
                  bottom: 28,
                  left: 0,
                  right: 0,
                  child: Text(
                    'برای رد کردن، OK را بزنید',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
                    if (_quotaLine.isNotEmpty)
                      Text(
                        _quotaLine,
                        style: const TextStyle(color: kCyan, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _FocusBtn(
                focusNode: FocusNode(),
                onPressed: _showProfilesSheet,
                background: kCard,
                foreground: Colors.white70,
                minWidth: 88,
                minHeight: 44,
                child: const Text('اشتراک‌ها', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 6),
              _FocusBtn(
                focusNode: FocusNode(),
                onPressed: _busy
                    ? null
                    : () async {
                        await _refreshSubscription(quiet: false);
                      },
                background: kCard,
                foreground: Colors.white70,
                minWidth: 100,
                minHeight: 44,
                child: const Text('بروز سرورها', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              _FocusBtn(
                focusNode: FocusNode(),
                onPressed: () => _checkUpdate(silent: false),
                background: kCard,
                foreground: Colors.white70,
                minWidth: 80,
                minHeight: 44,
                child: const Text('آپدیت اپ', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              _FocusBtn(
                focusNode: _logoutFocus,
                onPressed: _logout,
                background: kCard,
                foreground: Colors.white70,
                minWidth: 80,
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
              '🚀 اتصال سریع و پایدار روی تلویزیون · سرور هوشمند · تونل کامل\n'
              'از ربات جت‌کانفیگ، همیشه آنلاین بمانید',
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

/// دکمه اتصال نئونی — حس سرعت و تکنولوژی
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

class _CircularConnectBtnState extends State<_CircularConnectBtn>
    with TickerProviderStateMixin {
  late final AnimationController _orbit;
  late final AnimationController _pulse;
  late final AnimationController _glow;
  late final AnimationController _dash;

  @override
  void initState() {
    super.initState();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _dash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _CircularConnectBtn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _orbit.duration = const Duration(milliseconds: 1600);
      _dash.duration = const Duration(milliseconds: 900);
      _orbit
        ..reset()
        ..repeat();
      _dash
        ..reset()
        ..repeat();
    } else if (widget.isOn && !oldWidget.isOn) {
      _orbit.duration = const Duration(milliseconds: 7000);
      _dash.duration = const Duration(milliseconds: 4500);
      _orbit
        ..reset()
        ..repeat();
      _dash
        ..reset()
        ..repeat();
    } else if (!widget.busy && !widget.isOn) {
      _orbit.duration = const Duration(milliseconds: 4800);
      _dash.duration = const Duration(milliseconds: 2800);
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    _pulse.dispose();
    _glow.dispose();
    _dash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final neon = widget.isOn ? kTeal : kCyan;
    final neon2 =
        widget.isOn ? const Color(0xFF7CFFB2) : const Color(0xFF5B8CFF);
    final core = widget.isOn ? kTealDeep : kCyanDeep;

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
          return AnimatedBuilder(
            animation:
                Listenable.merge([_orbit, _pulse, _glow, _dash, widget.spin]),
            builder: (context, _) {
              final pulse = 0.92 + (_pulse.value * 0.08);
              final glowOp = 0.22 + (_glow.value * 0.38);
              final scale = focused ? 1.07 : 1.0;
              return Transform.scale(
                scale: scale,
                child: GestureDetector(
                  onTap: widget.onPressed,
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 200 * pulse,
                          height: 200 * pulse,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                neon.withOpacity(glowOp * 0.5),
                                neon2.withOpacity(glowOp * 0.15),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.42, 1.0],
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: _orbit.value * math.pi * 2,
                          child: CustomPaint(
                            size: const Size(188, 188),
                            painter: _OrbitDotsPainter(
                              color: neon.withOpacity(0.95),
                              color2: neon2.withOpacity(0.75),
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: -_dash.value * math.pi * 2,
                          child: CustomPaint(
                            size: const Size(176, 176),
                            painter: _NeonArcsPainter(
                              color: neon,
                              color2: neon2,
                              active: widget.busy || widget.isOn,
                            ),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(158, 158),
                          painter: _GradientRingPainter(
                            colors: [neon, neon2, neon.withOpacity(0.15)],
                          ),
                        ),
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                neon.withOpacity(0.98),
                                core,
                                neon2.withOpacity(0.9),
                              ],
                              stops: const [0.0, 0.52, 1.0],
                            ),
                            border: Border.all(
                              color: focused
                                  ? Colors.white.withOpacity(0.95)
                                  : Colors.white.withOpacity(0.35),
                              width: focused ? 3.0 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: neon.withOpacity(0.55),
                                blurRadius: 28,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: neon2.withOpacity(0.35),
                                blurRadius: 42,
                                spreadRadius: -4,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.3),
                                      Colors.transparent,
                                    ],
                                    center: const Alignment(-0.45, -0.55),
                                    radius: 0.9,
                                  ),
                                ),
                              ),
                              Icon(
                                widget.busy && !widget.isOn
                                    ? Icons.bolt_rounded
                                    : Icons.power_settings_new_rounded,
                                size: widget.busy && !widget.isOn ? 52 : 56,
                                color: Colors.white.withOpacity(0.96),
                                shadows: [
                                  Shadow(
                                    color: neon.withOpacity(0.85),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _OrbitDotsPainter extends CustomPainter {
  final Color color;
  final Color color2;
  _OrbitDotsPainter({required this.color, required this.color2});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    for (var i = 0; i < 14; i++) {
      final a = (i / 14) * math.pi * 2;
      final op = 0.3 + (i % 3) * 0.22;
      final paint = Paint()
        ..color = (i.isEven ? color : color2).withOpacity(op.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      canvas.drawCircle(p, i % 4 == 0 ? 3.4 : 2.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitDotsPainter old) =>
      old.color != color || old.color2 != color2;
}

class _NeonArcsPainter extends CustomPainter {
  final Color color;
  final Color color2;
  final bool active;
  _NeonArcsPainter({
    required this.color,
    required this.color2,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);

    final p1 = Paint()
      ..color = color.withOpacity(active ? 0.95 : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 4.8 : 3.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, active ? 3 : 1.5);

    final p2 = Paint()
      ..color = color2.withOpacity(active ? 0.88 : 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 3.6 : 2.4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawArc(rect, -0.25, 1.15, false, p1);
    canvas.drawArc(rect, 1.9, 0.95, false, p2);
    canvas.drawArc(rect, 3.7, 0.75, false, p1);
  }

  @override
  bool shouldRepaint(covariant _NeonArcsPainter old) =>
      old.active != active || old.color != color;
}

class _GradientRingPainter extends CustomPainter {
  final List<Color> colors;
  _GradientRingPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter old) => false;
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
