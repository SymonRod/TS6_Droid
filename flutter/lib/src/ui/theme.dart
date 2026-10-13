import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7DD1), brightness: b),
    );
