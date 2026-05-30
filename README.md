# Notes App — AWS Deployment Guide

Full-stack Flask + MySQL notes application, deployed on AWS with Docker, 
Load Balancer, RDS, and S3.

## Architecture

```
Internet
  │
  ├── http://<s3-bucket>.s3-website-us-east-1.amazonaws.com   ← Frontend (open this)
  │     └── S3 static website (index.html, style.css, script.js)
  │
  └── http://<alb-dns>                                         ← API endpoint
        └── ALB
              ├── Rule: /api/*  →  TargetGroup (ports 5000)
              │                     ├── EC2 #1 → Docker: Flask backend
              │                     └── EC2 #2 → Docker: Flask backend
              │                                    │
              └── Default: redirect to S3 website    └── RDS MySQL
```

## Requirements

| # | Requirement | Implementation |
|---|-------------|----------------|
| 1 | **Frontend + Backend as Docker containers on EC2** | Nginx (frontend) served from S3; Flask (backend) as Docker on each EC2 |
| 2 | **Backend on ≥2 EC2 instances** | 2 × `t2.micro` with Amazon Linux 2 |
| 3 | **Amazon RDS database** | MySQL 8.0 on `db.t3.micro` |
| 4 | **S3 Storage** | Frontend static hosting (HTML/CSS/JS) |
| 5 | **Application Load Balancer** | ALB with path-based routing: `/api/*` → backend, default → S3 |
| 6 | **Security Groups** | 3 SGs: ALB (80), Backend (5000 from ALB + 22 SSH), RDS (3306 from Backend) |
| 7 | **Public URL** | S3 website URL and ALB DNS name are publicly accessible |

---

## Automated Deployment (Recommended)

### Option A: PowerShell (Windows)

```powershell
cd scripts

.\deploy-all.ps1 `
    -AccessKey "ASIAVRZLLA3A..." `
    -SecretKey "CNYSalZn..." `
    -SessionToken "IQoJb3JpZ2lu..." `
    -KeyPrivatePath "C:\path\to\lab-key.pem"
```

Optional parameters:

| Param | Default | Description |
|-------|---------|-------------|
| `-Region` | `us-east-1` | AWS region |
| `-DbPassword` | `Admin12345` | RDS MySQL password |
| `-KeyPairName` | `notes-app-key` | EC2 key pair name |

### Option B: Bash (Linux / macOS / WSL)

```bash
cd scripts
chmod +x deploy-all.sh

./deploy-all.sh \
    -k "ASIAVRZLLA3A..." \
    -s "CNYSalZn..." \
    -t "IQoJb3JpZ2lu..." \
    -p "/path/to/lab-key.pem"
```

Optional flags: `-r us-east-1 -d Admin12345`

### What the script does

The script provisions all 8 steps automatically:

1. Configures AWS CLI with provided credentials
2. Imports your SSH key pair to AWS
3. Discovers default VPC and public subnets
4. Creates 3 Security Groups (ALB, Backend, RDS)
5. Creates RDS MySQL instance (waits for it)
6. Creates S3 bucket, sets public policy, enables static website
7. Launches 2 EC2 instances with userdata (installs Docker, builds Flask image, runs container)
8. Creates ALB + Target Group + Listener with path-based routing
9. Updates `script.js` with ALB DNS and uploads to S3

**Total time:** ~15–20 minutes (most of it waiting for RDS).

---

## Manual Deployment Step-by-Step

### Prerequisites

- AWS CLI installed and configured
- AWS Academy Learner Lab session active (credentials from "AWS Details")
- SSH key pair downloaded from the lab (typically `labsuser.pem`)
- Docker installed locally (optional, for testing)

### Step 1: Configure AWS CLI

```bash
aws configure set aws_access_key_id     "ASIAVRZLLA3A..."
aws configure set aws_secret_access_key "CNYSalZn..."
aws configure set aws_session_token     "IQoJb3JpZ2lu..."
aws configure set region                us-east-1

# Verify
aws sts get-caller-identity
```

### Step 2: Import SSH Key

```bash
# Extract public key from private key
ssh-keygen -y -f labsuser.pem > labsuser.pub

# Import to AWS
aws ec2 import-key-pair \
    --key-name notes-app-key \
    --public-key-material "fileb://labsuser.pub"
```

### Step 3: Find VPC and Subnets

```bash
# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)
echo "VPC: $VPC_ID"

# Get public subnets
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
    --query "Subnets[*].SubnetId" \
    --output text
```

