# -----------------------------------------------------------------------------
# Bedrock Agent Module - CodeBuild for Terraform Execution
# -----------------------------------------------------------------------------

resource "aws_codebuild_project" "terraform_executor" {
  name          = "${local.resource_prefix}-executor"
  description   = "Executes Terraform operations (plan, apply, destroy) for the Bedrock Agent"
  build_timeout = 60 # 60 minutes max
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "TF_IN_AUTOMATION"
      value = "true"
    }

    environment_variable {
      name  = "TF_INPUT"
      value = "false"
    }

    environment_variable {
      name  = "TERRAFORM_VERSION"
      value = var.terraform_version
    }

    environment_variable {
      name  = "TERRAFORM_BUCKET"
      value = aws_s3_bucket.terraform_files.id
    }

    environment_variable {
      name  = "STATE_BUCKET"
      value = aws_s3_bucket.output_docs.id
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.resource_prefix}-executor"
      stream_name = "build-log"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOF
      version: 0.2

      env:
        variables:
          TF_IN_AUTOMATION: "true"
          TF_INPUT: "false"

      phases:
        install:
          runtime-versions:
            python: 3.11
          commands:
            - echo "Installing Terraform $TERRAFORM_VERSION..."
            - curl -LO "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
            - unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
            - mv terraform /usr/local/bin/
            - terraform version

        pre_build:
          commands:
            - echo "Downloading Terraform files from S3..."
            - aws s3 sync "s3://$TERRAFORM_BUCKET/terraform/" ./terraform/
            - cd terraform
            - echo "Initializing Terraform..."
            - terraform init -input=false -no-color

        build:
          commands:
            - cd terraform
            - echo "Running Terraform operation: $TF_OPERATION"
            - |
              case "$TF_OPERATION" in
                "plan")
                  terraform plan -input=false -no-color -out=tfplan
                  terraform show -json tfplan > plan.json
                  ;;
                "apply")
                  if [ "$TF_AUTO_APPROVE" = "true" ]; then
                    terraform apply -input=false -no-color -auto-approve
                    terraform output -json > outputs.json
                  else
                    echo "ERROR: auto_approve must be true for apply operation"
                    exit 1
                  fi
                  ;;
                "destroy")
                  if [ "$TF_AUTO_APPROVE" = "true" ]; then
                    terraform destroy -input=false -no-color -auto-approve
                  else
                    echo "ERROR: auto_approve must be true for destroy operation"
                    exit 1
                  fi
                  ;;
                "validate")
                  terraform validate -no-color
                  ;;
                "output")
                  terraform output -json
                  ;;
                "state")
                  terraform state list
                  ;;
                *)
                  echo "Unknown operation: $TF_OPERATION"
                  exit 1
                  ;;
              esac

        post_build:
          commands:
            - cd terraform
            - echo "Uploading results to S3..."
            - |
              if [ -f plan.json ]; then
                aws s3 cp plan.json "s3://$STATE_BUCKET/terraform/plan.json"
              fi
            - |
              if [ -f outputs.json ]; then
                aws s3 cp outputs.json "s3://$STATE_BUCKET/terraform/outputs.json"
              fi
            - |
              if [ -f terraform.tfstate ]; then
                aws s3 cp terraform.tfstate "s3://$STATE_BUCKET/terraform/terraform.tfstate"
              fi
            - echo "Operation completed: $TF_OPERATION"

      cache:
        paths:
          - '/root/.terraform.d/plugin-cache/**/*'
    EOF
  }

  cache {
    type = "NO_CACHE"
  }

  tags = var.tags
}

# CloudWatch Log Group for CodeBuild
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.resource_prefix}-executor"
  retention_in_days = 14
  tags              = var.tags
}
