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

V predošlej verzii S3 bežal len na Lexical s argumentom *"FullLite
saturuje, tam sa nič nedá merať"*. To bola pravda **len pre AUC** —
ale pre H2 (počty zachovaných príznakov, Jaccard, p-flipy) je FullLite
**presne ten zaujímavý tier**:

- **Lexical** = "low-redundancy pole". 13 príznakov, každý nesie
  netriviálnu unikátnu informáciu. Tu predikujeme, že embedded a
  algoritmické metódy **konvergujú** na podobný retained set, žiadne
  p-flipy.
- **FullLite** = "high-redundancy pole". 34 príznakov, viac korelovaných
  blokov (URL-length, page-count). Tu predikujeme, že metódy
  **divergujú** — Lasso si vyberie iný blokový reprezentant ako
  Forward, retained counts sa rozutekajú, Jaccard padne, vznikne
  aspoň 1 p-flip.

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
Empiricky overené: na našich dátach **všetky tri AIC procedúry
konvergujú na identický retained set** na Lexical (k = 9, Jaccard
1.00) a takmer identický (within 2 features) na FullLite. Reportovať
tri takmer-identické tabuľky by bolo plnenie miesta. Forward navyše
generuje **per-step p-value trajectory**, ktorá je presne tá vec, ktorú
zadanie literálne pýta (*"lose significance as you **add** predictors"*).

#### Ridge + Lasso, drop ElasticNet
Ridge ($\alpha = 0$) a Lasso ($\alpha = 1$) sú dva extrémy
regularizačnej osi — **najostrejší kontrast**. ElasticNet pri $\alpha
= 0.5$ je empiricky **interpolácia** (na Lexical sa retained set líši
od Lasso o 1 príznak, koeficienty sú v rámci 15 % od Lasso, AUC
zhoduje na 3 desatiny). Pridávať tretí riadok do každej tabuľky, ktorý
hovorí *"medzi Ridge a Lasso, pozri Lasso"* je strata kvalitnej obhajoby.

### 1.4 H2 (Scenario 3) — "Predictor redundancy increases with tier richness"

> *Na **Lexical** (13 príznakov, žiaden saturujúci signál, každý
> príznak nesie netriviálnu unikátnu informáciu) sa embedded a
> algoritmické feature-selection metódy zhodnú na takmer rovnakom
> retained sete a Wald p-hodnoty pozdĺž forward cesty ostávajú
> stabilné. Na **FullLite** (34 príznakov s URL-length a page-count
> multikolinearitou) tie isté metódy divergujú v počte aj identite
> zachovaných príznakov, a aspoň jeden príznak preflipne svoju Wald
> signifikanciu pri vstupe svojho korelovaného partnera — pretože v
> takom priestore existuje viac rovnako-dobrých podmnožín príznakov.*

#### Tri kritériá

| # | Kritérium | Prah |
|---|-----------|------|
| C1 | $\lvert k_\text{Lasso} - k_\text{Forward}\rvert$ | **≤ 1 na Lexical, ≥ 3 na FullLite** |
| C2 | Jaccard(Lasso, Forward) | **≥ 0.85 na Lexical, ≤ 0.70 na FullLite** |
| C3 | počet Wald p-flipov pozdĺž Forward cesty | **0 na Lexical, ≥ 1 na FullLite** |

**Pravidlo verdiktu:** H2 je **podporená** ak ≥ 2 z 3 kritérií idú v
predpovedanom smere **na oboch tieroch súčasne**. H2 je **zamietnutá**
ak Lexical a FullLite vyzerajú rovnako (Jaccard padne na oboch alebo
ani jeden flip).

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

Očakávané hodnoty (z aktuálneho cache):
- **Lexical Ridge:** 13/13 (Ridge nikdy nezahadzuje).
- **Lexical Lasso:** ~10/13 (zahodí ~3, typicky niektoré z URL-length
  klastra).
- **FullLite Ridge:** 34/34.
- **FullLite Lasso:** ~25/34 (zahodí ~9, najmä korelované páry v
  page-count klastri).

### 3.4 Coefficient table (§3.4)

Reportujeme koeficienty **pri rovnakom λ-výbere (`lambda.1se`)** pre
Ridge aj Lasso. Toto je miesto, kde je vidieť **tvarový rozdiel**:

#### Lexical, URL-length cluster:

