# ============================================================
# DATA SOURCES
# ============================================================

data "aws_security_group" "default_sg" {
  name   = "default"
  vpc_id = aws_vpc.main.id
}

# ============================================================
# WINDOWS INSTANCE SECURITY GROUP
# ============================================================

resource "aws_security_group" "ssm_windows_sg" {
  name        = "ssm-windows-test-sg-${random_string.suffix.result}"
  description = "Windows instances - SSM via VPC endpoints, patches via WSUS"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to VPC endpoints for SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

   egress {
    description     = "HTTPS to S3 via gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3_gateway.prefix_list_id]
  }

  egress {
    description = "WSUS HTTP to WSUS server port 8530"
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "WSUS HTTPS to WSUS server port 8531"
    from_port   = 8531
    to_port     = 8531
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "ssm-windows-test-sg"
    Environment = var.target_environment
  }
}

# ============================================================
# WINDOWS EC2 INSTANCE
# Oldest available Server 2022 AMI - March 2026
# Patches via WSUS server inside VPC - no direct internet
# ============================================================

resource "aws_instance" "windows_ssm_test" {
  ami                    = "ami-038b0fc52513087d0"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.ssm_windows_sg.id
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
    <powershell>
    # Step 1 - Start SSM Agent
    Start-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    Set-Service AmazonSSMAgent -StartupType Automatic
    Write-Output "SSM Agent started at $(Get-Date)" | Out-File C:\ssm-init.log

    # Step 2 - Point Windows Update to WSUS server inside VPC
    $wuPath   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $wuAUPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    New-Item -Path $wuPath   -Force | Out-Null
    New-Item -Path $wuAUPath -Force | Out-Null

    Set-ItemProperty -Path $wuPath   -Name "WUServer"       -Value "http://${aws_instance.wsus_server.private_ip}:8530"
    Set-ItemProperty -Path $wuPath   -Name "WUStatusServer" -Value "http://${aws_instance.wsus_server.private_ip}:8530"
    Set-ItemProperty -Path $wuAUPath -Name "UseWUServer"    -Value 1 -Type DWord
    Set-ItemProperty -Path $wuAUPath -Name "AUOptions"      -Value 3 -Type DWord
    Set-ItemProperty -Path $wuAUPath -Name "NoAutoUpdate"   -Value 0 -Type DWord

    Write-Output "WSUS registry keys set at $(Get-Date)" | Out-File C:\ssm-init.log -Append

    # Step 3 - Restart Windows Update service
    Restart-Service wuauserv -Force
    Write-Output "Windows Update service restarted at $(Get-Date)" | Out-File C:\ssm-init.log -Append

    # Step 4 - Register with WSUS
    wuauclt /resetauthorization /detectnow
    Write-Output "Registered with WSUS at $(Get-Date)" | Out-File C:\ssm-init.log -Append

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
      Environment = var.target_environment
    }
  }

  tags = {
    Name       = "Windows-SSM-Test-${random_string.suffix.result}"
    OS         = "windows"
    AutoPatch  = "true"
    Environment = var.target_environment
  }

  lifecycle {
    ignore_changes = [
      user_data,
      ami,
      tags
    ]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.ec2,
  ]
}

# ============================================================
# SSM ASSOCIATION — Configure WSUS on Windows instances
# Runs daily on all instances tagged OS=windows
# Sets registry to point Windows Update at WSUS server
# Ensures wuauserv service is running (required for patching)
# Forces WSUS registration via wuauclt
# ============================================================
resource "aws_ssm_association" "configure_wsus_on_windows" {
  name                = "AWS-RunPowerShellScript"
  schedule_expression = "rate(1 day)"

  targets {
    key    = "tag:OS"
    values = ["windows"]
  }

  parameters = {
    commands = join("\n", [
      "$wuPath   = 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate'",
      "$wuAUPath = 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU'",
      "New-Item -Path $wuPath   -Force | Out-Null",
      "New-Item -Path $wuAUPath -Force | Out-Null",
      "Set-ItemProperty -Path $wuPath   -Name 'WUServer'       -Value 'http://${aws_instance.wsus_server.private_ip}:8530'",
      "Set-ItemProperty -Path $wuPath   -Name 'WUStatusServer' -Value 'http://${aws_instance.wsus_server.private_ip}:8530'",
      "Set-ItemProperty -Path $wuAUPath -Name 'UseWUServer'    -Value 1 -Type DWord",
      "Set-ItemProperty -Path $wuAUPath -Name 'AUOptions'      -Value 3 -Type DWord",
      "Set-ItemProperty -Path $wuAUPath -Name 'NoAutoUpdate'   -Value 0 -Type DWord",
      "Set-Service wuauserv -StartupType Automatic",
      "Start-Service wuauserv -ErrorAction SilentlyContinue",
      "wuauclt /resetauthorization /detectnow /reportnow",
      "Write-Output 'WSUS registry configured and Windows Update service started'"
    ])
  }

  depends_on = [aws_instance.wsus_server]
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
  value       = "aws ssm start-session --target ${aws_instance.windows_ssm_test.id} --region ${var.aws_region}"
}

output "windows_wsus_verify_command" {
  description = "Run inside SSM session to verify WSUS registry"
  value       = "reg query HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate"
}