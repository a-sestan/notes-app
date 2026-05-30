# Video snimak — Uputstvo za odbranu projekta

> **Trajanje:** 8–10 minuta  
> **Cilj:** Odbrana studentskog projekta pred profesorom (Consillium)  
> **Pristup:** Snimak treba pokazati DVA načina kreiranja infrastrukture —  
> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(1) **automatizovano** (Terraform/CLI) i (2) **ručno** (AWS Console Web UI)

---

## Redoslijed snimanja

| # | Segment | Okvirno trajanje |
|---|---------|------------------|
| 1 | Uvod — šta je projekat | ~20s |
| 2 | Pokretanje aplikacije — otvaramo S3 URL | ~30s |
| 3 | Demonstracija rada — CRUD operacije | ~90s |
| 4 | Prikaz infrastrukture kroz AWS konzolu (Web UI) | ~2 min |
| 5 | Automatizovani deployment — Terraform / CLI pristup | ~1 min |
| 6 | Manualni deployment kroz Web UI — kreiranje resursa korak po korak | ~2 min |
| 7 | High Availability — gašenje instance, aplikacija i dalje radi | ~90s |
| 8 | Arhitektura + Terraform kod | ~90s |
| 9 | Dokumentacija i troškovi | ~30s |

---

## Prije snimanja

### Šta vam treba
1. **Screen recorder** — OBS Studio (preporučen) ili Windows Game Bar (Win + G)
2. **AWS Academy sesija aktivna** — Start Lab, sačekajte zeleno dugme
3. **Tabovi u browseru:**
   - Tab 1: **AWS Console** (Open AWS Console)
   - Tab 2: **S3 website URL**
   - Tab 3: **GitHub repo** — `https://github.com/a-sestan/notes-app`
   - Tab 4: **AWS CLI** (CloudShell ili lokalni terminal)

### Vaši URL-ovi za snimanje
- **S3 website:** `http://notes-app-frontend-94795.s3-website-us-east-1.amazonaws.com`
- **ALB DNS:** `notes-alb-2018448528.us-east-1.elb.amazonaws.com`
- **RDS endpoint:** `notes-db.cqkmajlzi886.us-east-1.rds.amazonaws.com`

---

## Segment 1: Uvod (~20s)

### Šta govorite
> "Ovo je Notes App — full-stack web aplikacija za kreiranje i upravljanje bilješkama. Backend je Flask (Python), baza je MySQL, a sve radi na AWS infrastrukturi. Cilj projekta je bio dizajnirati i implementirati cloud arhitekturu koristeći EC2, RDS, S3, ALB i Terraform, sa fokusom na visoku dostupnost i automatizaciju deployment-a."

---

## Segment 2: Pokretanje aplikacije (~30s)

### Šta radite
1. Otvorite **novi tab** i zalijepite S3 URL
2. Pritisnite Enter — vidite **Notes App** sa formom za dodavanje bilješke

### Šta govorite
> "Frontend je hostovan na S3 bucketu kao statički website. Kada korisnik otvori ovaj URL, browser učitava HTML, CSS i JavaScript direktno sa S3. API pozivi (npr. slanje nove bilješke) idu na ALB koji ih prosljeđuje backendu."

---

## Segment 3: Demonstracija rada — CRUD (~90s)

### 3a. Kreiranje bilješke
1. Naslov: `Odbrana projekta`
2. Sadržaj: `Ovo je demonstracija za Consillium`
3. Tag: `posao`
4. Kliknite ⭐ da pinujete
5. Kliknite **Dodaj bilješku**

### 3b. Druga bilješka
1. Naslov: `AWS arhitektura`
2. Sadržaj: `EC2, RDS, S3, ALB, VPC, Terraform`
3. Tag: `ideje`
4. Dodajte

### 3c. Izmjena
1. Kliknite ✏️ pored prve bilješke
2. Promijenite naslov u: `Odbrana projekta - spremno`
3. Sačuvajte

### 3d. Brisanje
1. Kliknite 🗑️ pored druge bilješke
2. Bilješka nestaje — podaci su obrisani iz RDS baze

### 3e. API poziv (opciono, ali preporučeno za impresiju)
1. Otvorite **CloudShell** (ikonu `>_` u AWS konzoli)
2. Upišite:
```bash
curl -s -X POST "http://notes-alb-2018448528.us-east-1.elb.amazonaws.com/api/notes" \
  -H "Content-Type: application/json" \
  -d '{"title":"CloudShell Biljeska","content":"Kreirana direktno kroz API"}'

curl -s "http://notes-alb-2018448528.us-east-1.elb.amazonaws.com/api/notes" | python -m json.tool
```

