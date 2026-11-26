terraform {
  required_version = ">= 1.10"
  backend "s3" {
    bucket       = "tu-org-redmine-tfstate"
    key          = "redmine/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}