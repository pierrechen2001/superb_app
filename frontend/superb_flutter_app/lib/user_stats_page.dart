// 現有代碼...
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert' show utf8;  // 確保導入 utf8

class UserStatsPage extends StatefulWidget {
  const UserStatsPage({Key? key}) : super(key: key);

  @override
  _UserStatsPageState createState() => _UserStatsPageState();
}

class _UserStatsPageState extends State<UserStatsPage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  String _errorMessage = '';
  late TabController _tabController;
  
  // 更新主題色彩以匹配 chapter_detail_page_n.dart
  final Color primaryColor = Color(0xFF1E5B8C);  // 深藍色主題
  final Color secondaryColor = Color(0xFF2A7AB8); // 較淺的藍色
  final Color accentColor = Color.fromARGB(255, 238, 159, 41);    // 橙色強調色
  final Color cardColor = Color(0xFF3A8BC8);      // 淺藍色卡片背景色

  // 新增知識點分數數據
  List<Map<String, dynamic>> _knowledgeScores = [];
  // 新增學習趨勢數據
  Map<String, List<Map<String, dynamic>>> _weeklyStats = {};
  // 新增弱點知識點
  List<Map<String, dynamic>> _weakPoints = [];
  // 新增學習連續性
  int _streak = 0;
  // 新增學習建議
  List<String> _learningTips = [];
  // 新增推薦章節
  List<Map<String, dynamic>> _recommendedChapters = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchUserStats();
    _fetchKnowledgeScores();
    _fetchWeeklyStats();
    _fetchLearningSuggestions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = '請先登入';
        });
        return;
      }

      final response = await http.post(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/get_user_stats'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8',
        },
        body: jsonEncode({'user_id': user.uid}),
      );

      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = jsonDecode(jsonString);
        if (data['success']) {
          setState(() {
            _stats = data['stats'];
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = data['message'] ?? '獲取數據失敗';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '伺服器錯誤: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '發生錯誤: $e';
      });
    }
  }

  // 獲取知識點分數
  Future<void> _fetchKnowledgeScores() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final response = await http.get(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/get_knowledge_scores/${user.uid}'),
        headers: {
          'Accept': 'application/json; charset=utf-8',
        },
      );

      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = jsonDecode(jsonString);
        if (data['success']) {
          setState(() {
            _knowledgeScores = List<Map<String, dynamic>>.from(data['scores']);
            
            // 找出弱點知識點（分數低於5分的）
            _weakPoints = _knowledgeScores
                .where((score) => (score['score'] as num) < 5)
                .toList()
              ..sort((a, b) => (a['score'] as num).compareTo(b['score'] as num));
          });
        }
      }
    } catch (e) {
      print('獲取知識點分數時出錯: $e');
    }
  }

  // 獲取每週學習統計
  Future<void> _fetchWeeklyStats() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final response = await http.get(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/get_weekly_stats/${user.uid}'),
        headers: {
          'Accept': 'application/json; charset=utf-8',
        },
      );

      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = jsonDecode(jsonString);
        if (data['success']) {
          setState(() {
            _weeklyStats = {
              '本週': List<Map<String, dynamic>>.from(data['weekly_stats']['this_week']),
              '上週': List<Map<String, dynamic>>.from(data['weekly_stats']['last_week']),
            };
            _streak = data['streak'];
          });
        }
      }
    } catch (e) {
      print('獲取每週統計時出錯: $e');
    }
  }

  // 獲取學習建議
  Future<void> _fetchLearningSuggestions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final response = await http.get(
        Uri.parse('https://superb-backend-1041765261654.asia-east1.run.app/get_learning_suggestions/${user.uid}'),
        headers: {
          'Accept': 'application/json; charset=utf-8',
        },
      );

      if (response.statusCode == 200) {
        final jsonString = utf8.decode(response.bodyBytes);
        final data = jsonDecode(jsonString);
        if (data['success']) {
          setState(() {
            _weakPoints = List<Map<String, dynamic>>.from(data['weak_points']);
            _recommendedChapters = List<Map<String, dynamic>>.from(data['recommended_chapters']);
            _learningTips = List<String>.from(data['tips']);
          });
        }
      }
    } catch (e) {
      print('獲取學習建議時出錯: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的學習統計'),
        backgroundColor: primaryColor,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accentColor,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(icon: Icon(Icons.dashboard), text: '總覽'),
            Tab(icon: Icon(Icons.trending_up), text: '學習趨勢'),
            Tab(icon: Icon(Icons.psychology), text: '知識掌握'),
            Tab(icon: Icon(Icons.lightbulb), text: '學習建議'),
          ],
        ),
      ),
      body: Container(
        // 添加漸變背景，模擬海洋效果
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryColor, Color(0xFF0D3B69)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color.fromARGB(255, 238, 159, 41)),
              ))
            : _errorMessage.isNotEmpty
                ? Center(child: Text(_errorMessage, style: TextStyle(color: Colors.red)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildTrendsTab(),
                      _buildKnowledgeTab(),
                      _buildSuggestionsTab(),
                    ],
                  ),
      ),
    );
  }

  // 總覽標籤頁
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchUserStats();
        await _fetchKnowledgeScores();
        await _fetchWeeklyStats();
        await _fetchLearningSuggestions();
      },
      color: accentColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTodayStats(),
            const SizedBox(height: 24),
            _buildSubjectStats(),
            const SizedBox(height: 24),
            _buildTotalStats(),
            const SizedBox(height: 24),
            _buildRecentLevels(),
          ],
        ),
      ),
    );
  }

  // 學習趨勢標籤頁
  Widget _buildTrendsTab() {
    return RefreshIndicator(
      onRefresh: _fetchWeeklyStats,
      color: accentColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeeklyTrends(),
            const SizedBox(height: 24),
            _buildLearningStreak(),
            const SizedBox(height: 24),
            _buildSubjectProgress(),
          ],
        ),
      ),
    );
  }

  // 知識掌握標籤頁
  Widget _buildKnowledgeTab() {
    return RefreshIndicator(
      onRefresh: _fetchKnowledgeScores,
      color: accentColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKnowledgeRadarChart(),
            const SizedBox(height: 24),
            _buildKnowledgeList(),
          ],
        ),
      ),
    );
  }

  // 學習建議標籤頁
  Widget _buildSuggestionsTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchUserStats();
        await _fetchKnowledgeScores();
        await _fetchWeeklyStats();
        await _fetchLearningSuggestions();
      },
      color: accentColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeakPointsCard(),
            const SizedBox(height: 24),
            _buildLearningTips(),
            const SizedBox(height: 24),
            _buildNextSteps(),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayStats() {
    final todaySubjectLevels = _stats['today_subject_levels'] as List<dynamic>? ?? [];
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.today,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '今日學習',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatCard(
                  icon: Icons.star,
                  color: accentColor,
                  value: _stats['today_levels'].toString(),
                  label: '今日完成關卡',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (todaySubjectLevels.isNotEmpty)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: secondaryColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日各科目完成情況',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: todaySubjectLevels.map<Widget>((subject) {
                        final subjectName = subject['subject'] as String;
                        final levelCount = subject['level_count'] as int;
                        
                        // 定義科目顏色映射
                        final subjectColors = {
                          '數學': Colors.blue,
                          '國文': Colors.green,
                          '英文': Colors.purple,
                          '理化': Colors.orange,
                          '生物': Colors.red,
                          '地科': Colors.brown,
                          '化學': Colors.blueGrey,
                          '物理': Colors.deepPurple,
                          '歷史': Colors.deepOrange,
                          '地理': Colors.teal,
                          '公民': Colors.pink,
                        };
                        
                        return Chip(
                          backgroundColor: subjectColors[subjectName]?.withOpacity(0.8) ?? Colors.grey,
                          avatar: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.book, size: 16, color: subjectColors[subjectName] ?? Colors.grey),
                          ),
                          label: Text(
                            '$subjectName: $levelCount 關',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 學習趨勢圖表
  Widget _buildWeeklyTrends() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.trending_up,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '每週學習趨勢',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 300,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _weeklyStats.isEmpty
                  ? Center(child: Text('暫無數據', style: TextStyle(color: Colors.white70)))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _getMaxLevelCount() + 2,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipPadding: EdgeInsets.all(8),
                            tooltipMargin: 8,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              String weekDay = '';
                              String weekType = groupIndex == 0 ? '本週' : '上週';
                              if (groupIndex < _weeklyStats.length && rodIndex < (_weeklyStats[weekType]?.length ?? 0)) {
                                weekDay = _weeklyStats[weekType]?[rodIndex]['day'] ?? '';
                              }
                              return BarTooltipItem(
                                '$weekDay: ${rod.toY.toInt()} 關',
                                TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                String text = '';
                                switch (value.toInt()) {
                                  case 0: text = '一'; break;
                                  case 1: text = '二'; break;
                                  case 2: text = '三'; break;
                                  case 3: text = '四'; break;
                                  case 4: text = '五'; break;
                                  case 5: text = '六'; break;
                                  case 6: text = '日'; break;
                                }
                                return Text(text, style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ));
                              },
                              reservedSize: 30,
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                if (value == 0) return const Text('0', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10));
                                if (value % 2 == 0) return Text(value.toInt().toString(), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10));
                                return const Text('');
                              },
                              reservedSize: 30,
                            ),
                          ),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          checkToShowHorizontalLine: (value) => value % 2 == 0,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.white10,
                            strokeWidth: 1,
                          ),
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: _getBarGroups(),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('本週', Colors.blue),
                SizedBox(width: 24),
                _buildLegendItem('上週', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 獲取最大關卡數量，用於設置圖表Y軸
  double _getMaxLevelCount() {
    double maxCount = 0;
    _weeklyStats.forEach((week, stats) {
      for (var dayStat in stats) {
        if ((dayStat['levels'] as int).toDouble() > maxCount) {
          maxCount = (dayStat['levels'] as int).toDouble();
        }
      }
    });
    return maxCount;
  }

  // 獲取柱狀圖數據
  List<BarChartGroupData> _getBarGroups() {
    List<BarChartGroupData> barGroups = [];
    
    for (int i = 0; i < 7; i++) {
      List<BarChartRodData> bars = [];
      
      // 本週數據
      if (_weeklyStats.containsKey('本週') && i < (_weeklyStats['本週']?.length ?? 0)) {
        bars.add(
          BarChartRodData(
            toY: (_weeklyStats['本週']?[i]['levels'] as int? ?? 0).toDouble(),
            color: Colors.blue,
            width: 12,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        );
      }
      
      // 上週數據
      if (_weeklyStats.containsKey('上週') && i < (_weeklyStats['上週']?.length ?? 0)) {
        bars.add(
          BarChartRodData(
            toY: (_weeklyStats['上週']?[i]['levels'] as int? ?? 0).toDouble(),
            color: Colors.green,
            width: 12,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        );
      }
      
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: bars,
          showingTooltipIndicators: [0, 1],
        ),
      );
    }
    
    return barGroups;
  }

  // 新增方法：學習連續性
  Widget _buildLearningStreak() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '學習連續性',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    color: Colors.orange,
                    size: 40,
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '連續學習天數',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '$_streak 天',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: List.generate(7, (index) {
                  final bool isActive = index < _streak;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isActive ? accentColor : Colors.white24,
                              shape: BoxShape.circle,
                            ),
                            child: isActive 
                              ? Icon(Icons.check, color: Colors.white, size: 16)
                              : null,
                          ),
                          SizedBox(height: 4),
                          Text(
                            ['一', '二', '三', '四', '五', '六', '日'][index],
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增方法：科目進度
  Widget _buildSubjectProgress() {
    final subjectLevels = _stats['subject_levels'] as List<dynamic>? ?? [];
    
    // 定義科目顏色映射
    final subjectColors = {
      '數學': Colors.blue,
      '國文': Colors.green,
      '英文': Colors.purple,
      '理化': Colors.orange,
      '生物': Colors.red,
      '地科': Colors.brown,
      '化學': Colors.blueGrey,
      '物理': Colors.deepPurple,
      '歷史': Colors.deepOrange,
      '地理': Colors.teal,
      '公民': Colors.pink,
    };
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.subject,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '科目進度',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (subjectLevels.isEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: secondaryColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '尚未完成任何關卡',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            else
              Column(
                children: subjectLevels.map<Widget>((subject) {
                  final subjectName = subject['subject'] as String;
                  final levelCount = subject['level_count'] as int;
                  final color = subjectColors[subjectName] ?? Colors.grey;
                  
                  // 假設每個科目總共有30關
                  final totalLevels = 30;
                  final progress = levelCount / totalLevels;
                  
                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: secondaryColor.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: color,
                              radius: 12,
                              child: Icon(Icons.book, size: 14, color: Colors.white),
                            ),
                            SizedBox(width: 8),
                            Text(
                              subjectName,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Spacer(),
                            Text(
                              '$levelCount/$totalLevels 關',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white24,
                            color: color,
                            minHeight: 8,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '完成度: ${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // 新增方法：知識點雷達圖
  Widget _buildKnowledgeRadarChart() {
    // 選擇一些主要知識點類別進行展示
    final knowledgeCategories = [
      '數學運算', '代數', '幾何', '統計', '物理概念', '化學反應'
    ];
    
    // 模擬各類別的掌握程度（0-10分）
    final scores = [7.5, 6.0, 8.0, 5.5, 9.0, 4.0];
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.radar,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '知識掌握雷達圖',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 300,
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '知識雷達圖將在這裡顯示\n(需要使用RadarChart或自定義繪製)',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '知識類別掌握程度',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(knowledgeCategories.length, (index) {
                    final category = knowledgeCategories[index];
                    final score = scores[index];
                    final progress = score / 10;
                    
                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                category,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              Spacer(),
                              Text(
                                '${score.toStringAsFixed(1)}/10',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white24,
                              color: _getScoreColor(score),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增方法：知識點列表
  Widget _buildKnowledgeList() {
    if (_knowledgeScores.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              '尚未有知識點評分數據',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    
    // 按分數排序
    final sortedScores = List<Map<String, dynamic>>.from(_knowledgeScores)
      ..sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.list_alt,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '知識點掌握列表',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          '知識點',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '小節',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          '分數',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  Divider(color: Colors.white30),
                  ...sortedScores.take(10).map((score) {
                    final pointName = score['point_name'] as String;
                    final sectionName = score['section_name'] as String;
                    final scoreValue = score['score'] as num;
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              pointName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              sectionName,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getScoreColor(scoreValue.toDouble()),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                scoreValue.toStringAsFixed(1),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  if (sortedScores.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '... 還有 ${sortedScores.length - 10} 個知識點',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增方法：弱點知識點卡片
  Widget _buildWeakPointsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '需要加強的知識點',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_weakPoints.isEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: secondaryColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '太棒了！目前沒有需要特別加強的知識點',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: secondaryColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: _weakPoints.take(5).map((point) {
                    final pointName = point['point_name'] as String;
                    final sectionName = point['section_name'] as String;
                    final score = point['score'] as num;
                    
                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  pointName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getScoreColor(score.toDouble()),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${score.toStringAsFixed(1)}/10',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            '小節: $sectionName',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: score / 10,
                              backgroundColor: Colors.white24,
                              color: _getScoreColor(score.toDouble()),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 新增方法：學習建議
  Widget _buildLearningTips() {
    final tips = [
      '根據您的學習數據，建議您多花時間在數學代數部分',
      '您在物理力學概念上表現優秀，可以嘗試更高難度的題目',
      '建議每天至少完成3個關卡，保持學習連續性',
      '週末可以安排複習之前學過的知識點',
      '嘗試使用不同的學習方法，如製作筆記、思維導圖等',
    ];
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lightbulb,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '學習建議',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: tips.map((tip) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: accentColor,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 新增方法：下一步學習計劃
  Widget _buildNextSteps() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.next_plan,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '下一步學習計劃',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: secondaryColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildNextStepItem(
                    icon: Icons.priority_high,
                    title: '優先學習',
                    content: '代數方程式、化學反應式平衡',
                    color: Colors.red,
                  ),
                  Divider(color: Colors.white24, height: 24),
                  _buildNextStepItem(
                    icon: Icons.refresh,
                    title: '需要複習',
                    content: '三角函數、物理力學',
                    color: Colors.orange,
                  ),
                  Divider(color: Colors.white24, height: 24),
                  _buildNextStepItem(
                    icon: Icons.trending_up,
                    title: '可以提升',
                    content: '統計概率、英語閱讀理解',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '生成個人化學習計劃',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 輔助方法：下一步學習項目
  Widget _buildNextStepItem({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 4),
              Text(
                content,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 輔助方法：根據分數獲取顏色
  Color _getScoreColor(double score) {
    if (score < 3) return Colors.red;
    if (score < 5) return Colors.orange;
    if (score < 7) return Colors.yellow;
    if (score < 9) return Colors.lightGreen;
    return Colors.green;
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: secondaryColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectStats() {
    final subjectLevels = _stats['subject_levels'] as List<dynamic>? ?? [];
    
    // 定義科目顏色映射
    final subjectColors = {
      '數學': Colors.blue,
      '國文': Colors.green,
      '英文': Colors.purple,
      '理化': Colors.orange,
      '生物': Colors.red,
      '地科': Colors.brown,
      '化學': Colors.blueGrey,
      '物理': Colors.deepPurple,
      '歷史': Colors.deepOrange,
      '地理': Colors.teal,
      '公民': Colors.pink,
    };

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.pie_chart,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '各科目學習統計',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (subjectLevels.isEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: secondaryColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '尚未完成任何關卡',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            else
              Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: subjectLevels.map((subject) {
                          final subjectName = subject['subject'] as String;
                          final levelCount = subject['level_count'] as int;
                          return PieChartSectionData(
                            color: subjectColors[subjectName] ?? Colors.grey,
                            value: levelCount.toDouble(),
                            title: subjectName, // 只顯示科目名稱，不顯示數字
                            radius: 80,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: secondaryColor.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: subjectLevels.map<Widget>((subject) {
                        final subjectName = subject['subject'] as String;
                        final levelCount = subject['level_count'] as int;
                        return Chip(
                          backgroundColor: subjectColors[subjectName]?.withOpacity(0.8) ?? Colors.grey,
                          avatar: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.book, size: 16, color: subjectColors[subjectName] ?? Colors.grey),
                          ),
                          label: Text(
                            '$subjectName: $levelCount 關',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalStats() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bar_chart,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '總體學習統計',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                  icon: Icons.emoji_events,
                  color: accentColor,
                  value: _stats['total_levels'].toString(),
                  label: '總完成關卡',
                ),
                _buildStatCard(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  value: '${_stats['accuracy']}%',
                  label: '總答對率',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentLevels() {
    final recentLevels = _stats['recent_levels'] as List<dynamic>? ?? [];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '最近完成的關卡',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (recentLevels.isEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: secondaryColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '尚未完成任何關卡',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentLevels.length,
                separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white24),
                itemBuilder: (context, index) {
                  final level = recentLevels[index];
                  final DateTime answeredAt = DateTime.parse(level['answered_at']);
                  final formattedDate = DateFormat('yyyy/MM/dd HH:mm').format(answeredAt);
                  
                  final subject = level['subject'] is String ? level['subject'] : '未知科目';
                  final chapterName = level['chapter_name'] is String ? level['chapter_name'] : '未知章節';
                  final subjectInitial = subject.isNotEmpty ? subject[0] : '?';
                  
                  // 定義科目顏色映射
                  final subjectColors = {
                    '數學': Colors.blue,
                    '國文': Colors.green,
                    '英文': Colors.purple,
                    '理化': Colors.orange,
                    '生物': Colors.red,
                    '地科': Colors.brown,
                    '化學': Colors.blueGrey,
                    '物理': Colors.deepPurple,
                    '歷史': Colors.deepOrange,
                    '地理': Colors.teal,
                    '公民': Colors.pink,
                  };
                  
                  final backgroundColor = subjectColors[subject] ?? Colors.blue[700];
                  
                  return Container(
                    margin: EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: secondaryColor.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: backgroundColor,
                        child: Text(subjectInitial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(
                        '$chapterName',
                        style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(formattedDate, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          3,
                          (i) => Icon(
                            Icons.star,
                            color: i < (level['stars'] ?? 0) ? accentColor : Colors.white30,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}