# 1. Database Subnet Group: Tells RDS which private vaults it is allowed to use
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "enterprise-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "Enterprise-DB-Subnets"
  }
}

# 2. Security Group (Firewall): Only allows MySQL traffic (Port 3306) from inside the VPC
resource "aws_security_group" "rds_sg" {
  name        = "enterprise-rds-sg"
  description = "Allow MySQL traffic from within the VPC"
  vpc_id      = aws_vpc.enterprise_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    # 10.0.0.0/16 is the entire VPC. It means the database ignores the public internet.
    cidr_blocks = ["10.0.0.0/16"] 
  }

  tags = {
    Name = "Enterprise-RDS-Security-Group"
  }
}

# 3. The Actual Database: Amazon RDS MySQL 8.0
resource "aws_db_instance" "enterprise_db" {
  identifier             = "enterprise-cart-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro" # AWS Free Tier Eligible!
  allocated_storage      = 20            # 20 GB of SSD storage
  username               = "admin"
  password               = var.db_password # Injected securely from the variable!
  
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  publicly_accessible    = false # CRITICAL: This ensures it is not on the public internet
  skip_final_snapshot    = true  # Saves time when we want to delete it later
}

# 4. The Output: Automatically prints the connection URL when finished
output "rds_endpoint" {
  description = "The connection endpoint for your FastAPI app"
  value       = aws_db_instance.enterprise_db.endpoint
}