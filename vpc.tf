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
# Used by WSUS server (public subnet) to sync from Microsoft
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

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # No default route — private instances use:
  # 1. VPC endpoints for SSM communication
  # 2. WSUS server (inside VPC) for patching
  # No internet access required for Windows-only patching

  tags = {
    Name        = "ssm-patch-private-rt"
    Environment = "Production"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

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
# ============================================================

resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "vpc-endpoints-sg-${random_string.suffix.result}"
  description = "Allow HTTPS from private and public subnets to VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from private subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "HTTPS from public subnet"
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
# Both subnets included — WSUS (public) and instances (private)
# both need SSM communication
# ============================================================

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]  # ← both subnets
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
  subnet_ids          = [aws_subnet.private.id]  # ← both subnets
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
  subnet_ids          = [aws_subnet.private.id]  # ← both subnets
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
  subnet_ids          = [aws_subnet.private.id]  # ← both subnets
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "endpoint-ec2"
    Environment = "Production"
  }
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]   # gateway endpoint — no subnet needed

  tags = {
    Name        = "endpoint-s3-gateway"
    Environment = "Production"
  }
}

resource "aws_vpc_endpoint" "inspector2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.inspector2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]  # ← both subnets
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