// lib/services/reminder_service.dart
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._internal();
  static final ReminderService _singleton = ReminderService._internal();
  factory ReminderService() => _singleton;
  static ReminderService get instance => _singleton;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _reminderCheckTimer;
  bool _isCheckingReminders = false;
  
  // Store scheduled reminder times
  List<Map<String, dynamic>> _scheduledReminders = [];

  Future<void> init() async {
    if (_initialized) return;
    try {
      // 타임존
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

      // 플러그인 초기화
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
    const init = InitializationSettings(android: initAndroid, iOS: initIOS);
      bool? initialized = await _plugin.initialize(init);
      debugPrint('Notification plugin initialized: $initialized');

      // Android 13+ 알림 권한 체크 및 요청
      if (Platform.isAndroid) {
        final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
        // Create or update notification channel
        final channel = AndroidNotificationChannel(
          'reminders',
          'Reminders',
          description: 'Scheduled reminders for health checks',
          importance: Importance.high,
        );
        await a?.createNotificationChannel(channel);
        debugPrint('Notification channel created');
        
        // 일반 알림 권한
        final hasNotify = await a?.areNotificationsEnabled() ?? false;
        if (!hasNotify) {
          debugPrint('Requesting notification permission...');
          await a?.requestNotificationsPermission();
        }
        
        // 정확한 알람 권한 (Android 12+)
        final canExact = await a?.canScheduleExactNotifications() ?? false;
        debugPrint('Can schedule exact alarms: $canExact');
        if (!canExact) {
          debugPrint('Cannot schedule exact alarms - will use inexact mode');
        }
      }

      _initialized = true;
      
      // Start periodic reminder checking
      _startReminderChecker();
    } catch (e) {
      debugPrint('Notif init error: $e');
    }
  }
  
  /// Start a periodic checker for due reminders
  void _startReminderChecker() {
    if (_reminderCheckTimer?.isActive == true) return;
    
    _reminderCheckTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      _checkDueReminders();
    });
    debugPrint('Reminder checker started');
  }
  
  /// Check if any reminders are due and show them
  Future<void> _checkDueReminders() async {
    if (_isCheckingReminders) return;
    _isCheckingReminders = true;
    
    try {
      final now = DateTime.now();
      debugPrint('Checking for due reminders at $now');
      
      // Get all scheduled notifications and check if they're due
      final List<ActiveNotification>? active = await _plugin.getActiveNotifications();
      if (active == null || active.isEmpty) {
        _isCheckingReminders = false;
        return;
      }
      
      // Note: Active notifications are those currently displayed
      // We can't directly check scheduled ones, so we'll use a different approach
      // by storing reminder times in SharedPreferences
      
    } catch (e) {
      debugPrint('Error checking reminders: $e');
    }
    
    _isCheckingReminders = false;
  }

  // 초기화 보장
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  /// Check for due reminders when app opens (call this from app lifecycle)
  Future<void> checkScheduledReminders() async {
    await _ensureInitialized();
    
    if (_isCheckingReminders) return;
    _isCheckingReminders = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final reminderJson = prefs.getStringList('scheduled_reminders') ?? [];
      _scheduledReminders = reminderJson.map((j) => jsonDecode(j) as Map<String, dynamic>).toList();
      
      final now = DateTime.now();
      
      for (var reminder in _scheduledReminders) {
        final scheduledTime = DateTime.parse(reminder['time'] as String);
        final title = reminder['title'] as String;
        final body = reminder['body'] as String;
        final id = reminder['id'] as int;
        
        debugPrint('Checking reminder: $title at $scheduledTime (now: $now)');
        
        // If reminder is due (within 1 hour window and not yet shown)
        if (now.isAfter(scheduledTime.subtract(Duration(hours: 1))) && 
            !(reminder['shown'] as bool? ?? false)) {
          debugPrint('Showing due reminder: $title');
          
          await _plugin.show(
            id,
            title,
            body,
            _details(),
          );
          
          // Mark as shown
          reminder['shown'] = true;
          await _saveReminderList();
        }
      }
    } catch (e) {
      debugPrint('Error checking reminders: $e');
    } finally {
      _isCheckingReminders = false;
    }
  }
  
  /// Save reminder list to SharedPreferences
  Future<void> _saveReminderList() async {
    final prefs = await SharedPreferences.getInstance();
    final reminderJson = _scheduledReminders.map((r) => jsonEncode(r)).toList();
    await prefs.setStringList('scheduled_reminders', reminderJson);
  }
  
  /// Clear old reminders (older than 24 hours)
  Future<void> _cleanupOldReminders() async {
    final now = DateTime.now();
    _scheduledReminders.removeWhere((r) {
      final scheduledTime = DateTime.parse(r['time'] as String);
      return now.difference(scheduledTime).inHours > 24;
    });
    await _saveReminderList();
  }

  // ---------------- 디버그/테스트용 공개 메서드 ----------------
  Future<void> showNowTest({String? title, String? body}) async {
    await _ensureInitialized();
    await _plugin.show(
      9990,
      title ?? '테스트 알림',
      body ?? '즉시 표시 테스트',
      _details(),
    );
    debugPrint('showNowTest called - notification should appear immediately');
  }
  
  /// Check notification status and provide diagnostics
  Future<void> checkNotificationStatus() async {
    if (!Platform.isAndroid) {
      debugPrint('Not on Android - skipping status check');
      return;
    }
    
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) {
      debugPrint('Could not get Android plugin instance');
      return;
    }
    
    final hasNotify = await a.areNotificationsEnabled() ?? false;
    final canExact = await a.canScheduleExactNotifications() ?? false;
    
    debugPrint('=== Notification Status ===');
    debugPrint('Notifications enabled: $hasNotify');
    debugPrint('Can schedule exact alarms: $canExact');
    
    // Check if channel exists and is enabled
    final List<ActiveNotification>? activeNotifications = await _plugin.getActiveNotifications();
    debugPrint('Active scheduled notifications: ${activeNotifications?.length ?? 0}');
    if (activeNotifications != null && activeNotifications.isNotEmpty) {
      for (var notif in activeNotifications) {
        debugPrint('  - ID: ${notif.id}, Title: ${notif.title}');
      }
    }
    
    debugPrint('');
    debugPrint('If notifications are not appearing:');
    debugPrint('1. Go to Settings → Apps → finalhealthcheck');
    debugPrint('2. Check "Battery" → set to "Unrestricted"');
    debugPrint('3. Check "Alarms & reminders" → ensure it\'s ON');
    debugPrint('4. Check "Notifications" → ensure they\'re enabled');
    debugPrint('5. Ensure "Reminders" channel is enabled and not muted');
    debugPrint('=========================');
  }

  Future<void> scheduleAfterSecondsTest(int seconds) async {
    await _ensureInitialized();
    
    debugPrint('=== scheduleAfterSecondsTest: $seconds seconds ===');
    
    // Check permissions
    if (Platform.isAndroid) {
      final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final hasNotify = await a?.areNotificationsEnabled() ?? false;
      final canExact = await a?.canScheduleExactNotifications() ?? false;
      debugPrint('Notifications enabled: $hasNotify');
      debugPrint('Can schedule exact: $canExact');
      
      if (!hasNotify) {
        debugPrint('Requesting notification permission...');
        await a?.requestNotificationsPermission();
      }
      
      if (!canExact) {
        debugPrint('Requesting exact alarm permission...');
        await a?.requestExactAlarmsPermission();
        final canExact2 = await a?.canScheduleExactNotifications() ?? false;
        debugPrint('Can schedule exact after request: $canExact2');
      }
    }
    
    final now = tz.TZDateTime.now(tz.local);
    final when = now.add(Duration(seconds: seconds));
    
    debugPrint('NOW: $now');
    debugPrint('SCHEDULED TIME: $when');
    debugPrint('DIFFERENCE: ${when.difference(now).inSeconds} seconds');

    // Cancel any existing test notification first
    await cancel(9991);
    debugPrint('Cancelled previous test notification (if any)');

    // Try to schedule with a simpler approach first
    try {
      // Use higher priority details for test
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          channelDescription: 'Scheduled reminders',
          importance: Importance.max,
          priority: Priority.max,
          enableVibration: true,
          playSound: true,
          showWhen: true,
          autoCancel: true,
          ongoing: false,
          ticker: 'Test Notification',
        ),
        iOS: const DarwinNotificationDetails(),
      );
      
      await _plugin.zonedSchedule(
        9991,
        '테스트 스케줄',
        '$seconds초 뒤 표시 예정\n${DateTime.now().add(Duration(seconds: seconds))}',
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'test_scheduled',
      );
      debugPrint('✓ Notification scheduled successfully');
      debugPrint('✓ Check your device at: ${when.toString()}');
      debugPrint('✓ Notification details: MAX priority, high importance');
    } catch (e) {
      debugPrint('✗ Direct schedule failed: $e');
      debugPrint('Trying fallback with inexact mode...');
      try {
        final details = NotificationDetails(
          android: const AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Scheduled reminders',
      importance: Importance.max,
            priority: Priority.max,
            enableVibration: true,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(),
        );
        
        await _plugin.zonedSchedule(
          9991,
          '테스트 스케줄 (inexact)',
          '$seconds초 뒤 표시 예정 - Inexact mode',
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'test_inexact',
        );
        debugPrint('✓ Fallback schedule succeeded');
      } catch (e2) {
        debugPrint('✗ Fallback also failed: $e2');
      }
    }
  }

  // ---------- 내부: 권한/정확알람 확인 & 폴백 ----------
  Future<bool> _ensureAndroidPermissions({required bool needExact}) async {
    if (!Platform.isAndroid) return true;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) return true;

    final enabled = await a.areNotificationsEnabled() ?? true;
    if (!enabled) {
      final ok = await a.requestNotificationsPermission();
      if (ok != true) return false;
    }

    if (needExact) {
      final canExact = await a.canScheduleExactNotifications() ?? false;
      if (!canExact) {
        await a.requestExactAlarmsPermission();
        final canExact2 = await a.canScheduleExactNotifications() ?? false;
        return canExact2;
      }
    }
    return true;
  }

  AndroidNotificationDetails _androidDetails() {
    return AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Scheduled reminders for health checks',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      showWhen: true,
      autoCancel: true,
      ongoing: false,
      ticker: 'Reminder',
      styleInformation: BigTextStyleInformation(''), // Ensure visibility
    );
  }
  
  // Also create a high importance channel for testing
  AndroidNotificationDetails _testDetails() {
    return const AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Scheduled reminders for health checks',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: true,
      showWhen: true,
      autoCancel: true,
      ongoing: false,
      ticker: 'Test Reminder',
    );
  }
  NotificationDetails _details() =>
      NotificationDetails(android: _androidDetails(), iOS: const DarwinNotificationDetails());

  tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    final at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    return at.isBefore(now) ? at.add(const Duration(days: 1)) : at;
  }

  tz.TZDateTime _nextWeekday(int weekday, int hour, int minute) {
    var t = _nextTime(hour, minute);
    while (t.weekday != weekday) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }

  // ---------- 공용: 일/주 스케줄 (정확→inexact 폴백) ----------
  Future<bool> _zonedScheduleSmart({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required DateTimeComponents? match,
  }) async {
    try {
      debugPrint('_zonedScheduleSmart: Scheduling ID $id for $when');
      
      final canExact = await _ensureAndroidPermissions(needExact: true);
      final mode = canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      
      debugPrint('Using schedule mode: ${mode == AndroidScheduleMode.exactAllowWhileIdle ? "EXACT" : "INEXACT"}');

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details(),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: match,
        payload: 'id:$id',
      );
      
      debugPrint('Successfully scheduled notification ID $id');
      return true;
    } catch (e) {
      debugPrint('zonedSchedule error for ID $id: $e');
      try {
        debugPrint('Trying fallback with inexact mode...');
    await _plugin.zonedSchedule(
      id,
      title,
      body,
          when,
      _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: match,
          payload: 'id:$id',
        );
        debugPrint('Fallback succeeded for ID $id');
        return true;
      } catch (e2) {
        debugPrint('fallback schedule error for ID $id: $e2');
        return false;
      }
    }
  }

  // ---------- 외부 API ----------
  Future<bool> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final nextDate = _nextTime(hour, minute);
    final now = DateTime.now();
    
    // Store reminder for next 7 days
    for (int i = 0; i < 7; i++) {
      final date = nextDate.add(Duration(days: i));
      _scheduledReminders.add({
        'id': id,
        'title': title,
        'body': body,
        'time': date.toIso8601String(),
        'shown': false,
      });
    }
    
    await _saveReminderList();
    debugPrint('Stored daily reminder starting at ${nextDate.toString()}');
    
    // Also try Android scheduling as backup
    _zonedScheduleSmart(
      id: id,
      title: title,
      body: body,
      when: nextDate,
      match: DateTimeComponents.time,
    );
    
    return true;
  }

  Future<bool> scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    final nextDate = _nextWeekday(weekday, hour, minute);
    
    // Store reminders for next 4 weeks
    for (int i = 0; i < 4; i++) {
      final date = nextDate.add(Duration(days: i * 7));
      _scheduledReminders.add({
        'id': id,
        'title': title,
        'body': body,
        'time': date.toIso8601String(),
        'shown': false,
      });
    }
    
    await _saveReminderList();
    debugPrint('Stored weekly reminder starting at ${nextDate.toString()}');
    
    // Also try Android scheduling as backup
    _zonedScheduleSmart(
      id: id,
      title: title,
      body: body,
      when: nextDate,
      match: DateTimeComponents.dayOfWeekAndTime,
    );
    
    return true;
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
  Future<void> cancelAll() => _plugin.cancelAll();

  // ---------- 앱 전용 프리셋 ----------
  static const int _idOccultBase = 2000;
  static const int _idWindDown = 2100;
  static const int _idActivity = 2200;

  Future<bool> enableOccultWeekly({
    required List<int> weekdays,
    required int hour,
    required int minute,
  }) async {
    await disableOccultWeekly();
    var ok = true;
    for (final wd in weekdays) {
      final id = _idOccultBase + ((wd - 1) % 7);
      ok &= await scheduleWeekly(
        id: id,
        title: '잠혈 검사 리마인더',
        body: '테스트 키트로 잠혈 검사를 진행해 주세요.',
        weekday: wd,
        hour: hour,
        minute: minute,
      );
    }
    return ok;
  }

  Future<void> disableOccultWeekly() async {
    for (int i = 0; i < 7; i++) {
      await cancel(_idOccultBase + i);
    }
  }

  Future<bool> enableWindDownDaily({required int hour, required int minute}) async {
    await cancel(_idWindDown);
    return scheduleDaily(
      id: _idWindDown,
      title: '취침 준비 시간',
      body: '조명을 낮추고 휴대폰은 잠시 멀리 두세요.',
      hour: hour,
      minute: minute,
    );
  }

  Future<void> disableWindDownDaily() => cancel(_idWindDown);

  Future<bool> enableActivityDaily({required int hour, required int minute}) async {
    await cancel(_idActivity);
    return scheduleDaily(
      id: _idActivity,
      title: '활동 알림',
      body: '가벼운 산책으로 몸을 깨워보세요.',
      hour: hour,
      minute: minute,
    );
  }

  Future<void> disableActivityDaily() => cancel(_idActivity);

  /// Alternative test: Schedule without timezone
  Future<void> scheduleAfterSecondsTestSimple(int seconds) async {
    await _ensureInitialized();
    
    debugPrint('=== scheduleAfterSecondsTestSimple: $seconds seconds ===');
    
    // Cancel any existing notification
    await cancel(9991);
    
    // Schedule without timezone complexity
    try {
      final scheduledDate = DateTime.now().add(Duration(seconds: seconds));
      
      await _plugin.zonedSchedule(
        9991,
        'Simple Test 알림',
        '이것이 나타나면 성공입니다! ($seconds초 후)',
        tz.TZDateTime.from(scheduledDate, tz.local),
        _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'simple_test',
      );
      
      debugPrint('✓ Simple notification scheduled for: $scheduledDate');
      debugPrint('✓ Current time: ${DateTime.now()}');
      debugPrint('✓ Will trigger in ${seconds} seconds');
    } catch (e) {
      debugPrint('✗ Simple schedule failed: $e');
    }
  }

  /// Final test: Show immediate notification to verify channel works
  Future<void> testNotificationChannel() async {
    await _ensureInitialized();
    
    debugPrint('=== Testing Notification Channel ===');
    
    // Show immediate notification
    await _plugin.show(
      9992,
      '채널 테스트',
      '이 알림이 보이면 채널은 정상입니다!',
      _details(),
    );
    
    debugPrint('✓ Immediate notification sent');
    debugPrint('✓ If you see this notification, the channel works');
    debugPrint('✓ If you don\'t, check device notification settings');
  }

  /// Test if notifications trigger at the right time
  Future<void> watchNotificationTrigger(int seconds) async {
    await _ensureInitialized();
    
    debugPrint('=== Watching for notification trigger in $seconds seconds ===');
    debugPrint('Make sure the app stays in foreground or background (NOT closed)');
    
    await scheduleAfterSecondsTest(seconds);
    
    // Log every second to see when it triggers
    debugPrint('Watching... Current time: ${DateTime.now()}');
    debugPrint('Notification should appear at: ${DateTime.now().add(Duration(seconds: seconds))}');
    debugPrint('Keep this log visible and watch for the notification!');
  }
  
  /// Test with a workaround: use a future to trigger at the right time
  Future<void> scheduleWithWorkaround(int seconds) async {
    await _ensureInitialized();
    
    debugPrint('=== Testing workaround: schedule with Timer ===');
    
    // Use a Future with delay as a workaround
    final future = Future.delayed(Duration(seconds: seconds), () async {
      debugPrint('Timer expired at ${DateTime.now()}');
      debugPrint('Showing scheduled notification now...');
      
      await _plugin.show(
        9993,
        '예약된 알림 (Workaround)',
        '타이머로 ${seconds}초 후 표시됨',
        NotificationDetails(android: _testDetails(), iOS: const DarwinNotificationDetails()),
      );
      
      debugPrint('✓ Workaround notification shown');
    });
    
    debugPrint('Workaround scheduled for ${seconds} seconds from now');
    debugPrint('This will trigger even if standard scheduling fails');
    debugPrint('DON\'T CLOSE THE APP!');
  }
}
