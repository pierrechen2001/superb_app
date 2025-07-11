"""
推播通知相關 API
"""
from fastapi import APIRouter, HTTPException, Body
from database import get_db_connection
from models import PushNotificationRequest, LearningReminderRequest, RegisterTokenRequest, StandardResponse
from typing import Dict, Any
import traceback
import firebase_admin
from firebase_admin import credentials, messaging
from datetime import datetime

router = APIRouter(prefix="/notifications", tags=["Notifications"])

# 初始化 Firebase Admin（如果尚未初始化）
try:
    firebase_admin.get_app()
    print("✅ Firebase Admin 已經初始化過了")
except ValueError:
    # Firebase Admin 尚未初始化
    cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred)
    print("✅ Firebase Admin 初始化成功")


def send_push_notification(token: str, title: str, body: str) -> str:
    """發送推播通知"""
    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            token=token,
        )
        response = messaging.send(message)
        print(f"✅ 已送出推播：{token[:10]}... → {response}")
        return response
    except Exception as e:
        print(f"❌ 發送失敗：{e}")
        return "error"


@router.post("/register_token", response_model=StandardResponse)
async def register_token(request: RegisterTokenRequest):
    """註冊推播 token"""
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 檢查 token 是否已存在
            sql = "SELECT COUNT(*) as count FROM user_tokens WHERE user_id = %s AND token = %s"
            cursor.execute(sql, (request.user_id, request.token))
            result = cursor.fetchone()
            
            if result['count'] == 0:
                # 插入新 token
                sql = """
                INSERT INTO user_tokens (user_id, token, created_at, is_active) 
                VALUES (%s, %s, NOW(), 1)
                """
                cursor.execute(sql, (request.user_id, request.token))
                connection.commit()
                return StandardResponse(success=True, message="Token 註冊成功")
            else:
                # 更新現有 token 為活躍狀態
                sql = "UPDATE user_tokens SET is_active = 1, updated_at = NOW() WHERE user_id = %s AND token = %s"
                cursor.execute(sql, (request.user_id, request.token))
                connection.commit()
                return StandardResponse(success=True, message="Token 已更新")
    
    except Exception as e:
        print(f"[register_token] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()


@router.post("/send_test_push", response_model=StandardResponse)
async def send_test_push(request: dict = Body(...)):
    """發送測試推播"""
    try:
        user_id = request.get('user_id')
        title = request.get('title', '測試推播')
        body = request.get('body', '這是一個測試推播')
        
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 獲取用戶的活躍 token
            sql = "SELECT token FROM user_tokens WHERE user_id = %s AND is_active = 1"
            cursor.execute(sql, (user_id,))
            tokens = cursor.fetchall()
            
            if not tokens:
                return StandardResponse(success=False, message="找不到用戶的推播 token")
            
            success_count = 0
            for token_record in tokens:
                token = token_record['token']
                result = send_push_notification(token, title, body)
                if result != "error":
                    success_count += 1
            
            return StandardResponse(
                success=success_count > 0,
                message=f"成功發送 {success_count}/{len(tokens)} 個推播"
            )
    
    except Exception as e:
        print(f"[send_test_push] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()


@router.post("/send_learning_reminder", response_model=StandardResponse)
async def send_learning_reminder(request: LearningReminderRequest):
    """發送學習提醒"""
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 獲取用戶的活躍 token
            sql = "SELECT token FROM user_tokens WHERE user_id = %s AND is_active = 1"
            cursor.execute(sql, (request.user_id,))
            tokens = cursor.fetchall()
            
            if not tokens:
                return StandardResponse(success=False, message="找不到用戶的推播 token")
            
            # 自定義推播內容
            title = "🎓 學習提醒"
            body = f"該複習 {request.subject} - {request.chapter} 了！保持學習動力 💪"
            
            if request.difficulty_level == "高":
                body += " 這個章節比較有挑戰性，加油！"
            
            success_count = 0
            for token_record in tokens:
                token = token_record['token']
                result = send_push_notification(token, title, body)
                if result != "error":
                    success_count += 1
            
            # 記錄提醒歷史
            sql = """
            INSERT INTO reminder_history (user_id, subject, chapter, difficulty_level, sent_at, success_count)
            VALUES (%s, %s, %s, %s, NOW(), %s)
            """
            cursor.execute(sql, (request.user_id, request.subject, request.chapter, 
                                request.difficulty_level, success_count))
            connection.commit()
            
            return StandardResponse(
                success=success_count > 0,
                message=f"學習提醒已發送給 {success_count} 個設備"
            )
    
    except Exception as e:
        print(f"[send_learning_reminder] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()


@router.post("/cron_push_heart_reminder", response_model=StandardResponse)
async def cron_push_heart_reminder():
    """定時發送愛心恢復提醒（Cron 任務）"""
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 查找愛心不滿且有 token 的用戶
            sql = """
            SELECT DISTINCT u.user_id, ut.token
            FROM users u
            JOIN user_tokens ut ON u.user_id = ut.user_id
            WHERE u.hearts < u.max_hearts 
            AND ut.is_active = 1
            AND u.user_id NOT IN (
                SELECT user_id FROM reminder_history 
                WHERE sent_at > DATE_SUB(NOW(), INTERVAL 2 HOUR)
                AND subject = 'heart_reminder'
            )
            """
            cursor.execute(sql)
            users_tokens = cursor.fetchall()
            
            total_sent = 0
            for record in users_tokens:
                user_id = record['user_id']
                token = record['token']
                
                title = "💖 愛心已恢復！"
                body = "你的愛心已經恢復了，快來繼續學習吧！"
                
                result = send_push_notification(token, title, body)
                if result != "error":
                    total_sent += 1
                    
                    # 記錄提醒歷史
                    sql = """
                    INSERT INTO reminder_history (user_id, subject, chapter, difficulty_level, sent_at, success_count)
                    VALUES (%s, 'heart_reminder', '', '', NOW(), 1)
                    """
                    cursor.execute(sql, (user_id,))
            
            connection.commit()
            return StandardResponse(
                success=True,
                message=f"愛心提醒已發送給 {total_sent} 位用戶"
            )
    
    except Exception as e:
        print(f"[cron_push_heart_reminder] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()


@router.post("/cron_push_learning_reminder", response_model=StandardResponse)
async def cron_push_learning_reminder():
    """定時發送學習提醒（Cron 任務）"""
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 查找超過 24 小時沒有學習的用戶
            sql = """
            SELECT DISTINCT u.user_id, ut.token, u.name
            FROM users u
            JOIN user_tokens ut ON u.user_id = ut.user_id
            WHERE ut.is_active = 1
            AND u.user_id NOT IN (
                SELECT user_id FROM user_answers 
                WHERE answered_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
            )
            AND u.user_id NOT IN (
                SELECT user_id FROM reminder_history 
                WHERE sent_at > DATE_SUB(NOW(), INTERVAL 12 HOUR)
                AND subject = 'daily_reminder'
            )
            """
            cursor.execute(sql)
            inactive_users = cursor.fetchall()
            
            total_sent = 0
            for record in inactive_users:
                user_id = record['user_id']
                token = record['token']
                name = record['name'] or "同學"
                
                title = "📚 該學習囉！"
                body = f"{name}，今天還沒有學習呢！保持每日學習習慣很重要哦～"
                
                result = send_push_notification(token, title, body)
                if result != "error":
                    total_sent += 1
                    
                    # 記錄提醒歷史
                    sql = """
                    INSERT INTO reminder_history (user_id, subject, chapter, difficulty_level, sent_at, success_count)
                    VALUES (%s, 'daily_reminder', '', '', NOW(), 1)
                    """
                    cursor.execute(sql, (user_id,))
            
            connection.commit()
            return StandardResponse(
                success=True,
                message=f"學習提醒已發送給 {total_sent} 位用戶"
            )
    
    except Exception as e:
        print(f"[cron_push_learning_reminder] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()


@router.post("/validate_tokens", response_model=Dict[str, Any])
async def validate_tokens():
    """驗證並清理無效的推播 token"""
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 獲取所有活躍 token
            sql = "SELECT id, token FROM user_tokens WHERE is_active = 1"
            cursor.execute(sql)
            tokens = cursor.fetchall()
            
            invalid_count = 0
            for token_record in tokens:
                token_id = token_record['id']
                token = token_record['token']
                
                try:
                    # 嘗試發送測試消息來驗證 token
                    message = messaging.Message(
                        data={"test": "true"},
                        token=token,
                    )
                    messaging.send(message, dry_run=True)  # 只驗證不實際發送
                except Exception as e:
                    # Token 無效，標記為不活躍
                    if "not-registered" in str(e) or "invalid-registration-token" in str(e):
                        sql = "UPDATE user_tokens SET is_active = 0 WHERE id = %s"
                        cursor.execute(sql, (token_id,))
                        invalid_count += 1
            
            connection.commit()
            return {
                "total_tokens": len(tokens),
                "invalid_tokens": invalid_count,
                "valid_tokens": len(tokens) - invalid_count
            }
    
    except Exception as e:
        print(f"[validate_tokens] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()


@router.post("/debug_push_notification", response_model=Dict[str, Any])
async def debug_push_notification(request: dict = Body(...)):
    """調試推播通知"""
    try:
        token = request.get('token')
        title = request.get('title', '測試通知')
        body = request.get('body', '這是一個調試通知')
        
        if not token:
            raise HTTPException(status_code=400, detail="Token is required")
        
        result = send_push_notification(token, title, body)
        
        return {
            "success": result != "error",
            "result": result,
            "message": "推播發送成功" if result != "error" else "推播發送失敗"
        }
    
    except Exception as e:
        print(f"[debug_push_notification] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")


@router.get("/notify-daily-report", response_model=Dict[str, Any])
async def notify_daily_report():
    """每日報告通知"""
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            # 獲取今日活躍用戶統計
            sql = """
            SELECT 
                COUNT(DISTINCT user_id) as active_users,
                COUNT(*) as total_questions,
                SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct_answers
            FROM user_answers 
            WHERE DATE(answered_at) = CURDATE()
            """
            cursor.execute(sql)
            daily_stats = cursor.fetchone()
            
            # 可以將這些統計發送給管理員或記錄到日誌
            print(f"📊 今日統計：活躍用戶 {daily_stats['active_users']} 人，"
                  f"答題 {daily_stats['total_questions']} 題，"
                  f"正確 {daily_stats['correct_answers']} 題")
            
            return {
                "date": datetime.now().strftime('%Y-%m-%d'),
                "stats": daily_stats
            }
    
    except Exception as e:
        print(f"[notify_daily_report] Error: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    finally:
        if 'connection' in locals():
            connection.close()