### Step 4: Create Security Groups

```bash
# ALB SG — allows HTTP from anywhere
ALB_SG=$(aws ec2 create-security-group \
    --group-name notes-alb-sg \
    --description "ALB SG" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress \
    --group-id "$ALB_SG" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0

# Backend SG — allows traffic from ALB (port 5000) + SSH (port 22)
BACK_SG=$(aws ec2 create-security-group \
    --group-name notes-backend-sg \
    --description "Backend SG" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress \
    --group-id "$BACK_SG" \
    --protocol tcp --port 5000 --source-group "$ALB_SG"
aws ec2 authorize-security-group-ingress \
    --group-id "$BACK_SG" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0

# RDS SG — allows MySQL from Backend SG
RDS_SG=$(aws ec2 create-security-group \
    --group-name notes-rds-sg \
    --description "RDS SG" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress \
    --group-id "$RDS_SG" \
    --protocol tcp --port 3306 --source-group "$BACK_SG"
```

### Step 5: Create RDS MySQL

```bash
aws rds create-db-instance \
    --db-instance-identifier notes-db \
    --engine mysql --engine-version 8.0 \
    --db-instance-class db.t3.micro \
    --allocated-storage 20 \
    --db-name notesdb \
    --master-username notesuser \
    --master-user-password "YourPassword123" \
    --vpc-security-group-ids "$RDS_SG" \
    --publicly-accessible

# Wait (takes 5-8 minutes)
aws rds wait db-instance-available --db-instance-identifier notes-db

# Get endpoint
RDS_EP=$(aws rds describe-db-instances \
    --db-instance-identifier notes-db \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)
echo "RDS: $RDS_EP"

# Wait an extra 30s for the DB to accept connections
sleep 30
```

### Step 6: Create S3 Bucket

```bash
BUCKET="notes-app-frontend-$(shuf -i 10000-99999 -n 1)"

# Create bucket and enable static website
aws s3 mb "s3://$BUCKET"
aws s3 website "s3://$BUCKET" --index-document index.html

# Set public read policy
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::'"$BUCKET"'/*"
  }]
}'

aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=false,BlockPublicPolicy=false,IgnorePublicAcls=false,RestrictPublicBuckets=false
```

### Step 7: Launch EC2 Instances (×2)

Create a file called `userdata.sh`:

```bash
#!/bin/bash
set -ex
yum update -y
yum install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /home/ec2-user/notes-app
cd /home/ec2-user/notes-app

cat > Dockerfile << 'DOCKER'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.0 flask-cors==4.0.0 mysql-connector-python==8.3.0
COPY app.py .
CMD ["python", "app.py"]
DOCKER

# app.py content — copy from backend/app.py in the project
cat > app.py << 'PYTHON'
from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
import os, time

app = Flask(__name__)
CORS(app)

def get_db():
    return mysql.connector.connect(
        host=os.environ['DB_HOST'], user=os.environ['DB_USER'],
        password=os.environ['DB_PASSWORD'], database=os.environ['DB_NAME'],
        port=os.environ['DB_PORT'])

def init_db():
    for _ in range(10):
        try:
            conn = get_db(); cursor = conn.cursor()
            cursor.execute('''CREATE TABLE IF NOT EXISTS notes (
                id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(255) NOT NULL,
                content TEXT, tag ENUM('posao','privatno','ideje','todo') DEFAULT NULL,
                color TINYINT DEFAULT 0, pinned TINYINT(1) DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')
            conn.commit(); conn.close(); print("DB initialized!"); return
        except Exception as e: print(f"Waiting for DB... ({e})"); time.sleep(3)

@app.route('/api/notes', methods=['GET'])
def get_notes():
    conn = get_db(); cursor = conn.cursor(dictionary=True)
    cursor.execute('SELECT * FROM notes ORDER BY pinned DESC, created_at DESC')
    notes = cursor.fetchall(); conn.close()
    for n in notes:
        n['created_at'] = str(n['created_at']); n['pinned'] = bool(n['pinned'])
    return jsonify(notes)

@app.route('/api/notes', methods=['POST'])
def add_note():
    data = request.json; conn = get_db(); cursor = conn.cursor()
    cursor.execute('INSERT INTO notes (title,content,tag,color,pinned) VALUES (%s,%s,%s,%s,%s)',
        (data['title'], data.get('content',''), data.get('tag',None),
         data.get('color',0), data.get('pinned',False)))
    conn.commit(); new_id = cursor.lastrowid; conn.close()
    return jsonify({'status':'ok','id':new_id}), 201

@app.route('/api/notes/<int:note_id>', methods=['PUT'])
def update_note(note_id):
    data = request.json; conn = get_db(); cursor = conn.cursor()
    cursor.execute('UPDATE notes SET title=%s,content=%s,tag=%s,color=%s,pinned=%s WHERE id=%s',
        (data['title'],data.get('content',''),data.get('tag',None),
         data.get('color',0),data.get('pinned',False),note_id))
    conn.commit(); conn.close(); return jsonify({'status':'ok'})

@app.route('/api/notes/<int:note_id>', methods=['DELETE'])
def delete_note(note_id):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute('DELETE FROM notes WHERE id=%s',(note_id,))
    conn.commit(); conn.close(); return jsonify({'status':'ok'})

@app.route('/api/notes/<int:note_id>/pin', methods=['PATCH'])
def toggle_pin(note_id):
    conn = get_db(); cursor = conn.cursor()
    cursor.execute('UPDATE notes SET pinned = NOT pinned WHERE id=%s',(note_id,))
    conn.commit(); conn.close(); return jsonify({'status':'ok'})

@app.route('/health')
def health(): return jsonify({'status':'ok'})

if __name__ == '__main__':
    init_db(); app.run(host='0.0.0.0', port=5000)
PYTHON

docker build -t notes-backend:latest .

docker run -d --name notes-backend --restart always -p 5000:5000 \
    -e DB_HOST="$RDS_EP" \
    -e DB_USER=notesuser \
    -e DB_PASSWORD=YourPassword123 \
    -e DB_NAME=notesdb \
    -e DB_PORT=3306 \
    notes-backend:latest
```

