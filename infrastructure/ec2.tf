# 1. Dynamically fetch the latest Ubuntu Linux image
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu's publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 2. Security Group for the Server (The Firewall)
resource "aws_security_group" "app_sg" {
  name        = "enterprise-app-sg"
  description = "Allow HTTP and SSH traffic to the app server"
  vpc_id      = aws_vpc.enterprise_vpc.id

  # Allow standard web traffic (Port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow FastAPI testing port (Port 8000)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH to log into the server (Port 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Allow the server to download updates and Docker from the internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Enterprise-App-Security-Group"
  }
}

# 3. The Physical Server (EC2 Instance)
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro" # Updated to the modern Free Tier
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # We tell the server to automatically install Docker the moment it boots up!
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker ubuntu
              EOF

  tags = {
    Name = "Enterprise-FastAPI-Server"
  }
}

# 4. Output the Server's Public IP
output "app_server_public_ip" {
  description = "The public IP address of your application server"
  value       = aws_instance.app_server.public_ip
}