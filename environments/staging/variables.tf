variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "project" {
  type = string
}

variable "owner" {
  type = string
}

variable "cost_center" {
  type    = string
  default = "personal"
}

variable "alarm_email" {
  type    = string
  default = ""
}
