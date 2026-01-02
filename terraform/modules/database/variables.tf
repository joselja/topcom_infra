variable "name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "db_sg_id" { type = string }

variable "db_name" { type = string }
variable "db_username" { type = string }

variable "min_acu" { type = number }
variable "max_acu" { type = number }