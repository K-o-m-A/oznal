# Príprava na obhajobu — `scenario_3.rmd` (feature selection)

---

## 0.0 Pre úplných začiatočníkov — o čom to celé je

### Úloha
Máme **40 príznakov** (po EDA exclusions zo 50 pôvodných) a chceme
postaviť **logistický klasifikátor** phishing vs. legit. Otázka tohto
scenára nie je *"aký je najlepší klasifikátor"* (to bola otázka S2) —
ale **"ktoré príznaky vlastne treba"** a **ako sa rôzne metódy
feature-selection zhodnú/nezhodnú**.

### Prečo nás to vôbec zaujíma
- **Menej príznakov** → menší model, rýchlejšia inferencia, lacnejší
  zber dát v produkcii.
- **Lepšia interpretovateľnosť** — keď model má 9 namiesto 34
  príznakov, vieme audítorovi vysvetliť *prečo* bol konkrétny link
  blokovaný.
- **Štatistická poctivosť** — keď v modeli ostane príznak, ktorý
  *nie je* štatisticky významný, máme problém: model na ňom stojí, ale
  nemáme dôkaz, že jeho efekt je reálny a nie šum.

### Tri triedy metód feature-selection (a prečo máme po jednej z každej)
1. **Filter metódy** (mimo zadania) — pozerajú sa na korelácie /
   chí-kvadrát medzi príznakom a triedou, **bez modelu**. Rýchle, ale
   nevidia interakcie.
2. **Embedded metódy** — feature selection sa deje **vnútri tréningu**
   modelu cez regularizáciu. *Lasso* (L1) zatlačí niektoré koeficienty
   na presnú nulu = automaticky zahodí príznak. *Ridge* (L2) iba
   stiahne koeficienty (nikdy presne na 0) = nerobí selection, ale je
   referenciou *"čo by sa stalo, keby sme všetko nechali"*.
3. **Algoritmické metódy** — rozhodujú *navonok* podľa kritéria.
   *Forward AIC* začne s nulovým modelom a postupne pridáva ten
   príznak, ktorý najviac zníži AIC. Stop = AIC sa už neznižuje.

### Čo zadanie chce konkrétne
> *"Compare one algorithmic + two embedded methods. Report how many
> features you ultimately retain, and which features lose statistical
> significance as you add or remove predictors."*

Voľba: **Forward (algoritmické) + Ridge + Lasso (embedded)** = presne
1 + 2, podľa zadania.

### Aký je rozdiel oproti scenario_2
- S2 sa pýta *aký model triedi najlepšie* (LR vs RF vs SVM vs KNN…).
- S3 sa pýta *aké príznaky model potrebuje*. Triedič je vždy logistická
  regresia (parametrický). Otázka je, **koľko a ktorých** príznakov.
- Tieto dva scenáre **nepoužívajú jeden druhého** ako vstup. Sú to dve
  paralelné lentiky na ten istý dataset.

---

## 0. Slovník pojmov — feature-selection slang

### Logistická regresia (LR) v skratke
$$ \log \frac{P(\text{phishing})}{1 - P(\text{phishing})} = \beta_0 + \sum_j \beta_j x_j $$

Každý koeficient $\beta_j$ hovorí: *"keď x_j stúpne o 1, log-odds
phishingu stúpne o $\beta_j$".* Klasický parametrický model.

### Regularizácia — pripomenutie
Pridáme do stratovej funkcie penalizáciu závislú od koeficientov:
$$ -\text{loglik}(\beta) + \lambda \cdot \text{Pen}(\beta) $$

- **Ridge (L2):** $\text{Pen} = \sum_j \beta_j^2$. Geometricky: izolíny
  penalizácie sú **kruhy**. Riešenie sa stiahne k nule, ale **nikdy
  presne na 0**.
- **Lasso (L1):** $\text{Pen} = \sum_j |\beta_j|$. Izolíny sú **kosoštvorce
  s rohmi na osách**. Riešenie veľmi často padá presne **na roh** ⇒
  presne nulový koeficient ⇒ feature dropped.
- **ElasticNet:** $\alpha \cdot L_1 + (1-\alpha) \cdot L_2$. Kompromis.
  V S3 sme ho **zámerne nezahrnuli** (vysvetlenie v §1.2 R-mdku).

### glmnet — knižnica čo to počíta
- `cv.glmnet(X, y, alpha = 0)` = Ridge.
- `cv.glmnet(X, y, alpha = 1)` = Lasso.
- Vráti **celú regularizačnú cestu** (~80 hodnôt λ, od veľkej po
  malú) a navyše **CV vyber** dvoch konkrétnych λ:
  - **`lambda.min`** = λ s najmenšou CV deviance / najvyššou CV AUC.
    Najlepšia predikcia, ale najmenej parsimoniózny model.
  - **`lambda.1se`** = najväčšia λ, kde CV AUC je ešte v rámci 1·SE
    od `lambda.min`. **Sparsejší model "len trochu horší"**. Klasická
    voľba pre interpretovateľnosť.

V S3 reportujeme retained sets pri **`lambda.1se`** — to je tá voľba,
kde lasso najviac drví príznaky a kde rozdiel oproti ridge je
najviditeľnejší.

### AIC — Akaike Information Criterion
$$ \text{AIC} = -2 \log\hat{L} + 2k $$

kde $\hat{L}$ je likelihood modelu a $k$ počet parametrov. Cieľ: čím
menšia AIC, tým lepšie. Penalizácia $+2k$ ráta s tým, že **každý
ďalší parameter musí "zaplatiť"** dvojnásobok svojej váhy v
likelihood, inak ho nemáme pridávať.

**Forward selection** = chamtivý algoritmus:
1. Začni s `glm(y ~ 1)` (iba intercept).
2. Skús pridať každý ešte-nepridaný príznak, vyber ten, ktorý najviac
   zníži AIC.
3. Ak žiadne pridanie AIC neznižuje, stop.

### Wald test a p-value
V `summary(glm(...))` máme pre každý koeficient stĺpec `Pr(>|z|)` =
**Waldova p-hodnota**. Ide o test:
$$ H_0: \beta_j = 0 \quad \text{vs.} \quad H_1: \beta_j \ne 0 $$

Test používa štatistiku $z_j = \hat{\beta}_j / \text{SE}(\hat{\beta}_j)$
porovnávanú s normálnou distribúciou. Pri **p < 0.05** zvyčajne
hovoríme *"koeficient je štatisticky signifikantný"*.

