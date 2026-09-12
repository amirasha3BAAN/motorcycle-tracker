import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/motorcycle_provider.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/map_screen.dart';
import 'core/notifications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // If real Firebase environment were active, you would run:
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MotorcycleProvider()),
      ],
      child: const MotoSentryApp(),
    ),
  );
}

class MotoSentryApp extends StatelessWidget {
  const MotoSentryApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoSentry Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE50914), // Racing Red accent
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Colors.redAccent,
          secondary: Colors.blueAccent,
          background: Color(0xFF121212),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final FCMNotificationService _notificationService = FCMNotificationService();

  final List<Widget> _screens = const [
    MapScreen(),
    DashboardScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'LIVE MAP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize_outlined),
            activeIcon: Icon(Icons.dashboard_customize),
            label: 'DASHBOARD',
          ),
        ],
      ),
    );
  }
}
