import 'package:flutter_easyloading/flutter_easyloading.dart';

class ShowToastDialog {
  static showToast(String? message, {EasyLoadingToastPosition position = EasyLoadingToastPosition.top}) {
    EasyLoading.showToast(message!, toastPosition: position);
  }

  static showLoader(String message) {
    EasyLoading.show(status: message);
  }

  static closeLoader() {
    EasyLoading.dismiss();
  }

  // Transitions the SAME overlay the loading spinner was just showing into
  // a checkmark + message, then auto-dismisses (2026-08-27) - used right
  // when a slow action (login, signup) actually succeeds, so any residual
  // delay before navigation reads as "done" rather than looking like the
  // spinner is stuck/still working.
  static showSuccess(String message) {
    EasyLoading.showSuccess(message);
  }
}
