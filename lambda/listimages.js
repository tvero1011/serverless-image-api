// AWS SDK v3 is already included in the Node.js 18+/22 Lambda runtime: no npm install needed.
const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, ScanCommand } = require("@aws-sdk/lib-dynamodb");

// Created OUTSIDE the handler: reused across warm invocations (faster, fewer connections).
const s3 = new S3Client({});
const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const BUCKET_NAME = process.env.BUCKET_NAME;
const TABLE_NAME = process.env.TABLE_NAME;
const DEFAULT_PAGE_SIZE = Number(process.env.PAGE_SIZE || 20);
const MAX_PAGE_SIZE = 50;
const URL_EXPIRY_SECONDS = 300; // presigned GET URLs are valid for 5 minutes

// With Lambda proxy integration, API Gateway does NOT add CORS headers. We must.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "OPTIONS,GET",
};

const respond = (statusCode, payload) => ({
  statusCode,
  headers: CORS_HEADERS,
  body: JSON.stringify(payload),
});

// DynamoDB's LastEvaluatedKey is an object. We hand it to the client as one
// opaque base64 string ("cursor") so nobody outside this file has to know its shape.
const encodeCursor = (key) => Buffer.from(JSON.stringify(key)).toString("base64");
const decodeCursor = (cursor) => {
  try {
    return JSON.parse(Buffer.from(cursor, "base64").toString("utf8"));
  } catch {
    return undefined; // malformed cursor -> just start from the beginning
  }
};

exports.handler = async (event) => {
  try {
    const query = event.queryStringParameters || {};

    let limit = Number.parseInt(query.limit, 10);
    if (!Number.isInteger(limit) || limit < 1) limit = DEFAULT_PAGE_SIZE;
    limit = Math.min(limit, MAX_PAGE_SIZE);

    const exclusiveStartKey = query.cursor ? decodeCursor(query.cursor) : undefined;

    // NOTE: this is a Scan, which reads the table page by page regardless of
    // order. Fine for a demo-sized table. A production version would add a
    // GSI (constant partition key + uploadedAt as sort key) and Query it
    // instead, so pages come back pre-sorted and Scan's per-page read cost
    // goes away. See docs/architecture.md.
    const result = await docClient.send(
      new ScanCommand({
        TableName: TABLE_NAME,
        Limit: limit,
        ExclusiveStartKey: exclusiveStartKey,
      })
    );

    const images = await Promise.all(
      (result.Items || []).map(async (item) => ({
        imageId: item.imageId,
        originalName: item.originalName,
        contentType: item.contentType,
        sizeBytes: item.sizeBytes,
        uploadedAt: item.uploadedAt,
        // The images bucket is private (see main.tf), so instead of a
        // permanent public URL the browser gets a short-lived signed one.
        url: await getSignedUrl(
          s3,
          new GetObjectCommand({ Bucket: BUCKET_NAME, Key: item.s3Key }),
          { expiresIn: URL_EXPIRY_SECONDS }
        ),
      }))
    );

    // Scan does not return items in upload order; sort what we did get.
    // This only orders *within* the current page, not across the whole table
    // -- another reason a GSI is the "real" fix, noted above.
    images.sort((a, b) => (a.uploadedAt < b.uploadedAt ? 1 : -1));

    return respond(200, {
      images,
      nextCursor: result.LastEvaluatedKey ? encodeCursor(result.LastEvaluatedKey) : null,
    });
  } catch (err) {
    // Real details go to CloudWatch only. The client gets a generic message.
    console.error("List images failed:", err);
    return respond(500, { error: "Internal server error" });
  }
};