### Šta govorite
> "Ovdje vidimo standardne CRUD operacije — Create, Read, Update, Delete. Sve promjene se odmah perzistiraju u RDS MySQL bazi. Također mogu pokazati da API radi direktno iz CloudShell-a, što dokazuje da je komunikacija između frontenda (S3), ALB-a, EC2 backend-a i RDS baze potpuno funkcionalna."

---

## Segment 4: Prikaz infrastrukture kroz AWS konzolu — Web UI (~2 min)

**Vratite se na AWS konzolu.** Ovdje NE morate pokazati kako ste kreirali resurse (to dolazi kasnije) — samo pokažite šta postoji i radi.

### 4a. EC2 — instance
1. U pretragu upišite **EC2** → **Instances**
2. Vidite 2 instance: `notes-backend-1` i `notes-backend-2` — obje **Running**

> "Dvije t2.micro instance u različitim Availability Zone (us-east-1a i us-east-1b). Svaka pokreće Docker kontejner sa Flask backendom."

3. Kliknite jednu instancu → **Security** tab — pokažite `notes-backend-sg`

### 4b. ALB — Load Balancer
1. **Load Balancers** → `notes-alb` → **Listeners**
2. Pokažite:
   - **Default:** Redirect to S3 (HTTP 301)
   - **Rule (priority 1):** `/api/*` → Forward to `notes-backend-tg`

> "ALB prima promet na portu 80. Ako zahtjev ide na /api/*, prosljeđuje ga backend target grupi. Sve ostalo preusmjerava na S3 website. Ovo je primjer path-based routing-a."

3. **Target Groups** → `notes-backend-tg` → **Targets** — obje instance **healthy**

### 4c. RDS — baza
1. U pretragu upišite **RDS** → **Databases** → `notes-db`
2. Status: **Available**, Engine: MySQL 8.0, Size: db.t3.micro
3. **Connectivity & security** — endpoint + `notes-rds-sg`

### 4d. S3 — bucket
1. U pretragu upišite **S3** → `notes-app-frontend-94795`
2. Tri fajla: `index.html`, `style.css`, `script.js`
3. **Properties** → **Static website hosting** — pokažite URL

### 4e. VPC i subneti
1. U pretragu upišite **VPC** → **Your VPCs**
2. **Subnets** — 2 public, 2 private (u različitim AZ)
3. **Route Tables** — public RT (→ IGW), private RT (→ NAT)

### 4f. Security Groups
1. **Security Groups** — 3 grupe:
   - `notes-alb-sg`: port 80 od 0.0.0.0/0
   - `notes-backend-sg`: port 5000 samo od ALB SG
   - `notes-rds-sg`: port 3306 samo od Backend SG

---

## Segment 5: Automatizovani deployment — Terraform / CLI (~1 min)

### Šta govorite (dok pokazujete kod)

> "Infrastrukturu smo kreirali na DVA načina. Prvi je **automatizovani** — korištenjem Terraforma. Cijela infrastruktura definirana je kao kod (IaC)."

1. Otvorite GitHub → `terraform/main.tf`
2. Brzo skrolujte kroz: VPC, subneti, IGW, NAT, route tables

```bash
# Pokrenite komande (ne morate stvarno pokretati, samo prikažite kod)
terraform init
terraform plan
terraform apply -auto-approve
```

> "Sa samo tri komande — init, plan, apply — Terraform kreira svih 35 resursa za ~10 minuta. Ovo omogućava ponovljiv deployment u bilo kom AWS account-u, što je ključna prednost IaC pristupa."

3. Pokažite `terraform destroy -auto-approve` u kodu
> "I brisanje je jednako jednostavno — jedna komanda."

---

## Segment 6: Manualni deployment kroz Web UI (~2 min)

> "Drugi pristup je **manualni** — kreiranje resursa korak po korak kroz AWS Console Web UI. Ovo pomaže razumijevanju svakog servisa i njegove uloge."

**VAŽNO:** Ne morate stvarno kreirati nove resurse (postojeći su već aktivni). Dovoljno je pokazati obrazac za kreiranje i objasniti parametre.

### 6a. Kreiranje Security Groups — kroz Web UI

