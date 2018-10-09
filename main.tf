provider "aws" {
  region = "${var.aws_region}"
  access_key  = ""
  secret_key = "" 
}
resource "aws_vpc" "vpc_main" {
  cidr_block = "172.32.0.0/16"
  
  enable_dns_support = true
  enable_dns_hostnames = true
  
  tags {
    Name = "VPC Test"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.vpc_main.id}"
}

resource "aws_route" "internet_access" {
  route_table_id          = "${aws_vpc.vpc_main.main_route_table_id}"
  destination_cidr_block  = "0.0.0.0/0"
  gateway_id              = "${aws_internet_gateway.default.id}"
}

# Create a public subnet to launch our load balancers
resource "aws_subnet" "public" {
  vpc_id                  = "${aws_vpc.vpc_main.id}"
  cidr_block              = "176.32.1.0/24" # 10.0.1.0 - 10.0.1.255 (256)
  map_public_ip_on_launch = true
}

# Create a private subnet to launch our backend instances
resource "aws_subnet" "private" {
  vpc_id                  = "${aws_vpc.vpc_main.id}"
  cidr_block              = "172.32.16.0/20" # 172.32.16.0 - 172.32.16.255 (4096)
  map_public_ip_on_launch = true
}

# A security group for the ELB 
resource "aws_security_group" "elb public"{
  name        = "sec_group_elb_pub"
  description = "Security group for public ELB"
  vpc_id      = "${aws_vpc.vpc_main.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "SG_OPS" {
  name        = "sec_group_Operation"
  description = "Security group for Operations"
  vpc_id      = "${aws_vpc.vpc_main.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH custom port access from anywhere
  ingress {
    from_port   = 65022
    to_port     = 65022
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  # Allow all from private subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_subnet.private.cidr_block}"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#key pair section
resource "aws_key_pair" "auth" {
  key_name   = "default"
  public_key = "${file(var.public_key_path)}"
}

#instance node_app 
module "node_app" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 2
    group_name             = "backend_instance"
    instance_type          = "t2.medium"
}
#instance ansible 
module "ansible_host" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 2
    group_name             = "ansible_instance"
    instance_type          = "t2.medium"
}
module "db_postgress" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 3
    disk_size              = 30
    group_name             = "postgresql"
    instance_type          = "t2.medium"
}

module "db_redis" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 3
    disk_size              = 30
    group_name             = "redis"
    instance_type          = "t2.medium"
}


#ELB backend
resource "aws_elb" "elb_public" {
  name = "elb_public"

  subnets         = ["${aws_subnet.public.id}", "${aws_subnet.private.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${module.backend_api.instance_ids}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/hcm.php"
    interval            = 30
  }
}
resource "aws_elb" "elb_api" {
  name = "elb_api"

  subnets         = ["${aws_subnet.public.id}", "${aws_subnet.private.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${module.elb.instance_ids}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/hcm.php"
    interval            = 30
  }
}

