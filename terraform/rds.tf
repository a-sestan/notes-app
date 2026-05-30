# DB subnet group (private subnets)
resource "aws_db_subnet_group" "notes" {
  name       = "notes-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "notes-db-subnet-group" }
}

resource "aws_db_instance" "notes" {
  identifier        = "notes-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_subnet_group_name   = aws_db_subnet_group.notes.name
  publicly_accessible    = false
  skip_final_snapshot    = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
}
