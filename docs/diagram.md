Serverless Image Upload API – Architecture Diagram
          +-------------------+
          |   API Gateway     |
          |  POST /upload     |
          +---------+---------+
                    |
                    v
          +-------------------+
          |     Lambda        |
          | UploadImageLambda |
          +---------+---------+
            |             |
            v             v
     +-----------+   +-----------+
     |   S3      |   | DynamoDB  |
     |  Images   |   | Metadata  |
     +-----------+   +-----------+

Explanation:

API Gateway → exposes REST endpoint /upload
Lambda → processes incoming requests, decodes base64, uploads image to S3, and writes metadata to DynamoDB
S3 → stores the uploaded images
DynamoDB → stores metadata (imageId, uploadedAt)
CloudWatch → Lambda logs for monitoring (optional, not shown in diagram)