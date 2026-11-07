/// A TDLib error with its numeric code preserved for control flow.
class TdlibRequestException extends StateError {
  TdlibRequestException(this.code, String message) : super(message);
  final int? code;
}