**Pasca:** Wald p-hodnoty platia **iba** keď nezávisle vyberieme
príznaky **pred** pohľadom na dáta. Akonáhle robíme **stepwise
selection**, p-hodnoty po selekcii sú **biased** — model sa "obhájil"
na rovnakých dátach, na ktorých p-hodnoty počítame. Toto je
**post-selection inference** problém (viď §6).

### Wald p-flip
Termín, ktorý zavádzame v S3: **flip = predtým signifikantný príznak
(p < 0.05) sa stane nesignifikantným**, alebo opačne, **ako pridáme do
modelu jeho korelovaného partnera**.

Mechanika: keď sú dva príznaky silne korelované, ich "vysvetľovacia
sila" sa rozdelí. Pred vstupom partnera má jeden z nich celý kredit
(p ≈ 10⁻⁹⁰); po vstupe partnera sa kredit rozdelí ⇒ obe SE narastú,
obe Wald štatistiky padnú, p-hodnoty môžu vyskočiť na 0.5–0.9.

Toto je **priama empirická signatúra multikolinearity**.

### Jaccard index
$$ J(A, B) = \frac{|A \cap B|}{|A \cup B|} $$

Mieria sa "podiel rovnakých prvkov". Pre dve množiny zachovaných
príznakov hovorí: 1.0 = identické, 0.0 = žiadny prienik.

### Retention rate (per-feature, naprieč foldmi)
Z 10 fold-modelov spočítame, **v koľkých** zostal feature `j` v
retained sete. Hodnota 1.0 = vo všetkých 10, 0.0 = nikde.
- Ridge má retention rate vždy 1.0 (nezahadzuje).
- Lasso má retention rate v {0, 0.1, …, 1.0}. **0.5 = "coin-flip"
  feature** = známka nestability.

### Tier (úroveň)
Skupina príznakov definovaná v EDA / S2:
- **Lexical** (13 príznakov): iba URL string, všetky príznaky majú
  netriviálnu unikátnu informáciu, multikolinearita iba v jednom
  blokovi (URL-length cluster).
- **FullLite** (34 príznakov): Lexical + Trust + Behavior bez 6
  near-leakerov. Bohatý na redundanciu — URL-length cluster + page-count
  cluster + ďalšie korelované Behavior dvojice.

V S3 testujeme iba tieto dva tiery, lebo H2 je **predikcia o ich
kontraste**.

### Multikolinearita a "equivalence classes" príznakov
Ak je `URLLength`, `NoOfLettersInURL` a `NoOfDegitsInURL` korelovaná
trojica s |r| > 0.84, pre LR sú **takmer vymeniteľné**. Lasso si
vyberie jeden, Forward si môže vybrať iný (alebo dva), Ridge všetkých
troch zachová s rozdelenou váhou. **Žiadny z výberov nie je "zlý"** —
sú to ekvivalentné riešenia v priestore predikcií. Ale to je presne
dôvod, prečo retained sets divergujú a Wald p-hodnoty flipujú.

### CACHE_VERSION
String pridávaný do názvu RDS súborov. Pri zmene metodológie /
factor-konvencie ho **bumpneme**, čím staré cache prestanú zodpovedať
schéme a notebook ich pri ďalšom rendere refittne. Aktuálna hodnota
`v3_phishing_second_level` označuje, že factor je `levels = c(0,1),
labels = c("Legitimate", "Phishing")` — **Phishing je druhá úroveň**,
takže `predict(..., type = "response")` z glmnet/glm vráti P(Phishing).

---

## 1. Scenár a hypotéza

### 1.1 Prečo Lexical *aj* FullLite

H2 testujeme cez **dva režimy redundancie**, nie ako *prítomnosť vs.
neprítomnosť*:

- **Lexical** = "small isolated cluster". 13 príznakov, jeden
  3-feature URL-length blok (URLLength, NoOfLettersInURL,
  NoOfDegitsInURL — VIF > 1000 z EDA), zvyšné príznaky majú medzi
  sebou len mierne korelácie. Predikcia: Lasso a Forward sa zhodnú
  **viac** (jeden malý klaster, málo blokových reprezentantov na
  výber).
- **FullLite** = "rich multi-cluster". 34 príznakov, niekoľko
  korelovaných blokov (URL-length cluster + page-count cluster +
  binárne near-duplicates ako HasFavicon/HasDescription). Predikcia:
  Lasso a Forward sa zhodnú **menej** (viac klastrov = viac
  ekvivalentných reprezentantov, viac priestoru pre divergenciu).

**Dôležité pre obhajobu:** Lexical NIE JE „bez redundancie" —
multikolinearitný klaster tam je. Je to len **menší a izolovanejší**
ako na FullLite. H2 predikuje *kontrast medzi tiermi*, nie binárny
on/off stav redundancie.

### 1.2 Prečo nie aj Trust a Behavior

- **Trust (7 príznakov):** príliš malý priestor na to, aby vznikla
  bloková redundancia. Žiadny korelovaný blok = žiadna pozorovateľná
  divergencia metód. Zahrnutie by len rozriedilo signál.
- **Behavior (14 príznakov bez 6 leakerov):** dimenzionálne medzi
  Lexical a FullLite, jeden korelovaný blok (page-count). Zahrnutie
  by neprinieslo nový kontrast — H2 testujeme cez **dva extrémy**, nie
  cez gradient.

### 1.3 Voľba metód — 1 algoritmické + 2 embedded

Zadanie dovolí Forward / Backward / Stepwise pre algoritmickú časť a
Lasso / Ridge / ElasticNet pre embedded.

