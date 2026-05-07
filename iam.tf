# IAM Role for EC2 instance to work with Systems Manager and Inspector
resource "aws_iam_role" "ec2_ssm_role" {
  name = "EC2-SSM-Inspector-TestRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "EC2-SSM-Inspector-TestRole"
  }
}

# Attach AWS managed policies for Systems Manager
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "EC2-SSM-Inspector-TestProfile-${random_string.suffix.result}"
  role = aws_iam_role.ec2_ssm_role.name
}

# IAM Role for Maintenance Window
resource "aws_iam_role" "maintenance_window_role" {
  name = "MaintenanceWindow-TestRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "MaintenanceWindow-TestRole"
  }
}

# Attach maintenance window policy
resource "aws_iam_role_policy_attachment" "maintenance_window_policy" {
  role       = aws_iam_role.maintenance_window_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

# Additional policy for patch management
resource "aws_iam_role_policy" "maintenance_window_patch_policy" {
  name = "MaintenanceWindowPatchPolicy-${random_string.suffix.result}"
  role = aws_iam_role.maintenance_window_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetCommandInvocation",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}
