// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

bool isGoogleMapsLoaded() {
  // `window.google` should exist after the Google Maps JS SDK is loaded.
  final google = js.context['google'];
  if (google == null) return false;

  try {
    return google['maps'] != null;
  } catch (_) {
    return false;
  }
}

