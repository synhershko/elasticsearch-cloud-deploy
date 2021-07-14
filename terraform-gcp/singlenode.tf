data "template_file" "singlenode_userdata_script" {
  template = "${file("${path.module}/../templates/gcp_user_data.sh")}"
  vars = merge(local.user_data_common, {
    heap_size      = "${var.master_heap_size}"
    startup_script = "singlenode.sh"
  })
}

resource "google_compute_target_pool" "singlenode" {
  name = "${var.es_cluster}-singlenode-targetpool"
}

resource "google_compute_instance_group_manager" "singlenode" {
  provider = google-beta

  name    = "${var.es_cluster}-igm-singlenode"
  project = "${var.gcp_project_id}"
  zone    = "${var.singlenode_zone}"

  version {
    instance_template = google_compute_instance_template.singlenode.self_link
    name              = "primary"
  }

  base_instance_name = "${var.es_cluster}-singlenode"
  target_pools       = [google_compute_target_pool.singlenode.self_link]
}

resource "google_compute_autoscaler" "singlenode" {
  count = local.singlenode_mode ? 1 : 0

  name   = "${var.es_cluster}-autoscaler-singlenode"
  zone   = "${var.singlenode_zone}"
  target = google_compute_instance_group_manager.singlenode.self_link

  autoscaling_policy {
    max_replicas    = 1
    min_replicas    = 1
    cooldown_period = 60
  }
}

resource "google_compute_instance_template" "singlenode" {
  provider = google-beta
  name_prefix    = "${var.es_cluster}-instance-template-single"

  project      = "${var.gcp_project_id}"
  machine_type = "${var.data_machine_type}"

  tags = ["${var.es_cluster}", "es-singlenode-node", "http-server", "https-server"]

  metadata = {
    sshKeys = "ubuntu:${file(var.gcp_ssh_pub_key_file)}"
  }
  metadata_startup_script = "${data.template_file.singlenode_userdata_script.rendered}"

  labels = {
    environment = var.environment
    cluster     = "${var.environment}-${var.es_cluster}"
    role        = "singlenode"
  }

  disk {
    source_image = data.google_compute_image.kibana.self_link
    boot         = true
  }

  network_interface {
    network = var.cluster_network
  }

  service_account {
    scopes = ["userinfo-email", "compute-rw", "storage-ro"]
  }

  lifecycle {
    create_before_destroy = true
  }

}