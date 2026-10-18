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

// Allow-list of accepted types. The claimed type is also checked against the
// file's first bytes (SIGNATURES below), so a renamed non-image is rejected.
const ALLOWED_TYPES = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
};

// "Magic bytes": the fixed byte pattern every real file of that type starts with.
const SIGNATURES = {
  "image/png": (b) =>
    b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  "image/jpeg": (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  "image/gif": (b) => ["GIF87a", "GIF89a"].includes(b.subarray(0, 6).toString("latin1")),
  "image/webp": (b) =>
    b.subarray(0, 4).toString("latin1") === "RIFF" &&
    b.subarray(8, 12).toString("latin1") === "WEBP",
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
    if (body === null || typeof body !== "object") {
      throw new ValidationError("Request body must be a JSON object");
    }

    const { image, fileName, contentType } = body;

    if (typeof image !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(image)) {
      throw new ValidationError("'image' must be a base64 string");
    }
    if (typeof contentType !== "string" || !Object.hasOwn(ALLOWED_TYPES, contentType)) {
      throw new ValidationError("Unsupported contentType. Allowed: " + Object.keys(ALLOWED_TYPES).join(", "));
    }
    const extension = ALLOWED_TYPES[contentType];

    const imageData = Buffer.from(image, "base64");
    if (imageData.length === 0 || imageData.length > MAX_BYTES) {
      throw new ValidationError("Image must be between 1 byte and " + MAX_BYTES + " bytes");
    }
    if (!SIGNATURES[contentType](imageData)) {
      throw new ValidationError("File content does not match the declared contentType");
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
