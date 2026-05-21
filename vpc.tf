# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "ssm-patch-vpc"
    Environment = "Production"
  }
}

# ============================================================
# SUBNETS
# ============================================================

# Private subnet — Windows and Linux EC2 instances (no internet)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name        = "ssm-patch-private-subnet"
    Environment = "Production"
  }
}

# Public subnet — WSUS server only (has internet via IGW)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name        = "ssm-patch-public-subnet"
    Environment = "Production"
  }
}

# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "ssm-patch-igw"
    Environment = "Production"
  }
}

# ============================================================
# ROUTE TABLES
# ============================================================

# Private route table — no internet route
# Windows and Linux instances use VPC endpoints only
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "ssm-patch-private-rt"
    Environment = "Production"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Public route table — has internet route via IGW
# WSUS server uses this to reach Microsoft Windows Update
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "ssm-patch-public-rt"
    Environment = "Production"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# SECURITY GROUP FOR VPC ENDPOINTS
# Allows HTTPS from both subnets:
# — private subnet: Windows and Linux instances
# — public subnet: WSUS server SSM agent
# private_dns_enabled = true makes DNS resolution VPC-wide
# so WSUS in public subnet also resolves to endpoint private IP
# and can connect as long as this SG allows it
# ============================================================

resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "vpc-endpoints-sg-${random_string.suffix.result}"
  description = "Allow HTTPS from private and public subnets to VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnet - Windows and Linux instances"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "HTTPS from public subnet - WSUS server SSM agent"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "vpc-endpoints-sg"
    Environment = "Production"
  }
}

# ============================================================
# VPC INTERFACE ENDPOINTS
# All deployed in private subnet only — same AZ restriction
# prevents deploying in both subnets when they are in same AZ
# private_dns_enabled = true creates VPC-wide DNS override
# so ALL instances including WSUS in public subnet resolve
# endpoint hostnames to private IPs and connect through here
# ============================================================

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "endpoint-ssm"
    Environment = "Production"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "endpoint-ssmmessages"
    Environment = "Production"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "endpoint-ec2messages"
    Environment = "Production"
  }
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "endpoint-ec2"
    Environment = "Production"
  }
}

# S3 Gateway endpoint — free, required by AWS before S3 interface
# endpoint can use private_dns_enabled = true
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "endpoint-s3-gateway"
    Environment = "Production"
  }
}

# S3 Interface endpoint — handles private DNS resolution
# SSM patch module downloads use this
# Requires gateway endpoint to exist first — AWS requirement
resource "aws_vpc_endpoint" "s3_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  depends_on = [aws_vpc_endpoint.s3_gateway]

  tags = {
    Name        = "endpoint-s3-interface"
    Environment = "Production"
  }
}

resource "aws_vpc_endpoint" "inspector2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.inspector2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "endpoint-inspector2"
    Environment = "Production"
  }
}

# ============================================================
# OUTPUTS
# ============================================================

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}