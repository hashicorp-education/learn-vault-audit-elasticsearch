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

# This provider is expected to be configured through the
# following environment variables:
#
# VAULT_ADDR
# VAULT_TOKEN

provider "vault" {}

# -----------------------------------------------------------------------
# Audit Device Resources
# -----------------------------------------------------------------------
# This is being manually created by the learner for now.
#
# resource "vault_audit" "file_audit_device" {
#   type = "file"
#
#   options = {
#     file_path   = "${path.cwd}../4-vault/log/audit.log"
#     description = "Example file audit device"
#   }
# }

# -----------------------------------------------------------------------
# Auth method resources
# -----------------------------------------------------------------------

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Example AppRole auth method"
}

resource "vault_approle_auth_backend_role" "learn" {
  backend        = vault_auth_backend.approle.path
  role_name      = "learn-token-admin-role"
  token_policies = ["default", "token-admin"]
  description    = "Example AppRole role"
}

resource "vault_approle_auth_backend_role_secret_id" "id" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.learn-token-admin-role.role_name
}

resource "vault_approle_auth_backend_login" "login" {
  backend   = vault_auth_backend.approle.path
  role_id   = vault_approle_auth_backend_role.learn-token-admin-role.role_id
  secret_id = vault_approle_auth_backend_role_secret_id.id.secret_id
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
}

# Create a user, 'admin' with pre-seeded paassword 'superS3cret!'
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

# Create a user, 'student' with pre-seeded password 'ch4ngeMe~'
resource "vault_generic_endpoint" "student" {
  depends_on           = [vault_auth_backend.userpass]
  path                 = "auth/userpass/users/student"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "policies": ["student-secrets"],
  "password": "ch4ngeMe~"
}
EOT
}

# -----------------------------------------------------------------------
# ACL policy resources
# -----------------------------------------------------------------------

# Prometheus Metrics policy
resource "vault_policy" "prometheus" {
  name = "prometheus"

  policy = <<EOT
// Prometheus metrics gathering policy
path "/sys/metrics" {
  capabilities = ["read"]
}
EOT
}

# Token admin policy
# Read token config, create tokens, list auth methods & secrets engines
resource "vault_policy" "token_admin" {
  name = "token-admin"

  policy = <<EOT
# Read default token configuration
path "sys/auth/token/tune" {
  capabilities = [ "read", "sudo" ]
}

# Create and manage tokens (renew, lookup, revoke, etc.)
path "auth/token/*" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}

# List available auth methods
path "sys/auth" {
  capabilities = [ "read" ]
}

# List available secrets engines
path "sys/mounts" {
  capabilities = [ "read" ]
}
EOT
}

# Student secrets policy
resource "vault_policy" "student_secrets" {
  name = "student-secrets"

  policy = <<EOT
# List, create, update, and delete key/value secrets
# at 'api-credentials/student' path.
path "api-credentials/data/student/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Encrypt data with 'payment' key.
path "transit/encrypt/payment" {
  capabilities = ["update"]
}

# Decrypt data with 'payment' key.
path "transit/decrypt/payment" {
  capabilities = ["update"]
}

# Read and list keys under transit secrets engine.
path "transit/*" {
  capabilities = ["read", "list"]
}

# List secrets engines.
path "api-credentials/metadata/*" {
  capabilities = ["list"]
}
EOT
}

# -----------------------------------------------------------------------
# Secrets engine resources
# -----------------------------------------------------------------------

# Provision some static secrets in the KV secrets engine at the path 'kv-v2'

resource "vault_generic_secret" "api-wizard-service" {
  path = "api-credentials/admin/api-wizard"

  data_json = <<EOT
{
  "api-client-key": "api-eyj2LqNPIlgk7M616Tg",
  "api-secret-key": "V9QZ8l6xzhZGkq8jsUjpwvRMIWLRIMGWgnNqSWwT0gU2"
}
EOT
  depends_on = [
    vault_mount.kv-v2
  ]
}

resource "vault_generic_secret" "student_api_key" {
  path = "api-credentials/student/api-key"

  data_json = <<EOT
{
  "api_key":   "A26nYsDuB3Y9GHx2mstmuaPAQJPQjYtE2s5kEsIQ9Nk"
}
EOT
  depends_on = [
    vault_mount.kv-v2
  ]
}

resource "vault_generic_secret" "golden" {
  path = "api-credentials/student/golden"

  data_json = <<EOT
{
  "egg-b64":   "CiAgICAgICAgICAgICAgICAgICAuICAgICAgICAuICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAnL3ltcyAgICAgICAgeW15LycgICAgICAgICAgICAgICAKICAgICAgICAgICAgLW9oSEhISHMgICAgICAgIHlISEhIaG8nICAgICAgICAgICAgCiAgICAgICAgJy9zbUhISEhISEhzICAgICAgICB5SEhISEhILiAgLScgICAgICAgIAogICAgIC0raEhISEhISEhISEhtKyAgICAgICAgeUhISEhISC4gIHNIaCstICAgICAKICAgK21ISEhISEhISEhIaCstICAgICAgICAgIHlISEhISEguICBzSEhISG0rICAgCiAgIHlISEhISEhIZHM6JyAgIC4tICAgICAgICB5SEhISEhILiAgc0hISEhIeSAgIAogICB5SEhISEhoLiAgICc6c2RIeSAgICAgICAgeUhISEhISC4gIHNISEhISHkgICAKICAgeUhISEhIcyAgLmhISEhISHkgICAgICAgIHlISEhISEguICBzSEhISEh5ICAgCiAgIHlISEhISHMgIC5ISEhISEh5ICAgICAgICB5SEhISEhILiAgc0hISEhIeSAgIAogICB5SEhISEhzICAuSEhISEhIbXl5eXl5eXl5bUhISEhISC4gIHNISEhISHkgICAKICAgeUhISEhIcyAgLkhISEhISEhISEhISEhISEhISEhISEguICBzSEhISEh5ICAgCiAgIHlISEhISHMgIC5ISEhISEhISEhISEhISEhISEhISEhILiAgc0hISEhIeSAgIAogICB5SEhISEhzICAuSEhISEhIbXl5eXl5eXl5bUhISEhISC4gIHNISEhISHkgICAKICAgeUhISEhIcyAgLkhISEhISHkgICAgICAgIHlISEhISEguICBzSEhISEh5ICAgCiAgIHlISEhISHMgIC5ISEhISEh5ICAgICAgICB5SEhISEhoJyAgc0hISEhIeSAgIAogICB5SEhISEhzICAuSEhISEhIeSAgICAgICAgeUhkbzonICAgLmhISEhISHkgICAKICAgeUhISEhIcyAgLkhISEhISHkgICAgICAgIC0uICAgJy9zbUhISEhISEh5ICAgCiAgICtkSEhISHMgIC5ISEhISEh5ICAgICAgICAgIC1vaEhISEhISEhISEhkKyAgIAogICAgIC4raEhzICAuSEhISEhIeSAgICAgICAgb21ISEhISEhISEhIaCsuICAgICAKICAgICAgICAnLiAgLkhISEhISHkgICAgICAgIHlISEhISEhIbXM6JyAgICAgICAgCiAgICAgICAgICAgICcraEhISEh5ICAgICAgICB5SEhISGgrLSAgICAgICAgICAgIAogICAgICAgICAgICAgICAnYmxzfCAgICAgICAgeUhkLycgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgIC4gICAgICAgIC4K"
}
EOT
  depends_on = [
    vault_mount.kv-v2
  ]
}

# -----------------------------------------------------------------------
# Specific scenario resources
# -----------------------------------------------------------------------
