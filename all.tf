provider "aws" {
  region = "us-west-2"  // Specify your preferred region
access_key = "AKIAVRUVRIZFAOVD6UUP"
  secret_key = "w2j5gY/kQWiLuLGru8jvAlTJKhI5H5j0g2rvPES7"
}

// VPC
resource "aws_vpc" "primary" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}
// Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.primary.id
}

// Route Table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.primary.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

// Subnets
resource "aws_subnet" "app_subnet_a" {
  vpc_id            = aws_vpc.primary.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "us-west-2a"
}

resource "aws_subnet" "app_subnet_b" {
  vpc_id            = aws_vpc.primary.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "us-west-2b"
}

// Security Groups
resource "aws_security_group" "frontend_sg" {
  name        = "frontend-sg"
  description = "Security group for the frontend service"
  vpc_id      = aws_vpc.primary.id

  // Permit HTTP and HTTPS traffic from any source
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Permit all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "database_sg" {
  name        = "database-sg"
  description = "Security group for the database"
  vpc_id      = aws_vpc.primary.id

  // Allow database traffic from the frontend security group
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_sg.id]
  }

  // Permit all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// EC2 Instances
resource "aws_instance" "frontend_instance" {
  ami           = "ami-08a9496912b9d9445"  // Substitute with your AMI ID
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app_subnet_a.id
  security_groups = [aws_security_group.frontend_sg.id]

  // Example: User data to install and configure a web server
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y nginx
              echo "Welcome to the frontend instance!" | sudo tee /var/www/html/index.html
              EOF
}

resource "aws_instance" "database_instance" {
  ami           = "ami-08a9496912b9d9445"  // Substitute with your AMI ID
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app_subnet_b.id
  security_groups = [aws_security_group.database_sg.id]

  // Example: User data to install and configure PostgreSQL
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y postgresql

              # Configure PostgreSQL
              sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'manshi@123';"
              sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/12/main/postgresql.conf
              sudo service postgresql restart
              EOF
}

// Application Load Balancer (ALB)
resource "aws_lb" "frontend_alb" {
  name               = "frontend-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.app_subnet_a.id, aws_subnet.app_subnet_b.id]
}

// ALB Listener and Target Group
resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_target.arn
  }
}

resource "aws_lb_target_group" "frontend_target" {
  name     = "frontend-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.primary.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

// Output DNS name of ALB
output "alb_dns_name" {
  value = aws_lb.frontend_alb.dns_name
}
