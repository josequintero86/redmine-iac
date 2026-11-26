output "redmine_url" {
  value = "http://${aws_lb.redmine.dns_name}"
}
