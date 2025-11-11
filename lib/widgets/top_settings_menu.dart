// lib/widgets/top_settings_menu.dart
/// 대시보드 (홈페이지) 우측 상단의 드롭다운 '설정' 바 위젯

import 'package:flutter/material.dart';
import '../pages/reminder_settings_page.dart';
import '../pages/accessibility_settings_page.dart';

enum _DashMenu { reminder, accessibility /*, exportPdf, exportCsv */ }

/// 대시보드 AppBar 우측에 두는 드롭다운 메뉴
class TopSettingsMenu extends StatelessWidget {
  const TopSettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DashMenu>(
      tooltip: '설정',
      icon: const Icon(Icons.dehaze), // 가로줄 3개 아이콘
      onSelected: (m) async {
        switch (m) {
          case _DashMenu.reminder:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReminderSettingsPage()),
            );
            break;
          case _DashMenu.accessibility:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccessibilitySettingsPage()),
            );
            break;
        // 필요하면 추후 내보내기 항목도 활성화
        // case _DashMenu.exportPdf:
        // case _DashMenu.exportCsv:
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: _DashMenu.reminder,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('리마인더 설정'),
          ),
        ),
        PopupMenuItem(
          value: _DashMenu.accessibility,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.text_increase),
            title: Text('가독성/접근성 설정'),
          ),
        ),
        // 필요 시 나중에 추가
        // PopupMenuDivider(),
        // PopupMenuItem(
        //   value: _DashMenu.exportPdf,
        //   child: ListTile(
        //     dense: true,
        //     leading: Icon(Icons.picture_as_pdf_outlined),
        //     title: Text('PDF로 내보내기'),
        //   ),
        // ),
        // PopupMenuItem(
        //   value: _DashMenu.exportCsv,
        //   child: ListTile(
        //     dense: true,
        //     leading: Icon(Icons.table_chart_outlined),
        //     title: Text('CSV로 내보내기'),
        //   ),
        // ),
      ],
    );
  }
}