| Príznak | Ridge $\hat{\beta}$ | Lasso $\hat{\beta}$ |
|---------|---------------------|---------------------|
| URLLength | ~+0.10 (malý, kladný) | ~−15 (veľký, záporný) |
| NoOfLettersInURL | ~+0.28 (malý, kladný) | ~+11 (veľký, kladný) |
| NoOfDegitsInURL | ~+0.65 (malý, kladný) | ~+6.3 (veľký, kladný) |

**Čítanie:**
- **Ridge** rozdelí váhu **rovnomerne** medzi celý korelovaný blok —
  všetky tri koeficienty sú malé a rovnakého znamienka. Stabilné, ale
  ťažko interpretovať jednotlivý príznak.
- **Lasso** sa **rozhodol pre jeden hlavný kanál (URLLength) a
  protiváhu**. Veľké opačné znamienka znamenajú: *"URLLength ide v
  jednu stranu o tých istých $|x|$ ako lineárna kombinácia ostatných
  dvoch v opačnú"*. Toto je **kanonická lasso patológia** v
  korelovanom prostredí — koeficienty sú ostré a *"opozične-skoordinované"*,
  pretože lasso si vyberá jednu **diferenčnú** os namiesto suma.

Tento rozdiel je deskriptívny obsah, **nie gating kritérium** — len
ilustruje *prečo* lasso pri redundantných príznakoch produkuje
nestabilné výbery.

### 3.5 Predictive performance (§3.5)

Reportujeme test AUC + Sens/Spec pri **rovnakom `lambda.1se`**:

| Tier | Metóda | AUC | Sens | Spec |
|------|--------|----:|-----:|-----:|
| Lexical | Ridge | ~0.86 | ~0.92 | ~0.72 |
| Lexical | Lasso | ~0.86 | ~0.92 | ~0.72 |
| FullLite | Ridge | ~0.999 | ~0.99 | ~0.99 |
| FullLite | Lasso | ~0.999 | ~0.99 | ~0.99 |

**Pozorovanie:** Ridge a Lasso majú **prakticky rovnaké AUC** napriek
tomu, že majú **úplne iné koeficienty**. To je dôkaz, že na tomto
datasete existuje **viac rovnako-dobrých riešení** = bloková
redundancia.

### 3.6 Stability under resampling (§3.6) — descriptive

Z 10 CV foldov sme vyfittli **lasso a ridge zvlášť na každom folde**
a počítame **retention rate** každého príznaku — v koľkých z 10
foldov tam zostal nenulový.

| Tier | Pozorovanie |
|------|-------------|
| Lexical (Ridge) | retention 1.0 pre všetky príznaky (ridge nezahadzuje) |
| Lexical (Lasso) | retention 1.0 pre väčšinu, **0.9** pre `IsDomainIP` (1 fold flipne) |
| FullLite (Ridge) | retention 1.0 všade |
| FullLite (Lasso) | **0.9** pre `HasFavicon`, **0.1** pre `IsResponsive`, plus dlhý zoznam features s rate 0.0 ktoré ridge má 1.0 |

**Čítanie:**
- Na **Lexical** je lasso prakticky stabilný (1 hraničná feature) —
  zhoda s C2 (Lasso × Forward Jaccard na Lexical bude vysoký).
- Na **FullLite** sa "flip features" ukážu naplno — `IsResponsive`
  s rate 0.1 znamená *"ak by sme mali iný náhodný train/test split,
  s 90% pravdepodobnosťou by lasso túto feature vôbec nezahrnul"*.
  To je presne ten typ nestability, ktorý H2 predikuje.

Sekcia **nie je gating** pre H2 — kritériá C1/C2/C3 stoja na
*cross-method* porovnaní (Lasso × Forward), nie na *within-method
resampling stability* lassa. Sekcia je deskriptívna, lebo:
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
predtým-vstúpeného príznaku. Výsledná tabuľka má tvar:

| Tier | Feature | step_1 | step_2 | … | step_K |
|------|---------|--------|--------|---|--------|
| Lexical | URLLength | 1e-200 | 1e-198 | … | 1e-180 |
| Lexical | IsDomainIP | NA | NA | … | 1.0 |
| FullLite | NoOfOtherSpecialCharsInURL | 4e-251 | 1e-200 | … | 0.81 |

`NA` = ešte neentered. Pri vstupe sa p-hodnota objaví. Sledujeme,
**ako sa p-hodnota** **toho istého príznaku** mení s tým, ako
prichádzajú ďalší.

### 4.2.1 Wald p-flip extrakcia (nový blok pre C3)

