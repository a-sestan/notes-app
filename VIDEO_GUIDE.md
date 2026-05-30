# Video snimak — Uputstvo korak po korak

> **Trajanje:** 5–10 minuta  
> **Cilj:** Prikazati kompletan rad sistema na AWS-u  
> **Napomena:** Ovo uputstvo je pisano za potpune početnike — svaki klik je opisan.

---

## Sadržaj snimka (redoslijed)

| # | Segment | Okvirno trajanje |
|---|---------|------------------|
| 1 | Pokretanje aplikacije — otvaramo S3 URL u browseru | ~30s |
| 2 | Pregled AWS resursa (EC2, RDS, S3, ALB, Security Groups) | ~3 min |
| 3 | Demonstracija rada — kreiranje, čitanje, brisanje podataka | ~2 min |
| 4 | Load Balancer distribucija + gašenje jedne instance | ~2 min |
| 5 | Kratki opis arhitekture (dijagram + objašnjenje) | ~2 min |

---

## Prije snimanja — provjerite da li je sve spremno

### Šta vam treba:
1. **Screen recorder** — OBS Studio (besplatan, preporučen), ili ugrađeni Windows Game Bar (Win + G)
2. **AWS Academy sesija** — otvorena i aktivna (Start Lab, sačekajte zeleno dugme)
3. **Dva browser taba**:
   - Tab 1: **AWS konzola** (otvorite preko AWS Academy: kliknite **AWS Details** → **Open AWS Console**)
   - Tab 2: **S3 website URL** aplikacije
4. **GitHub repo** — otvorite `https://github.com/a-sestan/notes-app` u trećem tabu (za arhitekturu)

### Vaši konkretni URL-ovi (prilagodite ako ste ponovo pokretali):
- **S3 website (frontend):** `http://notes-app-frontend-94795.s3-website-us-east-1.amazonaws.com`
- **ALB DNS:** `notes-alb-2018448528.us-east-1.elb.amazonaws.com`
- **RDS endpoint:** `notes-db.cqkmajlzi886.us-east-1.rds.amazonaws.com`

---

## Segment 1: Pokretanje aplikacije putem Load Balancera (~30s)

### Šta radite na snimku:

1. Otvorite **novi browser tab**
2. Zalijepite S3 URL: `http://notes-app-frontend-94795.s3-website-us-east-1.amazonaws.com`
3. Pritisnite Enter — vidite **Notes App** sa poljem za naslov, sadržaj, dropdown za tag, i dugme "Dodaj bilješku"

### Šta govorite (primjer):
> "Ovo je frontend naše aplikacije koji hostujemo na S3 bucketu kao statički website. Kada korisnik otvori ovaj URL, browser učitava HTML, CSS i JavaScript direktno sa S3. A API pozivi (npr. slanje nove bilješke) idu na Application Load Balancer koji ih prosljeđuje backendu."

---

## Segment 2: Pregled AWS konzole i konfigurisanih resursa (~3 min)

**Vratite se na AWS konzolu (tab 1).** Prikažite sljedeće servise redom:

### 2a. EC2 — instance (1 min)

1. U AWS konzoli, u polje za pretragu na vrhu upišite **EC2** i kliknite
2. Sa lijeve strane kliknite **Instances** (ili "Instances (running)")
3. Vidite **2 instance** koje su u statusu `Running`:
   - `notes-backend-1` (IP: 34.226.249.71)
   - `notes-backend-2` (IP: 44.200.72.183)

**Šta govorite:**
> "Imamo dvije EC2 instance tipa t2.micro koje pokreću Docker kontejner sa Flask backendom. Svaka instanca je u različitoj Availability Zone — ovdje jedna u us-east-1a, druga u us-east-1b. Ovo nam daje visoku dostupnost: ako jedna zona padne, druga i dalje radi."

4. Kliknite na jednu instancu, pa u donjem panelu kliknite **Security** tab
5. Pokažite da je Security Group `notes-backend-sg` i da dozvoljava port 5000 samo od ALB-a

### 2b. ALB — Load Balancer (45s)

