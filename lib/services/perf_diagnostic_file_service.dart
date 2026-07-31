// TEMPORARY DIAGNOSTIC ONLY — not wired into the app's default image cache.
// Used solely by HomeScreen's images to measure exactly where first-load
// latency goes and to verify — at the real network layer, not by trusting
// widget code — whether images are actually requested all at once or only
// as they become visible. This sits *below* flutter_cache_manager's
// WebHelper concurrency queue (FileService.concurrentFetches, default 10 —
// see pub cache flutter_cache_manager-3.4.1 lib/src/web/file_service.dart:17
// and web_helper.dart:54), so a request only reaches this class's get() once
// a slot is actually granted.
//
// IMPORTANT COVERAGE NOTE: this only sees requests that go through
// CachedNetworkImage/flutter_cache_manager with `cacheManager:
// perfDiagnosticCacheManager` explicitly set. Flutter's native
// precacheImage(NetworkImage(url)) does NOT go through this file at all —
// it uses a completely separate HTTP path. HomeScreen.dart's _precacheBatch
// was fixed to use CachedNetworkImageProvider with this same cache manager
// specifically so that path is visible here too — if a new precache call is
// ever added elsewhere without doing that, it will be invisible to this
// instrumentation.
//
// Also dedupes concurrent/near-concurrent requests for the same URL itself
// (see _inFlight below) — the same vendor image can appear in three separate
// Home-screen carousels (main list, New Arrivals, Popular), each becoming
// scroll-visible at a slightly different moment. WebHelper's own _memCache
// dedup is timing-sensitive and was observed NOT catching every one of these
// in practice (real device logs showed fetch#2/#3/#4 for the same URL) —
// this guarantees correctness regardless of that timing, since it's the
// actual network chokepoint no matter what happens in the layers above it.
//
// Remove this file (and its call sites in HomeScreen.dart) once the
// root-cause investigation is done.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager/src/web/mime_converter.dart';
import 'package:http/http.dart' as http;

int _activeNetworkRequests = 0;
final Map<String, int> _fetchCountByUrl = {};

// Populated by widgets/precache calls the moment they ask for an image —
// BEFORE any network-layer involvement — via tagImageRequest() below. Lets
// REQUEST START compute real queue-wait time (ask → actual dispatch) and
// tag every network-layer log line with which Home-screen section the URL
// belongs to and what triggered the request.
final Map<String, Set<String>> _urlSections = {};
final Map<String, DateTime> _urlAskTime = {};
final Map<String, Set<String>> _urlTriggers = {};

/// Call this at the moment a widget (or precacheImage) is about to request
/// [url], before any network activity — e.g. in a StatefulWidget's build()
/// right before constructing the image widget. [section] is a human label
/// like "Story", "TopBanner", "NewArrival", "RestaurantList",
/// "MiddleBanner"; [trigger] identifies the mechanism, e.g.
/// "widget-build" or "precacheImage".
void tagImageRequest(String url, {required String section, required String trigger}) {
  if (url.isEmpty) return;
  _urlSections.putIfAbsent(url, () => <String>{}).add(section);
  _urlTriggers.putIfAbsent(url, () => <String>{}).add(trigger);
  _urlAskTime.putIfAbsent(url, () => DateTime.now());
}

String _sectionTag(String url) {
  final sections = _urlSections[url];
  if (sections == null || sections.isEmpty) return 'Unlabeled';
  return sections.join('+');
}

/// Public accessor so widget-layer logging (HomeScreen.dart) can show the
/// same section label the network layer uses, for easy cross-referencing.
String sectionLabelFor(String url) => _sectionTag(url);

String _triggerTag(String url) {
  final triggers = _urlTriggers[url];
  if (triggers == null || triggers.isEmpty) return 'unknown';
  return triggers.join('+');
}

class PerfTimedFileService extends FileService {
  // Overrides FileService's default of 10. Measured A/B evidence (same
  // 143,453-byte file, same network, same device): 2,248ms total when
  // downloaded alone (active=1-2) vs 28,457ms when downloaded as one of 9
  // concurrent requests — a 13x slowdown with identical bytes. dart:io's
  // HttpClient (which package:http/this class's http.Client use) only
  // speaks HTTP/1.1, not HTTP/2 — no multiplexing, so 10 "concurrent"
  // requests to the same host means 10 separate TCP+TLS connections, each
  // in its own TCP slow-start, all fighting over one real-world mobile/WiFi
  // pipe. None of them ever ramp up to good throughput. Capping this much
  // lower lets each connection actually get bandwidth instead of all of
  // them choking each other.
  @override
  int concurrentFetches = 4;

  final http.Client _httpClient = http.Client();
  final Map<String, Future<_BufferedResponse>> _inFlight = {};

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    _fetchCountByUrl[url] = (_fetchCountByUrl[url] ?? 0) + 1;
    final fetchNum = _fetchCountByUrl[url]!;

    final existing = _inFlight[url];
    if (existing != null) {
      debugPrint(
          '[HOME-PERF][NET][${_sectionTag(url)}] DEDUPED trigger=${_triggerTag(url)} — '
          'joining in-flight request instead of a fetch#$fetchNum network call — $url');
      return (await existing).toResponse();
    }

