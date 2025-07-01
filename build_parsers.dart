import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || !args.any((arg) => arg.startsWith('-f='))) {
    print(
      'Usage: dart build_parsers.dart -f=<parsers.json> -only=<parser_name>',
    );
    return;
  }

  var parsersFile = 'parsers.json';

  args.forEach((arg) {
    if (arg.startsWith('-f=')) {
      parsersFile = arg.substring(3);
    }
  });

  var onlyParser = args.firstWhere(
    (arg) => arg.startsWith('-only='),
    orElse: () => '',
  );

  var json =
      jsonDecode(await File(parsersFile).readAsString()) as List<dynamic>;
  for (var parser in json) {
    if (parser is Map<String, dynamic>) {
      if (onlyParser.isNotEmpty &&
          !onlyParser.endsWith(parser['name'] as String)) {
        continue;
      }
      await buildParser(parser, args);
    } else {
      print('Invalid parser entry: $parser');
    }
  }
}

String join(String a, String b) => a.endsWith('/') ? '$a$b' : '$a/$b';

Future<void> buildParser(
  Map<String, dynamic> options,
  List<String> args,
) async {
  var parserName = options['name'] as String?;
  if (parserName == null) {
    print('Parser name is missing in options: $options');
    return;
  }
  final parserVersion = options['version'] as String?;
  if (parserVersion == null) {
    print('Parser version is missing for $parserName in options: $options');
    return;
  }
  final parserUrl = options['url'] as String?;
  if (parserUrl == null) {
    print('Parser URL is missing for $parserName in options: $options');
    return;
  }
  print('Building parser: $parserName v$parserVersion from $parserUrl');

  final parserPath = 'build/$parserName';
  final parserDir = Directory(parserPath);
  if (parserDir.existsSync()) {
    parserDir.deleteSync(recursive: true);
    print('Deleted existing directory: $parserPath');
  }
  cloneRepo(parserUrl, parserPath);
  await buildAllTargets(parserName, parserPath, args);
  await createPackage(parserName, parserPath);
}

cloneRepo(String url, String path) {
  final result = Process.runSync('git', ['clone', url, path], runInShell: true);
  if (result.exitCode != 0) {
    print('Failed to clone $url: ${result.stderr}');
  } else {
    print('Cloned $url to $path');
  }
}

Future<void> buildAllTargets(
  String parserName,
  String parserPath,
  List<String> args,
) async {
  final srcDir = Directory(join(parserPath, 'src'));
  final parserC = File(join(srcDir.path, 'parser.c'));
  if (!parserC.existsSync()) {
    print('Missing parser.c for $parserName');
    return;
  }

  final scannerC = File(join(srcDir.path, 'scanner.c'));
  final hasScanner = scannerC.existsSync();
  print("PATH: ${Platform.environment['ANDROID_NDK_HOME']}");

  await buildXCFramework(parserName, parserPath, hasScanner);
  await buildLinux(parserName, parserPath, hasScanner);
  await buildAndroid(parserName, parserPath, hasScanner, args);
  await buildWindows(parserName, parserPath, hasScanner);
  await buildWasm(parserName, parserPath, hasScanner);
}

Future<void> buildXCFramework(String name, String path, bool hasScanner) async {
  final buildDir = Directory(join(path, 'darwin'));
  buildDir.createSync(recursive: true);

  final parserObj = await _compileToObject(
    join(path, 'src/parser.c'),
    join(buildDir.path, 'parser.o'),
  );
  final objects = [parserObj];

  if (hasScanner) {
    final scannerObj = await _compileToObject(
      join(path, 'src/scanner.c'),
      join(buildDir.path, 'scanner.o'),
    );
    objects.add(scannerObj);
  }

  final staticLib = join(buildDir.path, 'lib$name.a');
  final arResult = await Process.run('ar', ['rcs', staticLib, ...objects]);
  if (arResult.exitCode != 0) {
    print('Failed to archive static lib: ${arResult.stderr}');
    return;
  }

  final xcOutput = join(path, 'tree_sitter_$name.xcframework');
  final xcodeResult = await Process.run('xcodebuild', [
    '-create-xcframework',
    '-library',
    staticLib,
    '-headers',
    join(path, 'src'),
    '-output',
    xcOutput,
  ]);

  if (xcodeResult.exitCode != 0) {
    print('xcodebuild failed: ${xcodeResult.stderr}');
  } else {
    print('✅ Built XCFramework for $name at $xcOutput');
  }
}

