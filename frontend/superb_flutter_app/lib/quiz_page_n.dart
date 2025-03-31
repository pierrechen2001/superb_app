import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert' show utf8;
import 'dart:convert' show latin1;
import 'package:shared_preferences/shared_preferences.dart';

class QuizPage extends StatefulWidget {
  final String chapter;
  final String section;
  final String knowledgePoints;
  final String levelNum;
  
  const QuizPage({
    Key? key,
    required this.chapter,
    required this.section,
    required this.knowledgePoints,
    required this.levelNum,
  }) : super(key: key);

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> questions = [];
  int currentQuestionIndex = 0;
  bool isLoading = true;
  String? selectedAnswer;
  bool? isCorrect;
  int correctAnswersCount = 0;
  int? levelId; // 添加關卡 ID 變數
  
  // 添加動畫控制器
  late AnimationController _animationController;
  late Animation<double> _animation;

  // 修改 _errorController 的聲明，移除 final 關鍵字
  TextEditingController _errorController = TextEditingController();

  // 修改 UI 風格，使其與 chat_page_s.dart 一致

  // 1. 更新顏色方案
  final Color primaryColor = Colors.white;
  final Color secondaryColor = const Color.fromARGB(255, 255, 255, 255); 
  final Color accentColor = Color.fromARGB(255, 238, 159, 41);    // 橙色強調色，類似小島的顏色
  final Color cardColor = Colors.white;      // 白色卡片背景色

  // 添加一個新的狀態變量來跟踪結果計算過程
  bool isCalculatingResult = false;

  bool isExplanationVisible = false; // Add this line to track explanation visibility

