import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_mesh_network/flutter_mesh_network.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

void main() {
  runApp(const OfflinePartyFinderApp());
}

class OfflinePartyFinderApp extends StatelessWidget {
  const OfflinePartyFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const nearBlack = Color(0xFF101614);
    const copper = Color(0xFFE09A3E);
    const cream = Color(0xFFEFE8D8);

    return MaterialApp(
      title: 'Party Finder',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: nearBlack,
        colorScheme: const ColorScheme.dark(
          primary: copper,
          secondary: copper,
          surface: Color(0xFF1A221C),
          onSurface: cream,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: nearBlack,
          foregroundColor: cream,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const NameAndCodePage(),
    );
  }
}

class NameAndCodePage extends StatefulWidget {
  const NameAndCodePage({super.key});

  @override
  State<NameAndCodePage> createState() => _NameAndCodePageState();
}

class _NameAndCodePageState extends State<NameAndCodePage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController(text: 'PARTY');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Text(
                'Party Finder',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: const Color(0xFFE09A3E),
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Find your people offline',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFEFE8D8)),
              ),
              const Spacer(),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Party code',
                  helperText: 'Share this code with your group',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  final name = _nameController.text.trim();
                  final code = _codeController.text.trim().toUpperCase();
                  if (name.isEmpty || code.isEmpty) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => PartyHomePage(userName: name, partyCode: code),
                    ),
                  );
                },
                child: const Text('Join Party'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class PartyHomePage extends StatefulWidget {
  final String userName;
  final String partyCode;

  const PartyHomePage({super.key, required this.userName, required this.partyCode});

  @override
  State<PartyHomePage> createState() => _PartyHomePageState();
}

class _PartyHomePageState extends State<PartyHomePage> {
  late final MeshNetwork _mesh;
  final AudioPlayer _alarmPlayer = AudioPlayer();

  final List<MeshMessage> _messages = [];
  StreamSubscription<MeshMessage>? _messageSub;
  StreamSubscription<MeshNode>? _nodeSub;
  Position? _myPosition;
  bool _running = false;
  final _textController = TextEditingController();

  static const _sosOptions = [
    ('Lost', 'I\'m lost — please find me'),
    ('Help', 'I need help'),
    ('Medical', 'Medical emergency'),
    ('Uncomfortable', 'I feel unsafe / uncomfortable'),
    ('Meet up', 'Can we meet up?'),
    ('Phone dying', 'My phone is dying'),
  ];

  @override
  void initState() {
    super.initState();
    final serviceName = 'PF-${widget.partyCode}'.substring(0, math.min(15, 'PF-${widget.partyCode}'.length));
    _mesh = MeshNetwork(config: MeshConfig(serviceName: serviceName));
    _requestPermissions();
    _messageSub = _mesh.onMessage.listen((msg) {
      setState(() => _messages.insert(0, msg));
      if (msg.type == MessageType.sos) {
        _triggerSosAlert(msg.senderName, msg.payload);
      }
    });
    _nodeSub = _mesh.onNodeChanged.listen((_) => setState(() {}));
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();
  }

  Future<void> _triggerSosAlert(String fromName, String reason) async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 800], intensities: [0, 255, 0, 255, 0, 255]);
    }

    try {
      await _alarmPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      await _alarmPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/alarm_clock.ogg'));
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SOS from $fromName: $reason'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  Future<void> _toggleMesh() async {
    try {
      if (_running) {
        await _mesh.stop();
      } else {
        await _mesh.start(
          userId: 'user-${DateTime.now().millisecondsSinceEpoch}',
          userName: widget.userName,
        );
        _startLocationUpdates();
      }
      setState(() => _running = _mesh.isRunning);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mesh error: $e')));
      }
    }
  }

  Future<void> _startLocationUpdates() async {
    final loc = GeolocatorPlatform.instance;
    _myPosition = await loc.getCurrentPosition();
    loc.getPositionStream().listen((pos) {
      setState(() => _myPosition = pos);
      _mesh.broadcastLocation(latitude: pos.latitude, longitude: pos.longitude);
    });
  }

  double? _distanceTo(MeshNode node) {
    if (_myPosition == null || node.latitude == null || node.longitude == null) return null;
    return Geolocator.distanceBetween(
      _myPosition!.latitude,
      _myPosition!.longitude,
      node.latitude!,
      node.longitude!,
    );
  }

  double? _bearingTo(MeshNode node) {
    if (_myPosition == null || node.latitude == null || node.longitude == null) return null;
    final lat1 = _myPosition!.latitude * math.pi / 180;
    final lon1 = _myPosition!.longitude * math.pi / 180;
    final lat2 = node.latitude! * math.pi / 180;
    final lon2 = node.longitude! * math.pi / 180;
    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  String _cardinal(double? bearing) {
    if (bearing == null) return '';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((bearing + 22.5) / 45).floor() % 8;
    return dirs[idx];
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '—';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  void _showSosOptions() {
    if (!_running || _myPosition == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A221C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Send SOS',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ..._sosOptions.map((opt) => ListTile(
                    title: Text(opt.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(opt.$2),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _mesh.sendSos(
                        latitude: _myPosition!.latitude,
                        longitude: _myPosition!.longitude,
                      );
                      await _mesh.sendText('SOS: ${opt.$2}');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('SOS sent: ${opt.$1}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _textController.text;
    if (!_running || text.trim().isEmpty) return;
    await _mesh.sendText(text);
    _textController.clear();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _nodeSub?.cancel();
    _textController.dispose();
    _alarmPlayer.dispose();
    _mesh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peers = _mesh.knownNodes.values.toList();
    const copper = Color(0xFFE09A3E);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Party Finder'),
            Text(
              'Code: ${widget.partyCode}  •  ${peers.length} in party',
              style: const TextStyle(fontSize: 12, color: Color(0xFFEFE8D8)),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _toggleMesh,
              style: FilledButton.styleFrom(
                backgroundColor: _running ? Colors.redAccent : copper,
                foregroundColor: const Color(0xFF101614),
              ),
              child: Text(_running ? 'Stop' : 'Start Party'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: peers.isEmpty
                  ? Center(
                      child: Text(
                        _running
                            ? 'Searching for nearby party members...\nStay close'
                            : 'Tap Start Party to find people nearby',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: peers.length,
                      itemBuilder: (context, i) {
                        final p = peers[i];
                        final dist = _distanceTo(p);
                        final bearing = _bearingTo(p);
                        final isActive = p.status == NodeStatus.active;
                        final dir = _cardinal(bearing);
                        final subtitle = isActive
                            ? _formatDistance(dist)
                            : 'Last seen ${_formatDistance(dist)}${dir.isNotEmpty ? ' • $dir' : ''}';
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          color: const Color(0xFF1A221C),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: copper,
                              child: Text(
                                p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                style: const TextStyle(color: Color(0xFF101614), fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(subtitle),
                            trailing: isActive
                                ? const Icon(Icons.circle, color: Colors.greenAccent, size: 16)
                                : const Icon(Icons.navigation, color: Colors.grey, size: 20),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Expanded(
              flex: 1,
              child: _messages.isEmpty
                  ? const Center(child: Text('No messages yet'))
                  : ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final isSos = m.type == MessageType.sos || m.payload.startsWith('SOS:');
                        return ListTile(
                          leading: Icon(
                            isSos ? Icons.warning_amber_rounded : Icons.chat_bubble_outline,
                            color: isSos ? Colors.redAccent : copper,
                          ),
                          title: Text(
                            m.senderName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            m.payload,
                            style: TextStyle(
                              color: isSos ? Colors.redAccent : null,
                              fontWeight: isSos ? FontWeight.bold : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_running)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                color: const Color(0xFF101614),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Message the party',
                          filled: true,
                          fillColor: const Color(0xFF1A221C),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        onSubmitted: (_) => _sendText(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: copper),
                      icon: const Icon(Icons.send, color: Color(0xFF101614)),
                      onPressed: _sendText,
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
                      icon: const Icon(Icons.sos),
                      onPressed: _showSosOptions,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
