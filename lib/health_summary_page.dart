import 'package:flutter/material.dart';
import 'steps_page.dart';
import 'sleep_detail_page.dart';
import 'health_debug_page.dart';

class HealthSummaryPage extends StatelessWidget {
  const HealthSummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('건강')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            _BigButton(
              label: '걸음수',
              icon: Icons.directions_walk_outlined,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StepsPage())),
            ),
            const SizedBox(height: 16),
            _BigButton(
              label: '수면 패턴',
              icon: Icons.bedtime_outlined,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SleepDetailPage())),
            ),
            //HIDE DEBUG BUTTON FOR AUTH CHECK
            /*_BigButton(
              label: '디버그(권한/등록 확인)',
              icon: Icons.bug_report_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HealthDebugPage()),
              ),
            ),*/
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _BigButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 110,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon, size: 32), const SizedBox(width: 12), Text(label)],
        ),
      ),
    );
  }
}