#### Forward namiesto Backward / Stepwise
Empiricky overené: AIC procedúry (Forward / Backward / Stepwise)
konvergujú na takmer identický retained set na oboch tieroch.
Reportovať tri takmer-identické tabuľky by bolo plnenie miesta.
Forward navyše generuje **per-step p-value trajectory**, ktorá je
presne tá vec, ktorú zadanie literálne pýta (*"lose significance as
you **add** predictors"*).

#### Ridge + Lasso, drop ElasticNet
Ridge ($\alpha = 0$) a Lasso ($\alpha = 1$) sú dva extrémy
regularizačnej osi — **najostrejší kontrast**. ElasticNet pri $\alpha
= 0.5$ je empiricky **interpolácia** (na Lexical sa retained set líši
od Lasso o 1 príznak, koeficienty sú v rámci 15 % od Lasso, AUC
zhoduje na 3 desatiny). Pridávať tretí riadok do každej tabuľky, ktorý
hovorí *"medzi Ridge a Lasso, pozri Lasso"* je strata kvalitnej obhajoby.

### 1.4 H2 (Scenario 3) — "Predictor redundancy increases with tier richness"

> *Divergencia medzi Lasso a Forward retained sets **rastie s
> bohatosťou tieru o korelované bloky**. Na **Lexical** (jeden malý
> izolovaný klaster) sa metódy zhodnú viac na tom, ktoré príznaky sú
> dôležité; na **FullLite** (viacero prekrývajúcich sa klastrov) sa
> zhodnú menej.*

#### Jedno gating kritérium

| # | Kritérium | Prah |
|---|-----------|------|
| C1 | Jaccard(Lasso, Forward) **klesá** z Lexical na FullLite | $J_\text{FullLite} < J_\text{Lexical}$ (strict) |

**Pravidlo verdiktu:** H2 je **podporená** ak C1 drží — Lasso a
Forward sa zhodnú viac na malom-klastrovom tieri než na
viac-klastrovom. Žiadne absolútne prahy (0.85, 0.70 atď.) — len
**smer kontrastu**. Dôvod: absolútne hodnoty Jaccardu sú citlivé na
voľbu λ, AIC penalty a sample jitter; smer kontrastu je tá robustná
empirická predikcia.

**Descriptive support (nie gating).** Sledujeme aj:
- $\lvert k_\text{Lasso} - k_\text{Forward}\rvert$ na oboch tieroch
  — mal by tiež rásť (FullLite > Lexical) ak H2 platí
- počet Wald p-flipov pozdĺž Forward cesty — mal by byť aspoň
  rovnako vysoký na FullLite ako na Lexical, a Lexical flipy (ak
  sú) by mali padnúť na URL-length klaster, nie na izolované
  príznaky

Concordance všetkých troch signálov = silná evidencia. Len-gating
podpora = slabšia ale stále podporená H2.

#### Prečo single-criterion design

- **Robustnosť voči parametrom.** Trojitá tabuľka s konkrétnymi
  prahmi (0.85, 0.70, 3 flipov) sa môže rozsynchronizovať s cache
  pri zmene `lambda.min.ratio`, `nlambda` alebo seedu. Smerový
  kontrast tieto vplyvy ignoruje pokiaľ ostáva monotónny.
- **Falsifikovateľnosť.** H2 sa **dá zamietnuť** — keby
  $J_\text{FullLite} \ge J_\text{Lexical}$, redundancia by sa
  nepremietla do divergencie metód a hypotéza padne. Nie je to
  tautológia.
- **Mapping na zadanie.** Zadanie pýta *"how many features... and
  which lose significance"* — k a p-flipy sú deliverables, nie
  hypotézové gatingy. Forsírovať ich do gating prahov bolo
  metodologicky nadbytočné.

#### Bridge na H1
S2 ukázala, že parametrický–neparametrický AUC gap mizne na FullLite.
S3 dáva alternatívne čítanie tohto výsledku: na FullLite je dosť
**redundancie**, ktorú regularizovaný parametrický model dokáže
absorbovať = priblížiť sa neparametrickému ceiling-u. Toto **nie je
gating kritérium** H2 — len naratívne pozorovanie v §7.

---

## 2. Načítanie dát a exclusions

### 2.1 Identický recept ako S2 / S5
Tie isté **40 príznakov po EDA exclusions** (5 computed scores + 1
redundantný binárny + 4 pomery). Takže VIF, SMD, šikmosť čísla z EDA
priamo platia.

### 2.2 Factor order — dôležitá pasca

```r
factor(label, levels = c(0, 1), labels = c("Legitimate", "Phishing"))
```

**Phishing musí byť druhá úroveň.** Glmnet aj glm interne berú **druhú
úroveň ako "úspech" (1)**. Preto:
- `predict(model, type = "response")` vráti P(Phishing).
- `confusionMatrix(positive = "Phishing")` sa zhoduje s predikciami.
- `pROC::roc(levels = c("Legitimate", "Phishing"), direction = "<")` —
  positive je správna druhá úroveň.

V predošlej verzii bol factor `c("Phishing", "Legitimate")` — to robilo
P(Legit) namiesto P(Phishing) a celý report mal AUC ≈ 0.05 namiesto
0.95 (1 − AUC bug). Po oprave sme **bumpli CACHE_VERSION** na
`v3_phishing_second_level`, čím sa staré cache zneplatnili a nový
render všetko prefittol.

#### Quick smoke-test
- `mean(predict(model))` na vyváženej vzorke ≈ 0.5
- `AUC > 0.5`

Ak ktorýkoľvek z týchto je obrátený, factor je v zlom poradí.

### 2.3 Subsample, split, folds

Identicky ako v S2:
- 30 000 stratifikovaných riadkov z 235 k.
- 80/20 train/test split.
- 10 stratified folds na CV (cez `createFolds`).
- Zdieľané fold indexy pre Ridge, Lasso, Forward — porovnanie je
  **párované**.

### 2.4 Preprocessing
- `log1p()` na spojité príznaky (EDA §4.4 ukázala 19/22 |skew| > 2).
- Center + scale (mean 0, SD 1).
- Binárne príznaky tiež štandardizované — glmnet by to aj vnútorne
  spravil, ale explicitne nech sú koeficienty priamo čitateľné.

### 2.5 Multicollinearity recheck (§2.4 v rmd)
Vlastný `cor` v notebooku pre transparentnosť. Reportujeme všetky
páry s |r| > 0.7 na oboch tieroch:

| Tier | Páry s |r| > 0.7 |
|------|------------------|
| Lexical | URLLength ↔ NoOfLettersInURL (~0.99), URLLength ↔ NoOfDegitsInURL (~0.85), NoOfLettersInURL ↔ NoOfDegitsInURL (~0.83) |
| FullLite | URL-length cluster + page-count features korelujú vo viacerých dvojiciach |

To je presne ten **predpokladový základ**, na ktorom H2 stojí.

---

## 3. Embedded — Ridge a Lasso

### 3.1 cv.glmnet konfigurácia

```r
cv.glmnet(X_train, y_train, family = "binomial",
          alpha = 0,            # Ridge; 1 = Lasso
          nfolds = 10,
          standardize = FALSE,  # už sme štandardizovali ručne
          type.measure = "auc",
          nlambda = 80,
          lambda.min.ratio = 1e-2,
          maxit = 1e6)
```

#### Prečo `nlambda = 80`?
Defaultne 100. 80 stačí pre hladké zachytenie celej cesty od silne
penalizovanej (všetko ≈ 0) po skoro-OLS. Menej ako 50 → cesty by
mohli preskočiť optimum λ.

#### Prečo `lambda.min.ratio = 1e-2`?
Default je `1e-4`, čo by sa mohlo blížiť OLS tak, že sa Hessián stane
singulárnym. Pri n/p > 1000 stačí 1e-2 (aktuálne ratio na Lexical:
24000/13 ≈ 1850) — model nikdy nezostane bez regularizácie.

#### Prečo `type.measure = "auc"`?
CV výber λ je založený na maximalizácii AUC priamo na CV foldoch (nie
na deviance). Konzistentné s metrikami v S2.

#### Prečo `standardize = FALSE`?
Glmnet by inak štandardizoval ešte raz, čo by zmenilo škálu
koeficientov. My sme štandardizovali v §2.4, koeficienty
zodpovedajú **z-score škále** = priamo porovnateľné medzi príznakmi.

### 3.2 Regularization paths (§3.2 v rmd)
2×2 grid (Ridge / Lasso × Lexical / FullLite). X-os: `log(λ)`.

**Čo na nich vidno:**
- **Ridge:** všetky čiary ostávajú **nenulové** pre akékoľvek λ. Čím
  väčšie λ, tým bližšie k 0. **Žiaden zub v zelenej čiare**, žiadne
  presné nuly.
- **Lasso:** čiary postupne padajú na **presné 0** (geometria
  L1 normy). Poradie pádov je algoritmickou odpoveďou na otázku
  *"aký feature je najmenej dôležitý pri postupne silnejšej
  penalizácii"*.
- **Vertikálne čiarkované línie** označujú `lambda.min` (vľavo) a
  `lambda.1se` (vpravo). Reportujeme retained set pri 1se = sparsejší.

### 3.3 Retained features pri `lambda.1se` (§3.3)

Ako čítať tabuľku: pre každý tier × metódu počet **nenulových**
koeficientov (mimo intercept).

Konkrétne hodnoty čítame priamo z tabuľky vygenerovanej notebookom
(neopisujeme ich tu, aby próza neklamala pri zmene cache). Kvalitatívne:
- **Ridge** retains 13/13 na Lexical a 34/34 na FullLite — by L2
  construction.
- **Lasso** retains podstatne menej (typicky polovica až dve tretiny
  z dostupných príznakov).

### 3.4 Coefficient table (§3.4)

Reportujeme koeficienty **pri rovnakom λ-výbere (`lambda.1se`)** pre
Ridge aj Lasso. Toto je miesto, kde je vidieť **tvarový rozdiel** na
Lexical URL-length klastri (URLLength, NoOfLettersInURL,
NoOfDegitsInURL).

**Čítanie tabuľky (konkrétne čísla v notebooku):**
- **Ridge** distribúje váhu pomerne rovnomerne, koeficienty sú malé
  a rovnakého znamienka. Stabilné, ale ťažko interpretovať
  individuálny príznak.
- **Lasso** vyrobí **opačne-znamienkové** koeficienty výrazne väčšej
  magnitúdy. Veľké opačné znamienka v korelovanom blok znamenajú
  *"jeden príznak ide v jednu stranu, druhý/-í v opačnú a navzájom
  sa dovažujú"*. Toto je **kanonická lasso patológia** v korelovanom
  prostredí — koeficienty sa nedajú interpretovať jednotlivo, len
  ich lineárna kombinácia má zmysel.

Lasso zahodí príznaky **mimo** URL-length klastra (lower-signal
features). Klaster sám si lasso ponechá ako celok, lebo zahodenie
ktoréhokoľvek člena by zničilo to opačno-znamienkové dovaženie,
pomocou ktorého fituje.

Tento rozdiel je deskriptívny obsah, **nie gating kritérium** — len
ilustruje *prečo* lasso pri redundantných príznakoch produkuje
nestabilné výbery.

### 3.5 Stability under resampling (§3.5) — descriptive

Z 10 CV foldov sme vyfittli **lasso a ridge zvlášť na každom folde**
a počítame **retention rate** každého príznaku — v koľkých z 10
foldov tam zostal nenulový.

**Čítanie tabuľky (konkrétne hodnoty v notebooku):**

- **Ridge** sedí na 1.0 všade — by L2 construction nikdy nezahodí
  feature. To je **baseline**, oproti ktorému je lasso variabilita
  čítateľná ako patológia, nie ako náhodný šum.
- **Lasso na Lexical** sedí prevažne na 1.0 alebo 0.0 — features sú
  buď konzistentne pickované cez všetky foldy alebo konzistentne
  zahadzované. Maximálne jeden-dva borderline prípady. Signál je
  dostatočne koncentrovaný, aby sa "coin-flip" mechanizmus
  nespustil.
- **Lasso na FullLite** ukáže **band intermediate retentions**
  (features pickované na niektorých foldoch a nie na iných). To je
  ten "coin-flip" — pri inom random sub-sample by sa retained set
  zmenil. Plus dlhý zoznam features s rate 0.0 (tie čo Ridge drží na
  1.0) — iný prejav tej istej picking instability, kde sa lasso
  rozhodne pre jedného člena redundantnej dvojice a nikdy ho
  neprehodnotí.

Sekcia **nie je gating** pre H2 — gating C1 stojí na *cross-method*
porovnaní (Lasso × Forward Jaccard), nie na *within-method*
stability. Sekcia je deskriptívna, lebo:
1. zadanie explicitne pýta správanie *"across folds"*,
2. ilustruje, **prečo** redundancia spôsobuje retained-set divergenciu.

---

## 4. Algorithmic — Forward (AIC)

### 4.1 `stats::step` setup

```r
null_mod <- glm(label ~ 1, data = dtr, family = binomial)
full_mod <- glm(label ~ ., data = dtr, family = binomial)
forward  <- step(null_mod,
                 scope = list(lower = null_mod, upper = full_mod),
                 direction = "forward", trace = FALSE, k = 2)
```

#### Prečo `k = 2`?
`k` je penalizácia v $\text{AIC} = -2\log\hat{L} + k \cdot p$. Default
$k = 2$ je **klasický Akaike**. Iné voľby (`k = log(n)`) by dali BIC,
čo penalizuje silnejšie a vyber by skončil pri menšom modeli.

#### Prečo na **štandardizovaných** dátach?
Forward AIC nepotrebuje štandardizáciu pre validitu (AIC je
škála-invariantný), ale my chceme, aby koeficienty z `summary(forward)`
boli priamo porovnateľné s lasso/ridge koeficientmi (ktoré sú v
z-score škále).

### 4.2 Entry order + per-step Wald p-values (§4.1)

Pre každý krok forward selection uložíme p-hodnotu **každého**
predtým-vstúpeného príznaku. Výsledná tabuľka má v notebooku tvar
"Tier × Feature × step_k". `NA` = ešte neentered. Pri vstupe sa
p-hodnota objaví. Sledujeme, **ako sa p-hodnota toho istého príznaku
mení s tým, ako prichádzajú ďalší**.

### 4.2.1 Wald p-flip extrakcia (descriptive support)

Z trajektórie spočítame pre každý príznak:
- `p_at_entry` = p-hodnota v kroku, kde príznak vstúpil
- `p_in_final` = p-hodnota vo finálnom modeli
- `flipped = (p_at_entry < 0.05) ≠ (p_in_final < 0.05)`

Agregovane reportujeme `n_flipped` per tier (konkrétne čísla
v notebooku).

**Pozícia v H2 dizajne (Level 2):** flipy sú **descriptive support**,
nie gating kritérium. Gating C1 je smerový kontrast Jaccardu
(§6.2). Flipy len overujú, či sa redundancia premietne aj do
forward-path Wald nestability — *concordance check* s C1.

**Predikcia:** ak H2 platí end-to-end, počet flipov by mal byť aspoň
rovnako vysoký na FullLite ako na Lexical, a Lexical flipy (ak
sú) by mali padnúť na URL-length klaster (jediný redundantný
blok), nie na izolované príznaky.

#### Prečo to funguje (mechanizmus)
Na **Lexical** je signál koncentrovaný — väčšina príznakov nesie
unikátnu informáciu, len URL-length trio je v korelovanom bloku.
Pridanie nového príznaku zriedka rozpustí SE existujúceho, takže
flipy sú zriedkavé.

Na **FullLite** je signál distribuovaný cez viacero korelovaných
blokov (URL-length + page-count + binárne near-duplicates). Pri
vstupe každého ďalšieho člena bloku sa SE jeho už-vstúpených
partnerov rozpustí ⇒ Wald štatistika klesne ⇒ p vyskočí. **Flip**.

### 4.3 Final model coefficients (§4.2)

Posledný stĺpec §4.1 je p-hodnota vo finálnom modeli. Reportujeme
osobitne pre čitateľnosť.

**Anomálie na oboch tieroch:** Forward AIC drží features, ktorých
Wald p-hodnota sedí výrazne nad 0.05 — typicky **kvázi-separácia**
(IsDomainIP na Lexical, IsHTTPS na FullLite — málo pozitívnych
bodov, GLM nekonverguje jasne, SE blow-up rádovo, Wald p ≈ 1).
AIC ich drží lebo log-likelihood sa nepatrne zlepšil — *"AIC kept
what Wald wouldn't"*. Toto **nie sú p-flipy** v C3 zmysle (flip
vyžaduje zmenu signifikancie *medzi step-N a final*, nie *medzi
zadaním a final*).

