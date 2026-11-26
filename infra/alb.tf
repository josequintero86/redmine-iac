resource "aws_lb" "redmine" {
  name               = "redmine-${var.environment}"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.alb.id]
}
resource "aws_lb_target_group" "redmine" {
  name        = "redmine-${var.environment}"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.redmine.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redmine.arn
  }
}

