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
  }
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
  name                  = "rogerthat-endpoint-group"
  network_endpoint_type = "SERVERLESS"
  region                = "us-central1"
  cloud_run {
    service = google_cloud_run_v2_service.default.name
  }
}

# Next, a backend service that uses that endpoint group as a backend.

resource "google_compute_backend_service" "default" {
  name                  = "rogerthat-run-backend-service"
  port_name             = "http"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  backend {
    group = google_compute_region_network_endpoint_group.default.id
  }
  log_config {
  }
}
# We'll also need an external IP address to assign to the load balancer and serve as a our frontend

resource "google_compute_global_address" "default" {
  name    = "rogerthat-ip"
  project = var.project_id
}

# The URL map is what appears in Console on the Load Balancing page.

resource "google_compute_url_map" "default" {
  name            = "rogerthat-load-balancer"
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

# # HTTP proxy
# resource "google_compute_target_http_proxy" "default" {
#   name    = "rogerthat-http-proxy"
#   url_map = google_compute_url_map.default.id
# }

# # Global forwarding rule
# resource "google_compute_global_forwarding_rule" "http" {
#   name                  = "rogerthat-http-forwarding-rule"
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   port_range            = "80"
#   target                = google_compute_target_http_proxy.default.id
#   ip_address            = google_compute_global_address.default.id
# }
