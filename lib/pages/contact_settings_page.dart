import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../phone_format.dart';

class ContactSettingsPage extends StatefulWidget {
  final String initialHospitalName;
  final String initialHospitalPhone;
  final String initialGuardianName;
  final String initialGuardianPhone;

  const ContactSettingsPage({
    super.key,
    this.initialHospitalName = '',
    this.initialHospitalPhone = '',
    this.initialGuardianName = '',
    this.initialGuardianPhone = '',
  });

  @override
  State<ContactSettingsPage> createState() => _ContactSettingsPageState();
}

class _ContactSettingsPageState extends State<ContactSettingsPage> {
  // 폼/컨트롤러
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hospitalNameController;
  late TextEditingController _hospitalPhoneController;
  late TextEditingController _guardianNameController;
  late TextEditingController _guardianPhoneController;

  // 간단한 전화번호 필터(숫자/+, -, 공백 허용)
  final _phoneFormatter =
  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'));

  @override
  void initState() {
    super.initState();
    _hospitalNameController =
        TextEditingController(text: widget.initialHospitalName);
    _hospitalPhoneController =
        TextEditingController(text: widget.initialHospitalPhone);
    _guardianNameController =
        TextEditingController(text: widget.initialGuardianName);
    _guardianPhoneController =
        TextEditingController(text: widget.initialGuardianPhone);
  }

  @override
  void dispose() {
    _hospitalNameController.dispose();
    _hospitalPhoneController.dispose();
    _guardianNameController.dispose();
    _guardianPhoneController.dispose();
    super.dispose();
  }

  String? _requireNonEmpty(String? v, {String label = '값'}) {
    if (v == null || v.trim().isEmpty) return '$label을(를) 입력하세요';
    return null;
  }

  String? _optionalPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null; // 선택 항목
    final cleaned = v.replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.length < 7) return '전화번호 형식을 확인해주세요';
    return null;
  }

  void _saveSettings() {
    // 병원 이름/번호는 필수, 보호자는 선택
    if (_formKey.currentState?.validate() != true) return;

    Navigator.pop(context, {
      'hospitalName': _hospitalNameController.text.trim(),
      'hospitalPhone': _hospitalPhoneController.text.trim(),
      'guardianName': _guardianNameController.text.trim(),
      'guardianPhone': _guardianPhoneController.text.trim(),
    });

    // ⚠️ SnackBar는 pop 이후 현재 context가 dispose되므로
    // 여기서 띄우지 않고 호출한 페이지에서 띄우도록 처리함.
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('연락처 설정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_outlined),
            onPressed: _saveSettings,
            tooltip: '완료',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              Text('담당 병원 정보', style: t.titleLarge),
              const SizedBox(height: 8),
              TextFormField(
                controller: _hospitalNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '병원 이름',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                validator: (v) => _requireNonEmpty(v, label: '병원 이름'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hospitalPhoneController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneFormatter],
                decoration: const InputDecoration(
                  labelText: '병원 전화번호',
                  hintText: '예: 02-1234-5678',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => _requireNonEmpty(v, label: '병원 전화번호'),
              ),

              const SizedBox(height: 24),
              Text('보호자 정보', style: t.titleLarge),
              const SizedBox(height: 8),
              TextFormField(
                controller: _guardianNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '보호자 이름 (선택)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _guardianPhoneController,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneFormatter],
                decoration: const InputDecoration(
                  labelText: '보호자 전화번호 (선택)',
                  hintText: '예: 010-1111-2222',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android_outlined),
                ),
                validator: _optionalPhone,
              ),

              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.done_all_outlined),
                label: const Text('설정 완료'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: _saveSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
