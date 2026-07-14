output "api_gateway_url" {
  value = "${aws_api_gateway_stage.st.invoke_url}/upload"
}

output "frontend_url" {
  value = aws_s3_bucket_website_configuration.conf.website_endpoint
}

output "images_bucket_name" {
  value = aws_s3_bucket.images.bucket
}