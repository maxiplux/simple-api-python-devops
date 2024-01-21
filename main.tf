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



resource "aws_iam_user_policy_attachment" "app_runner" {
  user       = aws_iam_user.weclouddata.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAppRunnerFullAccess"
}
resource "aws_iam_user_policy_attachment" "countainer_registry" {
  user       = aws_iam_user.weclouddata.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_user_policy_attachment" "countainer_registry_public" {
  user       = aws_iam_user.weclouddata.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicFullAccess"
}



resource "aws_ecr_repository" "weclouddata" {
  name                 = "weclouddata-${random_uuid.unique_service_name.result}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "null_resource" "docker_image_to_ecr" {
  depends_on = [aws_ecr_repository.weclouddata]

  provisioner "local-exec" {


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


output "aws_image_repository_weclouddata" {
  value = "${aws_ecr_repository.weclouddata.repository_url}:latest"
}


output "aws_ecr_repository_weclouddata" {
  value = aws_ecr_repository.weclouddata.repository_url
}

output "user_name" {
  value = aws_iam_user.weclouddata.name
}

output "access_key_id" {
  value = aws_iam_access_key.weclouddata.id

}

output "secret_access_key" {
  value     = aws_iam_access_key.weclouddata.secret
  sensitive = true
}


################################################################################################################################################


output "random_uuid_unique_service_name" {
  value = random_uuid.unique_service_name.result

}



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
resource "aws_iam_role_policy_attachment" "app_runner" {
  role       = aws_iam_role.app_runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}



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
output "apprunner_service_weclouddata" {
  value = aws_apprunner_service.weclouddata.service_url
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
