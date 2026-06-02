# Notes App — AWS Deployment

Flask + MySQL aplikacija za bilješke, deployana na AWS-u sa Terraformom.

## Arhitektura

```
Internet → S3 (frontend)     Internet → ALB (port 80)
        (HTML/CSS/JS)                   ├── /api/* → EC2 #1 + EC2 #2 → RDS MySQL
                                        └── default → redirect na S3
                  ══════ VPC 10.0.0.0/16 ══════
     Public AZ-a           Public AZ-b        Private AZ-a+b
     ALB + EC2 #1          ALB + EC2 #2        RDS (MySQL)
     IGW → internet        IGW → internet      NAT → internet
```

## Pokretanje (Terraform)

### Preduslovi
- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.5
- [AWS CLI](https://aws.amazon.com/cli/) — pokrenite `aws configure`
- **EC2 key pair** — kreirajte u AWS konzoli (EC2 → Key Pairs → Create key pair)

### Koraci

```bash
# 1. Uđite u terraform folder
cd terraform

# 2. Kopirajte primjer konfiguracije
cp terraform.tfvars.example terraform.tfvars

# 3. Uredite terraform.tfvars:
#    - key_name = "ime-vaseg-key-pair-a"
#    - db_password = "NekaSifra123"

# 4. Inicijalizujte Terraform
terraform init

# 5. Pregledajte šta će se kreirati
terraform plan

# 6. Kreirajte infrastrukturu (čekajte ~10 min)
terraform apply -auto-approve

# 7. Kad završi, otvorite frontend:
terraform output frontend_url   # zalijepite u browser
```

### Brisanje

```bash
cd terraform
terraform destroy -auto-approve
```

## Šta Terraform kreira (35 resursa)

| Resurs | Detalji |
|--------|---------|
| VPC | 10.0.0.0/16, 2 public + 2 private subnet-a, IGW, NAT |
| EC2 × 2 | t2.micro, Docker, Flask backend |
| RDS | MySQL 8.0, db.t3.micro, 20 GB |
| S3 | Statički website (HTML/CSS/JS) |
| ALB | Path-based routing: /api/* → backend, ostalo → S3 |
| Security Groups | ALB (80), Backend (5000), RDS (3306) |

## Pristup aplikaciji

| Šta | URL |
|-----|-----|
| Frontend | `http://<bucket>.s3-website-us-east-1.amazonaws.com` |
| API | `http://<alb-dns>/api/notes` |

## Dokumentacija

- [`DOKUMENTACIJA.md`](DOKUMENTACIJA.md) — tehnička dokumentacija, troškovi, izazovi (bosanski)
- [`VIDEO_GUIDE.md`](VIDEO_GUIDE.md) — uputstvo za snimanje odbrane
- [`terraform/README.md`](terraform/README.md) — kratak Terraform vodič

## Struktura projekta

```
notes-app/
├── backend/         ← Flask aplikacija + Dockerfile
├── frontend/        ← HTML, CSS, JavaScript
├── terraform/       ← Terraform kod (IaC)
├── scripts/         ← Deployment skripte (opciono)
├── DOKUMENTACIJA.md ← Tehnička dokumentacija
└── VIDEO_GUIDE.md   ← Uputstvo za video odbranu
```
