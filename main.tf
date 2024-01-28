terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.33.0"

    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }

  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Name    = "weclouddata"
      project = "devops"
    }
  }
}

resource "random_uuid" "unique_service_name" {

}

resource "random_integer" "random_integer_service_id" {
  min = 2050
  max = 7500

}


resource "aws_iam_user" "weclouddata" {
  name = "weclouddata-${random_uuid.unique_service_name.result}"
}

resource "aws_iam_access_key" "weclouddata" {
  user = aws_iam_user.weclouddata.name
}


# Attach AppRunner policy to the user
resource "aws_iam_user_policy_attachment" "app_runner" {
  user       = aws_iam_user.weclouddata.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAppRunnerFullAccess"
}
# Attach EC2 Container Registry policy to the user
resource "aws_iam_user_policy_attachment" "countainer_registry" {
  user       = aws_iam_user.weclouddata.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}
# Attach EC2 Container Registry Public policy to the user
resource "aws_iam_user_policy_attachment" "countainer_registry_public" {
  user       = aws_iam_user.weclouddata.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicFullAccess"
}


# Create an ECR repository
resource "aws_ecr_repository" "weclouddata" {
  name                 = "weclouddata-${random_uuid.unique_service_name.result}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}
# Build and push Docker image to ECR
resource "null_resource" "docker_image_to_ecr" {
  depends_on = [aws_ecr_repository.weclouddata]

  provisioner "local-exec" {
    #The key to allow to deploy the image is the buildx, we cannot deploy ARM images to AppRunner, so we need to build the image for amd64
    #This was one the biggest challenges that I had, I was trying to build and deploy  the image for ARM and deploy it to AppRunner, but it was not working
    #However, when I change to amd64 it worked
    #This code was tested in a M3 Macbook  and Github Actions. I'm not sure if it will work in other platforms yet
    command = <<EOF
    #!/bin/bash
    echo "Start:Reading enviroment variables"
    env  AWS_ACCESS_KEY_ID=${aws_iam_access_key.weclouddata.id}
    env  AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.weclouddata.secret}
    echo "End:Reading enviroment variables"


    $(aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.weclouddata.registry_id}.dkr.ecr.us-east-1.amazonaws.com})

    docker buildx build --platform linux/amd64  -t ${aws_ecr_repository.weclouddata.repository_url}:latest .
    docker push ${aws_ecr_repository.weclouddata.repository_url}:latest
    EOF
  }
  triggers = {
    always_run = "${timestamp()}"
  }
}

# Output the ECR repository URL IMAGE TAG
output "aws_image_repository_weclouddata" {
  value = "${aws_ecr_repository.weclouddata.repository_url}:latest"
}

# Output the ECR repository URL
output "aws_ecr_repository_weclouddata" {
  value = aws_ecr_repository.weclouddata.repository_url
}

#We want to have less privileges as possible so we are going to create a new user with only the permissions that we need.
# Output the IAM access key ID
output "access_key_id" {
  value = aws_iam_access_key.weclouddata.id

}
# Output the IAM secret access key
output "secret_access_key" {
  value     = aws_iam_access_key.weclouddata.secret
  sensitive = true
}


################################################################################################################################################


output "random_uuid_unique_service_name" {
  value = random_uuid.unique_service_name.result

}


# Create an IAM role for AppRunner
resource "aws_iam_role" "app_runner" {
  name = "app_runner-weclouddata"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
      },
    ]
  })
}
# Attach AppRunner service policy to the role
resource "aws_iam_role_policy_attachment" "app_runner" {
  role       = aws_iam_role.app_runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}


# Create an AppRunner service
resource "aws_apprunner_service" "weclouddata" {
  service_name = "weclouddata${random_integer.random_integer_service_id.result}"
  depends_on   = [aws_iam_role_policy_attachment.app_runner, null_resource.docker_image_to_ecr]


  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.app_runner.arn
    }
    image_repository {
      image_configuration {
        port = "8080"
      }
      image_identifier      = "${aws_ecr_repository.weclouddata.repository_url}:latest"
      image_repository_type = "ECR"
    }




    auto_deployments_enabled = true
  }

}

# Output the AppRunner service URL
#if you want to use the service url you need to create a dns record, therefore we need to print that
output "apprunner_service_weclouddata" {
  value = "https://${aws_apprunner_service.weclouddata.service_url}"
}



#terraform destroy  -auto-approve
#terraform apply -auto-approve
#terraform output secret_access_key
#git clone https://git-codecommit.us-east-1.amazonaws.com/v1/repos/weclouddata
#aws configure --profile weclouddata
#git config --global credential.helper '!aws codecommit credential-helper $@'
#git config --global credential.UseHttpPath true
#git config --global credential.profile weclouddata

# cd code
# cop
#python3.12  -m venv venv
#source venv/bin/activate
#pip install -r requirements.txt
#uvicorn main:app --reload --host 0.0.0.0 --port 80
