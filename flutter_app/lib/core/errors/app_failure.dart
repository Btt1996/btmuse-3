class AppFailure implements Exception {
  final String message;
  final String code;
  final Object? cause;

  const AppFailure(this.message, {this.code = 'unknown', this.cause});

  @override
  String toString() => 'AppFailure($code): $message';
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.code = 'network_error', super.cause});
}

class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure(super.message, {super.code = 'not_authorized', super.cause});
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.code = 'validation_error', super.cause});
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.code = 'storage_error', super.cause});
}
