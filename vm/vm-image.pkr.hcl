packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1"
    }
  }
}

variable "image_name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "source_image" {
  type = string
}

variable "zone" {
  type = string
}

source "googlecompute" "build_image" {
  image_labels = {
    ubuntu     = "22_04"
  }

  disk_size    = 50
  disk_type    = "pd-ssd"
  image_name   = "${var.image_name}"
  machine_type = "n2d-standard-16"
  project_id   = "${var.project_id}"
  source_image = "${var.source_image}"

  ssh_username   = "ubuntu"
  ssh_agent_auth = false

  state_timeout = "30m"

  instance_name = "gh-runner-packer-{{uuid}}"

  # required since OpenSSH 8.8
  temporary_key_pair_type = "ed25519"

  wait_to_add_ssh_keys = "10s"

  zone = "${var.zone}"

  # enable Nested Hypervisor
  image_licenses          = ["projects/vm-options/global/licenses/enable-vmx"]
  image_storage_locations = ["eu"]
  image_guest_os_features = ["GVNIC", "VIRTIO_SCSI_MULTIQUEUE"]
}

build {
  sources = ["source.googlecompute.build_image"]

  provisioner "file" {
    source      = "${path.root}/setup.sh"
    destination = "/tmp/setup.sh"
  }

  provisioner "shell-local" {
    command = "tar -cvf ${path.root}/rootfs.tar rootfs"
  }

  provisioner "file" {
    source      = "${path.root}/rootfs.tar"
    destination = "/tmp/"
    generated   = true
  }
  
  provisioner "shell" {
    script = "packer-shell-script.sh"
  }
}