Konkrétny zoznam non-significant retained features per tier čítame
priamo z tabuľky v notebooku.

---

## 5. Post-Selection Inference — research piece

### 5.1 Prečo Wald p-hodnoty po selekcii **nie sú validné** (§5.1)

Klasický test predpokladá, že:
1. Vyberieme príznaky **pred** pohľadom na dáta.
2. Wald štatistika $z = \hat{\beta}/\text{SE}$ má pod $H_0$ štandardnú
   normálnu distribúciu.

Pri stepwise selection to porušujeme **kvôli dvom mechanizmom**:
- **Selection bias:** AIC výber z 13 (alebo 34) kandidátov pričom
  necháme len tie najsľubnejšie ⇒ vybrané príznaky sú **výberovo
  zaujaté smerom k zdaniu signifikancie**. P-hodnoty sú **prílišne
  malé**.
- **Distribučná zmena:** zlatý štandard z odvodzuje od fixnej
  multivariate-normal Hessián matice; po selekcii Hessián odráža iba
  **vybrané** stĺpce, nie celý priestor ⇒ NULL distribúcia z je už
  iná než $\mathcal{N}(0,1)$, je **truncated Gaussian** alebo polynomial
  (Lee–Tibshirani 2014).

**Štandardný odhad:** Wald p ≈ 0.001 z post-selection modelu môže v
realite zodpovedať skutočnej p ≈ 0.05–0.20. Smiešne nadhodnotené.

