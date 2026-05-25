# ============================================================
# DATA SOURCES
# ============================================================

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_security_group" "default_sg" {
  name   = "default"
  vpc_id = aws_vpc.main.id
}

# ============================================================
# WINDOWS INSTANCE SECURITY GROUP
# ============================================================

resource "aws_security_group" "ssm_windows_sg" {
  name        = "ssm-windows-test-sg-${random_string.suffix.result}"
  description = "Windows instances - outbound to VPC endpoints and Microsoft Update via NAT"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to VPC endpoints for SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to Microsoft Update via NAT Gateway"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP to Microsoft Update via NAT Gateway"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ssm-windows-test-sg"
    Environment = "Production"
  }
}

# ============================================================
# UBUNTU INSTANCE SECURITY GROUP
# Ubuntu patches directly via NAT Gateway → Canonical
# ============================================================

resource "aws_security_group" "ssm_ubuntu_sg" {
  name        = "ssm-ubuntu-test-sg-${random_string.suffix.result}"
  description = "Ubuntu instances - outbound to VPC endpoints and Canonical via NAT"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to VPC endpoints for SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to Canonical repos via NAT Gateway"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP to Canonical repos via NAT Gateway"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ssm-ubuntu-test-sg"
    Environment = "Production"
  }
}

# ============================================================
# WINDOWS EC2 INSTANCE
# ============================================================

resource "aws_instance" "windows_ssm_test" {
  # ami = data.aws_ami.windows_2022.id  ← use for production
  ami                    = "ami-038b0fc52513087d0"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.ssm_windows_sg.id,
    data.aws_security_group.default_sg.id
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
    <powershell>
    Start-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    Set-Service AmazonSSMAgent -StartupType Automatic
    Write-Output "SSM Agent started at $(Get-Date)" | Out-File C:\ssm-init.log

    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (Test-Path $wuPath) {
      Remove-Item -Path $wuPath -Recurse -Force
      Write-Output "Removed old WSUS registry keys at $(Get-Date)" | Out-File C:\ssm-init.log -Append
    }

    Restart-Service wuauserv -Force
    Write-Output "Windows Update configured for direct Microsoft access at $(Get-Date)" | Out-File C:\ssm-init.log -Append
    Write-Output "Windows Server 2022 setup complete at $(Get-Date)" | Out-File C:\ssm-init.log -Append
    </powershell>
  EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name        = "windows-ssm-test-root"
      Environment = "Production"
    }
  }

  tags = {
    Name        = "Windows-SSM-Test-${random_string.suffix.result}"
    Environment = "Production"
  }

  lifecycle {
    ignore_changes = [
      tags,
      user_data
      ]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_nat_gateway.main,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.s3_interface
  ]
}

# ============================================================
# UBUNTU 22.04 EC2 INSTANCE
# Patches directly via NAT Gateway → Canonical
# ============================================================

resource "aws_instance" "ubuntu22_ssm_test" {
  ami                    = "ami-0f457776b2f2411c1"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.ssm_ubuntu_sg.id,
    data.aws_security_group.default_sg.id
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
    #!/bin/bash
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    echo "SSM Agent started at $(date)" > /var/log/ssm-init.log

    # Remove proxy config if exists
    rm -f /etc/apt/apt.conf.d/01proxy
    echo "Using direct internet via NAT Gateway" >> /var/log/ssm-init.log
    echo "Ubuntu 22.04 setup complete at $(date)" >> /var/log/ssm-init.log
  EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name        = "ubuntu22-ssm-test-root"
      Environment = "Production"
    }
  }

  tags = {
    Name        = "Ubuntu22-SSM-Test-${random_string.suffix.result}"
    Environment = "Production"
  }

  lifecycle {
    ignore_changes = [tags,user_data]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_nat_gateway.main,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.s3_interface
  ]
}

# ============================================================
# UBUNTU 24.04 EC2 INSTANCE
# Patches directly via NAT Gateway → Canonical
# ============================================================

resource "aws_instance" "ubuntu24_ssm_test" {
  ami                    = "ami-036d2bb3f14d36e07"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.ssm_ubuntu_sg.id,
    data.aws_security_group.default_sg.id
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
    #!/bin/bash
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    echo "SSM Agent started at $(date)" > /var/log/ssm-init.log

    # Remove proxy config if exists
    rm -f /etc/apt/apt.conf.d/01proxy
    echo "Using direct internet via NAT Gateway" >> /var/log/ssm-init.log
    echo "Ubuntu 24.04 setup complete at $(date)" >> /var/log/ssm-init.log
  EOF

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name        = "ubuntu24-ssm-test-root"
      Environment = "Production"
    }
  }

  tags = {
    Name        = "Ubuntu24-SSM-Test-${random_string.suffix.result}"
    Environment = "Production"
  }

  lifecycle {
    ignore_changes = [tags,user_data]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_nat_gateway.main,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.s3_interface
  ]
}

# ============================================================
# OUTPUTS
# ============================================================

output "windows_instance_id" {
  description = "Instance ID of the Windows SSM test instance"
  value       = aws_instance.windows_ssm_test.id
}

output "windows_instance_private_ip" {
  description = "Private IP of the Windows SSM test instance"
  value       = aws_instance.windows_ssm_test.private_ip
}

output "windows_ssm_session_command" {
  description = "Connect to Windows via Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.windows_ssm_test.id}"
}

output "ubuntu22_instance_id" {
  description = "Instance ID of Ubuntu 22.04"
  value       = aws_instance.ubuntu22_ssm_test.id
}

output "ubuntu22_instance_private_ip" {
  description = "Private IP of Ubuntu 22.04"
  value       = aws_instance.ubuntu22_ssm_test.private_ip
}

output "ubuntu22_ssm_session_command" {
  description = "Connect to Ubuntu 22.04 via Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.ubuntu22_ssm_test.id}"
}

output "ubuntu24_instance_id" {
  description = "Instance ID of Ubuntu 24.04"
  value       = aws_instance.ubuntu24_ssm_test.id
}

output "ubuntu24_instance_private_ip" {
  description = "Private IP of Ubuntu 24.04"
  value       = aws_instance.ubuntu24_ssm_test.private_ip
}

output "ubuntu24_ssm_session_command" {
  description = "Connect to Ubuntu 24.04 via Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.ubuntu24_ssm_test.id}"
}