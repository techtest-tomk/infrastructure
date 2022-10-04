locals {
  public_subnets = [for az in var.availability_zones : {
    name = "tt-public-${az}"
    type = "public"
  }]
  private_subnets = [for az in var.availability_zones : {
    name = "tt-private-${az}"
    type = "private"
  }]
  all_subnets = concat(local.public_subnets, local.private_subnets)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "tt-vpc"
  cidr = "10.0.0.0/16"

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "tt_public_alb_sg" {
  name        = "tt_public_alb_sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "tt_public_alb_sg"
  }
}

resource "aws_security_group" "tt_api_alb_sg" {
  name        = "tt_api_alb_sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from VPC"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = [module.vpc.vpc_cidr_block]
    security_groups = [aws_security_group.tt_public_alb_sg.id]
  }

  tags = {
    Name = "tt_api_alb_sg"
  }
}

resource "aws_lb" "tt_public_alb" {
  name               = "tt-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tt_public_alb_sg.id]
  subnets            = module.vpc.public_subnets
  idle_timeout       = 120

  depends_on = [
    aws_lb_target_group.tt_public_lb_tg
  ]
}

resource "aws_lb" "tt_api_alb" {
  name               = "tt-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.tt_api_alb_sg.id]
  subnets            = module.vpc.private_subnets
}

resource "aws_lb_target_group" "tt_public_lb_tg" {
  name     = "tt-public-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

resource "aws_lb_target_group" "tt_api_lb_tg" {
  name     = "tt-api-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

resource "aws_lb_listener" "tt_public_lb_listener" {
  load_balancer_arn = aws_lb.tt_public_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tt_public_lb_tg.arn
  }
}

resource "aws_lb_listener" "tt_api_lb_listener" {
  load_balancer_arn = aws_lb.tt_api_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tt_api_lb_tg.arn
  }
}

resource "aws_launch_configuration" "tt_asg_ui_lc" {
  name            = "tt-ui-launch-config"
  image_id        = data.aws_ami.ui.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.tt_api_alb_sg.id]
  user_data       = <<EOF
  #!/bin/bash
  sed -i "/^\([[:space:]]*API_ENDPOINT:\).*/s//\1\"${aws_lb.tt_api_alb.dns_name}\"/" ~/app/build/env-config.js
  EOF
}

resource "aws_launch_configuration" "tt_asg_api_lc" {
  name            = "tt-api-launch-config"
  image_id        = data.aws_ami.api.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.tt_api_alb_sg.id]
}

resource "aws_autoscaling_group" "tt_asg_ui" {
  name                 = "tt-asg-ui"
  launch_configuration = aws_launch_configuration.tt_asg_ui_lc.name
  min_size             = 1
  max_size             = 2

  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [aws_lb_target_group.tt_public_lb_tg.arn]
}
resource "aws_autoscaling_group" "tt_asg_api" {
  name                 = "tt-asg-api"
  launch_configuration = aws_launch_configuration.tt_asg_api_lc.name
  min_size             = 1
  max_size             = 2

  vpc_zone_identifier = module.vpc.private_subnets
}

resource "aws_vpc_endpoint" "dynamodb_ep" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.eu-west-2.dynamodb"
}
