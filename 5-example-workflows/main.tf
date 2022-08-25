#------------------------------------------------------------------------
# Vault Learn lab: Audit Device Incident Response with Elasticsearch
#
# Docker container environment configuration for example scenarios
#------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0.0"
}

# -----------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------

# tcp with hostname example:
# export TF_VAR_docker_host="tcp://docker:2345"
variable "docker_host" {
  default = "unix:///var/run/docker.sock"
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------
# Auth method resources
# -----------------------------------------------------------------------

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Example AppRole auth method"
}

resource "vault_auth_backend" "userpass" {
  type        = "userpass"
  path        = "userpass"
  description = "Example Username and password auth method"
}

resource "vault_approle_auth_backend_role" "learn" {
  backend        = vault_auth_backend.approle.path
  role_name      = "learn-role"
  token_policies = ["default", "dev", "prod"]
}

resource "vault_approle_auth_backend_role_secret_id" "id" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.learn.role_name
}

resource "vault_approle_auth_backend_login" "login" {
  backend   = vault_auth_backend.approle.path
  role_id   = vault_approle_auth_backend_role.learn.role_id
  secret_id = vault_approle_auth_backend_role_secret_id.id.secret_id
}

# -----------------------------------------------------------------------
# Secrets engine resources
# -----------------------------------------------------------------------
