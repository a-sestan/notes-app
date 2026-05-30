resource "aws_db_instance" "notes" {
  identifier        = "notes-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "notesdb"
  username = "notesuser"
  password = var.db_password

  publicly_accessible = false
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.rds.id]
}

output "rds_endpoint" {
  value = aws_db_instance.notes.endpoint
}
