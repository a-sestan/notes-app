# Terraform — Notes App

Infrastruktura kao kod za AWS deployment.

## Preduslovi

- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.5
- [AWS CLI](https://aws.amazon.com/cli/) konfigurisan (`aws configure`)
- EC2 key pair kreiran u AWS account-u

## Pokretanje

```bash
# 1. Podesi varijable
cp terraform.tfvars.example terraform.tfvars
# Uredi terraform.tfvars — postavi key_name i db_password

# 2. Inicijalizuj
terraform init

# 3. Pregledaj plan
terraform plan

# 4. Kreiraj infrastrukturu (čekaj ~10 min)
terraform apply -auto-approve

# 5. Izlazni URL-ovi
terraform output frontend_url   # Otvori u browseru
terraform output api_url        # API endpoint
```

## Brisanje

```bash
terraform destroy -auto-approve
```

## Struktura

| Fajl | Opis |
|------|------|
| `main.tf` | VPC, subneti, IGW, NAT, route tables |
| `variables.tf` | Varijable (region, instance_type, db_password, key_name...) |
| `outputs.tf` | Izlazne vrijednosti (frontend_url, api_url, alb_dns...) |
| `provider.tf` | AWS provider |
| `ec2_alb.tf` | EC2 instance + ALB + Target Group + listener |
| `rds.tf` | RDS MySQL + db subnet group |
| `s3.tf` | S3 bucket + public policy + frontend upload |
| `security_groups.tf` | ALB, Backend, RDS security grupe |
| `userdata.sh` | Script za Docker i Flask na EC2 |
| `terraform.tfvars.example` | Primjer konfiguracije |

## Kreira (35 resursa)

- VPC (10.0.0.0/16) sa 2 public + 2 private subnet-a
- Internet Gateway + NAT Gateway
- 3 Security Groups (ALB:80, Backend:5000, RDS:3306)
- 2 × EC2 t2.micro sa Docker/Flask
- RDS MySQL 8.0 db.t3.micro
- S3 bucket sa statičkim website hostingom
- ALB + Target Group + path-based routing (/api/* → backend)
