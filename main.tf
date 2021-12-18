variable "aws_region" {
  default = "us-west-2"
}

provider "aws" {
  region          = "${var.aws_region}"
}

resource "null_resource" "lambda_buildstep" {
  triggers = {
    handler = "${base64sha256(file("code/index.js"))}"
    package = "${base64sha256(file("code/package.json"))}"
    build   = "${base64sha256(file("code/build.sh"))}"
  }

  provisioner "local-exec" {
    command = "code/build.sh"
  }
}

data "archive_file" "lambda" {
  source_dir  = "code/"
  output_path = "code/lambda.zip"
  type        = "zip"

  depends_on = [ null_resource.lambda_buildstep ]
}

resource "aws_lambda_function" "lambda" {
  function_name    = "check-key-age"
  role             = "${aws_iam_role.lambda.arn}"
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  filename         = "${data.archive_file.lambda.output_path}"
  source_code_hash = "${data.archive_file.lambda.output_base64sha256}"

  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }
}

resource "aws_iam_role" "lambda" {
  name = "check-key-age-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  inline_policy {
    name   = "allow-sns-publish"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [ "sns:Publish" ],
      "Effect": "Allow",
      "Resource": "${aws_sns_topic.alerts.arn}"
    },
    {
      "Action": [ "iam:ListUsers", "iam:ListAccessKeys" ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
  }
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = "${aws_iam_role.lambda.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_sns_topic" "alerts" {
  name = "check-key-age-alerts"
}

#resource "aws_sns_topic_subscription" "alerts" {
#  topic_arn = aws_sns_topic.alerts.arn
#  protocol  = "email"
#  endpoint  = "email@address"
#}

resource "aws_cloudwatch_event_rule" "alerts" {
  name = "check-key-age"
  schedule_expression = "cron(0 0 5 ? * MON *)"
}

resource "aws_cloudwatch_event_target" "alerts" {
  rule      = aws_cloudwatch_event_rule.alerts.name
  target_id = "lambda"
  arn       = aws_lambda_function.lambda.arn
}

resource "aws_lambda_permission" "alerts" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.lambda.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.alerts.arn}"
}
