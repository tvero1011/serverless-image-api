// AWS SDK v3 is already included in the Node.js 18+/22 Lambda runtime: no npm install needed.
const crypto = require("crypto");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

// Created OUTSIDE the handler: reused across warm invocations (faster, fewer connections).
const s3 = new S3Client({});
const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const BUCKET_NAME = process.env.BUCKET_NAME;
const TABLE_NAME = process.env.TABLE_NAME;
const MAX_BYTES = Number(process.env.MAX_IMAGE_BYTES || 4 * 1024 * 1024);

// Allow-list: we never trust the client's content type or file extension.
const ALLOWED_TYPES = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
};

// With Lambda proxy integration, API Gateway does NOT add CORS headers. We must.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "OPTIONS,POST",
};

class ValidationError extends Error {}

const respond = (statusCode, payload) => ({
  statusCode,
  headers: CORS_HEADERS,
  body: JSON.stringify(payload),
});

exports.handler = async (event) => {
  try {
    // 1. Parse and validate the request (bad input = client's fault = 4xx)
    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      throw new ValidationError("Request body must be valid JSON");
    }

    const { image, fileName, contentType } = body;

    if (typeof image !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(image)) {
      throw new ValidationError("'image' must be a base64 string");
    }
    const extension = ALLOWED_TYPES[contentType];
    if (!extension) {
      throw new ValidationError("Unsupported contentType. Allowed: " + Object.keys(ALLOWED_TYPES).join(", "));
    }

    const imageData = Buffer.from(image, "base64");
    if (imageData.length === 0 || imageData.length > MAX_BYTES) {
      throw new ValidationError("Image must be between 1 byte and " + MAX_BYTES + " bytes");
    }

    // 2. Server-generated ID: no overwrites, no path tricks like "../../x"
    const imageId = crypto.randomUUID();
    const s3Key = "uploads/" + imageId + "." + extension;
    const originalName = String(fileName || "unnamed").split(/[\\/]/).pop().slice(0, 100);

    // 3. Store the file in S3
    await s3.send(
      new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: s3Key,
        Body: imageData,
        ContentType: contentType,
      })
    );

    // 4. Store the metadata in DynamoDB
    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          imageId,
          s3Key,
          originalName,
          contentType,
          sizeBytes: imageData.length,
          uploadedAt: new Date().toISOString(),
        },
      })
    );

    return respond(200, { message: "Success!", imageId });
  } catch (err) {
    if (err instanceof ValidationError) {
      return respond(400, { error: err.message });
    }
    // Real details go to CloudWatch only. The client gets a generic message.
    console.error("Upload failed:", err);
    return respond(500, { error: "Internal server error" });
  }
};