1. Sa lijeve strane kliknite **Load Balancers** (pod "Load Balancing")
2. Vidite `notes-alb` — **State:** `Active`, **Type:** `application`
3. Kliknite na naziv ALB-a, pa kliknite **Listeners** tab
4. Pokažite pravilo:
   - **Default action:** Redirect to S3 (HTTP 301)
   - **Rule (priority 1):** IF path is `/api/*` → Forward to `notes-backend-tg`

**Šta govorite:**
> "Application Load Balancer prima sav promet na portu 80. Ako zahtjev ide na `/api/bilošta`, ALB ga prosljeđuje backend target grupi koja raspoređuje zahtjeve na obje EC2 instance. Sve ostalo (uključujući root `/`) preusmjerava se na S3 website."

5. Sa lijeve strane kliknite **Target Groups**, pa kliknite `notes-backend-tg`
6. Kliknite **Targets** tab — vidite obje instance sa statusom `healthy`
7. Ovo je dokaz da backend radi na obje instance

### 2c. RDS — baza podataka (30s)

1. U polje za pretragu upišite **RDS** i kliknite
2. Sa lijeve strane kliknite **Databases**
3. Vidite `notes-db` — **Status:** `Available`, **Engine:** `MySQL 8.0`, **Size:** `db.t3.micro`

**Šta govorite:**
> "RDS MySQL baza podataka je u potpunosti managed service — AWS automatski radi backup, patching i replikaciju. Naša aplikacija se povezuje preko endpointa koji vidite ovdje."

4. Kliknite na naziv baze i pokažite **Connectivity & security** tab:
   - **Endpoint:** `notes-db.cqkmajlzi886.us-east-1.rds.amazonaws.com`
   - **VPC Security Groups:** `notes-rds-sg` (port 3306 — samo backend instance)

### 2d. S3 — bucket za frontend (30s)

1. U polje za pretragu upišite **S3** i kliknite
2. Kliknite na bucket `notes-app-frontend-94795`
3. Vidite tri fajla: `index.html`, `style.css`, `script.js`

**Šta govorite:**
> "S3 bucket hostuje statički frontend. Ovo je najjeftiniji način hostinga — bucket policy dozvoljava javni read, a mi smo uključili Static Website Hosting. Cijena je zanemarljiva (~$0.023/GB mjesečno)."

4. Kliknite **Properties** tab, pa skrolajte do **Static website hosting** — pokažite URL

### 2e. VPC i subneti — mrežna infrastruktura (30s)

1. U polje za pretragu upišite **VPC** i kliknite
2. Sa lijeve strane kliknite **Your VPCs** — vidite VPC (može biti default ili `notes-app-vpc` ako je kreiran kroz Terraform)
3. Kliknite **Subnets** — vidite najmanje 2 public subnet-a (sa mapiranjem javne IP adrese) i 2 private subnet-a (bez javne IP)
4. Pokažite route tables:
   - **Public RT:** `0.0.0.0/0` → Internet Gateway
   - **Private RT:** `0.0.0.0/0` → NAT Gateway

**Šta govorite:**
> "VPC je izolovana mreža u kojoj su svi resursi. Imamo dva public subnet-a (u različitim Availability Zones) za ALB i EC2 instance, i dva private subnet-a za RDS bazu. Public subnet-i imaju pristup internetu preko Internet Gateway-a, dok private subnet-i koriste NAT Gateway za izlazak na internet (npr. za Docker pull), ali nisu direktno dostupni izvana."

### 2f. Security Groups — sumarno (15s)

1. U pretragu upišite **Security Groups** (ili **VPC** → Security Groups)
2. Pokažite 3 grupe sa opisom:
   - `notes-alb-sg`: port 80 od svuda (0.0.0.0/0)
   - `notes-backend-sg`: port 5000 samo od ALB SG + port 22 (SSH)
   - `notes-rds-sg`: port 3306 samo od Backend SG

---

## Segment 3: Demonstracija rada aplikacije (~2 min)

**Vratite se na frontend (tab sa S3 URL-om).**

### 3a. Kreiranje bilješke (30s)

1. U polje **Naslov** upišite: `Demo biljeska`
2. U polje **Sadržaj** upišite: `Ova biljeska je kreirana preko AWS aplikacije`
3. U dropdown **Tag** odaberite: `posao`
4. Kliknite na zvjezdicu (⭐) da pinujete (ako postoji)
5. Kliknite **Dodaj bilješku**
6. Vidite da se nova bilješka pojavila na listi

