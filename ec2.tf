# ============================================================
# DATA SOURCES
# ============================================================

# # Windows Server 2022 AMI - latest
# data "aws_ami" "windows_2022" {
#   most_recent = true
#   owners      = ["amazon"]

#   filter {
#     name   = "name"
#     values = ["Windows_Server-2022-English-Full-Base-*"]
#   }

#   filter {
#     name   = "state"
#     values = ["available"]
#   }

#   filter {
#     name   = "architecture"
#     values = ["x86_64"]
#   }
# }

# Default VPC security group
data "aws_security_group" "default_sg" {
  name   = "default"
  vpc_id = aws_vpc.main.id
}

# ============================================================
# WINDOWS INSTANCE SECURITY GROUP
# ============================================================

resource "aws_security_group" "ssm_windows_sg" {
  name        = "ssm-windows-test-sg-${random_string.suffix.result}"
  description = "Windows instances - outbound to VPC endpoints and WSUS only"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS to VPC endpoints for SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "WSUS HTTP to WSUS server"
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    description = "WSUS HTTPS to WSUS server"
    from_port   = 8531
    to_port     = 8531
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  tags = {
    Name        = "ssm-windows-test-sg"
    Environment = "Production"
  }
}

# ============================================================
# WINDOWS EC2 INSTANCE
# Now using Windows Server 2022
# Private subnet — no internet
# Patches via WSUS server (also Server 2022)
# ============================================================

