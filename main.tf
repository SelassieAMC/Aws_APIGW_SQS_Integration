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
      version = "~>4.48.0"
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

resource "aws_api_gateway_method" "post_message" {
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_rest_api.api.root_resource_id
  api_key_required     = false
  http_method          = "POST"
  authorization        = "NONE"
  depends_on = [ aws_api_gateway_rest_api.api ]
}

resource "aws_api_gateway_method" "get_messages" {
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_rest_api.api.root_resource_id
  api_key_required     = false
  http_method          = "GET"
  authorization        = "NONE"
  depends_on = [ aws_api_gateway_rest_api.api ]
}

#query messages
resource "aws_api_gateway_integration" "get_messages" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = "GET"
  type                    = "AWS"
  integration_http_method = "GET"
  passthrough_behavior    = "NEVER"
  credentials             = aws_iam_role.api.arn
  uri                     = "arn:aws:apigateway:us-east-1:sqs:path/${aws_sqs_queue.queue.name}"#/?Action=ReceiveMessage&MaxNumberOfMessages=5&VisibilityTimeout=15&AttributeName=All&Version=2012-11-05"
  
  request_parameters = {
    "integration.request.querystring.Action"="'ReceiveMessage'"
    "integration.request.querystring.MaxNumberOfMessages"="'5'"
    "integration.request.querystring.VisibilityTimeout"="'15'"
    "integration.request.querystring.AttributeName"="'All'"
    "integration.request.querystring.Version"="'2012-11-05'"
  }

  request_templates = {
    "application/json" = ""
  }

  depends_on = [ aws_api_gateway_method.get_messages ]
}

#forward records into SQS
resource "aws_api_gateway_integration" "post_message" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = "POST"
  type                    = "AWS"
  integration_http_method = "POST"
  passthrough_behavior    = "NEVER"
  credentials             = aws_iam_role.api.arn
  uri                     = "arn:aws:apigateway:us-east-1:sqs:path/${aws_sqs_queue.queue.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"
  }

  depends_on = [ aws_api_gateway_method.post_message ]
}

#handler for post success responses
resource "aws_api_gateway_integration_response" "successResponse" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_rest_api.api.root_resource_id
  http_method       = aws_api_gateway_method.post_message.http_method
  status_code       = aws_api_gateway_method_response.successResponse.status_code
  selection_pattern = "^2[0-9][0-9]" // regex pattern for any 200 message that comes back from SQS

  response_templates = {
    "application/json" = "{\"message\": \"Message queued!\"}"
  }

  depends_on = [aws_api_gateway_integration.post_message]
}

resource "aws_api_gateway_method_response" "successResponse" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.post_message.http_method
  status_code = 200

  response_models = {
    "application/json" = "Empty"
  }
}

#handler for get success responses
resource "aws_api_gateway_integration_response" "getMessagesResponse" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_rest_api.api.root_resource_id
  http_method       = aws_api_gateway_method.get_messages.http_method
  status_code       = aws_api_gateway_method_response.getMessageSuccessResponse.status_code
  selection_pattern = "^2[0-9][0-9]" // regex pattern for any 200 message that comes back from SQS

  depends_on = [aws_api_gateway_integration.get_messages]
}

resource "aws_api_gateway_method_response" "getMessageSuccessResponse" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_rest_api.api.root_resource_id
  http_method = aws_api_gateway_method.get_messages.http_method
  status_code = 200

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_description  = "Deployed at ${timestamp()}"
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.api.id,
      aws_api_gateway_method.post_message.id,
      aws_api_gateway_integration.post_message.id,
      aws_api_gateway_method.get_messages.id,
      aws_api_gateway_integration.get_messages.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "dev"
}
