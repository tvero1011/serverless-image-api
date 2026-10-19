# Serverless Image Upload API

[![Terraform checks](https://github.com/tvero1011/serverless-image-api/actions/workflows/terraform.yml/badge.svg)](https://github.com/tvero1011/serverless-image-api/actions/workflows/terraform.yml)

Upload an image from a web page and browse everything uploaded so far. Images are
stored in a private S3 bucket, metadata in DynamoDB. Everything is created with Terraform.

**Stack:** S3 (static site + image storage), API Gateway (REST), Lambda (Node.js 22,
one function per route), DynamoDB (on-demand), IAM, CloudWatch Logs, Terraform,
GitHub Actions (fmt + validate).

See [docs/architecture.md](docs/architecture.md) for the diagram.

## Demo

![Gallery demo](docs/proof/02-gallery-demo.png)

Deployed and tested with Terraform, then destroyed to avoid charges; redeploy with one `terraform apply`.

| Proof | What it shows |
|-------|---------------|
| [Deploy](docs/proof/01-terraform-apply-complete.png) | `terraform apply` completes and prints the outputs (IDs redacted) |
| [XSS fix](docs/proof/03-xss-filename-safe.png) | A file named `x" onload="alert(1)` renders as plain text, no popup |
| [Fake PNG rejected](docs/proof/04-curl-fake-png-rejected.png) | A text file declared as `image/png` is rejected by the magic-byte check |
| [Teardown](docs/proof/05-terraform-destroy-complete.png) | `terraform destroy` removes all 32 resources |

## Project layout

```
terraform/   main.tf, variables.tf, outputs.tf, provider.tf
lambda/      uploadimage.js       (POST /upload, zipped by Terraform)
             listimages.js        (GET /images, zipped by Terraform)
frontend/    index.html.tpl       (template; Terraform injects both API URLs)
docs/        architecture.md, proof/ (screenshots)
.github/     workflows/terraform.yml  (CI: terraform fmt -check + validate)
```

## How a request flows

**Upload — `POST /upload`**
1. Browser sends `OPTIONS /upload` (CORS preflight). API Gateway answers it with a MOCK integration.
2. Browser sends `POST /upload` with JSON `{ image (base64), fileName, contentType }`.
3. API Gateway invokes `upload_fn` (proxy integration).
4. Lambda validates input (size, allowed type, magic bytes), saves `uploads/<uuid>.<ext>` to S3,
   saves metadata to DynamoDB.
5. Lambda returns `{ message, imageId }` with CORS headers.

**Gallery — `GET /images`**
1. Browser sends `GET /images?limit=24` (a CORS "simple request" — no preflight).
2. API Gateway invokes `list_images_fn` (proxy integration).
3. Lambda `Scan`s the DynamoDB table (up to `limit`, max 50) and, for each item, generates a
   5-minute presigned S3 `GetObject` URL — the images bucket itself is never made public.
4. Lambda returns `{ images: [...], nextCursor }` with CORS headers. `nextCursor` (pass it back
   as `?cursor=`) is `null` once there's nothing left to page through.

## Deploy

Prerequisites: Terraform >= 1.5, and an AWS account where you can create S3, API Gateway,
Lambda, DynamoDB, IAM and CloudWatch resources. Use an AWS CLI profile (default name `tf-dev`);
if it's an SSO profile, run `aws sso login --profile YOUR_PROFILE` first.

```bash
cd terraform
terraform init
terraform apply                                   # uses the default profile "tf-dev"
# or: terraform apply -var="aws_profile=YOUR_PROFILE"
```

Bucket names are globally unique, and the defaults in `variables.tf` belong to the original
author, so you will most likely need your own. If apply fails with `BucketAlreadyExists`, pass them:
`-var="frontend_bucket_name=..." -var="images_bucket_name=..."`.

Terraform prints four outputs: `frontend_url` (open it in a browser), `api_gateway_url`
(the upload endpoint, already ending in `/upload`), `list_images_url` (the gallery endpoint,
already ending in `/images`), and `images_bucket_name`.

`frontend_url` is HTTP only (S3 website hosting), so the browser may show "Not secure".

## Test the API

Use the output values as they are; don't append `/upload` or `/images` again.
Run these from the project root, with a small `test.png` in that folder.

**Bash**

```bash
UPLOAD_URL=$(terraform -chdir=terraform output -raw api_gateway_url)
LIST_URL=$(terraform -chdir=terraform output -raw list_images_url)

# Upload (macOS: use `base64 -i test.png` instead of `base64 -w0 test.png`)
B64=$(base64 -w0 test.png)
printf '{"image":"%s","fileName":"test.png","contentType":"image/png"}' "$B64" \
  | curl -X POST "$UPLOAD_URL" -H "Content-Type: application/json" -d @-

# List
curl "$LIST_URL?limit=10"
```

**PowerShell**

```powershell
$url  = terraform -chdir=terraform output -raw api_gateway_url
$list = terraform -chdir=terraform output -raw list_images_url

# Upload
$b64  = [Convert]::ToBase64String([IO.File]::ReadAllBytes("test.png"))
$body = @{ image = $b64; fileName = "test.png"; contentType = "image/png" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body

# List
Invoke-RestMethod "${list}?limit=10"
```

Then check the S3 bucket for `uploads/...` and the DynamoDB table for the metadata item.

**Negative test:** a text file declared as `image/png` is rejected with `400` and
`File content does not match the declared contentType`.

```bash
# Bash
FAKE=$(printf 'this is not an image' | base64 -w0)
printf '{"image":"%s","fileName":"fake.png","contentType":"image/png"}' "$FAKE" \
  | curl -X POST "$UPLOAD_URL" -H "Content-Type: application/json" -d @-
```

```powershell
# PowerShell (reuses $url from above)
$fake = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("this is not an image"))
$body = @{ image = $fake; fileName = "fake.png"; contentType = "image/png" } | ConvertTo-Json
try { Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body } catch { $_.ErrorDetails.Message }
```

## Limits and design choices

- Max image size 4 MB: Lambda accepts 6 MB request payloads and base64 adds about 33%.
- Allowed types: png, jpeg, gif, webp. The file's leading bytes (magic bytes) are checked
  against the declared type, so a renamed text file is rejected. Non-object request bodies
  return `400`. IDs are server-generated UUIDs.
- The gallery builds its DOM with safe DOM APIs, so filenames are always shown as text and
  never interpreted as HTML.
- `GET /images` defaults to 20 results per page (`?limit=`, capped at 50) and pages with an
  opaque `?cursor=` token. It reads with a DynamoDB `Scan`, so pages aren't guaranteed to be
  in upload order and this won't scale past a small table — see docs/architecture.md.
- Presigned image URLs returned by `GET /images` expire after 5 minutes.
- The API is public (no auth) with stage throttling (5 req/s, burst 10). Demo only.
- Each Lambda has its own least-privilege IAM role: the upload function can only write,
  the list function can only read.

## CI

GitHub Actions runs `terraform fmt -check` and `terraform validate` on every push and pull
request (`.github/workflows/terraform.yml`). It needs no AWS credentials and does not deploy
anything; deployment is manual for now.

## Cleanup

```bash
cd terraform
terraform destroy                                 # or add -var="aws_profile=YOUR_PROFILE"
```

Cost: at demo scale this sits at or near the AWS free tier (Lambda, API Gateway, DynamoDB
on-demand, small S3 usage), but nothing here should stay running. Run `terraform destroy`
when you're done. The images bucket uses `force_destroy`, so uploaded test images are deleted too.

## Troubleshooting

- **`ResourceAlreadyExistsException` for a CloudWatch log group:** Lambda auto-creates a log
  group if it runs before Terraform manages one. Delete the stale groups, then apply again:
  ```bash
  aws logs delete-log-group --log-group-name /aws/lambda/upload_fn
  aws logs delete-log-group --log-group-name /aws/lambda/list_images_fn
  ```
- **`Token has expired` (SSO profile):** run `aws sso login --profile YOUR_PROFILE`.
- **`BucketAlreadyExists`:** pick your own bucket names (see Deploy).
- **Broken thumbnails in the gallery:** presigned links expire after 5 minutes; click Refresh.

## Known gaps

- **No authentication:** the API is open to anyone with the URL. Next step: API key or Cognito.
- **HTTP-only frontend:** S3 website hosting has no HTTPS. Next step: CloudFront.
- **Wildcard CORS:** responses allow any origin. Should be restricted to the frontend's origin.
- **Orphaned S3 object:** if the DynamoDB write fails after the S3 upload succeeds, the image
  stays in S3 with no metadata. Fix: clean up on failure, or a periodic reconciliation job.
- **`Scan` instead of `Query`:** a GSI with a constant partition key and `uploadedAt` as the
  sort key would give upload-ordered results that scale.
- **Local Terraform state:** fine for one person; a team would use an S3 backend with locking.
- **No automated application tests yet.** CI covers Terraform formatting and validation only.

**Next steps:** CloudFront + HTTPS for the frontend, Cognito auth, WAF, presigned-URL uploads
for large files, remote Terraform state, automated deployment with GitHub Actions (OIDC),
CloudWatch alarms.
