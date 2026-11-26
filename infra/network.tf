data "aws_availability_zones" "available" {
  state = "available"
}
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}
module "vpc" {
  source         = "terraform-aws-modules/vpc/aws"
  version        = "~> 5.0"
  name           = "redmine-${var.environment}"
  cidr           = var.vpc_cidr
  azs            = local.azs
  public_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i +
  10)]
  database_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i +
  20)]
  create_database_subnet_group = true
  enable_nat_gateway           = true
  single_nat_gateway           = true # Ahorro de costos; en alta disponibilidad real usa uno por AZ
}