### 5.2 Prečo p-trajectory **JE užitočná** ako descriptive observation (§5.2)

Tu nie je "test of significance" v klasickom zmysle. Používame
**zmenu p-hodnoty toho istého príznaku, ako sa pridávajú ďalšie**, ako
**popisný indikátor multikolinearity**.

Konkrétne: ak feature má p ≈ $10^{-200}$ pri vstupe a niekoľko
krokov neskôr p ≈ 0.5 (po vstupe korelovaného partnera), **SE
narástla rádovo**, čo nie je inferenčná otázka — je to deskriptívna
otázka: *"how much does this feature's evidence depend on which
other features are around?"*. Odpoveď v rádovom skoku = veľmi.

Toto deskriptívne čítanie p-flipov je validné aj keď konkrétne
číselné p-hodnoty samy osebe neoznačujú signifikanciu. Konkrétne
flipnuté features per tier čítame priamo z `flip_counts` tabuľky
v notebooku.

### 5.3 Prečo **lasso fold-stability** je embedded analóg (§5.3)

Lasso nedáva p-hodnoty (ani biased ani unbiased — nedáva ich vôbec),
takže "is this feature significant" sa formálne testovať nedá.
**Ale** retention-rate (§3.5) je analóg: feature s rate ∈ (0, 1) je
empiricky to, čo by Wald nazval *"on the edge of significance"*. Bez
post-selection korekcie, ale s priamou observačnou interpretáciou.

Toto je sekcia, ktorá **odôvodňuje** stability table v §3.5 ako
embedded answer na zadanie *"which features lose significance"* —
nie cez p-hodnotu, ale cez **fold-frequency**.

