import 'dart:ffi';
import 'dart:io';

import 'package:treesitter/src/tree_sitter_abstract.dart';

final DynamicLibrary _lib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.process();
  } else if (Platform.isLinux || Platform.isFuchsia || Platform.isAndroid) {
    return DynamicLibrary.open('libtree_sitter_c.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('tree_sitter_c.dll');
  } else {
    throw UnsupportedError('Unsupported platform');
  }
}();

final Pointer<Void> Function() _languageFn =
    _lib
        .lookup<NativeFunction<Pointer<Void> Function()>>('tree_sitter_c')
        .asFunction();

class TreeSitterc extends TreeSitterLanguage {
  @override
  String get languageId => 'c';

  @override
  dynamic getLanguagePtr() {
    return _languageFn().address;
  }
}