1. U AWS konzoli idite na **VPC** → **Security Groups** → **Create security group**
2. Pokažite obrazac (ne kliknite Create):
   - **Name:** `notes-alb-sg`
   - **Description:** Allow HTTP from internet
   - **Inbound rule:** Type=HTTP, Source=0.0.0.0/0

> "Security grupe su virtuelni firewalii. Prvo kreiramo ALB SG koja dozvoljava HTTP saobraćaj sa interneta na port 80."

3. Zatim pokažite drugi obrazac:
   - **Name:** `notes-backend-sg`
   - **Inbound rule:** Type=Custom TCP, Port=5000, Source=ALB Security Group

> "Backend SG dozvoljava saobraćaj samo sa ALB-a na port 5000. Na ovaj način niko ne može direktno pristupiti backendu — sav promet mora ići kroz ALB."

4. Treći obrazac:
   - **Name:** `notes-rds-sg`
   - **Inbound rule:** Type=MySQL/Aurora, Port=3306, Source=Backend Security Group

### 6b. Kreiranje RDS baze — kroz Web UI

1. U pretragu upišite **RDS** → **Create database**
2. Pokažite odabrane parametre (ne kreirajte):
   - **Engine:** MySQL 8.0
   - **Templates:** Free tier (ili Dev/Test)
   - **DB instance identifier:** `notes-db`
   - **Master username:** `notesuser`
   - **Master password:** `********`
   - **DB instance class:** db.t3.micro
   - **Storage:** 20 GB gp2
   - **VPC security group:** `notes-rds-sg`

> "RDS je potpuno managed servis — AWS automatski radi backup, patching, monitoring. Mi samo definišemo konfiguraciju i password."

3. Pokažite opciju **Additional configuration** → **Initial database name:** `notesdb`

### 6c. Kreiranje S3 bucketa — kroz Web UI

1. U pretragu upišite **S3** → **Create bucket**
2. Pokažite parametre:
   - **Bucket name:** `notes-app-frontend-94795`
   - **Region:** us-east-1 (ili po izboru)
   - **Block Public Access settings:** isključite (dozvolite javni read)
3. Nakon kreiranja, **Properties** → **Static website hosting** → **Enable**
   - **Index document:** `index.html`