Replace `YourPassword123` and `$RDS_EP` with your values, then launch:

```bash
# Get Amazon Linux 2 AMI
AMI=$(aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
    --query "Parameters[0].Value" --output text)

# Launch 2 instances in different subnets
INSTANCE_1=$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type t2.micro \
    --key-name notes-app-key \
    --security-group-ids "$BACK_SG" \
    --subnet-id "$SUBNET_1" \
    --user-data "file://userdata.sh" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=notes-backend-1}]' \
    --query "Instances[0].InstanceId" --output text)

INSTANCE_2=$(aws ec2 run-instances \
    --image-id "$AMI" --instance-type t2.micro \
    --key-name notes-app-key \
    --security-group-ids "$BACK_SG" \
    --subnet-id "$SUBNET_2" \
    --user-data "file://userdata.sh" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=notes-backend-2}]' \
    --query "Instances[0].InstanceId" --output text)

# Wait for them to be running
aws ec2 wait instance-running --instance-ids "$INSTANCE_1" "$INSTANCE_2"
```

### Step 8: Create ALB + Target Group

```bash
# Target group
TG_ARN=$(aws elbv2 create-target-group \
    --name notes-backend-tg \
    --protocol HTTP --port 5000 \
    --vpc-id "$VPC_ID" \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --query "TargetGroups[0].TargetGroupArn" --output text)

# Register both instances
aws elbv2 register-targets --target-group-arn "$TG_ARN" \
    --targets "Id=$INSTANCE_1,Port=5000" "Id=$INSTANCE_2,Port=5000"

# ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name notes-alb \
    --subnets "$SUBNET_1" "$SUBNET_2" \
    --security-groups "$ALB_SG" \
    --scheme internet-facing --type application \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query "LoadBalancers[0].DNSName" --output text)
echo "ALB DNS: $ALB_DNS"

# Listener: default → redirect to S3, /api/* → backend
LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions "Type=redirect,RedirectConfig={Protocol=HTTP,Port=80,Host=$BUCKET.s3-website-us-east-1.amazonaws.com,Path=/,StatusCode=HTTP_301}" \
    --query "Listeners[0].ListenerArn" --output text)

aws elbv2 create-rule \
    --listener-arn "$LISTENER_ARN" --priority 1 \
    --conditions Field=path-pattern,Values=/api/* \
    --actions "Type=forward,ForwardConfig={TargetGroups=[{TargetGroupArn=$TG_ARN,Weight=1}]}"
```

### Step 9: Upload Frontend to S3

