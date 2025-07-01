abstract class TreeSitterLanguage {
  String get languageId;

  dynamic getLanguagePtr(); // FFI: Pointer<TSLanguage>, Web: JS interop object
}
