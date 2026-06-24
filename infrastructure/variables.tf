variable "db_password" {
  description = "The password for the RDS database"
  type        = string
  sensitive   = true # This prevents the password from printing to your terminal logs
}