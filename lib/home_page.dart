import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 건강 대시보드')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('대시보드 구성 예정 (수면/심박/실내환경 요약 등)'),
        ),
      ),
    );
  }
}
