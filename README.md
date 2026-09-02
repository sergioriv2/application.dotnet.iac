# application.dotnet.iac

Azure Function App (`AzureFunctionTest`, .NET 10 isolated) desplegada con Terraform sobre un plan **Flex Consumption (FC1)**, con CI/CD en GitHub Actions autenticado por OIDC (sin secrets de larga duración). Diseñado para costar **$0** en uso de desarrollo/pruebas.

## Arquitectura

```
infrastructure/
├── bootstrap/
│   ├── main.tf               # Crea el storage remoto donde vive el state de Terraform (state local, se aplica una sola vez)
│   └── variables.tf
└── live/
    ├── main.tf                # Recursos reales: Resource Group, Log Analytics, Storage, Function App (FC1)
    └── environments/
        ├── dev.tfvars
        ├── qa.tfvars
        └── prod.tfvars        # qa/prod son plantillas: agregá su infra cuando existan (ver nota en el paso 3)
```

Terraform no distingue entre archivos `.tf` dentro de un mismo directorio, los trata como si fueran uno solo — dividirlos en `providers.tf`/`outputs.tf`/etc. es puramente estético. Se optó por consolidar al mínimo, salvo `variables.tf` en `bootstrap` que se mantiene aparte.

- **Hosting**: Azure Functions, plan **Flex Consumption (FC1)** — sucesor del Consumption clásico (Y1), que Microsoft retira en Linux el 30-sep-2028. FC1 tiene capa gratuita mensual (ejecuciones + GB-s) y escala a cero.
- **Auth CI/CD**: OIDC / Federated Credentials en Microsoft Entra ID — GitHub Actions obtiene un token de corta duración por cada run, no hay client secret guardado.
- **State remoto**: Azure Storage con auth por Azure AD (`use_azuread_auth = true`), no por storage account key.

## Prerrequisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [.NET SDK 10](https://dotnet.microsoft.com/download)
- Una suscripción de Azure (Pay-As-You-Go recomendado — Free Trial tiene restricciones de cuota más agresivas)
- Un repositorio en GitHub

---

## 1. Login en Azure

```bash
az login
az account show   # confirmar que apunta a la suscripción correcta
```

## 2. Bootstrap: crear el backend remoto de Terraform

Este paso se corre **una sola vez**. Crea el Resource Group + Storage Account donde va a vivir el `.tfstate` de todo lo demás (por eso no puede usar ese mismo backend — usa state local).

```bash
cd infrastructure/bootstrap
terraform init
terraform plan
terraform apply
```

> ⚠️ El `terraform.tfstate` que queda en esta carpeta es local y **no está versionado** (ver `.gitignore`). Es la única copia — no lo borres ni lo pierdas, o vas a perder el tracking de estos recursos.

Anotá el nombre del storage account creado:

```bash
terraform output -raw storage_account_name
```

## 3. Conectar el backend de `live`

Editá el bloque `backend "azurerm"` dentro de `infrastructure/live/main.tf` (arriba del archivo) con el valor del paso anterior:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-<project>-tfstate"
    storage_account_name = "<valor del output>"
    container_name       = "tfstate"
    key                   = "iactest.dev.tfstate"
    use_azuread_auth      = true
  }
}
```

> ℹ️ **Múltiples entornos (`environments/qa.tfvars`, `environments/prod.tfvars`)**: el atributo `key` del backend es estático — no admite interpolar `var.environment` — así que por defecto todos los entornos apuntarían al mismo state (`iactest.dev.tfstate`) y se pisarían entre sí. Para aplicar `qa` o `prod` sin tocar el state de `dev`, pasá una key distinta en el `init` de ese entorno: `terraform init -reconfigure -backend-config="key=iactest.qa.tfstate"`. Los `.tfvars` de `qa`/`prod` en este repo son plantillas — la infra real para esos entornos todavía no existe.

`use_azuread_auth = true` significa que la identidad que corre Terraform (tu usuario local, o el Service Principal en CI) necesita el rol **Storage Blob Data Contributor** sobre ese storage account — no alcanza con ser dueño de la suscripción para leer/escribir blobs:

```bash
SUBID=$(az account show --query id -o tsv)
USER_OID=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --assignee "$USER_OID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBID/resourceGroups/rg-<project>-tfstate/providers/Microsoft.Storage/storageAccounts/<storage-account-name>"
```

> 🪟 **Windows + Git Bash**: si usás Git Bash, cualquier argumento que empiece con `/` (como un resource ID de Azure) se reinterpreta como un path de Windows. Anteponé `MSYS_NO_PATHCONV=1` al comando (`az`, `terraform import`, etc.) para evitarlo.

> 🖥️ **Alternativa por Portal**: **Storage accounts → `<storage-account-name>` → Access Control (IAM) → Add → Add role assignment** → rol **Storage Blob Data Contributor** → pestaña Members → "Assign access to: User, group, or service principal" → buscar tu usuario → Review + assign.

## 4. Registrar resource providers (solo si es una suscripción nueva)

Una suscripción que nunca usó cierto tipo de recurso no tiene el namespace registrado, y falla con `MissingSubscriptionRegistration` (HTTP 409):

```bash
az provider register --namespace Microsoft.App --wait               # si en algún momento volvés a usar Container Apps
az provider show --namespace Microsoft.Web --query registrationState -o tsv
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
az provider show --namespace Microsoft.Storage --query registrationState -o tsv
```

Si alguno no está `Registered`, correr `az provider register --namespace <nombre> --wait`.

## 5. Aplicar `infrastructure/live`

```bash
cd infrastructure/live
terraform init
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

