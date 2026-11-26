variable "region" {
  type    = string
  default = "us-east-1"
}
variable "environment" {
  type    = string
  default = "prod"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "redmine_image" {
  type    = string
  default = "redmine:5.1"
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "task_cpu" {
  type    = number
  default = 512
}
variable "task_memory" {
  type    = number
  default = 1024
}
variable "desired_count" {
  type    = number
  default = 1
}
