class Holiday {
  final String name;
  final DateTime date;
  final String type;

  Holiday({
    required this.name,
    required this.date,
    required this.type,
  });
}

class HolidayService {
  List<Holiday> getHolidays(int year) {
    // Kerala public holidays for the given year
    return [
      Holiday(
        name: 'Republic Day',
        date: DateTime(year, 1, 26),
        type: 'National Holiday',
      ),
      Holiday(
        name: 'Vishu',
        date: DateTime(year, 4, 14),
        type: 'Kerala Holiday',
      ),
      Holiday(
        name: 'Independence Day',
        date: DateTime(year, 8, 15),
        type: 'National Holiday',
      ),
      Holiday(
        name: 'Onam',
        date: DateTime(year, 8, 30),
        type: 'Kerala Holiday',
      ),
      Holiday(
        name: 'Gandhi Jayanti',
        date: DateTime(year, 10, 2),
        type: 'National Holiday',
      ),
      Holiday(
        name: 'Christmas',
        date: DateTime(year, 12, 25),
        type: 'National Holiday',
      ),
      // Add more Kerala-specific holidays here
      Holiday(
        name: 'Thiruvonam',
        date: DateTime(year, 8, 31),
        type: 'Kerala Holiday',
      ),
      Holiday(
        name: 'Kerala Piravi',
        date: DateTime(year, 11, 1),
        type: 'Kerala Holiday',
      ),
    ];
  }
}
