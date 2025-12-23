// lib/pages/emergency_contacts_page.dart
/// 긴급 전화 번호 페이지. 119/담당병원/보호자. (시니어 친화적 카드 디자인 적용)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_settings_page.dart';
import '../phone_format.dart'; // normalizePhoneDigits / formatKoreanPhone

/// SharedPreferences 키 상수
const _kHospitalName = 'e_hospitalName';
const _kHospitalPhone = 'e_hospitalPhone';
const _kGuardianName = 'e_guardianName';
const _kGuardianPhone = 'e_guardianPhone';

class EmergencyContactPage extends StatefulWidget {
  const EmergencyContactPage({super.key});

  @override
  State<EmergencyContactPage> createState() => _EmergencyContactPageState();
}

class _EmergencyContactPageState extends State<EmergencyContactPage> {
  String _hospitalNameDisplay = "";
  String _hospitalPhoneDisplay = "";
  String _guardianNameDisplay = "";
  String _guardianPhoneDisplay = "";

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedContactInfo();
  }

  Future<void> _loadSavedContactInfo() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hospitalNameDisplay = prefs.getString(_kHospitalName) ?? "";
      _hospitalPhoneDisplay = prefs.getString(_kHospitalPhone) ?? "";
      _guardianNameDisplay = prefs.getString(_kGuardianName) ?? "";
      _guardianPhoneDisplay = prefs.getString(_kGuardianPhone) ?? "";
      _isLoading = false;
    });
  }

  Future<void> _saveContactInfoToPrefs(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHospitalName, (data['hospitalName'] ?? '').trim());
    await prefs.setString(_kHospitalPhone, normalizePhoneDigits(data['hospitalPhone'] ?? ''));
    await prefs.setString(_kGuardianName, (data['guardianName'] ?? '').trim());
    await prefs.setString(_kGuardianPhone, normalizePhoneDigits(data['guardianPhone'] ?? ''));
  }

  Future<void> _navigateToSettings() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactSettingsPage(
          initialHospitalName: _hospitalNameDisplay,
          initialHospitalPhone: formatKoreanPhone(_hospitalPhoneDisplay),
          initialGuardianName: _guardianNameDisplay,
          initialGuardianPhone: formatKoreanPhone(_guardianPhoneDisplay),
        ),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      await _saveContactInfoToPrefs(result);
      setState(() {
        _hospitalNameDisplay = result['hospitalName']!.trim();
        _hospitalPhoneDisplay = normalizePhoneDigits(result['hospitalPhone'] ?? '');
        _guardianNameDisplay = result['guardianName']!.trim();
        _guardianPhoneDisplay = normalizePhoneDigits(result['guardianPhone'] ?? '');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연락처 설정이 저장되었습니다.'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _handleButtonPress(String actionType, String? name, String? digitsRaw) {
    if (actionType != "119" && (digitsRaw == null || digitsRaw.isEmpty)) {
      _navigateToSettings(); // 번호 없으면 설정 화면으로 이동
      return;
    }

    final pretty = digitsRaw == null || digitsRaw.isEmpty ? "번호 없음" : formatKoreanPhone(digitsRaw);
    final msg = (actionType == "119")
        ? "🚑 119로 전화를 겁니다."
        : "📞 $name($pretty)에게 전화를 겁니다.";

    // 실제 전화 기능은 url_launcher 연동 필요
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleLongPressCopy(String? digitsRaw) {
    if (digitsRaw == null || digitsRaw.isEmpty) return;
    final pretty = formatKoreanPhone(digitsRaw);
    Clipboard.setData(ClipboardData(text: pretty));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('전화번호가 복사되었습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // 배경색 통일
      appBar: AppBar(
        title: const Text('응급 연락', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 28),
            onPressed: _isLoading ? null : _navigateToSettings,
            tooltip: '연락처 설정',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: <Widget>[
          const SizedBox(height: 10),
          const Text(
            "위급한 상황인가요?\n버튼을 누르면 바로 연결됩니다.",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.3, color: Colors.black87),
          ),
          const SizedBox(height: 30),

          // 1. 119 버튼 (가장 크게, 빨간색 강조)
          _EmergencyCard(
            title: '119 응급실',
            subtitle: '화재 / 구조 / 구급',
            icon: Icons.local_hospital_rounded,
            color: Colors.red,
            isPrimary: true, // 강조 스타일
            onTap: () => _handleButtonPress("119", null, null),
          ),
          const SizedBox(height: 24),

          // 2. 구분선
          Row(
            children: [
              const Expanded(child: Divider(color: Colors.grey)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text("비상 연락망", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ),
              const Expanded(child: Divider(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 24),

          // 3. 담당 병원
          _EmergencyCard(
            title: _hospitalNameDisplay.isEmpty ? "담당 병원" : _hospitalNameDisplay,
            subtitle: _hospitalPhoneDisplay.isEmpty
                ? "눌러서 번호를 저장하세요"
                : formatKoreanPhone(_hospitalPhoneDisplay),
            icon: Icons.business_rounded,
            color: Colors.green,
            isSet: _hospitalPhoneDisplay.isNotEmpty,
            onTap: () => _handleButtonPress("hospital", _hospitalNameDisplay, _hospitalPhoneDisplay),
            onLongPress: () => _handleLongPressCopy(_hospitalPhoneDisplay),
          ),
          const SizedBox(height: 16),

          // 4. 보호자
          _EmergencyCard(
            title: _guardianNameDisplay.isEmpty ? "보호자" : _guardianNameDisplay,
            subtitle: _guardianPhoneDisplay.isEmpty
                ? "눌러서 번호를 저장하세요"
                : formatKoreanPhone(_guardianPhoneDisplay),
            icon: Icons.person_rounded,
            color: Colors.blue,
            isSet: _guardianPhoneDisplay.isNotEmpty,
            onTap: () => _handleButtonPress("guardian", _guardianNameDisplay, _guardianPhoneDisplay),
            onLongPress: () => _handleLongPressCopy(_guardianPhoneDisplay),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ---------------- UI 컴포넌트 ----------------

class _EmergencyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isPrimary; // 119 강조용
  final bool isSet;     // 번호 설정 여부
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _EmergencyCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.isPrimary = false,
    this.isSet = true,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // 119(Primary)는 붉은색 틴트 배경, 나머지는 흰색 배경
    final bgColor = isPrimary ? Colors.red[50] : Colors.white;
    // 설정 안된 상태면 흐리게
    final fgColor = isSet ? color : Colors.grey;
    final titleColor = isSet ? Colors.black87 : Colors.grey;
    final subColor = isSet ? Colors.grey[700] : Colors.orangeAccent;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          border: isPrimary ? Border.all(color: Colors.red.withOpacity(0.2), width: 1.5) : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isPrimary ? 0.15 : 0.08),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // 아이콘 원형 배경
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSet ? color.withOpacity(0.15) : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: fgColor, size: 32),
            ),
            const SizedBox(width: 20),

            // 텍스트 영역
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: subColor,
                      fontWeight: isSet ? FontWeight.w500 : FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // 전화기 아이콘 (설정된 경우만)
            if (isSet)
              Icon(Icons.call_rounded, color: color.withOpacity(0.8), size: 28)
            else
              const Icon(Icons.edit_rounded, color: Colors.grey, size: 24),
          ],
        ),
      ),
    );
  }
}