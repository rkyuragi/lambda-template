data "aws_caller_identity" "caller" {}

locals {
  account_id      = data.aws_caller_identity.caller.account_id
  default_bus_arn = "arn:aws:events:${var.region}:${local.account_id}:event-bus/default"
}

