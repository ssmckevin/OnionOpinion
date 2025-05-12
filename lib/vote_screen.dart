import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'leaderboard.dart';

class VoteScreen extends StatefulWidget {
  final String partyCode;
  const VoteScreen({super.key, required this.partyCode});

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _hasVoted = false;
  bool _isUpdating = false;
  StreamSubscription<DocumentSnapshot>? _partySubscription;

  @override
  void initState() {
    super.initState();
    _listenToPartyUpdates();
  }

  @override
  void dispose() {
    _partySubscription?.cancel();
    super.dispose();
  }

  // Add this method to handle game completion
  void _handleGameCompletion() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LeaderboardScreen(partyCode: widget.partyCode),
          ),
        );
      }
    });
  }

  Future<void> _vote(bool agree) async {
    if (_hasVoted) return;

    setState(() => _isUpdating = true);

    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      final partyDoc = await _firestore.collection('parties').doc(widget.partyCode).get();
      final players = List<Map<String, dynamic>>.from(partyDoc['players'] ?? []);

      // Update points if agreed
      if (agree) {
        final hostIndex = players.indexWhere((p) => p['isHost'] == true);
        if (hostIndex != -1) {
          players[hostIndex]['points'] = (players[hostIndex]['points'] ?? 0) + 1;
        }
      }

      // Mark voter as done
      final updatedPlayers = players.map((player) {
        if (player['id'] == currentUserId) {
          return {
            ...player,
            'hasVoted': true,
          };
        }
        return player;
      }).toList();

      await _firestore.collection('parties').doc(widget.partyCode).update({
        'players': updatedPlayers,
      });

      setState(() => _hasVoted = true);

      // Check if all players have completed their turn
      final allCompleted = updatedPlayers.every((player) =>
      (player['isHost'] && player['hasSubmittedOpinion'] == true) ||
          (!player['isHost'] && player['hasVoted'] == true));

      if (allCompleted) {
        await _rotateHost(updatedPlayers);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vote failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _rotateHost(List<Map<String, dynamic>> players) async {
    try {
      final partyDoc = await _firestore.collection('parties').doc(widget.partyCode).get();
      final currentRound = partyDoc['currentRound'] ?? 1;
      final totalRounds = partyDoc['totalRounds'] ?? 3;
      final currentHostIndex = partyDoc['currentHostIndex'] ?? 0;

      final nextHostIndex = (currentHostIndex + 1) % players.length;
      final isNewRound = nextHostIndex == 0;
      final newRound = isNewRound ? currentRound + 1 : currentRound;

      // Check if game should end
      if (isNewRound && newRound > totalRounds) {
        await _firestore.collection('parties').doc(widget.partyCode).update({
          'gameCompleted': true,
          'currentPhase': 'completed',
        });
        _handleGameCompletion();
        return;
      }

      // Update roles
      final rotatedPlayers = players.map((player) {
        final isNewHost = player['id'] == players[nextHostIndex]['id'];
        return {
          ...player,
          'isHost': isNewHost,
          'hasVoted': isNewHost,
          'hasSubmittedOpinion': false,
        };
      }).toList();

      await _firestore.collection('parties').doc(widget.partyCode).update({
        'players': rotatedPlayers,
        'hostId': players[nextHostIndex]['id'],
        'currentHostIndex': nextHostIndex,
        'currentRound': newRound,
        'opinion': '',
        'currentPhase': 'opinion',
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Host rotation failed: ${e.toString()}')),
      );
    }
  }

  void _listenToPartyUpdates() {
    _partySubscription = _firestore.collection('parties').doc(widget.partyCode)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data()!;
      final gameCompleted = data['gameCompleted'] ?? false;
      final players = List<Map<String, dynamic>>.from(data['players'] ?? []);
      final currentUserId = _auth.currentUser?.uid;

      if (gameCompleted) {
        _handleGameCompletion();
        return;
      }

      if (currentUserId != null) {
        final isHost = players.any((p) => p['id'] == currentUserId && p['isHost'] == true);
        final hasVoted = players.any((p) => p['id'] == currentUserId && p['hasVoted'] == true);

        if (mounted) {
          setState(() {
            _hasVoted = hasVoted;
          });
        }

        if (isHost && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pushReplacementNamed(
            context,
            '/opinion',
            arguments: {'partyCode': widget.partyCode},
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Voting Screen"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('parties').doc(widget.partyCode).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Party not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final players = List<Map<String, dynamic>>.from(data['players'] ?? []);
          final opinion = data['opinion'] ?? 'No opinion submitted yet';
          final currentHost = players.firstWhere(
                (p) => p['isHost'] == true,
            orElse: () => {'name': 'Unknown', 'points': 0},
          );

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('Host: ${currentHost['name']}'),
                        const SizedBox(height: 10),
                        Text('Opinion: $opinion'),
                        const SizedBox(height: 10),
                        Text('Points: ${currentHost['points'] ?? 0}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (!_hasVoted) ...[
                  const Text('Do you agree?'),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _isUpdating ? null : () => _vote(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          minimumSize: const Size(120, 50),
                        ),
                        child: _isUpdating
                            ? const CircularProgressIndicator()
                            : const Text("Agree"),
                      ),
                      ElevatedButton(
                        onPressed: _isUpdating ? null : () => _vote(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          minimumSize: const Size(120, 50),
                        ),
                        child: _isUpdating
                            ? const CircularProgressIndicator()
                            : const Text("Disagree"),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text('You have voted!', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 10),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  const Text('Waiting for others...'),
                ],
                const SizedBox(height: 20),
                const Text('Leaderboard:', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(player['name'][0]),
                        ),
                        title: Text(player['name']),
                        trailing: Text('${player['points'] ?? 0} pts'),
                        tileColor: player['isHost'] == true
                            ? Colors.deepPurple.withOpacity(0.1)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}