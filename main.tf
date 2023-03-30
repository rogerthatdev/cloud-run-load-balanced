module "project_services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "13.0.0"
  disable_services_on_destroy = false
  project_id                  = var.project_id
  enable_apis                 = var.enable_apis

  activate_apis = [
    "compute.googleapis.com",
    "run.googleapis.com"
  ]
}

# Run service

resource "google_cloud_run_v2_service" "default" {
  name     = "rogerthat-serverless"
  project  = var.project_id
  location = "us-central1"
  ingress  = "INGRESS_TRAFFIC_ALL"
  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
    service_account = google_service_account.default.email
  }
}

resource "google_service_account" "default" {
  project      = var.project_id
  account_id   = "cloud-runner"
  display_name = "Service Account"
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_v2_service.default.location
  project  = google_cloud_run_v2_service.default.project
  service  = google_cloud_run_v2_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

# Network stuff

# First an endpoint group that is configured to include your Cloud Run service

resource "google_compute_region_network_endpoint_group" "default" {
  project               = var.project_id
  name                  = "rogerthat-endpoint-group"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_run {
    service = google_cloud_run_v2_service.default.name
  }
}

# Next, a backend service that uses that endpoint group as a backend.

resource "google_compute_backend_service" "default" {
  project               = var.project_id
  name                  = "rogerthat-run-backend-service"
  port_name             = "http"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backend {
    group = google_compute_region_network_endpoint_group.default.id
  }
  log_config {
    enable = false
  }
}
# We'll also need an external IP address to assign to the load balancer and serve as a our frontend

resource "google_compute_global_address" "default" {
  project = var.project_id
  name    = "rogerthat-ip"
}

# The URL map is what appears in Console on the Load Balancing page.

resource "google_compute_url_map" "default" {
  project         = var.project_id
  name            = "rogerthat-https-gclb"
  default_service = google_compute_backend_service.default.id
  # Host rules lets you forward requests based on host and path
  # The hosts in this host_rule subscibe to the rules in the corresponding path_matcher block below it
  host_rule {
    hosts        = ["${google_compute_global_address.default.address}"]
    path_matcher = "external-ip"
  }
  path_matcher {
    name            = "external-ip"
    default_service = google_compute_backend_service.default.id
    # Below is what a path rule would look like if we wanted to direct certain requests to a different backend
    # path_rule {
    #   paths = ["/images/*"]
    #   service = "a GCS backend bucket"
    # }
  }
}

resource "google_compute_url_map" "https_redirect" {
  project = var.project_id
  name    = "rogerthat-http-redirect"
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# # HTTP proxy
resource "google_compute_target_http_proxy" "default" {
  project = var.project_id
  name    = "rogerthat-http-proxy"
  url_map = google_compute_url_map.default.id
}

# Add an https proxy
resource "google_compute_target_https_proxy" "default" {
  project = var.project_id
  name    = "rogerthat-https-proxy"
  url_map = google_compute_url_map.default.id

  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# The Google managed SSL cert used for the https proxy
resource "google_compute_managed_ssl_certificate" "default" {
  project = var.project_id
  name    = "rogerthat-ssl-certificate"

  managed {
    domains = ["${var.domain}."]
  }
}

# Global forwarding rule
resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "rogerthat-http-forwarding-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}
