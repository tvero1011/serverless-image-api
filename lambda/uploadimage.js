// 1. Modern SDK v3 imports (Built into Node 18)
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

// 2. Initialize Clients
const s3Client = new S3Client({});
const ddbClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(ddbClient);

const BUCKET_NAME = process.env.BUCKET_NAME;
const TABLE_NAME = process.env.TABLE_NAME;

exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);

        // Safety check: Fallback for different frontend naming (data vs image)
        const base64Data = body.image || body.data; 
        const fileName = body.fileName || body.name || `image-${Date.now()}.png`;

        if (!base64Data) {
            throw new Error("No image data found in request body");
        }

        const imageData = Buffer.from(base64Data, 'base64');

        // 3. Upload to S3
        await s3Client.send(new PutObjectCommand({
            Bucket: BUCKET_NAME,
            Key: fileName,
            Body: imageData,
            ContentType: body.contentType || 'image/png'
        }));

        // 4. Store metadata in DynamoDB
        await docClient.send(new PutCommand({
            TableName: TABLE_NAME,
            Item: {
                imageId: fileName,
                uploadedAt: new Date().toISOString()
            }
        }));

        // 5. The Response with full CORS support
        return {
            statusCode: 200,
            headers: {
                "Access-Control-Allow-Origin": "*", // Allows any website to call this API
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "OPTIONS,POST"
            },
            body: JSON.stringify({ message: 'Success!', imageId: fileName }),
        };

    } catch (err) {
        console.error('Error:', err);
        return {
            statusCode: 500,
            headers: { 
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "OPTIONS,POST"
            },
            body: JSON.stringify({ error: err.message }),
        };
    }
};