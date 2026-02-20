module "vpc" {
  source       = "./modules/vpc"
  vpc_cidr     = var.vpc_cidr
  cluster_name = var.cluster_name
  environment  = var.environment
}

module "eks" {
  source              = "./modules/eks"
  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnets
  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 4
}