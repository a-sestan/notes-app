param(
    [Parameter(Mandatory=$true)]
    [string]$DbPassword,
    [Parameter(Mandatory=$true)]
    [string]$KeyPairName,
    [Parameter(Mandatory=$true)]
    [string]$VpcId,
    [Parameter(Mandatory=$true)]
    [string[]]$PublicSubnetIds,
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Deploy Notes App to AWS (AWS CLI)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

Write-Host "`n[1/7] Creating S3 bucket for frontend..." -ForegroundColor Yellow
$BucketName = "notes-app-frontend-$(Get-Random -Minimum 1000 -Maximum 9999)"
aws s3 mb "s3://$BucketName" --region $Region
aws s3 website "s3://$BucketName" --index-document index.html --region $Region

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
$Policy | aws s3api put-bucket-policy --bucket $BucketName --policy file:///dev/stdin
aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration BlockPublicAcls=false,BlockPublicPolicy=false,IgnorePublicAcls=false,RestrictPublicBuckets=false

Write-Host "  S3 bucket created: $BucketName" -ForegroundColor Green

Write-Host "`n[2/7] Creating RDS MySQL instance..." -ForegroundColor Yellow
$RdsEndpoint = aws rds create-db-instance `
    --db-instance-identifier notes-db `
    --engine mysql `
    --engine-version 8.0 `
    --db-instance-class db.t3.micro `
    --allocated-storage 20 `
    --db-name notesdb `
    --master-username notesuser `
    --master-user-password $DbPassword `
    --vpc-security-group-ids <PLACEHOLDER_SG> `
    --publicly-accessible `
    --query "DBInstance.Endpoint.Address" `
    --output text `
    --region $Region

Write-Host "  Waiting for RDS to be available (this takes ~5-10 min)..." -ForegroundColor Yellow
aws rds wait db-instance-available --db-instance-identifier notes-db --region $Region
$RdsEndpoint = aws rds describe-db-instances --db-instance-identifier notes-db --query "DBInstance.Endpoint.Address" --output text --region $Region
Write-Host "  RDS endpoint: $RdsEndpoint" -ForegroundColor Green

Write-Host "`n[3/7] Creating Security Groups..." -ForegroundColor Yellow

$AlbSgId = aws ec2 create-security-group --group-name notes-alb-sg --description "ALB SG" --vpc-id $VpcId --query "GroupId" --output text --region $Region
aws ec2 authorize-security-group-ingress --group-id $AlbSgId --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $Region
Write-Host "  ALB SG: $AlbSgId" -ForegroundColor Green

$BackendSgId = aws ec2 create-security-group --group-name notes-backend-sg --description "Backend SG" --vpc-id $VpcId --query "GroupId" --output text --region $Region
aws ec2 authorize-security-group-ingress --group-id $BackendSgId --protocol tcp --port 5000 --source-group $AlbSgId --region $Region
Write-Host "  Backend SG: $BackendSgId" -ForegroundColor Green

$RdsSgId = aws ec2 create-security-group --group-name notes-rds-sg --description "RDS SG" --vpc-id $VpcId --query "GroupId" --output text --region $Region
aws ec2 authorize-security-group-ingress --group-id $RdsSgId --protocol tcp --port 3306 --source-group $BackendSgId --region $Region
Write-Host "  RDS SG: $RdsSgId" -ForegroundColor Green

Write-Host "`n[4/7] Building and pushing backend Docker image to ECR..." -ForegroundColor Yellow

aws ecr create-repository --repository-name notes-backend --region $Region --query "repository.repositoryUri" --output text
$AccountId = aws sts get-caller-identity --query "Account" --output text
$EcrUri = "$AccountId.dkr.ecr.$Region.amazonaws.com/notes-backend"

aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $EcrUri

docker build -t notes-backend "$ProjectRoot\backend"
docker tag notes-backend:latest "$EcrUri`:latest"
docker push "$EcrUri`:latest"

Write-Host "  Image pushed to: $EcrUri" -ForegroundColor Green

Write-Host "`n[5/7] Launching 2 EC2 instances..." -ForegroundColor Yellow

$UserData = @"
#!/bin/bash
set -ex
dnf update -y
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $EcrUri
docker pull $EcrUri:latest

mkdir -p /home/ec2-user/notes-app
cat > /home/ec2-user/notes-app/docker-compose.yml << 'COMPOSE'
services:
  backend:
    image: $EcrUri:latest
    ports:
      - "5000:5000"
    environment:
      DB_HOST: $RdsEndpoint
      DB_USER: notesuser
      DB_PASSWORD: $DbPassword
      DB_NAME: notesdb
      DB_PORT: "3306"
    restart: always
COMPOSE

cd /home/ec2-user/notes-app
docker compose up -d
"@

$UserDataBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($UserData))