Esto crea: Resource Group → Log Analytics Workspace → Storage Account (+ container `deployments`) → Service Plan `FC1` → Function App.

### Troubleshooting: cuota 0 al crear el Service Plan

Si ves un error `401 Unauthorized ... Current Limit (Total VMs): 0`, es porque la suscripción no tiene cuota de cómputo asignada todavía en esa región (común en cuentas nuevas, incluso Pay-As-You-Go). Se pide gratis desde el Portal:

**Portal → Quotas → My quotas → filtrar Provider "Microsoft.Web" / categoría "App Service" → región → buscar la fila con el SKU exacto (ej. `FC1 VMs`) y también `Total Regional VMs` → New quota request.**

En cuentas Pay-As-You-Go suele aprobarse en minutos. No hace falta pedirlo por cada SKU que pruebes — solo por el que efectivamente uses.

## 6. Configurar OIDC para GitHub Actions

### 6.1 Crear el App Registration + Service Principal

```bash
APPID=$(az ad app create --display-name "gh-oidc-<project>" --query appId -o tsv)
az ad sp create --id "$APPID"
```

> 🖥️ **Alternativa por Portal**:
> 1. **Microsoft Entra ID → App registrations → New registration** → nombre `gh-oidc-<project>` → "Accounts in this organizational directory only" → Register.
> 2. Eso crea el App Registration *y* el Service Principal asociado automáticamente (no hace falta un paso aparte, a diferencia de la CLI donde `az ad sp create` es explícito).
> 3. Anotá el **Application (client) ID** que aparece en Overview — lo vas a necesitar en 6.4.

### 6.2 Federated credentials

GitHub firma el token OIDC con un `subject` que identifica el repo y el evento. Para repos **creados después del 15-jul-2026**, el formato por defecto incluye IDs inmutables de owner/repo (`owner@id/repo@id`), no solo el nombre — importante para no pisar credenciales viejas de un repo renombrado/transferido.

Conseguí esos IDs con:

```bash
gh api repos/<owner>/<repo> --jq '{owner_id: .owner.id, repo_id: .id}'
```

Y creá las credenciales (una por trigger que uses):

```bash
az ad app federated-credential create --id "$APPID" --parameters '{
  "name": "gh-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>@<owner_id>/<repo>@<repo_id>:pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'

az ad app federated-credential create --id "$APPID" --parameters '{
  "name": "gh-push-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

> Si un run falla con `AADSTS700213: No matching federated identity record found`, el mensaje de error incluye el `subject` exacto que GitHub envió — copiálo tal cual con `az ad app federated-credential update`.

> 🖥️ **Alternativa por Portal**: **Microsoft Entra ID → App registrations → `gh-oidc-<project>` → Certificates & secrets → Federated credentials → Add credential** → escenario "GitHub Actions deploying Azure resources" → completar Organization, Repository, Entity type (Pull request / Branch) y el nombre de la branch (`main`) → el Portal arma el `subject` solo, no hace falta calcular `owner_id`/`repo_id` a mano. Repetir una vez por trigger (PR, push a main).

### 6.3 Dar permisos al Service Principal

```bash
SUBID=$(az account show --query id -o tsv)

# Permiso sobre los recursos de la app
MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee "$APPID" --role "Contributor" \
  --scope "/subscriptions/$SUBID/resourceGroups/rg-<project>-dev"

