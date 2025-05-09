data "yandex_compute_image" "ubuntu2404" {
  family = "ubuntu-2404-lts-oslogin"
}
resource "yandex_vpc_network" "default" {
  name = var.project
}
resource "yandex_vpc_gateway" "default" {
  name = var.project
  shared_egress_gateway {}
}
resource "yandex_vpc_route_table" "default" {
  name       = var.project
  network_id = yandex_vpc_network.default.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.default.id
  }
}
resource "yandex_vpc_subnet" "default" {
  name           = "${yandex_vpc_network.default.name}-${var.zone}"
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = ["10.130.0.0/24"]
  route_table_id = yandex_vpc_route_table.default.id
}
resource "yandex_vpc_subnet" "iscsi" {
  count          = 2
  name           = format("%s%02d-%s",
    "${yandex_vpc_network.default.name}-iscsi", count.index+1, var.zone
  )
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = [cidrsubnet("10.0.0.0/8", 16, 256*(131+count.index))]
}
resource "yandex_compute_disk" "iscsi" {
  count = local.yandex_compute_instance_iscsi_count
  size  = 20
  type  = "network-hdd"
}
resource "yandex_compute_instance" "iscsi" {
  count       = local.yandex_compute_instance_iscsi_count
  name        = format("%s-%02d", "${var.project}-iscsi", count.index + 1)
  hostname    = format("%s-%02d", "${var.project}-iscsi", count.index + 1)
  platform_id = "standard-v3"
  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }
  scheduling_policy { preemptible = true }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu2404.id
      size     = 20
      type     = "network-hdd"
    }
  }
  secondary_disk {
    disk_id     = yandex_compute_disk.iscsi[count.index].id
    auto_delete = true
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.default.id
    ip_address = cidrhost(
      one(yandex_vpc_subnet.default.v4_cidr_blocks), 11 + count.index
    )
    nat       = false
  }
  dynamic "network_interface" {
    for_each = yandex_vpc_subnet.iscsi
    content {
      subnet_id = network_interface.value.id
      ip_address = cidrhost(
        one(network_interface.value.v4_cidr_blocks), 11 + count.index
      )
      nat       = false
    }
  }
  metadata = local.yandex_compute_instance_metadata
}
resource "yandex_compute_instance" "backend" {
  count       = 3
  name        = format("%s-%02d", "${var.project}-backend", count.index + 1)
  hostname    = format("%s-%02d", "${var.project}-backend", count.index + 1)
  platform_id = "standard-v3"
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  scheduling_policy { preemptible = true }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu2404.id
      size     = 20
      type     = "network-ssd"
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.default.id
    ip_address = cidrhost(
      one(yandex_vpc_subnet.default.v4_cidr_blocks), 21 + count.index
    )
    nat       = false
  }
  dynamic "network_interface" {
    for_each = yandex_vpc_subnet.iscsi
    content {
      subnet_id = network_interface.value.id
      ip_address = cidrhost(
        one(network_interface.value.v4_cidr_blocks), 21 + count.index
      )
      nat       = false
    }
  }
  metadata = local.yandex_compute_instance_metadata
}
resource "yandex_compute_instance" "db" {
  count       = 1
  name        = format("%s-%02d", "${var.project}-db", count.index + 1)
  hostname    = format("%s-%02d", "${var.project}-db", count.index + 1)
  platform_id = "standard-v3"
  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }
  scheduling_policy { preemptible = true }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu2404.id
      size     = 20
      type     = "network-hdd"
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.default.id
    ip_address = cidrhost(
      one(yandex_vpc_subnet.default.v4_cidr_blocks), 31 + count.index
    )
    nat       = false
  }
  metadata = local.yandex_compute_instance_metadata
}
resource "yandex_compute_instance" "lb" {
  count       = 2
  name        = format("%s-%02d", "${var.project}-lb", count.index + 1)
  hostname    = format("%s-%02d", "${var.project}-lb", count.index + 1)
  platform_id = "standard-v3"
  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }
  scheduling_policy { preemptible = true }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu2404.id
      size     = 20
      type     = "network-hdd"
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.default.id
    ip_address = cidrhost(
      one(yandex_vpc_subnet.default.v4_cidr_blocks), 41 + count.index
    )
    nat       = count.index == 0
  }
  metadata = local.yandex_compute_instance_metadata
}
resource "yandex_lb_target_group" "lb" {
  name      = "${var.project}-lb"
  dynamic "target" {
    for_each = yandex_compute_instance.lb
    content {
      subnet_id = yandex_vpc_subnet.default.id
      address = target.value.network_interface.0.ip_address
    }
  }
}
resource "yandex_lb_network_load_balancer" "lb" {
  name = "${var.project}-lb"
  listener {
    name = "${var.project}-lb-https"
    port = 443
    external_address_spec {
      ip_version = "ipv4"
    }
  }
  attached_target_group {
    target_group_id = yandex_lb_target_group.lb.id
    healthcheck {
      name = "https"
      healthy_threshold = 2
      unhealthy_threshold = 2
      interval = 2
      timeout = 1
      tcp_options {
        port = 443
      }
    }
  }
}
resource "local_file" "inventory" {
  filename = "${path.root}/inventory.yml"
  content = templatefile("${path.module}/inventory.tftpl", {
    ssh_username = var.ssh_username,
    ssh_key_file = var.ssh_key_file,
    groups = [
      {
        name  = "iscsi"
        hosts = yandex_compute_instance.iscsi
        ipvars = ["ip_address_iscsi1", "ip_address_iscsi2"]
        jumphost = yandex_compute_instance.lb.0
      },
      {
        name     = "backend",
        hosts    = yandex_compute_instance.backend
        ipvars = ["ip_address_iscsi1", "ip_address_iscsi2"]
        jumphost = yandex_compute_instance.lb.0
      },
      {
        name     = "db",
        hosts    = yandex_compute_instance.db
        ipvars = []
        jumphost = yandex_compute_instance.lb.0
      },
      {
        name     = "lb",
        hosts    = yandex_compute_instance.lb
        ipvars = []
        jumphost = yandex_compute_instance.lb.0
      }
    ],
  })
}