  TextStyle _textStyle({
    Color color = Colors.black,
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
  }) {
    return TextStyle(
      fontFamily: 'Medium',
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  @override
  void initState() {
    super.initState();
    // 不再需要從 API 獲取 level_id，直接使用傳入的值
    _initializeLevelId();
    _fetchQuestionsFromDatabase();
    
    // 初始化動畫控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _animationController.forward();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // 初始化 level_id
  void _initializeLevelId() {
    try {
      // 嘗試將傳入的 level_id 轉換為整數
      if (widget.levelNum.isNotEmpty) {
        levelId = int.tryParse(widget.levelNum);
        // print('使用 CSV 中的 level_id: $levelId');
      }
    } catch (e) {
      print('初始化 level_id 時出錯: $e');
    }
  }

  Future<void> _fetchQuestionsFromDatabase() async {
    try {
      // 知識點已經是字符串形式，格式為 "知識點1、知識點2、知識點3"
      final String knowledgePointsStr = widget.knowledgePoints;
      
      // print("知識點字符串: $knowledgePointsStr");
      // print("小節摘要: ${widget.section}");
      // print("關卡名稱: ${widget.section}");
      
      // 檢查是否有知識點
      if (knowledgePointsStr.isEmpty) {
        print("錯誤: 沒有提供知識點");
        setState(() {
          isLoading = false;
        });
        return;
      }
      
      // 從數據庫獲取題目
      final response = await http.post(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/get_questions_by_level'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8'
        },
        body: jsonEncode({
          'chapter': '',  // 不使用章節過濾
          'section': widget.section,  // 使用小節名稱
          'knowledge_points': knowledgePointsStr,  // 使用知識點字符串
          'user_id': await _getUserId(),  // 添加用戶ID
          'level_id': widget.levelNum,  // 添加關卡ID
        }),
      );

      // print('發送請求到: https://superb-backend-1041765261654.asia-east1.run.app/get_questions_by_level');
      // print('請求數據: ${jsonEncode({
      //   'chapter': '',
      //   'section': widget.section,
      //   'knowledge_points': knowledgePointsStr,
      // })}');

      if (response.statusCode == 200) {
        // 嘗試使用 UTF-8 解碼
        final String responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        // print('響應數據: $data');
        
        if (data['success']) {
          final List<dynamic> questionsData = data['questions'];
          
          // 檢查並處理每個題目
          List<Map<String, dynamic>> processedQuestions = [];
          for (var q in questionsData) {
            // 確保每個題目都有 id 字段
            if (q['id'] != null) {
              // 確保 correct_answer 是字符串類型
              var correctAnswer = q['correct_answer'];
              if (correctAnswer != null) {
                // 如果是數字，轉換為字符串
                if (correctAnswer is int) {
                  q['correct_answer'] = correctAnswer.toString();
                } else if (correctAnswer is String) {
                  // 如果是字符串，確保是數字格式（1-4）
                  if (!RegExp(r'^[1-4]$').hasMatch(correctAnswer)) {
                    print("警告: 題目 ${q['id']} 的正確答案格式不正確: $correctAnswer");
                  }
                }
              } else {
                print("警告: 題目 ${q['id']} 沒有正確答案");
                continue; // 跳過沒有正確答案的題目
              }
              
              // 構建選項列表
              List<dynamic> options = [];
              
              // 檢查是否有 options 字段
              if (q['options'] != null && q['options'] is List) {
                options = q['options'];
              } 
              // 如果沒有 options 字段，嘗試從 option_1, option_2 等字段構建
              else {
                // 確保所有選項字段都存在
                if (q['option_1'] != null && q['option_2'] != null) {
                  options = [
                    q['option_1'],
                    q['option_2'],
                    q['option_3'] ?? '',
                    q['option_4'] ?? '',
                  ];
                }
              }
              
              // 如果選項列表為空，跳過這個題目
              if (options.isEmpty) {
                print("警告: 題目 ${q['id']} 沒有選項，跳過");
                continue;
              }
              
              // 獲取該題目的知識點
              String knowledgePoint = "";
              
              // 嘗試從後端獲取知識點信息
              if (q['knowledge_point'] != null) {
                knowledgePoint = q['knowledge_point'];
              } else {
                // 如果後端沒有提供知識點信息，則查詢數據庫
                try {
                  final knowledgeResponse = await http.get(
                    Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/get_question_knowledge_point/${q['id']}'),
                  );
                  
                  if (knowledgeResponse.statusCode == 200) {
                    final knowledgeData = jsonDecode(utf8.decode(knowledgeResponse.bodyBytes));
                    if (knowledgeData['success'] && knowledgeData['knowledge_point'] != null) {
                      knowledgePoint = knowledgeData['knowledge_point'];
                    }
                  }
                } catch (e) {
                  print("獲取題目知識點時出錯: $e");
                }
              }
              
              // 如果仍然沒有獲取到知識點，使用傳入的知識點列表中的第一個
              if (knowledgePoint.isEmpty) {
                knowledgePoint = widget.knowledgePoints.split('、')[0];
              }
              
              processedQuestions.add({
                'id': q['id'],
                'question': q['question_text'] ?? '',
                'options': options,
                'correct_answer': q['correct_answer'].toString(), // 確保是字符串
                'explanation': q['explanation'] ?? '',
                'knowledge_point': q['knowledge_point'] ?? widget.knowledgePoints.split('、')[0], // 使用API返回的知識點，如果沒有則使用默認值
              });
              
              // 打印處理後的題目，以便調試
              // print("處理後的題目: ${processedQuestions.last}");
            } else {
              print("警告: 發現沒有 ID 的題目: $q");
            }
          }
          
          setState(() {
            questions = processedQuestions;
            isLoading = false;
          });
        } else {
          print('Error: ${data['message']}');
          setState(() {
            isLoading = false;
          });
        }
      } else {
        print('Error: ${response.statusCode}');
        setState(() {
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

  // 在用戶回答問題後調用
  void _handleAnswer(String selectedOption) {
    if (isCorrect != null) return; // 如果已經提交過答案，則不再處理

    setState(() {
      selectedAnswer = selectedOption;
      print('選擇的答案: $selectedAnswer');
    });
  }

  // Add new method to handle answer confirmation
  void _confirmAnswer() {
    if (selectedAnswer == null) return;
    
    setState(() {
      // 獲取當前題目
      final currentQuestion = questions[currentQuestionIndex];
      
      // 獲取選中選項在列表中的位置（從0開始）
      final selectedIndex = currentQuestion['options'].indexOf(selectedAnswer);
      
      // 獲取資料庫中的正確答案（已經是0-based索引）
      final correctAnswerStr = currentQuestion['correct_answer'];
      final correctAnswerIndex = int.tryParse(correctAnswerStr) ?? 0;
      
      // 直接比較索引，因為API已經將答案轉換為0-based索引
      isCorrect = selectedIndex == correctAnswerIndex;
      
      // 如果答對了，增加正確答案計數
      if (isCorrect!) {
        correctAnswersCount++;
      }
    });
    
    // 記錄答題情況
    _recordUserAnswer(questions[currentQuestionIndex]['id'], isCorrect!);
  }

  // 記錄用戶答題情況
  Future<void> _recordUserAnswer(int questionId, bool isCorrect) async {
    try {
      // 如果用戶已登入，則記錄答題情況
      final userId = await _getUserId();
      if (userId != null) {
        // 發送請求到後端 API 記錄答題情況
        final response = await http.post(
          Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/record_answer'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'question_id': questionId,
            'is_correct': isCorrect,
          }),
        );
        
        // 檢查響應
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (!data['success']) {
            print('記錄答題情況失敗：${data['message']}');
          }
        } else {
          print('記錄答題情況失敗，狀態碼：${response.statusCode}');
        }
      }
    } catch (e) {
      print('Error recording answer: $e');
    }
  }

  // 獲取用戶 ID 的方法
  Future<String?> _getUserId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');
      if (userId != null && userId.isNotEmpty) {
        return userId; // 直接返回字串
      }
      return null;
    } catch (e) {
      print("獲取用戶 ID 時出錯: $e");
      return null;
    }
  }

  void _nextQuestion() {
    if (currentQuestionIndex < questions.length - 1) {
      // Reset animation
      _animationController.reset();
      
      setState(() {
        currentQuestionIndex++;
        selectedAnswer = null;
        isCorrect = null;
        isExplanationVisible = false; // Reset explanation visibility
      });
      
      // Play enter animation
      _animationController.forward();
    }
  }

  void _showResultDialog() {
    // 設置計算結果狀態為 true
    setState(() {
      isCalculatingResult = true;
    });
    
    // 先記錄關卡完成情況
    _completeLevel().then((_) {
      // 計算完成後，重置狀態
      setState(() {
        isCalculatingResult = false;
      });
      
      final percentage = (correctAnswersCount / questions.length * 100).round();
      String resultMessage;
      Color resultColor;
      IconData resultIcon;
      
      if (percentage >= 90) {
        resultMessage = "太棒了！你對這個部分掌握得非常好！";
        resultColor = Color(0xFF4ADE80);
        resultIcon = Icons.sentiment_very_satisfied;
      } else if (percentage >= 70) {
        resultMessage = "做得好！你已經掌握了大部分內容。";
        resultColor = Color(0xFF4ADE80);
        resultIcon = Icons.sentiment_satisfied;
      } else if (percentage >= 50) {
        resultMessage = "繼續努力！你已經理解了一半的內容。";
        resultColor = accentColor;
        resultIcon = Icons.sentiment_neutral;
      } else {
        resultMessage = "需要更多練習，不要氣餒！";
        resultColor = Color(0xFFF87171);
        resultIcon = Icons.sentiment_dissatisfied;
      }
      
      // 顯示結果對話框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: secondaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Center(
            child: Text(
              '測驗結果',
              style: _textStyle(color: const Color.fromARGB(255, 28, 49, 88), fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                resultIcon,
                color: resultColor,
                size: 64,
              ),
              SizedBox(height: 16),
              Text(
                '$percentage% 正確率',
                style: _textStyle(color: resultColor, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                '${correctAnswersCount}/${questions.length} 題答對',
                style: _textStyle(color: const Color.fromARGB(255, 28, 49, 88), fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                resultMessage,
                textAlign: TextAlign.center,
                style: _textStyle(color: const Color.fromARGB(255, 19, 31, 54), fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 關閉對話框
                Navigator.of(context).pop(); // 返回上一頁
              },
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
              ),
              child: Text(
                '返回',
                style: _textStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    });
  }

  // 顯示報告錯誤的對話框
  void _showReportErrorDialog(int? questionId) {
    print("開始顯示錯誤回報對話框，題目ID: $questionId");
    
    // 如果 questionId 為 null，使用一個默認值或顯示錯誤信息
    if (questionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('無法識別題目 ID，請稍後再試。'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) {
        print("構建錯誤回報對話框");
        return AlertDialog(
          backgroundColor: secondaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.report_problem_outlined,
                color: accentColor,
                size: 24,
              ),
              SizedBox(width: 10),
              Text(
                '回報題目錯誤',
                style: _textStyle(color: const Color.fromARGB(255, 28, 49, 88), fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '請描述題目的錯誤之處：',
                  style: _textStyle(color: const Color.fromARGB(255, 131, 141, 159), fontSize: 15),
                ),
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _errorController,
                    maxLines: 4,
                    style: _textStyle(color: const Color.fromARGB(255, 28, 49, 88), fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '例如：選項有誤、答案不正確、題目敘述不清...',
                      hintStyle: _textStyle(color: const Color.fromARGB(255, 113, 121, 137), fontSize: 14),
                      contentPadding: EdgeInsets.all(16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withOpacity(0.7),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '取消',
                style: _textStyle(fontSize: 15),
              ),
              onPressed: () {
                print("取消錯誤回報");
                Navigator.of(context).pop();
                _errorController.clear();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                '送出回報',
                style: _textStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                print("送出錯誤回報");
                if (_errorController.text.trim().isNotEmpty) {
                  print("回報內容: ${_errorController.text.trim()}");
                  _reportQuestionError(questionId, _errorController.text.trim());
                  Navigator.of(context).pop();
                  
                  // 顯示成功提示
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 10),
                          Text('回報成功，感謝您的反饋！'),
                        ],
                      ),
                      backgroundColor: Color(0xFF4ADE80),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: EdgeInsets.all(10),
                    ),
                  );
                  
                  _errorController.clear();
                }
              },
            ),
          ],
          actionsPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );
      },
    );
  }
  