Future<void> buildLinux(String name, String path, bool hasScanner) async {
  final outPath = join(path, 'libtree_sitter_$name.so');
  final files = ['$path/src/parser.c'];
  if (hasScanner) files.add('$path/src/scanner.c');

  final compiler =
      '/opt/homebrew/Cellar/musl-cross/0.9.9_2/libexec/bin/x86_64-linux-musl-gcc';
  final result = await Process.run(compiler, [
    '-shared',
    '-fPIC',
    '-O3',
    '-o',
    outPath,
    ...files,
  ]);

  if (result.exitCode != 0) {
    print('Linux build failed: ${result.stderr}');
  } else {
    print('✅ Built Linux .so for $name');
  }
}

Future<void> buildAndroid(
  String name,
  String path,
  bool hasScanner,
  List<String> args,
) async {
  final outDir = Directory(join(path, 'android/'));
  outDir.createSync(recursive: true);

  final files = ['$path/src/parser.c'];
  if (hasScanner) files.add('$path/src/scanner.c');

  final outPath = join(outDir.path, 'libtree_sitter_$name.so');

  var ndkPath = args.firstWhere(
    (arg) => arg.startsWith('-ndk='),
    orElse: () => '',
  );
  if (ndkPath.isNotEmpty) {
    ndkPath = ndkPath.substring(5);
  } else {
    ndkPath = Platform.environment['ANDROID_NDK_HOME'] ?? '';
  }
  if (ndkPath.isEmpty) {
    print("ANDROID_NDK_HOME must be set");
    return;
  }
  final clang = join(
    ndkPath,
    'toolchains/llvm/prebuilt/darwin-x86_64/bin/clang',
  );

  final target = 'aarch64-linux-android21'; // 64-bit Android, API level 21+
  final sysroot = join(
    ndkPath,
    'toolchains/llvm/prebuilt/darwin-x86_64/sysroot',
  );

  final result = await Process.run(clang, [
    '--target=$target',
    '--sysroot=$sysroot',
    '-shared',
    '-fPIC',
    '-O3',
    '-o',
    outPath,
    ...files,
  ]);

  if (result.exitCode != 0) {
    print('Android build failed: ${result.stderr}');
  } else {
    print('✅ Built Android .so for $name at $outPath');
  }
}

Future<void> buildWindows(String name, String path, bool hasScanner) async {
  final outPath = join(path, 'libtree_sitter_$name.dll');
  final files = ['$path/src/parser.c'];
  if (hasScanner) files.add('$path/src/scanner.c');

  final result = await Process.run('x86_64-w64-mingw32-gcc', [
    '-shared',
    '-O3',
    '-o',
    outPath,
    ...files,
  ]);

  if (result.exitCode != 0) {
    print('Windows build failed: ${result.stderr}');
  } else {
    print('✅ Built Windows .dll for $name');
  }
}

Future<void> buildWasm(String name, String path, bool hasScanner) async {
  final outPath = join(path, 'libtree_sitter_$name.dll');
  final files = ['$path/src/parser.c'];
  if (hasScanner) files.add('$path/src/scanner.c');

  final result = await Process.run('emcc', [
    ...files,
    '-s',
    'SIDE_MODULE=1',
    '-O3',
    '-o',
    outPath,
  ]);

  if (result.exitCode != 0) {
    print('WASM build failed: ${result.stderr}');
  } else {
    print('✅ Built WebAssembly .wasm for $name');
  }
}

Future<String> _compileToObject(String inputPath, String outputPath) async {
  final result = await Process.run('clang', [
    '-c',
    inputPath,
    '-o',
    outputPath,
  ]);

  if (result.exitCode != 0) {
    print('Failed to compile $inputPath: ${result.stderr}');
  }

  return outputPath;
}

