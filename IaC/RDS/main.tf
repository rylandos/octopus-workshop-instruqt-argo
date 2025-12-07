terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# Generate unique suffix per environment
resource "random_pet" "suffix" {
  length = 2
}

resource "random_password" "password" {
  length  = 16
  special = false
}

# ---------------------------------------------
# VPC with DNS enabled (required for public RDS)
# ---------------------------------------------
resource "aws_vpc" "sql_vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "sql-vpc-${random_pet.suffix.id}"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.sql_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.sql_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.sql_vpc.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.sql_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rt_a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rt_b" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.rt.id
}

# -----------------------------------------------------
# Security Group (Public inbound allowed temporarily)
# -----------------------------------------------------
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg-${random_pet.suffix.id}"
  description = "Temporary public access for demo"

  vpc_id = aws_vpc.sql_vpc.id

  ingress {
    description = "SQL Server"
    protocol    = "tcp"
    from_port   = 1433
    to_port     = 1433
    cidr_blocks = ["0.0.0.0/0"]  # <= OPEN ACCESS FOR NOW
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------
# Subnet Group
# -----------------------------------------------------
resource "aws_db_subnet_group" "sql_subnets" {
  name       = "sql-subnets-${random_pet.suffix.id}"
  subnet_ids = [
    aws_subnet.subnet_1.id,
    aws_subnet.subnet_2.id
  ]

  tags = {
    Name = "sql-subnets-${random_pet.suffix.id}"
  }
}

# -----------------------------------------------------
# RDS SQL Server Free Tier
# -----------------------------------------------------
resource "aws_db_instance" "sqlserver" {
  identifier              = "sql-${random_pet.suffix.id}"
  allocated_storage       = 20
  engine                  = "sqlserver-ex"
  instance_class          = "db.t3.micro"
  username                = "admin${random_pet.suffix.id}"
  password                = random_password.password.result
  db_subnet_group_name    = aws_db_subnet_group.sql_subnets.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  publicly_accessible     = true
  skip_final_snapshot     = true
  port                    = 1433

  tags = {
    Name = "sql-${random_pet.suffix.id}"
  }
}

# -----------------------------------------------------
# Outputs
# -----------------------------------------------------
output "rds_host" {
  value = aws_db_instance.sqlserver.address
}

output "rds_port" {
  value = aws_db_instance.sqlserver.port
}

output "username" {
  value = aws_db_instance.sqlserver.username
}

output "password" {
  value     = nonsensitive(random_password.password.result)
  sensitive = false
}

output "instance_identifier" {
  value = aws_db_instance.sqlserver.identifier
}
