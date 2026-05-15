import 'package:rxdart/rxdart.dart';

enum PlaybackState { pause, play, next, previous }

class StoryController {
  final playbackNotifier = BehaviorSubject<PlaybackState>();

  // Fires when a video detects its actual runtime duration after initialisation.
  // StoryViewState listens to this and corrects the animation controller so the
  // progress bar matches the true video length (fixes the black-screen overshoot).
  final durationNotifier = BehaviorSubject<Duration>();

  void pause() => playbackNotifier.add(PlaybackState.pause);
  void play() => playbackNotifier.add(PlaybackState.play);
  void next() => playbackNotifier.add(PlaybackState.next);
  void previous() => playbackNotifier.add(PlaybackState.previous);

  void notifyDuration(Duration d) {
    if (!durationNotifier.isClosed) durationNotifier.add(d);
  }

  void dispose() {
    playbackNotifier.close();
    durationNotifier.close();
  }
}
