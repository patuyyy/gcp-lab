resource "google_compute_backend_service" "frontend_backend" {
  name                  = "frontend-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30

  health_checks = [
    google_compute_health_check.frontend_hc.id
  ]

  backend {
    group = google_compute_instance_group_manager.frontend_mig.instance_group
  }
}

resource "google_compute_backend_service" "backend_backend" {
  name                  = "backend-backend"
  protocol              = "HTTP"
  port_name             = "be-port"
  load_balancing_scheme = "EXTERNAL"

  health_checks = [
    google_compute_health_check.backend_hc.id
  ]

  backend {
    group = google_compute_instance_group_manager.backend_mig.instance_group
  }
}

resource "google_compute_url_map" "web_map" {
  name = "decommoir-url-map"

  # default → frontend
  default_service = google_compute_backend_service.frontend_backend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "api-matcher"
  }

  path_matcher {
    name            = "api-matcher"
    default_service = google_compute_backend_service.frontend_backend.id

    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.backend_backend.id
    }
  }
}


resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "decommoir-http-proxy"
  url_map = google_compute_url_map.https_redirect.id
}

resource "google_compute_global_forwarding_rule" "http_forwarding" {
  name                  = "decommoir-http-forwarding"
  target                = google_compute_target_http_proxy.http_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL"
}

resource "google_compute_firewall" "allow_lb_to_frontend" {
  name    = "allow-lb-to-frontend"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["frontend"]
}

resource "google_compute_managed_ssl_certificate" "decommoir_cert" {
  name = "decommoir-ssl-cert"

  managed {
    domains = ["decommoir.online", "www.decommoir.online", "be.decommoir.online"]
  }
}

resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "decommoir-https-proxy"
  url_map          = google_compute_url_map.web_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.decommoir_cert.id]
}

resource "google_compute_global_forwarding_rule" "https_forwarding" {
  name                  = "decommoir-https-forwarding"
  target                = google_compute_target_https_proxy.https_proxy.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}

resource "google_compute_url_map" "https_redirect" {
  name = "http-to-https"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
  
}