#------------------------------------------------------------------------
# Vault Learn lab: Audit Device Incident Response with Elasticsearch
#
# Docker container environment configuration for example scenarios
# plus PostgreSQL container and related configuration
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

variable "postgres_version" {
  default = "15.0-alpine"
}

variable "vault_version" {
  default = "1.12.0"
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
# PostgresSQL resources
# -----------------------------------------------------------------------

resource "docker_image" "postgres" {
  name         = "postgres:${var.postgres_version}"
  keep_locally = true
}

resource "docker_container" "postgres" {
  name     = "learn_lab_postgres"
  image    = docker_image.postgres.repo_digest
  env      = ["POSTGRES_USER=root", "POSTGRES_PASSWORD=rootpassword"]
  hostname = "postgres"
  must_run = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.252"
  }

  // Create role and grant
  provisioner "local-exec" {
    command = "sleep 5;docker exec -i learn_lab_postgres psql -U root -c \"CREATE ROLE \"ro\" NOINHERIT;\" ; docker exec -i learn_lab_postgres psql -U root -c \"GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"ro\";\""
  }

}

# -----------------------------------------------------------------------
# Policy resources
# -----------------------------------------------------------------------

resource "vault_policy" "research" {
  name = "research"

  policy = <<EOT
# Create and manage  auth methods.
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}
EOT
}

resource "vault_policy" "databases" {
  name = "databases"

  policy = <<EOT
# Create and manage  auth methods.
path "postgres/+/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOT
}

resource "vault_policy" "dev_team" {
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
  token_policies = ["default", "research"]
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
  "policies": ["dev-team"],
  "password": "superS3cret!"
}
EOT
}

# Create a user, 'dba'
resource "vault_generic_endpoint" "dba" {
  depends_on           = [vault_auth_backend.userpass]
  path                 = "auth/userpass/users/research"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "policies": ["databases"],
  "password": "Da4ta^Bass"
}
EOT
}

# Create a user, 'research'
resource "vault_generic_endpoint" "research" {
  depends_on           = [vault_auth_backend.userpass]
  path                 = "auth/userpass/users/research"
  ignore_absent_fields = true

  data_json = <<EOT
{
  "policies": ["research"],
  "password": "n0t00@s3cr37"
}
EOT
}

# -----------------------------------------------------------------------
# Secrets engine resources
# -----------------------------------------------------------------------

resource "vault_mount" "api_credentials" {
  path        = "api-credentials"
  type        = "kv-v2"
  description = "Example KV version 2 secrets engine"
}

resource "vault_generic_secret" "api_key" {
  path = "api-credentials/deployment-api-key"

  data_json = <<EOT
{
  "api-client-key": "api-eyj2LqNPIlgk7M616Tg",
  "api-secret-key": "V9QZ8l6xzhZGkq8jsUjpwvRMIWLRIMGWgnNqSWwT0gU2"
}
EOT
  depends_on = [
    vault_mount.api_credentials
  ]

  // Need to wait for secret availability before attempting access, etc.
  provisioner "local-exec" {
    command = "printf 'Waiting for secrets engine ' ; until $(curl --request GET --output /dev/null --silent --head --fail --header 'X-Vault-Token: root' http://localhost:8200/v1/api-credentials/config) ; do printf '.' sleep 5 ; done"
  }
}

resource "vault_generic_secret" "research_credentials" {
  path = "api-credentials/research-credentials"

  data_json = <<EOT
{
  "api-client-key": "api-eZqjuMIe4Du4sCu0x",
  "api-secret-key": "P0x2dguBm67GxdtFD30D8aP6h2kTedc5Xes2YbpG6im8"
}
EOT
  depends_on = [
    vault_mount.api_credentials
  ]

}

resource "vault_mount" "db" {
  path = "postgres"
  type = "database"
  depends_on = [
    docker_container.postgres
  ]
}

resource "vault_database_secret_backend_connection" "postgres" {
  backend       = vault_mount.db.path
  name          = "postgres"
  allowed_roles = ["dev"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@10.42.42.252:5432/postgres?sslmode=disable"
    username       = "root"
    password       = "rootpassword"
  }
  depends_on = [
    docker_container.postgres
  ]
}

