import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardScreen extends StatelessWidget {
  final String partyCode;
  const LeaderboardScreen({Key? key, required this.partyCode}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Results'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('parties').doc(partyCode).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Game session has ended'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/party',
                            (route) => false,
                      );
                    },
                    child: const Text('Return to Home'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final players = List<Map<String, dynamic>>.from(data['players'] ?? []);

          // Sort players by points (descending)
          players.sort((a, b) => (b['points'] ?? 0).compareTo(a['points'] ?? 0));

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text(
                  'Final Scores',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: index == 0 ? Colors.amber : Colors.deepPurple,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(player['name']),
                          trailing: Text(
                            '${player['points'] ?? 0} pts',
                            style: const TextStyle(fontSize: 18),
                          ),
                          tileColor: index == 0 ? Colors.green[50] : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  players.isNotEmpty ? 'Winner: ${players[0]['name']}' : '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/party',
                            (route) => false,
                      );
                    },
                    child: const Text('Return to Home'),
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