locals {
  ubuntu_image = "ibm-ubuntu-18-04-1-minimal-amd64-2"
  user_data_vsi_file = "${path.module}/config/user-data-vsi.sh"
  user_data_vsi = data.local_file.user_data_vsi.content
  resource_group_id = var.resource_group_id
}

resource null_resource print-names {
  provisioner "local-exec" {
    command = "echo 'VPC name: ${var.vpc_name}'"
  }
}

data ibm_is_vpc vpc {
  depends_on = [null_resource.print-names]

  name  = var.vpc_name
}

data local_file user_data_vsi {
  filename = local.user_data_vsi_file
}

data "ibm_is_image" "ubuntu_image" {
    name = local.ubuntu_image
}

resource "ibm_is_security_group" "vsi_sg" {
    name           = "${var.vpc_name}-sg-scc"
    vpc            = data.ibm_is_vpc.vpc.id
    resource_group = local.resource_group_id
}

resource "ibm_is_security_group_rule" "rule-all-outbound" {
    group = ibm_is_security_group.vsi_sg.id
    direction = "outbound"
    remote = "0.0.0.0/0"
}

resource "ibm_is_security_group_rule" "rule-ssh-inbound" {
    group = ibm_is_security_group.vsi_sg.id
    direction = "inbound"
    remote = "0.0.0.0/0"
    tcp {
        port_min = 22
        port_max = 22
    }
}

resource "ibm_is_instance" "vsi" {
  count = var.vpc_subnet_count

  name           = "${var.vpc_name}-vsi"
  resource_group = local.resource_group_id
  profile        = "cx2-2x4"
  image          = data.ibm_is_image.ubuntu_image.id
  vpc            = var.vpc_id
  keys           = [var.ssh_key_id]
  zone           = local.zone
  user_data      = local.user_data_vsi

  primary_network_interface {
    subnet          = ibm_is_subnet.subnet_vsi.id
    security_groups = [ibm_is_security_group.vsi_sg.id]
  }

  # Don't respin the VSI if the startup script is updated.
  lifecycle {
    ignore_changes = [
      user_data
    ]
  }
}

resource "ibm_is_floating_ip" "vsi_floatingip" {
  name           = "${local.name_prefix}-vsi-fip"
  target         = ibm_is_instance.vsi.primary_network_interface.0.id
  resource_group = data.ibm_resource_group.resource_group.id
}
  
# Setup scc
resource "null_resource" "setup_scc" {
  depends_on = [ibm_is_floating_ip.vsi_floatingip]

  connection {
    type        = "ssh"
    user        = "root"
    password    = ""
    private_key = var.ssh_private_key
    host        = ibm_is_floating_ip.vsi_floatingip.address
  }

  
  provisioner "remote-exec" {
    inline     = [
        templatefile("${path.module}/scripts/scc.sh",{scc_registration_key = var.scc_registration_key})
    ]
  }
}  