provider "ibm" {
  region           = var.region
  ibmcloud_api_key = var.ibmcloud_api_key
  generation       = 2
  ibmcloud_timeout = 900
}
