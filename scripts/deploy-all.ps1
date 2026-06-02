#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Notes App to AWS Academy — fully automated.
.DESCRIPTION
    Creates all AWS resources: S3, RDS, EC2 (×2), ALB, Security Groups.
    Requires only AWS credentials from the Academy Learner Lab.
.PARAMETER AccessKey
    AWS Access Key ID (from Academy "AWS Details").
.PARAMETER SecretKey
    AWS Secret Access Key.
.PARAMETER SessionToken
    AWS Session Token.
.PARAMETER Region
    AWS region (default: us-east-1).
.PARAMETER DbPassword
    RDS master password (default: Admin12345).
.PARAMETER KeyPairName
    EC2 key pair name (default: notes-app-key).
.PARAMETER KeyPrivatePath
    Path to the .pem private key file.
.EXAMPLE
    .\deploy-all.ps1 -AccessKey "ASIA..." -SecretKey "..." -SessionToken "..." -KeyPrivatePath "C:\keys\lab.pem"
#>

param(
    [Parameter(Mandatory = $true)] [string]$AccessKey,
    [Parameter(Mandatory = $true)] [string]$SecretKey,
    [Parameter(Mandatory = $true)] [string]$SessionToken,
    [Parameter(Mandatory = $false)] [string]$Region = "us-east-1",
    [Parameter(Mandatory = $false)] [string]$DbPassword = "Admin12345",
    [Parameter(Mandatory = $false)] [string]$KeyPairName = "notes-app-key",
    [Parameter(Mandatory = $true)] [string]$KeyPrivatePath
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TempDir = "$env:TEMP\notes-app-deploy"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

function Write-Step($s) { Write-Host "`n=== $s ===" -ForegroundColor Cyan }
function Write-Ok($s)  { Write-Host "  ✓ $s" -ForegroundColor Green }
function Write-Wait($s){ Write-Host "  ⏳ $s ..." -ForegroundColor Yellow }

Write-Step "[0/8] Configuring AWS CLI"
aws configure set aws_access_key_id     $AccessKey
aws configure set aws_secret_access_key $SecretKey
aws configure set aws_session_token     $SessionToken
aws configure set region                $Region
$AccountId = aws sts get-caller-identity --query "Account" --output text
Write-Ok "Account: $AccountId / Region: $Region"

Write-Step "[1/8] Importing SSH key pair"
if (-not (Test-Path $KeyPrivatePath)) { throw "Private key not found: $KeyPrivatePath" }
$pubKey = ssh-keygen -y -f $KeyPrivatePath 2>$null
$pubKeyFile = "$TempDir\key.pub"
Set-Content -Path $pubKeyFile -Value $pubKey -NoNewline
aws ec2 import-key-pair --key-name $KeyPairName --public-key-material "fileb://$pubKeyFile" 2>$null
Write-Ok "Key pair: $KeyPairName"

Write-Step "[2/8] Discovering VPC & subnets"
$VpcId = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text
Write-Ok "VPC: $VpcId"
$SubnetIds = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VpcId" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[*].SubnetId" --output text
$SubnetArr = $SubnetIds -split "`t"
Write-Ok "Subnets: $($SubnetArr -join ', ')"

Write-Step "[3/8] Creating Security Groups"

$AlbSgId = aws ec2 create-security-group --group-name notes-alb-sg --description "ALB SG" --vpc-id $VpcId --query "GroupId" --output text
aws ec2 authorize-security-group-ingress --group-id $AlbSgId --protocol tcp --port 80 --cidr 0.0.0.0/0 | Out-Null
Write-Ok "ALB SG: $AlbSgId"

$BackSgId = aws ec2 create-security-group --group-name notes-backend-sg --description "Backend SG" --vpc-id $VpcId --query "GroupId" --output text
aws ec2 authorize-security-group-ingress --group-id $BackSgId --protocol tcp --port 5000 --source-group $AlbSgId | Out-Null
aws ec2 authorize-security-group-ingress --group-id $BackSgId --protocol tcp --port 22 --cidr 0.0.0.0/0 | Out-Null
Write-Ok "Backend SG: $BackSgId"

$RdsSgId = aws ec2 create-security-group --group-name notes-rds-sg --description "RDS SG" --vpc-id $VpcId --query "GroupId" --output text
aws ec2 authorize-security-group-ingress --group-id $RdsSgId --protocol tcp --port 3306 --source-group $BackSgId | Out-Null
Write-Ok "RDS SG: $RdsSgId"

Write-Step "[4/8] Creating RDS MySQL instance"
aws rds create-db-instance `
    --db-instance-identifier notes-db `
    --engine mysql --engine-version 8.0 `
    --db-instance-class db.t3.micro `
    --allocated-storage 20 `
    --db-name notesdb `
    --master-username notesuser `
    --master-user-password $DbPassword `
    --vpc-security-group-ids $RdsSgId `
    --publicly-accessible | Out-Null

Write-Wait "Waiting for RDS to be available (5-8 minutes)"
aws rds wait db-instance-available --db-instance-identifier notes-db
$RdsEndpoint = aws rds describe-db-instances --db-instance-identifier notes-db --query "DBInstances[0].Endpoint.Address" --output text
Write-Ok "RDS endpoint: $RdsEndpoint"

Start-Sleep -Seconds 30

Write-Step "[5/8] Creating S3 bucket & uploading frontend"
$BucketSuffix = Get-Random -Minimum 10000 -Maximum 99999
$BucketName = "notes-app-frontend-$BucketSuffix"
aws s3 mb "s3://$BucketName" --region $Region
aws s3 website "s3://$BucketName" --index-document index.html

$Policy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BucketName/*"
  }]
}
"@
Set-Content "$TempDir\bucket-policy.json" -Value $Policy
aws s3api put-bucket-policy --bucket $BucketName --policy "file://$TempDir\bucket-policy.json"
aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration BlockPublicAcls=false,BlockPublicPolicy=false,IgnorePublicAcls=false,RestrictPublicBuckets=false

$S3Url = "http://$BucketName.s3-website-$Region.amazonaws.com"
Write-Ok "S3 bucket: $BucketName"

Write-Step "[6/8] Launching 2 EC2 instances"

$AppPyContent = Get-Content "$ProjectRoot\backend\app.py" -Raw

$UserData = @'
#!/bin/bash
set -ex
yum update -y
yum install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /home/ec2-user/notes-app
cd /home/ec2-user/notes-app

cat > Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask==3.0.0 flask-cors==4.0.0 mysql-connector-python==8.3.0
COPY app.py .
CMD ["python", "app.py"]
DOCKERFILE

cat > app.py << 'PYTHON'
'@ + "`n$AppPyContent`n" + @'
PYTHON

docker build -t notes-backend:latest .

docker run -d \
  --name notes-backend \
  --restart always \
  -p 5000:5000 \
  -e DB_HOST='@ + $RdsEndpoint + @' \
  -e DB_USER=notesuser \
  -e DB_PASSWORD='@ + $DbPassword + @' \
  -e DB_NAME=notesdb \
  -e DB_PORT=3306 \
  notes-backend:latest
'@

$UserDataFile = "$TempDir\userdata.sh"
Set-Content -Path $UserDataFile -Value $UserData -NoNewline

$AmiId = aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query "Parameters[0].Value" --output text
Write-Ok "AMI: $AmiId"

$InstanceIds = @()
for ($i = 1; $i -le 2; $i++) {
    $instId = aws ec2 run-instances `
        --image-id $AmiId `
        --instance-type t2.micro `
        --key-name $KeyPairName `
        --security-group-ids $BackSgId `
        --subnet-id $SubnetArr[$i - 1] `
        --user-data "file://$UserDataFile" `
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=notes-backend-$i}]" `
        --query "Instances[0].InstanceId" `
        --output text
    $InstanceIds += $instId
    Write-Ok "EC2 #$i: $instId"
}

Write-Wait "Waiting for instances to reach running state"
aws ec2 wait instance-running --instance-ids $InstanceIds
$InstanceIps = aws ec2 describe-instances --instance-ids $InstanceIds --query "Reservations[].Instances[].PrivateIpAddress" --output text
Write-Ok "Instances running: $InstanceIps"

Write-Step "[7/8] Creating ALB & Target Group"

$TgArn = aws elbv2 create-target-group `
    --name notes-backend-tg `
    --protocol HTTP --port 5000 `
    --vpc-id $VpcId `
    --health-check-path /health `
    --health-check-interval-seconds 30 `
    --health-check-timeout-seconds 5 `
    --healthy-threshold-count 2 `
    --unhealthy-threshold-count 2 `
    --query "TargetGroups[0].TargetGroupArn" `
    --output text

$TargetList = $InstanceIds | ForEach-Object { "Id=$_,Port=5000" }
aws elbv2 register-targets --target-group-arn $TgArn --targets $TargetList

$AlbArn = aws elbv2 create-load-balancer `
    --name notes-alb `
    --subnets $SubnetArr[0..1] `
    --security-groups $AlbSgId `
    --scheme internet-facing `
    --type application `
    --query "LoadBalancers[0].LoadBalancerArn" `
    --output text

