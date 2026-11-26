resource "aws_ecs_cluster" "main" {
  name = "redmine-${var.environment}"
}
resource "aws_cloudwatch_log_group" "redmine" {
  name              = "/ecs/redmine-${var.environment}"
  retention_in_days = 30
}
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "execution" {
  name               = "redmine-${var.environment}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}
resource "aws_iam_role_policy_attachment" "execution_base" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.db_password.arn,
        aws_secretsmanager_secret.secret_key_base.arn,
      ]
    }]
  })
}
resource "aws_ecs_task_definition" "redmine" {
  family                   = "redmine-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions = jsonencode([{
    name         = "redmine"
    image        = var.redmine_image
    essential    = true
    portMappings = [{ containerPort = 3000, protocol = "tcp" }]
    environment = [
      { name = "REDMINE_DB_POSTGRES", value = aws_db_instance.redmine.address
      },
      { name = "REDMINE_DB_PORT", value = "5432" },
      { name = "REDMINE_DB_DATABASE", value = "redmine" },
      { name = "REDMINE_DB_USERNAME", value = "redmine" },
      { name = "PGSSLMODE", value = "require" },
    ]
    secrets = [
      { name = "REDMINE_DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
      { name = "REDMINE_SECRET_KEY_BASE", valueFrom = aws_secretsmanager_secret.secret_key_base.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.redmine.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "redmine"
      }
    }
  }])
}
resource "aws_ecs_service" "redmine" {
  name                              = "redmine"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.redmine.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 180 # Redmine tarda en migrar la BD la primera vez
  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.app.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.redmine.arn
    container_name   = "redmine"
    container_port   = 3000
  }
  depends_on = [aws_lb_listener.http]
}
