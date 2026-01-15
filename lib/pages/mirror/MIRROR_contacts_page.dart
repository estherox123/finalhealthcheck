import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../phone_format.dart';

// 저장 키 (내부 키값은 유지하되, 화면 표시 내용은 변경됨)
const _kSlot1Name = 'm_slot1_name';
const _kSlot1Phone = 'm_slot1_phone';
const _kSlot2Name = 'm_slot2_name';
const _kSlot2Phone = 'm_slot2_phone';
const _kSlot3Name = 'm_slot3_name';
const _kSlot3Phone = 'm_slot3_phone';
const _kSlot4Name = 'm_slot4_name';
const _kSlot4Phone = 'm_slot4_phone';

class MirrorContactPage extends StatefulWidget {
  const MirrorContactPage({super.key});

  @override
  State<MirrorContactPage> createState() => _MirrorContactPageState();
}

class _MirrorContactPageState extends State<MirrorContactPage> {
  // 기본값 설정: 관리자, 식당, 병원, 보호자
  String _name1 = "관리자";
  String _phone1 = "";

  String _name2 = "식당";
  String _phone2 = "";

  String _name3 = "병원";
  String _phone3 = "";

  String _name4 = "보호자";
  String _phone4 = "";

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name1 = prefs.getString(_kSlot1Name) ?? "관리자";
      _phone1 = prefs.getString(_kSlot1Phone) ?? "";

      _name2 = prefs.getString(_kSlot2Name) ?? "식당";
      _phone2 = prefs.getString(_kSlot2Phone) ?? "";

      _name3 = prefs.getString(_kSlot3Name) ?? "병원";
      _phone3 = prefs.getString(_kSlot3Phone) ?? "";

      _name4 = prefs.getString(_kSlot4Name) ?? "보호자";
      _phone4 = prefs.getString(_kSlot4Phone) ?? "";

      _isLoading = false;
    });
  }

  Future<void> _showEditDialog(String titleKey, String phoneKey, String currentTitle, String currentPhone) async {
    final titleCtrl = TextEditingController(text: currentTitle);
    final phoneCtrl = TextEditingController(text: currentPhone);

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(30),
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("연락처 수정", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                _buildTextField(label: "이름", controller: titleCtrl, isNumber: false),
                const SizedBox(height: 20),
                _buildTextField(label: "전화번호", controller: phoneCtrl, isNumber: true),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.grey, fontSize: 18))),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(titleKey, titleCtrl.text);
                        await prefs.setString(phoneKey, normalizePhoneDigits(phoneCtrl.text));
                        await _loadData();
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text("저장", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextField({required String label, required TextEditingController controller, required bool isNumber}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
      ),
    );
  }

  void _showBigNumber(String title, String number) {
    if (number.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.white24)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 28, color: Colors.grey)),
              const SizedBox(height: 30),
              FittedBox(
                child: Text(
                  formatKoreanPhone(number),
                  style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4.0),
                ),
              ),
              const SizedBox(height: 50),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 28),
                label: const Text("닫기", style: TextStyle(fontSize: 20)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("주요 연락처", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              "카드를 누르면 번호가 크게 보입니다.",
              style: TextStyle(color: Colors.grey, fontSize: 18),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 1.3,
                children: [
                  // 1. 관리자
                  _ContactCard(
                    title: _name1,
                    phone: _phone1,
                    icon: Icons.admin_panel_settings_rounded, // 아이콘 변경
                    color: Colors.blueAccent,
                    onTap: () => _phone1.isEmpty
                        ? _showEditDialog(_kSlot1Name, _kSlot1Phone, _name1, _phone1)
                        : _showBigNumber(_name1, _phone1),
                    onEdit: () => _showEditDialog(_kSlot1Name, _kSlot1Phone, _name1, _phone1),
                  ),
                  // 2. 식당
                  _ContactCard(
                    title: _name2,
                    phone: _phone2,
                    icon: Icons.restaurant_rounded, // 아이콘 변경
                    color: Colors.orangeAccent,
                    onTap: () => _phone2.isEmpty
                        ? _showEditDialog(_kSlot2Name, _kSlot2Phone, _name2, _phone2)
                        : _showBigNumber(_name2, _phone2),
                    onEdit: () => _showEditDialog(_kSlot2Name, _kSlot2Phone, _name2, _phone2),
                  ),
                  // 3. 병원
                  _ContactCard(
                    title: _name3,
                    phone: _phone3,
                    icon: Icons.local_hospital_rounded, // 아이콘 변경
                    color: Colors.greenAccent,
                    onTap: () => _phone3.isEmpty
                        ? _showEditDialog(_kSlot3Name, _kSlot3Phone, _name3, _phone3)
                        : _showBigNumber(_name3, _phone3),
                    onEdit: () => _showEditDialog(_kSlot3Name, _kSlot3Phone, _name3, _phone3),
                  ),
                  // 4. 보호자
                  _ContactCard(
                    title: _name4,
                    phone: _phone4,
                    icon: Icons.favorite_rounded, // 아이콘 변경 (하트)
                    color: Colors.purpleAccent,
                    onTap: () => _phone4.isEmpty
                        ? _showEditDialog(_kSlot4Name, _kSlot4Phone, _name4, _phone4)
                        : _showBigNumber(_name4, _phone4),
                    onEdit: () => _showEditDialog(_kSlot4Name, _kSlot4Phone, _name4, _phone4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final String title;
  final String phone;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _ContactCard({
    required this.title, required this.phone, required this.icon, required this.color, required this.onTap, required this.onEdit
  });

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = phone.isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.grey),
                  onPressed: onEdit,
                )
              ],
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontSize: 24, color: Colors.grey, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(
              isEmpty ? "터치하여 저장" : formatKoreanPhone(phone),
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isEmpty ? Colors.grey[700] : Colors.white
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}