```bash
# Update API_BASE in script.js
sed -i "s|const API_BASE = '';|const API_BASE = 'http://$ALB_DNS';|g" frontend/script.js

# Upload
aws s3 cp frontend/index.html "s3://$BUCKET/index.html" --content-type "text/html"
aws s3 cp frontend/style.css  "s3://$BUCKET/style.css"  --content-type "text/css"
aws s3 cp frontend/script.js  "s3://$BUCKET/script.js"  --content-type "application/javascript"
```

### Step 10: Test

After ~2 minutes for the EC2 userdata to finish:

```bash
# Test health
curl -s "http://$ALB_DNS/health"

# Test API
curl -s "http://$ALB_DNS/api/notes"

# Create a note
curl -s -X POST "http://$ALB_DNS/api/notes" \
    -H "Content-Type: application/json" \
    -d '{"title":"Hello","content":"From AWS!","color":0,"pinned":false}'

# Open the app in your browser:
echo "http://$BUCKET.s3-website-us-east-1.amazonaws.com"
```

---

## Obtaining AWS Academy Credentials

1. Log in at [awsacademy.com](https://awsacademy.com)
2. Open your course → **Modules** → **Learner Lab**
3. Click **Start Lab** (wait for green circle)
4. Click **AWS Details** (dropdown next to the timer)
5. Copy the 4 values:
   - **AWS Access Key ID**
   - **AWS Secret Access Key**
   - **AWS Session Token**
   - **Region** (usually `us-east-1`)
6. Use these values with the deployment scripts above

**⚠ The session expires when you click End Lab. Re-copy credentials each time.**

---

## Cleanup

Delete all resources to avoid charges:

```bash
# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"

# Delete target group
aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

# Terminate EC2 instances
aws ec2 terminate-instances --instance-ids "$INSTANCE_1" "$INSTANCE_2"

# Delete RDS
aws rds delete-db-instance --db-instance-identifier notes-db --skip-final-snapshot

# Delete S3 bucket (must be empty first)
aws s3 rm "s3://$BUCKET" --recursive
aws s3 rb "s3://$BUCKET"

# Delete Security Groups
aws ec2 delete-security-group --group-id "$RDS_SG"
aws ec2 delete-security-group --group-id "$BACK_SG"
aws ec2 delete-security-group --group-id "$ALB_SG"

# Delete key pair
aws ec2 delete-key-pair --key-name notes-app-key
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `RunInstances` denied | Wrong AMI (AL2023 not supported) | Use Amazon Linux 2 (`/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2`) |
| ALB returns 404 on root | ALB default action not set | Ensure default action redirects to S3; `/api/*` rule forwards to TG |
| API returns 404 on `/api/notes` | Flask routes missing `/api` prefix | Check `backend/app.py` routes start with `/api/` |
| CORS errors in browser | Missing `Access-Control-Allow-Origin` | Flask-CORS should handle this; check `CORS(app)` is present |
| Targets unhealthy | Container not running or wrong health check path | SSH into EC2 and check `docker ps`; verify `/health` returns 200 |
| Session expired | Lab ended | Restart lab in AWS Academy and re-copy credentials |
| RDS not accepting connections | Still provisioning | Wait longer; check `aws rds describe-db-instances` status |
| `docker build` fails on EC2 | Out of disk space or network issue | Use larger instance type or check security group egress rules |

## Project Structure

```
notes-app/
├── backend/
│   ├── app.py              ← Flask application
│   ├── Dockerfile          ← Docker image for backend
│   └── requirements.txt    ← Python dependencies
├── frontend/
│   ├── index.html          ← App HTML
│   ├── style.css           ← Styles
│   ├── script.js           ← JavaScript (API calls)
│   ├── Dockerfile          ← Nginx container for local dev
│   └── nginx.conf          ← Nginx config with /api/ proxy
├── scripts/
│   ├── deploy-all.ps1      ← Automated deployment (Windows)
│   ├── deploy-all.sh       ← Automated deployment (Unix)
│   └── upload-frontend.ps1 ← Upload frontend to S3 only
├── terraform/              ← Infrastructure as Code (alternative)
│   ├── main.tf
│   ├── provider.tf
│   ├── s3.tf
│   ├── rds.tf
│   ├── ec2_alb.tf
│   ├── security_groups.tf
│   ├── variables.tf
│   ├── userdata.sh
│   └── terraform.tfvars.example
├── docker-compose.yml       ← Local development stack
├── docker-compose-aws.yml   ← EC2 docker-compose (RDS vars)
└── database.sql             ← Schema definition
```
