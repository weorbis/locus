import 'package:flutter/services.dart';

class LocusChannels {
  static const MethodChannel methods = MethodChannel('locus/methods');
  static const EventChannel events = EventChannel('locus/events');
  static const MethodChannel headless = MethodChannel('locus/headless');
  static const MethodChannel headlessValidation =
      MethodChannel('locus/headless_validation');
  static const MethodChannel headlessHeaders =
      MethodChannel('locus/headless_headers');
}
