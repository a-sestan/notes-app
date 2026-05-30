variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "db_username" {
  description = "RDS MySQL username"
  type        = string
  default     = "notesuser"
}

variable "db_password" {
  description = "RDS MySQL password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "RDS MySQL database name"
  type        = string
  default     = "notesdb"
}

variable "key_name" {
  description = "EC2 key pair name (must exist in the AWS account)"
  type        = string
}
