# Serverless Image Upload API

Upload an image from a web page and browse everything uploaded so far. Images are
stored in a private S3 bucket, metadata in DynamoDB. Everything is created with Terraform.

**Stack:** S3 (static site + image storage), API Gateway (REST), Lambda (Node.js 22,
one function per route), DynamoDB (on-demand), IAM, CloudWatch Logs, Terraform.

See [docs/architecture.md](docs/architecture.md) for the diagram.

## Project layout

```
terraform/   main.tf, variables.tf, outputs.tf, provider.tf
lambda/      uploadimage.js       (POST /upload, zipped by Terraform)
             listimages.js        (GET /images, zipped by Terraform)
frontend/    index.html.tpl       (template; Terraform injects both API URLs)
```

## How a request flows

**Upload — `POST /upload`**
1. Browser sends `OPTIONS /upload` (CORS preflight). API Gateway answers it with a MOCK integration.
2. Browser sends `POST /upload` with JSON `{ image (base64), fileName, contentType }`.
3. API Gateway invokes `upload_fn` (proxy integration).
4. Lambda validates input, saves `uploads/<uuid>.<ext>` to S3, saves metadata to DynamoDB.
5. Lambda returns `{ message, imageId }` with CORS headers.

**Gallery — `GET /images`**
1. Browser sends `GET /images?limit=24` (a CORS "simple request" — no preflight).
2. API Gateway invokes `list_images_fn` (proxy integration).
3. Lambda `Scan`s the DynamoDB table (up to `limit`, max 50) and, for each item, generates a
   5-minute presigned S3 `GetObject` URL — the images bucket itself is never made public.
4. Lambda returns `{ images: [...], nextCursor }` with CORS headers. `nextCursor` (pass it back
   as `?cursor=`) is `null` once there's nothing left to page through.

## Deploy

Prerequisites: Terraform >= 1.5, AWS CLI configured with a profile (default name `tf-dev`).

```bash
cd terraform
terraform init
terraform apply -var="aws_profile=YOUR_PROFILE"
```

Bucket names are globally unique. If apply fails with `BucketAlreadyExists`, pass your own:
`-var="frontend_bucket_name=..." -var="images_bucket_name=..."`.

Terraform prints `frontend_url` (open it) and `api_gateway_url`.

## Test the API (bash)

```bash
# Upload
curl -X POST "<api_gateway_url>/upload" \
  -H "Content-Type: application/json" \
  -d '{"image":"<base64>","fileName":"test.png","contentType":"image/png"}'

# List
curl "<api_gateway_url>/images?limit=10"
```

On Windows PowerShell use `curl.exe` (plain `curl` is an alias for Invoke-WebRequest and does not accept `-X`).
Then check the S3 bucket for `uploads/...` and the DynamoDB table for the metadata item.

## Limits and design choices

- Max image size 4 MB: Lambda accepts 6 MB request payloads and base64 adds about 33%.
- Allowed types: png, jpeg, gif, webp. IDs are server-generated UUIDs.
- `GET /images` defaults to 20 results per page (`?limit=`, capped at 50) and pages with an
  opaque `?cursor=` token. It reads with a DynamoDB `Scan`, so pages aren't guaranteed to be
  in upload order and this won't scale past a small table — see docs/architecture.md.
- Presigned image URLs returned by `GET /images` expire after 5 minutes.
- The API is public (no auth) with stage throttling (5 req/s, burst 10). Demo only.

## Cleanup

```bash
terraform destroy -var="aws_profile=YOUR_PROFILE"
```

## Known gaps / next steps

Presigned-URL uploads for large files, a GSI so `GET /images` can `Query` in upload order
instead of `Scan`, CloudFront + HTTPS for the frontend, API key or Cognito auth, WAF, remote
Terraform state, CI/CD with GitHub Actions (OIDC), CloudWatch alarms, tests.
