terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    helm    = { source = "hashicorp/helm",    version = "~> 2.10" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.20" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "adc9f320-e56e-45b1-845e-c73484745fc8"
}

# The providers will use the local file created in Step 3
provider "kubernetes" {
  config_path = "./kubeconfig"
  insecure    = true 
}

provider "helm" {
  kubernetes {
    config_path = "./kubeconfig"
    insecure    = true
  }
}

# --- 1. Infrastructure ---
resource "azurerm_resource_group" "rg" {
  name     = "cilium-final-rg"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "k8s-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "k8s-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "k8s-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "k8s-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowK8s"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "k8s-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "k8s-node"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  # TESTED K3S INSTALL: Includes TLS-SAN for the Public IP to avoid cert errors
  custom_data = base64encode(<<-SCRIPT
#!/bin/bash
PUBLIC_IP=$(curl -s ifconfig.me)
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --write-kubeconfig-mode 644 \
  --tls-san $PUBLIC_IP
SCRIPT
  )
}

output "vm_ip" { value = azurerm_public_ip.pip.ip_address }

# --- 2. Software (Cilium & NGINX) ---
resource "helm_release" "nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  depends_on       = [azurerm_linux_virtual_machine.vm]
}

