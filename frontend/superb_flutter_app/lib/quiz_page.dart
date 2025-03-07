import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:convert' show LineSplitter;

class QuizPage extends StatefulWidget {
  // 儲存章節名稱
  final String section;
  // 儲存知識點資訊
  final Map<String, dynamic> knowledgePoints;
  // 儲存章節摘要
  final String sectionSummary;

  QuizPage({
    required this.section,
    required this.knowledgePoints,
    required this.sectionSummary,
  });

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  // 儲存所有題目的列表
  List<Map<String, dynamic>> questions = [];
  // 當前顯示的題目索引
  int currentQuestionIndex = 0;
  // 控制載入狀態
  bool isLoading = true;
  // 使用者選擇的答案
  String? selectedAnswer;
  // 判斷答案是否正確
  bool? isCorrect;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      // 向後端 API 發送請求獲取題目
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/generate_questions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'section': widget.section,
          'knowledge_points': widget.knowledgePoints,
          'section_summary': widget.sectionSummary,
        }),
      );

      print('API Response: ${response.body}');
      
      if (response.statusCode == 200) {
        // 清理回應內容：移除引號和處理換行符
        final cleanResponse = response.body
            .replaceAll('"', '')  // 移除引號
            .replaceAll('\\n', '\n')  // 處理跳脫的換行符
            .trim();  // 移除前後空白
        
        final rows = cleanResponse.split('\n');
        
        // 打印每題資訊
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].trim().isEmpty) continue;
          
          final cols = rows[i].split(',');
          if (cols.length >= 7) {
            print('第${i + 1}題');
            print('題目：${utf8.decode(cols[1].codeUnits)}');
            print('選項：A.${utf8.decode(cols[3].codeUnits)}, ' +
                  'B.${utf8.decode(cols[4].codeUnits)}, ' +
                  'C.${utf8.decode(cols[5].codeUnits)}, ' +
                  'D.${utf8.decode(cols[6].codeUnits)}');
            print('正確答案：${cols[2]}');
            print('-------------------');
          }
        }

        // 解析每一行資料為題目物件
        final List<Map<String, dynamic>> parsedQuestions = [];
        for (var row in rows) {
          if (row.trim().isEmpty) continue; // 跳過空行
          
          final cols = row.split(',');
          if (cols.length >= 7) {
            try {
              // 將每個題目轉換為結構化資料
              parsedQuestions.add({
                'knowledge_point': utf8.decode(cols[0].codeUnits),
                'question': utf8.decode(cols[1].codeUnits),
                'correct_answer': utf8.decode(cols[2].codeUnits),
                'options': [
                  utf8.decode(cols[3].codeUnits),
                  utf8.decode(cols[4].codeUnits),
                  utf8.decode(cols[5].codeUnits),
                  utf8.decode(cols[6].codeUnits),
                ],
              });
            } catch (e) {
              print('Error parsing row: $e');
            }
          }
        }

        setState(() {
          questions = parsedQuestions;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching questions: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _checkAnswer() {
    // 檢查答案是否正確
    final currentQuestion = questions[currentQuestionIndex];
    try {
      // 打印調試信息
      print('Correct answer string: ${currentQuestion['correct_answer']}');
      
      // 確保正確答案是數字字符串
      final correctAnswerString = currentQuestion['correct_answer'].trim();
      final correctAnswerIndex = int.parse(correctAnswerString) - 1;
      final correctAnswer = currentQuestion['options'][correctAnswerIndex];
      
      setState(() {
        // 比對使用者選擇的答案是否正確
        isCorrect = selectedAnswer == correctAnswer;
        print('Selected: $selectedAnswer');
        print('Correct: $correctAnswer');
        print('Is Correct: $isCorrect');
      });
    } catch (e) {
      print('Error in _checkAnswer: $e');
      print('Current question: $currentQuestion');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 顯示載入中畫面
    if (isLoading) {
      return Scaffold(
        backgroundColor: Color(0xFF1B3B4B),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 顯示錯誤訊息
    if (questions.isEmpty) {
      return Scaffold(
        backgroundColor: Color(0xFF1B3B4B),
        body: Center(child: Text('無法載入題目', style: TextStyle(color: Colors.white))),
      );
    }

    final currentQuestion = questions[currentQuestionIndex];

    return Scaffold(
      backgroundColor: Color(0xFF1B3B4B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('練習題 ${currentQuestionIndex + 1}/${questions.length}'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顯示題目文字
            Text(
              currentQuestion['question'],
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            // 顯示選項按鈕
            ...currentQuestion['options'].asMap().entries.map((entry) {
              // 設定選項的狀態（是否被選中、是否正確）
              final index = entry.key;
              final option = entry.value;
              final isSelected = selectedAnswer == option;
              final isCorrectAnswer = isCorrect != null && 
                  option == currentQuestion['options'][int.parse(currentQuestion['correct_answer']) - 1];
              
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  onTap: isCorrect == null ? () {
                    setState(() {
                      selectedAnswer = option;
                    });
                  } : null,
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isCorrect == null 
                              ? Colors.blue.withOpacity(0.3)
                              : (isCorrect! 
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.red.withOpacity(0.3)))
                          : (isCorrectAnswer && isCorrect != null
                              ? Colors.green.withOpacity(0.3)
                              : Colors.white.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${String.fromCharCode(65 + (index as num).toInt())}. $option',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
            Spacer(),
            // 底部導航按鈕（上一題、送出答案、下一題）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (currentQuestionIndex > 0)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        currentQuestionIndex--;
                        selectedAnswer = null;
                        isCorrect = null;
                      });
                    },
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back, color: Colors.white),
                        SizedBox(width: 8),
                        Text('上一題', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                if (selectedAnswer != null && isCorrect == null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _checkAnswer,
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('送出答案', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                if (currentQuestionIndex < questions.length - 1)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        currentQuestionIndex++;
                        selectedAnswer = null;
                        isCorrect = null;
                      });
                    },
                    child: Row(
                      children: [
                        Text('下一題', style: TextStyle(fontSize: 16)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: Colors.white),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 