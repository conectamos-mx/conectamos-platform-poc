# Terraform — conectamos-platform (S3 + CloudFront)

Flutter Web SPA servida desde AWS S3 con CDN CloudFront.

---

## Bootstrap one-time (antes del primer push)

### 1. Workspaces de Terraform Cloud

En la org `CONECTAMOSAI`, crear **dos workspaces** con Execution Mode = **Local**:

| Workspace | Branch | Tags |
|---|---|---|
| `conectamos-platform` | `main` (prod) | `conectamos-platform` |
| `conectamos-platform-dev` | `dev` | `conectamos-platform` |

### 2. Permisos adicionales en `gha-deploy` (cuenta conectamos-ai)

El rol `gha-deploy` necesita S3 + CloudFront + ACM para gestionar estos recursos.
Ejecutar en la cuenta `conectamos-ai` con credenciales de admin:

```bash
cat > s3-cloudfront.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Full",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::conectamos-platform-*",
        "arn:aws:s3:::conectamos-platform-*/*"
      ]
    },
    {
      "Sid": "CloudFrontFull",
      "Effect": "Allow",
      "Action": "cloudfront:*",
      "Resource": "*"
    },
    {
      "Sid": "ACMFull",
      "Effect": "Allow",
      "Action": "acm:*",
      "Resource": "*"
    }
  ]
}
EOF
aws iam put-role-policy --role-name gha-deploy \
  --policy-name s3-cloudfront \
  --policy-document file://s3-cloudfront.json
```

### 3. GitHub Secrets en el repo (a nivel repo, no org)

Crear en `conectamos-mx/conectamos-platform → Settings → Secrets`:

| Secret | Descripción |
|---|---|
| `DART_DEFINE_SUPABASE_URL` | URL del proyecto Supabase (mismo que `.env` local) |
| `DART_DEFINE_SUPABASE_ANON_KEY` | Supabase anon key (pública, no la service_role) |

Los siguientes ya existen a nivel org:
- `TF_API_TOKEN` — token de Terraform Cloud
- `AWS_AI_KEY` — ARN del rol OIDC en cuenta conectamos-ai
- `DEVOPS_WEBHOOK_URL` — webhook de notificaciones

### 4. GitHub Variables en el repo (opcional — para custom domains)

Si querés custom domain, crear en `Settings → Variables`:

| Variable | Valor ejemplo |
|---|---|
| `CUSTOM_DOMAIN_PROD` | `platform.conectamos.ai` |
| `CUSTOM_DOMAIN_DEV` | `platform-dev.conectamos.ai` |

Si no se setean, CloudFront usa su dominio por defecto (`*.cloudfront.net`).

### 5. Custom domain en Cloudflare (post-apply, si aplica)

Después del primer `terraform apply` exitoso, el output `acm_certificate_validation_records`
muestra los CNAMEs de validación ACM. Créalos en Cloudflare en **DNS-only (sin proxy)**
y espera que el certificado quede en estado `ISSUED` (~2 min).

Luego agrega el CNAME de la distribución:
```
platform.conectamos.ai  CNAME  <cloudfront_domain>  DNS-only
```

---

## Variables disponibles

| Variable | Default | Descripción |
|---|---|---|
| `aws_region` | `us-east-1` | Región AWS |
| `custom_domain` | `""` | Dominio personalizado. Vacío = CloudFront default |

---

## Notas

- `API_BASE_URL` se inyecta vía secrets `PLATFORM_API_URL` / `PLATFORM_API_URL_DEV` en el workflow — se compila en el bundle Flutter y es visible públicamente.
- `index.html` se sube con `Cache-Control: no-cache` — los assets (JS/CSS/fonts) con `max-age=31536000` ya que Flutter los hashea.
- `prevent_destroy = true` en bucket y distribución para evitar pérdida accidental de datos.
- Cuenta conectamos-ai es temporal — mover a prod/dev cuando esas cuentas estén bootstrappeadas.
