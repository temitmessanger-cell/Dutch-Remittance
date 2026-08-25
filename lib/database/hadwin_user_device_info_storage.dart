import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Tracks basic device info and first-install/onboarding status.
///
/// Backed by Hive — works identically on mobile, desktop, and web. The
/// previous implementation used an in-memory flag on web (since dart:io
/// File doesn't work there) which meant onboarding status reset on every
/// page reload; Hive makes that genuinely persistent like every other
/// platform.
class UserDeviceInfoStorage {
  static const String boxName = 'dutch_remit_device_info';
  static const String _dataKey = 'deviceInfo';

  late String _deviceOS;
  late String _deviceOSVersion;

  UserDeviceInfoStorage() {
    if (!kIsWeb) {
      _deviceOS = Platform.operatingSystem;
      _deviceOSVersion = Platform.operatingSystemVersion;
    } else {
      _deviceOS = 'web';
      _deviceOSVersion = 'web';
    }
  }

  Future<Box> get _box async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box(boxName);
    }
    return Hive.openBox(boxName);
  }

  Future<bool> initializeInstallationStatus() async {
    DateTime dateOfFirstUse = DateTime.now();

    try {
      final box = await _box;
      await box.put(_dataKey, {
        'deviceOS': _deviceOS,
        'deviceOSVersion': _deviceOSVersion,
        'dateOfFirstUse': dateOfFirstUse.toString()
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> get wasUsedBefore async {
    try {
      final box = await _box;
      final data = box.get(_dataKey);
      if (data != null && Map<String, dynamic>.from(data).isNotEmpty) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteFile() async {
    try {
      final box = await _box;
      await box.delete(_dataKey);
     //* THE USER DEVICE INFORMATION HAS BEEN DELETED
      return true;
    } catch (e) {
     //* THE USER DEVICE INFORMATION HAS NOT BEEN DELETED
      return false;
    }
  }
}
