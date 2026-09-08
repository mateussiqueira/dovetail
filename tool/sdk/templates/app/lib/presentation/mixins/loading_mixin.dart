import 'package:flutter/foundation.dart';

mixin LoadingMixin on ChangeNotifier {
  bool _loadingIsLoading = false;

  bool get isLoading => _loadingIsLoading;

  void setLoading(bool value) {
    if (_loadingIsLoading == value) return;
    _loadingIsLoading = value;
    notifyListeners();
  }

  Future<T> withLoading<T>(Future<T> Function() action) async {
    setLoading(true);
    try {
      return await action();
    } finally {
      setLoading(false);
    }
  }
}
