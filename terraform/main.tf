############################
# 1. THE WEBSITE (S3)
############################

resource "aws_s3_bucket" "frontend" {
  bucket = "rovnp-portfolio-frontend-9921" 
  force_destroy  = true # Allows deletion of index.html 
}

resource "aws_s3_bucket_public_access_block" "frontend_bpa" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "conf" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend_bpa]

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

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html" 
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/index.html")
}

############################
# 2. THE STORAGE & DB
############################

resource "aws_s3_bucket" "images" {
  bucket = "my-portfolio-images-2026-unique-rovnp" 
  force_destroy  = true # Allows deletion of your uploaded photos
}

resource "aws_dynamodb_table" "db" {
  name         = "ImageMetadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "imageId"

  attribute {
    name = "imageId"
    type = "S"
  }
}

############################
# 3. THE LOGIC (Lambda)
############################

resource "aws_iam_role" "role" {
  name = "lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "policy" {
  role = aws_iam_role.role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Action = ["s3:PutObject"], Effect = "Allow", Resource = "${aws_s3_bucket.images.arn}/*" },
      { Action = ["dynamodb:PutItem"], Effect = "Allow", Resource = aws_dynamodb_table.db.arn },
      { Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Effect = "Allow", Resource = "arn:aws:logs:*:*:*" }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/uploadimage.js"
  output_path = "${path.module}/uploadimage.zip"
}

resource "aws_lambda_function" "fn" {
  function_name    = "upload_fn"
  role             = aws_iam_role.role.arn
  handler          = "uploadimage.handler"
  runtime          = "nodejs18.x"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images.bucket
      TABLE_NAME  = aws_dynamodb_table.db.name
    }
  }
}

############################
# 4. THE API (Gateway + CORS)
############################

resource "aws_api_gateway_rest_api" "api" { name = "UploadAPI" }

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST" 
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.fn.invoke_arn
}

resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    # MUST be wrapped in single quotes inside double quotes: "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'" 
  }
  depends_on = [aws_api_gateway_integration.options_integration]
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# --- FIX START: DEPLOYMENT & STAGE ---

resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Forces a new deployment whenever code or methods change
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.lambda.id,
      aws_api_gateway_method.options.id,
      aws_api_gateway_integration.options_integration.id,
      aws_api_gateway_integration_response.options_integration_response.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda, 
    aws_api_gateway_integration.options_integration
  ]
}

resource "aws_api_gateway_stage" "st" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
}