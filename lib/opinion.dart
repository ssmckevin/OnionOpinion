import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'leaderboard.dart';

class OpinionScreen extends StatefulWidget {
  final String partyCode;
  const OpinionScreen({Key? key, required this.partyCode}) : super(key: key);

  @override
  _OpinionScreenState createState() => _OpinionScreenState();
}

class _OpinionScreenState extends State<OpinionScreen> {
  final TextEditingController _opinionController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSubmitting = false;
  StreamSubscription<DocumentSnapshot>? _partySubscription;

  @override
  void initState() {
    super.initState();
    _listenForRoleChange();
  }

  @override
  void dispose() {
    _opinionController.dispose();
    _partySubscription?.cancel();
    super.dispose();
  }

  void _listenForRoleChange() {
    _partySubscription = _firestore.collection('parties').doc(widget.partyCode)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;

      final data = snapshot.data()!;

      // Check if game is over
      if (data['gameCompleted'] == true) {
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
        return;
      }

      final players = List<Map<String, dynamic>>.from(data['players'] ?? []);
      final currentUserId = _auth.currentUser?.uid;

      if (currentUserId != null) {
        final isStillHost = players.any((p) =>
        p['id'] == currentUserId && p['isHost'] == true);

        if (!isStillHost && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pushReplacementNamed(
            context,
            '/voting',
            arguments: {'partyCode': widget.partyCode},
          );
        }
      }
    });
  }

  Future<void> _submitOpinion() async {
    String opinion = _opinionController.text.trim();
    if (opinion.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      // Get current party data
      final partyDoc = await _firestore.collection('parties').doc(widget.partyCode).get();
      final players = List<Map<String, dynamic>>.from(partyDoc['players'] ?? []);

      // Update host's opinion and mark as submitted
      final updatedPlayers = players.map((player) {
        if (player['id'] == currentUserId) {
          return {
            ...player,
            'hasSubmittedOpinion': true,
          };
        }
        return player;
      }).toList();

      await _firestore.collection('parties').doc(widget.partyCode).update({
        'opinion': opinion,
        'players': updatedPlayers,
        'currentPhase': 'voting',
      });

      // Host remains on this screen until role changes
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Submit Opinion")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _opinionController,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: "Enter your opinion",
                border: OutlineInputBorder(),
                hintText: "Keep it under 500 characters",
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitOpinion,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator()
                  : const Text("Submit Opinion"),
            ),
          ],
        ),
      ),
    );
  }
}