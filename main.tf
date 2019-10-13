provider "aws" {
  region = "eu-west-2"
}

resource "aws_instance" "example" {
  ami = "ami-0be057a22c63962cb"
  instance_type = "t2.micro"
  tags = {
    Name = "terraform-example"
  }
}