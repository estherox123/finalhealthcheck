import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';

// ⚠️ [중요] 방금 보여주신 코드가 들어있는 파일명을 정확히 import 해야 합니다.
// 만약 보여주신 코드가 'lib/mirror_app_shell.dart'라면 아래처럼 씁니다.
import 'mirror_app_shell.dart';

// ✅ 이 함수가 있어야 앱이 시작됩니다!
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  // 권한 요청 (필요 시)
  await [
    Permission.activityRecognition,
    Permission.location,
    Permission.sensors,
  ].request();

  runApp(const MirrorApp());
}

class MirrorApp extends StatelessWidget {
  const MirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Mirror',
      debugShowCheckedModeBanner: false,

      // ✅ 미러용 다크 테마 설정
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),

      // ✅ 여기서 아까 보여주신 'MirrorAppShell'을 실행합니다.
      home: const MirrorAppShell(),
    );
  }
}