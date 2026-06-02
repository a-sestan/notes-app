param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName,
    [Parameter(Mandatory=$false)]
    [string]$AlbDns
)

# Update API_BASE in script.js if ALB DNS is provided
if ($AlbDns) {
    $scriptPath = Join-Path $PSScriptRoot "frontend\script.js"
    (Get-Content $scriptPath) -replace "const API_BASE = '';", "const API_BASE = 'http://$AlbDns';" | Set-Content $scriptPath
    Write-Host "API_BASE set to http://$AlbDns"
}

# Upload frontend files to S3
Write-Host "Uploading frontend files to s3://$BucketName ..."
aws s3 cp "$PSScriptRoot\frontend\index.html" "s3://$BucketName/index.html" --content-type "text/html"
aws s3 cp "$PSScriptRoot\frontend\style.css"  "s3://$BucketName/style.css"  --content-type "text/css"
aws s3 cp "$PSScriptRoot\frontend\script.js"  "s3://$BucketName/script.js"  --content-type "application/javascript"

# Enable static website hosting
aws s3 website "s3://$BucketName" --index-document index.html

Write-Host "Done! Website URL: http://$BucketName.s3-website-us-east-1.amazonaws.com"
