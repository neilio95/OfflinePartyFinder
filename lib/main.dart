import 'dart:async';
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
    return MaterialApp(
      title: 'Offline Party Finder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF101614)),
        useMaterial3: true,
      ),
      home: const PartyHomePage(),
    );
  }
}

class PartyHomePage extends StatefulWidget {
  const PartyHomePage({super.key});

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

  @override
  void initState() {
    super.initState();
    _mesh = MeshNetwork(
      config: MeshConfig(serviceName: 'PartyFinder'),
    );
    _requestPermissions();
    _messageSub = _mesh.onMessage.listen((msg) {
      setState(() => _messages.insert(0, msg));
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
        await _mesh.start(userId: 'user-${DateTime.now().millisecondsSinceEpoch}', userName: 'You');
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
      _myPosition = pos;
      _mesh.broadcastLocation(latitude: pos.latitude, longitude: pos.longitude);
    });
  }

  Future<void> _sendSos() async {
    if (!_running || _myPosition == null) return;
    await _mesh.sendSos(latitude: _myPosition!.latitude, longitude: _myPosition!.longitude);
  }

  Future<void> _sendText(String text) async {
    if (!_running || text.trim().isEmpty) return;
    await _mesh.sendText(text);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _nodeSub?.cancel();
    _mesh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peers = _mesh.knownNodes.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_running ? 'Party Finder (${_mesh.onlineNodeCount} peers)' : 'Party Finder'),
        actions: [
          IconButton(
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            onPressed: _toggleMesh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_myPosition != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'You: ${_myPosition!.latitude.toStringAsFixed(5)}, ${_myPosition!.longitude.toStringAsFixed(5)}',
              ),
            ),
          Expanded(
            flex: 2,
            child: peers.isEmpty
                ? const Center(child: Text('No peers yet — start mesh and get closer'))
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (context, i) {
                      final p = peers[i];
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text(p.status.name),
                      );
                    },
                  ),
          ),
          const Divider(),
          Expanded(
            flex: 1,
            child: _messages.isEmpty
                ? const Center(child: Text('No messages'))
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      return ListTile(
                        leading: Icon(
                          m.type == MessageType.sos ? Icons.warning : Icons.message,
                          color: m.type == MessageType.sos ? Colors.red : null,
                        ),
                        title: Text(m.payload),
                        subtitle: Text('${m.senderName} • hop ${m.hopCount}'),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Message'),
                    onSubmitted: _sendText,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.warning, color: Colors.red),
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
