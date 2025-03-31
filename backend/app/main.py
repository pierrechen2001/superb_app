from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from openai import OpenAI
from fastapi.middleware.cors import CORSMiddleware
import base64
import csv
import os
from dotenv import load_dotenv
from datetime import datetime
import pymysql
import pymysql.cursors
from typing import Optional
from pydantic import BaseModel
import io
from email.mime.text import MIMEText
from datetime import datetime

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 允許所有來源（建議在開發環境使用，生產環境應指定來源）
    allow_credentials=True,
    allow_methods=["*"],  # 允許所有方法（GET, POST, PUT, DELETE）
    allow_headers=["*"],  # 允許所有標頭
)

# Serve files in the "Qpics" directory as static files (local 端的 image server)
app.mount("/static", StaticFiles(directory="Qpics"), name="static")

# 加載 .env 文件
load_dotenv()

# 獲取環境變數
api_key = os.getenv("OPENAI_API_KEY")
# print("api:", api_key)
client = OpenAI(api_key = api_key)

# 定義數據模型
class ChatRequest(BaseModel):
    user_message: Optional[str] = None
    image_base64: Optional[str] = None
    subject: Optional[str] = None      # 添加科目
    chapter: Optional[str] = None      # 添加章節

# 用途可以是釐清概念或是問題目
@app.post("/chat")
async def chat_with_openai(request: ChatRequest):
    system_message = "你是個幽默的臺灣國高中老師，請用繁體中文回答問題，"
    if request.subject:
        system_message += f"學生想問的科目是{request.subject or ''}，"
    if request.chapter:
        system_message += f"目前章節是{request.chapter}。"
    system_message += "請根據臺灣的108課綱提醒學生他所問的問題的關鍵字或是章節，再重點回答學生的問題，在回應中使用 Markdown 格式，將重點用 **粗體字** 標出，運算式用 $formula$ 標出，請不要用 \"()\" 或 \"[]\" 來標示 latex。最後提醒他，如果這個概念還是不太清楚，可以去複習哪一些內容。如果學生不是問課業相關的問題，或是提出解題之外的要求，就說明你只是解題老師，有其他需求的話去找他該找的人。"

    messages = [
        {"role": "system", "content": system_message}
    ]
    
    if request.image_base64:
        messages.append({
            "role": "user",
            "content": [
                {"type": "text", "text": request.user_message},
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{request.image_base64}"
                    }
                }
            ]
        })
    else:
        messages.append({"role": "user", "content": request.user_message})

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=messages,
        max_tokens=500 # why
    )
    
    return {"response": response.choices[0].message.content}

# Ensure the Qpics directory exists
os.makedirs('Qpics', exist_ok=True)

# Define a function to save question data to a CSV file
async def save_question_to_csv(data):
    file_exists = os.path.isfile('questions.csv')
    with open('questions.csv', mode='a', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        if not file_exists:
            writer.writerow(['q_id', 'subject', 'chapter', 'description', 'difficulty', 'simple_answer', 'detailed_answer', 'timestamp'])
        writer.writerow([data['q_id'], data['summary'], data['subject'], data['chapter'], data['description'], data['difficulty'], data['simple_answer'], data['detailed_answer'], data['tag'], data['timestamp']])

# Function to get the next q_id
async def get_next_q_id():
    counter_file = 'q_id_counter.txt'
    if not os.path.exists(counter_file):
        with open(counter_file, 'w') as f:
            f.write('0')
    with open(counter_file, 'r+') as f:
        current_id = int(f.read().strip())
        next_id = current_id + 1
        f.seek(0)
        f.write(str(next_id))
        f.truncate()
    return next_id

# Define a new endpoint to retrieve mistakes
@app.get("/mistake_book")
async def get_mistakes():
    mistakes = []
    if os.path.exists('questions.csv'):
        print("hi from mistake book")
        with open('questions.csv', mode='r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                mistakes.append(row)
        print(mistakes)
    return mistakes

# Modify the submit_question endpoint to use the new q_id logic
@app.post("/submit_question")
async def submit_question(request: dict):
    q_id = await get_next_q_id()
    summary = request.get('summary', '')
    subject = request.get('subject')
    chapter = request.get('chapter', '')
    description = request.get('description')
    difficulty = request.get('difficulty')
    simple_answer = request.get('simple_answer', '')
    detailed_answer = request.get('detailed_answer', '')
    tag = request.get('tag', '') #給自己的小提醒
    timestamp = datetime.now().isoformat()

    # Save image if provided
    image_base64 = request.get('image_base64')
    if image_base64:
        image_data = base64.b64decode(image_base64)
        with open(f'Qpics/{q_id}.jpg', 'wb') as image_file:
            image_file.write(image_data)

    # Save question data to CSV
    await save_question_to_csv({
        'q_id': q_id,
        'summary': summary,
        'subject': subject,
        'chapter': chapter,
        'description': description,
        'difficulty': difficulty,
        'simple_answer': simple_answer,
        'detailed_answer': detailed_answer,
        'tag': tag,
        'timestamp': timestamp
    })

    return {"status": "success", "message": "Question submitted successfully."}

# 串 GPT 統整問題摘要
# 回傳摘要、科目
@app.post("/summarize")
async def chat_with_openai(request: ChatRequest):
    #system_message = "請你分辨輸入圖片的科目類型（國文、數學、英文、社會、自然），並且用十個字以內的話總結這個題目的重點。回傳csv格式為：科目,十字總結"
    system_message = "請你用十個字以內的話總結這個題目的重點，回傳十字總結"

    messages = [
        {"role": "system", "content": system_message}
    ]

    if request.image_base64:
        messages.append({
            "role": "user",
            "content": [
                {"type": "text", "text": request.user_message},
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{request.image_base64}"
                    }
                }
            ]
        })
    else:
        messages.append({"role": "user", "content": request.user_message})

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=messages,
        max_tokens=1000 # why
    )
    
    return {"response": response.choices[0].message.content}

############### SQL

# 連接到 Google Cloud SQL
def get_db_connection():
    try:
        connection = pymysql.connect(
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            database=os.getenv('DB_NAME'),
            unix_socket=f"/cloudsql/{os.getenv('INSTANCE_CONNECTION_NAME')}",
            cursorclass=pymysql.cursors.DictCursor
        )
        return connection
    except Exception as e:
        print(f"Database connection error: {str(e)}")
        raise

# 用戶模型.
class User(BaseModel):
    user_id: str
    email: Optional[str] = None
    name: Optional[str] = None
    photo_url: Optional[str] = None
    created_at: Optional[str] = None

