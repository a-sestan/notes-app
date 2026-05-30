# Tehnička dokumentacija — Notes App

> **Autor:** Abdulhalim Šestan  
> **Predmet:** Oblak projekat 1  
> **Tehnologije:** AWS, Terraform, Docker, Flask, MySQL, S3

---

## Sadržaj

1. [Arhitekturni dijagram sistema](#1-arhitekturni-dijagram-sistema)
2. [Procjena troškova AWS servisa](#2-procjena-troškova-aws-servisa)
3. [Upute za pokretanje i testiranje](#3-upute-za-pokretanje-i-testiranje)
4. [Opis izazova i rješenja](#4-opis-izazova-i-rješenja)

---

## 1. Arhitekturni dijagram sistema

### 1.1 Opis arhitekture

Aplikacija se sastoji od tri sloja:

| Sloj | Servis | Opis |
|------|--------|------|
| **Frontend** | S3 Static Website | HTML, CSS, JS hostovani na S3 bucketu sa javnim read policyjem |
| **Backend** | EC2 + Docker + Flask | Dvije EC2 instance u različitim Availability Zone, svaka pokreće Docker kontejner sa Flask API-jem |
| **Baza podataka** | RDS MySQL | MySQL 8.0 baza u private subnet-ima |

Load Balancer (ALB) raspoređuje promet: `/api/*` → backend, sve ostalo → S3.

### 1.2 Vizuelni dijagram

```
╔══════════════════════════════════════════════════════════════╗
║                        INTERNET                              ║
╚══════════════════════════════════════════════════════════════╝
          │                                       │
          ▼                                       ▼
┌─────────────────────┐             ┌───────────────────────────┐
│  S3 Static Website   │             │    ALB (Application      │
│  notes-app-frontend  │◄──── HTTP 301│    Load Balancer)        │
│  (index.html,        │      redirect│    port 80               │
│   style.css,         │             │    notes-alb              │
│   script.js)         │             └───────────┬───────────────┘
└─────────────────────┘                         │
                                          Rule: /api/*
                                          ┌─────┴──────┐
                                          ▼            ▼
                              ┌──────────────────┐  ┌──────────────────┐
                              │  Target Group     │  │  Target Group     │
                              │  notes-backend-tg │  │  notes-backend-tg │
                              │  health: /health  │  │  health: /health  │
                              └────────┬─────────┘  └────────┬─────────┘
                                       │                     │
                                       ▼                     ▼
                              ┌──────────────────┐  ┌──────────────────┐
                              │  EC2 #1          │  │  EC2 #2          │
                              │  notes-backend-1 │  │  notes-backend-2 │
                              │  AZ: us-east-1a  │  │  AZ: us-east-1b  │
                              │  t2.micro        │  │  t2.micro        │
                              │  Docker: Flask   │  │  Docker: Flask   │
                              │  172.31.89.164   │  │  172.31.10.150   │
                              └────────┬─────────┘  └────────┬─────────┘
                                       │                     │
                                       └──────────┬──────────┘
                                                  │ Port 3306
                                                  ▼
                              ┌──────────────────────────────┐
                              │  RDS MySQL 8.0               │
                              │  notes-db                    │
                              │  db.t3.micro, 20GB           │
                              │  notes-db.cqkmajlzi886...    │
                              │  Private subnet (2 AZ)       │
                              └──────────────────────────────┘


╔══════════════════════════════════════════════════════════════╗
║                     VPC 10.0.0.0/16                          ║
║                                                              ║
║  ┌─────────────────────────┐  ┌─────────────────────────┐    ║
║  │  Public subnet AZ-a     │  │  Public subnet AZ-b     │    ║
║  │  10.0.0.0/24           │  │  10.0.1.0/24            │    ║
║  │  ├── ALB (internet)    │  │  ├── ALB (internet)     │    ║
║  │  ├── EC2 #1            │  │  ├── EC2 #2             │    ║
║  │  └── IGW → 0.0.0.0/0  │  │  └── IGW → 0.0.0.0/0   │    ║
║  └─────────────────────────┘  └─────────────────────────┘    ║
║                                                              ║
║  ┌─────────────────────────┐  ┌─────────────────────────┐    ║
║  │  Private subnet AZ-a    │  │  Private subnet AZ-b    │    ║
║  │  10.0.10.0/24          │  │  10.0.11.0/24           │    ║
║  │  └── RDS (primary)     │  │  └── RDS (standby)      │    ║
║  │  NAT → internet (out)  │  │  NAT → internet (out)   │    ║
║  └─────────────────────────┘  └─────────────────────────┘    ║
║                                                              ║
║  Security Groups:                                            ║
║  ┌─────────────┐  ┌──────────────┐  ┌───────────┐          ║
║  │ notes-alb-sg│  │notes-backend-│  │notes-rds- │          ║
║  │ port 80     │  │sg port 5000  │  │sg port    │          ║
║  │ 0.0.0.0/0  │◄─│(od ALB SG)   │◄─│3306 (od   │          ║
║  │             │  │+ SSH port 22 │  │Backend SG)│          ║
║  └─────────────┘  └──────────────┘  └───────────┘          ║
╚══════════════════════════════════════════════════════════════╝
```

### 1.3 Kako kreirati dijagram u draw.io

1. Otvorite https://app.diagrams.net
2. Izaberite **Create New Diagram** → **Blank**
3. Sa lijeve strane povucite oblike:
   - **AWS Simple Icons** → potražite: VPC, EC2, RDS, S3, ALB, Security Group, Internet Gateway, NAT Gateway
   - Ili koristite **Rectangle** i **Cylinder** za jednostavniji prikaz
4. Povežite strelicama prema dijagramu iznad
5. Sačuvajte kao `dijagram.png` i dodajte u `/images/` folder projekta

---

## 2. Procjena troškova AWS servisa

> **Napomena:** Cijene su za us-east-1 region, na osnovu AWS Pricing Calculator (maj 2026).  
> U AWS Academy Learner Lab okruženju, svi resursi su pokriveni lab budget-om i ne naplaćuju se dodatno.

### 2.1 Mjesečni troškovi (24/7 rad, 730 sati mjesečno)

| Servis | Konfiguracija | Cijena po satu | Mjesečno (730h) |
|--------|---------------|---------------:|-----------------:|
| **EC2 × 2** | t2.micro, Linux, on-demand | $0.0116 × 2 | **$16.94** |
| **RDS** | db.t3.micro, MySQL, 20GB gp2 | $0.017 + $2.30 (storage) | **$14.71** |
| **ALB** | 1 ALB, 1 LCU prosjek | $0.0225 + $0.008 (LCU) | **$22.27** |
| **NAT Gateway** | 1 NAT u public subnetu | $0.045 | **$32.85** |
| **S3** | ~50KB, public website | < $0.01 | **~$0.00** |
| **Data transfer** | 5 GB/mjesečno (out) | $0.09/GB (prvih 10TB) | **$0.45** |
| **Elastic IP** | 1 NAT EIP (uključen u NAT) | $0.00 (dok je instanca aktivna) | **$0.00** |
| | | **Ukupno:** | **~$87.22** |

### 2.2 Uštede (ako se isključi kada se ne koristi)

| Strategija | Opis | Mjesečni trošak |
|-----------|------|-----------------|
| **24/7** | Sve radi stalno | ~$87 |
| **Radno vrijeme** | 8h/dan × 22 dana | ~$21 |
| **Samo testiranje** | Ugasiti kad se ne koristi | $0–5 |

### 2.3 Pojedinačne cijene servisa (za referencu)

| Servis | Cijena | Detalji |
|--------|-------|---------|
| t2.micro | $0.0116/h | 2 vCPU, 1 GB RAM |
| db.t3.micro | $0.017/h | 2 vCPU, 1 GB RAM, MySQL |
| EBS gp2 (RDS) | $0.115/GB/mj | 20 GB alocirano = $2.30/mj |
| S3 Standard | $0.023/GB/mj | Za ~50KB frontend: zanemarivo |
| ALB | $0.0225/h + $0.008/LCU-h | 1 LCU = 25 novih veza/s, 1000 aktivnih zahtjeva/s |
| NAT Gateway | $0.045/h + $0.045/GB | Obrada podataka kroz NAT |
| Data transfer out | $0.09/GB (prvih 10 TB) | Do interneta sa EC2/ALB |

### 2.4 Procjena godišnjeg troška

- **Produkcioni scenario (24/7):** ~$1,044 godišnje
- **Razvojni scenario (8h × 22 dana):** ~$252 godišnje
- **AWS Academy (lab budget):** $0 (pokriveno lab kreditima)

---

## 3. Upute za pokretanje i testiranje

### 3.1 Softverski preduslovi

| Alat | Verzija | Svrha |
|------|---------|-------|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | ≥ 1.5 | Kreiranje infrastrukture (IaC) |
| [AWS CLI](https://aws.amazon.com/cli/) | ≥ 2.x | Ručne AWS komande (alternativa Terraformu) |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | ≥ 24.x | Lokalni razvoj i testiranje |
| [Git](https://git-scm.com/) | ≥ 2.x | Verzionisanje koda |
| SSH klijent | PuTTY (Windows) ili OpenSSH (Linux/Mac) | Pristup EC2 instancama |

### 3.2 AWS kredencijali (AWS Academy)

1. Prijavite se na https://awsacademy.com
2. Otvorite kurs → **Modules** → **Learner Lab**
3. Kliknite **Start Lab** (sačekajte zeleno dugme)
4. Kliknite **AWS Details** → kopirajte:
   - `AWS Access Key ID`
   - `AWS Secret Access Key`
   - `AWS Session Token`
   - `Region` (obično `us-east-1`)

### 3.3 Opcija A: Potpuna automatizacija — Terraform (preporučeno)

```bash
# 1. Klonirajte repozitorij
git clone https://github.com/a-sestan/notes-app.git
cd notes-app/terraform

# 2. Konfigurišite AWS kredencijale
aws configure set aws_access_key_id     "ASIA..."
aws configure set aws_secret_access_key "CNYS..."
aws configure set aws_session_token     "IQoJ..."
aws configure set region                us-east-1

# 3. Kreirajte EC2 key pair i preuzmite .pem fajl
#    (u AWS konzoli: EC2 → Key Pairs → Create key pair)

# 4. Podesite varijable
cp terraform.tfvars.example terraform.tfvars
# Uredite terraform.tfvars:
#   key_name = "ime-vaseg-key-pair-a"
#   db_password = "NekaSifra123"

# 5. Pokrenite Terraform
terraform init
terraform plan          # Pregled šta će se kreirati
terraform apply        # Kreiraj infrastrukturu (čekaj ~10 min)

# 6. Nakon završetka, pogledajte izlaz:
terraform output frontend_url   # Otvorite u browseru
terraform output api_url        # API endpoint
```

**Šta Terraform radi (35 resursa):**
- Kreira VPC (10.0.0.0/16) sa 2 public i 2 private subnet-a
- Kreira Internet Gateway i NAT Gateway
- Kreira 3 Security Groups sa pravilima
- Kreira RDS MySQL bazu (db.t3.micro)
- Kreira S3 bucket i uploaduje frontend fajlove
- Kreira 2 EC2 instance sa Docker-om i Flask backendom
- Kreira ALB sa Target Group, listenerom i path-based routing pravilom
- Automatski postavlja `API_BASE` u script.js na ALB DNS

### 3.4 Opcija B: Ručni deployment (PowerShell)

```powershell
cd scripts
.\deploy-all.ps1 `
    -AccessKey "ASIA..." `
    -SecretKey "CNYS..." `
    -SessionToken "IQoJ..." `
    -KeyPrivatePath "C:\path\to\labsuser.pem"
```

Detaljna uputstva za ručni deployment potražite u `README.md`.

### 3.5 Opcija C: Lokalno testiranje (Docker)

```bash
cd notes-app

# Pokrenite MySQL + backend + frontend
docker-compose up -d

# Otvorite u browseru:
#   http://localhost:8080   (frontend)
#   http://localhost:5000   (backend API)
```

### 3.6 Kako pristupiti aplikaciji nakon deployment-a

| URL | Namjena |
|-----|---------|
| `http://<s3-bucket>.s3-website-us-east-1.amazonaws.com` | **Frontend** — otvorite u browseru |
| `http://<alb-dns>/api/notes` | **API** — direktan pristup (JSON) |
| `http://<alb-dns>/api/notes` (POST) | **Kreiranje bilješke** |

### 3.7 Kako očistiti AWS resurse nakon testiranja

**Terraform:**
```bash
cd terraform
terraform destroy -auto-approve
```

**Ručno (ako ste koristili deploy skripte):**
```bash
aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
aws elbv2 delete-target-group --target-group-arn "$TG_ARN"
aws ec2 terminate-instances --instance-ids "$INSTANCE_1" "$INSTANCE_2"
aws rds delete-db-instance --db-instance-identifier notes-db --skip-final-snapshot
aws s3 rm "s3://$BUCKET" --recursive
aws s3 rb "s3://$BUCKET"
aws ec2 delete-security-group --group-id "$RDS_SG"
aws ec2 delete-security-group --group-id "$BACK_SG"
aws ec2 delete-security-group --group-id "$ALB_SG"
aws ec2 delete-key-pair --key-name notes-app-key
```

**⚠️ Ne zaboravite:** Ugasite AWS Academy Lab sesiju (End Lab) kada završite da ne biste trošili lab budget.

---

## 4. Opis izazova i rješenja

### 4.1 Problem: ALB listener nije usmjeravao /api/ zahtjeve na backend

**Opis:** Na početku, ALB listener je imao default action koja je slala sav promet direktno na backend target grupu. To je značilo da su i zahtjevi za frontendom (HTML, CSS, JS) išli na Flask backend, koji nije znao da ih servira. Frontend se nije učitao u browseru.

**Rješenje:** ALB listener je konfigurisan sa dva pravila:
- **Default action:** HTTP 301 redirect na S3 website URL (za sve ne-API zahtjeve)
- **Rule (priority 1):** Ako putanja počinje sa `/api/*`, proslijedi na backend target grupu

Ova konfiguracija omogućava da korisnik otvori S3 URL za frontend, a API pozivi automatski idu na ALB → backend.

### 4.2 Problem: Flask rute nisu imale /api prefiks

**Opis:** Inicijalna verzija backend koda (`backend/app.py` i `terraform/userdata.sh`) imala je rute kao `@app.route('/notes')` umjesto `@app.route('/api/notes')`. Kada je ALB slao zahtjev na `/api/notes`, Flask backend nije prepoznavao tu rutu i vraćao je 404.

**Rješenje:** Sve Flask rute su promijenjene da koriste `/api` prefiks:
```
/notes           → /api/notes
/notes/<id>      → /api/notes/<id>
/notes/<id>/pin  → /api/notes/<id>/pin
/health          → /health (ostao bez prefiksa za health check)
```

Također je dodata ruta `/health` na portu 5000 koju ALB koristi za provjeru zdravlja instanci.

### 4.3 Problem: Terraform kod nije kreirao VPC i subnet-e

**Opis:** Početna Terraform konfiguracija je koristila `var.vpc_id` i `var.public_subnet_ids` kao varijable, očekujući da VPC i subneti već postoje. Ovo je značilo da se Terraform nije mogao pokrenuti na novom AWS account-u bez prethodnog ručnog kreiranja VPC-a. Nastavno osoblje ne bi moglo testirati kod na svom account-u.

**Rješenje:** Dodan je kompletan VPC setup u `main.tf`:
- VPC sa CIDR 10.0.0.0/16
- 2 public subnet-a (10.0.0.0/24, 10.0.1.0/24) u različitim AZ
- 2 private subnet-a (10.0.10.0/24, 10.0.11.0/24) u različitim AZ
- Internet Gateway za public subnet-e
- NAT Gateway za private subnet-e
- Route table-e i asocijacije

### 4.4 Problem: EC2 instance nisu imale subnet_id

**Opis:** EC2 instance su kreirane bez eksplicitnog `subnet_id`, što je značilo da Terraform bira default subnet iz default VPC-a. Ovo nije garantovalo da će instance biti u različitim Availability Zone, niti da će biti u public subnet-ima.

**Rješenje:** Dodan je `subnet_id = aws_subnet.public[count.index].id` na EC2 resource, čime svaka instanca ide u svoj public subnet i svoju AZ.

### 4.5 Problem: RDS nije imao subnet grupu

**Opis:** RDS instanca je kreirana bez `db_subnet_group`. AWS je automatski birao default subnet grupu, što je moglo uzrokovati probleme sa mrežnom dostupnošću.

**Rješenje:** Dodan je `aws_db_subnet_group.notes` resource koji koristi private subnet-e, a RDS instanca ga referencira preko `db_subnet_group_name`.

### 4.6 Problem: script.js API_BASE je bio prazan

**Opis:** Frontend fajl `frontend/script.js` ima konstantu `API_BASE = ''` koju treba postaviti na ALB DNS URL. Kod ručnog deployment-a, deploy skripta koristi `sed` da zamijeni ovu vrijednost. Međutim, Terraform je uploadovao fajl sa praznom vrijednošću, što je značilo da frontend šalje API zahtjeve na S3 domen (koji ne zna da ih obradi).

**Rješenje:** U `s3.tf`, upload script.js koristi `replace()` funkciju da dinamički zamijeni `API_BASE = ''` sa stvarnim ALB DNS-om koji Terraform kreira:
```hcl
content = replace(
  file("../frontend/script.js"),
  "API_BASE = ''",
  "API_BASE = 'http://${aws_lb.main.dns_name}'"
)
```

### 4.7 Problem: Namesigurnost sa kredencijalima

**Opis:** Početna verzija deploy skripti i README.md sadržavala je primjere sa placeholder kredencijalima koji su bili preblizu stvarnim vrijednostima. Postojala je opasnost da se osjetljivi podaci (SSH ključevi, AWS tokeni) slučajno commit-uju na GitHub.

**Rješenje:**
- Dodan je `.gitignore` koji isključuje `*.pem`, `node_modules/`, `.env`, `.tfvars` fajlove
- SSH privatni ključ `notes-app-key.pem` je isključen iz repozitorija
- AWS kredencijali se unose putem varijabli (Terraform) ili parametara (PowerShell skripte)
- Token za GitHub je uklonjen iz git remote URL-a nakon push-a

### 4.8 Problem: Health check na ALB nije radio

**Opis:** ALB health check je konfigurisan na putanji `/health`, ali je inicijalna verzija Flaska imala samo API rute. Bez `/health` endpoint-a, ALB je označavao instance kao `unhealthy` i nije im slao promet.

**Rješenje:** Dodan je jednostavan `@app.route('/health')` endpoint koji vraća `{"status": "ok"}` na portu 5000. ALB sada periodično (svakih 30 sekundi) provjerava ovaj endpoint i smatra instancu zdravom ako dobije HTTP 200.

### 4.9 Problem: Izbor AMI-ja za EC2

**Opis:** Inicijalni AMI filter u Terraformu i deploy skriptama koristio je Amazon Linux 2023 (`al2023-ami-*-x86_64`). Međutim, AWS Academy Learner Lab ponekad nema najnoviju AL2023 AMI, što je uzrokovalo greške `RunInstances denied` ili `InvalidAMIID.NotFound`.

**Rješenje:** Prebačeno na Amazon Linux 2 (`amzn2-ami-hvm-x86_64-gp2`) koji je stabilniji u lab okruženju. AL2 koristi `yum` umjesto `dnf`, što je zahtijevalo manje izmjene u `userdata.sh`.

### 4.10 Problem: Node.js zavisnosti su bile prevelike za GitHub

**Opis:** `node_modules/` direktorij je bio prevelik (~200 MB) za commit na GitHub, a `package.json` i `package-lock.json` su bili nepotrebni u repozitoriju jer frontend koristi čisti HTML/CSS/JS (bez Node.js build step-a).

**Rješenje:** `node_modules/` je dodat u `.gitignore`. `package.json` i `package-lock.json` su zadržani u repu jer dokumentuju zavisnosti projekta (iako nisu neophodne za AWS deployment).

---

## Reference

- GitHub repozitorij: https://github.com/a-sestan/notes-app
- AWS Pricing Calculator: https://calculator.aws
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest
- Flask dokumentacija: https://flask.palletsprojects.com
- Docker dokumentacija: https://docs.docker.com