Future<void> createPackage(String name, String buildPath) async {
  var packageName = "treesitter_$name";
  if (Directory('./parsers/$packageName()').existsSync()) {
    print('Deleting existing package for $name');
    Directory('./parsers/$packageName').deleteSync(recursive: true);
  }
  var result = Process.runSync('flutter', [
    'create',
    '--template=plugin_ffi',
    '--description=Tree-sitter $name parser',
    '--platforms=ios,macos,linux,windows,android',
    './parsers/$packageName',
  ]);

  if (result.exitCode != 0) {
    print('✅ Failed to create package: ${result.stderr}');
    return;
  }
  await copyParsers(packageName, name, buildPath);
  await setupPlatforms(packageName, name);
  print('Created package for $name at ./parsers/treesitter_$name');
}

Future<void> copyParsers(
  String packageName,
  String parserName,
  String buildPath,
) async {
  final packagePath = './parsers/$packageName';

  // List of files and where they go
  final copyJobs = [
    ("$buildPath/tree_sitter_$parserName.xcframework", "$packagePath/ios"),
    ("$buildPath/tree_sitter_$parserName.xcframework", "$packagePath/macos"),
    ("$buildPath/libtree_sitter_$parserName.so", "$packagePath/linux"),
    (
      "$buildPath/android/libtree_sitter_$parserName.so",
      "$packagePath/android",
    ),
    ("$buildPath/libtree_sitter_$parserName.dll", "$packagePath/windows"),
  ];

  for (final (src, dest) in copyJobs) {
    final destDir = Directory(dest);
    destDir.createSync(recursive: true);

    final result = await Process.run('cp', ['-r', src, dest]);
    if (result.exitCode != 0) {
      print('❌ Failed to copy $src to $dest: ${result.stderr}');
    } else {
      print('✅ Copied $src → $dest');
    }
  }

  print('🎉 Finished copying for package: $packageName ($packagePath)');
}

Future<void> setupPlatforms(String packageName, String parserName) async {
  final packagePath = './parsers/$packageName';
  final xcframeworkName = 'tree_sitter_$parserName.xcframework';

  final appleTargets = [('ios', 'ios'), ('macos', 'macos')];

  for (final (platform, dirName) in appleTargets) {
    final platformPath = join(packagePath, dirName);
    final podspecPath = join(platformPath, '$packageName.podspec');
    final vendoredLine = "s.vendored_frameworks = '$xcframeworkName'";

    final dir = Directory(platformPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final podspecFile = File(podspecPath);
    String content;

    if (!podspecFile.existsSync()) {
      content = '''
Pod::Spec.new do |s|
  s.name             = '$packageName'
  s.version          = '0.0.1'
  s.summary          = 'Tree-sitter parser for $parserName'
  s.description      = 'Auto-generated parser wrapper for $parserName.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Generated' => 'noreply@example.com' }
  s.source           = { :git => 'https://example.com/repo.git', :tag => 'v0.0.1' }
  s.platform         = :$platform, '11.0'
  $vendoredLine
end
''';
      print('📄 Created new podspec at $podspecPath');
    } else {
      content = await podspecFile.readAsString();

      if (content.contains('s.vendored_frameworks')) {
        content = content.replaceAllMapped(
          RegExp(r"s\.vendored_frameworks\s*=.*"),
          (_) => vendoredLine,
        );
        print('🔁 Updated vendored_frameworks in $podspecPath');
      } else {
        final match = RegExp(
          r'^\s*end\s*$',
          multiLine: true,
        ).firstMatch(content);
        if (match != null) {
          final insertPos = match.start;
          content =
              content.substring(0, insertPos) +
              '  $vendoredLine\n' +
              content.substring(insertPos);
          print('➕ Inserted vendored_frameworks in $podspecPath');
        } else {
          content += '\n$vendoredLine\nend\n';
          print('⚠️ No `end` found, appended line in $podspecPath');
        }
      }
    }

    await podspecFile.writeAsString(content);
  }

  print('✅ Finished setup for $packageName ($parserName)');
}
