# Serverless Image API on AWS

![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?logo=amazonaws)
![Terraform](https://img.shields.io/badge/Terraform-IaC-623CE4?logo=terraform)
![Node.js](https://img.shields.io/badge/Node.js-18-339933?logo=node.js)
![License](https://img.shields.io/badge/License-MIT-green)

Hands-on serverless application demonstrating Infrastructure as Code (IaC) with Terraform and AWS serverless services.

---

# Overview

Serverless Image API is a cloud engineering project that demonstrates how to provision and deploy a serverless image upload application on AWS using Terraform.

The project provisions cloud infrastructure through Infrastructure as Code while exposing a REST API that allows users to upload images. Uploaded files are stored in Amazon S3, metadata is persisted in Amazon DynamoDB, and application execution is monitored using Amazon CloudWatch Logs.

The objective of this project is to strengthen practical experience with AWS serverless architecture, Infrastructure as Code, and cloud-native application development.

---

# Solution Architecture

```text
                    Client
                       │
                       ▼
              Amazon API Gateway
                       │
                       ▼
                AWS Lambda Function
                       │
         ┌─────────────┴─────────────┐
         ▼                           ▼
   Amazon S3                  Amazon DynamoDB
 Image Storage               Image Metadata

                       │
                       ▼
             Amazon CloudWatch Logs

────────────────────────────────────────────

Infrastructure Provisioned with Terraform

• Amazon API Gateway
• AWS Lambda
• Amazon S3
• Amazon DynamoDB
• IAM Roles & Policies
• Amazon CloudWatch Logs
```

*A visual AWS architecture diagram will be added in a future update.*

---

# AWS Services Used

- AWS Lambda
- Amazon API Gateway
- Amazon S3
- Amazon DynamoDB
- IAM Roles & Policies
- Amazon CloudWatch Logs

---

# Technologies

- Terraform
- AWS
- Node.js
- JavaScript
- REST API
- Git
- GitHub

---

# Key Features

- Infrastructure provisioned entirely with Terraform
- Serverless REST API using Amazon API Gateway
- Image upload processing with AWS Lambda
- Object storage using Amazon S3
- Metadata persistence with Amazon DynamoDB
- IAM least-privilege access control
- Centralized application logging with Amazon CloudWatch Logs
- Simple frontend for testing API functionality

---

# Repository Structure

```text
serverless-image-api
│
├── docs/
│   ├── diagram.md
│   └── notes.md
│
├── frontend/
│   └── index.html
│
├── lambda/
│   ├── uploadimage.js
│   ├── utils.js
│   └── uploadimage.zip
│
├── terraform/
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── .terraform.lock.hcl
│
├── .gitignore
└── README.md
```

---

# Skills Demonstrated

- Infrastructure as Code (IaC)
- Terraform
- AWS Lambda
- Amazon API Gateway
- Amazon S3
- Amazon DynamoDB
- IAM
- REST API Development
- Serverless Architecture
- Cloud Automation
- Version Control

---

# Project Status

This project was developed as a hands-on cloud engineering exercise to strengthen practical experience with AWS serverless services and Infrastructure as Code.

The repository demonstrates how cloud infrastructure and application components can be provisioned, managed, and version-controlled using Terraform while applying AWS serverless architectural best practices.

---

# Lessons Learned

Through this project I gained practical experience with:

- Designing serverless applications on AWS
- Provisioning infrastructure using Terraform
- Developing AWS Lambda functions with Node.js
- Building REST APIs using Amazon API Gateway
- Managing object storage with Amazon S3
- Persisting application metadata using Amazon DynamoDB
- Configuring IAM roles following least-privilege principles
- Monitoring serverless applications using Amazon CloudWatch Logs

---

# Future Enhancements

- Professional AWS architecture diagram
- Image resizing and thumbnail generation
- File validation and size restrictions
- Authentication using Amazon Cognito
- GitHub Actions CI/CD pipeline
- CloudFront integration for content delivery

---

# Author

**Rovert Pangan**

AWS Certified Solutions Architect – Associate

Cloud Engineer | Automation Engineer

---

## License

This project is licensed under the MIT License.