# Permiso sobre el storage del backend remoto (para que CI pueda leer/escribir el state)
MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee "$APPID" --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBID/resourceGroups/rg-<project>-tfstate/providers/Microsoft.Storage/storageAccounts/<tfstate-storage-account>"
```

> 🖥️ **Alternativa por Portal** (repetir para cada scope):
> 1. **Resource groups → `rg-<project>-dev` → Access Control (IAM) → Add → Add role assignment** → rol **Contributor** → Members → "Assign access to: User, group, or service principal" → buscar `gh-oidc-<project>` (por nombre, no aparece por App ID) → Review + assign.
> 2. Repetir en **Resource groups → `rg-<project>-tfstate` → Access Control (IAM)** con rol **Storage Blob Data Contributor**, mismo Service Principal.
> 3. Si el rol se asigna a nivel del Storage Account en vez del Resource Group, andá directo a **Storage accounts → `<tfstate-storage-account>` → Access Control (IAM)**.

### 6.4 Secrets en GitHub

En el repo → **Settings → Secrets and variables → Actions → New repository secret**, cargar:

| Secret | Dónde conseguirlo |
|---|---|
| `AZURE_CLIENT_ID` | Portal → Microsoft Entra ID → App registrations → `gh-oidc-<project>` → Overview → "Application (client) ID" |
| `AZURE_TENANT_ID` | Mismo lugar → "Directory (tenant) ID" |
| `AZURE_SUBSCRIPTION_ID` | Portal → Subscriptions → tu suscripción → "Subscription ID" |

## 7. Workflow de CI/CD

`.github/workflows/ci-cd.yml`, filtrado por `paths` a `infrastructure/live/**` y las carpetas de la Function:

- **PR a `main`** → job `terraform-plan`: `fmt` + `validate` + `plan` (solo lectura).
- **Push a `main`** (ej. al mergear un PR) → `terraform-apply` (aplica infra) → `deploy-function` (build + publish de `AzureFunctionTest` al Function App), encadenados.

Todo el workflow corre bajo un único `concurrency.group` (`terraform-live`) porque `terraform-plan` y `terraform-apply` comparten el mismo backend/state — así los runs se encolan en vez de pelear por el lock del state.

### Troubleshooting: `Error message: state blob is already locked`

Terraform usa un *blob lease* de Azure Storage como lock del state. Pasa cuando dos runs intentan tocar el mismo state a la vez, o cuando un run anterior murió a mitad de camino (runner caído, cancelado manualmente) y no llegó a liberar el lease.

1. Mirá el log completo del job fallido — el error trae un bloque `Lock Info:` con el `ID`, quién lo tomó (`Who`) y cuándo (`Created`).
2. Confirmá en la pestaña **Actions** que no haya otro run de este workflow corriendo ahora mismo (con el `concurrency` group de arriba, esto no debería pasar de nuevo — pero si el lock quedó de *antes* de agregarlo, sigue colgado y hay que liberarlo a mano).
3. Si no hay nada corriendo, liberá el lock con el `ID` del paso 1:

   ```bash
   cd infrastructure/live
   terraform init -input=false
   terraform force-unlock <LOCK_ID>
   ```

   > 🖥️ **Alternativa por Portal** (si no querés/podés correr Terraform local): **Storage accounts → `<tfstate-storage-account>` → Containers → `tfstate` → click en el blob `iactest.dev.tfstate` → Break lease**.

## 8. Deploy manual (sin pipeline)

Si querés probar sin pasar por GitHub Actions:

```bash
dotnet publish AzureFunctionTest/AzureFunctionTest.csproj -c Release -o ./publish
cd publish
zip -r ../publish.zip .
az functionapp deployment source config-zip \
  --name <function-app-name> \
  --resource-group rg-<project>-dev \
  --src ../publish.zip
```

## Costos ($0 esperado)

| Recurso | Por qué es $0 |
|---|---|
| Resource Group | Sin costo, es solo agrupación |
| Log Analytics Workspace | Capa gratuita: ~5GB/mes de ingesta |
| Storage Account (Standard LRS) | Uso mínimo (metadata de la Function), centavos en el peor caso |
| Service Plan `FC1` + Function App | Flex Consumption: capa gratuita mensual de ejecuciones + GB-s, escala a cero en reposo |

El bloque de **ACR + RBAC** dentro de `infrastructure/live/main.tf` está **comentado intencionalmente** — Basic ACR tiene costo fijo diario (~$5/mes) aunque no se use. Reactivar solo si se necesita un registry privado.

## Cleanup

```bash
cd infrastructure/live
terraform destroy -var-file=environments/dev.tfvars

cd ../bootstrap
terraform destroy   # opcional: borra también el backend remoto
```

También conviene borrar el App Registration si no se va a seguir usando:

```bash
az ad app delete --id "$APPID"
```
