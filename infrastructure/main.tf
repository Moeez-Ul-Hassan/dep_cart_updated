# 1. The Provider: Tell Terraform we are using AWS in N. Virginia
provider "aws" {
  region = "us-east-1"
}

# 2. The VPC: The invisible, secure perimeter
resource "aws_vpc" "enterprise_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "Enterprise-Cart-VPC"
  }
}

# 3. The Internet Gateway: The front door for public traffic
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.enterprise_vpc.id

  tags = {
    Name = "Enterprise-IGW"
  }
}

# 4. Public Subnet: Where your FastAPI server will eventually live
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.enterprise_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true # Automatically assigns a public IP to servers here

  tags = {
    Name = "Enterprise-Public-Subnet"
  }
}

# 5. Route Table: Tells the Public Subnet how to reach the Internet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.enterprise_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Enterprise-Public-Route"
  }
}

# 6. Route Table Association: Links the traffic cop to the specific subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# 7. Private Subnet 1: The hidden vault for your MySQL Database (Zone A)
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.enterprise_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Enterprise-Private-Subnet-A"
  }
}

# 8. Private Subnet 2: The backup vault for Database High Availability (Zone B)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.enterprise_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Enterprise-Private-Subnet-B"
  }
}