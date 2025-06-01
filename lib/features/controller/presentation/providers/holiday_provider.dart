import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:office_pal/features/controller/domain/services/holiday_service.dart';

final holidayServiceProvider = Provider((ref) => HolidayService());

final holidaysProvider = FutureProvider.family<List<Holiday>, int>(
  (ref, year) async {
    final holidayService = ref.watch(holidayServiceProvider);
    return holidayService.getHolidays(year);
  },
);
