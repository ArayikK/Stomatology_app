import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A random id generated once per install and persisted locally. There is
/// no login/registration - this id is how the backend tells one
/// installation's data apart from another's.
class DeviceIdentity {
  DeviceIdentity._();

  static const _prefsKey = 'stom_device_id';
  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }
}