resource "vault_database_secret_backend_role" "role" {
  backend             = vault_mount.db.path
  name                = "dev"
  db_name             = vault_database_secret_backend_connection.postgres.name
  creation_statements = ["Q1JFQVRFIFJPTEUgInt7bmFtZX19IiBXSVRIIExPR0lOIFBBU1NXT1JEICd7e3Bhc3N3b3JkfX0nIFZBTElEIFVOVElMICd7e2V4cGlyYXRpb259fScgSU5IRVJJVDtHUkFOVCBybyBUTyAie3tuYW1lfX0iOw=="]
  depends_on = [
    docker_container.postgres
  ]
}

# -----------------------------------------------------------------------
# Token resources
# -----------------------------------------------------------------------

resource "vault_token_auth_backend_role" "dba_token_role" {
  role_name              = "dba"
  allowed_policies       = ["databases"]
  allowed_entity_aliases = ["dba_entity"]
  orphan                 = true
  token_period           = "86400"
  renewable              = true
  token_explicit_max_ttl = "115200"
  path_suffix            = "dba-token"
}

resource "vault_token" "dba_token" {
  role_name = "${vault_token_auth_backend_role.dba_token_role.role_name}"

  policies = ["databases"]

  renewable = true
  ttl = "24h"

  renew_min_lease = 43200
  renew_increment = 86400

  metadata = {
    "purpose" = "Database administration"
  }
  depends_on = [
    vault_token_auth_backend_role.dba_token_role
  ]
}

# -----------------------------------------------------------------------
# Vault client resources
# -----------------------------------------------------------------------

resource "docker_image" "vault" {
  name         = "vault:${var.vault_version}"
  keep_locally = true
}

# List secrets engines OK
resource "docker_container" "vault_client_0" {
  name     = "learn_lab_vault_client_0"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://10.42.42.200:8200", "VAULT_TOKEN=root"]
  command  = ["vault", "secrets", "list"]
  hostname = "vault-client-0"
  must_run = false
  rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.128"
  }
}

# Get K/V secret NOT OK
resource "docker_container" "vault_client_1" {
  name     = "learn_lab_vault_client_1"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://10.42.42.200:8200", "VAULT_TOKEN=bogus"]
  command  = ["vault", "kv", "get", "api-credentials/deployment-api-key"]
  hostname = "vault-client-1"
  must_run = false
  rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.222"
  }
}

# AppRole role access OK
resource "docker_container" "vault_client_2" {
  name     = "learn_lab_vault_client_2"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://10.42.42.200:8200", "VAULT_TOKEN=bogus"]
  command  = ["vault", "read", "auth/approle/role/learn-role"]
  hostname = "vault-client-2"
  must_run = false
  rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.24"
  }
}

# Unwrap token NOT OK
resource "docker_container" "vault_client_3" {
  name     = "learn_lab_vault_client_3"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://10.42.42.200:8200", "VAULT_TOKEN=bogus"]
  command  = ["vault", "unwrap", "hvs.CAESIIQWw1DuWkRbt--MoYMm_fXHMJz4b3klr5CwSWtWwW3RGh4KHGh2cy4ydmU5OTcxOFhWcEo1OWlJWkdhU2hGR1k"]
  hostname = "vault-client-3"
  must_run = false
  rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.111"
  }
}

# Compromised host
resource "docker_container" "vault_client_4" {
  name     = "learn_lab_vault_client_4"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://10.42.42.200:8200", "VAULT_TOKEN=${vault_token.dba_token.client_token}"]
  command  = ["vault", "read", "postgres/creds/dev"]
  hostname = "vault-client-4"
  must_run = false
  rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.199"
  }
  depends_on = [
    vault_database_secret_backend_role.role
  ]
}

# Userpass login NOT OK
resource "docker_container" "vault_client_5" {
  name     = "learn_lab_vault_client_5"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://10.42.42.200:8200"]
  command  = ["vault", "login", "-method=userpass", "username=research", "password=bogus"]
  hostname = "vault-client-5"
  must_run = false
  rm       = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.102"
  }
}
