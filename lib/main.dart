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
  final MeshNetwork _mesh = MeshNetwork();
  final List<MeshPeer> _peers = [];
  final List<String> _chat = [];
  StreamSubscription? _peerSub;
  StreamSubscription? _msgSub;
  Position? _myPosition;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
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

  Future<void> _startMesh() async {
    if (_running) return;
    setState(() => _running = true);

    await _mesh.start(
      serviceName: 'OfflinePartyFinder',
      onPeerFound: (peer) {
        setState(() {
          if (!_peers.any((p) => p.id == peer.id)) _peers.add(peer);
        });
      },
      onPeerLost: (peer) {
        setState(() => _peers.removeWhere((p) => p.id == peer.id));
      },
      onMessage: (from, message) {
        setState(() => _chat.add('${from.displayName}: $message'));
      },
    );

    _startLocationUpdates();
  }

  Future<void> _startLocationUpdates() async {
    final loc = GeolocatorPlatform.instance;
    _myPosition = await loc.getCurrentPosition();
    loc.getPositionStream().listen((pos) {
      _myPosition = pos;
      _mesh.broadcastLocation(pos.latitude, pos.longitude);
    });
  }

  void _sendSos() {
    _mesh.sendSos('SOS — need help');
    setState(() => _chat.add('You: SOS sent'));
  }

  void _sendChat(String text) {
    if (text.trim().isEmpty) return;
    _mesh.sendText(text);
    setState(() => _chat.add('You: $text'));
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _msgSub?.cancel();
    _mesh.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Finder'),
        actions: [
          IconButton(
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            onPressed: _running ? () => _mesh.stop() : _startMesh,
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
            child: ListView.builder(
              itemCount: _peers.length,
              itemBuilder: (context, i) {
                final p = _peers[i];
                return ListTile(
                  title: Text(p.displayName),
                  subtitle: Text(p.distanceMeters != null
                      ? '${p.distanceMeters!.toStringAsFixed(0)} m'
                      : 'nearby'),
                );
              },
            ),
          ),
          const Divider(),
          Expanded(
            flex: 1,
            child: ListView.builder(
              itemCount: _chat.length,
              itemBuilder: (context, i) => ListTile(title: Text(_chat[i])),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Message'),
                    onSubmitted: _sendChat,
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