    final future = _fetchAndBuffer(url, headers, fetchNum);
    _inFlight[url] = future;
    try {
      return (await future).toResponse();
    } finally {
      // Only clear once this specific fetch settles — a slower fetch#1
      // finishing after a would-be fetch#2 already joined it is fine, the
      // map entry just needs to stay put until then.
      _inFlight.remove(url);
    }
  }

  Future<_BufferedResponse> _fetchAndBuffer(
      String url, Map<String, String>? headers, int fetchNum) async {
    _activeNetworkRequests++;
    final askTime = _urlAskTime[url];
    final now = DateTime.now();
    final queueWaitMs = askTime != null ? now.difference(askTime).inMilliseconds : null;
    final section = _sectionTag(url);
    final trigger = _triggerTag(url);
    debugPrint(
        '[HOME-PERF][NET][$section] REQUEST START (active=$_activeNetworkRequests, '
        'fetch#$fetchNum for this URL) trigger=$trigger '
        '${queueWaitMs != null ? "queueWait=${queueWaitMs}ms " : "queueWait=unknown(no widget tag) "}'
        'at ${now.toIso8601String()} — $url');

    final sw = Stopwatch()..start();
    final req = http.Request('GET', Uri.parse(url));
    if (headers != null) req.headers.addAll(headers);

    final http.StreamedResponse httpResponse;
    try {
      httpResponse = await _httpClient.send(req);
    } catch (e) {
      _activeNetworkRequests--;
      debugPrint(
          '[HOME-PERF][NET][$section] REQUEST FAILED (connect/send) after ${sw.elapsedMilliseconds}ms, '
          'active now=$_activeNetworkRequests — $url — $e');
      rethrow;
    }
    final ttfbMs = sw.elapsedMilliseconds;
    debugPrint(
        '[HOME-PERF][NET][$section] TTFB ${ttfbMs}ms (status=${httpResponse.statusCode}) — $url');

    final List<int> bytes;
    try {
      bytes = await httpResponse.stream.toBytes();
    } catch (e) {
      sw.stop();
      _activeNetworkRequests--;
      debugPrint(
          '[HOME-PERF][NET][$section] DOWNLOAD ERROR after ${sw.elapsedMilliseconds}ms, '
          'active now=$_activeNetworkRequests — $url — $e');
      rethrow;
    }
    sw.stop();
    _activeNetworkRequests--;
    debugPrint(
        '[HOME-PERF][NET][$section] REQUEST FINISH total=${sw.elapsedMilliseconds}ms '
        '(ttfb=${ttfbMs}ms, download=${sw.elapsedMilliseconds - ttfbMs}ms), '
        '${bytes.length}bytes, active now=$_activeNetworkRequests, '
        'finishedAt=${DateTime.now().toIso8601String()} — $url');

    return _BufferedResponse(
      statusCode: httpResponse.statusCode,
      headers: httpResponse.headers,
      bytes: bytes,
    );
  }
}

// Buffered (not streamed) so the same downloaded bytes can back multiple
// FileServiceResponse instances for deduped callers — a live
// http.StreamedResponse's stream can only be listened to once.
class _BufferedResponse {
  _BufferedResponse(
      {required this.statusCode, required this.headers, required this.bytes});
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bytes;
  final DateTime receivedTime = DateTime.now();

  FileServiceResponse toResponse() => _TimedHttpGetResponse(this);
}

class _TimedHttpGetResponse implements FileServiceResponse {
  _TimedHttpGetResponse(this._buffered);
  final _BufferedResponse _buffered;

  @override
  int get statusCode => _buffered.statusCode;

  String? _header(String name) => _buffered.headers[name];

  @override
  Stream<List<int>> get content => Stream.value(_buffered.bytes);

  @override
  int? get contentLength => _buffered.bytes.length;

  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final controlHeader = _header(HttpHeaders.cacheControlHeader);
    if (controlHeader != null) {
      for (final setting in controlHeader.split(',')) {
        final s = setting.trim().toLowerCase();
        if (s == 'no-cache') ageDuration = Duration.zero;
        if (s.startsWith('max-age=')) {
          final validSeconds = int.tryParse(s.split('=')[1]) ?? 0;
          if (validSeconds > 0) ageDuration = Duration(seconds: validSeconds);
        }
      }
    }
    return _buffered.receivedTime.add(ageDuration);
  }

  @override
  String? get eTag => _header(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    var ext = '';
    final contentTypeHeader = _header(HttpHeaders.contentTypeHeader);
    if (contentTypeHeader != null) {
      ext = ContentType.parse(contentTypeHeader).fileExtension;
    }
    return ext;
  }
}

// Separate cache key from the app's real DefaultCacheManager so this
// diagnostic instance doesn't share/pollute the normal disk cache database.
final CacheManager perfDiagnosticCacheManager = CacheManager(
  Config('homePerfDiagCache', fileService: PerfTimedFileService()),
);
