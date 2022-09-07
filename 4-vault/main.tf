#------------------------------------------------------------------------
# Vault Learn lab: Audit Device Incident Response with Elasticsearch
#
# Docker container environment configuration for Vault
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

variable "vault_version" {
  default = "1.11.3"
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------
# Vault resources
# -----------------------------------------------------------------------

resource "docker_image" "vault" {
  name         = "vault:${var.vault_version}"
  keep_locally = true
}

resource "docker_container" "vault" {
  name     = "vault-openldap-vault"
  image    = docker_image.vault.repo_digest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://0.0.0.0:8200"]
  command  = ["vault", "server", "-dev", "-dev-root-token-id=root", "-dev-listen-address=0.0.0.0:8200"]
  hostname = "vault"
  must_run = true
  capabilities {
    add = ["IPC_LOCK"]
  }
  healthcheck {
    test         = ["CMD", "vault", "status"]
    interval     = "10s"
    timeout      = "2s"
    start_period = "10s"
    retries      = 2
  }
  ports {
    internal = "8200"
    external = "8200"
    protocol = "tcp"
  }
  networks_advanced {
    name         = "learn-vault"
    ipv4_address = "10.42.42.200"
  }
  volumes {
    host_path      = "${path.cwd}/log"
    container_path = "/vault/logs"
  }
  volumes {
    host_path      = "${path.cwd}/data"
    container_path = "/vault/data"
  }
}
