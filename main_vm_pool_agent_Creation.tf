provider "azurerm" {
  features {}
  subscription_id = "c3ffccd6-dc13-4a9e-964b-c27c366b43d0"
}

# 🔍 Fetch your current public IP dynamically
data "http" "my_ip" {
  url = "https://api.ipify.org?format=text"
}

resource "azurerm_resource_group" "rg" {
  name     = "devops-rg"
  location = "Central India"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "devops-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "devops-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  depends_on = [azurerm_virtual_network.vnet]

  timeouts {
    create = "5m"
    delete = "5m"
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "devops-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = data.http.my_ip.response_body
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip" {
  name                = "devops-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = "devops-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  depends_on = [azurerm_subnet.subnet]
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 🚀 Create DevOps agent pool via REST API
resource "null_resource" "create_agent_pool" {
  provisioner "local-exec" {
    command = <<EOT
      curl -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: Basic OkZLTnJKMVRETG1tYjBXOGcyQ2p4cWp2SjJjeWVQRTNpUzFrTDN3bmhxZzlPdWpubWhoY3hKUVFKOTlCSkFDQUFBQUFBQUFBQUFBQVNBWkRPTExzMA==" \
        -d '{"name": "tfnjpool", "poolType": "automation"}' \
        https://dev.azure.com/azurepractice0120/_apis/distributedtask/pools?api-version=7.1-preview.1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 🧠 VM with embedded agent bootstrap
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "devops-agent-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  admin_password      = "YourSecurePassword123!"
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic.id]

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

  computer_name = "devops-agent"

  custom_data = base64encode(<<EOF
#!/bin/bash
set -e

apt-get update && apt-get install -y curl tar libcurl4 openssh-client

mkdir -p /opt/tfnjagent && cd /opt/tfnjagent

curl -o agent.tar.gz https://download.agent.dev.azure.com/agent/4.261.0/vsts-agent-linux-x64-4.261.0.tar.gz
tar zxvf agent.tar.gz

./config.sh --unattended \
  --url https://dev.azure.com/azurepractice0120 \
  --auth pat \
  --token FKNrJ1TDLmmb0W8g2CjxqjvJ2cyePE3iS1kL3wnhqg9OujnmhhcxJQQJ99BJACAAAAAAAAAAAAASAZDOLLs0 \
  --pool tfnjpool \
  --agent tfnjagent \
  --acceptTeeEula \
  --work _work

./svc.sh install
./svc.sh start
EOF
  )

  depends_on = [null_resource.create_agent_pool]
}
