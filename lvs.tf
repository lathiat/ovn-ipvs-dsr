provider "openstack" {
# Uses the environment variables by default
}

resource "openstack_compute_keypair_v2" "zlab" {
  name       = "zlab"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "openstack_networking_network_v2" "private" {
  name = "private"
  admin_state_up = "true"
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
  network_id     = openstack_networking_network_v2.private.id
  admin_state_up = "true"
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
  image_name  = "jammy"
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.frontend_port.id
  }
}

resource "openstack_networking_port_v2" "frontend_port" {
  name           = "frontend_port"
  network_id     = openstack_networking_network_v2.private.id
  admin_state_up = "true"
  #allowed_address_pairs {
  #  ip_address = "192.168.21.230"
  #}
  no_security_groups = true
  port_security_enabled = false
}

# Backend Instance (apache2)
resource "openstack_compute_instance_v2" "backend" {
  name        = "backend"
  image_name  = "jammy"
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.backend_port.id
  }
}

resource "openstack_networking_port_v2" "backend_port" {
  name           = "backend_port"
  network_id     = openstack_networking_network_v2.private.id
  admin_state_up = "true"

  #port_security_enabled = false
  #allowed_address_pairs {
  #  ip_address = "192.168.21.230"
  #}

  no_security_groups = true
  port_security_enabled = false
}

# Test Instance (without security group)
resource "openstack_compute_instance_v2" "test_instance" {
  name        = "test"
  image_name  = "jammy"
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.test_port.id
  }
}

resource "openstack_networking_port_v2" "test_port" {
  name           = "test_port"
  network_id     = openstack_networking_network_v2.private.id
  admin_state_up = "true"
  #port_security_enabled = false
  #allowed_address_pairs {
  #  ip_address = "192.168.21.230"
  #}
  no_security_groups = true
  port_security_enabled = false
}

resource "openstack_networking_floatingip_v2" "test_float" {
  pool = "ext_net"
  port_id = openstack_networking_port_v2.test_port.id
}

# Test2 Instance (with security group)
resource "openstack_compute_instance_v2" "test2" {
  name        = "test2"
  image_name  = "jammy"
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.zlab.name

  network {
    port = openstack_networking_port_v2.test2_port.id
  }
}

resource "openstack_networking_port_v2" "test2_port" {
  name           = "test2_port"
  network_id     = openstack_networking_network_v2.private.id
  admin_state_up = "true"
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
  # Wait for the instances to be ready

  triggers = {
    playbook = filesha1("playbook.yml")
    backend = openstack_compute_instance_v2.backend.id
    frontend = openstack_compute_instance_v2.frontend.id
  }

  provisioner "remote-exec" {
    connection {
      host = openstack_compute_instance_v2.frontend.access_ip_v4
      user = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
    }

    inline = ["echo 'connected!'"]
  }

  provisioner "remote-exec" {
    connection {
      host = openstack_compute_instance_v2.backend.access_ip_v4
      user = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
    }

    inline = ["echo 'connected!'"]
  }

  # Run ansible
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.yml playbook.yml"
  }
}
