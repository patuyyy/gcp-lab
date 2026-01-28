variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-southeast2"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-southeast2-a"
}

variable "backend_image" {
  description = "Backend container image (Artifact Registry)"
  type        = string
}

variable "backend_env" {
  description = "Backend environment variables"
  type        = map(string)
}

variable "frontend_image" {
  description = "Frontend container image"
  type        = string
}