$AlbDns = aws elbv2 describe-load-balancers --load-balancer-arns $AlbArn --query "LoadBalancers[0].DNSName" --output text
Write-Ok "ALB DNS: http://$AlbDns"

$RedirectAction = @"
[{
  "Type": "redirect",
  "RedirectConfig": {
    "Protocol": "HTTP",
    "Port": "80",
    "Host": "$BucketName.s3-website-$Region.amazonaws.com",
    "Path": "/",
    "StatusCode": "HTTP_301"
  }
}]
"@
Set-Content "$TempDir\default-action.json" -Value $RedirectAction

$ListenerArn = aws elbv2 create-listener `
    --load-balancer-arn $AlbArn `
    --protocol HTTP --port 80 `
    --default-actions "file://$TempDir\default-action.json" `
    --query "Listeners[0].ListenerArn" `
    --output text

$ApiAction = @"
[{
  "Type": "forward",
  "ForwardConfig": {
    "TargetGroups": [{
      "TargetGroupArn": "$TgArn",
      "Weight": 1
    }]
  }
}]
"@
Set-Content "$TempDir\api-action.json" -Value $ApiAction

aws elbv2 create-rule `
    --listener-arn $ListenerArn `
    --priority 1 `
    --conditions Field=path-pattern,Values=/api/* `
    --actions "file://$TempDir\api-action.json" | Out-Null

Write-Ok "ALB listener configured"

Write-Step "[8/8] Updating frontend & uploading to S3"

$ScriptJsPath = "$ProjectRoot\frontend\script.js"
(Get-Content $ScriptJsPath) -replace "const API_BASE = '';", "const API_BASE = 'http://$AlbDns';" | Set-Content $ScriptJsPath

aws s3 cp "$ProjectRoot\frontend\index.html" "s3://$BucketName/index.html" --content-type "text/html" | Out-Null
aws s3 cp "$ProjectRoot\frontend\style.css"  "s3://$BucketName/style.css"  --content-type "text/css" | Out-Null
aws s3 cp "$ProjectRoot\frontend\script.js"  "s3://$BucketName/script.js"  --content-type "application/javascript" | Out-Null
Write-Ok "Frontend uploaded to S3"

Write-Wait "Waiting for targets to become healthy"
Start-Sleep -Seconds 90

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Frontend (open this):" -ForegroundColor White
Write-Host "    $S3Url" -ForegroundColor Yellow
Write-Host ""
Write-Host "  API endpoint:" -ForegroundColor White
Write-Host "    http://$AlbDns/api/notes" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Health check:" -ForegroundColor White
Write-Host "    http://$AlbDns/health" -ForegroundColor Yellow
Write-Host ""
Write-Host "  RDS endpoint:" -ForegroundColor White
Write-Host "    $RdsEndpoint" -ForegroundColor Yellow
Write-Host ""
Write-Host "  EC2 instances:" -ForegroundColor White
$InstanceIds | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  NOTE: The ALB root redirects to S3." -ForegroundColor Yellow
Write-Host "  JS calls the ALB for /api/* behind the scenes." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
