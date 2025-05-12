import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:test1/party.dart';
import 'package:test1/signIn.dart';
import 'package:test1/signUp.dart';
import 'package:test1/vote_screen.dart';
import 'package:test1/opinion.dart';

import 'leaderboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpinionOnion',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.deepPurple.shade200,
        primarySwatch: Colors.deepPurple,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple.shade400),
        useMaterial3: true,
      ),
      initialRoute: '/signin',
      routes: {
        '/signup': (context) => const SignUpScreen(),
        '/signin': (context) => const SignInScreen(),
        '/party': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return PartyScreen(key: args?['key']);
        },
        '/voting': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
          return VoteScreen(partyCode: args['partyCode']);
        },
        '/opinion': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
          return OpinionScreen(partyCode: args['partyCode']);
        },
        '/leaderboard': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
          return LeaderboardScreen(partyCode: args['partyCode']);
        },
      },
    );
  }
}