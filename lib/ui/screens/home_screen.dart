import 'package:flutter/material.dart';

import '../../domain/alarm_service.dart';
import '../../domain/shift_store.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'shift_manage_screen.dart';
import 'stats_screen.dart';

/// 底導航主頁：日曆／班次／統計／設置四個 tab，用 IndexedStack 保持狀態。
class HomeScreen extends StatefulWidget {
  final ShiftStore store;
  final AlarmService alarms;

  const HomeScreen({super.key, required this.store, required this.alarms});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          CalendarScreen(store: widget.store, alarms: widget.alarms),
          ShiftManageScreen(store: widget.store, alarms: widget.alarms),
          StatsScreen(store: widget.store),
          SettingsScreen(store: widget.store, alarms: widget.alarms),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日曆',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: '班次',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '統計',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設置',
          ),
        ],
      ),
    );
  }
}
