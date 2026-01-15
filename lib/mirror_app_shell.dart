import 'package:finalhealthcheck/pages/mirror/MIRROR_contacts_page.dart';
import 'package:flutter/material.dart';

// ✅ 페이지 Import
import 'pages/mirror/MIRROR_home_page.dart';           // 1. 홈 (시계/대시보드)
import 'pages/mirror/MIRROR_health_summary_page.dart'; // 2. 건강 (미러용 디자인)
import 'pages/device_control_page.dart';               // 3. 제어 (공용 - 다크테마 자동적용)
import 'pages/mirror/MIRROR_contacts_page.dart';           // 4. 전화 (공용 - 다크테마 자동적용)

class MirrorAppShell extends StatefulWidget {
  const MirrorAppShell({super.key});

  @override
  State<MirrorAppShell> createState() => _MirrorAppShellState();
}

class _MirrorAppShellState extends State<MirrorAppShell> {
  int _currentIndex = 0;

  // ✅ 탭 페이지 구성 (홈 - 건강 - 제어 - 긴급)
  final List<Widget> _pages = const [
    MirrorHomePage(),          // 0
    MirrorHealthSummaryPage(), // 1
    DeviceControlPage(),       // 2
    MirrorContactPage(),    // 3
  ];

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 미러 배경 검정

      // 페이지 표시 영역
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      // ✅ 하단 탭바 (검정 배경 + 흰색 아이콘)
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: Colors.black, // 탭바 배경 검정
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onItemTapped,
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white, // 선택된 아이콘 흰색
          unselectedItemColor: Colors.grey, // 선택 안 된 아이콘 회색
          type: BottomNavigationBarType.fixed, // 탭이 4개라 fixed 필수
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: const [
            // 1. 홈
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: '홈',
            ),
            // 2. 건강
            BottomNavigationBarItem(
              icon: Icon(Icons.health_and_safety_outlined),
              activeIcon: Icon(Icons.health_and_safety),
              label: '건강',
            ),
            // 3. 제어 (아이콘 변경됨)
            BottomNavigationBarItem(
              icon: Icon(Icons.devices_other_outlined),
              activeIcon: Icon(Icons.devices_other),
              label: '제어',
            ),
            // 4. 긴급
            BottomNavigationBarItem(
              icon: Icon(Icons.phone_in_talk_outlined),
              activeIcon: Icon(Icons.phone_in_talk),
              label: '긴급',
            ),
          ],
        ),
      ),
    );
  }
}