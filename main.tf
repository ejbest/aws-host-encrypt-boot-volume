# Initialize the provider
provider "aws" {
  region = var.aws_region
}

# Create a security group that allows SSH access
resource "aws_security_group" "test_server_sg" {
  name        = "test-server-sg"
  description = "Allow SSH inbound traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance
resource "aws_instance" "test_server" {
  ami           = var.ami_id
  instance_type = var.instance_type

  tags = {
    Name = var.instance_name
    job  = var.instance_job_tag
  }

  root_block_device {
    volume_size = var.root_volume_size

    tags = {
      Name = var.volume_name
      job  = var.volume_job_tag
      Duty = var.volume_duty_tag
    }
  }

  security_groups = [aws_security_group.test_server_sg.name]
}

# Output the instance ID
output "instance_id" {
  value = aws_instance.test_server.id
}

# Output the instance public DNS
output "instance_public_dns" {
  value = aws_instance.test_server.public_dns
}

resource "aws_ebs_volume" "new_volume" {
  availability_zone = "unknown"
  size              = 10
}