---

## 6. Comparison — Retained Sets Side by Side

### 6.1 Deliverable table (§6.1)

Splnenie zadania *"how many features do you retain"*. Tabuľka v
notebooku (`retained_by_method`) reportuje retained / total pre
Ridge / Lasso / Forward na oboch tieroch.

**Kvalitatívne:**
- Ridge zachováva **všetky** príznaky tiera (13/13 na Lexical,
  34/34 na FullLite) — by L2 construction.
- Lasso a Forward sú podmnožiny rôznej veľkosti.
- Descriptive support pre H2: $\lvert k_\text{Lasso} - k_\text{Forward}\rvert$
  by mal rásť z Lexical na FullLite.

### 6.2 Feature-set overlap (§6.2) — H2 GATING

Notebook reportuje plnú 3×3 Jaccard maticu (Ridge × Lasso ×
Forward) pre každý tier, plus extrahovaný **Lasso × Forward**
Jaccard per tier (tabuľka `lasso_fwd_jac`).

**H2 gating C1:** $J_\text{FullLite}(\text{Lasso}, \text{Forward}) <
J_\text{Lexical}(\text{Lasso}, \text{Forward})$ — strict inequality.
Hodnoty čítame priamo z `lasso_fwd_jac` v notebooku.

#### Prečo Ridge × * Jaccard je nezaujímavý
Ridge zachováva **všetkých k** príznakov daného tiera (k=13 alebo 34).
Lasso a Forward sú podmnožiny. Takže Jaccard(Ridge, X) = |X| / |tier|
**nehovorí o disagreement medzi metódami**, len o tom, koľko z tiera
podmnožina pokrýva. Preto gating je explicitne **Lasso × Forward**.

### 6.3 AUC + Sens/Spec per metóda (§6.3)

Tabuľka `tier_compare` v notebooku reportuje test AUC + Sensitivity +
Specificity (pri thresholdu 0.5) pre Ridge / Lasso / Forward na oboch
tieroch. Pre Forward sa predikcie počítajú z plain GLM refitu na
retained sete.

**Pozorovanie (kvalitatívne):** všetky tri metódy dosahujú **prakticky
rovnakú AUC** na oboch tieroch napriek rôznym retained countom. To je
opäť prejav redundancie — viacero rovnako-dobrých riešení vyrobí
ekvivalentnú prediktívnu výkonnosť.

---

## 7. H2 Verdikt (§7)

### 7.1 Single-criterion gating

| # | Kritérium | Test | Drží? |
|---|-----------|------|-------|
| C1 | $J_\text{FullLite}(\text{Lasso}, \text{Forward}) < J_\text{Lexical}(\text{Lasso}, \text{Forward})$ | `lasso_fwd_jac` v notebooku | čítaj v `verdict` tabuľke |

**Verdikt:** H2 je **supported** ak `C1_jaccard_drops` v notebookovej
tabuľke `verdict` vychádza `TRUE` — Lasso a Forward sa zhodnú viac na
malo-klastrovom tieri (Lexical) než na multi-klastrovom (FullLite).

### 7.2 Descriptive support (concordance check)

Notebook navyše reportuje:
- **`k_diff_grows`**: rastie $\lvert k_\text{Lasso} - k_\text{Forward}\rvert$
  z Lexical na FullLite?
- **`flips_grow`**: je `n_flipped` na FullLite aspoň tak vysoký ako
  na Lexical?

Ak všetky tri vyjdú `TRUE`, redundancia sa premieta cez tri
nezávislé optiky (set overlap, retained-count gap, forward-path
significance) — **silná concordance**. Ak vyjde len gating C1,
H2 je stále supported, ale slabšie (descriptive prejavy
nesúhlasili).

### 7.3 Prečo to dáva zmysel (mechanizmus)

#### Lexical (small isolated cluster)
Hostí jeden 3-členný URL-length klaster; zvyšných 10 príznakov je
medzi sebou len mierne korelovaných. Lasso a Forward sa zhodnú **viac**
— jediný redundantný blok ponúka len málo alternatívnych blokových
reprezentantov, takže výber sa nelíši dramaticky.

#### FullLite (rich multi-cluster)
URL-length klaster + page-count klaster + niekoľko binárnych
near-duplicates (HasFavicon, HasDescription, ...) — vytvárajú **viaceré
equivalence classes** príznakov, kde vymeniť jedného člena za druhého
produkuje takmer-identický model. Lasso si vyberie blokového
reprezentanta **A**, Forward si vyberie **B**, retained counts sa
rozutekajú, Jaccard padne. **Presne to, čo C1 meria.**

### 7.4 Bridge na H1 — naratívne pozorovanie

S2 ukázala, že parametric–non-parametric AUC gap sa stiahne z
Lexical na FullLite. **Možné čítania:**

1. **"FullLite je easier"** — viac signálu, každý model tam dosiahne
   strop.
2. **"FullLite je redundancy-rich"** — regularizovaný parametrický
   model dokáže vyžmýkať korelované bloky do podobnej kapacity ako
   neparametrický. Nie je to *"easy"*, je to *"penalisation absorbs
   the redundancy"*.

H2 čítanie podporuje **(2)**. Konzistentne s tým: §6.3 ukazuje, že
penalised LR (Ridge alebo Lasso) na FullLite dosahuje AUC v
neighborhoode S2 non-parametric champions. To **nie je gating**
kritérium H2 — len observačná podpora narativu.

### 7.5 Čo H2 **netvrdí**

- **Netvrdí**, že redundancia je *"zlá"* — naopak, je dôvod, prečo
  modely na FullLite vystačia s menšou množinou príznakov bez straty
  predikcie.
- **Netvrdí**, že Forward je lepší / horší ako Lasso — sú to dva rôzne
  pohľady na ten istý problém s prakticky identickou test AUC.
- **Netvrdí**, že Lexical je *"bez redundancie"* — len **menej
  redundantný** ako FullLite. URL-length klaster s VIF > 1000 tam je
  a ovplyvňuje §3.4 koeficienty.
- **Netvrdí**, že p-flip = "zlý príznak". P-flip je **diagnostika
  multikolinearity**, nie diskvalifikácia featury z modelu. Featura,
  ktorá flipne, môže byť stále predikčne užitočná — len jej *unique
  credit* nie je stabilný.

---

## 8. Interpretácia výsledkov

### 8.1 Hlavné pozorovania

