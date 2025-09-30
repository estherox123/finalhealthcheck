import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_settings_page.dart';
import 'phone_format.dart'; // ✅ normalizePhoneDigits / formatKoreanPhone / Formatter

/// SharedPreferences 키 상수
const _kHospitalName = 'e_hospitalName';
const _kHospitalPhone = 'e_hospitalPhone';   // 숫자만 저장
const _kGuardianName = 'e_guardianName';
const _kGuardianPhone = 'e_guardianPhone';   // 숫자만 저장

class EmergencyContactPage extends StatefulWidget {
  const EmergencyContactPage({super.key});

  @override
  State<EmergencyContactPage> createState() => _EmergencyContactPageState();
}

class _EmergencyContactPageState extends State<EmergencyContactPage> {
  String _hospitalNameDisplay = "담당 병원 (설정 필요)";
  String _hospitalPhoneDisplay = "";   // 내부 저장은 숫자-only
  String _guardianNameDisplay = "보호자 (설정 필요)";
  String _guardianPhoneDisplay = "";   // 내부 저장은 숫자-only

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
      _hospitalNameDisplay =
          prefs.getString(_kHospitalName) ?? "담당 병원 (설정 필요)";
      _hospitalPhoneDisplay = prefs.getString(_kHospitalPhone) ?? "";
      _guardianNameDisplay =
          prefs.getString(_kGuardianName) ?? "보호자 (설정 필요)";
      _guardianPhoneDisplay = prefs.getString(_kGuardianPhone) ?? "";
      _isLoading = false;
    });
  }

  Future<void> _saveContactInfoToPrefs(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    // 이름은 trim, 번호는 숫자-only로 정규화 저장
    await prefs.setString(_kHospitalName, (data['hospitalName'] ?? '').trim());
    await prefs.setString(
        _kHospitalPhone, normalizePhoneDigits(data['hospitalPhone'] ?? ''));
    await prefs.setString(_kGuardianName, (data['guardianName'] ?? '').trim());
    await prefs.setString(
        _kGuardianPhone, normalizePhoneDigits(data['guardianPhone'] ?? ''));
  }

  Future<void> _navigateToSettings() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactSettingsPage(
          initialHospitalName:
          _hospitalNameDisplay.contains("설정 필요") ? "" : _hospitalNameDisplay,
          // 입력창엔 보기 좋게 포맷 넣고 시작 (사용자가 편집하면 Formatter가 유지)
          initialHospitalPhone: formatKoreanPhone(_hospitalPhoneDisplay),
          initialGuardianName:
          _guardianNameDisplay.contains("설정 필요") ? "" : _guardianNameDisplay,
          initialGuardianPhone: formatKoreanPhone(_guardianPhoneDisplay),
        ),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      await _saveContactInfoToPrefs(result);
      setState(() {
        _hospitalNameDisplay = result['hospitalName']!.isNotEmpty
            ? result['hospitalName']!.trim()
            : "담당 병원 (설정 필요)";
        _hospitalPhoneDisplay = normalizePhoneDigits(result['hospitalPhone'] ?? '');
        _guardianNameDisplay = result['guardianName']!.isNotEmpty
            ? result['guardianName']!.trim()
            : "보호자 (설정 필요)";
        _guardianPhoneDisplay = normalizePhoneDigits(result['guardianPhone'] ?? '');
      });

      // 저장 안내
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연락처 설정이 저장되었습니다.')),
      );
    }
  }

  void _handleButtonPress(String actionType, String? name, String? digitsRaw) {
    // (전화 기능은 추후 추가) — 지금은 안내만
    final pretty = digitsRaw == null || digitsRaw.isEmpty
        ? "번호 미설정"
        : formatKoreanPhone(digitsRaw);

    final msg = (actionType == "119")
        ? "119 버튼이 눌렸습니다. (전화 기능 구현 필요)"
        : "$name 버튼이 눌렸습니다. ($pretty) (전화 기능 구현 필요)";

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 길게 누르면 전화번호 복사 (보기용 포맷으로 복사)
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
    final appBar = AppBar(
      title: const Text('응급 연락'),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: _isLoading ? null : _navigateToSettings,
          tooltip: '설정',
        ),
      ],
    );

    if (_isLoading) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _EmergencyButton(
              label: '119 응급실',
              icon: Icons.local_hospital_outlined,
              backgroundColor: Colors.red.shade700,
              onPressed: () => _handleButtonPress("119", null, null),
              onLongPress: null,
              enabled: true,
              semanticsLabel: '119 응급실로 전화',
              subLabel: null,
            ),
            const SizedBox(height: 24),

            _EmergencyButton(
              label: _hospitalNameDisplay,
              subLabel: _hospitalPhoneDisplay.isNotEmpty
                  ? formatKoreanPhone(_hospitalPhoneDisplay)
                  : null,
              icon: Icons.business_outlined,
              backgroundColor: Colors.green.shade700,
              onPressed: _hospitalPhoneDisplay.isNotEmpty
                  ? () => _handleButtonPress(
                "hospital",
                _hospitalNameDisplay,
                _hospitalPhoneDisplay,
              )
                  : null,
              onLongPress: _hospitalPhoneDisplay.isNotEmpty
                  ? () => _handleLongPressCopy(_hospitalPhoneDisplay)
                  : null,
              enabled: _hospitalPhoneDisplay.isNotEmpty,
              semanticsLabel: _hospitalPhoneDisplay.isNotEmpty
                  ? '담당 병원 ${_hospitalNameDisplay} 전화 ${formatKoreanPhone(_hospitalPhoneDisplay)}'
                  : '담당 병원 연락처 설정 필요',
            ),
            const SizedBox(height: 24),

            _EmergencyButton(
              label: _guardianNameDisplay,
              subLabel: _guardianPhoneDisplay.isNotEmpty
                  ? formatKoreanPhone(_guardianPhoneDisplay)
                  : null,
              icon: Icons.person_search_outlined,
              backgroundColor: Colors.blue.shade700,
              onPressed: _guardianPhoneDisplay.isNotEmpty
                  ? () => _handleButtonPress(
                "guardian",
                _guardianNameDisplay,
                _guardianPhoneDisplay,
              )
                  : null,
              onLongPress: _guardianPhoneDisplay.isNotEmpty
                  ? () => _handleLongPressCopy(_guardianPhoneDisplay)
                  : null,
              enabled: _guardianPhoneDisplay.isNotEmpty,
              semanticsLabel: _guardianPhoneDisplay.isNotEmpty
                  ? '보호자 ${_guardianNameDisplay} 전화 ${formatKoreanPhone(_guardianPhoneDisplay)}'
                  : '보호자 연락처 설정 필요',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  final String label;
  final String? subLabel; // 보기용 포맷 문자열(예: 010-1234-5678)
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool enabled;
  final String? semanticsLabel;

  const _EmergencyButton({
    required this.label,
    this.subLabel,
    required this.icon,
    required this.backgroundColor,
    required this.onPressed,
    required this.onLongPress,
    required this.enabled,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = ElevatedButton.styleFrom(
      minimumSize: const Size(double.infinity, 90),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 3,
      foregroundColor: Colors.white,
    ).copyWith(
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        final base = backgroundColor;
        if (states.contains(MaterialState.disabled)) {
          return base.withOpacity(0.45);
        }
        return base;
      }),
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return Colors.white.withOpacity(0.7);
        }
        return Colors.white;
      }),
    );

    final bool showSub = subLabel != null && subLabel!.isNotEmpty;

    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      enabled: enabled,
      child: ElevatedButton(
        style: style,
        onPressed: enabled ? onPressed : null,
        onLongPress: enabled ? onLongPress : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (showSub) ...[
              const SizedBox(height: 5),
              Text(
                subLabel!,
                style: const TextStyle(fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
