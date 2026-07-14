# 🛠️ AWS Serverless Image Upload: Post-Mortem

## 1. The Error: CORS (Cross-Origin Resource Sharing)
- **Symptom:** Browser console showed "Access to fetch at... has been blocked by CORS policy."
- **The "Why":** Browsers block scripts from one domain (S3) from talking to another (API Gateway) unless the API "waves a green flag." 
- **The Gap:** - The **OPTIONS** (Preflight) request from the browser wasn't being handled by a MOCK integration.
    - The **POST** response from the Lambda was missing the `Access-Control-Allow-Origin` header in its JSON return object.



## 2. The Error: Deployment Deadlock (Terraform)
- **Symptom:** `BadRequestException: Active stages pointing to this deployment must be moved or deleted`.
- **The "Why":** Terraform tried to delete an old API Deployment while the "prod" Stage was still "standing on it." AWS protects active stages from having their underlying code deleted.

## 3. The Solutions
### ✅ Infrastructure (Terraform)
- **MOCK Integration:** Added a dedicated `OPTIONS` method to return a `200 OK` with CORS headers for the preflight check.
- **Lifecycle Rules:** Added `create_before_destroy = true` to the deployment. This tells Terraform to "Build the new one first, then swap the stage, then kill the old one."
- **Triggers:** Used a `sha1` hash of the API resources to force a redeployment whenever the Lambda or API settings change.

### ✅ Backend (Node.js)
- **Lambda Headers:** Updated the `handler` to return a specific `headers` object:
  ```javascript
  headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "OPTIONS,POST",
      "Access-Control-Allow-Headers": "Content-Type"
  }

  ✅ Frontend (HTML/JS)

    Payload Sync: Ensured the JSON keys in index.html (image and fileName) perfectly matched what the Lambda was looking for.

    URL Accuracy: Verified the fetch URL included the /prod/upload path suffix.