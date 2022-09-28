#------------------------------------------------------------------------
# Vault Learn lab: Audit Device Incident Response with Elasticsearch
#
# Docker container environment configuration for Elasticsearch & Kibana
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
variable "elasticsearch_version" {
  default = "8.3.3"
}

# Kibana image version
variable "kibana_version" {
  default = "8.3.3"
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------
# Custom network
# -----------------------------------------------------------------------
resource "docker_network" "learn_vault" {
  name       = "learn-vault"
  attachable = true
  ipam_config { subnet = "10.42.42.0/24" }
}

# -----------------------------------------------------------------------
# Elasticsearch resources
# -----------------------------------------------------------------------

resource "docker_image" "elasticsearch" {
  name         = "docker.elastic.co/elasticsearch/elasticsearch:${var.elasticsearch_version}"
  keep_locally = true
}

resource "docker_container" "elasticsearch" {
  name  = "elasticsearch"
  image = docker_image.elasticsearch.repo_digest
  env   = ["discovery.type=single-node", "ES_JAVA_OPTS=-Xms1g -Xmx1g", "ELASTIC_PASSWORD=2learnVault", "KIBANA_PASSWORD=2learnVault"]
  rm    = true

  ports {
    internal = "9200"
    external = "9200"
    protocol = "tcp"
  }

  ports {
    internal = "9300"
    external = "9300"
    protocol = "tcp"
  }

  networks_advanced {
    name         = "learn-vault"
    ipv4_address = "10.42.42.100"
  }

  // Cosmetic: two ownership changes suppress warnings emitted when creating
  // the enrollment token with elasticsearch-create-enrollment-token
  provisioner "local-exec" {
    command = "docker exec -u 0 elasticsearch chown elasticsearch /usr/share/elasticsearch/config/users"
  }

  provisioner "local-exec" {
    command = "docker exec -u 0 elasticsearch chown elasticsearch /usr/share/elasticsearch/config/users_roles"
  }

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:9200"]
    interval = "5s"
    timeout  = "2s"
    retries  = 4
  }

}

# -----------------------------------------------------------------------
# Kibana resources
# -----------------------------------------------------------------------

resource "docker_image" "kibana" {
  name         = "docker.elastic.co/kibana/kibana:${var.elasticsearch_version}"
  keep_locally = true
}

resource "docker_container" "kibana" {
  name  = "kibana"
  image = docker_image.kibana.repo_digest
  rm    = true

  networks_advanced {
    name         = "learn-vault"
    ipv4_address = "10.42.42.120"
  }

  ports {
    internal = "5601"
    external = "5601"
    protocol = "tcp"
  }

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:5601"]
    interval = "5s"
    timeout  = "2s"
    retries  = 4
  }
}

resource "null_resource" "util" {

  // Need to wait for Elasticsearch container availability before
  // copying the CA certificate to the necessary locations
  // for subsequent steps.
  provisioner "local-exec" {
    command = "printf 'Waiting for Elasticsearch API ' ; until $(curl --output /dev/null --silent --head --fail http://localhost:5601) ; do printf '.' sleep 5 ; done ; sleep 5"
  }

  provisioner "local-exec" {
    command = "docker cp elasticsearch:/usr/share/elasticsearch/config/certs/http_ca.crt ../2-fleet-agent-bootstrap/cert/ca.pem"
  }

  provisioner "local-exec" {
    command = "docker cp elasticsearch:/usr/share/elasticsearch/config/certs/http_ca.crt ../3-enroll-elastic-agent/cert/ca.pem"
  }

  depends_on = [
    docker_container.elasticsearch
  ]

}
