# Serverless Image Upload API

A lightweight serverless API for uploading images, storing them in S3, and saving metadata in DynamoDB. Built using AWS Free Tier-compatible services.

## Features

- POST `/upload` → Upload image (base64) to S3
- DynamoDB stores metadata: `imageId` and `uploadedAt`
- Fully serverless: Lambda + API Gateway + S3 + DynamoDB
- Cost-friendly, free-tier compatible
- Demo-ready for portfolio

## Architecture

![Architecture Diagram](./docs/architecture-diagram.png)

## Technologies

- AWS Lambda (Node.js 18)
- AWS API Gateway
- AWS S3
- AWS DynamoDB
- AWS IAM & CloudWatch
- Terraform (optional infrastructure automation)

## Installation & Deployment

1. Clone repository
```bash
git clone https://github.com/<your-username>/serverless-image-api.git
cd serverless-image-api

2. Install dependencies (Lambda code)
cd lambda
npm init -y
npm install aws-sdk


3. Deploy manually:
Create S3 bucket (free tier)
Create DynamoDB table ImageMetadata (on-demand)
Create IAM role for Lambda
Create Lambda function UploadImageLambda and upload uploadImage.js
Connect API Gateway POST /upload → Lambda

4. Optional Terraform deployment:
cd terraform
terraform init
terraform apply

5. Testing (CLI - powershell)
curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/upload \
-H "Content-Type: application/json" \
-d '{"name":"test.png","data":"<base64-encoded-data>"}'

Check S3 bucket for uploaded file and DynamoDB for metadata.

6. Cleanup (Free Tier)
After demo/testing:
Delete S3 bucket
Delete DynamoDB table
Delete Lambda function
Delete API Gateway
This ensures zero AWS cost.
