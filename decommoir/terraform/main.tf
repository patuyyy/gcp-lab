resource "google_compute_network" "vpc" {
  name                    = "decommoir-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "public-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/24"
}

resource "google_compute_subnetwork" "private" {
  name          = "private-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.1.0/24"
  private_ip_google_access = true
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] 
  
}

resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name   = "cloud-nat"
  router = google_compute_router.nat_router.name
  region = var.region

  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_service_account" "backend_sa" {
  account_id   = "decommoir-backend"
  display_name = "Decommoir Backend Runtime"
}

# Allow pull image from Artifact Registry
resource "google_project_iam_member" "backend_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

locals {
  backend_env_string = join(" ", [
    for k, v in var.backend_env : "-e ${k}=${v}"
  ])
}

resource "google_compute_instance_template" "backend_tpl" {
  name_prefix = "decommoir-backend-"
  machine_type = "e2-micro"

  tags = ["backend"]

  service_account {
    email  = google_service_account.backend_sa.email
    scopes = ["cloud-platform"]
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # NO external IP
  }

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    apt-get update
    apt-get install -y docker.io

    systemctl enable docker
    systemctl start docker

    gcloud auth configure-docker asia-southeast2-docker.pkg.dev --quiet

    docker run -d \
      --restart=always \
      -p 3000:3000 \
      ${local.backend_env_string} \
      ${var.backend_image}
  EOT
}

resource "google_compute_health_check" "backend_hc" {
  name = "backend-hc"

  http_health_check {
    port = 3000
    request_path = "/api/health"
  }
}

resource "google_compute_instance_group_manager" "backend_mig" {
  name               = "backend-mig"
  zone               = var.zone
  base_instance_name = "backend"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.backend_tpl.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.backend_hc.id
    initial_delay_sec = 120
  }

  named_port {
    name = "be-port"
    port = 3000
  }
}

resource "google_compute_firewall" "allow_backend_internal" {
  name    = "allow-backend-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_service_account" "frontend_sa" {
  account_id = "decommoir-frontend"
  display_name = "Decommoir Frontend Runtime"
}

resource "google_project_iam_member" "frontend_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.frontend_sa.email}"
}

resource "google_compute_instance_template" "frontend_tpl" {
  name_prefix  = "decommoir-frontend-"
  machine_type = "e2-micro"

  tags = ["frontend"]

  service_account {
    email  = google_service_account.frontend_sa.email
    scopes = ["cloud-platform"]
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
  }

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    apt-get update
    apt-get install -y docker.io openssh-server

    systemctl enable docker
    systemctl start docker

    systemctl enable ssh
    systemctl start ssh

    gcloud auth configure-docker asia-southeast2-docker.pkg.dev --quiet

    docker run -d \
      --restart=always \
      -p 80:80 \
      ${var.frontend_image}
  EOT
}


resource "google_compute_health_check" "frontend_hc" {
  name = "frontend-hc"

  http_health_check {
    port = 80
    request_path = "/"
  }
}

resource "google_compute_instance_group_manager" "frontend_mig" {
  name               = "frontend-mig"
  zone               = var.zone
  base_instance_name = "frontend"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.frontend_tpl.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.frontend_hc.id
    initial_delay_sec = 120
  }

  named_port {
    name = "http"
    port = 80
  }
}


