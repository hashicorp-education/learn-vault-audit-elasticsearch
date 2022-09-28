#------------------------------------------------------------------------
# Vault Learn lab: Audit Device Incident Response with Elasticsearch
#
# Docker container environment configuration for Elastic Agent
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

# Elasticsearch image version
variable "elasticagent_version" {
  default = "8.3.3"
}

variable "elasticsearch_host" {
  default = "https://10.42.42.100:9200"
}

# Use TF_VAR_fleet_server_service_token environment variable to set this
variable "fleet_server_service_token" {
  default = "none"
}

# Use TF_VAR_fleet_enrollment_token environment variable to set this
variable "fleet_enrollment_token" {
  default = "none"
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------
# Elastic Agent bootstrap phase resources
# -----------------------------------------------------------------------

resource "docker_image" "elastic-agent" {
  name         = "docker.elastic.co/beats/elastic-agent:${var.elasticagent_version}"
  keep_locally = true
}

resource "docker_container" "elastic-agent" {
  name  = "learn_lab_elastic_agent"
  hostname = "elasticagent"
  image = docker_image.elastic-agent.repo_digest
  env   = ["FLEET_SERVER_ENABLE=true",
    "FLEET_ENROLL=1",
    "FLEET_SERVER_ELASTICSEARCH_HOST=${var.elasticsearch_host}",
    "FLEET_SERVER_SERVICE_TOKEN=${var.fleet_server_service_token}",
    "FLEET_SERVER_POLICY_ID=fleet-server-policy",
    "FLEET_SERVER_ELASTICSEARCH_CA=/cert/ca.pem",
    "FLEET_ENROLLMENT_TOKEN=${var.fleet_enrollment_token}"
  ]
  rm    = true
  networks_advanced {
    name         = "learn_lab_network"
    ipv4_address = "10.42.42.130"
  }
  volumes {
    host_path      = "${path.cwd}/cert"
    container_path = "/cert"
  }
}
