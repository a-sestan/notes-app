output "alb_dns" {
  description = "ALB DNS name (API endpoint)"
  value       = aws_lb.main.dns_name
}

output "s3_bucket_url" {
  description = "S3 static website URL (frontend)"
  value       = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.frontend.bucket
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.notes.endpoint
}

output "frontend_url" {
  description = "Frontend URL (open this in browser)"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "api_url" {
  description = "API base URL"
  value       = "http://${aws_lb.main.dns_name}/api"
}
