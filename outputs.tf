output "vpc_id" {
  description = "The ID of the VPC created."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "The IDs of the private subnets created."
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "The IDs of the public subnets created."
  value       = module.vpc.public_subnets
}

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = local.cluster_name
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository."
  value       = aws_ecr_repository.nginx.repository_url
}
