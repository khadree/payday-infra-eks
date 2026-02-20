terraform {
  backend "s3" {
    bucket = "payday-demo-s3"
    key    = "remote/terrafrom.tfstate"
    region = "us-east-1"
    # dynamodb_table = "basic-dynamodb-table"
  }
}