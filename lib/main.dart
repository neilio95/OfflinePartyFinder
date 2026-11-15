import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_mesh_network/flutter_mesh_network.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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

  final List<MeshMessage> _messages = [];
  StreamSubscription<MeshMessage>? _messageSub;
  StreamSubscription<MeshNode>? _nodeSub;
  Position? _myPosition;
  bool _running = false;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final serviceName = 'PF-${widget.partyCode}'.substring(0, math.min(15, 'PF-${widget.partyCode}'.length));
    _mesh = MeshNetwork(config: MeshConfig(serviceName: serviceName));
    _requestPermissions();
    _messageSub = _mesh.onMessage.listen((msg) {
      setState(() => _messages.insert(0, msg));
      if (msg.type == MessageType.sos) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS from ${msg.senderName}!'),
            backgroundColor: Colors.red,
          ),
        );
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
    ].request();
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

  String _formatDistance(double? meters) {
    if (meters == null) return '—';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _sendSos() async {
    if (!_running || _myPosition == null) return;
    await _mesh.sendSos(latitude: _myPosition!.latitude, longitude: _myPosition!.longitude);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS sent to the party'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendText(String text) async {
    if (!_running || text.trim().isEmpty) return;
    await _mesh.sendText(text);
    _textController.clear();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _nodeSub?.cancel();
    _textController.dispose();
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
              'Code: ${widget.partyCode}  •  ${peers.length} nearby',
              style: const TextStyle(fontSize: 12, color: Color(0xFFEFE8D8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_running ? Icons.stop_circle : Icons.play_circle, color: copper, size: 32),
            onPressed: _toggleMesh,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: peers.isEmpty
                ? const Center(
                    child: Text(
                      'No one nearby yet\nStart the mesh and stay close',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (context, i) {
                      final p = peers[i];
                      final dist = _distanceTo(p);
                      final isActive = p.status == NodeStatus.active;
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
                          subtitle: Text(_formatDistance(dist)),
                          trailing: Icon(
                            isActive ? Icons.circle : Icons.circle_outlined,
                            color: isActive ? Colors.greenAccent : Colors.grey,
                            size: 16,
                          ),
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
                      final isSos = m.type == MessageType.sos;
                      return ListTile(
                        leading: Icon(
                          isSos ? Icons.warning_amber_rounded : Icons.chat_bubble_outline,
                          color: isSos ? Colors.redAccent : copper,
                        ),
                        title: Text(
                          m.payload,
                          style: TextStyle(color: isSos ? Colors.redAccent : null, fontWeight: isSos ? FontWeight.bold : null),
                        ),
                        subtitle: Text(m.senderName),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
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
                    onSubmitted: _sendText,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
                  icon: const Icon(Icons.sos),
                  onPressed: _sendSos,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
