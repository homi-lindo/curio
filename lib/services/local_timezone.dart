import 'package:timezone/timezone.dart' as tz;

final class LocalTimeZoneResolver {
  const LocalTimeZoneResolver();

  String resolve({String? systemName, Duration? systemOffset}) {
    final rawName = systemName ?? DateTime.now().timeZoneName;
    final rawOffset = systemOffset ?? DateTime.now().timeZoneOffset;

    if (_hasLocation(rawName)) {
      return rawName;
    }

    final mapped = _systemNames[_normalize(rawName)];
    if (mapped != null && _hasLocation(mapped)) {
      return mapped;
    }

    final offsetMatches = _preferredLocationsByOffset[rawOffset.inMinutes];
    if (offsetMatches != null) {
      for (final candidate in offsetMatches) {
        if (_hasCurrentOffset(candidate, rawOffset)) {
          return candidate;
        }
      }
    }

    return 'UTC';
  }

  static bool _hasLocation(String? name) {
    if (name == null || name.isEmpty) {
      return false;
    }
    return tz.timeZoneDatabase.locations.containsKey(name);
  }

  static bool _hasCurrentOffset(String name, Duration offset) {
    if (!_hasLocation(name)) {
      return false;
    }
    return tz.getLocation(name).currentTimeZone.offset == offset;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll('_', ' ');
  }
}

const Map<String, String> _systemNames = <String, String>{
  'e. south america standard time': 'America/Sao_Paulo',
  'brasilia standard time': 'America/Sao_Paulo',
  'america/sao paulo': 'America/Sao_Paulo',
  'brt': 'America/Sao_Paulo',
  '-03': 'America/Sao_Paulo',
  'gmt-03:00': 'America/Sao_Paulo',
  'utc-03:00': 'America/Sao_Paulo',
  'utc': 'UTC',
  'gmt': 'UTC',
  'z': 'UTC',
  'eastern standard time': 'America/New_York',
  'central standard time': 'America/Chicago',
  'mountain standard time': 'America/Denver',
  'pacific standard time': 'America/Los_Angeles',
  'greenwich standard time': 'Europe/London',
  'gmt standard time': 'Europe/London',
  'w. europe standard time': 'Europe/Berlin',
  'romance standard time': 'Europe/Paris',
  'tokyo standard time': 'Asia/Tokyo',
};

const Map<int, List<String>> _preferredLocationsByOffset = <int, List<String>>{
  0: <String>['UTC', 'Europe/London'],
  -180: <String>['America/Sao_Paulo', 'America/Argentina/Buenos_Aires'],
  -240: <String>['America/New_York', 'America/Caracas'],
  -300: <String>['America/New_York', 'America/Chicago', 'America/Bogota'],
  -360: <String>['America/Chicago', 'America/Denver'],
  -420: <String>['America/Denver', 'America/Los_Angeles'],
  -480: <String>['America/Los_Angeles', 'America/Vancouver'],
  60: <String>['Europe/London', 'Europe/Berlin'],
  120: <String>['Europe/Berlin', 'Europe/Paris'],
  540: <String>['Asia/Tokyo'],
};
