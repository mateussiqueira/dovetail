import 'package:flutter/foundation.dart';
import 'package:{{name}}/domain/errors/domain_error.dart';
import 'package:{{name}}/presentation/errors/ui_error.dart';

mixin ErrorHandlingMixin on ChangeNotifier {
  UIError? _errorHandlingError;

  UIError? get error => _errorHandlingError;

  bool get hasError => _errorHandlingError != null;

  void setError(UIError? error) {
    if (_errorHandlingError == error) return;
    _errorHandlingError = error;
    notifyListeners();
  }

  void clearError() {
    if (_errorHandlingError == null) return;
    _errorHandlingError = null;
    notifyListeners();
  }

  Future<T> handleError<T>(
    Future<T> Function() action, {
    UIError? fallbackError,
  }) async {
    clearError();
    try {
      return await action();
    } on DomainError catch (e) {
      setError(UIError.fromDomainError(e));
      rethrow;
    } catch (_) {
      setError(fallbackError ?? UIError.unexpected);
      rethrow;
    }
  }

  /// Mesmo mapeamento do [handleError], sem repropagar: o erro já virou
  /// [UIError] e quem chama não tem o que fazer com a exceção. Devolve
  /// `null` quando a ação falhou.
  Future<T?> guard<T>(
    Future<T> Function() action, {
    UIError? fallbackError,
  }) async {
    try {
      return await handleError(action, fallbackError: fallbackError);
    } catch (_) {
      return null;
    }
  }
}