resource "aws_instance" "windows_ssm_test" {
  # ami                    = data.aws_ami.windows_2022.id
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
    # Start SSM Agent
    Start-Service AmazonSSMAgent -ErrorAction SilentlyContinue
    Set-Service AmazonSSMAgent -StartupType Automatic
    Write-Output "SSM Agent started at $(Get-Date)" | Out-File C:\ssm-init.log

    # Wait for WSUS server to be ready
    $wsusIp = "${aws_instance.wsus_server.private_ip}"
    $wsusReady = $false
    $attempts = 0

    Write-Output "Waiting for WSUS server at $wsusIp`:8530" | Out-File C:\ssm-init.log -Append

    while (-not $wsusReady -and $attempts -lt 60) {
      try {
        $connection = Test-NetConnection -ComputerName $wsusIp -Port 8530 -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
          $wsusReady = $true
          Write-Output "WSUS server ready at $(Get-Date)" | Out-File C:\ssm-init.log -Append
        }
      } catch {}
      if (-not $wsusReady) {
        Write-Output "WSUS not ready yet... attempt $attempts at $(Get-Date)" | Out-File C:\ssm-init.log -Append
        Start-Sleep -Seconds 60
        $attempts++
      }
    }

    if (-not $wsusReady) {
      Write-Output "WARNING: WSUS server not reachable after 60 attempts" | Out-File C:\ssm-init.log -Append
    }

    # Configure Windows Update Agent to use WSUS server
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (!(Test-Path $wuPath)) { New-Item -Path $wuPath -Force }
    if (!(Test-Path $auPath)) { New-Item -Path $auPath -Force }

    Set-ItemProperty -Path $wuPath -Name "WUServer" `
      -Value "http://$wsusIp`:8530" -Force
    Set-ItemProperty -Path $wuPath -Name "WUStatusServer" `
      -Value "http://$wsusIp`:8530" -Force
    Set-ItemProperty -Path $auPath -Name "UseWUServer" -Value 1 -Force

    Restart-Service wuauserv -Force

    Write-Output "WSUS configured at $(Get-Date) pointing to http://$wsusIp`:8530" `
      | Out-File C:\ssm-init.log -Append
    Write-Output "Windows Server 2022 instance setup complete" | Out-File C:\ssm-init.log -Append
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
    ignore_changes = [tags]
  }

  depends_on = [
    aws_iam_instance_profile.ec2_ssm_profile,
    aws_instance.wsus_server,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages,
    aws_vpc_endpoint.ec2,
    aws_vpc_endpoint.s3_interface
  ]
}

# ============================================================
# LINUX INSTANCE SECURITY GROUP -- NOT REQUIRED
# ============================================================

# resource "aws_security_group" "ssm_linux_sg" {
#   name        = "ssm-linux-test-sg-${random_string.suffix.result}"
#   description = "Linux SSM test instance - outbound HTTPS to VPC endpoints only"
#   vpc_id      = aws_vpc.main.id
#
#   egress {
#     description = "HTTPS to VPC endpoints for SSM and S3"
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = [var.vpc_cidr]
#   }
#
#   tags = {
#     Name        = "ssm-linux-test-sg"
#     Environment = "Production"
#   }
# }

# ============================================================
# LINUX EC2 INSTANCE -- NOT REQUIRED
# ============================================================

# resource "aws_instance" "linux_ssm_test" {
#   ami                    = "ami-0e267a9919cdf778f"
#   instance_type          = "t3.medium"
#   subnet_id              = aws_subnet.private.id
#   vpc_security_group_ids = [
#     aws_security_group.ssm_linux_sg.id,
#     data.aws_security_group.default_sg.id
#   ]
#   iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
#
#   user_data = <<-EOF
#     #!/bin/bash
#     systemctl enable amazon-ssm-agent
#     systemctl start amazon-ssm-agent
#     echo "SSM Agent started at $(date)" > /var/log/ssm-init.log
#   EOF
#
#   root_block_device {
#     volume_type           = "gp3"
#     volume_size           = 30
#     delete_on_termination = true
#     encrypted             = true
#
#     tags = {
#       Name        = "linux-ssm-test-root"
#       Environment = "Production"
#     }
#   }
#
#   tags = {
#     Name        = "Linux-SSM-Test-${random_string.suffix.result}"
#     Environment = "Production"
#   }
#
#   lifecycle {
#     ignore_changes = [tags]
#   }
#
#   depends_on = [
#     aws_iam_instance_profile.ec2_ssm_profile,
#     aws_vpc_endpoint.ssm,
#     aws_vpc_endpoint.ssmmessages,
#     aws_vpc_endpoint.ec2messages,
#     aws_vpc_endpoint.ec2,
#     aws_vpc_endpoint.s3_interface
#   ]
# }

# ============================================================
# UBUNTU INSTANCE SECURITY GROUP -- NOT REQUIRED
# ============================================================

# resource "aws_security_group" "ssm_ubuntu_sg" {
#   name        = "ssm-ubuntu-test-sg-${random_string.suffix.result}"
#   description = "Ubuntu instance - outbound to VPC endpoints and apt-cache server"
#   vpc_id      = aws_vpc.main.id
#
#   egress {
#     description = "HTTPS to VPC endpoints"
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = [var.vpc_cidr]
#   }
#
#   egress {
#     description = "apt-cacher-ng for Ubuntu patches"
#     from_port   = 3142
#     to_port     = 3142
#     protocol    = "tcp"
#     cidr_blocks = [var.public_subnet_cidr]
#   }
#
#   tags = {
#     Name        = "ssm-ubuntu-test-sg"
#     Environment = "Production"
#   }
# }

# ============================================================
# UBUNTU EC2 INSTANCE -- NOT REQUIRED
# ============================================================

# resource "aws_instance" "ubuntu_ssm_test" {
#   ami                    = "ami-0f457776b2f2411c1"
#   instance_type          = "t3.medium"
#   subnet_id              = aws_subnet.private.id
#   vpc_security_group_ids = [
#     aws_security_group.ssm_ubuntu_sg.id,
#     data.aws_security_group.default_sg.id
#   ]
#   iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
#
#   user_data = <<-EOF
#     #!/bin/bash
#     systemctl enable amazon-ssm-agent
#     systemctl start amazon-ssm-agent
#     echo "SSM Agent started at $(date)" > /var/log/ssm-init.log
#
#     APT_CACHE_IP="${aws_instance.apt_cache_server.private_ip}"
#     echo "Waiting for apt-cache server at $APT_CACHE_IP:3142" >> /var/log/ssm-init.log
#
#     READY=false
#     ATTEMPTS=0
#     while [ "$READY" = "false" ] && [ $ATTEMPTS -lt 30 ]; do
#       if curl -s --connect-timeout 5 "http://$APT_CACHE_IP:3142" > /dev/null 2>&1; then
#         READY=true
#         echo "apt-cache server ready at $(date)" >> /var/log/ssm-init.log
#       else
#         echo "Waiting... attempt $ATTEMPTS at $(date)" >> /var/log/ssm-init.log
#         sleep 30
#         ATTEMPTS=$((ATTEMPTS + 1))
#       fi
#     done
#
#     echo "Acquire::http::Proxy \"http://$APT_CACHE_IP:3142\";" \
#       > /etc/apt/apt.conf.d/01proxy
#     echo "apt proxy configured to http://$APT_CACHE_IP:3142" >> /var/log/ssm-init.log
#   EOF
#
#   root_block_device {
#     volume_type           = "gp3"
#     volume_size           = 30
#     delete_on_termination = true
#     encrypted             = true
#
#     tags = {
#       Name        = "ubuntu-ssm-test-root"
#       Environment = "Production"
#     }
#   }
#
#   tags = {
#     Name        = "Ubuntu-SSM-Test-${random_string.suffix.result}"
#     Environment = "Production"
#   }
#
#   lifecycle {
#     ignore_changes = [tags]
#   }
#
#   depends_on = [
#     aws_iam_instance_profile.ec2_ssm_profile,
#     aws_instance.apt_cache_server,
#     aws_vpc_endpoint.ssm,
#     aws_vpc_endpoint.ssmmessages,
#     aws_vpc_endpoint.ec2messages,
#     aws_vpc_endpoint.ec2,
#     aws_vpc_endpoint.s3_interface
#   ]
# }

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

# output "linux_instance_id" {
#   description = "Instance ID of the Linux SSM test instance"
#   value       = aws_instance.linux_ssm_test.id
# }
#
# output "linux_instance_private_ip" {
#   description = "Private IP of the Linux SSM test instance"
#   value       = aws_instance.linux_ssm_test.private_ip
# }
#
# output "linux_ssm_session_command" {
#   description = "Connect to Linux via Session Manager"
#   value       = "aws ssm start-session --target ${aws_instance.linux_ssm_test.id}"
# }
#
# output "ubuntu_instance_id" {
#   description = "Instance ID of the Ubuntu SSM test instance"
#   value       = aws_instance.ubuntu_ssm_test.id
# }
#
# output "ubuntu_instance_private_ip" {
#   description = "Private IP of the Ubuntu SSM test instance"
#   value       = aws_instance.ubuntu_ssm_test.private_ip
# }
#
# output "ubuntu_ssm_session_command" {
#   description = "Connect to Ubuntu via Session Manager"
#   value       = "aws ssm start-session --target ${aws_instance.ubuntu_ssm_test.id}"
# }
