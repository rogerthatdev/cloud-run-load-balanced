output "frontend_url" {
  value = "http://${google_compute_global_address.default.address}/"
}