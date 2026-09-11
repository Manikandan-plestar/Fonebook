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

  Future<void> _handlePop() async {
    final navState = _navigatorKeys[_index].currentState;
    if (navState != null && await navState.maybePop()) {
      return;
    }

    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }

    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    const barBgColor = Color(0xFFD3E3FD);
    const selectedColor = Color(0xFF041E49);
    const unselectedColor = Color(0xFF44474E);
    final activePillColor = Colors.white.withValues(alpha: 0.55);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F9),
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
          decoration: BoxDecoration(
            color: barBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.transparent,
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
                backgroundColor: Colors.transparent,
                selectedItemColor: selectedColor,
                unselectedItemColor: unselectedColor,
                selectedLabelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: selectedColor,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: unselectedColor,
                ),
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                    icon: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        color: _index == 0 ? activePillColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _index == 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.travel_explore,
                        size: 22,
                        color: _index == 0 ? selectedColor : unselectedColor,
                      ),
                    ),
                    label: 'Directory',
                  ),
                  BottomNavigationBarItem(
                    icon: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        color: _index == 1 ? activePillColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _index == 1
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Image.asset(
                        'assets/images/recents_icon.png',
                        width: 22,
                        height: 22,
                        color: _index == 1 ? selectedColor : unselectedColor,
                      ),
                    ),
                    label: 'Recent',
                  ),
                  BottomNavigationBarItem(
                    icon: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        color: _index == 2 ? activePillColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _index == 2
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.contacts,
                        size: 22,
                        color: _index == 2 ? selectedColor : unselectedColor,
                      ),
                    ),
                    label: 'Contacts',
                  ),
                ],
              ),
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
