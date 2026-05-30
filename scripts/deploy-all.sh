#!/bin/bash
# ============================================================
# deploy-all.sh — Deploy Notes App to AWS Academy (bash version)
# Usage: ./deploy-all.sh -k ACCESS_KEY -s SECRET_KEY -t SESSION_TOKEN -p KEY_PATH
# ============================================================
set -e

# ─── Parse args ───
while [[ $# -gt 0 ]]; do
  case "$1" in
    -k) ACCESS_KEY="$2"; shift 2 ;;
    -s) SECRET_KEY="$2"; shift 2 ;;
    -t) SESSION_TOKEN="$2"; shift 2 ;;
    -p) KEY_PATH="$2"; shift 2 ;;
    -r) REGION="$2"; shift 2 ;;
    -d) DB_PASS="$2"; shift 2 ;;
    *)  echo "Usage: $0 -k ACCESS_KEY -s SECRET_KEY -t SESSION_TOKEN -p KEY_PATH [-r REGION] [-d DB_PASSWORD]"
        exit 1 ;;
  esac
done

ACCESS_KEY="${ACCESS_KEY:?Missing -k ACCESS_KEY}"
SECRET_KEY="${SECRET_KEY:?Missing -s SECRET_KEY}"
SESSION_TOKEN="${SESSION_TOKEN:?Missing -t SESSION_TOKEN}"
KEY_PATH="${KEY_PATH:?Missing -p KEY_PATH}"
REGION="${REGION:-us-east-1}"
DB_PASS="${DB_PASS:-Admin12345}"
KEY_NAME="notes-app-key"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="/tmp/notes-app-deploy"
mkdir -p "$TEMP_DIR"

echo ""
echo "============================================"
echo "  Notes App — AWS Deployment"
echo "============================================"

# ─── 0. Configure AWS ───
echo ""
echo "=== [0/8] Configuring AWS CLI ==="
aws configure set aws_access_key_id     "$ACCESS_KEY"
aws configure set aws_secret_access_key "$SECRET_KEY"
aws configure set aws_session_token     "$SESSION_TOKEN"
aws configure set region                "$REGION"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "  ✓ Account: $ACCOUNT_ID / Region: $REGION"

# ─── 1. Import SSH key ───
echo ""
echo "=== [1/8] Importing SSH key pair ==="
ssh-keygen -y -f "$KEY_PATH" > "$TEMP_DIR/key.pub" 2>/dev/null
aws ec2 import-key-pair --key-name "$KEY_NAME" --public-key-material "fileb://$TEMP_DIR/key.pub" 2>/dev/null || true
echo "  ✓ Key pair: $KEY_NAME"

# ─── 2. Discover VPC ───
echo ""
echo "=== [2/8] Discovering VPC & subnets ==="
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
echo "  ✓ VPC: $VPC_ID"
SUBNET_IDS=($(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[*].SubnetId" --output text))
echo "  ✓ Subnets: ${SUBNET_IDS[*]}"

# ─── 3. Security Groups ───
echo ""
echo "=== [3/8] Creating Security Groups ==="
ALB_SG=$(aws ec2 create-security-group --group-name notes-alb-sg --description "ALB SG" --vpc-id "$VPC_ID" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
echo "  ✓ ALB SG: $ALB_SG"

BACK_SG=$(aws ec2 create-security-group --group-name notes-backend-sg --description "Backend SG" --vpc-id "$VPC_ID" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$BACK_SG" --protocol tcp --port 5000 --source-group "$ALB_SG" >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$BACK_SG" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
echo "  ✓ Backend SG: $BACK_SG"

RDS_SG=$(aws ec2 create-security-group --group-name notes-rds-sg --description "RDS SG" --vpc-id "$VPC_ID" --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id "$RDS_SG" --protocol tcp --port 3306 --source-group "$BACK_SG" >/dev/null
echo "  ✓ RDS SG: $RDS_SG"

# ─── 4. RDS ───
echo ""
echo "=== [4/8] Creating RDS MySQL instance ==="
aws rds create-db-instance \
    --db-instance-identifier notes-db \
    --engine mysql --engine-version 8.0 \
    --db-instance-class db.t3.micro \
    --allocated-storage 20 \
    --db-name notesdb \
    --master-username notesuser \
    --master-user-password "$DB_PASS" \
    --vpc-security-group-ids "$RDS_SG" \
    --publicly-accessible >/dev/null

echo "  ⏳ Waiting for RDS to be available (5-8 minutes)..."
aws rds wait db-instance-available --db-instance-identifier notes-db
RDS_EP=$(aws rds describe-db-instances --db-instance-identifier notes-db --query "DBInstances[0].Endpoint.Address" --output text)
echo "  ✓ RDS endpoint: $RDS_EP"
sleep 30

# ─── 5. S3 ───
echo ""
echo "=== [5/8] Creating S3 bucket ==="
BUCKET="notes-app-frontend-$RANDOM"
aws s3 mb "s3://$BUCKET" --region "$REGION"
aws s3 website "s3://$BUCKET" --index-document index.html

cat > "$TEMP_DIR/policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET/*"
  }]
}
EOF
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$TEMP_DIR/policy.json"
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=false,BlockPublicPolicy=false,IgnorePublicAcls=false,RestrictPublicBuckets=false
S3_URL="http://$BUCKET.s3-website-$REGION.amazonaws.com"
echo "  ✓ S3 bucket: $BUCKET"

# ─── 6. EC2 ───
echo ""
echo "=== [6/8] Launching 2 EC2 instances ==="

# Build userdata with embedded app.py
APP_PY=$(cat "$PROJECT_DIR/backend/app.py")

cat > "$TEMP_DIR/userdata.sh" <<EOF
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

cat > app.py << 'PYTHON'
$APP_PY
PYTHON

docker build -t notes-backend:latest .

docker run -d \
  --name notes-backend \
  --restart always \
  -p 5000:5000 \
  -e DB_HOST=$RDS_EP \
  -e DB_USER=notesuser \
  -e DB_PASSWORD=$DB_PASS \
  -e DB_NAME=notesdb \
  -e DB_PORT=3306 \
  notes-backend:latest
EOF

AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query "Parameters[0].Value" --output text)
echo "  ✓ AMI: $AMI_ID"

INSTANCES=()
for i in 1 2; do
    ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t2.micro \
        --key-name "$KEY_NAME" \
        --security-group-ids "$BACK_SG" \
        --subnet-id "${SUBNET_IDS[$((i-1))]}" \
        --user-data "file://$TEMP_DIR/userdata.sh" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=notes-backend-$i}]" \
        --query "Instances[0].InstanceId" \
        --output text)
    INSTANCES+=("$ID")
    echo "  ✓ EC2 #$i: $ID"
