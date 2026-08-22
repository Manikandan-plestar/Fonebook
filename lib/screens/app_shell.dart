import 'package:flutter/material.dart';
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
  const AppShell({super.key, this.initialIndex = 0, this.showProfileList = false});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
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

  Future<bool> _onWillPop() async {
    final isFirstRouteInCurrentTab = !await _navigatorKeys[_index].currentState!.maybePop();
    if (isFirstRouteInCurrentTab) {
      if (_index != 0) {
        setState(() => _index = 0);
        return false;
      }
    }
    return isFirstRouteInCurrentTab;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _buildNavigator(0, HomeScreen(
              api: api,
              store: store,
              session: _session,
              onSearchModeChanged: (searching) {},
            )),
            _buildNavigator(1, RecentScreen(api: api, store: store, session: _session)),
            _buildNavigator(2, MyContactsScreen(api: api, session: _session)),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF212529),
            border: Border(top: BorderSide(color: Color(0xFF343A40), width: 0.8)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: const Color(0xFF212529),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: BottomNavigationBar(
              elevation: 0,
              currentIndex: _index,
              onTap: (i) {
                if (_index == i) {
                  _navigatorKeys[i].currentState?.popUntil((route) => route.isFirst);
                } else {
                  setState(() => _index = i);
                }
              },
              backgroundColor: const Color(0xFF212529),
              selectedItemColor: const Color(0xFFF6D207),
              unselectedItemColor: const Color(0xFFA0A0A0),
              selectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12),
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: _index == 0 ? const Color(0xFF343A40) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.search,
                      size: 22,
                      color: _index == 0 ? const Color(0xFFF6D207) : const Color(0xFFA0A0A0),
                    ),
                  ),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: _index == 1 ? const Color(0xFF343A40) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset('assets/images/recent.png', width: 22, height: 22, color: _index == 1 ? const Color(0xFFF6D207) : const Color(0xFFA0A0A0)),
                  ),
                  label: 'Recent',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: _index == 2 ? const Color(0xFF343A40) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.contacts,
                      size: 20,
                      color: _index == 2 ? const Color(0xFFF6D207) : const Color(0xFFA0A0A0),
                    ),
                  ),
                  label: 'Saved',
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
        if (index == 0 && widget.showProfileList) {
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