  // 發送錯誤報告到後端
  Future<void> _reportQuestionError(int? questionId, String errorMessage) async {
    if (questionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('無法識別題目 ID，請稍後再試。'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    try {
      final response = await http.post(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/report_question_error'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question_id': questionId,
          'error_message': errorMessage,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('感謝您的回報！我們會盡快處理。'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('回報失敗：${data['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('回報失敗，請稍後再試。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('回報題目錯誤時出錯: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('回報失敗，請檢查網絡連接。'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 在用戶完成所有題目後調用
  Future<void> _completeLevel() async {
    try {
      // 獲取用戶 ID
      String? userId = await _getUserId();
      if (userId == null) {
        print('無法保存關卡記錄: 用戶未登入');
        return;
      }
      
      if (levelId == null) {
        print('無法保存關卡記錄: 關卡 ID 未知');
        return;
      }
      
      print('開始提交關卡完成記錄: user_id=$userId, level_id=$levelId');
      
      // 準備請求數據
      final requestData = {
        'user_id': userId,
        'level_id': levelId,
        'stars': _calculateStars(correctAnswersCount, questions.length),  // 根據正確率計算星星數
      };
      
      print('請求數據: $requestData');
      
      final response = await http.post(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/complete_level'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestData),
      );
      
      print('收到響應: 狀態碼=${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        print('響應數據: $data');
        
        if (data['success']) {
          print('關卡完成記錄已保存');
        } else {
          print('保存關卡記錄失敗: ${data['message']}');
        }
      } else {
        print('保存關卡記錄失敗: HTTP ${response.statusCode}');
        print('響應內容: ${response.body}');
      }
    } catch (e) {
      print('Error completing level: $e');
    }
  }

  // 根據正確率計算星星數
  int _calculateStars(int correctCount, int totalQuestions) {
    final percentage = (correctCount / totalQuestions * 100).round();
    if (percentage >= 90) return 3;  // 90% 以上獲得 3 星
    if (percentage >= 70) return 2;  // 70% 以上獲得 2 星
    if (percentage >= 50) return 1;  // 50% 以上獲得 1 星
    return 0;  // 50% 以下獲得 0 星
  }

  // Add this method to toggle explanation visibility
  void _toggleExplanation() {
    setState(() {
      isExplanationVisible = !isExplanationVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 在這裡檢查 selectedAnswer 是否為 null
    if (selectedAnswer == null) {
        print('尚未選擇任何答案。'); // 調試訊息
    }

    // 底部按鈕邏輯
    Widget bottomButtons = isCalculatingResult 
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: accentColor,
              ),
              SizedBox(height: 16),
              Text(
                "正在分析測驗結果...",
                style: _textStyle(color: secondaryColor, fontSize: 16),
              ),
            ],
          ),
        )
      : Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 如果不是最後一題，顯示下一題按鈕
            if (currentQuestionIndex < questions.length - 1)
              ElevatedButton(
                onPressed: isCorrect != null ? _nextQuestion : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  '下一題',
                  style: _textStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              )
            else if (isCorrect != null)
              ElevatedButton(
                onPressed: _showResultDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  '完成測驗',
                  style: _textStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
          
            // 顯示題目進度
            Text(
              '${currentQuestionIndex + 1}/${questions.length}',
              style: _textStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        );

    // 修改 Scaffold 以處理不同的狀態
    return Scaffold(
      backgroundColor: primaryColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: Text(
          '${widget.section}',
          style: _textStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: primaryColor,
        ),
        child: SafeArea(
          child: isLoading 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: accentColor),
                    SizedBox(height: 16),
                    Text(
                      '載入題目中...',
                      style: _textStyle(color: Colors.black, fontSize: 16),
                    ),
                  ],
                ),
              )
            : questions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: accentColor,
                        size: 64,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '無法載入題目',
                        style: _textStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '請檢查網絡連接或稍後再試',
                        style: _textStyle(color: Colors.black.withOpacity(0.8), fontSize: 16),
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          '返回上一頁',
                          style: _textStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 添加頂部間距
                    SizedBox(height: 16),
                    
                    // 進度條
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '問題 ${currentQuestionIndex + 1}/${questions.length}',
                                style: _textStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              // 添加「題目有誤」按鈕
                              TextButton.icon(
                                icon: Icon(Icons.report_problem_outlined, color: accentColor, size: 16),
                                label: Text(
                                  '題目有誤',
                                  style: _textStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size(0, 0),
                                  backgroundColor: secondaryColor.withOpacity(0.3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () {
                                  print("按下題目有誤按鈕");
                                  if (questions.isNotEmpty && currentQuestionIndex < questions.length) {
                                    // 檢查 id 是否存在
                                    final questionId = questions[currentQuestionIndex]['id'];
                                    print("當前題目: ${questions[currentQuestionIndex]}");
                                    print("顯示錯誤回報對話框，題目ID: $questionId");
                                    _showReportErrorDialog(questionId);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('無法識別當前題目，請稍後再試。'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (currentQuestionIndex + 1) / questions.length,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                            borderRadius: BorderRadius.circular(10),
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      child: FadeTransition(
                        opacity: _animation,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 知識點標籤
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  questions[currentQuestionIndex]['knowledge_point'],
                                  style: _textStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ),
                              SizedBox(height: 16),
                              
                              // 題目文字 - 使用卡片風格
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  questions[currentQuestionIndex]['question'],
                                  style: _textStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                              ),
                              SizedBox(height: 24),
                              
                              // 選項 - 使用更現代的卡片風格
                              Column(
                                children: questions[currentQuestionIndex]['options'].asMap().entries.map<Widget>((entry) {
                                  final index = entry.key;
                                  final option = entry.value;
                                  final isSelected = selectedAnswer == option;
                                  
                                  // 獲取正確答案索引（已經是0-based）
                                  final correctAnswerIndex = int.tryParse(questions[currentQuestionIndex]['correct_answer']) ?? 0;
                                  
                                  // 判斷這個選項是否是正確答案
                                  final isCorrectOption = index == correctAnswerIndex;
                                  
                                  Color optionColor = secondaryColor.withOpacity(0.7);
                                  IconData? trailingIcon;
                                  Color iconColor = Colors.white;
                                  
                                  if (isCorrect != null) {
                                    // 答案已提交
                                    if (isCorrectOption) {
                                      // 這是正確答案
                                      optionColor = Color(0xFF4ADE80).withOpacity(0.2);
                                      trailingIcon = Icons.check_circle;
                                      iconColor = Color(0xFF4ADE80);
                                    } else if (isSelected) {
                                      // 這是用戶選擇的錯誤答案
                                      optionColor = Color(0xFFF87171).withOpacity(0.2);
                                      trailingIcon = Icons.cancel;
                                      iconColor = Color(0xFFF87171);
                                    }
                                  } else if (isSelected) {
                                    // 答案未提交，但已選擇
                                    optionColor = accentColor.withOpacity(0.2);
                                  }
                                  
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: isCorrect != null ? null : () {
                                          _handleAnswer(option);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: optionColor,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isCorrect != null
                                                  ? (isCorrectOption 
                                                      ? Color(0xFF4ADE80)  // Green for correct answer
                                                      : (isSelected ? Color(0xFFF87171) : Colors.transparent))  // Red for selected wrong answer
                                                  : (isSelected ? accentColor : Colors.transparent),  // Orange for selection before submission
                                              width: 2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  option,
                                                  style: _textStyle(color: Colors.black, fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                                                ),
                                              ),
                                              if (trailingIcon != null)
                                                Icon(
                                                  trailingIcon,
                                                  color: iconColor,
                                                  size: 24,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              
                              SizedBox(height: 24),
                              
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            color: primaryColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isCorrect == null 
                      ? (selectedAnswer != null ? _confirmAnswer : null)  // 確認答案
                      : (currentQuestionIndex < questions.length - 1 ? _nextQuestion : _showResultDialog),  // 下一題或完成測驗
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
                        if (states.contains(MaterialState.disabled)) {
                          // 當按鈕被禁用時（未選擇答案）
                          return Colors.grey[300]!;
                        }
                        // 當按鈕啟用時（已選擇答案）
                        return accentColor;
                      }),
                      foregroundColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
                        if (states.contains(MaterialState.disabled)) {
                          // 當按鈕被禁用時的文字顏色
                          return Colors.black;
                        }
                        // 當按鈕啟用時的文字顏色
                        return Colors.white;
                      }),
                      padding: MaterialStateProperty.all(
                        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      elevation: MaterialStateProperty.all(0),
                    ),
                    child: Text(
                      isCorrect == null 
                        ? '確認答案'  // 未確認答案時
                        : (currentQuestionIndex < questions.length - 1 ? '下一題' : '完成測驗'),  // 已確認答案時
                      style: _textStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                // Replace question counter with explanation toggle button
                if (isCorrect != null)
                  ElevatedButton(
                    onPressed: _toggleExplanation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isExplanationVisible ? Colors.grey[300] : accentColor,
                      foregroundColor: isExplanationVisible ? Colors.black : Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isExplanationVisible ? '隱藏詳解' : '查看詳解',
                      style: _textStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          // Add collapsible explanation section
          if (isCorrect != null && isExplanationVisible)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isCorrect! ? Color(0xFF4ADE80) : Color(0xFFF87171),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCorrect! ? Icons.check_circle : Icons.cancel,
                        color: isCorrect! ? Color(0xFF4ADE80) : Color(0xFFF87171),
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Text(
                        isCorrect! ? '答對了！' : '答錯了！',
                        style: _textStyle(
                          color: isCorrect! ? Color(0xFF4ADE80) : Color(0xFFF87171),
                          fontSize: 18,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    '解釋：',
                    style: _textStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    questions[currentQuestionIndex]['explanation'] ?? '無解釋',
                    style: _textStyle(color: Colors.black.withOpacity(0.9), fontSize: 16),
                  ),
                ],
              ),
            ),
          // 添加底部導航圖片
          Image.asset(
            'assets/images/quiz-nav.png',
            fit: BoxFit.contain,
            width: double.infinity,
          ),
        ],
      ),
    );
  }
}