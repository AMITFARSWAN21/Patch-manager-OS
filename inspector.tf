resource "aws_inspector2_enabler" "ec2_scanning" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2"]

  timeouts {
    delete = "15m"
  }
}

resource "aws_cloudwatch_log_group" "patch_logs" {
  name              = "/aws/ssm/patch-manager-${random_string.suffix.result}"
  retention_in_days = 7

  tags = {
    Name = "patch-manager-logs"
  }
}