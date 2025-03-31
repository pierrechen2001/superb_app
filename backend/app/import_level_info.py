import csv
import pymysql
import os
from dotenv import load_dotenv
import pandas as pd

# 載入環境變數
load_dotenv()

# 數據庫連接配置
DB_HOST = os.getenv("DB_HOST")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")

#print("password:", DB_PASSWORD)

#password=DB_PASSWORD,
def get_db_connection():
    """建立與數據庫的連接"""
    return pymysql.connect(
        host=DB_HOST,
        port=3306,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )

def import_level_info(csv_file_path):
    """從 CSV 檔案導入關卡資訊到數據庫，並將生成的 level ID 寫回 CSV"""
    connection = get_db_connection()
    
    # 使用 pandas 讀取 CSV 檔案
    df = pd.read_csv(csv_file_path, encoding='utf-8')
    
    # 添加 level_id 列（如果不存在）
    if 'level_id' not in df.columns:
        df['level_id'] = None
    
    try:
        with connection.cursor() as cursor:
            # 設置連接的字符集
            cursor.execute("SET NAMES utf8mb4")
            cursor.execute("SET CHARACTER SET utf8mb4")
            cursor.execute("SET character_set_connection=utf8mb4")
            
            # 遍歷每一行數據
            for index, row in df.iterrows():
                # 查找章節 ID
                chapter_sql = """
                SELECT id FROM chapter_list 
                WHERE year_grade = %s 
                AND chapter_name = %s
                """
                cursor.execute(chapter_sql, (
                    row['年級'],
                    row['章節名稱']
                ))
                chapter_result = cursor.fetchone()
                
                if not chapter_result:
                    print(f"找不到章節: 年級={row['年級']}, 章節名稱={row['章節名稱']}")
                    continue
                
                chapter_id = chapter_result['id']
                
                # 檢查關卡是否存在
                level_sql = """
                SELECT id FROM level_info 
                WHERE chapter_id = %s 
                AND level_num = %s
                """
                cursor.execute(level_sql, (
                    chapter_id,
                    row['關卡編號']
                ))
                level_result = cursor.fetchone()
                
                if not level_result:
                    # 創建新關卡
                    insert_level_sql = """
                    INSERT INTO level_info (chapter_id, level_num)
                    VALUES (%s, %s)
                    """
                    cursor.execute(insert_level_sql, (
                        chapter_id,
                        row['關卡編號']
                    ))
                    connection.commit()
                    level_id = cursor.lastrowid
                    print(f"已創建關卡: 章節ID={chapter_id}, 關卡編號={row['關卡編號']} (ID: {level_id})")
                    
                    # 將生成的 level_id 寫入 DataFrame
                    df.at[index, 'level_id'] = level_id
                else:
                    level_id = level_result['id']
                    print(f"關卡已存在: 章節ID={chapter_id}, 關卡編號={row['關卡編號']} (ID: {level_id})")
                    
                    # 將現有的 level_id 寫入 DataFrame
                    df.at[index, 'level_id'] = level_id
            
            # 將更新後的 DataFrame 寫回 CSV 檔案
            df.to_csv(csv_file_path, index=False, encoding='utf-8')
            
            print("關卡資訊導入完成，並已將 level_id 寫回 CSV 檔案！")
    
    except Exception as e:
        print(f"導入過程中出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
    
    finally:
        connection.close()

def update_csv_with_level_ids(csv_file_path):
    """僅更新 CSV 檔案中的 level_id，不進行導入操作"""
    connection = get_db_connection()
    
    # 使用 pandas 讀取 CSV 檔案
    df = pd.read_csv(csv_file_path, encoding='utf-8')
    
    # 添加 level_id 列（如果不存在）
    if 'level_id' not in df.columns:
        df['level_id'] = None
    
    try:
        with connection.cursor() as cursor:
            # 設置連接的字符集
            cursor.execute("SET NAMES utf8mb4")
            cursor.execute("SET CHARACTER SET utf8mb4")
            cursor.execute("SET character_set_connection=utf8mb4")
            
            # 遍歷每一行數據
            for index, row in df.iterrows():
                # 查找章節 ID
                chapter_sql = """
                SELECT id FROM chapter_list 
                WHERE year_grade = %s 
                AND chapter_name = %s
                """
                cursor.execute(chapter_sql, (
                    row['年級'],
                    row['章節名稱']
                ))
                chapter_result = cursor.fetchone()
                
                if not chapter_result:
                    print(f"找不到章節: 年級={row['年級']}, 章節名稱={row['章節名稱']}")
                    continue
                
                chapter_id = chapter_result['id']
                
                # 查找關卡 ID
                level_sql = """
                SELECT id FROM level_info 
                WHERE chapter_id = %s 
                AND level_num = %s
                """
                cursor.execute(level_sql, (
                    chapter_id,
                    row['關卡編號']
                ))
                level_result = cursor.fetchone()
                
                if level_result:
                    level_id = level_result['id']
                    print(f"找到關卡: 章節ID={chapter_id}, 關卡編號={row['關卡編號']} (ID: {level_id})")
                    
                    # 將 level_id 寫入 DataFrame
                    df.at[index, 'level_id'] = level_id
                else:
                    print(f"找不到關卡: 章節ID={chapter_id}, 關卡編號={row['關卡編號']}")
            
            # 將更新後的 DataFrame 寫回 CSV 檔案
            df.to_csv(csv_file_path, index=False, encoding='utf-8')
            
            print("已將 level_id 寫回 CSV 檔案！")
    
    except Exception as e:
        print(f"更新過程中出錯: {str(e)}")
        import traceback
        print(traceback.format_exc())
    
    finally:
        connection.close()

if __name__ == "__main__":
    # CSV 檔案路徑
    csv_file_path = "level_info_civ.csv" # 要改這個路徑！！！！
    
    # 選擇操作模式
    mode = input("選擇操作模式：1. 導入關卡資訊並更新 CSV  2. 僅更新 CSV 中的 level_id：")
    
    if mode == "1":
        # 導入關卡資訊並更新 CSV
        import_level_info(csv_file_path)
    elif mode == "2":
        # 僅更新 CSV 中的 level_id
        update_csv_with_level_ids(csv_file_path)
    else:
        print("無效的選擇！")