### 3b. Kreiranje još jedne bilješke (20s)

1. Naslov: `Ideja za projekat`
2. Sadržaj: `Koristiti Terraform za sve resurse`
3. Tag: `ideje`
4. Dodajte

### 3c. Izmjena bilješke (20s)

1. Kliknite na olovku ✏️ (edit) pored bilješke "Demo biljeska"
2. Promijenite naslov u: `Demo biljeska - izmijenjeno`
3. Sačuvajte

### 3d. Brisanje bilješke (10s)

1. Kliknite na 🗑️ (delete) pored bilješke "Ideja za projekat"
2. Bilješka nestaje

### 3e. Provjera u bazi — direktno (30s, opciono)

Ako želite impresionirati profesora, pokažite da su podaci stvarno u RDS-u:

1. Otvorite **CloudShell** ili **AWS CLI** na lokalnom terminalu
2. Upišite:
```bash
# Kreiramo bilješku preko API-ja
curl -s -X POST "http://notes-alb-2018448528.us-east-1.elb.amazonaws.com/api/notes" \
  -H "Content-Type: application/json" \
  -d '{"title":"API Biljeska","content":"Kreirana preko komandne linije","color":0,"pinned":false}'

# Čitamo sve bilješke
curl -s "http://notes-alb-2018448528.us-east-1.elb.amazonaws.com/api/notes"
```

---

## Segment 4: Load Balancer distribucija + gašenje instance (~2 min)

### 4a. Prikaz target grupe (15s)

1. Vratite se u AWS konzolu → EC2 → Target Groups → `notes-backend-tg`
2. Kliknite **Targets** tab — pokažite dvije healthy instance

### 4b. Gašenje jedne instance (45s)

1. U AWS konzoli idite na **EC2 → Instances**
2. **Desni klik** na `notes-backend-1` → **Manage instance state** → **Stop**
3. Pojavi se dijalog — kliknite **Stop** (potvrdite)
4. Instance prelazi u status `Stopping` → `Stopped` (20-30 sekundi)
5. Dok čekate, vratite se na Target Groups → **Targets** tab
6. Nakon ~30 sekundi, vidite da je `notes-backend-1` sada `unhealthy` (draining)

### 4c. Aplikacija i dalje radi (30s)

1. Vratite se na frontend (S3 URL)
2. Kliknite **Osvježi** (F5)
3. Kreirajte novu bilješku — **radi i dalje**
4. Objasnite: "Druga instanca preuzima sav promet jer je ALB detektovao da je prva nezdrava"

### 4d. Ponovno pokretanje (30s)

1. Vratite se u **EC2 → Instances**
2. Desni klik na `notes-backend-1` → **Manage instance state** → **Start**
3. Sačekajte 20-30 sekundi da bude `Running`
4. Vratite se u Target Groups — obje su ponovo `healthy`
5. Promet se automatski raspoređuje na obje instance

---

## Segment 5: Kratki opis arhitekture (~2 min)

### 5a. Otvorite GitHub repo (15s)

1. Otvorite tab sa `https://github.com/a-sestan/notes-app`
2. Otvorite `README.md` da vidite ASCII dijagram arhitekture

### 5b. Objasnite arhitekturu (1.5 min)

Pokažite na ekranu sljedeći dijagram:

```
Internet
  │
  ├── http://notes-app-frontend-XXXXX.s3-website-us-east-1.amazonaws.com
  │     └── S3 static website (index.html, style.css, script.js)
  │
  └── http://notes-alb-XXXXXXXX.us-east-1.elb.amazonaws.com
        └── ALB (port 80)
              │
              ├── Default: HTTP 301 redirect → S3 website
              │
              └── Rule: /api/*  →  TargetGroup (port 5000)
                                    │
                          ┌─────────┴─────────┐
                          │                   │
                    EC2 #1 (AZ-a)        EC2 #2 (AZ-b)
                    ┌──────────┐        ┌──────────┐
                    │ Docker   │        │ Docker   │
                    │ Flask    │        │ Flask    │
                    └────┬─────┘        └────┬─────┘
                          │                   │
                          └─────────┬─────────┘
                                    │
                             ┌──────┴──────┐
                             │  RDS MySQL  │
                             │ (private    │
                             │  subnet)    │
                             └─────────────┘

══════════════  VPC 10.0.0.0/16  ════════════════

  Public subnet (AZ-a)      Public subnet (AZ-b)
  ┌─────────────────┐      ┌─────────────────┐
  │ ALB + EC2 #1    │      │ ALB + EC2 #2    │
  │ IGW → internet  │      │ IGW → internet  │
  └─────────────────┘      └─────────────────┘

  Private subnet (AZ-a)    Private subnet (AZ-b)
  ┌─────────────────┐      ┌─────────────────┐
  │ RDS (MySQL)     │      │ (multi-AZ      │
  │ NAT → internet  │      │  standby)       │
  └─────────────────┘      └─────────────────┘
```

**Objašnjenje koje govorite:**

> "Cijeli sistem se nalazi unutar VPC mreže (10.0.0.0/16) koja je podijeljena na četiri subnet-a: dva public i dva private, raspoređena u dvije Availability Zone (us-east-1a i us-east-1b).
>
> **Public subnet-i** sadrže ALB i EC2 instance. Pristup internetu imaju preko Internet Gateway-a. ALB prima sav promet na portu 80 i:
> - Ako je putanja `/api/*` → prosljeđuje backend target grupi
> - Sve ostalo → HTTP 301 redirect na S3 website
>
> **Private subnet-i** sadrže RDS MySQL bazu. One nemaju direktan pristup internetu, već koriste NAT Gateway za izlazne veze (npr. za software updates). RDS prima konekcije samo sa backend security group-a na portu 3306.
>
> **EC2 instance** (2 × t2.micro) pokreću Docker kontejner sa Flask aplikacijom. Target grupa ravnomjerno raspoređuje zahtjeve (round-robin). Ako jedna instanca padne, ALB je automatski uklanja nakon neuspjelih health check-ova i sav promet ide na zdravu instancu.
>
> **S3 bucket** hostuje statički frontend (HTML/CSS/JS). Ovo je najjeftiniji način hostinga i ne zahtijeva server.
>
> **Terraform** definiše svaki resurs kao kod — VPC, subneti, security grupe, EC2, RDS, S3, ALB. Ovo omogućava ponovljiv deployment u bilo kom AWS account-u sa samo `terraform apply`."

### 5c. Prikažite Terraform strukturu (30s)

1. U GitHub repu otvorite folder `terraform/`
2. Pokažite organizaciju fajlova:
   - `main.tf` — VPC, subneti, route tables, IGW, NAT Gateway, provideri
   - `variables.tf` — sve varijable (region, instance_type, db_username/password/name, key_name)
   - `outputs.tf` — izlazne vrijednosti (frontend_url, api_url, alb_dns, rds_endpoint, s3_bucket_name)
   - `provider.tf` — AWS provider
   - `s3.tf` — S3 bucket + policy + upload fajlova (sa automatskim popunjavanjem API_BASE)
   - `rds.tf` — RDS MySQL + db subnet group
   - `ec2_alb.tf` — EC2 instance + ALB + Target Group + listener + routing pravilo
   - `security_groups.tf` — 3 security grupe sa pravilima
   - `userdata.sh` — script koji se izvršava na EC2 (instalira Docker, pokreće Flask)
   - `terraform.tfvars.example` — primjer konfiguracije

**Šta govorite:**
> "Terraform kod je organizovan u zasebne fajlove po odgovornostima. Sve promjenjive vrijednosti su izdvojene u variables.tf, a output-i u outputs.tf. Nastavno osoblje može testirati Terraform na svom AWS account-u: samo kopiraju terraform.tfvars.example u terraform.tfvars, popune key_name i db_password, i pokrenu terraform init && terraform apply. Kod će kreirati kompletnu infrastrukturu — 35 resursa — za ~10 minuta."

### 5c. Pokažite Terraform kod (30s)

