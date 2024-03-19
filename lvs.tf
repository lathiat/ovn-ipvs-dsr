# Note: Unfortunately the terraform inventory provider for ansible doesn't seem
# to support workspaces, so only the default workspace works.

variable "stateless" {
  type = bool
  default = true
}

variable "ip_frontend" {
  default = "192.168.21.22"
}

variable "ip_backend" {
  default = "192.168.21.19"
}

variable "ip_test" {
  default = "192.168.21.14"
}

variable "ip_test2" {
  default = "192.168.21.23"
}

variable "ip_vip" {
  default = "192.168.21.43"
}

provider "openstack" {
# Uses the environment variables by default
}

resource "openstack_images_image_v2" "jammy" {
  name             = "jammy"
  image_source_url = "https://cloud-images.ubuntu.com/releases/jammy/release/ubuntu-22.04-server-cloudimg-amd64.img"
  container_format = "bare"
  disk_format      = "qcow2"
}

resource "openstack_compute_keypair_v2" "zlab" {
  name       = "zlab"
  public_key = file("~/.ssh/id_rsa.pub")
}

data "openstack_networking_network_v2" "private" {
  name = "private"
}

data "openstack_networking_subnet_v2" "private_subnet" {
  name = "private_subnet"
}

# openstack provider doesn't support stateless security groups
# or rules for any protocol

# secgroup=$(openstack security group create stateless_all --stateless -f value -c id)
# openstack security group rule create $secgroup --protocol any --ethertype IPv4
# openstack security group rule create $secgroup --protocol any --ethertype IPv6

data "openstack_networking_secgroup_v2" "stateless_all" {
  name = "stateless_all"
}

resource "openstack_networking_secgroup_v2" "test" {
  name = "test"
  description = "Allow all"
}

resource "openstack_networking_secgroup_rule_v2" "test_rule_1" {
  security_group_id = openstack_networking_secgroup_v2.test.id
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
}

resource "openstack_networking_secgroup_rule_v2" "test_rule_2" {
  security_group_id = openstack_networking_secgroup_v2.test.id
  direction = "egress"
  ethertype = "IPv4"
  protocol = "tcp"
}

# VIP

resource "openstack_networking_port_v2" "vip_port" {
  name           = "vip_port"
  network_id     = data.openstack_networking_network_v2.private.id
  admin_state_up = "true"
  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_vip
  }
  #port_security_enabled = false
  #allowed_address_pairs {
  #  ip_address = "192.168.21.230"
  #}
  no_security_groups = true
  port_security_enabled = false
}

# Frontend Instance (keepalived)
resource "openstack_compute_instance_v2" "frontend" {
  name        = "frontend"
  image_id    = openstack_images_image_v2.jammy.id
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.frontend_port.id
  }
}

resource "openstack_networking_port_v2" "frontend_port" {
  name           = "frontend_port"
  network_id     = data.openstack_networking_network_v2.private.id
  admin_state_up = "true"
  mac_address    = "fa:16:3e:0e:cf:c5"

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_frontend
  }

  #no_security_groups = !var.stateless
  #port_security_enabled = var.stateless

  #dynamic "allowed_address_pairs" {
  #  for_each = var.stateless ? [1] : []
  #  content {
  #    ip_address = openstack_networking_port_v2.vip_port.all_fixed_ips[0]
  #  }
  #}

  #security_group_ids = var.stateless ? [openstack_networking_secgroup_v2.stateless_all.id] : []

  no_security_groups = true
  port_security_enabled = false

  #security_group_ids = [openstack_networking_secgroup_v2.stateless_all.id]
  #port_security_enabled = true
  #allowed_address_pairs {
  #  ip_address = openstack_networking_port_v2.vip_port.all_fixed_ips[0]
  #}

}

# Backend Instance (apache2)
resource "openstack_compute_instance_v2" "backend" {
  name        = "backend"
  image_id    = openstack_images_image_v2.jammy.id
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.backend_port.id
  }
}

