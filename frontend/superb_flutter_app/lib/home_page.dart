import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';  // 引入原來的 AI 問問題頁面
import 'auth_page.dart';  // Import the AuthPage
import 'mistake_book.dart';  // Import the MistakeBookPage
import 'dart:math';
// import 'chapter_detail_page.dart';  // 默認深藍色
import 'chapter_detail_page_n.dart';  // 藍橘配色
import 'chat_page_s.dart';
import 'user_profile_page.dart';  // 引入新的用戶中心頁面
import 'package:flutter_svg/flutter_svg.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _selectedIndex = 1;
  ScrollController _scrollController = ScrollController();
  final double _maxPlanetSize = 200.0;  // 增加最大尺寸
  final double _minPlanetSize = 100.0;  // 增加最小尺寸
  double _screenHeight = 600.0;  // 初始值
  String? _userPhotoUrl;  // 添加用戶頭像 URL 狀態變量
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserPhoto();  // 在初始化時加載用戶頭像
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUserPhoto(); // 當應用程序從後台恢復時重新加載頭像
    }
  }

  // 加載用戶頭像
  Future<void> _loadUserPhoto() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userPhotoUrl = prefs.getString('photo_url');
      print("頭像 URL: $_userPhotoUrl");
    });
  }

  // 計算星球大小的方法
  double calculatePlanetSize(double scrollPosition, double itemPosition) {
    // 調整中心點位置（向上偏移 20%）
    double adjustedScrollPosition = scrollPosition - (_screenHeight * 0.13);
    
    // 計算與中心線的距離（0-1範圍）
    double distanceFromCenter = (adjustedScrollPosition - itemPosition).abs() / (_screenHeight / 2);
    // 限制距離範圍在 0-1 之間
    distanceFromCenter = distanceFromCenter.clamp(0.0, 1.0);
    // 使用餘弦函數創建平滑的大小變化
    double sizeFactor = (cos(distanceFromCenter * pi) + 1) / 2;
    // 在最小和最大大小之間插值
    return _minPlanetSize + (_maxPlanetSize - _minPlanetSize) * sizeFactor;
  }

  // 計算文字大小的方法
  double calculateTextSize(double size) {
    // 根據圖片大小計算對應的文字大小
    double maxTextSize = 28.0;
    double minTextSize = 18.0;
    double ratio = (size - _minPlanetSize) / (_maxPlanetSize - _minPlanetSize);
    return minTextSize + (maxTextSize - minTextSize) * ratio;
  }

