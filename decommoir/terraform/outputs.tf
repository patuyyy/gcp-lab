output "backend_mig_name" {
  value = google_compute_instance_group_manager.backend_mig.name
}

output "backend_subnet" {
  value = google_compute_subnetwork.private.name
}