1. U GitHub repu otvorite folder `terraform/`
2. Pokažite fajlove:
   - `provider.tf` — AWS provider
   - `main.tf` — glavni resursi
   - `s3.tf` — S3 bucket
   - `rds.tf` — RDS baza
   - `ec2_alb.tf` — EC2 + ALB + Target Group
   - `security_groups.tf` — Security Groups

**Šta govorite:**
> "Cijela infrastruktura je definirana kao kod pomoću Terraforma. Ovo omogućava ponovljiv deployment — jednim klikom možemo kreirati identičnu infrastrukturu u bilo kom regionu ili accountu."

---

## Dodatni savjeti za snimanje

### Priprema
1. **Zatvorite sve nepotrebne tabove** i aplikacije
2. **Obrišite istoriju** browsera ili koristite inkognito/private mode
3. **Provjerite mikrofon** — snimite testnih 10 sekundi pa preslušajte
4. **Postavite rezoluciju ekrana** na 1920x1080 (ako može)

### Tokom snimanja
- **Govorite polako i jasno** — zamislite da objašnjavate drugaru koji nije nikad koristio AWS
- **Pauzirajte između segmenata** ako vam treba vremena da se pripremite
- **Ne brinite ako pogriješite** — možete nastaviti pa isjeći grešku poslije
- **Pratite redoslijed iznad** — tako ćete biti sigurni da ništa niste propustili

### Montaža (opciono)
- Koristite **Shotcut** ili **DaVinci Resolve** (besplatni) da isječete greške
- Dodajte **tekstualne oznake** na ekran (npr. "S3 bucket", "ALB", itd.)

### Prije finalne verzije
1. Pogledajte cijeli snimak od početka do kraja
2. Provjerite da li se vidi svaki klik (ako nešto nije vidljivo, presnimite taj dio)
3. Provjerite da li se čuje svaka riječ

---

## Lista za provjeru (checklist) — prije nego pošaljete

- [ ] S3 frontend se vidi u browseru
- [ ] Kreirali ste bar jednu bilješku i ona se pojavila
- [ ] Izmijenili ste bilješku
- [ ] Obrisali ste bilješku
- [ ] Pokazali ste EC2 instance (2 running, jedna po AZ)
- [ ] Pokazali ste ALB listener pravilo (/api/* → backend)
- [ ] Pokazali ste Target Group (2 healthy targets)
- [ ] Pokazali ste RDS bazu (status Available)
- [ ] Pokazali ste S3 bucket (index.html, style.css, script.js)
- [ ] Pokazali ste VPC i subnet-e (2 public + 2 private)
- [ ] Pokazali ste Security Groups (3 grupe sa pravilima)
- [ ] Zaustavili ste jednu EC2 instancu
- [ ] Pokazali ste da aplikacija i dalje radi
- [ ] Ponovo pokrenuli instancu
- [ ] Objasnili ste arhitekturu (dijagram sa VPC, subnetima, AZ-ovima)
- [ ] Pokazali ste Terraform kod (main.tf, variables.tf, outputs.tf, ec2_alb.tf, rds.tf, s3.tf, security_groups.tf)
- [ ] Snimak traje 5-10 minuta
- [ ] Snimak je uploadan na Google Drive/YouTube (ne-LinkedIn)
- [ ] Link ka snimku je dodat u GitHub README.md

---

## Kako uploadati video i dodati link u README?

### Upload na Google Drive
1. Idite na https://drive.google.com
2. Kliknite **+ New** → **File upload**
3. Izaberite video fajl
4. Desni klik na fajl → **Share** → **General access** → **Anyone with the link**
5. Kopirajte link

### Upload na YouTube (not-listed)
1. Idite na https://youtube.com
2. Kliknite na kameru ikonu → **Upload Video**
3. Izaberite video
4. U **Visibility** izaberite **Unlisted**
5. Kliknite **Save**
6. Kopirajte link

### Dodavanje linka u README.md
1. Otvorite GitHub repo: `https://github.com/a-sestan/notes-app`
2. Kliknite na `README.md`
3. Kliknite olovku (Edit)
4. Na kraju fajla (prije ```) dodajte:
```markdown
## Video snimak

[Pogledajte video demonstraciju](LINK_ZA_VIDEO)
```
5. Kliknite **Commit changes**