void _onItemTapped(int index) {
  if (index == 0) {  // If "錯題本" (Wrongbook) is tapped
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MistakeBookPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(-1.0, 0.0); // Start from the left
          const end = Offset.zero; // End at the normal position
          const curve = Curves.easeInOut;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  } else if (index == 2) {  // If "汪汪題" (Chat) is tapped
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatPage()),
    );
  } else {
    setState(() {
      _selectedIndex = index;  // Only update state for "學習" (Learning)
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 主要內容區域
          IndexedStack(
            index: _selectedIndex,
            children: [
              MistakeBookPage(),
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/home-background.png'),
                    fit: BoxFit.fill,
                  ),
                  color: Color(0xFF1B3B4B),
                ),
                child: Column(
                  children: [
                    SizedBox(height: 50),
                    // Dogtor 標題和用戶頭像在同一列
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SvgPicture.asset(
                            'assets/images/dogtor_eng_logo.svg',
                            width: 120,
                            height: 24,
                            color: Color.fromRGBO(
                              (0.06 * 255).round(),
                              (0.13 * 255).round(),
                              (0.19 * 255).round(),
                              1,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => UserProfilePage(),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    const begin = Offset(1.0, 0.0);
                                    const end = Offset.zero;
                                    const curve = Curves.easeInOut;
                                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                    var offsetAnimation = animation.drive(tween);
                                    return SlideTransition(
                                      position: offsetAnimation,
                                      child: child,
                                    );
                                  },
                                ),
                              ).then((_) {
                                _loadUserPhoto();
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                                image: _userPhotoUrl != null && _userPhotoUrl!.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(_userPhotoUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _userPhotoUrl == null || _userPhotoUrl!.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      color: Colors.blue.shade700,
                                      size: 24,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    // 學科列表
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _screenHeight = constraints.maxHeight;
                          return ListView.builder(
                            controller: _scrollController,
                            itemCount: planets.length,
                            itemBuilder: (context, index) {
                              return AnimatedBuilder(
                                animation: _scrollController,
                                builder: (context, child) {
                                  double itemPosition = index * 180.0;
                                  double scrollPosition = _scrollController.hasClients 
                                      ? _scrollController.offset 
                                      : 0.0;
                                  double viewportCenter = constraints.maxHeight * 0.4;
                                  double size = calculatePlanetSize(
                                    scrollPosition + viewportCenter,
                                    itemPosition
                                  );
                                  
                                  bool isLeft = index.isEven;
                                  
                                  return Container(
                                    height: 180,
                                    padding: EdgeInsets.symmetric(horizontal: 40),
                                    child: Row(
                                      mainAxisAlignment: isLeft 
                                          ? MainAxisAlignment.start 
                                          : MainAxisAlignment.end,
                                      children: [
                                        if (!isLeft) Expanded(
                                          child: Padding(
                                            padding: EdgeInsets.only(right: 40),
                                            child: AnimatedDefaultTextStyle(
                                              duration: Duration(milliseconds: 100),
                                              style: Theme.of(context).textTheme.displayMedium!.copyWith(
                                                fontSize: calculateTextSize(size),
                                                color: Colors.white,
                                              ),
                                              child: Text(
                                                planets[index]['name'],
                                                textAlign: TextAlign.end,
                                              ),
                                            ),
                                          ),
                                        ),
                                        AnimatedContainer(
                                          duration: Duration(milliseconds: 100),
                                          width: size,
                                          height: size,
                                          child: GestureDetector(
                                            onTap: () {
                                              print('點擊了 ${planets[index]['name']}');
                                              if (planets[index]['name'] == '理化') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => ChapterDetailPage(
                                                      subject: '理化',
                                                      csvPath: 'assets/edu_data/level_info/junior_science_level.csv',
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            child: Image.asset(
                                              planets[index]['image'],
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        if (isLeft) Expanded(
                                          child: Padding(
                                            padding: EdgeInsets.only(left: 40),
                                            child: AnimatedDefaultTextStyle(
                                              duration: Duration(milliseconds: 100),
                                              style: Theme.of(context).textTheme.displayMedium!.copyWith(
                                                fontSize: calculateTextSize(size),
                                                color: Colors.white,
                                              ),
                                              child: Text(
                                                planets[index]['name'],
                                                textAlign: TextAlign.start,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              ChatPage(),
            ],
          ),
        ],
      ),
      // 底部導航欄
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Image(
                image: AssetImage('assets/images/toolbar-mistake.png'),
              ),
              label: '錯題本',
            ),
            BottomNavigationBarItem(
              icon: Image(
                image: AssetImage('assets/images/toolbar-learn.png'),
              ),
              label: '學習',
            ),
            BottomNavigationBarItem(
              icon: Image(
                image: AssetImage('assets/images/toolbar-ask.png'),
              ),
              label: '汪汪題',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white.withOpacity(0.5),
          backgroundColor: Color(0xFF102031),
          type: BottomNavigationBarType.fixed,
          onTap: _onItemTapped,
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> planets = [
    {
      'name': '自然',
      'image': 'assets/pics/home-island1.png',
    },
    {
      'name': '理化',
      'image': 'assets/pics/home-island2.png',
    },
    {
      'name': '物理',
      'image': 'assets/pics/home-island3.png',
    },
    {
      'name': '化學',
      'image': 'assets/pics/home-island4.png',
    },
    {
      'name': '數學',
      'image': 'assets/pics/home-island5.png',
    },
    {
      'name': '國文',
      'image': 'assets/pics/home-island1.png',
    },
    {
      'name': '英文',
      'image': 'assets/pics/home-island2.png',  // 重複使用圖片
    },
    {
      'name': '社會',
      'image': 'assets/pics/home-island3.png',
    },
    {
      'name': '地科',
      'image': 'assets/pics/home-island4.png',
    },
    {
      'name': '生物',
      'image': 'assets/pics/home-island5.png',
    },
    {
      'name': '歷史',
      'image': 'assets/pics/home-island1.png',
    },
    {
      'name': '地理',
      'image': 'assets/pics/home-island2.png',
    },
  ];
}