# DevSecOps Infrastructure as Code
# Secure infrastructure deployment with security best practices

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
  
  backend "s3" {
    bucket         = "devsecops-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "DevSecOps"
      ManagedBy   = "Terraform"
      Security    = "High"
    }
  }
}

# VPC with Security Best Practices
module "vpc" {
  source = "./modules/vpc"
  
  environment     = var.environment
  vpc_cidr       = var.vpc_cidr
  azs            = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs
  
  enable_nat_gateway = true
  single_nat_gateway = false
  enable_vpn_gateway = true
  
  tags = local.common_tags
}

# EKS Cluster with Security Hardening
module "eks" {
  source = "./modules/eks"
  
  cluster_name    = "${var.environment}-devsecops-cluster"
  cluster_version = "1.28"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # Security configurations
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
  
  # Node group security
  node_groups = {
    security = {
      desired_capacity = 2
      max_capacity     = 4
      min_capacity     = 1
      
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      
      # Security hardening
      ami_type       = "AL2_x86_64"
      disk_size      = 50
      
      # Security groups
      vpc_security_group_ids = [aws_security_group.node_security_group.id]
      
      # IAM role with minimal permissions
      iam_role_additional_policies = [
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      ]
    }
  }
  
  # Security policies
  cluster_security_group_additional_rules = {
    ingress_nodes_443 = {
      description                = "Node groups to cluster API"
      protocol                  = "tcp"
      port                      = 443
      type                      = "ingress"
      source_node_security_group = true
    }
  }
  
  tags = local.common_tags
}

# Security Groups
resource "aws_security_group" "node_security_group" {
  name_prefix = "${var.environment}-node-sg"
  vpc_id      = module.vpc.vpc_id
  
  # Allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow inbound traffic from cluster
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [module.eks.cluster_security_group_id]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.environment}-node-security-group"
  })
}

# Container Registry with Security Scanning
module "ecr" {
  source = "./modules/ecr"
  
  repository_name = "devsecops-app"
  environment     = var.environment
  
  # Security configurations
  image_tag_mutability = "IMMUTABLE"
  scan_on_push        = true
  
  # Lifecycle policies
  max_image_count = 10
  
  tags = local.common_tags
}

# Secrets Management
module "secrets" {
  source = "./modules/secrets"
  
  environment = var.environment
  
  # Application secrets
  secrets = {
    "app/database" = {
      description = "Database connection credentials"
      type        = "database"
    }
    "app/api" = {
      description = "API keys and tokens"
      type        = "api"
    }
    "app/ssl" = {
      description = "SSL certificates"
      type        = "ssl"
    }
  }
  
  tags = local.common_tags
}

# Monitoring and Logging
module "monitoring" {
  source = "./modules/monitoring"
  
  environment = var.environment
  cluster_id  = module.eks.cluster_id
  
  # Security monitoring
  enable_security_monitoring = true
  enable_audit_logging      = true
  
  # Alerting
  enable_alerts = true
  alert_email   = var.alert_email
  
  tags = local.common_tags
}

# WAF for Application Load Balancer
module "waf" {
  source = "./modules/waf"
  
  environment = var.environment
  
  # WAF rules
  enable_owasp_rules = true
  enable_rate_limiting = true
  enable_geo_blocking = true
  
  # IP reputation lists
  enable_managed_rules = true
  
  tags = local.common_tags
}

# Backup and Disaster Recovery
module "backup" {
  source = "./modules/backup"
  
  environment = var.environment
  
  # Backup plans
  backup_plans = {
    daily = {
      schedule = "cron(0 2 * * ? *)"
      retention = 30
    }
    weekly = {
      schedule = "cron(0 2 ? * SUN *)"
      retention = 90
    }
  }
  
  tags = local.common_tags
}

# Local variables
locals {
  common_tags = {
    Environment = var.environment
    Project     = "DevSecOps"
    ManagedBy   = "Terraform"
    Security    = "High"
    Compliance  = "SOC2"
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "alert_email" {
  description = "Email for security alerts"
  type        = string
  default     = "security@example.com"
}

# Outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}