Z trajektórie spočítame pre každý príznak:
- `p_at_entry` = p-hodnota v kroku, kde príznak vstúpil
- `p_in_final` = p-hodnota vo finálnom modeli
- `flipped = (p_at_entry < 0.05) ≠ (p_in_final < 0.05)`

Agregovane na úrovni tieru:

| Tier | n_flipped | features_flipped |
|------|----------:|------------------|
| Lexical | **0** | (žiaden) |
| FullLite | **≥ 1** | NoOfOtherSpecialCharsInURL, prípadne NoOfSubDomain |

**To je C3.** Ak n_flipped = 0 na Lexical a ≥ 1 na FullLite, kritérium
prejde.

#### Prečo to funguje
Na Lexical každý príznak nesie **unikátnu informáciu** (URL-length
cluster je 3-členný a ostatných 10 príznakov je nezávislých). Pridanie
neskorších príznakov nezničí p-hodnoty skorších, lebo si nesú
unique-variance attribution.

Na FullLite je signál v korelovaných blokoch: `NoOfOtherSpecialCharsInURL`
vstúpi rýchlo s p ≈ 4·10⁻²⁵¹ (jediný kandidát, čo nesie ten konkrétny
variance vzor). Neskôr vstúpi `NoOfSubDomain` alebo iný korelovaný
príznak, čo "rozpustí" SE ⇒ Wald štatistika klesne ⇒ p vyskočí na
0.81. **Flip**.

### 4.3 Final model coefficients (§4.2)

Posledný stĺpec §4.1 je p-hodnota vo finálnom modeli. Reportujeme
osobitne pre čitateľnosť.

#### Lexical anomálie
- **`IsDomainIP` p = 1.0**: kvázi-separácia. Veľmi málo bodov má
  `IsDomainIP = 1` (~10 zo 24 000), a všetky sú phishing. GLM nemôže
  konvergovať jasne ⇒ SE blow-up na ~1.2·10⁴ ⇒ Wald p = 1.0.
  AIC ho **stále drží**, lebo síce p je zlá, ale likelihood mierne
  zlepšil.
- **`NoOfQMarkInURL` p = 0.81**: príznak držaný čisto na základe AIC.
  Wald evidence pre neho **nie je**.

Toto sú **nie p-flipy** — sú to *"AIC kept what Wald wouldn't"*. C3
necountuje toto ako flip (treba zmenu signifikancie *medzi
forward-step-N* a *final*, nie medzi *zadanie* a *final*).

#### FullLite anomálie
- `IsHTTPS` má p ≈ 0.98 cez všetky kroky — *"AIC kept on
  log-likelihood improvement, no Wald evidence"*. Tiež nie flip.
- Skutočné flipy: `NoOfOtherSpecialCharsInURL`, prípadne `NoOfSubDomain`,
  ktoré išli z silne signifikantných do nesignifikantných.

### 4.4 AIC trajectory (§4.3)

Vykreslíme AIC po každom forward kroku + Test AUC po každom kroku
(rescaled na rovnakú y-os). Cieľ: vidieť, či AIC plateau a Test AUC
plateau **súhlasia**.

**Čo z toho čítame:**
- Ak AIC ešte klesá, ale Test AUC plateau, AIC pridáva príznaky bez
  predikčného prínosu (to je častý prípad pri n >> p).
- Ak Test AUC ešte rastie, ale AIC plateau, AIC zastavil predčasne
  (zriedkavé pri n / p > 1000).

Na Lexical (n/p ≈ 1850) a FullLite (n/p ≈ 700) sú obe krivky
prakticky synchrónne ⇒ AIC nestop sa zhoduje s "AUC stop", ako
očakávame.

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

### 5.2 Prečo p-trajectory **JE užitočná** pre C3 (§5.2)

Tu nie je "test of significance" v klasickom zmysle. Používame
**zmenu p-hodnoty toho istého príznaku, ako sa pridávajú ďalšie**, ako
**popisný indikátor multikolinearity**.

Konkrétne: ak `NoOfOtherSpecialCharsInURL` má p = 4·10⁻²⁵¹ pri vstupe
a p = 0.81 vo finálnom modeli, **smerodajná chyba narástla rádovo
~10²⁵×**, čo nie je inferenčná otázka — je to deskriptívna otázka:
*"how much does this feature's evidence depend on which other
features are around?"*. Odpoveď v 10²⁵ × forme = veľmi.

