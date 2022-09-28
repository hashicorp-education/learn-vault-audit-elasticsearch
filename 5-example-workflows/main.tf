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

variable "curl_version" {
  default = "7.84.0"
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# Vault provider is expected to be configured through the
# following environment variables:
#
# VAULT_ADDR
# VAULT_TOKEN

provider "vault" {}

# -----------------------------------------------------------------------
# Audit Device Resources
# -----------------------------------------------------------------------

/*

resource "vault_audit" "file_audit_device" {
  type = "file"
  path  = "file"

  options = {
    file_path   = "/vault/logs/vault-audit.log"
    description = "File audit device"
  }
}

resource "vault_audit" "socket_audit_device" {
  type = "socket"
  path  = "socket_elastic_agent"

  options = {
    address     = "10.42.42.130:9007"
    socket_type = "tcp"
    description = "Socket audit device for Elastic Agent"
  }
}

*/

# -----------------------------------------------------------------------
# Policy resources
# -----------------------------------------------------------------------

resource "vault_policy" "admins" {
  name = "dev-team"

  policy = <<EOT
# Create and manage  auth methods.
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List auth methods.
path "sys/auth" {
  capabilities = ["read"]
}

# Create and manage tokens.
path "/auth/token/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

# Create and manage ACL policies.
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List ACL policies.
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Create and manage secrets engines.
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List secrets engines.
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# List, create, update, and delete key/value secrets at api-credentials.
path "api-credentials/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage transit secrets engine.
path "transit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Read Vault health status.
path "sys/health" {
  capabilities = ["read", "sudo"]
}
EOT
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

# Create a user, 'admin'
resource "vault_generic_endpoint" "admin" {
  depends_on           = [vault_auth_backend.userpass]
  path                 = "auth/userpass/users/admin"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "policies": ["admins"],
  "password": "superS3cret!"
}
EOT
}

# -----------------------------------------------------------------------
# Secrets engine resources
# -----------------------------------------------------------------------

resource "vault_mount" "kv_v2" {
  path        = "kv-v2"
  type        = "kv-v2"
  description = "Example KV version 2 secrets engine"
}

resource "vault_generic_secret" "api_key" {
  path = "kv-v2/deployment-api-key"
  data_json = <<EOT
{
  "access-key": "ea5b3f004d57d48e69ff581798ec0399",
  "secret-key": "4d469453a1ec37ea5888663ce24f0aeff8b72058cb9a68be8134b49b9d93010a"
}
EOT

  // Need to wait for secret availability before attempting access, etc.
  provisioner "local-exec" {
    command = "printf 'Waiting for secrets engine ' ; until $(curl --request GET --output /dev/null --silent --head --fail --header 'X-Vault-Token: root' http://localhost:8200/v1/kv-v2/config) ; do printf '.' sleep 5 ; done ; sleep 5"
  }
}

# -----------------------------------------------------------------------
# Client resources
# -----------------------------------------------------------------------

resource "docker_image" "curl" {
  name         = "curlimages/curl:${var.curl_version}"
  keep_locally = true
}

resource "docker_container" "curl" {
  name     = "learn_lab_vault_client"
  image    = docker_image.curl.repo_digest
  command  = ["curl", "--silent", "--header 'X-Vault-Token: root'", "http://10.42.42.200:8200/v1/sys/mounts"]
  hostname = "vault-client-1"
  must_run = false
  # rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.128"
  }

}

resource "docker_container" "curl2" {
  name     = "learn_lab_vault_client_2"
  image    = docker_image.curl.repo_digest
  command  = ["curl", "--silent", "--header 'X-Vault-Token: nope'", "http://10.42.42.200:8200/v1/kv-v2/data/deployment-api-key?version=1"]
  hostname = "vault-client-2"
  must_run = false
  # rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.50"
  }

}
