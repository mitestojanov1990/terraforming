output "resource_group_name" {
  value = azurerm_resource_group.this_rg.name
}
output "public_ip_addresses" {
  value = module.testvm.public_ips
}