**1. Forward, Lasso a Ridge dávajú prakticky rovnakú AUC** — na oboch
tieroch v rámci 0.001. Voľba feature-selection metódy **nie je o
prediction performance**, je o **interpretability + parsimony**.

**2. Retained counts divergujú jedine na FullLite.** Na Lexical
všetky tri metódy zhodnocujú podobný "core signal". Na FullLite je
tento "core signal" spread cez korelované bloky a metódy si vyberajú
rôznych blokových reprezentantov.

**3. P-flipy sú empirický fingerprint multikolinearity.** Forward
trajectory dáva nielen *"keep / drop"* odpoveď, ale aj *"how much does
this feature's evidence depend on which other features are around?"*
— to je informácia, ktorú embedded metódy nedávajú.

**4. Lasso fold-stability vyplňuje to, čo p-trajectory chýba pre
embedded.** Lasso nemá Wald p, ale features s retention rate
v intervale (0, 1) sú empirický analóg "on the edge of significance"
— hovoria to isté čo Wald p-flip: *"túto feature drží tenké vlákno
empirických podmienok, ktoré sa lámu pri inom train splite"*.

### 8.2 Praktické dôsledky

#### Pre nasadenie modelu
1. **URL-only filter (Lexical):** stačí 9–10 príznakov. Nasadiť
   Lasso/Forward na produkčnú LR — ekvivalentné AUC, lepšia
   parsimonia ako Ridge.
2. **Page-level filter (FullLite):** existuje **veľa rovnocenných
   modelov**. Voľba podmnožiny by mala ísť podľa *cost of feature
   collection* — page-count features potrebujú DOM parsing, niektoré
   stoja viac CPU než iné.
3. **Audit / interpretovateľnosť:** Forward dáva *najúdernejšiu*
   interpretovateľnú odpoveď, lebo retained set je najmenší a má
   per-step trajectory. Pre regulačné rebriefingy preferovať Forward.

#### Pre dataset
Multikolinearita v PhiUSIIL je **reálna a kvantifikovateľná**. Akékoľvek
budúce model pridanie features do Behavior alebo do FullLite by malo
zvážiť, či feature **nepridáva variance**, ktorú už pokrýva existujúci
blok.

---

## 9. Čo by sa dalo robiť ďalej

### 9.1 Vylepšenia metodológie
1. **Selective inference (Lee & Tibshirani 2014, Berk et al. 2013).**
   Reportovali by sme **post-selection-corrected** p-hodnoty, ktoré sú
   skutočne validné po stepwise. Knižnica `selectiveInference` v R.
   Nie sme to spravili, lebo aktuálne ich používame **deskriptívne**
   (ako fingerprint multikolinearity), nie ako test.
2. **Stabilita Forward cez bootstrap.** Aktuálne ostať jeden Forward
   na celom train sete. Mohli by sme spraviť 100 bootstrap-Forward
   modelov a reportovať per-feature **inclusion frequency** (analogicky
   k §3.6 lasso).
3. **ElasticNet ako tretí embedded.** Pridať $\alpha = 0.5$ a sledovať,
   či sa retained set posunie smerom k Forward (predikujeme *áno* na
   FullLite — lasso je extrémne sparse).
4. **Group lasso / hierarchical selection.** Manuálne nadefinovať
   skupiny (URL-length cluster, page-count cluster) a fitnúť `gglasso`,
   ktoré buď zachová celú skupinu alebo žiadnu.

### 9.2 Vylepšenia experimentu
5. **Tier gradient.** Pridať Trust a Behavior do tabuliek, aby C1/C2/C3
   ukazovali plnú **monotónnu krivku** namiesto dvojice extrémov. To
   nemení H2 verdikt, len ho robí finer.
6. **Repeated CV pre retention rates.** Aktuálne 10 foldov. Repeated
   10×5 = 50 fold modelov by dalo **jemnejšie** retention rates (granularita
   1/50 namiesto 1/10).

### 9.3 Pre obhajobu — slabé miesta, ktoré sami priznáme
- **Wald p-hodnoty sú biased post-selection.** Čítame ich len
  deskriptívne, nie ako test. Komisia: *"prečo nemáte selectiveInference?"*
  → *"Pre flip-detekciu deskriptívne stačia; pre formálny test by sme
  ich nahradili. Plán je v §9.1."*
- **C1 ako single gating je striktný kontrast bez rezervy.** Komisia:
  *"čo ak Jaccard FullLite > Lexical len o pár tisícin?"* → *"Vtedy
  H2 padá. To je vlastnosť dizajnu, nie chyba — chceli sme
  falsifikovateľné kritérium. Descriptive support (k_diff, flips) v
  notebookovej `verdict` tabuľke ukáže, či je drop monotónny aj cez
  ďalšie optiky."*
- **Lexical nie je čistý 'no-redundancy' tier.** URL-length klaster
  s VIF > 1000 tam je. H2 to **explicitne berie do úvahy** —
  predikujeme len že FullLite je *redundantnejší* než Lexical, nie že
  Lexical je *bez redundancie*. Komisia: *"prečo to potom nazývate
  small-cluster tier?"* → *"Lebo má len jeden klaster a 10 príznakov
  bez bloc redundance; FullLite má tri až štyri prekrývajúce sa
  klastre."*
- **Ridge nie je gating participant.** Z definície L2 nezahadzuje, takže
  retained-count a Jaccard kritérium na ňu neaplikujeme. Ridge má v S3
  rolu **kontrastového referenčného bodu** v §3.4 (coefficient bloc
  shape) a §3.5 (stability baseline = 1.00 všade).

---

## 10. Cheatsheet — otázky a odpovede pre obhajobu

**Q: Prečo ste nedrnúli ElasticNet, keď je v zadaní povolený?**
A: Empiricky overené: pri α = 0.5 je retained set vzdialený od Lasso
o 1 príznak, koeficienty v rámci 15 %, AUC zhodné na 3 desatiny.
Pridáva tretí riadok do každej tabuľky, ktorý hovorí *"medzi Ridge
a Lasso"*. Lasso a Ridge ako extrémy α-osi sú **najostrejší kontrast**
— ElasticNet ich len interpoluje.

**Q: Prečo je v scenário 2 aj Ridge — neopakujeme prácu?**
A: V S2 je Ridge použitá ako **fixed-λ baseline pre LR** (klasifikátor-
family benchmark, nie feature-selection lens). V S3 je tá istá
glmnet-Ridge pýtaná **inú otázku**: *"ako rozdistribuuje váhu cez
korelovaný blok"*. Tá istá rovnica, dva rôzne deliverable.

