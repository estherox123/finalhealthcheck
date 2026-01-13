import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact_settings_page.dart';
import '../phone_format.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연락처 설정이 저장되었습니다.'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _makeCall(String number) async {
    if (number.isEmpty) { _navigateToSettings(); return; }
    final Uri launchUri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(launchUri)) { await launchUrl(launchUri); }
  }

  void _handleButtonPress(String actionType, String? name, String? digitsRaw) {
    if (actionType == "119") _makeCall("119");
    else _makeCall(digitsRaw ?? "");
  }

  void _handleLongPressCopy(String? digitsRaw) {
    if (digitsRaw == null || digitsRaw.isEmpty) return;
    Clipboard.setData(ClipboardData(text: formatKoreanPhone(digitsRaw)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('전화번호가 복사되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 화면 너비 체크: 미러 여부 확인
    final isMirror = MediaQuery.of(context).size.width > 600;
    final bgColor = isMirror ? Colors.black : const Color(0xFFF5F7FA);
    final textColor = isMirror ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('응급 연락', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined, size: 28), onPressed: _isLoading ? null : _navigateToSettings, tooltip: '연락처 설정'),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: <Widget>[
          const SizedBox(height: 10),
          Text("위급한 상황인가요?\n버튼을 누르면 바로 연결됩니다.", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.3, color: textColor)),
          const SizedBox(height: 30),
          _EmergencyCard(title: '119 응급실', subtitle: '화재 / 구조 / 구급', icon: Icons.local_hospital_rounded, color: Colors.red, isPrimary: true, onTap: () => _handleButtonPress("119", null, null)),
          const SizedBox(height: 24),
          Row(children: [const Expanded(child: Divider(color: Colors.grey)), Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("비상 연락망", style: TextStyle(color: Colors.grey[600], fontSize: 14))), const Expanded(child: Divider(color: Colors.grey))]),
          const SizedBox(height: 24),
          _EmergencyCard(title: _hospitalNameDisplay.isEmpty ? "담당 병원" : _hospitalNameDisplay, subtitle: _hospitalPhoneDisplay.isEmpty ? "눌러서 번호를 저장하세요" : formatKoreanPhone(_hospitalPhoneDisplay), icon: Icons.business_rounded, color: Colors.green, isSet: _hospitalPhoneDisplay.isNotEmpty, onTap: () => _handleButtonPress("hospital", _hospitalNameDisplay, _hospitalPhoneDisplay), onLongPress: () => _handleLongPressCopy(_hospitalPhoneDisplay)),
          const SizedBox(height: 16),
          _EmergencyCard(title: _guardianNameDisplay.isEmpty ? "보호자" : _guardianNameDisplay, subtitle: _guardianPhoneDisplay.isEmpty ? "눌러서 번호를 저장하세요" : formatKoreanPhone(_guardianPhoneDisplay), icon: Icons.person_rounded, color: Colors.blue, isSet: _guardianPhoneDisplay.isNotEmpty, onTap: () => _handleButtonPress("guardian", _guardianNameDisplay, _guardianPhoneDisplay), onLongPress: () => _handleLongPressCopy(_guardianPhoneDisplay)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  final String title; final String subtitle; final IconData icon; final Color color; final bool isPrimary; final bool isSet; final VoidCallback onTap; final VoidCallback? onLongPress;
  const _EmergencyCard({required this.title, required this.subtitle, required this.icon, required this.color, this.isPrimary = false, this.isSet = true, required this.onTap, this.onLongPress});
  @override
  Widget build(BuildContext context) {
    final bgColor = isPrimary ? Colors.red[50] : Colors.white;
    final titleColor = isSet ? Colors.black87 : Colors.grey;
    return InkWell(
      onTap: onTap, onLongPress: onLongPress, borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24), border: isPrimary ? Border.all(color: Colors.red.withOpacity(0.2), width: 1.5) : null, boxShadow: [BoxShadow(color: color.withOpacity(isPrimary ? 0.15 : 0.08), blurRadius: 15, offset: const Offset(0, 6))]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isSet ? color.withOpacity(0.15) : Colors.grey[100], shape: BoxShape.circle), child: Icon(icon, color: isSet ? color : Colors.grey, size: 32)),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: titleColor), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 6), Text(subtitle, style: TextStyle(fontSize: 16, color: isSet ? Colors.grey[700] : Colors.orangeAccent, fontWeight: isSet ? FontWeight.w500 : FontWeight.bold))])),
          if (isSet) Icon(Icons.call_rounded, color: color.withOpacity(0.8), size: 28) else const Icon(Icons.edit_rounded, color: Colors.grey, size: 24),
        ]),
      ),
    );
  }
}