import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool isGoogleMapsLoaded() {
  // `window.google.maps` exists once the Google Maps JS SDK has loaded.
  final google = globalContext.getProperty<JSObject?>('google'.toJS);
  if (google == null) return false;
  return google.getProperty<JSAny?>('maps'.toJS) != null;
}