**Q: Prečo Forward namiesto Backward / Stepwise?**
A: Empiricky všetky tri AIC procedúry konvergujú na **identický
retained set** na Lexical (k = 9, Jaccard = 1.00) a na **takmer
identický** (within 2 features) na FullLite. Reportovať tri sa stáva
plnením miesta. Forward je natural fit pre zadanie *"ako predictors
**add**"*; backward by reportoval to isté zo symetrickej strany.

**Q: Prečo `lambda.1se` a nie `lambda.min`?**
A: `lambda.min` dá najlepšiu prediction, ale typicky najmenej parsimonious
model. `lambda.1se` je sparsejší (najväčšia λ s CV AUC v rámci 1·SE
od optima). Pre H2, ktorá meria **redundancy**, chceme model, kde
Lasso najviac drví príznaky — `lambda.1se` to dáva.

**Q: AIC nie je test signifikancie. Prečo komentujete Wald p-hodnoty
v AIC-vybranom modeli?**
A: AIC vyberá **podmnožinu** príznakov; Wald p-hodnoty sa potom dajú
**popisne** spočítať na vybranom modeli. Nepoužívame ich ako
*"signifikantný"* / *"nesignifikantný"* test (post-selection bias) —
používame ich ako **fingerprint multikolinearity**: zmena p-hodnoty
**toho istého** príznaku medzi step-N a final je deskriptívna otázka,
nie inferenčná. Plný argument v §5.2.

**Q: Aké je presné gating kritérium H2 a prečo len jedno?**
A: $J_\text{FullLite}(\text{Lasso}, \text{Forward}) <
J_\text{Lexical}(\text{Lasso}, \text{Forward})$ — strict inequality.
Single-criterion design je robustnejší voči parametrom (lambda
choice, AIC penalty) než tri kritériá s absolútnymi prahmi. Tie sa
môžu rozsynchronizovať s cache pri zmene konfigu, smerový kontrast
nie. Descriptive support (k_diff, flips) v notebookovej `verdict`
tabuľke ukazuje, či redundancia bije aj cez ďalšie dve optiky.

**Q: Ako čítate konkrétne hodnoty Jaccardu / k_diff / flipov?**
A: Z notebookovej tabuľky `verdict` (alebo `lasso_fwd_jac` +
`flip_counts`). Próza ich úmyselne nereportuje konkrétnym číslom,
aby pri prípadnom refite neostala out-of-sync s cache. Komisia ich
vidí priamo v rendrovanom HTML.

**Q: Prečo nepoužívate `selectiveInference` knižnicu?**
A: Lebo aktuálne čítame Wald p-hodnoty čisto deskriptívne — nie ako
test. `selectiveInference` by sme potrebovali, ak by sme chceli tvrdiť
*"feature X je signifikantná aj po stepwise korekcii"*. To H2
netvrdí. Plán: §9.1, ako budúce rozšírenie.

**Q: Čo ak `C1_jaccard_drops` v notebooku vyjde TRUE, ale `k_diff_grows`
alebo `flips_grow` vyjde FALSE?**
A: H2 zostáva supported (gating je len C1), ale slabšie. Komisia:
*"čo to znamená?"* → *"Redundancia sa premieta do set overlapu, ale
nie do retained-count gapu alebo Wald nestability. To môže byť
artefakt voľby `lambda.1se` (sparsifikuje agresívne na oboch tieroch
podobne) alebo Forward AIC stoppingu (zastaví na podobnom relatívnom
mieste). H2 nie je vyvrátená, ale concordance je len 1/3."*

**Q: Bridge na H1 v §7.4 je naratívne pozorovanie. Prečo to nie je
formálne kritérium?**
A: Dva dôvody. (1) S3 zadanie je o feature-selection, nie o porovnaní
s neparametrickými modelmi. (2) Viazať H2 verdikt na konkrétne číslo
(Δ AUC vs S2 SVM) by bolo krehké voči refitu S2. H1 bola uzavretá
v S2 — revisitovať ju cez S3 kritérium by bolo dramaturgicky zvláštne.

**Q: Lasso na FullLite zahodí veľkú časť príznakov. Sú to "zbytočné"?**
A: Nie nutne. Sú to *blokoví zástupcovia*, ktorých informáciu už
zachytili iné členy ich klastra. V inom train splite by Lasso možno
vybralo iný retained set. Toto presne ukazuje stability table §3.5
(retention rate medzi 0 a 1 = blokový "coin-flip" feature).

**Q: Ktorá metóda by sa mala nasadiť do produkcie?**
A: **Forward** pre interpretovateľnosť (najmenší retained set + per-step
trajectory pre audit), **Lasso** pre rýchlu rebudovu (nemusí robiť
full step search). Ridge nie pre produkčný feature-selection, lebo
nezahadzuje; Ridge má iné využitie ako stabilizovaná regresia (S2 LR
baseline). Predikčne sa **rovnajú v rámci sub-percenta AUC**, takže
voľba je business-side, nie statistical.

**Q: Prečo nie Trust a Behavior?**
A: Trust má 7 príznakov (málo na blokovú redundanciu). Behavior po
odstránení 6 leakerov (14 príznakov) je dimenzionálne medzi Lexical
a FullLite. H2 testuje **dva režimy redundancie** (small isolated vs.
rich multi-cluster) — Trust by ten kontrast len rozriedil. Plán:
§9.2, plný gradient ako budúce rozšírenie.

**Q: H2 by sa zamietla ak…?**
A: Ak by $J_\text{FullLite} \ge J_\text{Lexical}$ — Lasso a Forward
by sa zhodli rovnako alebo viac na multi-klastrovom tieri než na
single-klastrovom. To by znamenalo, že redundancia sa nepremieta do
divergencie metód, alebo že Lexical je rovnako alebo viac
redundantný. *"Redundancy increases with tier richness"* by nedržalo.

**Q: Coefficient bloc shape v §3.4 (Ridge spreads, Lasso opposes).
Prečo to nie je gating kritérium?**
A: Lebo bloc-shape je **within-method** popis (ako jednotlivá metóda
rieši multikolinearitu), nie **between-method** disagreement (čo H2
testuje). Je to správna deskriptívna informácia o *prečo* sa
metódy správajú odlišne, ale nie test toho *či* sa správajú odlišne.
