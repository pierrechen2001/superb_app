# 使用輕量級 Python 映像
FROM python:3.10-slim

# 設定工作目錄
WORKDIR /app

# 複製所有專案檔案到容器內
COPY . .

# 安裝 pip 套件（需要你等一下有 requirements.txt）
RUN pip install --no-cache-dir -r requirements.txt

# 建立 Qpics 資料夾（避免容器啟動出錯）
RUN mkdir -p /app/Qpics

# 設定容器執行時的 Port
EXPOSE 8080

# 使用 Uvicorn 啟動 FastAPI 應用
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]