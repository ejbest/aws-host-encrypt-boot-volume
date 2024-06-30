variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "The AMI ID to use for the instance"
  type        = string
  default     = "ami-0c55b159cbfafe1f0"  # Example AMI ID for Amazon Linux 2 in us-east-1
}

variable "instance_type" {
  description = "The type of instance to create"
  type        = string
  default     = "t2.micro"
}

variable "instance_name" {
  description = "The name tag for the instance"
  type        = string
  default     = "testserver"
}

variable "instance_job_tag" {
  description = "The job tag for the instance"
  type        = string
  default     = "job1"
}

variable "root_volume_size" {
  description = "The size of the root volume in GB"
  type        = number
  default     = 10
}

variable "volume_name" {
  description = "The name tag for the root volume"
  type        = string
  default     = "testserverDisk"
}

variable "volume_job_tag" {
  description = "The job tag for the root volume"
  type        = string
  default     = "job1"
}

variable "volume_duty_tag" {
  description = "The duty tag for the root volume"
  type        = string
  default     = "job2"
}
