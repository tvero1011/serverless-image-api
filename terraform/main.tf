############################
# 1. THE WEBSITE (S3 static hosting)
############################

resource "aws_s3_bucket" "frontend" {
  bucket        = var.frontend_bucket_name
  force_destroy = true # lets `terraform destroy` delete index.html too
}

# Public website => we must turn OFF the safety switches, deliberately.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket     = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend] # policy is rejected while block_public_policy = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

# index.html is a TEMPLATE: Terraform injects the real API URL at deploy time,
# so nobody ever copy-pastes the URL by hand again.
locals {
  index_html = templatefile("${path.module}/../frontend/index.html.tpl", {
    api_url = "${aws_api_gateway_stage.prod.invoke_url}/upload"
  })
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content      = local.index_html
  content_type = "text/html"
  etag         = md5(local.index_html) # re-upload whenever the content changes
}

############################
# 2. STORAGE & DATABASE
############################

resource "aws_s3_bucket" "images" {
  bucket        = var.images_bucket_name
  force_destroy = true # lets `terraform destroy` delete uploaded photos
}

# The images bucket must NEVER be public. Only the Lambda writes to it.
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "db" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # no capacity planning, pay per request
  hash_key     = "imageId"

  attribute {
    name = "imageId"
    type = "S"
  }
}

############################
# 3. THE LOGIC (Lambda + IAM + logs)
############################

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14 # otherwise logs are kept (and billed) forever
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  # TRUST policy: WHO may wear this role => the Lambda service
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# PERMISSION policy: WHAT the role may do (least privilege)
resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.db.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# Terraform zips the code for us. The zip is a build artifact: do NOT commit it.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/uploadimage.js"
  output_path = "${path.module}/uploadimage.zip"
}

resource "aws_lambda_function" "fn" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda.arn
  handler          = "uploadimage.handler" # <file name>.<exported function>
  runtime          = "nodejs22.x"
  timeout          = 10  # default is 3s, too tight for a multi-MB upload
  memory_size      = 256 # more memory also means more CPU
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256 # redeploy when code changes

  environment {
    variables = {
      BUCKET_NAME     = aws_s3_bucket.images.bucket
      TABLE_NAME      = aws_dynamodb_table.db.name
      MAX_IMAGE_BYTES = tostring(var.max_image_bytes)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}

############################
# 4. THE API (API Gateway REST + CORS)
############################

resource "aws_api_gateway_rest_api" "api" {
  name = "UploadAPI"
}

resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "upload"
}

# --- POST /upload -> Lambda (proxy integration: Lambda builds the whole HTTP response)
resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "NONE" # public on purpose for the demo; see handbook "known gaps"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST" # API GW always calls Lambda with POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.fn.invoke_arn
}

# --- OPTIONS /upload -> MOCK (answers the browser's CORS "preflight" without touching Lambda)
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.upload.id
  http_method       = aws_api_gateway_method.options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    # Values must be wrapped in single quotes INSIDE the double quotes
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# --- Permission: API Gateway is allowed to invoke ONLY this function, ONLY for POST /upload
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/POST/upload"
}

# --- Deployment + Stage
resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # A deployment is a SNAPSHOT of the API. Terraform will not create a new one
  # unless something in this hash changes.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.upload.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.lambda.id,
      aws_api_gateway_method.options.id,
      aws_api_gateway_integration.options.id,
      aws_api_gateway_method_response.options_200.id,
      aws_api_gateway_integration_response.options.id
    ]))
  }

  # Build the new deployment BEFORE destroying the old one, because the
  # "prod" stage is still pointing at the old one (your deadlock error).
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.options
  ]
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
}

# Basic abuse protection: cap requests/second for every method on the stage.
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
  }
}