# 檢查用戶是否存在
@app.get("/users/check")
async def check_user(user_id: str):
    connection = None
    try:
        print(f"檢查用戶 {user_id} 是否存在...")
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 檢查用戶是否存在
            sql = "SELECT * FROM users WHERE user_id = %s"
            cursor.execute(sql, (user_id,))
            result = cursor.fetchone()
            
            if result:
                print(f"用戶 {user_id} 存在，開始初始化知識點分數...")
                # 用戶存在，檢查並初始化知識點分數
                await initialize_user_knowledge_scores(user_id, connection)
                return {"exists": True, "user": result}
            else:
                print(f"用戶 {user_id} 不存在")
                return {"exists": False}
    except Exception as e:
        print(f"檢查用戶時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if connection:
            connection.close()

# 創建新用戶
@app.post("/users")
async def create_user(user: User):
    connection = None
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 檢查用戶是否已存在
            sql = "SELECT * FROM users WHERE user_id = %s"
            cursor.execute(sql, (user.user_id,))
            existing_user = cursor.fetchone()
            
            if existing_user:
                # 用戶已存在，檢查並初始化知識點分數
                await initialize_user_knowledge_scores(user.user_id, connection)
                return {"message": "User already exists", "user": existing_user}
            
            # 創建新用戶
            sql = """
            INSERT INTO users (user_id, email, name, photo_url, created_at)
            VALUES (%s, %s, %s, %s, %s)
            """
            cursor.execute(sql, (
                user.user_id,
                user.email,
                user.name,
                user.photo_url,
                user.created_at or datetime.now().isoformat()
            ))
            connection.commit()
            
            # 獲取創建的用戶
            sql = "SELECT * FROM users WHERE user_id = %s"
            cursor.execute(sql, (user.user_id,))
            new_user = cursor.fetchone()
            
            # 初始化知識點分數
            await initialize_user_knowledge_scores(user.user_id, connection)
            
            return {"message": "User created successfully", "user": new_user}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if connection:
            connection.close()

# 初始化用戶知識點分數
async def initialize_user_knowledge_scores(user_id: str, connection):
    try:
        print(f"===== 開始初始化用戶 {user_id} 的知識點分數 =====")
        
        with connection.cursor() as cursor:
            # 檢查用戶是否存在
            cursor.execute("SELECT * FROM users WHERE user_id = %s", (user_id,))
            user_result = cursor.fetchone()
            if not user_result:
                print(f"錯誤: 找不到用戶 ID: {user_id}")
                return
            # print(f"找到用戶: {user_result['name']} (ID: {user_result['user_id']})")
            
            # 檢查 user_knowledge_score 表結構
            try:
                cursor.execute("DESCRIBE user_knowledge_score")
                table_structure = cursor.fetchall()
            except Exception as e:
                print(f"無法獲取表結構: {str(e)}")
            
            # 獲取所有知識點
            cursor.execute("SELECT COUNT(*) as count FROM knowledge_points")
            count_result = cursor.fetchone()
            total_knowledge_points = count_result['count']
            print(f"數據庫中共有 {total_knowledge_points} 個知識點")
            
            if total_knowledge_points == 0:
                print("警告: 知識點表為空，無法初始化用戶知識點分數")
                return
            
            sql = "SELECT id, section_name, point_name FROM knowledge_points LIMIT 5"
            cursor.execute(sql)
            sample_points = cursor.fetchall()
            # print(f"知識點示例:")
            # for point in sample_points:
            #     print(f"  - ID: {point['id']}, 小節: {point['section_name']}, 知識點: {point['point_name']}")
            
            sql = "SELECT id FROM knowledge_points"
            cursor.execute(sql)
            all_knowledge_points = cursor.fetchall()
            # print(f"獲取到 {len(all_knowledge_points)} 個知識點")
            
            # 獲取用戶已有的知識點分數
            sql = "SELECT COUNT(*) as count FROM user_knowledge_score WHERE user_id = %s"
            cursor.execute(sql, (user_id,))
            count_result = cursor.fetchone()
            existing_count = count_result['count']
            # print(f"用戶已有 {existing_count} 個知識點分數記錄")
            
            if existing_count > 0:
                # 顯示一些現有記錄作為示例
                sql = "SELECT * FROM user_knowledge_score WHERE user_id = %s LIMIT 3"
                cursor.execute(sql, (user_id,))
                sample_scores = cursor.fetchall()
                # print(f"用戶現有知識點分數示例:")
                # for score in sample_scores:
                #     print(f"  - ID: {score['id']}, 知識點ID: {score['knowledge_id']}, 分數: {score['score']}")
            
            sql = "SELECT knowledge_id FROM user_knowledge_score WHERE user_id = %s"
            cursor.execute(sql, (user_id,))
            existing_scores = cursor.fetchall()
            existing_knowledge_ids = [score['knowledge_id'] for score in existing_scores]
            
            # 為缺少的知識點創建分數記錄
            inserted_count = 0
            error_count = 0
            for point in all_knowledge_points:
                knowledge_id = point['id']
                if knowledge_id not in existing_knowledge_ids:
                    try:
                        sql = """
                        INSERT INTO user_knowledge_score (user_id, knowledge_id, score)
                        VALUES (%s, %s, 0)
                        ON DUPLICATE KEY UPDATE score = VALUES(score)
                        """
                        cursor.execute(sql, (user_id, knowledge_id))
                        inserted_count += 1
                        
                        # 每插入10條記錄輸出一次進度
                        if inserted_count % 10 == 0:
                            print(f"已插入 {inserted_count} 條記錄...")
                    except Exception as insert_error:
                        error_count += 1
                        if error_count <= 5:  # 只顯示前5個錯誤
                            print(f"插入知識點 {knowledge_id} 時出錯: {str(insert_error)}")
                        elif error_count == 6:
                            print("更多錯誤被省略...")
            
            print(f"為用戶 {user_id} 新增了 {inserted_count} 個知識點分數記錄，失敗 {error_count} 個")
            
            if error_count > 0:
                # 嘗試插入一條測試記錄，以診斷問題
                try:
                    print("嘗試插入測試記錄...")
                    # 獲取一個不在現有記錄中的知識點ID
                    test_knowledge_id = None
                    for point in all_knowledge_points:
                        if point['id'] not in existing_knowledge_ids:
                            test_knowledge_id = point['id']
                            break
                    
                    if test_knowledge_id:
                        # print(f"測試知識點ID: {test_knowledge_id}")
                        sql = """
                        INSERT INTO user_knowledge_score (user_id, knowledge_id, score)
                        VALUES (%s, %s, 0)
                        ON DUPLICATE KEY UPDATE score = VALUES(score)
                        """
                        cursor.execute(sql, (user_id, test_knowledge_id))
                        print("測試記錄插入成功!")
                except Exception as test_error:
                    print(f"測試記錄插入失敗: {str(test_error)}")
                    print(f"SQL: INSERT INTO user_knowledge_score (user_id, knowledge_id, score) VALUES ('{user_id}', {test_knowledge_id}, 0)")
            
            # 再次檢查用戶知識點分數記錄數量
            sql = "SELECT COUNT(*) as count FROM user_knowledge_score WHERE user_id = %s"
            cursor.execute(sql, (user_id,))
            count_result = cursor.fetchone()
            final_count = count_result['count']
            print(f"初始化後，用戶共有 {final_count} 個知識點分數記錄")
            
            connection.commit()
            print(f"===== 已成功初始化用戶 {user_id} 的知識點分數 =====")
    except Exception as e:
        print(f"初始化知識點分數時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        # 不拋出異常，讓登錄過程繼續

# 更新用戶信息
@app.put("/users/{user_id}")
async def update_user(user_id: str, user: User):
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 檢查用戶是否存在
            sql = "SELECT * FROM users WHERE user_id = %s"
            cursor.execute(sql, (user_id,))
            existing_user = cursor.fetchone()
            
            if not existing_user:
                raise HTTPException(status_code=404, detail="User not found")
            
            # 更新用戶信息
            sql = """
            UPDATE users
            SET email = %s, name = %s, photo_url = %s
            WHERE user_id = %s
            """
            cursor.execute(sql, (
                user.email,
                user.display_name,
                user.photo_url,
                user_id
            ))
            connection.commit()
            
            # 獲取更新後的用戶
            sql = "SELECT * FROM users WHERE user_id = %s"
            cursor.execute(sql, (user_id,))
            updated_user = cursor.fetchone()
            
            return {"message": "User updated successfully", "user": updated_user}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        connection.close()

@app.post("/admin/import-knowledge-points")
async def import_knowledge_points(file: UploadFile = File(...)):
    """
    導入知識點 CSV 文件
    """
    print("開始導入知識點...")
    
    if not file.filename.endswith('.csv'):
        raise HTTPException(status_code=400, detail="只接受 CSV 文件")
    
    # 讀取上傳的文件內容
    contents = await file.read()
    csv_file = io.StringIO(contents.decode('utf-8'))
    csv_reader = csv.reader(csv_file)
    
    # 跳過標題行（如果有）
    next(csv_reader, None)
    
    connection = None
    imported_count = 0
    
    try:
        connection = get_db_connection()
        
        for row in csv_reader:
            print(f"處理行: {row}")
            if len(row) < 4:
                print(f"跳過無效行: {row}")
                continue
            
            chapter_name = row[4].strip()
            section_num = int(row[5].strip())
            section_name = row[6].strip()
            knowledge_points_str = row[7].strip()
            
            # 查找 chapter_id
            with connection.cursor() as cursor:
                sql = "SELECT id FROM chapter_list WHERE chapter_name = %s"
                cursor.execute(sql, (chapter_name,))
                result = cursor.fetchone()
                
                if not result:
                    print(f"找不到章節: {chapter_name}，跳過")
                    continue
                
                chapter_id = result['id']
                print(f"找到章節 ID: {chapter_id} 對應章節: {chapter_name}")
                
                # 分割知識點
                knowledge_points = [kp.strip() for kp in knowledge_points_str.split('、')]
                
                # 插入每個知識點
                for point_name in knowledge_points:
                    if not point_name:
                        continue
                    
                    try:
                        sql = """
                        INSERT INTO knowledge_points 
                        (section_num, section_name, point_name, chapter_id)
                        VALUES (%s, %s, %s, %s)
                        """
                        cursor.execute(sql, (section_num, section_name, point_name, chapter_id))
                        imported_count += 1
                        print(f"已插入知識點: {point_name}")
                    except pymysql.err.IntegrityError as e:
                        if "Duplicate entry" in str(e):
                            print(f"知識點已存在，跳過: {point_name}")
                        else:
                            print(f"插入知識點時出錯: {e}")
                            continue
            
            # 提交事務
            connection.commit()
            print(f"已完成行: {row}")
    
    except Exception as e:
        print(f"處理 CSV 文件時出錯: {e}")
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"導入失敗: {str(e)}")
    finally:
        if connection:
            connection.close()
            print("數據庫連接已關閉")
    
    return {"message": f"成功導入 {imported_count} 個知識點"}

@app.post("/get_questions_by_level")
async def get_questions_by_level(request: Request):
    try:
        data = await request.json()
        chapter = data.get("chapter", "")
        section = data.get("section", "")
        knowledge_points = data.get("knowledge_points", "")
        user_id = data.get("user_id", "")
        level_id = data.get("level_id", "")  # 獲取關卡ID
        
        print(f"接收到的請求參數: chapter={chapter}, section={section}, knowledge_points={knowledge_points}, user_id={user_id}, level_id={level_id}")
        
        # 檢查參數
        if not section and not knowledge_points:
            return {"success": False, "message": "必須提供 section 或 knowledge_points"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 將知識點字符串拆分為列表
                knowledge_point_list = []
                if knowledge_points:
                    # 嘗試使用頓號（、）分隔
                    if '、' in knowledge_points:
                        knowledge_point_list = [kp.strip() for kp in knowledge_points.split('、')]
                    # 嘗試使用逗號（,）分隔
                    elif ',' in knowledge_points:
                        knowledge_point_list = [kp.strip() for kp in knowledge_points.split(',')]
                    # 如果只有一個知識點
                    else:
                        knowledge_point_list = [knowledge_points.strip()]

                # 獲取知識點的ID
                knowledge_ids = []
                for kp in knowledge_point_list:
                    cursor.execute("SELECT id FROM knowledge_points WHERE point_name = %s", (kp,))
                    result = cursor.fetchone()
                    if result:
                        knowledge_ids.append(result['id'])
                    else:
                        # 嘗試模糊匹配
                        cursor.execute("SELECT id FROM knowledge_points WHERE point_name LIKE %s", (f"%{kp}%",))
                        results = cursor.fetchall()
                        for r in results:
                            if r['id'] not in knowledge_ids:
                                knowledge_ids.append(r['id'])

                # 如果仍然沒有找到知識點，嘗試使用 level_id 查找
                if not knowledge_ids and level_id:
                    cursor.execute("""
                    SELECT kp.id
                    FROM knowledge_points kp
                    JOIN level_knowledge_mapping lkm ON kp.id = lkm.knowledge_id
                    WHERE lkm.level_id = %s
                    """, (level_id,))
                    results = cursor.fetchall()
                    for r in results:
                        knowledge_ids.append(r['id'])

                print(f"知識點列表: {knowledge_point_list}")
                print(f"找到的知識點 ID: {knowledge_ids}")
                
                # 如果有用戶ID，獲取用戶對這些知識點的掌握程度
                knowledge_scores = {}
                total_score = 0
                if user_id:
                    for knowledge_id in knowledge_ids:
                        cursor.execute("""
                        SELECT score FROM user_knowledge_score 
                        WHERE user_id = %s AND knowledge_id = %s
                        """, (user_id, knowledge_id))
                        result = cursor.fetchone()
                        # 如果沒有分數記錄，默認為5分（中等掌握程度）
                        score = result['score'] if result else 5
                        knowledge_scores[knowledge_id] = score
                        total_score += score
                
                # 如果沒有找到任何知識點 ID，返回錯誤
                if not knowledge_ids:
                    return {"success": False, "message": "找不到匹配的知識點"}

                # 計算每個知識點應該分配的題目數量
                total_questions = 10  # 總共要獲取10題
                questions_per_knowledge = {}

                if user_id and knowledge_scores:
                    # 計算每個知識點的反向權重（分數越低，權重越高）
                    inverse_weights = {}
                    total_inverse_weight = 0
                    
                    for knowledge_id in knowledge_ids:
                        # 獲取知識點分數，如果沒有記錄則默認為5
                        score = knowledge_scores.get(knowledge_id, 5)
                        # 使用反向分數作為權重（10-score），確保最小為1
                        inverse_weight = max(10 - score, 1)
                        inverse_weights[knowledge_id] = inverse_weight
                        total_inverse_weight += inverse_weight
                    
                    # 根據反向權重分配題目數量
                    remaining_questions = total_questions
                    for knowledge_id, inverse_weight in inverse_weights.items():
                        # 計算應分配的題目數量（至少1題）
                        question_count = max(1, int(round((inverse_weight / total_inverse_weight) * total_questions)))
                        # 確保不超過剩餘題目數
                        question_count = min(question_count, remaining_questions)
                        questions_per_knowledge[knowledge_id] = question_count
                        remaining_questions -= question_count
                    
                    # 如果還有剩餘題目，分配給分數最低的知識點
                    if remaining_questions > 0:
                        lowest_score_id = min(knowledge_scores.items(), key=lambda x: x[1])[0]
                        questions_per_knowledge[lowest_score_id] += remaining_questions
                else:
                    # 如果沒有用戶ID或分數記錄，平均分配題目
                    base_count = total_questions // len(knowledge_ids) if knowledge_ids else 0
                    remainder = total_questions % len(knowledge_ids) if knowledge_ids else 0
                    
                    for i, knowledge_id in enumerate(knowledge_ids):
                        questions_per_knowledge[knowledge_id] = base_count + (1 if i < remainder else 0)
                
                # 打印分配結果
                print(f"知識點分數: {knowledge_scores}")
                print(f"題目分配: {questions_per_knowledge}")
                
                # 構建查詢條件
                conditions = []
                params = []
                
                if chapter:
                    conditions.append("cl.chapter_name = %s")
                    params.append(chapter)
                
                if section:
                    conditions.append("kp.section_name = %s")
                    params.append(section)
                
                # 獲取所有題目
                all_questions = []
                
                # 為每個知識點獲取指定數量的題目
                for knowledge_id, question_count in questions_per_knowledge.items():
                    if question_count <= 0:
                        continue
                        
                    # 構建查詢
                    knowledge_conditions = conditions.copy()
                    knowledge_params = params.copy()
                    
                    knowledge_conditions.append("q.knowledge_id = %s")
                    knowledge_params.append(knowledge_id)
                    
                    # 組合 WHERE 子句
                    where_clause = " AND ".join(knowledge_conditions) if knowledge_conditions else "1=1"
                    
                    # 查詢題目，排除有錯誤訊息的題目
                    sql = f"""
                    SELECT q.id, q.knowledge_id, q.question_text, q.option_1, q.option_2, q.option_3, q.option_4, q.correct_answer, q.explanation, kp.point_name as knowledge_point
                    FROM questions q
                    JOIN knowledge_points kp ON q.knowledge_id = kp.id
                    JOIN chapter_list cl ON kp.chapter_id = cl.id
                    WHERE {where_clause} AND (q.Error_message IS NULL OR q.Error_message = '')
                    ORDER BY RAND()
                    LIMIT {question_count}
                    """
                    
                    print(f"執行的 SQL: {sql}")
                    print(f"SQL 參數: {knowledge_params}")
                    
                    cursor.execute(sql, knowledge_params)
                    knowledge_questions = cursor.fetchall()
                    all_questions.extend(knowledge_questions)
                
                # 如果獲取的題目不足10題，從所有相關知識點中隨機補充
                if len(all_questions) < total_questions:
                    remaining_count = total_questions - len(all_questions)
                    
                    # 已獲取的題目ID列表
                    existing_ids = [q['id'] for q in all_questions]
                    id_placeholders = ', '.join(['%s'] * len(existing_ids)) if existing_ids else '0'
                    
                    # 構建知識點條件
                    kp_placeholders = ', '.join(['%s'] * len(knowledge_ids)) if knowledge_ids else '0'
                    
                    # 查詢補充題目
                    supplement_sql = f"""
                    SELECT q.id, q.knowledge_id, q.question_text, q.option_1, q.option_2, q.option_3, q.option_4, q.correct_answer, q.explanation, kp.point_name as knowledge_point
                    FROM questions q
                    JOIN knowledge_points kp ON q.knowledge_id = kp.id
                    JOIN chapter_list cl ON kp.chapter_id = cl.id
                    WHERE q.knowledge_id IN ({kp_placeholders})
                    AND q.id NOT IN ({id_placeholders})
                    AND (q.Error_message IS NULL OR q.Error_message = '')
                    ORDER BY RAND()
                    LIMIT {remaining_count}
                    """
                    
                    supplement_params = knowledge_ids + existing_ids
                    
                    print(f"執行補充 SQL: {supplement_sql}")
                    print(f"補充 SQL 參數: {supplement_params}")
                    
                    cursor.execute(supplement_sql, supplement_params)
                    supplement_questions = cursor.fetchall()
                    all_questions.extend(supplement_questions)
                
                # 將結果轉換為 JSON 格式
                result = []
                for q in all_questions:
                    # 直接使用查詢中獲取的知識點名稱
                    knowledge_point = q['knowledge_point'] if q['knowledge_point'] else ""
                    
                    result.append({
                        "id": q["id"],
                        "question_text": q["question_text"],
                        "options": [
                            q["option_1"],
                            q["option_2"],
                            q["option_3"],
                            q["option_4"]
                        ],
                        "correct_answer": int(q["correct_answer"]) - 1,  # 轉換為 0-based 索引
                        "explanation": q["explanation"] or "",
                        "knowledge_point": knowledge_point,  # 添加知識點信息
                        "knowledge_id": q["knowledge_id"]  # 添加知識點ID
                    })
                
                return {"success": True, "questions": result}
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"獲取題目時出錯: {str(e)}"}

# 處理question_stats
@app.post("/record_answer")
async def record_answer(request: Request):
    try:
        data = await request.json()
        user_id = data.get('user_id')
        question_id = data.get('question_id')
        is_correct = data.get('is_correct')
        
        print(f"收到記錄答題請求: user_id={user_id}, question_id={question_id}, is_correct={is_correct}")
        
        if not user_id or not question_id:
            return {"success": False, "message": "缺少必要參數"}
        
        # 連接到資料庫
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 檢查記錄是否存在
                cursor.execute(
                    "SELECT id, total_attempts, correct_attempts FROM user_question_stats WHERE user_id = %s AND question_id = %s",
                    (user_id, question_id)
                )
                record = cursor.fetchone()
                
                current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                
                if record:
                    # 更新現有記錄
                    record_id = record['id']
                    total_attempts = record['total_attempts'] + 1
                    correct_attempts = record['correct_attempts'] + (1 if is_correct else 0)
                    
                    print(f"更新現有記錄: id={record_id}, total_attempts={total_attempts}, correct_attempts={correct_attempts}")
                    
                    cursor.execute(
                        "UPDATE user_question_stats SET total_attempts = %s, correct_attempts = %s, last_attempted_at = %s WHERE id = %s",
                        (total_attempts, correct_attempts, current_time, record_id)
                    )
                else:
                    # 創建新記錄
                    print(f"創建新記錄: user_id={user_id}, question_id={question_id}, is_correct={is_correct}")
                    
                    cursor.execute(
                        "INSERT INTO user_question_stats (user_id, question_id, total_attempts, correct_attempts, last_attempted_at) VALUES (%s, %s, %s, %s, %s)",
                        (user_id, question_id, 1, 1 if is_correct else 0, current_time)
                    )
                
                connection.commit()
                print(f"成功記錄答題情況")
                return {"success": True, "message": "答題記錄已保存"}
                
        except Exception as e:
            connection.rollback()
            print(f"資料庫錯誤: {str(e)}")
            return {"success": False, "message": f"資料庫錯誤: {str(e)}"}
        finally:
            connection.close()
            
    except Exception as e:
        print(f"處理答題記錄時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"處理錯誤: {str(e)}"}

@app.post("/report_question_error")
async def report_question_error(request: Request):
    try:
        data = await request.json()
        question_id = data.get("question_id")
        error_message = data.get("error_message")
        
        if not question_id or not error_message:
            return {"success": False, "message": "缺少必要參數"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 更新題目的錯誤訊息
                sql = """
                UPDATE questions 
                SET Error_message = %s 
                WHERE id = %s
                """
                cursor.execute(sql, (error_message, question_id))
                connection.commit()
                
                return {"success": True, "message": "回報成功"}
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"回報題目錯誤時出錯: {str(e)}"}

# 紀錄答題狀況、更新知識點紀錄
@app.post("/complete_level")
async def complete_level(request: Request):
    try:
        data = await request.json()
        user_id = data.get('user_id')
        level_id = data.get('level_id')
        stars = data.get('stars', 0)
        
        print(f"收到關卡完成請求: user_id={user_id}, level_id={level_id}, stars={stars}")
        
        if not user_id or not level_id:
            return {"success": False, "message": "缺少必要參數"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                
                # 每次都創建新記錄，不檢查是否已存在
                insert_sql = """
                INSERT INTO user_level (user_id, level_id, stars, answered_at) 
                VALUES (%s, %s, %s, %s)
                """
                cursor.execute(insert_sql, (user_id, level_id, stars, current_time))
                
                connection.commit()
                
                # 更新知識點分數
                # 從 level_info 表中獲取關卡對應的 chapter_id
                cursor.execute("""
                SELECT chapter_id FROM level_info WHERE id = %s
                """, (level_id,))
                level_result = cursor.fetchone()
                
                if not level_result:
                    return {"success": True, "message": "關卡完成記錄已新增，但無法更新知識點分數"}
                
                chapter_id = level_result['chapter_id']
                
                # 獲取該章節的所有知識點
                cursor.execute("""
                SELECT id, point_name FROM knowledge_points WHERE chapter_id = %s
                """, (chapter_id,))
                knowledge_points = cursor.fetchall()
                
                if not knowledge_points:
                    return {"success": True, "message": "關卡完成記錄已新增，但該章節沒有知識點"}
                
                knowledge_ids = [kp['id'] for kp in knowledge_points]
                
                # 更新這些知識點的分數
                updated_count = 0
                for knowledge_id in knowledge_ids:
                    # 獲取與該知識點相關的所有題目
                    cursor.execute("""
                    SELECT id 
                    FROM questions 
                    WHERE knowledge_id = %s
                    """, (knowledge_id,))
                    
                    questions = cursor.fetchall()
                    question_ids = [q['id'] for q in questions]
                    
                    if not question_ids:
                        continue
                    
                    # 獲取用戶對這些題目的答題記錄
                    placeholders = ', '.join(['%s'] * len(question_ids))
                    query = f"""
                    SELECT 
                        SUM(total_attempts) as total_attempts,
                        SUM(correct_attempts) as correct_attempts
                    FROM user_question_stats 
                    WHERE user_id = %s AND question_id IN ({placeholders})
                    """
                    
                    params = [user_id] + question_ids
                    cursor.execute(query, params)
                    stats = cursor.fetchone()
                    
                    # 計算分數
                    total_attempts = stats['total_attempts'] if stats and stats['total_attempts'] else 0
                    correct_attempts = stats['correct_attempts'] if stats and stats['correct_attempts'] else 0
                    
                    # 分數計算公式
                    if total_attempts == 0:
                        score = 0  # 沒有嘗試過，分數為 0
                    else:
                        # 使用正確率作為基礎分數
                        accuracy = correct_attempts / total_attempts
                        
                        # 根據嘗試次數給予額外加權（熟練度）
                        experience_factor = min(1, total_attempts / 10)  # 最多嘗試 10 次達到滿分加權
                        
                        # 最終分數 = 正確率 * 10 * 經驗係數
                        score = accuracy * 10 * experience_factor
                    
                    # 限制分數在 0-10 範圍內
                    score = min(max(score, 0), 10)
                    
                    # 更新知識點分數
                    cursor.execute("""
                    INSERT INTO user_knowledge_score (user_id, knowledge_id, score)
                    VALUES (%s, %s, %s)
                    ON DUPLICATE KEY UPDATE score = VALUES(score)
                    """, (user_id, knowledge_id, score))
                    
                    updated_count += 1
                
                connection.commit()
                
                return {"success": True, "message": "關卡完成記錄已新增"}
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"記錄關卡完成時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"記錄關卡完成時出錯: {str(e)}"}

@app.post("/update_knowledge_score")
async def update_knowledge_score(request: Request):
    try:
        data = await request.json()
        user_id = data.get('user_id')
        level_id = data.get('level_id')  # 新增參數，可選
        
        print(f"收到更新知識點分數請求: user_id={user_id}, level_id={level_id}")
        
        if not user_id:
            print(f"錯誤: 缺少用戶 ID")
            return {"success": False, "message": "缺少用戶 ID"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 如果提供了關卡 ID，只更新該關卡相關的知識點
                if level_id:
                    print(f"只更新關卡 {level_id} 相關的知識點")
                    await _update_level_knowledge_scores(user_id, level_id, connection)
                    return {
                        "success": True, 
                        "message": f"已更新關卡 {level_id} 相關的知識點分數"
                    }
                
                # 否則更新所有知識點（保留原有功能）
                print(f"更新所有知識點")
                # 獲取所有知識點
                cursor.execute("SELECT id FROM knowledge_points")
                all_knowledge_points = cursor.fetchall()
                print(f"找到 {len(all_knowledge_points)} 個知識點")
                
                updated_scores = []
                
                # 對每個知識點計算分數
                for point in all_knowledge_points:
                    knowledge_id = point['id']
                    
                    # 獲取與該知識點相關的所有題目
                    cursor.execute("""
                    SELECT q.id 
                    FROM questions q 
                    WHERE q.knowledge_id = %s
                    """, (knowledge_id,))
                    
                    questions = cursor.fetchall()
                    question_ids = [q['id'] for q in questions]
                    
                    if not question_ids:
                        # 如果沒有相關題目，跳過此知識點
                        continue
                    
                    # 獲取用戶對這些題目的答題記錄
                    placeholders = ', '.join(['%s'] * len(question_ids))
                    query = f"""
                    SELECT 
                        SUM(total_attempts) as total_attempts,
                        SUM(correct_attempts) as correct_attempts
                    FROM user_question_stats 
                    WHERE user_id = %s AND question_id IN ({placeholders})
                    """
                    
                    params = [user_id] + question_ids
                    cursor.execute(query, params)
                    stats = cursor.fetchone()
                    
                    # 計算分數
                    total_attempts = stats['total_attempts'] if stats['total_attempts'] else 0
                    correct_attempts = stats['correct_attempts'] if stats['correct_attempts'] else 0
                    
                    # 修正的分數計算公式
                    if total_attempts == 0:
                        score = 0  # 沒有嘗試過，分數為 0
                    else:
                        # 使用正確率作為基礎分數
                        accuracy = correct_attempts / total_attempts
                        
                        # 根據嘗試次數給予額外加權（熟練度）
                        experience_factor = min(1, total_attempts / 10)  # 最多嘗試 10 次達到滿分加權
                        
                        # 最終分數 = 正確率 * 10 * 經驗係數
                        score = accuracy * 10 * experience_factor
                    
                    # 限制分數在 0-10 範圍內
                    score = min(max(score, 0), 10)
                    
                    # 更新知識點分數
                    update_sql = """
                    INSERT INTO user_knowledge_score (user_id, knowledge_id, score)
                    VALUES (%s, %s, %s)
                    ON DUPLICATE KEY UPDATE score = VALUES(score)
                    """
                    print(f"執行 SQL: {update_sql} 參數: {user_id}, {knowledge_id}, {score}")
                    
                    cursor.execute(update_sql, (user_id, knowledge_id, score))
                    affected_rows = cursor.rowcount
                    print(f"知識點 {knowledge_id} 更新結果: 影響 {affected_rows} 行")
                    
                    updated_scores.append({
                        "knowledge_id": knowledge_id,
                        "score": score,
                        "total_attempts": total_attempts,
                        "correct_attempts": correct_attempts,
                        "affected_rows": affected_rows
                    })
                
                print(f"提交事務，更新了 {len(updated_scores)} 個知識點")
                connection.commit()
                print(f"事務提交成功")
                
                return {
                    "success": True, 
                    "message": f"已更新 {len(updated_scores)} 個知識點的分數",
                    "updated_scores": updated_scores
                }
        
        finally:
            connection.close()
            print(f"資料庫連接已關閉")
    
    except Exception as e:
        print(f"更新知識點分數時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"更新知識點分數時出錯: {str(e)}"}

@app.get("/get_knowledge_scores/{user_id}")
async def get_knowledge_scores(user_id: str):
    try:
        print(f"收到獲取用戶知識點分數請求: user_id={user_id}")
        
        if not user_id:
            print(f"錯誤: 缺少用戶 ID")
            return {"success": False, "message": "缺少用戶 ID"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 獲取用戶的知識點分數，包括知識點名稱和小節名稱
                cursor.execute("""
                SELECT 
                    uks.knowledge_id,
                    uks.score,
                    kp.point_name,
                    kp.section_name,
                    cl.subject
                FROM 
                    user_knowledge_score uks
                JOIN 
                    knowledge_points kp ON uks.knowledge_id = kp.id
                JOIN 
                    chapter_list cl ON kp.chapter_id = cl.id
                WHERE 
                    uks.user_id = %s
                ORDER BY 
                    uks.score DESC
                """, (user_id,))
                
                scores = cursor.fetchall()
                
                return {
                    "success": True,
                    "scores": scores
                }
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"獲取用戶知識點分數時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"獲取用戶知識點分數時出錯: {str(e)}"}

@app.get("/get_weekly_stats/{user_id}")
async def get_weekly_stats(user_id: str):
    try:
        print(f"收到獲取用戶每週學習統計請求: user_id={user_id}")
        
        if not user_id:
            print(f"錯誤: 缺少用戶 ID")
            return {"success": False, "message": "缺少用戶 ID"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 獲取當前日期
                from datetime import datetime, timedelta
                today = datetime.now().date()
                
                # 計算本週的開始日期（週一）
                days_since_monday = today.weekday()
                this_week_start = today - timedelta(days=days_since_monday)
                
                # 計算上週的開始和結束日期
                last_week_start = this_week_start - timedelta(days=7)
                last_week_end = this_week_start - timedelta(days=1)
                
                # 獲取本週每天的完成關卡數
                this_week_stats = []
                for i in range(7):
                    day = this_week_start + timedelta(days=i)
                    day_start = datetime.combine(day, datetime.min.time())
                    day_end = datetime.combine(day, datetime.max.time())
                    
                    cursor.execute("""
                    SELECT COUNT(*) as level_count
                    FROM user_level
                    WHERE user_id = %s AND answered_at BETWEEN %s AND %s
                    """, (user_id, day_start, day_end))
                    
                    result = cursor.fetchone()
                    level_count = result['level_count'] if result else 0
                    
                    this_week_stats.append({
                        'day': ['週一', '週二', '週三', '週四', '週五', '週六', '週日'][i],
                        'date': day.strftime('%Y-%m-%d'),
                        'levels': level_count
                    })
                
                # 獲取上週每天的完成關卡數
                last_week_stats = []
                for i in range(7):
                    day = last_week_start + timedelta(days=i)
                    day_start = datetime.combine(day, datetime.min.time())
                    day_end = datetime.combine(day, datetime.max.time())
                    
                    cursor.execute("""
                    SELECT COUNT(*) as level_count
                    FROM user_level
                    WHERE user_id = %s AND answered_at BETWEEN %s AND %s
                    """, (user_id, day_start, day_end))
                    
                    result = cursor.fetchone()
                    level_count = result['level_count'] if result else 0
                    
                    last_week_stats.append({
                        'day': ['週一', '週二', '週三', '週四', '週五', '週六', '週日'][i],
                        'date': day.strftime('%Y-%m-%d'),
                        'levels': level_count
                    })
                
                # 計算學習連續性（連續學習的天數）
                cursor.execute("""
                SELECT DISTINCT DATE(answered_at) as study_date
                FROM user_level
                WHERE user_id = %s
                ORDER BY study_date DESC
                LIMIT 30
                """, (user_id,))
                
                study_dates = [row['study_date'] for row in cursor.fetchall()]
                
                streak = 0
                if study_dates:
                    # 檢查今天是否有學習
                    if study_dates[0] == today:
                        streak = 1
                        # 檢查之前的連續天數
                        for i in range(1, len(study_dates)):
                            prev_date = study_dates[i-1]
                            curr_date = study_dates[i]
                            if (prev_date - curr_date).days == 1:
                                streak += 1
                            else:
                                break
                
                return {
                    "success": True,
                    "weekly_stats": {
                        "this_week": this_week_stats,
                        "last_week": last_week_stats
                    },
                    "streak": streak
                }
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"獲取用戶每週學習統計時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"獲取用戶每週學習統計時出錯: {str(e)}"}

@app.get("/get_learning_suggestions/{user_id}")
async def get_learning_suggestions(user_id: str):
    try:
        print(f"收到獲取用戶學習建議請求: user_id={user_id}")
        
        if not user_id:
            print(f"錯誤: 缺少用戶 ID")
            return {"success": False, "message": "缺少用戶 ID"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 獲取弱點知識點（分數低於5分的）
                cursor.execute("""
                SELECT 
                    uks.knowledge_id,
                    uks.score,
                    kp.point_name,
                    kp.section_name,
                    cl.subject,
                    cl.chapter_name
                FROM 
                    user_knowledge_score uks
                JOIN 
                    knowledge_points kp ON uks.knowledge_id = kp.id
                JOIN 
                    chapter_list cl ON kp.chapter_id = cl.id
                WHERE 
                    uks.user_id = %s AND uks.score < 5
                ORDER BY 
                    uks.score ASC
                LIMIT 10
                """, (user_id,))
                
                weak_points = cursor.fetchall()
                
                # 獲取推薦的下一步學習章節
                cursor.execute("""
                SELECT 
                    cl.id as chapter_id,
                    cl.subject,
                    cl.chapter_name,
                    AVG(uks.score) as avg_score,
                    COUNT(DISTINCT li.id) as total_levels,
                    COUNT(DISTINCT ul.level_id) as completed_levels
                FROM 
                    chapter_list cl
                JOIN 
                    knowledge_points kp ON cl.id = kp.chapter_id
                JOIN 
                    user_knowledge_score uks ON kp.id = uks.knowledge_id
                LEFT JOIN 
                    level_info li ON cl.id = li.chapter_id
                LEFT JOIN 
                    user_level ul ON li.id = ul.level_id AND ul.user_id = %s
                WHERE 
                    uks.user_id = %s
                GROUP BY 
                    cl.id, cl.subject, cl.chapter_name
                ORDER BY 
                    avg_score ASC, (total_levels - completed_levels) DESC
                LIMIT 5
                """, (user_id, user_id))
                
                recommended_chapters = cursor.fetchall()
                
                # 生成學習建議
                tips = [
                    "每天保持固定的學習時間，建立學習習慣",
                    "專注於弱點知識點，逐一攻克",
                    "複習已完成的關卡，鞏固知識",
                    "嘗試不同科目的學習，保持學習的多樣性",
                    "設定每週學習目標，追蹤進度"
                ]
                
                # 根據弱點知識點生成具體建議
                if weak_points:
                    subjects = set([wp['subject'] for wp in weak_points])
                    for subject in subjects:
                        subject_weak_points = [wp for wp in weak_points if wp['subject'] == subject]
                        if subject_weak_points:
                            point_names = [wp['point_name'] for wp in subject_weak_points[:3]]
                            tips.append(f"加強{subject}科目中的{', '.join(point_names)}等知識點")
                
                return {
                    "success": True,
                    "weak_points": weak_points,
                    "recommended_chapters": recommended_chapters,
                    "tips": tips
                }
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"獲取用戶學習建議時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"獲取用戶學習建議時出錯: {str(e)}"}

# 新增輔助函數：更新特定關卡相關的知識點分數
async def _update_level_knowledge_scores(user_id: str, level_id: str, connection):
    try:
        print(f"正在更新用戶 {user_id} 的關卡 {level_id} 相關知識點分數...")
        
        with connection.cursor() as cursor:
            # 從 level_knowledge_mapping 表獲取關卡相關的知識點
            cursor.execute("""
            SELECT knowledge_id
            FROM level_knowledge_mapping
            WHERE level_id = %s
            """, (level_id,))
            
            knowledge_points = cursor.fetchall()
            knowledge_ids = [point['knowledge_id'] for point in knowledge_points if point['knowledge_id']]
            
            # 如果沒有找到知識點映射，嘗試從題目中獲取
            if not knowledge_ids:
                print(f"在 level_knowledge_mapping 中找不到關卡 {level_id} 的知識點，嘗試從題目中獲取...")
                
                # 獲取該關卡的所有題目
                cursor.execute("""
                SELECT DISTINCT q.knowledge_id
                FROM questions q
                JOIN level_questions lq ON q.id = lq.question_id
                WHERE lq.level_id = %s
                """, (level_id,))
                
                question_knowledge_points = cursor.fetchall()
                knowledge_ids = [point['knowledge_id'] for point in question_knowledge_points if point['knowledge_id']]
            
            if not knowledge_ids:
                print(f"警告: 找不到關卡 {level_id} 相關的知識點，無法更新分數")
                return
            
            print(f"找到 {len(knowledge_ids)} 個關卡相關知識點: {knowledge_ids}")
            updated_count = 0
            
            # 對每個知識點計算分數
            for knowledge_id in knowledge_ids:
                # 獲取與該知識點相關的所有題目
                cursor.execute("""
                SELECT id 
                FROM questions 
                WHERE knowledge_id = %s
                """, (knowledge_id,))
                
                questions = cursor.fetchall()
                question_ids = [q['id'] for q in questions]
                
                if not question_ids:
                    print(f"知識點 {knowledge_id} 沒有相關題目，跳過")
                    continue
                
                # 獲取用戶對這些題目的答題記錄
                placeholders = ', '.join(['%s'] * len(question_ids))
                query = f"""
                SELECT 
                    SUM(total_attempts) as total_attempts,
                    SUM(correct_attempts) as correct_attempts
                FROM user_question_stats 
                WHERE user_id = %s AND question_id IN ({placeholders})
                """
                
                params = [user_id] + question_ids
                cursor.execute(query, params)
                stats = cursor.fetchone()
                
                # 計算分數
                total_attempts = stats['total_attempts'] if stats and stats['total_attempts'] else 0
                correct_attempts = stats['correct_attempts'] if stats and stats['correct_attempts'] else 0
                
                # 分數計算公式
                if total_attempts == 0:
                    score = 0  # 沒有嘗試過，分數為 0
                else:
                    # 使用正確率作為基礎分數
                    accuracy = correct_attempts / total_attempts
                    
                    # 根據嘗試次數給予額外加權（熟練度）
                    experience_factor = min(1, total_attempts / 10)  # 最多嘗試 10 次達到滿分加權
                    
                    # 最終分數 = 正確率 * 10 * 經驗係數
                    score = accuracy * 10 * experience_factor
                
                # 限制分數在 0-10 範圍內
                score = min(max(score, 0), 10)
                
                # 更新知識點分數
                cursor.execute("""
                INSERT INTO user_knowledge_score (user_id, knowledge_id, score)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE score = VALUES(score)
                """, (user_id, knowledge_id, score))
                
                updated_count += 1
                print(f"已更新知識點 {knowledge_id} 的分數: {score}")
            
            connection.commit()
            print(f"已更新 {updated_count} 個知識點的分數")
        
    except Exception as e:
        print(f"更新關卡知識點分數時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())

# 修改處理每日使用量通知的 API
@app.get("/notify-daily-report")
async def notify_daily_report():
    try:
        print("開始執行每日報告功能...")
        import smtplib
        from email.mime.text import MIMEText
        from datetime import datetime, timedelta, timezone
        
        # 獲取環境變數
        GMAIL_ADDRESS = os.getenv("GMAIL_ADDRESS")
        APP_PASSWORD = os.getenv("APP_PASSWORD")
        RECEIVERS = os.getenv("RECEIVERS", "").split(",") if os.getenv("RECEIVERS") else []
        
        print(f"環境變數檢查: GMAIL_ADDRESS={'已設置' if GMAIL_ADDRESS else '未設置'}")
        print(f"環境變數檢查: APP_PASSWORD={'已設置' if APP_PASSWORD else '未設置'}")
        print(f"環境變數檢查: RECEIVERS={RECEIVERS}")
        
        # 發送郵件
        def send_email(subject, body):
            print(f"準備發送郵件: 主題={subject}, 收件人={RECEIVERS}")
            if not GMAIL_ADDRESS or not APP_PASSWORD or not RECEIVERS:
                print("警告: 郵件發送信息不完整，無法發送郵件")
                return False
                
            try:
                msg = MIMEText(body, "plain", "utf-8")
                msg["Subject"] = subject
                msg["From"] = GMAIL_ADDRESS
                msg["To"] = ", ".join(RECEIVERS)
                
                print("連接到 SMTP 服務器...")
                with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
                    print("登錄 SMTP 服務器...")
                    server.login(GMAIL_ADDRESS, APP_PASSWORD)
                    print("發送郵件...")
                    server.sendmail(GMAIL_ADDRESS, RECEIVERS, msg.as_string())
                    print("郵件發送成功")
                return True
            except Exception as e:
                print(f"發送郵件時出錯: {e}")
                import traceback
                print(traceback.format_exc())
                return False
        
        # 獲取當日關卡數據
        print("開始獲取當日關卡數據...")
        
        # 計算昨天的日期
        today = datetime.now().date()
        yesterday = today - timedelta(days=1)
        yesterday_start = datetime.combine(yesterday, datetime.min.time())
        yesterday_end = datetime.combine(yesterday, datetime.max.time())
        
        yesterday_start_str = yesterday_start.strftime('%Y-%m-%d %H:%M:%S')
        yesterday_end_str = yesterday_end.strftime('%Y-%m-%d %H:%M:%S')
        
        print(f"查詢日期範圍: {yesterday_start_str} 至 {yesterday_end_str}")
        
        # 連接到資料庫
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 獲取昨天完成的關卡數量
                cursor.execute("""
                SELECT COUNT(*) as total_levels, COUNT(DISTINCT user_id) as total_users
                FROM user_level
                WHERE answered_at BETWEEN %s AND %s
                """, (yesterday_start_str, yesterday_end_str))
                
                level_stats = cursor.fetchone()
                total_levels = level_stats['total_levels'] if level_stats else 0
                total_users = level_stats['total_users'] if level_stats else 0
                
                # 獲取昨天的答題數量
                cursor.execute("""
                SELECT COUNT(*) as total_answers, COUNT(DISTINCT user_id) as answer_users
                FROM user_question_stats
                WHERE last_attempted_at BETWEEN %s AND %s
                """, (yesterday_start_str, yesterday_end_str))
                
                # 獲取昨天活躍的前5名用戶
                cursor.execute("""
                SELECT user_id, COUNT(*) as level_count
                FROM user_level
                WHERE answered_at BETWEEN %s AND %s
                GROUP BY user_id
                ORDER BY level_count DESC
                LIMIT 5
                """, (yesterday_start_str, yesterday_end_str))
                
                top_users = cursor.fetchall()
                
                # 獲取用戶名稱
                top_user_details = []
                for user in top_users:
                    cursor.execute("SELECT name FROM users WHERE user_id = %s", (user['user_id'],))
                    user_info = cursor.fetchone()
                    user_name = user_info['name'] if user_info and user_info['name'] else user['user_id']
                    top_user_details.append({
                        "name": user_name,
                        "level_count": user['level_count']
                    })
        
        finally:
            connection.close()
        
        # 構建郵件內容
        today_str = today.strftime("%Y-%m-%d")
        yesterday_str = yesterday.strftime("%Y-%m-%d")
        subject = f"【Dogtor 每日系統報告】{today_str}"
        
        print("構建郵件內容...")
        body = f"""Dogtor 每日使用報告 ({yesterday_str})：

【使用統計】
昨日完成關卡數：{total_levels} 個
昨日活躍用戶數：{total_users} 人
"""

        if top_user_details:
            body += "\n【昨日最活躍用戶】\n"
            for i, user in enumerate(top_user_details, 1):
                body += f"{i}. {user['name']} - 完成 {user['level_count']} 個關卡\n"
        
        body += """
祝您有美好的一天！

（本報告由系統自動生成，請勿直接回覆）
"""
        
        print("郵件內容構建完成，開始發送...")
        email_sent = send_email(subject, body)
        
        if email_sent:
            return {"status": "success", "message": "每日報告已發送"}
        else:
            return {"status": "warning", "message": "每日報告生成成功，但郵件發送失敗"}
            
    except Exception as e:
        print(f"發送每日報告時出錯: {e}")
        import traceback
        print(traceback.format_exc())
        return {"status": "error", "message": f"發送每日報告時出錯: {str(e)}"}

@app.post("/get_user_stats")
async def get_user_stats(request: Request):
    try:
        data = await request.json()
        user_id = data.get('user_id')
        
        print(f"收到獲取用戶統計數據請求: user_id={user_id}")
        
        if not user_id:
            print(f"錯誤: 缺少用戶 ID")
            return {"success": False, "message": "缺少用戶 ID"}
        
        connection = get_db_connection()
        connection.charset = 'utf8mb4'
        
        try:
            with connection.cursor() as cursor:
                # 設置連接的字符集
                cursor.execute("SET NAMES utf8mb4")
                cursor.execute("SET CHARACTER SET utf8mb4")
                cursor.execute("SET character_set_connection=utf8mb4")
                
                # 獲取今天的日期範圍
                today = datetime.now().date()
                today_start = datetime.combine(today, datetime.min.time())
                today_end = datetime.combine(today, datetime.max.time())
                
                today_start_str = today_start.strftime('%Y-%m-%d %H:%M:%S')
                today_end_str = today_end.strftime('%Y-%m-%d %H:%M:%S')
                
                # 1. 獲取今日完成的關卡數量
                cursor.execute("""
                SELECT COUNT(*) as today_levels
                FROM user_level
                WHERE user_id = %s AND answered_at BETWEEN %s AND %s
                """, (user_id, today_start_str, today_end_str))
                
                today_result = cursor.fetchone()
                today_levels = today_result['today_levels'] if today_result else 0
                
                # 2. 獲取今日各科目完成的關卡數量
                cursor.execute("""
                SELECT cl.subject, COUNT(*) as level_count
                FROM user_level ul
                JOIN level_info li ON ul.level_id = li.id
                JOIN chapter_list cl ON li.chapter_id = cl.id
                WHERE ul.user_id = %s AND ul.answered_at BETWEEN %s AND %s
                GROUP BY cl.subject
                """, (user_id, today_start_str, today_end_str))
                
                today_subject_levels = cursor.fetchall()
                
                # 3. 獲取各科目完成的關卡數量
                cursor.execute("""
                SELECT cl.subject, COUNT(*) as level_count
                FROM user_level ul
                JOIN level_info li ON ul.level_id = li.id
                JOIN chapter_list cl ON li.chapter_id = cl.id
                WHERE ul.user_id = %s
                GROUP BY cl.subject
                """, (user_id,))
                
                subject_levels = cursor.fetchall()
                
                # 4. 獲取總共完成的關卡數量
                cursor.execute("""
                SELECT COUNT(*) as total_levels
                FROM user_level
                WHERE user_id = %s
                """, (user_id,))
                
                total_result = cursor.fetchone()
                total_levels = total_result['total_levels'] if total_result else 0
                
                # 5. 獲取總體答對率
                cursor.execute("""
                SELECT 
                    SUM(total_attempts) as total_attempts,
                    SUM(correct_attempts) as correct_attempts
                FROM user_question_stats
                WHERE user_id = %s
                """, (user_id,))
                
                accuracy_result = cursor.fetchone()
                total_attempts = accuracy_result['total_attempts'] if accuracy_result and accuracy_result['total_attempts'] else 0
                correct_attempts = accuracy_result['correct_attempts'] if accuracy_result and accuracy_result['correct_attempts'] else 0
                
                accuracy = 0
                if total_attempts > 0:
                    accuracy = (correct_attempts / total_attempts) * 100
                
                # 6. 獲取最近完成的關卡
                cursor.execute("""
                SELECT 
                    ul.level_id, 
                    ul.stars, 
                    ul.answered_at,
                    cl.subject,
                    cl.chapter_name
                FROM user_level ul
                JOIN level_info li ON ul.level_id = li.id
                JOIN chapter_list cl ON li.chapter_id = cl.id
                WHERE ul.user_id = %s
                ORDER BY ul.answered_at DESC
                LIMIT 5
                """, (user_id,))
                
                recent_levels = cursor.fetchall()
                
                # 格式化最近關卡的時間
                for level in recent_levels:
                    if 'answered_at' in level and level['answered_at']:
                        level['answered_at'] = level['answered_at'].strftime('%Y-%m-%d %H:%M:%S')
                
                return {
                    "success": True,
                    "stats": {
                        "today_levels": today_levels,
                        "today_subject_levels": today_subject_levels,
                        "subject_levels": subject_levels,
                        "total_levels": total_levels,
                        "accuracy": round(accuracy, 2),
                        "recent_levels": recent_levels
                    }
                }
        
        finally:
            connection.close()
    
    except Exception as e:
        print(f"獲取用戶統計數據時出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
        return {"success": False, "message": f"獲取用戶統計數據時出錯: {str(e)}"}