#!/bin/bash
set -ex

# Install Docker
dnf update -y
dnf install -y docker

# Install docker-compose plugin
dnf install -y docker-compose-plugin

# Start Docker
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Create app directory
mkdir -p /home/ec2-user/notes-app

# Write docker-compose file
cat > /home/ec2-user/notes-app/docker-compose.yml << 'EOF'
services:
  backend:
    image: notes-backend:latest
    ports:
      - "5000:5000"
    environment:
      DB_HOST: ${db_host}
      DB_USER: ${db_user}
      DB_PASSWORD: ${db_password}
      DB_NAME: ${db_name}
      DB_PORT: ${db_port}
    restart: always
EOF

# Build backend Docker image
cd /home/ec2-user/notes-app

cat > Dockerfile << 'DOCKER'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
DOCKER

cat > requirements.txt << 'REQ'
flask==3.0.0
flask-cors==4.0.0
mysql-connector-python==8.3.0
REQ

cat > app.py << 'PY'
from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
import os
import time

app = Flask(__name__)
CORS(app)

def get_db():
    return mysql.connector.connect(
        host=os.environ['DB_HOST'],
        user=os.environ['DB_USER'],
        password=os.environ['DB_PASSWORD'],
        database=os.environ['DB_NAME'],
        port=os.environ['DB_PORT']
    )

def init_db():
    for _ in range(10):
        try:
            conn = get_db()
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS notes (
                    id         INT AUTO_INCREMENT PRIMARY KEY,
                    title      VARCHAR(255) NOT NULL,
                    content    TEXT,
                    tag        ENUM('posao', 'privatno', 'ideje', 'todo') DEFAULT NULL,
                    color      TINYINT DEFAULT 0,
                    pinned     TINYINT(1) DEFAULT 0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            conn.commit()
            conn.close()
            print("Baza inicijalizovana!")
            return
        except Exception as e:
            print(f"Cekam bazu... ({e})")
            time.sleep(3)

@app.route('/api/notes', methods=['GET'])
def get_notes():
    conn = get_db()
    cursor = conn.cursor(dictionary=True)
    cursor.execute('SELECT * FROM notes ORDER BY pinned DESC, created_at DESC')
    notes = cursor.fetchall()
    conn.close()
    for n in notes:
        n['created_at'] = str(n['created_at'])
        n['pinned'] = bool(n['pinned'])
    return jsonify(notes)

@app.route('/api/notes', methods=['POST'])
def add_note():
    data = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        'INSERT INTO notes (title, content, tag, color, pinned) VALUES (%s, %s, %s, %s, %s)',
        (data['title'], data.get('content', ''), data.get('tag', None), data.get('color', 0), data.get('pinned', False))
    )
    conn.commit()
    new_id = cursor.lastrowid
    conn.close()
    return jsonify({'status': 'ok', 'id': new_id}), 201

@app.route('/api/notes/<int:note_id>', methods=['PUT'])
def update_note(note_id):
    data = request.json
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute(
        'UPDATE notes SET title=%s, content=%s, tag=%s, color=%s, pinned=%s WHERE id=%s',
        (data['title'], data.get('content', ''), data.get('tag', None), data.get('color', 0), data.get('pinned', False), note_id)
    )
    conn.commit()
    conn.close()
    return jsonify({'status': 'ok'})

@app.route('/api/notes/<int:note_id>', methods=['DELETE'])
def delete_note(note_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM notes WHERE id=%s', (note_id,))
    conn.commit()
    conn.close()
    return jsonify({'status': 'ok'})

@app.route('/api/notes/<int:note_id>/pin', methods=['PATCH'])
def toggle_pin(note_id):
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE notes SET pinned = NOT pinned WHERE id=%s', (note_id,))
    conn.commit()
    conn.close()
    return jsonify({'status': 'ok'})

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
PY

# Build and run
docker build -t notes-backend:latest .
docker compose up -d