$AmiId = aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query "Parameters[0].Value" --output text --region $Region

$InstanceIds = @()
for ($i = 1; $i -le 2; $i++) {
    $InstId = aws ec2 run-instances `
        --image-id $AmiId `
        --instance-type t2.micro `
        --key-name $KeyPairName `
        --security-group-ids $BackendSgId `
        --subnet-id $PublicSubnetIds[0] `
        --user-data (ConvertTo-Json -Compress @{ "Fn::Base64" = $UserDataBase64 }) `
        --iam-instance-profile-name "EC2-S3-Access" `
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=notes-backend-$i}]" `
        --query "Instances[0].InstanceId" `
        --output text `
        --region $Region
    
    $InstanceIds += $InstId
    Write-Host "  EC2 instance $i created: $InstId" -ForegroundColor Green
}

Write-Host "  Waiting for EC2 instances to be running..." -ForegroundColor Yellow
aws ec2 wait instance-running --instance-ids $InstanceIds --region $Region
Write-Host "  EC2 instances are running!" -ForegroundColor Green

Write-Host "`n[6/7] Creating ALB and Target Group..." -ForegroundColor Yellow

$TargetGroupArn = aws elbv2 create-target-group `
    --name notes-backend-tg `
    --protocol HTTP `
    --port 5000 `
    --vpc-id $VpcId `
    --health-check-path /health `
    --health-check-interval-seconds 30 `
    --health-check-timeout-seconds 5 `
    --healthy-threshold-count 2 `
    --unhealthy-threshold-count 2 `
    --query "TargetGroups[0].TargetGroupArn" `
    --output text `
    --region $Region

$Targets = $InstanceIds | ForEach-Object { @{Id=$_} }
aws elbv2 register-targets --target-group-arn $TargetGroupArn --targets ($InstanceIds | ForEach-Object { "Id=$_" }) --region $Region

$AlbArn = aws elbv2 create-load-balancer `
    --name notes-alb `
    --subnets $PublicSubnetIds `
    --security-groups $AlbSgId `
    --scheme internet-facing `
    --type application `
    --query "LoadBalancers[0].LoadBalancerArn" `
    --output text `
    --region $Region

$AlbDns = aws elbv2 describe-load-balancers --load-balancer-arns $AlbArn --query "LoadBalancers[0].DNSName" --output text --region $Region

aws elbv2 create-listener `
    --load-balancer-arn $AlbArn `
    --protocol HTTP `
    --port 80 `
    --default-actions Type=forward,TargetGroupArn=$TargetGroupArn `
    --region $Region

Write-Host "  ALB DNS: http://$AlbDns" -ForegroundColor Green

Write-Host "`n[7/7] Uploading frontend to S3..." -ForegroundColor Yellow

$ScriptJsPath = "$ProjectRoot\frontend\script.js"
(Get-Content $ScriptJsPath) -replace "const API_BASE = '';", "const API_BASE = 'http://$AlbDns';" | Set-Content $ScriptJsPath

aws s3 cp "$ProjectRoot\frontend\index.html" "s3://$BucketName/index.html" --content-type "text/html" --region $Region
aws s3 cp "$ProjectRoot\frontend\style.css"  "s3://$BucketName/style.css"  --content-type "text/css" --region $Region
aws s3 cp "$ProjectRoot\frontend\script.js"  "s3://$BucketName/script.js"  --content-type "application/javascript" --region $Region

$WebsiteUrl = "http://$BucketName.s3-website-$Region.amazonaws.com"

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  S3 Website URL:   $WebsiteUrl" -ForegroundColor White
Write-Host "  ALB DNS (API):    http://$AlbDns" -ForegroundColor White
Write-Host "  RDS Endpoint:     $RdsEndpoint" -ForegroundColor White
Write-Host "  EC2 Instances:    $InstanceIds" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  NOTE: Open the S3 Website URL for the app." -ForegroundColor Yellow
Write-Host "  The JS calls the ALB for /api/* routes." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
