resource "azurerm_storage_account" "app_storage" {
  name                         = "${lower(replace(local.app_resource_group,"-",""))}storage"
  resource_group_name          = "${module.iis_app.app_resource_group}"
  location                     = "${var.location}"
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "LRS"
 
  network_rules {
    default_action             = "Deny"
    bypass                     = ["Logging","Metrics","AzureServices"] # Logging, Metrics, AzureServices, or None.
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
  # ip_rules                   = "${local.admin_ip_ranges}" # BUG: CIDR notation doesn't work as advertised
    ip_rules                   = "${local.admin_ips}" # BUG: CIDR notation doesn't work as advertised
    # Allow the Firewall subnet
    virtual_network_subnet_ids = ["${azurerm_subnet.iag_subnet.id}"]
  } 

  # HACK: To prevent 'not provisioned. They are in Updating state..'
  depends_on                   = ["azurerm_subnet.iag_subnet","azurerm_storage_account.archive_storage","azurerm_storage_account.vdc_diag_storage"]

  tags                         = "${local.tags}"
}

resource "azurerm_storage_container" "app_storage_container" {
  name                         = "data"
  storage_account_name         = "${azurerm_storage_account.app_storage.name}"
  container_access_type        = "private"
}

resource "azurerm_storage_blob" "app_storage_blob_sample" {
  name                         = "sample.txt"

  resource_group_name          = "${module.iis_app.app_resource_group}"
  storage_account_name         = "${azurerm_storage_account.app_storage.name}"
  storage_container_name       = "${azurerm_storage_container.app_storage_container.name}"

  type                         = "block"
  source                       = "../Data/sample.txt"
}

resource "azurerm_storage_account" "archive_storage" {
  name                         = "${lower(replace(local.app_resource_group,"-",""))}archive"
  resource_group_name          = "${module.iis_app.app_resource_group}"
  location                     = "${var.location}"
  account_kind                 = "StorageV2"
  account_tier                 = "Standard"
  account_replication_type     = "LRS"

  depends_on                   = ["azurerm_subnet.iag_subnet"]

  tags                         = "${local.tags}"
}

resource "azurerm_storage_container" "archive_storage_container" {
  name                         = "eventarchive"
  storage_account_name         = "${azurerm_storage_account.archive_storage.name}"
  container_access_type        = "private"
}

resource "azurerm_eventhub_namespace" "app_eventhub" {
  name                         = "${lower(replace(local.app_resource_group,"-",""))}eventhubNamespace"
  resource_group_name          = "${module.iis_app.app_resource_group}"
  location                     = "${var.location}"
  sku                          = "Standard"
  capacity                     = 1
  kafka_enabled                = false

  # TODO: Service Endpoint support
/*   
  network_rules {
    default_action             = "Deny"
    # Without this hole we can't make (automated) changes. Disable it later in the interactive demo
    ip_rules                   = ["${chomp(data.http.localpublicip.body)}"] # We need this to make changes
    # Allow the Firewall subnet
    virtual_network_subnet_ids = ["${azurerm_subnet.iag_subnet.id}"]
  }  */

  tags                         = "${local.tags}"
}

resource "azurerm_eventhub" "app_eventhub" {
  name                         = "${lower(replace(local.app_resource_group,"-",""))}eventhub"
  namespace_name               = "${azurerm_eventhub_namespace.app_eventhub.name}"
  resource_group_name          = "${module.iis_app.app_resource_group}"
  partition_count              = 2
  message_retention            = 1

  capture_description {
    enabled                    = true
    encoding                   = "Avro"
    interval_in_seconds        = 60
    destination {
      name                     = "EventHubArchive.AzureBlockBlob"
      archive_name_format      = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      storage_account_id       = "${azurerm_storage_account.archive_storage.id}"
      blob_container_name      = "${azurerm_storage_container.archive_storage_container.name}"
    }
  }

}