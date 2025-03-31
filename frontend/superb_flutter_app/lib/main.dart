import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'home_page.dart';
import 'auth_page.dart';
import 'mistake_book.dart';
import 'chat_page_s.dart';

import 'login_page.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://sdjytgbojqslkfwfxlvs.supabase.co', // Bo
    // url: 'https://zgccuixkrlsfmsgblbpe.supabase.co', // Pierre
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkanl0Z2JvanFzbGtmd2Z4bHZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDA0NjEwNjUsImV4cCI6MjA1NjAzNzA2NX0.IAFreOpeUF0qxKyWaEbpyG3eQPWS3F58XisraV_Z8S8', // Bo
    // anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnY2N1aXhrcmxzZm1zZ2JsYnBlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU5NjI3MzksImV4cCI6MjA1MTUzODczOX0.6SVEK8ib3RDeQ7-Qj3oGUU6e0j_baKkfhH6MoL03sQM', // Pierre
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 初始化 Hive
  await Hive.initFlutter();
  await Hive.openBox('questionsBox');

  final dir = await getApplicationDocumentsDirectory();
  print("Hive 資料會儲存在這裡：${dir.path}");


  
  runApp(MyApp());
}

// MyApp: 應用程序的根組件
// 負責設置應用的整體主題、顏色方案和字體樣式
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 學習助手',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Color(0xFF102031), // 深藍色微偏綠
        colorScheme: ColorScheme.dark(
          primary: Color(0xFF102031),    // 藍綠色
          secondary: Color(0xFF2D7A8F),   // 淺藍綠色
          surface: Color(0xFF1B3B4B),     // 深藍色微偏綠
        ),
        textTheme: TextTheme(
          displayLarge: TextStyle(fontSize: 40, fontFamily: 'Heavy', fontWeight: FontWeight.bold, color: Colors.white),
          displayMedium: TextStyle(fontSize: 32, fontFamily: 'Medium', fontWeight: FontWeight.w600, color: Colors.white),
          bodyLarge: TextStyle(fontSize: 20, fontFamily: 'Normal', fontWeight: FontWeight.normal, color: Colors.white70),
          bodyMedium: TextStyle(fontSize: 16, fontFamily: 'Normal', fontWeight: FontWeight.normal, color: Colors.white70),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        '/chat': (context) => ChatPage(),
        '/auth': (context) => AuthPage(),
        '/mistakes': (context) => MistakeBookPage(),
      },
    );
  }
}