4. **Permissions** → **Bucket policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::notes-app-frontend-94795/*"
  }]
}
```

### 6d. Upload frontend fajlova — kroz Web UI

1. Otvorite bucket → **Upload**
2. Dodajte: `index.html`, `style.css`, `script.js`
3. Nakon uploada, otvorite S3 website URL da provjerite

### 6e. Kreiranje EC2 instanci — kroz Web UI

1. **EC2** → **Instances** → **Launch instances**
2. Pokažite parametre (ne kreirajte):
   - **Name:** `notes-backend-1`
   - **AMI:** Amazon Linux 2023 (ili Amazon Linux 2)
   - **Instance type:** t2.micro
   - **Key pair:** Izaberite postojeći ili kreirajte novi
   - **Network settings:** 
     - VPC: Izabrani VPC
     - Subnet: Public subnet (AZ-a)
     - Auto-assign public IP: Enable
     - Security group: `notes-backend-sg`
3. **Advanced details** → **User data** — ovdje se nalazi script koji instalira Docker i pokreće Flask aplikaciju
4. Ponovite za drugu instancu u drugom public subnetu (AZ-b)

### 6f. Kreiranje ALB — kroz Web UI

1. **EC2** → **Load Balancers** → **Create Load Balancer** → **Application Load Balancer**
2. Pokažite parametre:
   - **Name:** `notes-alb`
   - **Scheme:** Internet-facing
   - **VPC:** notes-app-vpc
   - **Mappings:** Izaberite 2 public subnet-a (različite AZ)
   - **Security groups:** `notes-alb-sg`
   - **Listeners:** HTTP:80
3. **Target group:** kreirajte novu → `notes-backend-tg`
   - **Target type:** Instances
   - **Protocol:** HTTP:5000
   - **Health check path:** `/health`
   - **Register targets:** 2 EC2 instance
4. **Create Load Balancer**
5. Nakon kreiranja, **Listeners** → dodajte pravilo:
   - **Default:** Redirect to S3 (HTTP 301)
   - **Rule:** IF path=/api/* THEN forward to notes-backend-tg

### Šta govorite na kraju segmenta
> "Ovo je manualni pristup — svaki resurs se kreira zasebno kroz Web UI. Iako je edukativan, ručni proces je spor (30-45 minuta) i podložan greškama. Zato smo implementirali i Terraform automatizaciju koja sve ovo radi automatski za ~10 minuta. Oba pristupa su validna i prikazana u projektu."

---

## Segment 7: High Availability — gašenje instance (~90s)

### 7a. Prikaz target grupe (10s)
1. **EC2** → **Target Groups** → `notes-backend-tg` → **Targets** — 2 healthy

### 7b. Gašenje jedne instance (40s)
1. **EC2** → **Instances**
2. Desni klik na `notes-backend-1` → **Manage instance state** → **Stop** → **Stop**
3. Sačekajte da pređe u `Stopping` → `Stopped`
4. Vratite se na Target Groups — vidite `unhealthy`

### 7c. Aplikacija i dalje radi (20s)
1. Vratite se na frontend (S3 URL)
2. **Osvježite** (F5)
3. Kreirajte novu bilješku — **radi**

### 7d. Ponovno pokretanje (20s)
1. **EC2** → **Instances** → desni klik na `notes-backend-1` → **Start**
2. Nakon 30s, obje instance ponovo **healthy**

### Šta govorite
> "Ovo demonstrira visoku dostupnost. Kada smo ugasili jednu instancu, ALB je automatski detektovao da je nezdrava (health check na /health je pao) i uklonio je iz rotacije. Sav promet je preusmjeren na drugu instancu — aplikacija je nastavila da radi bez prekida. Kada smo instancu ponovo pokrenuli, ALB je automatski vratio u rotaciju. Ovo je ključna prednost AWS arhitekture sa više instanci i Load Balancerom."

---

## Segment 8: Arhitektura + Terraform kod (~90s)

### 8a. Dijagram arhitekture
Otvorite GitHub → `DOKUMENTACIJA.md` → skrolujte do dijagrama

```
Internet → S3 (frontend)     Internet → ALB (port 80)
                                          ├── /api/* → EC2 #1 + EC2 #2 → RDS
                                          └── default → redirect na S3
                      ═════ VPC 10.0.0.0/16 ═════
         Public AZ-a          Public AZ-b        Private AZ-a    Private AZ-b
         ALB + EC2 #1         ALB + EC2 #2        RDS (MySQL)     (standby)
         IGW → internet       IGW → internet      NAT → internet  NAT → internet
```

### 8b. Objašnjenje
> "Arhitektura se sastoji od tri sloja:
> 1. **Prezentacioni sloj** — S3 statički website (HTML/CSS/JS)
> 2. **Aplikacioni sloj** — 2 EC2 instance sa Docker/Flask, iza ALB-a
> 3. **Podatkovni sloj** — RDS MySQL u private subnet-ima
>
> VPC je podijeljen na public subnet-e (ALB, EC2) i private subnet-e (RDS). Public subnet-i imaju pristup internetu preko Internet Gateway-a, private subnet-i koriste NAT Gateway za izlazne veze (npr. Docker pull). ALB koristi path-based routing: /api/* → backend, sve ostalo → S3. Ovo omogućava da frontend i backend budu potpuno nezavisni."

### 8c. Terraform kod
Otvorite GitHub → `terraform/` folder → pokažite strukturu:

| Fajl | Sadržaj |
|------|---------|
| `main.tf` | VPC, subneti, IGW, NAT, route tables |
| `variables.tf` | Varijable (region, instance_type, db_username/password, key_name) |
| `outputs.tf` | Izlaz: frontend_url, api_url, alb_dns, rds_endpoint, s3_bucket |
| `ec2_alb.tf` | EC2 + ALB + Target Group + listener + routing pravil |
| `rds.tf` | RDS MySQL + db subnet group |
| `s3.tf` | S3 bucket + policy + upload + API_BASE templating |
| `security_groups.tf` | 3 security grupe |
| `userdata.sh` | Script za Docker i Flask na EC2 |
| `terraform.tfvars.example` | Primjer konfiguracije |

> "Ključna prednost Terraforma je **ponovljivost**. Nastavno osoblje može klonirati repozitorij, kopirati terraform.tfvars.example u terraform.tfvars, popuniti key_name i db_password, i pokrenuti `terraform init && terraform apply`. Za ~10 minuta, Terraform kreira svih 35 resursa na njihovom AWS account-u. Ovo garantuje da je rješenje potpuno prenosivo i testabilno."

---

## Segment 9: Dokumentacija i troškovi (~30s)

1. Otvorite `DOKUMENTACIJA.md` na GitHub-u
2. Pokažite sekcije:
   - **Procjena troškova** — ~$87/mj (24/7), ~$21/mj (radno vrijeme), $0 (AWS Academy)
   - **Opis izazova i rješenja** — 10 problema sa deployment-om

> "Dokumentacija sadrži arhitekturni dijagram, procjenu troškova korištenjem AWS Pricing Calculator-a, kompletna uputstva za pokretanje (ručno i kroz Terraform), te opis izazova na koje smo naišli — poput ALB routing konfiguracije, /api prefiksa na rutama, i VPC mrežne arhitekture. Ukupni mjesečni trošak za 24/7 rad je ~$87, ali u AWS Academy okruženju je pokriven lab budget-om."

---

## Dodatni savjeti za odbranu

### Prije snimanja
1. **Provjerite da li su obje EC2 instance Running** — ako ne, pokrenite ih
2. **Provjerite Target Group** — obje instance moraju biti **healthy**
3. **Provjerite S3 website** — da se učitava
4. **Obrišite istoriju browsera** ili koristite private/inkognito mode
5. **Postavite rezoluciju na 1920×1080** ako je moguće

### Tokom snimanja
- **Govorite polako i jasno** — profesori cijene razumljivost
- **Kad pokazujete Web UI, ne žurite** — svaki klik treba biti vidljiv
- **Objasnite ZAŠTO** ste nešto uradili, ne samo ŠTA ste uradili
- **Naglasite DVA pristupa** (automatizovani i manualni) — to pokazuje duboko razumijevanje
- **Ako pogriješite, samo nastavite** — greške se moge isjeći u montaži

### Šta profesori posebno gledaju
- Da li razumijete svaki AWS servis koji ste koristili
- Da li možete objasniti arhitekturu (ne samo pokazati)
- Da li ste samostalno riješili probleme na koje ste naišli
- Da li je kod organizovan i dokumentovan
- Da li je rješenje ponovljivo (Terraform omogućava ovo)

---

## Lista za provjeru (checklist)

### Prije snimanja
- [ ] AWS Academy sesija aktivna (Start Lab → zeleno dugme)
- [ ] Obje EC2 instance u statusu **Running**
- [ ] Target Group: obje instance **healthy**
- [ ] S3 website se učitava u browseru
- [ ] GitHub repo otvoren i spreman
- [ ] Screen recorder radi (test snimak 10s)
- [ ] Mikrofon radi

### Segmenti koje treba snimiti
- [ ] **Uvod** — šta je projekat, koje tehnologije
- [ ] **Pokretanje aplikacije** — S3 URL u browseru
- [ ] **CRUD demonstracija** — kreiranje, izmjena, brisanje bilješki
- [ ] **API poziv** — CloudShell ili curl
- [ ] **Pregled resursa (Web UI)** — EC2, ALB, Target Group, RDS, S3, VPC, Security Groups
- [ ] **Automatizovani deployment** — Terraform kod (main.tf, plan, apply)
- [ ] **Manualni deployment (Web UI)** — obrasci za kreiranje: SG, RDS, S3, EC2, ALB
- [ ] **High Availability** — gašenje jedne instance, aplikacija i dalje radi
- [ ] **Arhitektura** — dijagram i objašnjenje
- [ ] **Terraform kod** — struktura fajlova
- [ ] **Dokumentacija i troškovi**
- [ ] **Zaključak** (opciono)

### Nakon snimanja
- [ ] Snimak traje **8–10 minuta**
- [ ] Video uploadan na **Google Drive/YouTube** (Unlisted)
- [ ] Link dodat u `README.md` na GitHub-u
- [ ] Repozitorij je **public**
- [ ] Provjereno da nema osjetljivih podataka u repozitoriju

---

## Upload i dodavanje linka

### Google Drive
1. https://drive.google.com → **+ New** → **File upload**
2. Izaberite video → desni klik → **Share** → **Anyone with the link**

### YouTube
1. https://youtube.com → kamera ikona → **Upload Video**
2. Izaberite video → **Visibility:** **Unlisted** → **Save**

### Dodavanje u README.md
1. Otvorite `https://github.com/a-sestan/notes-app`
2. Kliknite na `README.md` → olovka (Edit)
3. Dodajte na kraj:
```markdown
## Video demonstracija

[Pogledajte video odbrane projekta](LINK_ZA_VIDEO)
```
4. Kliknite **Commit changes**
