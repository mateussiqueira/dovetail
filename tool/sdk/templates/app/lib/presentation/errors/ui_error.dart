import 'package:{{name}}/domain/errors/domain_error.dart';

enum UIError {
  domain,
  unexpected;

  static UIError fromDomainError(DomainError error) => UIError.domain;
}