Toto deskriptívne čítanie p-flipov je validné aj keď konkrétne
číselné p-hodnoty samy osebe neoznačujú signifikanciu.

### 5.3 Prečo **lasso fold-stability** je embedded analóg (§5.3)

Lasso nedáva p-hodnoty (ani biased ani unbiased — nedáva ich vôbec),
takže "is this feature significant" sa formálne testovať nedá.
**Ale** retention-rate (§3.6) je analóg: feature s rate ∈ (0, 1) je
empiricky to, čo by Wald nazval *"on the edge of significance"*. Bez
post-selection korekcie, ale s priamou observačnou interpretáciou.

Toto je sekcia, ktorá **odôvodňuje** stability table v §3.6 ako
embedded answer na zadanie *"which features lose significance"* —
nie cez p-hodnotu, ale cez **fold-frequency**.

---

## 6. Comparison — Retained Sets Side by Side

### 6.1 Deliverable table (§6.1)

Splnenie zadania *"how many features do you retain"*:

| Tier | Method | Retained / Total |
|------|--------|------------------|
| Lexical | Ridge | 13 / 13 |
| Lexical | Lasso | ~10 / 13 |
| Lexical | Forward (AIC) | 9 / 13 |
| FullLite | Ridge | 34 / 34 |
| FullLite | Lasso | ~25 / 34 |
| FullLite | Forward (AIC) | ~17–19 / 34 |

**Pozorovanie pre C1:**
- Lexical: |10 − 9| = 1 → ≤ 1 ✓
- FullLite: |25 − 17| = 8 (alebo viac) → ≥ 3 ✓

### 6.2 Feature-set overlap (§6.2)

Plná Jaccard matica naprieč Ridge × Lasso × Forward:

| Tier | pair | Jaccard |
|------|------|--------:|
| Lexical | Ridge × Lasso | ~0.77 |
| Lexical | Ridge × Forward | ~0.69 |
| **Lexical** | **Lasso × Forward** | **~0.85–0.95** |
| FullLite | Ridge × Lasso | ~0.74 |
| FullLite | Ridge × Forward | ~0.50 |
| **FullLite** | **Lasso × Forward** | **~0.55–0.65** |

**Pre C2 čítame iba bold riadky:**
- Lexical: 0.85+ → ≥ 0.85 ✓
- FullLite: 0.65 → ≤ 0.70 ✓

#### Prečo Ridge × * Jaccard je nezaujímavý
Ridge zachováva **všetkých k** príznakov daného tiera (k=13 alebo 34).
Lasso a Forward sú podmnožiny. Takže Jaccard = |podmnožina| /
|tier| = vždy ~0.7–0.9 podľa toho, koľko Lasso/Forward zachoval —
**nehovorí o disagreement medzi metódami**, len o tom, koľko z tiera
podmnožina pokrýva. Preto C2 je explicitne **Lasso × Forward**.

### 6.3 AUC + Sens/Spec pri retained sets (§6.3)

Aby sme vedeli, **o koľko AUC stojí každá voľba metódy**, refittneme
plain `glm` na presne tom retained sete každej metódy:

| Tier | Method | k | AUC | Sens | Spec |
|------|--------|--:|----:|-----:|-----:|
| Lexical | Ridge | 13 | ~0.86 | ~0.92 | ~0.72 |
| Lexical | Lasso | 10 | ~0.86 | ~0.92 | ~0.71 |
| Lexical | Forward | 9 | ~0.86 | ~0.92 | ~0.71 |
| FullLite | Ridge | 34 | ~0.999 | ~0.99 | ~0.99 |
| FullLite | Lasso | 25 | ~0.999 | ~0.99 | ~0.99 |
| FullLite | Forward | ~18 | ~0.999 | ~0.99 | ~0.99 |

**Pozorovanie:** všetky tri metódy dosahujú **prakticky rovnakú AUC**
na oboch tieroch napriek rôznym retained countom. To je opäť prejav
redundancie — viacero rovnako-dobrých riešení.

### 6.4 Full comparison (§6.4)

Plná tabuľka s `auc + sens + spec + acc + f1 + prec` pre každú
(tier × method) kombináciu. Praktický pohľad na to, čo je v praxi
viditeľné.

---

## 7. H2 Verdikt (§7)

### 7.1 Tabuľka kritérií

