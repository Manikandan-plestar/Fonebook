import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../models/user_session.dart';
import 'home_screen.dart';
import 'recent_screen.dart';
import 'my_contacts_screen.dart';
import 'profile_list_screen.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;
  final bool showProfileList;
  const AppShell({super.key, this.initialIndex = 1, this.showProfileList = false});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 1;
  final api = ApiClient();
  final store = SessionStore();
  UserSession _session = const UserSession();

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _refresh();
    store.addListener(_refresh);
  }

  @override
  void dispose() {
    store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => store.read().then((s) => setState(() => _session = s));

  Future<void> _handlePop() async {
    final navState = _navigatorKeys[_index].currentState;
    if (navState != null && await navState.maybePop()) {
      return;
    }

    if (_index != 1) {
      setState(() => _index = 1);
      return;
    }

    await SystemNavigator.pop();
  }

  Color _getSelectedColor(int index) {
    if (index == 1) return const Color(0xFFD7A007); // Search: Warm Gold
    return const Color(0xFF4C5B8F); // Calls & Contacts: Primary Slate Navy
  }

  Color _getPillColor(int index) {
    if (index == 1) return const Color(0xFFFFF8E1); // Warm Gold tint
    return const Color(0xFFEEF2FF); // Soft Navy/Blue tint
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = _getSelectedColor(_index);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _buildNavigator(0, RecentScreen(api: api, store: store, session: _session)),
            _buildNavigator(1, HomeScreen(
              api: api,
              store: store,
              session: _session,
              onSearchModeChanged: (searching) {},
            )),
            _buildNavigator(2, MyContactsScreen(api: api, session: _session)),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Colors.white,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: BottomNavigationBar(
              elevation: 0,
              currentIndex: _index,
              onTap: (i) {
                _navigatorKeys[i].currentState?.popUntil((route) => route.isFirst);
                if (_index != i) {
                  setState(() => _index = i);
                }
              },
              backgroundColor: Colors.white,
              selectedItemColor: selectedColor,
              unselectedItemColor: const Color(0xFF757575),
              selectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12),
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: _index == 0 ? _getPillColor(0) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Image.asset(
                      'assets/images/history-icon.png',
                      width: 22,
                      height: 22,
                      color: _index == 0 ? selectedColor : const Color(0xFF757575),
                    ),
                  ),
                  label: 'Calls',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: _index == 1 ? _getPillColor(1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.travel_explore,
                      size: 22,
                      color: _index == 1 ? selectedColor : const Color(0xFF757575),
                    ),
                  ),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: _index == 2 ? _getPillColor(2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.contacts,
                      size: 20,
                      color: _index == 2 ? selectedColor : const Color(0xFF757575),
                    ),
                  ),
                  label: 'Contacts',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigator(int index, Widget rootPage) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateInitialRoutes: (navigator, initialRoute) {
        final routes = <Route<dynamic>>[
          MaterialPageRoute(builder: (context) => rootPage),
        ];
        if (index == 1 && widget.showProfileList) {
          routes.add(
            MaterialPageRoute(
              builder: (context) => ProfileListScreen(
                api: api,
                session: _session,
                mode: 'profile',
              ),
            ),
          );
        }
        return routes;
      },
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(builder: (context) => rootPage);
      },
    );
  }
}
