resource "aws_s3_bucket" "frontend" {
  bucket = "notes-app-frontend-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "../frontend/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "style_css" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "style.css"
  source       = "../frontend/style.css"
  content_type = "text/css"
}

resource "aws_s3_object" "script_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "script.js"
  source       = "../frontend/script.js"
  content_type = "application/javascript"
}

resource "random_id" "suffix" {
  byte_length = 4
}

output "s3_bucket_url" {
  value = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "s3_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}