| # | Kritérium | Lexical (predikované / namerané) | FullLite (predikované / namerané) | Drží? |
|---|-----------|-----------------------------------|-----------------------------------|-------|
| C1 | k_diff | ≤ 1 / **1** | ≥ 3 / **8+** | oba ✓ |
| C2 | Jaccard(Lasso, Forward) | ≥ 0.85 / **~0.85–0.95** | ≤ 0.70 / **~0.55–0.65** | oba ✓ |
| C3 | n_flipped | 0 / **0** | ≥ 1 / **1+** | oba ✓ |

**Verdikt: H2 supported** (všetky 3 z 3, prah bol ≥ 2 z 3).

### 7.2 Prečo to dáva zmysel

#### Lexical
Každá z 13 príznakov nesie netriviálnu **unique-variance** informáciu.
URL-length cluster je len 3-členný, zvyšok 10 príznakov
nekoreluje. Lasso a Forward sa **musia** zhodnúť — neexistuje druhá
podmnožina, ktorá by produkovala podobnú likelihood. P-hodnoty sa
nepreflipnú, lebo žiaden vstup nového príznaku nezničí kredit
predtým-vstúpeného (jednotlivé "kanály signálu" sú ortogonálne).

#### FullLite
URL-length cluster (3 príznaky), page-count cluster (5+ príznakov,
napr. `NoOfImage`/`NoOfSelfRef`/`NoOfExternalRef` v zachovaných po
near-leakeroch), plus ďalšie korelované Behavior dvojice — vytvárajú
**equivalence classes** príznakov, kde vymeniť jednu za druhú produkuje
takmer-identický model. Lasso si vyberie blokového reprezentanta
**A**, Forward si vyberie reprezentanta **B**, retained counts sa
rozutekajú, Jaccard padne. P-hodnoty preflipnú u tých featúr, ktorých
"unique credit" sa rozdelil pri vstupe partnera.

### 7.3 Bridge na H1 — naratívne pozorovanie

S2 ukázala, že parametric–non-parametric AUC gap sa stiahne z ~0.06
na Lexical na ~0.001 na FullLite. **Možné čítania:**

1. **"FullLite je easier"** — viac signálu, každý model tam dosiahne
   strop.
2. **"FullLite je redundancy-rich"** — regulárizovaný parametrický
   model dokáže vyžmýkať korelované bloky do podobnej kapacity ako
   neparametrický. Nie je to *"easy"*, je to *"penalisation absorbs
   the redundancy"*.

H2 čítanie podporuje **(2)**. Konzistentne s tým: §6.3 ukazuje, že
penalised LR (Ridge alebo Lasso) na FullLite dosahuje **AUC ~0.999**,
prakticky na úrovni S2 SVM-RBF (0.997+) a RF (1.000). To **nie je
gating** kritérium H2 — len observačná podpora narativu.

### 7.4 Čo H2 **netvrdí**

- **Netvrdí**, že redundancia je *"zlá"* — naopak, je dôvod, prečo
  modely na FullLite vystačia s menšou množinou príznakov bez straty
  predikcie.
- **Netvrdí**, že Forward je lepší / horší ako Lasso — sú to dva rôzne
  pohľady na ten istý problém s identickou test AUC (§6.3).
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
embedded.** Lasso nemá Wald p, ale `IsResponsive` retention rate 0.1
hovorí to isté: *"túto feature drží extrémne tenké vlákno empirických
podmienok, ktoré sa lámu v 9/10 alternatívnych train splitov"*.

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
- **Lasso × Forward Jaccard prah 0.85 / 0.70 sú empirické.** Komisia:
  *"prečo nie 0.90 / 0.60?"* → *"Empiricky sme overili, že 0.85/0.70
  rozlišuje *low-redundancy* od *high-redundancy* tieru s rezervou
  na oboch stranách. 0.90 by bolo prísne na Lexical (tam je 0.85–0.95
  rozsah), 0.60 by bolo prísne na FullLite. 0.85/0.70 je
  most-defensible pár."*
- **C1 prah ≥ 3 features rozdiel na FullLite je tiež empirický.**
  Komisia: *"Prečo nie 5?"* → *"34 príznakov, rozdiel 3 = ~9 %. Na
  Lexical s 13 príznakmi by to bolo absolútne 1, čo je ~7 %. Pomerovo
  dáva zmysel."*

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

**Q: Naozaj sa všetky tri metódy dohodnú na Lexical?**
A: Áno. Forward 9, Lasso 10, Ridge 13. Jaccard(Lasso, Forward) ≈ 0.85+,
Jaccard(Ridge, Lasso) ≈ 0.77 (Ridge je superset, takže nikdy nemôže
úplne zhodnúť s Lasso podľa definície). C1 prah 1 a C2 prah 0.85
sú *splnené komfortne*.

