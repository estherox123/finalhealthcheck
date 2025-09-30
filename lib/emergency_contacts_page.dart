import 'package:flutter/material.dart';

class EmergencyContactsPage extends StatelessWidget {
  const EmergencyContactsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('응급 연락처')),
      body: const Center(child: Text('가족/의료진 연락처 관리 (추가 예정)')),
    );
  }
}
