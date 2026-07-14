#############################################################
# Terraform Variables for Image Upload Project
#############################################################

variable "region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

# Prefix for S3 bucket storing uploaded images
variable "s3_bucket_prefix" {
  description = "Prefix for the images S3 bucket"
  type        = string
  default     = "my-images-bucket"
}

# Prefix for S3 bucket hosting the frontend website
variable "frontend_bucket_prefix" {
  description = "Prefix for the frontend S3 bucket"
  type        = string
  default     = "my-frontend-bucket"
}

# DynamoDB table name
variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing image metadata"
  type        = string
  default     = "ImageMetadata"
}

# Lambda function name
variable "lambda_function_name" {
  description = "Name of the Lambda function handling image uploads"
  type        = string
  default     = "upload_image"
}