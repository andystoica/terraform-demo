provider "aws" {
  region = "eu-west-2"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

output "alb_dns_name" {
  value = aws_lb.web_server.dns_name
  description = "The domain name of the load balancer"
}


data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}


# Security Groups
resource "aws_security_group" "web_server" {
  name = "terraform-example-instance"
  
  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"
  
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Auto Scaling Group
resource "aws_launch_configuration" "web_server" {
  image_id = "ami-0be057a22c63962cb"
  instance_type = "t2.micro" 
  security_groups = [aws_security_group.web_server.id]
  
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_server" {
  launch_configuration = aws_launch_configuration.web_server.name
  vpc_zone_identifier = data.aws_subnet_ids.default.ids
  
  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10
  
  tag {
    key = "Name"
    value = "terraform-asg-web-server"
    propagate_at_launch = true
  }
}


# Load Balancer
resource "aws_lb" "web_server" {
  name = "terraform-alb-web-server"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-web-server"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_server.arn
  port = 80
  protocol = "HTTP"
  
  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100
  
  condition {
    field = "path-pattern"
    values = ["*"]
  }
  
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}