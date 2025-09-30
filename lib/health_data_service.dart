import 'package:health/health.dart';
import 'health_controller.dart';

class HealthDataService {
  final Health _health = Health(); // Instance of Health from the package

  // Helper to ensure permissions; might be simplified if HealthController handles more
  Future<void> _ensureAuthorized(List<HealthDataType> types) async {
    await HealthController.I.ensureConfigured(); // From your HealthController
    bool granted = await HealthController.I.hasPermsFor(types);
    if (!granted) {
      granted = await HealthController.I.requestPermsFor(types);
    }
    if (!granted) {
      throw Exception("Permissions not granted for health data types: $types");
    }
  }

  Future<Duration?> getLastNightSleepDuration() async {
    await _ensureAuthorized([HealthDataType.SLEEP_SESSION]); // Ensure this type is correct

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final yesterdayStart = startOfToday.subtract(const Duration(days: 1));

    final sleepSessions = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.SLEEP_SESSION],
      startTime: yesterdayStart,
      endTime: startOfToday, // Data up to the very beginning of today
    );

    Duration totalDuration = Duration.zero;
    for (var session in sleepSessions) {
      if (session.dateFrom != null && session.dateTo != null) {
        totalDuration += session.dateTo!.difference(session.dateFrom!);
      }
    }
    print("HealthDataService: Last night sleep duration: $totalDuration");
    return totalDuration == Duration.zero ? null : totalDuration;
  }

// TODO: Add methods for heart rate, HRV, etc.
// Example:
// Future<int?> getLatestHeartRate() async {
//   await _ensureAuthorized([HealthDataType.HEART_RATE]);
//   final now = DateTime.now();
//   final startTime = now.subtract(const Duration(days: 1)); // Example: last 24 hours
//   final rates = await _health.getHealthDataFromTypes(
//       types: const [HealthDataType.HEART_RATE],
//       startTime: startTime,
//       endTime: now);
//   if (rates.isNotEmpty) {
//     rates.sort((a, b) => b.dateFrom.compareTo(a.dateFrom)); // Get the latest
//     return (rates.first.value as NumericHealthValue).numericValue.toInt();
//   }
//   return null;
// }
}
