import 'package:rxdart/rxdart.dart';

enum PlaybackState { pause, play, next, previous }

class StoryController {
  final playbackNotifier = BehaviorSubject<PlaybackState>();

  // Fires when a video detects its actual runtime duration after initialisation.
  // StoryViewState listens to this and corrects the animation controller so the
  // progress bar matches the true video length (fixes the black-screen overshoot).
  final durationNotifier = BehaviorSubject<Duration>();

  // Fires true when the video player stalls waiting for data, false when the
  // buffer fills and playback resumes. Used by _VendorStoryPageState to pause
  // the view-count timer during buffer stalls so wall-clock time is not counted
  // as watch time.
  final bufferingNotifier = BehaviorSubject<bool>.seeded(false);

  void pause() => playbackNotifier.add(PlaybackState.pause);
  void play() => playbackNotifier.add(PlaybackState.play);
  void next() => playbackNotifier.add(PlaybackState.next);
  void previous() => playbackNotifier.add(PlaybackState.previous);

  void notifyDuration(Duration d) {
    if (!durationNotifier.isClosed) durationNotifier.add(d);
  }

  void notifyBuffering(bool isBuffering) {
    if (!bufferingNotifier.isClosed) bufferingNotifier.add(isBuffering);
  }

  void dispose() {
    playbackNotifier.close();
    durationNotifier.close();
    bufferingNotifier.close();
  }
}