done

echo "  ⏳ Waiting for instances to reach running state..."
aws ec2 wait instance-running --instance-ids "${INSTANCES[@]}"
echo "  ✓ Instances running"

# ─── 7. ALB ───
echo ""
echo "=== [7/8] Creating ALB & Target Group ==="

TG_ARN=$(aws elbv2 create-target-group \
    --name notes-backend-tg \
    --protocol HTTP --port 5000 \
    --vpc-id "$VPC_ID" \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)

for ID in "${INSTANCES[@]}"; do
    aws elbv2 register-targets --target-group-arn "$TG_ARN" --targets "Id=$ID,Port=5000"
done

ALB_ARN=$(aws elbv2 create-load-balancer \
    --name notes-alb \
    --subnets "${SUBNET_IDS[0]}" "${SUBNET_IDS[1]}" \
    --security-groups "$ALB_SG" \
    --scheme internet-facing \
    --type application \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query "LoadBalancers[0].DNSName" --output text)
echo "  ✓ ALB DNS: http://$ALB_DNS"

# Listener with default redirect
cat > "$TEMP_DIR/default-action.json" <<EOF
[{
  "Type": "redirect",
  "RedirectConfig": {
    "Protocol": "HTTP",
    "Port": "80",
    "Host": "$BUCKET.s3-website-$REGION.amazonaws.com",
    "Path": "/",
    "StatusCode": "HTTP_301"
  }
}]
EOF

L_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions "file://$TEMP_DIR/default-action.json" \
    --query "Listeners[0].ListenerArn" \
    --output text)

# Rule for /api/* -> backend
cat > "$TEMP_DIR/api-action.json" <<EOF
[{
  "Type": "forward",
  "ForwardConfig": {
    "TargetGroups": [{
      "TargetGroupArn": "$TG_ARN",
      "Weight": 1
    }]
  }
}]
EOF

aws elbv2 create-rule \
    --listener-arn "$L_ARN" \
    --priority 1 \
    --conditions Field=path-pattern,Values=/api/* \
    --actions "file://$TEMP_DIR/api-action.json" >/dev/null

echo "  ✓ ALB listener configured"

# ─── 8. Upload frontend ───
echo ""
echo "=== [8/8] Uploading frontend to S3 ==="

sed -i "s|const API_BASE = '';|const API_BASE = 'http://$ALB_DNS';|g" "$PROJECT_DIR/frontend/script.js"

aws s3 cp "$PROJECT_DIR/frontend/index.html" "s3://$BUCKET/index.html" --content-type "text/html" >/dev/null
aws s3 cp "$PROJECT_DIR/frontend/style.css"  "s3://$BUCKET/style.css"  --content-type "text/css" >/dev/null
aws s3 cp "$PROJECT_DIR/frontend/script.js"  "s3://$BUCKET/script.js"  --content-type "application/javascript" >/dev/null
echo "  ✓ Frontend uploaded"

echo "  ⏳ Waiting for targets to become healthy (~90s)..."
sleep 90

# ─── Summary ───
echo ""
echo "============================================================"
echo "  DEPLOYMENT COMPLETE!"
echo "============================================================"
echo "  Frontend (open this):"
echo "    $S3_URL"
echo ""
echo "  API endpoint:"
echo "    http://$ALB_DNS/api/notes"
echo ""
echo "  RDS endpoint:"
echo "    $RDS_EP"
echo ""
echo "  EC2 instances:"
for ID in "${INSTANCES[@]}"; do
    echo "    $ID"
done
echo "============================================================"
echo "  NOTE: The ALB root redirects to S3."
echo "  JS calls the ALB for /api/* behind the scenes."
echo "============================================================"

rm -rf "$TEMP_DIR"
