import 'package:flutter/material.dart';
import 'dart:async';

import 'package:treesitter/src/tree_sitter_ffi.dart';
import 'package:treesitter_c/treesitter_c.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    var parser = Parser();
    parser.setLanguage(TreeSitterC());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Packages')),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              ],
            ),
          ),
        ),
      ),
    );
  }
}
