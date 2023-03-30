variable "project_id" {
  type = string
}

variable "enable_apis" {
  type    = bool
  default = true

}

variable "domain" {
  type        = string
  description = "A valid domain name. Its DNS must be updated to an ephemeral ip address known after apply."
}