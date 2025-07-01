export './src/tree_sitter_abstract.dart';

export './src/tree_sitter.dart'
    if (dart.library.ffi) './src/treesitter_ffi.dart'
    if (dart.library.html) './src/treesitter_web.dart';
