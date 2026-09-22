variable "region" {
  description = "AWS region where everything is created"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile Terraform uses to authenticate"
  type        = string
  default     = "tf-dev"
}

variable "project_name" {
  description = "Prefix used to name IAM roles, API, etc."
  type        = string
  default     = "image-upload"
}

# S3 bucket names are GLOBALLY unique across all AWS accounts.
variable "frontend_bucket_name" {
  description = "Globally unique name of the bucket hosting index.html"
  type        = string
  default     = "rovnp-portfolio-frontend-9921"
}

variable "images_bucket_name" {
  description = "Globally unique name of the bucket storing uploaded images"
  type        = string
  default     = "my-portfolio-images-2026-unique-rovnp"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table storing image metadata"
  type        = string
  default     = "ImageMetadata"
}

variable "lambda_function_name" {
  description = "Name of the upload Lambda function"
  type        = string
  default     = "upload_fn"
}

variable "max_image_bytes" {
  description = "Max decoded image size. Lambda's 6 MB request limit and base64's ~33% overhead mean ~4 MB is the safe ceiling."
  type        = number
  default     = 4194304
}

variable "list_lambda_function_name" {
  description = "Name of the GET /images Lambda function"
  type        = string
  default     = "list_images_fn"
}

variable "images_page_size" {
  description = "Default number of images returned per GET /images call (client can override with ?limit=, capped at 50 in the Lambda)"
  type        = number
  default     = 20
}
