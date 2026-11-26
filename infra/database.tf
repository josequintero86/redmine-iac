resource "random_password" "db" {
  length  = 32
  special = false
}
resource "random_password" "secret_key_base" {
  length  = 64
  special = false
}
resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "redmine/${var.environment}/db-password-"
}
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}
resource "aws_secretsmanager_secret" "secret_key_base" {
  name_prefix = "redmine/${var.environment}/secret-key-base-"
}
resource "aws_secretsmanager_secret_version" "secret_key_base" {
  secret_id     = aws_secretsmanager_secret.secret_key_base.id
  secret_string = random_password.secret_key_base.result
}
resource "aws_db_instance" "redmine" {
  identifier              = "redmine-${var.environment}"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_encrypted       = true
  db_name                 = "redmine"
  username                = "redmine"
  password                = random_password.db.result
  db_subnet_group_name    = module.vpc.database_subnet_group_name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  multi_az                = false # true en producción crítica
  backup_retention_period = 7
  deletion_protection     = false # pásalo a true en producción
  skip_final_snapshot     = true  # pásalo a false en producción
}
