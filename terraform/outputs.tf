output "api_gateway_url" {
  description = "POST images to this URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/upload"
}

output "frontend_url" {
  description = "Open this in a browser (S3 website endpoints are HTTP only)"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "images_bucket_name" {
  value = aws_s3_bucket.images.bucket
}
