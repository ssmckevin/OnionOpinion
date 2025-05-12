import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math';
import 'leaderboard.dart'; // Make sure to import your LeaderboardScreen

class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  final TextEditingController _joinCodeController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _partyCode;
  bool _isInParty = false;
  String? _message;
  bool _isHost = false;
  List<Map<String, dynamic>> _partyMembers = [];
  int _selectedRounds = 3;
  bool _isCreatingParty = false;
  bool _isJoiningParty = false;

  StreamSubscription<DocumentSnapshot>? _partySubscription;

  String get _currentUserId => _auth.currentUser?.uid ?? 'guest_${Random().nextInt(9999)}';

  @override
  void dispose() {
    _joinCodeController.dispose();
    _usernameController.dispose();
    _partySubscription?.cancel();
    super.dispose();
  }

  String _generateRandomUsername() {
    const adjectives = ['Cool', 'Fast', 'Sneaky', 'Blue', 'Smart', 'Crazy'];
    const nouns = ['Tiger', 'Falcon', 'Wolf', 'Panda', 'Dragon', 'Sloth'];
    final rand = Random();
    return '${adjectives[rand.nextInt(adjectives.length)]}${nouns[rand.nextInt(nouns.length)]}${rand.nextInt(100)}';
  }

  String _generatePartyCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(Random().nextInt(chars.length))),
    );
  }

  Future<void> _createParty() async {
    setState(() {
      _isCreatingParty = true;
      _message = null;
    });

    try {
      final newCode = _generatePartyCode();
      final username = _usernameController.text.trim().isEmpty
          ? _generateRandomUsername()
          : _usernameController.text.trim();

      // Delete any existing parties hosted by this user
      final existing = await _firestore
          .collection('parties')
          .where('hostId', isEqualTo: _currentUserId)
          .get();

      for (var doc in existing.docs) {
        await _firestore.collection('parties').doc(doc.id).delete();
      }

      await _firestore.collection('parties').doc(newCode).set({
        'hostId': _currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'players': [
          {
            'id': _currentUserId,
            'name': username,
            'isHost': true,
            'hasVoted': false,
            'points': 0,
          }
        ],
        'totalRounds': _selectedRounds,
        'currentRound': 1,
        'currentHostIndex': 0,
        'gamePhase': 'lobby',
        'opinion': '',
        'gameCompleted': false,
      });

      _setPartyState(newCode, username, isHost: true);
    } catch (e) {
      setState(() {
        _message = 'Failed to create party: ${e.toString()}';
      });
    } finally {
      setState(() => _isCreatingParty = false);
    }
  }

  Future<void> _joinParty() async {
    setState(() {
      _isJoiningParty = true;
      _message = null;
    });

    try {
      final code = _joinCodeController.text.trim().toUpperCase();
      if (code.isEmpty) {
        setState(() => _message = 'Please enter a code');
        return;
      }

      final username = _usernameController.text.trim().isEmpty
          ? _generateRandomUsername()
          : _usernameController.text.trim();

      final docRef = _firestore.collection('parties').doc(code);
      final doc = await docRef.get();

      if (!doc.exists) {
        setState(() => _message = 'Party not found');
        return;
      }

      if (doc['gameCompleted'] == true) {
        setState(() => _message = 'This game has already ended');
        return;
      }

      final players = List<Map<String, dynamic>>.from(doc['players'] ?? []);
      final alreadyJoined = players.any((p) => p['id'] == _currentUserId);

      if (!alreadyJoined) {
        await docRef.update({
          'players': FieldValue.arrayUnion([
            {
              'id': _currentUserId,
              'name': username,
              'isHost': false,
              'hasVoted': false,
              'points': 0,
            }
          ])
        });
      }

      _setPartyState(code, username, isHost: doc['hostId'] == _currentUserId);
    } catch (e) {
      setState(() {
        _message = 'Failed to join: ${e.toString()}';
      });
    } finally {
      setState(() => _isJoiningParty = false);
    }
  }

  void _setPartyState(String code, String username, {required bool isHost}) {
    if (!mounted) return;

    setState(() {
      _partyCode = code;
      _message = "Joined party: $code";
      _isInParty = true;
      _isHost = isHost;
      _partyMembers = [
        {
          'id': _currentUserId,
          'name': username,
          'isHost': isHost,
        }
      ];
    });

    _listenToPartyUpdates(code);
  }

  void _listenToPartyUpdates(String code) {
    _partySubscription?.cancel();

    _partySubscription = _firestore.collection('parties').doc(code).snapshots().listen((snapshot) async {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data()!;
      final gameCompleted = data['gameCompleted'] ?? false;

      // Navigate to leaderboard when game is completed
      if (gameCompleted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pushReplacementNamed(
          context,
          '/leaderboard',
          arguments: {'partyCode': code},
        );
        return;
      }

      final players = List<Map<String, dynamic>>.from(data['players'] ?? []);
      final hostId = data['hostId'];
      final gameStarted = data['gameStarted'] ?? false;
      final currentRound = data['currentRound'] ?? 1;
      final totalRounds = data['totalRounds'] ?? 3;

      players.sort((a, b) => (a['id'] == hostId ? -1 : (b['id'] == hostId ? 1 : 0)));

      if (mounted) {
        setState(() {
          _partyMembers = players;
          _selectedRounds = totalRounds;
        });
      }

      if (gameStarted && ModalRoute.of(context)?.isCurrent == true) {
        final isHost = _auth.currentUser?.uid == hostId;
        if (isHost) {
          Navigator.pushReplacementNamed(
            context,
            '/opinion',
            arguments: {'partyCode': code},
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            '/voting',
            arguments: {'partyCode': code},
          );
        }
      }
    });
  }

  Future<void> _startParty() async {
    if (_partyCode == null) return;

    try {
      await _firestore.collection('parties').doc(_partyCode).update({
        'gameStarted': true,
        'currentRound': 1,
        'currentHostIndex': 0,
        'gamePhase': 'opinion',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: ${e.toString()}')),
        );
      }
    }
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Game Over'),
        content: const Text('All rounds completed! View the final results.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => LeaderboardScreen(partyCode: _partyCode!),
                ),
              );
            },
            child: const Text('View Leaderboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) Navigator.pushReplacementNamed(context, '/signin');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Party Lobby"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Username (optional)",
                border: OutlineInputBorder(),
                hintText: "Leave blank for random name",
              ),
            ),
            if (_isHost || !_isInParty) ...[
              const SizedBox(height: 20),
              const Text("Number of Rounds:"),
              Slider(
                value: _selectedRounds.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: _selectedRounds.toString(),
                onChanged: _isInParty ? null : (value) {
                  setState(() {
                    _selectedRounds = value.toInt();
                  });
                },
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isCreatingParty ? null : _createParty,
                child: _isCreatingParty
                    ? const CircularProgressIndicator()
                    : const Text("Create New Party"),
              ),
            ),
            if (_partyCode != null) ...[
              const SizedBox(height: 20),
              const Text(
                "Share this code:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _partyCode!,
                style: const TextStyle(fontSize: 32, letterSpacing: 3),
                textAlign: TextAlign.center,
              ),
            ],
            const Divider(height: 40),
            TextField(
              controller: _joinCodeController,
              decoration: const InputDecoration(
                labelText: "Enter Party Code",
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isJoiningParty ? null : _joinParty,
                child: _isJoiningParty
                    ? const CircularProgressIndicator()
                    : const Text("Join Party"),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 20),
              Text(
                _message!,
                style: TextStyle(
                  color: _message!.contains('Failed') ? Colors.red : Colors.green,
                ),
              ),
            ],
            if (_isInParty) ...[
              const SizedBox(height: 30),
              const Text(
                "Party Members:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _partyMembers.length,
                itemBuilder: (context, index) {
                  final member = _partyMembers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(member['name'][0]),
                    ),
                    title: Text(member['name']),
                    trailing: member['isHost']
                        ? const Chip(
                      label: Text("Host"),
                      backgroundColor: Colors.deepPurple,
                      labelStyle: TextStyle(color: Colors.white),
                    )
                        : null,
                  );
                },
              ),
              if (_isHost && _partyMembers.length > 1) ...[
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _startParty,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: const Text(
                      "Start Game",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}