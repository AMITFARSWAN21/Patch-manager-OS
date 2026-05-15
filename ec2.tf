
# Latest Windows Server 2019 AMI (stable, pre-installed SSM agent)
data "aws_ami" "windows_2019" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
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

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# Default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ============================================================
# SECURITY GROUP
# No inbound rules — SSM Session Manager uses outbound HTTPS only
# ============================================================

resource "aws_security_group" "ssm_windows_sg" {
  name        = "ssm-windows-test-sg-${random_string.suffix.result}"
  description = "Windows SSM test instance - no inbound RDP, outbound HTTPS only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound for SSM agent to reach AWS endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ssm-windows-test-sg"
    Environment = "Production"
  }
}

# ============================================================
# WINDOWS EC2 INSTANCE
# References aws_iam_instance_profile.ec2_ssm_profile from iam.tf
# ============================================================

resource "aws_instance" "windows_ssm_test" {
  ami                    = data.aws_ami.windows_2019.id
  instance_type          = "t3.medium"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ssm_windows_sg.id]

  # References instance profile defined in iam.tf
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  # Ensure SSM agent is running on first boot
  user_data = <<-EOF
    <powershell>
    Start-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    Set-Service AmazonSSMAgent -StartupType Automatic
    Write-Output "SSM Agent started at $(Get-Date)" | Out-File C:\ssm-init.log
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
    Environment = "Production"          # Required: picked up by aws_instances filter in OS detection module
    OS          = "windows"             # Manual tag = "manual" confidence, no SSM inventory wait needed
    Project     = "SSM-Patch-Testing"
    Owner       = "ops-team"
    PatchGroup  = "windows-Production-PatchGroup"
    AutoPatch   = "true"
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile  # Defined in iam.tf
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

output "windows_ami_used" {
  description = "Windows AMI resolved at apply time"
  value = {
    id   = data.aws_ami.windows_2019.id
    name = data.aws_ami.windows_2019.name
  }
}

output "ssm_session_command" {
  description = "Connect via Session Manager (no RDP or open ports needed)"
  value       = "aws ssm start-session --target ${aws_instance.windows_ssm_test.id}"
}
