data "aws_ami" "ui" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "tag:Application"
    values = ["tt-ui"]
  }
} 

data "aws_ami" "api" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "tag:Application"
    values = ["tt-api"]
  }
}
