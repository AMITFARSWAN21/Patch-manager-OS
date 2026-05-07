# variable "aws_region" {
#   description = "AWS region"
#   type        = string
#    default     = "ap-south-1"
# }

# variable "instance_type" {
#   description = "EC2 instance type"
#   type        = string
#   default     = "t2.micro"
# }

# variable "ami_id" {
#   description = "AMI ID for EC2 instances"
#   type        = string
#   default     = "ami-0a936bb624678fd88"
# }

# variable "key_name" {
#   description = "EC2 Key Pair name (optional)"
#   type        = string
#   default     = ""
# }

# variable "instance_name" {
#   description = "Name for the EC2 instance"
#   type        = string
#   default     = "PatchTest-Instance"
# }

# variable "target_environment" {
#   description = "Environment tag value to target existing instances"
#   type        = string
#   default     = "Production"
# }


# variable "patch_group_name" {
#   description = "Patch group name for production instances"
#   type        = string
#   default     = "Production-PatchGroup"
# }


variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-0a936bb624678fd88"
}

variable "key_name" {
  description = "EC2 Key Pair name (optional)"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Name for the EC2 instance"
  type        = string
  default     = "PatchTest-Instance"
}

variable "target_environment" {
  description = "Environment tag value to target existing instances"
  type        = string
  default     = "Production"
}

variable "patch_group_name" {
  description = "Patch group name for production instances"
  type        = string
  default     = "Production-PatchGroup"
}

# Add these missing variables
variable "maintenance_window_schedule" {
  description = "Maintenance window schedule for production (cron expression)"
  type        = string
   default = "rate(10 minutes)"  
}

variable "scan_schedule" {
  description = "Patch scan schedule"
  type        = string
   default = "rate(5 minutes)"  
}
