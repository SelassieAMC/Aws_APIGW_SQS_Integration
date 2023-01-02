terraform {
  cloud {
    organization = "TrainingGA"

    workspaces {
      name = "ApiGW_SQS_Integration"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.31.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_sqs_queue" "queue" {
  name                      = "simple-queue-service_IP"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10

  tags = {
    Environment = "IP"
  }
}

resource "aws_iam_role" "api" {
  name = "my-api-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "apigateway.amazonaws.com"
          },
          "Effect" : "Allow",
          "Sid" : ""
        }
      ]
  })
}

resource "aws_iam_policy" "api" {
  name = "my-api-perms"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents",
            "logs:GetLogEvents",
            "logs:FilterLogEvents"
          ],
          "Resource" : "*"
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "sqs:GetQueueUrl",
            "sqs:ChangeMessageVisibility",
            "sqs:ListDeadLetterSourceQueues",
            "sqs:SendMessageBatch",
            "sqs:PurgeQueue",
            "sqs:ReceiveMessage",
            "sqs:SendMessage",
            "sqs:GetQueueAttributes",
            "sqs:CreateQueue",
            "sqs:ListQueueTags",
            "sqs:ChangeMessageVisibilityBatch",
            "sqs:SetQueueAttributes"
          ],
          "Resource" : "${aws_sqs_queue.queue.arn}"
        },
        {
          "Effect" : "Allow",
          "Action" : "sqs:ListQueues",
          "Resource" : "*"
        }
      ]
  })
}

resource "aws_iam_role_policy_attachment" "api" {
  role       = aws_iam_role.api.name
  policy_arn = aws_iam_policy.api.arn
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "my-sqs-api"
  description = "Manage SQS messages"
}