resource "openstack_networking_port_v2" "backend_port" {
  name           = "backend_port"
  network_id     = data.openstack_networking_network_v2.private.id
  admin_state_up = "true"
  mac_address    = "fa:16:3e:e4:d4:58"
  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_backend
  }

  no_security_groups = !var.stateless
  port_security_enabled = var.stateless

  dynamic "allowed_address_pairs" {
    for_each = var.stateless ? [1] : []
    content {
      ip_address = openstack_networking_port_v2.vip_port.all_fixed_ips[0]
    }
  }

  #security_group_ids = var.stateless ? [openstack_networking_secgroup_v2.stateless_all.id] : []
  security_group_ids = [openstack_networking_secgroup_v2.test.id]
}

# Test Instance (without security group)
resource "openstack_compute_instance_v2" "test_instance" {
  name        = "test"
  image_id    = openstack_images_image_v2.jammy.id
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.test_port.id
  }
}

resource "openstack_networking_port_v2" "test_port" {
  name           = "test_port"
  network_id     = data.openstack_networking_network_v2.private.id
  admin_state_up = "true"
  mac_address    = "fa:16:3e:e8:2f:a6"

  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_test
  }

  no_security_groups = !var.stateless
  port_security_enabled = var.stateless

  #security_group_ids = var.stateless ? [openstack_networking_secgroup_v2.stateless_all.id] : []
  security_group_ids = [openstack_networking_secgroup_v2.test.id]
  #port_security_enabled = true
}

resource "openstack_networking_floatingip_v2" "test_float" {
  pool = "ext_net"
  port_id = openstack_networking_port_v2.test_port.id
}

# Test2 Instance (with security group)
resource "openstack_compute_instance_v2" "test2" {
  name        = "test2"
  image_id    = openstack_images_image_v2.jammy.id
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.test2_port.id
  }
}

resource "openstack_networking_port_v2" "test2_port" {
  name           = "test2_port"
  network_id     = data.openstack_networking_network_v2.private.id
  admin_state_up = "true"
  mac_address    = "fa:16:3e:4a:41:ad"
  fixed_ip {
    subnet_id = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_test2
  }
  security_group_ids = [openstack_networking_secgroup_v2.test.id]
  port_security_enabled = true
}

resource "openstack_networking_floatingip_v2" "test2_float" {
  pool = "ext_net"
  port_id = openstack_networking_port_v2.test2_port.id
}


# Export Ansible inventory
resource "ansible_host" "frontend" {
  name   = openstack_compute_instance_v2.frontend.name
  groups = ["frontend"]
  variables = {
    ansible_ssh_common_args      = "-o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null -W %h:%p -q ubuntu@${openstack_networking_floatingip_v2.test_float.address}\""
    ansible_host                 = openstack_compute_instance_v2.frontend.access_ip_v4
    ansible_user                 = "ubuntu",
    ansible_ssh_private_key_file = "~/.ssh/id_rsa",
    ansible_python_interpreter   = "/usr/bin/python3",
    vip                          = openstack_networking_port_v2.vip_port.all_fixed_ips[0]
  }
}

resource "ansible_host" "backend" {
  name   = openstack_compute_instance_v2.backend.name
  groups = ["backend"]
  variables = {
    ansible_ssh_common_args      = "-o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null -W %h:%p -q ubuntu@${openstack_networking_floatingip_v2.test_float.address}\""
    ansible_host                 = openstack_compute_instance_v2.backend.access_ip_v4
    ansible_user                 = "ubuntu",
    ansible_ssh_private_key_file = "~/.ssh/id_rsa",
    ansible_python_interpreter   = "/usr/bin/python3",
    vip                          = openstack_networking_port_v2.vip_port.all_fixed_ips[0]
  }
}


#resource "ansible_playbook" "playbook" {
#  name = "playbook"
#  playbook = "playbook.yml"
#  replayable = true
#  extra_vars = {
#    vip = openstack_networking_port_v2.vip_port.all_fixed_ips[0]
#  }
#}

# Run Ansible
resource "null_resource" "ansible" {
  triggers = {
    playbook = filesha1("playbook.yml")
    backend = openstack_compute_instance_v2.backend.id
    frontend = openstack_compute_instance_v2.frontend.id
  }

  # Wait until we can SSH to the test instance, which is our ProxyJump to
  # deploy to the other hosts with Ansible
  provisioner "remote-exec" {
    connection {
      host = openstack_networking_floatingip_v2.test_float.address
      user = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
    }

    inline = [ "/usr/bin/cloud-init status --wait" ]
  }

  # Run ansible
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.yml playbook.yml -e wd=${terraform.workspace}"
  }
}
