module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4"
}

module "regions" {
  source  = "Azure/regions/azurerm"
  version = "~> 0.6"
}

locals {
  tags = {
    scenario = "common_ubuntu_w_ssh"
  }
  test_regions = ["westeurope"]
}

resource "random_integer" "region_index" {
  max = length(local.test_regions) - 1
  min = 0
}


resource "azurerm_resource_group" "this_rg" {
  location = local.test_regions[random_integer.region_index.result]
  name     = module.naming.resource_group.name_unique
  tags     = local.tags
}

resource "azurerm_resource_group" "this_rg_secondary" {
  location = local.test_regions[random_integer.region_index.result]
  name     = "${module.naming.resource_group.name_unique}-alt"
  tags     = local.tags
}

resource "azurerm_virtual_network" "this_vnet" {
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this_rg.location
  name                = module.naming.virtual_network.name_unique
  resource_group_name = azurerm_resource_group.this_rg.name
  tags                = local.tags
}

resource "azurerm_subnet" "this_subnet_1" {
  address_prefixes     = ["10.0.1.0/24"]
  name                 = "${module.naming.subnet.name_unique}-1"
  resource_group_name  = azurerm_resource_group.this_rg.name
  virtual_network_name = azurerm_virtual_network.this_vnet.name
}

resource "azurerm_subnet" "this_subnet_2" {
  address_prefixes     = ["10.0.2.0/24"]
  name                 = "${module.naming.subnet.name_unique}-2"
  resource_group_name  = azurerm_resource_group.this_rg.name
  virtual_network_name = azurerm_virtual_network.this_vnet.name
}

resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this_rg.name
  virtual_network_name = azurerm_virtual_network.this_vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_public_ip" "bastionpip" {
  name                = module.naming.public_ip.name_unique
  location            = azurerm_resource_group.this_rg.location
  resource_group_name = azurerm_resource_group.this_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion" {
  name                = module.naming.bastion_host.name_unique
  location            = azurerm_resource_group.this_rg.location
  resource_group_name = azurerm_resource_group.this_rg.name

  ip_configuration {
    name                 = "${module.naming.bastion_host.name_unique}-ipconf"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastionpip.id
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "example_identity" {
  location            = azurerm_resource_group.this_rg.location
  name                = module.naming.user_assigned_identity.name_unique
  resource_group_name = azurerm_resource_group.this_rg.name
  tags                = local.tags
}

module "avm_res_keyvault_vault" {
  source                      = "Azure/avm-res-keyvault-vault/azurerm"
  version                     = "=0.6.2"
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  name                        = module.naming.key_vault.name_unique
  resource_group_name         = azurerm_resource_group.this_rg.name
  location                    = azurerm_resource_group.this_rg.location
  enabled_for_disk_encryption = true
  network_acls = {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  role_assignments = {
    deployment_user_secrets = { #give the deployment user access to secrets
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    deployment_user_keys = { #give the deployment user access to keys
      role_definition_id_or_name = "Key Vault Crypto Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    user_managed_identity_keys = { #give the user assigned managed identity for the disk encryption set access to keys
      role_definition_id_or_name = "Key Vault Crypto Officer"
      principal_id               = azurerm_user_assigned_identity.example_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  wait_for_rbac_before_key_operations = {
    create = "60s"
  }

  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }

  tags = local.tags

  keys = {
    des_key = {
      name     = "des-disk-key"
      key_type = "RSA"
      key_size = 2048

      key_opts = [
        "decrypt",
        "encrypt",
        "sign",
        "unwrapKey",
        "verify",
        "wrapKey",
      ]
    }
  }
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "admin_ssh_key" {
  key_vault_id = module.avm_res_keyvault_vault.resource_id
  name         = "azureuser-ssh-private-key"
  value        = tls_private_key.this.private_key_pem

  depends_on = [
    module.avm_res_keyvault_vault
  ]
}

resource "azurerm_disk_encryption_set" "this" {
  key_vault_key_id    = module.avm_res_keyvault_vault.keys_resource_ids.des_key.id
  location            = azurerm_resource_group.this_rg.location
  name                = module.naming.disk_encryption_set.name_unique
  resource_group_name = azurerm_resource_group.this_rg.name
  tags                = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.example_identity.id]
  }
}

module "testvm" {
  source = "./modules/compute_virtualmachine"
  #source = "Azure/avm-res-compute-virtualmachine/azurerm"
  #version = "0.15.0"

  admin_username                     = "azureuser"
  enable_telemetry                   = var.enable_telemetry
  encryption_at_host_enabled         = false
  generate_admin_password_or_ssh_key = false
  location                           = azurerm_resource_group.this_rg.location
  name                               = module.naming.virtual_machine.name_unique
  resource_group_name                = azurerm_resource_group.this_rg.name
  os_type                            = "Linux"
  sku_size                           = "Standard_B2s_v2"
  zone                               = null

  admin_ssh_keys = [
    {
      public_key = tls_private_key.this.public_key_openssh
      username   = "azureuser" #the username must match the admin_username currently.
    }
  ]

  data_disk_managed_disks = {
    disk1 = {
      name                   = "${module.naming.managed_disk.name_unique}-lun0"
      storage_account_type   = "StandardSSD_LRS"
      lun                    = 0
      caching                = "ReadWrite"
      disk_size_gb           = 32
      disk_encryption_set_id = azurerm_disk_encryption_set.this.id
      resource_group_name    = azurerm_resource_group.this_rg_secondary.name
      role_assignments = {
        role_assignment_2 = {
          principal_id               = data.azurerm_client_config.current.client_id
          role_definition_id_or_name = "Contributor"
          description                = "Assign the Contributor role to the deployment user on this managed disk resource scope."
          principal_type             = "ServicePrincipal"
        }
      }
    }
  }

  managed_identities = {
    system_assigned            = true
    user_assigned_resource_ids = [azurerm_user_assigned_identity.example_identity.id]
  }

  network_interfaces = {
    network_interface_1 = {
      name                           = "${module.naming.network_interface.name_unique}-1"
      accelerated_networking_enabled = true
      ip_forwarding_enabled          = true
      ip_configurations = {
        ip_configuration_1 = {
          name                          = "${module.naming.network_interface.name_unique}-nic1-ipconfig1"
          private_ip_subnet_resource_id = azurerm_subnet.this_subnet_1.id
        }
      }
      resource_group_name = azurerm_resource_group.this_rg_secondary.name
    }
    network_interface_2 = {
      name                  = "${module.naming.network_interface.name_unique}-2"
      ip_forwarding_enabled = true
      ip_configurations = {
        ip_configuration_avs_facing = {
          name                          = "${module.naming.network_interface.name_unique}-nic2-ipconfig1"
          private_ip_subnet_resource_id = azurerm_subnet.this_subnet_2.id
        }
      }
    }
  }

  os_disk = {
    caching                = "ReadWrite"
    storage_account_type   = "StandardSSD_LRS"
    disk_encryption_set_id = azurerm_disk_encryption_set.this.id
  }

  role_assignments_system_managed_identity = {
    role_assignment_1 = {
      scope_resource_id          = module.avm_res_keyvault_vault.resource_id
      role_definition_id_or_name = "Key Vault Secrets Officer"
      description                = "Assign the Key Vault Secrets Officer role to the virtual machine's system managed identity"
      principal_type             = "ServicePrincipal"
    }
  }

  role_assignments = {
    role_assignment_2 = {
      principal_id               = data.azurerm_client_config.current.client_id
      role_definition_id_or_name = "Virtual Machine Contributor"
      description                = "Assign the Virtual Machine Contributor role to the deployment user on this virtual machine resource scope."
      principal_type             = "ServicePrincipal"
    }
  }

  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = local.tags

  depends_on = [
    module.avm_res_keyvault_vault
  ]
}