# State Management

## Current State

This module does not configure a backend — Terraform defaults to local state (`terraform.tfstate` in the working directory). This is acceptable for development but not recommended for shared or production environments.

## Recommended: Azure Storage Backend

Azure Blob Storage with lease-based locking is the standard remote backend for Azure-based Terraform deployments. Per [HashiCorp's backend documentation](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm).

### 1. Create Backend Resources

Create the storage account and container (once, outside this module):

```sh
RESOURCE_GROUP="rg-terraform-state"
STORAGE_ACCOUNT="tfstate$(openssl rand -hex 4)"   # must be globally unique, 3–24 chars
CONTAINER="netskope-bwan-azure"
LOCATION="westeurope"

# Create resource group for state (separate from the gateway resource group)
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Enable versioning for state recovery
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --enable-versioning true

# Create the state container
az storage container create \
  --name $CONTAINER \
  --account-name $STORAGE_ACCOUNT
```

### 2. Configure the Backend

Add a backend block to the root module. Create `backend.tf` (do not add to `versions.tf` — backends cannot use variables):

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstateXXXXXXXX"    # your storage account name
    container_name       = "netskope-bwan-azure"
    key                  = "terraform.tfstate"
  }
}
```

### 3. Migrate Existing State

If you already have local state:

```sh
terraform init -migrate-state
```

Terraform will prompt you to confirm the migration from local to Azure Blob Storage. After migration, the local `terraform.tfstate` file can be deleted (keep a backup first).

### 4. Authenticate the Backend

The `azurerm` backend uses the same credential chain as the provider. For CI/CD, set:

```sh
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."
export ARM_SUBSCRIPTION_ID="..."
```

The Service Principal needs `Storage Blob Data Contributor` on the state container (in addition to the gateway deployment permissions).

## Security Considerations

- **Encryption**: Azure Blob Storage encrypts data at rest by default (AES-256). The state file contains sensitive values including the Netskope API token and gateway activation tokens — ensure storage account access is restricted.
- **Access control**: Assign `Storage Blob Data Contributor` only to the Terraform operator and CI/CD service principal. Do not grant broad read access.
- **Versioning**: Enable blob versioning to allow state recovery from accidental corruption or deletion.
- **Locking**: Azure Blob Storage uses lease-based locking to prevent concurrent `terraform apply` runs from corrupting state. No separate lock table is needed.
- **Audit logging**: Enable storage account diagnostic settings to log blob access for audit purposes.

## Alternative Backends

Other backends that work with this module:

| Backend | Use Case |
|---|---|
| [Terraform Cloud / HCP](https://developer.hashicorp.com/terraform/cloud-docs) | Managed state, runs, and collaboration |
| [Azure Storage (azurerm)](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm) | Self-managed Azure-native (recommended for Azure deployments) |
| [S3](https://developer.hashicorp.com/terraform/language/settings/backends/s3) | Cross-cloud or existing S3 infrastructure |
| [Consul](https://developer.hashicorp.com/terraform/language/settings/backends/consul) | Existing Consul infrastructure |

Choose based on your organisation's infrastructure and collaboration requirements.
