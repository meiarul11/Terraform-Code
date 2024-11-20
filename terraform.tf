# Define the provider
provider "azurerm" {
  features {}
}

# Resource group for compute resources
resource "azurerm_resource_group" "compute_rg" {
  name     = "compute-resources-rg"
  location = "East US"
  tags = {
    environment = "production"
    team        = "cloud-services"
  }
}

# Virtual network for the compute resources
resource "azurerm_virtual_network" "vnet" {
  name                = "compute-vnet"
  location            = azurerm_resource_group.compute_rg.location
  resource_group_name = azurerm_resource_group.compute_rg.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "production"
  }
}

# Subnet for the VM
resource "azurerm_subnet" "subnet" {
  name                 = "compute-subnet"
  resource_group_name  = azurerm_resource_group.compute_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network security group
resource "azurerm_network_security_group" "nsg" {
  name                = "compute-nsg"
  location            = azurerm_resource_group.compute_rg.location
  resource_group_name = azurerm_resource_group.compute_rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "production"
  }
}

# Network interface for the VM
resource "azurerm_network_interface" "nic" {
  name                = "compute-nic"
  location            = azurerm_resource_group.compute_rg.location
  resource_group_name = azurerm_resource_group.compute_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Virtual machine with auto-scaling capability
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "compute-vm"
  resource_group_name = azurerm_resource_group.compute_rg.name
  location            = azurerm_resource_group.compute_rg.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  tags = {
    environment = "production"
    scalable    = "true"
  }
}

# Load Balancer for Scalability
resource "azurerm_lb" "lb" {
  name                = "compute-lb"
  location            = azurerm_resource_group.compute_rg.location
  resource_group_name = azurerm_resource_group.compute_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.compute_public_ip.id
  }

  tags = {
    environment = "production"
  }
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "compute_public_ip" {
  name                = "compute-public-ip"
  location            = azurerm_resource_group.compute_rg.location
  resource_group_name = azurerm_resource_group.compute_rg.name
  allocation_method   = "Static"
}

# Auto-scaling setup (using Azure Monitor autoscale settings)
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "compute-autoscale"
  resource_group_name = azurerm_resource_group.compute_rg.name
  location            = azurerm_resource_group.compute_rg.location

  profile {
    name = "scale-out"

    capacity {
      minimum = "1"
      maximum = "5"
      default = "1"
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine.vm.id
        operator           = "GreaterThan"
        statistic          = "Average"
        threshold          = 75
        time_aggregation   = "Average"
        frequency          = "PT1M"
        window_size        = "PT5M"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}
