# LocalStack's community EC2 is a mock with no machine behind it, so this
# container stands in as the real host Ansible configures.
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_image" "host" {
  name         = var.host_image
  keep_locally = true
}

resource "docker_container" "host" {
  name     = "taskflow-host"
  image    = docker_image.host.image_id
  command  = ["sleep", "infinity"]
  must_run = true

  networks_advanced {
    name = var.docker_network
  }

  # Lets the host's Docker CLI pull images through the daemon that can reach lab07-registry.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  labels {
    label = "taskflow.lab"
    value = "lab08"
  }
}
