// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;

// Web implementation communicating with window.setOceanAtmosphereFromFlutter
void jsSetOceanAtmosphere(
  String shiftCode,
  double sunElev,
  double sunAzimuth,
  double nightGlow,
) {
  try {
    js.context.callMethod('setOceanAtmosphereFromFlutter', [
      shiftCode,
      sunElev,
      sunAzimuth,
      nightGlow,
    ]);
  } catch (_) {}
}

void jsTriggerOceanSurge() {
  try {
    js.context.callMethod('triggerOceanSurgeFromFlutter');
  } catch (_) {}
}
