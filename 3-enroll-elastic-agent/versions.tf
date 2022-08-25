terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.20.2"
    }
  }
  required_version = ">= 1.0.0"
}
