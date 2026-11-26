# Redmine en AWS con Terraform y GitHub Actions

Infraestructura como código (IaC) para desplegar [Redmine](https://www.redmine.org/) en AWS usando Terraform, con un pipeline CI/CD en GitHub Actions que valida, planifica y aplica los cambios.

## Arquitectura

```text
Usuario → ALB (HTTP :80) → ECS Fargate (Redmine :3000) → RDS PostgreSQL
```

| Componente | Detalle |
|---|---|
| Red | VPC con subredes públicas (ALB), privadas (contenedores) y de base de datos, en 2 zonas de disponibilidad |
| Cómputo | ECS Fargate con la imagen oficial `redmine` |
| Base de datos | RDS PostgreSQL 16, cifrada, en subredes privadas |
| Entrada | Application Load Balancer |
| Secretos | AWS Secrets Manager (contraseña de BD y `SECRET_KEY_BASE`) |
| Logs | CloudWatch Logs (`/ecs/redmine-prod`) |
| Estado de Terraform | Bucket S3 con versionado, cifrado y bloqueo nativo (`use_lockfile`) |
| CI/CD | GitHub Actions con autenticación OIDC (sin claves de acceso almacenadas) |

## Estructura del repositorio

```text
redmine-iac/
├── bootstrap/             # Se aplica UNA vez, a mano
│   └── main.tf            # Bucket de estado + OIDC de GitHub + rol IAM
├── infra/                 # Infraestructura de Redmine (la gestiona el pipeline)
│   ├── backend.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── network.tf
│   ├── security.tf
│   ├── database.tf
│   ├── ecs.tf
│   ├── alb.tf
│   └── outputs.tf
├── .github/workflows/
│   └── terraform.yml      # Pipeline CI/CD
├── .gitignore
└── README.md
```

## Prerrequisitos

- Cuenta de AWS con un usuario IAM (o SSO) con permisos suficientes para el bootstrap.
- [AWS CLI](https://aws.amazon.com/cli/) configurado (`aws configure`) y verificado con `aws sts get-caller-identity`.
- [Terraform](https://developer.hashicorp.com/terraform/install) **>= 1.10** (recomendado la versión de 64 bits).
- Git y un repositorio en GitHub.

## Puesta en marcha

### 1. Bootstrap (una sola vez, desde tu equipo)

Crea el bucket del estado remoto, el proveedor OIDC de GitHub y el rol que asumirá el pipeline.

```powershell
cd bootstrap
terraform init
terraform apply -var="github_repo=USUARIO/REPOSITORIO" -var="state_bucket_name=NOMBRE-UNICO-DEL-BUCKET"
```

> `github_repo` debe tener el formato `usuario/repositorio` (**sin** `https://github.com/`) y respetar mayúsculas y minúsculas.
> El nombre del bucket debe ser único a nivel global en AWS.

Anota el valor de salida `role_arn` (o consúltalo con `terraform output role_arn`).

> **Importante sobre el claim OIDC:** algunas cuentas de GitHub envían el `sub` del token con los IDs numéricos del propietario y del repositorio, por ejemplo `repo:usuario@ID_USUARIO/repositorio@ID_REPO:ref:refs/heads/main`. Si el pipeline falla con `Not authorized to perform sts:AssumeRoleWithWebIdentity`, comprueba el `sub` real y añade ese formato a la condición `StringLike` de la política de confianza en `bootstrap/main.tf`.

### 2. Configurar el backend

Edita `infra/backend.tf` y pon el mismo nombre de bucket usado en el bootstrap.

### 3. Configurar GitHub

1. **Settings → Secrets and variables → Actions → pestaña *Variables***: crea la variable `AWS_ROLE_ARN` con el valor de `role_arn`. Debe ser una *variable*, no un *secret*.
2. **Settings → Environments**: crea el entorno `production` y añade *Required reviewers* para exigir aprobación manual antes del `apply`.
3. **Settings → Branches**: protege `main` (exigir Pull Request y checks).

### 4. Desplegar

1. Crea una rama, haz un cambio en `infra/` y abre un Pull Request: el pipeline ejecuta `fmt`, `validate` y `plan`, y publica el plan como comentario.
2. Fusiona el PR en `main`: se genera el plan y queda a la espera de aprobación en el entorno `production`.
3. Aprueba el despliegue en la pestaña **Actions**.
4. Al terminar, obtén la URL:

   ```powershell
   cd infra
   terraform output redmine_url
   ```

La primera carga puede tardar varios minutos mientras Redmine ejecuta las migraciones de la base de datos (el ALB puede mostrar 503 al inicio).

### 5. Primer acceso a Redmine

Usuario por defecto: `admin` / contraseña `admin`. **Cámbiala inmediatamente.**

## Flujo del pipeline

| Evento | Acción |
|---|---|
| Pull Request que toca `infra/**` | `fmt -check`, `init`, `validate`, `plan` y comentario con el plan |
| Push a `main` | Plan + `apply` del plan aprobado (requiere aprobación en `production`) |

## Comandos útiles (local)

```powershell
cd infra
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Para evitar errores de checksum entre Windows y los runners Linux de GitHub, genera el lock file para ambas plataformas y súbelo al repositorio:

```powershell
terraform providers lock -platform=linux_amd64 -platform=windows_amd64
```

## Qué NO debe subirse al repositorio

- La carpeta `.terraform/` (contiene binarios de providers de cientos de MB; GitHub rechaza archivos de más de 100 MB).
- Archivos de estado (`*.tfstate`) y planes (`tfplan`): contienen secretos.
- Archivos `.tfvars` con datos sensibles.

Sí debe subirse `.terraform.lock.hcl`.

`.gitignore` recomendado:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
tfplan
crash.log
*.auto.tfvars
secrets.tfvars
```

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `GH001: Large files detected` al hacer push | Se versionó `.terraform/`. Añádela al `.gitignore`, ejecuta `git rm -r --cached <ruta>/.terraform` y reescribe el commit |
| `No valid credential sources found` | AWS CLI sin configurar. Ejecuta `aws configure` y verifica con `aws sts get-caller-identity` |
| Error con `\` en PowerShell | `\` es de Bash. En PowerShell usa una sola línea o el acento grave `` ` `` para continuar |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Revisa que `AWS_ROLE_ARN` sea el ARN del **rol**, que esté en *Variables*, y que el `sub` del token coincida con la política de confianza |
| `NoSuchEntity` en `AmazonECSTaskExecutionRolePolicy` | El ARN correcto es `arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` (con guion en `service-role`) |
| Targets `unhealthy` en el ALB | Revisa los logs en CloudWatch (`/ecs/redmine-prod`) y los eventos del servicio ECS; la primera migración tarda |

Si un `apply` falla a medias, no uses *Re-run* sobre el run fallido: haz un nuevo push para generar un plan actualizado.

## Mejoras recomendadas para producción

- **HTTPS y dominio propio:** certificado en ACM, listener 443 y registro en Route 53.
- **Archivos adjuntos persistentes:** montar Amazon EFS en `/usr/src/redmine/files` (el almacenamiento de Fargate es efímero).
- **Alta disponibilidad:** `multi_az = true` en RDS, un NAT Gateway por AZ y `desired_count = 2` (requiere EFS).
- **Mínimo privilegio:** reemplazar `AdministratorAccess` del rol de GitHub por una política acotada.
- **Protección de datos:** `deletion_protection = true` y `skip_final_snapshot = false` en RDS.
- **Seguridad en el pipeline:** añadir `tflint` y `checkov`/`trivy config`.
- **Varios entornos:** separar `dev` y `prod` con `.tfvars` y claves de estado distintas.
- **Correo:** configurar SMTP (por ejemplo, Amazon SES) para notificaciones.

## Costos y destrucción

Los costos fijos principales son NAT Gateway, ALB, RDS y Fargate. Verifica el estimado con la calculadora de precios de AWS.

Para eliminar la infraestructura de Redmine:

```powershell
cd infra
terraform destroy
```

Para eliminar también el bootstrap, vacía primero el bucket de estado (tiene versionado) y luego ejecuta `terraform destroy` en `bootstrap/`.

## Seguridad

- No subas credenciales, claves de acceso ni archivos de estado.
- Mantén el repositorio **privado**.
- Una vez funcionando el OIDC, elimina o desactiva las claves de acceso IAM usadas para el bootstrap.