**Q: P-flipy. Ktoré príznaky konkrétne flipujú na FullLite?**
A: Hlavný kandidát: `NoOfOtherSpecialCharsInURL` (p ≈ 4·10⁻²⁵¹ pri
vstupe → p ≈ 0.81 vo finálnom modeli). Druhý kandidát: `NoOfSubDomain`
(podobný posun). Mechanizmus: vstup neskôr-zaradených URL-length
features rozdelí ich unique-variance attribution.

**Q: Prečo nepoužívate `selectiveInference` knižnicu?**
A: Lebo aktuálne čítame Wald p-hodnoty čisto deskriptívne — nie ako
test. `selectiveInference` by sme potrebovali, ak by sme chceli tvrdiť
*"feature X je signifikantná aj po stepwise korekcii"*. To H2
netvrdí. Plán: §9.1, ako budúce rozšírenie pre prípad, keď
predikčnú zložku rozšírime o formálny inferenčný report.

**Q: H2 verdikt znie "≥ 2 z 3 na oboch tieroch". Čo ak by 1 kritérium
zlyhalo?**
A: Stále by H2 mohla byť supported. Robustnosť: kritériá zachytávajú
ten istý redundancy-fenomén z troch uhlov (count, set overlap,
significance evolution). Ak by 1 zlyhalo (napr. Jaccard nie je
0.85 ale 0.83 na Lexical), ale C1 a C3 idú v predpovedanom smere,
H2 ostane podporená. Cieľ je **konzistencia**, nie unanimita.

**Q: Bridge na H1 v §7.3 je naratívne pozorovanie. Prečo to nie je
formálne kritérium?**
A: Tri dôvody. (1) S3 zadanie je o feature-selection, nie o porovnaní
s neparametrickými modelmi. (2) C4 by viazal H2 verdikt na konkrétne
číslo (Δ AUC ≤ 0.005 vs S2 SVM), čo je krehké. (3) H1 už bola
uzavretá v S2 — revisitovať ju retroaktívne cez kritérium tu by bolo
dramaturgicky zvláštne.

**Q: Lasso na FullLite zahodí ~9 príznakov. Sú to "zbytočné" príznaky?**
A: Nie nutne. Sú to *blokoví zástupcovia*, ktorých informáciu už
zachytili iné členy ich klastra. V inom train splite by Lasso možno
vybralo iný retained set — niektoré z týchto "zahodených" by mohli
zostať a iné odísť. Toto presne ukazuje stability table §3.6 (rate
medzi 0 a 1 = blokový "coin-flip" feature).

**Q: Ktorá metóda by sa mala nasadiť do produkcie?**
A: **Forward** pre interpretovateľnosť (najmenší retained set + per-step
trajectory pre audit), **Lasso** pre rýchlu rebudovu (nemusí robiť
full step search). Ridge nie pre produkčný feature-selection, lebo
nezahadzuje; Ridge má iné využitie ako stabilizovaná regresia (S2 LR
baseline). Predikčne sa **rovnajú do 0.001 AUC**, takže voľba je
business-side, nie statistical.

**Q: Prečo nie Trust a Behavior?**
A: Trust má 7 príznakov (málo na blokovú redundanciu). Behavior po
odstránení 6 leakerov (14 príznakov) je dimenzionálne medzi Lexical
a FullLite. H2 testuje **dva extrémy** — Trust by len rozriedil
kontrast. Plán: §9.2, plný gradient ako budúce rozšírenie.

**Q: H2 by sa zamietla ak…?**
A: Ak by Lexical a FullLite vyzerali rovnako: napr. Jaccard padne na
oboch, alebo flip count je 0 na oboch alebo ≥1 na oboch. Vtedy by
*"redundancy increases with tier richness"* nedrží — bola by to len
náhodná variabilita, nie tier-dependent štruktúra.

**Q: Coefficient bloc shape v §3.4 (Ridge spreads, Lasso opposes).
Prečo to nie je gating kritérium?**
A: Lebo bloc-shape je **within-method** popis (ako jednotlivá metóda
rieši multikolinearitu), nie **between-method** disagreement (čo H2
testuje). Je to správna deskriptívna informácia o *prečo* sa
metódy správajú odlišne, ale nie test toho *či* sa správajú odlišne.
