# Príprava na obhajobu — `scenario_2.rmd` (parametrické vs. neparametrické modely)

---

## 0.0 Pre úplných začiatočníkov — o čom to celé je

### Úloha
Chceme **automaticky rozhodnúť**, či je konkrétna URL adresa phishing alebo legitímna.


Na rozhodovanie máme **50 príznakov** (features) o každej URL —
napríklad: koľko má znakov, či obsahuje digity, koľko subdomén, či
odkazuje na banku, či obsahuje skryté formuláre atď. Cieľom je vyrobiť
**matematický model**, ktorý z týchto čísel odhadne
**pravdepodobnosť**, že daná URL je phishing.

### Čo sa môže pokaziť
- **Overfitting**: model sa naučí trénovacie dáta naspamäť, ale na
  nových URL zlyháva.
- **Underfitting**: model je príliš hlúpy na to, aby zachytil vzory.
  Ako keby sme rozhodovali podľa *"URL dlhšia ako 30 znakov = phishing"*
  — funguje, ale nie veľmi dobre.
- **Chybné rozhodnutie môže byť v dvoch smeroch:**
  - **False Negative (FN)** — prepustíme phishing.
  - **False Positive (FP)** — zablokujeme legitímnu URL.
  - V bankovom svete **FN stojí 10–100× viac než FP**, ale obidva typy
    sú pre nás podstatné.

### Prečo vôbec porovnávame "parametrické" vs "neparametrické" modely
**Parametrický model** má **pevný, vopred daný tvar** rozhodovania
(napr. lineárnu čiaru alebo Gaussovský zvon) — v dátach hľadá iba
niekoľko koeficientov, ktoré ten tvar upresnia. Keď sa dáta naozaj
takto správajú, je to efektívne a interpretovateľné; keď nie,
parametrický model narazí na strop.

**Neparametrický model** na rozdiel od toho **nedrží pevný tvar**. Čím
viac dát mu dáme, tým zložitejšie vzory dokáže zachytiť — pretože jeho
"zložitosť" rastie spolu s dátami. Má menej predpokladov o tom, ako
svet vyzerá, no za to platí výpočtovým časom a horšou
interpretovateľnosťou.

V našom projekte to chceme zmerať v praxi: **keď dáme modelu iba 13
URL príznakov (slabý signál), pomôže mu flexibilita neparametrického
prístupu?** To je jadro H1. A keď dáme modelu 34 silných príznakov
— spraví ten rozdiel ešte zmysel, alebo už všetko funguje rovnako?
To je motivácia pre "gradient" naprieč 4 tiermi.

---

## 0. Slovník pojmov — základné a modelové

### AUC (Area Under the ROC Curve)
**Najdôležitejšia metrika v tomto projekte.**

**Intuícia v ľudskej reči:** AUC meria, **ako dobre model rozlišuje
phishing od legitímnych URL na úrovni skórovania** — bez ohľadu na to,
kde presne nastavíme prah. Predstavte si, že model vypľuje skóre
P(phishing) pre každú URL: keby sme všetky URL zoradili podľa skóre od
najnižšieho po najvyššie, **AUC je pravdepodobnosť, že v náhodnej
dvojici (jeden phishing + jeden legit) dostane phishing vyššie skóre**.

Technické detaily:
- **Binárny klasifikátor** vracia pre každý príklad pravdepodobnosť
  P(phishing). Pre tvrdé rozhodnutie potrebujeme **prah**.
- **ROC krivka** vykresľuje pre všetky možné prahy:
  - **FPR** (False Positive Rate) = FP/(FP+TN) = aká časť legitimate
    je chybne označená ako phishing,
  - **TPR** (True Positive Rate) = TP/(TP+FN) = aká časť phishing je
    správne odhalená.
- **AUC** = integrál pod ROC krivkou, hodnota v intervale [0, 1].
  - 1.0 → dokonalý klasifikátor, 0.5 → náhoda (mince).
  - 0.85 už je slušný klasifikátor, 0.95+ veľmi dobrý.
- Prahovo nezávislá → férovo porovnáva kvalitu *skórovania*, nie
  konkrétneho rozhodnutia.
- **Slabina:** nevidí, čo sa stane pri konkrétnom prahu 0.5. Dva
  modely s rovnakým AUC môžu pri prahu 0.5 robiť úplne iné chyby
  (viď NB patológia v §6.1.1).

### Cross-validation (CV, krížová validácia)
Metóda odhadu výkonu modelu na neuvidených dátach. **k-fold**: dáta
rozdelené na k rovnako veľkých foldov; model trénovaný na k-1 z nich a
vyhodnotený na zvyšnom; priemer naprieč k-pokusmi.

**Stratified k-fold** zachová pomer tried v každom folde.

**Prečo?** Rozdelenie na jeden train/test split je náhodný ťah; priemer
a SD cez CV foldy dávajú robustnejší odhad výkonu + meranie
variability.

### Multikolinearita
Stav, keď sú prediktory silne lineárne korelované. Vedie k:
- nestabilným koeficientom (malá zmena dát → veľká zmena modelu),
- nafúknutým štandardným chybám,
- stratenej interpretovateľnosti.

### VIF (Variance Inflation Factor)
$$ \text{VIF}_j = \frac{1}{1 - R_j^2} $$
Diagnostika multikolinearity: VIF > 10 = vážny problém, > 100 = takmer
perfektná lineárna závislosť.

### Overfitting / underfitting
- **Overfitting**: model sa prispôsobil šumu trénovacích dát; vysoká
  AUC na tréningu, nízka na teste.
- **Underfitting**: model je príliš jednoduchý, nedosiahne dobrý fit
  ani na tréningu.

### Regularizácia
Penalizácia zložitosti modelu (obvykle L1 alebo L2 norm koeficientov)
v stratovej funkcii. Bojuje proti overfittingu a v prípade L1 aj robí
feature selection.
- **Ridge (L2):** penalizuje $\sum \beta_j^2$. Shrinkuje koeficienty k
  nule, ale nevyrobí presné 0.
- **LASSO (L1):** penalizuje $\sum |\beta_j|$. Geometria má "rohy",
  takže riešenie typicky obsahuje presné 0 → feature selection.
- **ElasticNet:** lineárna kombinácia L1 a L2.

### Párový Wilcoxonov signed-rank test
Neparametrická alternatíva párového t-testu. Testuje, či medián
rozdielov dvoch spárovaných vzoriek je 0.

**Prečo neparametrický?** Rozdiely AUC medzi modelmi **nemusia** byť
normálne rozdelené (náš vzorka má n=10, stále málo na spoľahlivé
overenie normality). Wilcoxon je robustný voči odchýlkam od normality.

**Diskrétna podlaha p-hodnoty:** pri n=10 spárovaných pozorovaniach
má jednostranný test najmenšiu možnú p-hodnotu **1/2¹⁰ = 1/1024 ≈
0.00098**. Ak všetky fold-rozdiely majú rovnaké znamienko, dosiahneme
presne túto hodnotu — nižšie sa nedá dostať bez ďalšieho navýšenia
foldov. Podstatný rozdiel oproti predošlej 5-fold verzii (podlaha
1/32 ≈ 0.031): s 10 foldami vieme po prvýkrát **odlíšiť Trust
(p ≈ 0.02)** od ostatných tierov, ktoré naďalej padajú na podlahu
(p ≈ 0.001). Test teda konečne nesie informáciu.

### Parametrický vs. neparametrický model
- **Parametrický** = pevný počet parametrov, predpoklady o distribúcii
  (LR, LDA, NB).
- **Neparametrický** = počet efektívnych parametrov rastie s dátami,
  bez distribučných predpokladov (RF, KNN, SVM).

### Kernel (jadro) v SVM
Keď data nie sú oddeliteľné rovnou čiarou v pôvodnom
priestore, **kernel je matematický trik, ktorý ich prenesie do
priestoru s vyšším počtom dimenzií**, kde uz čiarou oddeliteľné sú. SVM
potom v tom novom priestore nájde rovnú deliacu rovinu; v pôvodnom
priestore to zodpovedá zakrivenej deliacej ploche.

**RBF jadro** $K(x,y) = \exp(-\sigma \|x-y\|^2)$ — meria "podobnosť"
dvoch bodov ako gaussovský zvon okolo vzdialenosti. Čím bližšie sú
body, tým vyššia hodnota jadra. Univerzálny aproximátor: pri dostatku
dát vie aproximovať ľubovoľnú spojitú rozhodovaciu funkciu.

### Margin a support vectors
- **Margin** (okraj) = šírka pásma okolo deliacej čiary, kde nestojí
  žiadny trénovací bod. SVM hľadá **maximálny** margin — deliacu
  hranicu, ktorá má od najbližších bodov oboch tried čo najväčšiu
  vzdialenosť. Intuícia: široký margin = robustné rozhodovanie, malé
  posunutie bodu nezmení predikciu.
- **Support vectors** = body, ktoré ležia **na okraji marginu** (alebo
  zle-klasifikované body). **Iba ony** definujú deliacu hranicu — ostatné
  trénovacie body by sa mohli odstrániť a SVM by dal ten istý model.
  Typicky je to niekoľko stovák až tisícov bodov z 24 000 tréningových.

### Bagging (bootstrap aggregating)
Technika v Random Forest: namiesto jedného stromu natrénujeme **stovky
stromov**, každý na inej **bootstrap sample** (náhodný výber s
vracaním z trénovacích dát — niektoré body sa zopakujú, iné vôbec
nezahrnú). Predikcie stromov sa potom priemerujú.

**Prečo to pomáha:** jeden strom je náchylný na overfitting (vidí presný
šum v dátach). Priemer stoviek stromov, každý s trochu iným pohľadom,
dáva hladšie a robustnejšie predikcie. Efekt je podobný hlasovaniu
poroty — nezhody jednotlivých sudcov sa vyrušia, kým spoločná intuícia
prevládne.

### Bootstrap sample
Náhodný výber z trénovacej sady **s vracaním** — ak má pôvodná sada
10 000 bodov, bootstrap má tiež 10 000, ale niektoré sú zopakované 2–3×
a ~36 % bodov vôbec nie je zahrnutých (tie sú "out-of-bag" a používajú
sa na priebežné validovanie modelu).

### Out-of-bag (OOB) AUC
V RF: pre každý trénovací bod pozrieme iba na stromy, v ktorých tento
bod **nebol** v bootstrap sample (out-of-bag). Priemerujeme ich predikcie
— tým dostaneme predikciu pre tento bod, ktorú tieto stromy nevideli pri
učení. OOB AUC je teda **vnútorný CV** zadarmo, bez nutnosti oddeliť
validačnú sadu.

### Podmienená nezávislosť (v Naive Bayes)
Naive Bayes predpokladá, že príznaky sú **vnútri jednej triedy
navzájom nezávislé**. Napr. *"medzi phishing URL nemá `URLLength`
nijakú súvislosť s `NoOfDegitsInURL`"*. V realite je to naše dáta
**porušené** (|r| > 0.7), čo vedie k systematickému vychýleniu NB
predikcií. Viac detailov v §4.3.

### Kovariančná matica (pre LDA)
Matica, ktorá popisuje **ako sa spolu menia príznaky**. Na diagonále sú
variancie (rozptyly) jednotlivých príznakov, mimo diagonály kovariancie
(keď `URLLength` rastie, ako sa v priemere mení `NoOfDegits`). LDA
predpokladá, že **obe triedy** (phishing, legit) majú **rovnakú**
kovariančnú maticu — sú posunuté v priestore, ale majú rovnaký
"tvar oblaku".

### Feature selection
Proces výberu podmnožiny príznakov, ktoré idú do modelu (ostatné sa
zahodia). Dôvod: menej príznakov → jednoduchší model, lepšia
interpretovateľnosť, niekedy lepšia generalizácia. LASSO to robí
automaticky; Ridge nie (všetky zachová).

---

## 1. Scenár a hypotéza

### Čo testujeme
**H1 z EDA:** na URL-only úrovni neparametrické modely získajú
štatisticky významne viac signálu než parametrické.

EDA však ukázala, že na **Full** dataset je near-perfectly separable
(AUC ≈ 0.99 pre všetky modely) — tam sa rozdiel nedá zmerať. Preto
definujeme **4 úrovne** príznakov:

| Úroveň | # príznakov | Čo model vidí | Cena získania |
|--------|---:|---------------|---------------|
| Lexical | 13 | iba URL reťazec | zadarmo |
| Trust | 7 | doména/title/HTTPS flagy | DNS lookup |
| Behavior | 14 | page-level signály **bez 6 near-leakerov** | fetch + parse HTML |
| FullLite | 34 | všetky 3 rodiny mínus 6 near-leakerov | plná |

### Prečo vyhadzujeme 6 príznakov *všade*?
Šesť príznakov (`LineOfCode`, `NoOfExternalRef`, `NoOfImage`,
`NoOfSelfRef`, `NoOfJS`, `NoOfCSS`) má **samostatne** AUC 0.958–0.990.
Dôvod: phishing stránky sú plytké HTML shelly — majú málo obrázkov,
scriptov, externých odkazov. Takže tieto počty sú v tomto datasete
pseudo-leakery.

**Konzistentné pravidlo:** ak je to pseudo-leaker, je to pseudo-leaker
nezávisle od tier-u. Preto ich vyhadzujeme **aj z Behavior** (20→14),
**aj z FullLite** (40→34).  Po konzistentnom odstránení:
- Lexical a Trust ostávajú slabé (AUC 0.85–0.93),
- Behavior sa stáva **honest middle tier** (AUC 0.99, ale Accuracy
  rozptyl 0.86–0.97 → viditeľný family contrast),
- FullLite je **jediný** saturovaný high-dim tier — a obhajobu si
  zaslúži iba raz, ako dôkaz že 34 poctivých príznakov už stačí na
  linear separabilitu.

### Dôležité pre obhajobu
- Úrovne sú **vnorené ablácie**, nie náhodné výbery. Testujeme
  **gradient** H1: rozdiel by mal byť **najväčší na Lexical** a
  **zmenšovať sa** s pridávaným signálom.
- Scenario 2 nie je len binárne ÁNO/NIE pre H1 — je to **trajektória**
  ako sa rozdiel mení naprieč úrovňami.

---

## 2. Načítanie dát a replikácia exclusions

Zopakujeme rovnaké vylúčenie ako v EDA §3.3 (5 computed scores + 1
redundantný binárny + 4 pomery = 10 vylúčení). Cieľ: Scenario 2 testuje
na **tej istej** 40-príznakovej matrici, aby EDA závery (VIF, SMD,
šikmosť) priamo platili.

---

## 3. Setup modelovania

### 3.1 Stratifikované podvzorkovanie — prečo 30 000?

Celý dataset má 235 795 riadkov. **SVM s RBF jadrom** má zložitosť
**O(n²)–O(n³)** v počte trénovacích bodov. Trénovanie 6 modelov × 4
úrovne × 10 foldov by na celých dátach trvalo dni.

**Prečo 30 k?** Empiricky najväčšia veľkosť, kde:
- SVM-RBF dobehne v rozumnom čase (~30 min cez všetky úrovne pri
  10-fold CV),
- CV AUC má SD < 0.01 (stabilné),
- stratifikácia 15 k / 15 k drží triedy dokonale vyvážené.

**Prečo stratified, nie random sampling?** Aby pomer tried ostal fixný
naprieč úrovňami a foldami.

#### Čo by sa stalo s inou veľkosťou vzorky

| Veľkosť | Čo sa stane |
|---------|-------------|
| 5 000 | CV AUC kolíše o 0.02–0.03 medzi behmi, H1 gradient sa stráca v šume |
| 10 000 | Stabilnejšie, ale SVM-RBF trvá ešte dlho na niektorých foldoch |
| **30 000 (naša voľba)** | Najväčšia veľkosť, kde SVM-RBF dobehne v rozumnom čase (~15 min), CV SD < 0.01 |
| 100 000 | SVM by trval hodiny, RF/KNN tiež rastú; žiadny ďalší zisk stability |
| 235 000 (celý dataset) | SVM dni na tréning, experiment nepraktický; AUC sa už nezlepší |

#### Čo by sa stalo s iným počtom foldov (k)

| k | Čo sa stane |
|---|-------------|
| 3 | Málo odhadov, vysoká SD; Wilcoxon podlaha je 1/8 = 0.125 (test takmer bezmocný) |
| 5 | Rozumný kompromis času/stability; Wilcoxon podlaha 1/32 ≈ 0.031, čo celé tri silnejšie tiery stlačí na rovnakú p-hodnotu a test neinformuje |
| **10 (naša voľba)** | Dvojnásobný čas SVM (~30 min); Wilcoxon podlaha 1/1024 ≈ 0.001 — prvá úroveň, kde sa Trust (p ≈ 0.02) odlíši od ostatných tierov |
| 25 (repeated 5×5) | Lepšia štatistická moc; Wilcoxon podlaha ~10⁻⁸. Odporúčané budúce rozšírenie. |

### 3.2 Zdieľané fold indices

`createFolds(..., k=10)` vyrobí 10 fold-indexov **raz** a tie isté sa
použijú pre všetkých 6 modelov × 4 úrovne.

**Prečo to je dôležité?**
1. **Párovanie:** rozdiel AUC modelu A a B na fold i je porovnateľný s
   rozdielom na fold j, lebo sa hodnotí na rovnakých bodoch. Umožňuje
   **párový Wilcoxonov test** (§6.2).
2. **Eliminácia variability foldov:** keby mal každý model vlastné
   foldy, jeden by mohol náhodou dostať "ľahší" split a vyzerať lepší.

### 3.3 Preprocessing — dva paralelné recepty

#### Prečo dva?
Parametrické a distance-based modely majú iné požiadavky na dáta než
tree-based.

#### Parametrický / distance recept
(pre **LR, LDA, NB, SVM-RBF, KNN**)

1. **`log1p()`** na spojité príznaky.
   - EDA §4.4: 19 z 22 spojitých príznakov malo |skew| > 2.
   - `log1p(x) = log(1 + x)` je definované aj pre x = 0 (nulové
     počty URL znakov), kým `log(0) = -∞`.
   - Aproximuje normalitu pri pravostrannej šikmosti.
2. **Center + scale (z-score):** nutné pre:
   - **SVM-RBF:** jadro $K(x,y) = \exp(-\sigma \|x-y\|^2)$ je
     vzdialenostné. Bez z-score by URLLength (veľká škála)
     dominovalo vzdialenosť a ostatné by boli ignorované.
   - **KNN:** Euklidovská vzdialenosť rovnaké odôvodnenie.
   - **Regularizovaná LR (Ridge):** L2 penalizácia je symetrická v
     koeficientoch. Keby mali príznaky rôzne škály, penalizácia by
     bola prakticky asymetrická.
3. **Binárne príznaky:** netransformujeme. Log binárnej 0/1 nemá
   zmysel; centrovanie je OK, ale pre konzistenciu necháme 0/1.

#### Tree recept
(pre **Random Forest**) — **bez transformácie**.

**Prečo?**
- Trees rozhodujú splittingom typu `x < threshold`. Pre monotónny
  transform `f` platí `x < t ⇔ f(x) < f(t)` → strom by urobil to isté
  rozhodnutie s rovnakým skóre. **Invariantné na monotónne transformácie.**
- Škálovanie nemá vplyv — strom nepoužíva Euklid ani skalárny súčin.
- Preprocessing by iba stratil čas a zbytočne zaviedol možný artefakt.

### 3.4 `fit_one_tier` utility

Jedna funkcia sa volá **24×** (6 modelov × 4 úrovne). Zaručuje, že:
- každý model vidí identické `fold_idx` (viď §3.2),
- AUC je počítané rovnako cez `pROC::roc`,
- test-set metriky sú na tej istej 20 % held-out sade.

`run_or_load` je jednoduchý caching wrapper: prvý knit trénuje, ďalšie
knity len načítajú `.rds` zo `scenario_2/artifacts/`. To je dôležité,
lebo SVM-RBF trvá ~15 min a nechceme ho znovu trénovať pri každej
drobnej úprave notebooku.

---

## 4. Parametrické modely — voľba a zdôvodnenie parametrov

### 4.1 Logistická regresia s Ridge regularizáciou

**Model:** binárny logit $\log\frac{P(\text{phishing})}{1-P(\text{phishing})} = \beta_0 + \sum \beta_j x_j$.

**Ridge cieľ:** minimalizuj $-\text{loglik}(\beta) + \lambda \sum \beta_j^2$.

**Parametre:** `alpha = 0`, `lambda = 0.01` (cez `glmnet`).

#### Prečo ridge a nie obyčajná LR?
EDA §4.3 ukázala VIF > 1000 v Lexical klastri (URLLength ↔ NoOfLetters
↔ NoOfDegits). Neregularizovaná LR je tam **numericky nestabilná**:
- Hessián matice v Newton-Raphson iterácii je takmer singulárny.
- Koeficienty oscilujú medzi foldami, niekedy menia znamienko.
- Štandardné chyby sú obrovské.

Ridge (L2, α=0) penalizuje $\sum \beta^2$, čo **obmedzí normu**
koeficientov a stabilizuje fit. Nerobí feature selection — všetky
príznaky ostanú v modeli, len menšie.

#### Prečo nie LASSO (α=1)?
LASSO by robil automaticky feature selection. To by H1 "kontaminovalo"
úlohou Scenario 3. H1 sa pýta: *aký dobrý je
plne-featurizovaný parametrický model?* — nie *aký dobrý je s
automatickou redukciou*.

#### Prečo λ = 0.01 a nie CV-tuning?
- S 24 k trénovacími vzorkami a 13-34 príznakmi je model dobre
  regularizovaný aj pri malej λ.
- Väčšia λ → strata signálu (under-regularization poistka);
  menšia → nestabilita sa vracia.
- CV výber λ by bol legitímny, ale pridal by **ďalší zdroj
  variability** do porovnania rodín modelov. Pre férovosť
  kontrastu preferujeme **fixné hyperparametre** pre všetky modely.

#### Čo by sa stalo s inou hodnotou λ

| Hodnota λ | Čo sa stane | Dopad na AUC |
|-----------|-------------|--------------|
| 0 (obyčajná LR) | Numerická nestabilita v Lexical klastri, koeficienty oscilujú medzi foldami | ~stále OK na Behavior/FullLite, na Lexical prípadne chybové hlásenia konvergencie |
| 0.001 | Takmer žiadna regularizácia, koeficienty prakticky voľné | Na Lexical sa výsledky kolísajú v ±0.01 AUC medzi behmi |
| **0.01 (naša voľba)** | Malá, stabilizujúca regularizácia | Stabilné AUC, žiadna strata signálu |
| 0.1 | Mierne šetrná regularizácia | Na Lexical pokles AUC o ~0.01-0.02 |
| 1.0 | Silná regularizácia, koeficienty stiahnuté k 0 | Zreteľný pokles AUC všade (~0.03-0.05) |
| 100 | Model skoro "nič sa nenauč", predikuje priemernú pravdepodobnosť | AUC padá smerom k 0.5 (náhoda) |

**Prečo by nás malé λ nezničilo:** máme 24 000 bodov a iba 13–34
príznakov, pomer bodov/parameterov je 700–1800. V tomto režime sa aj
bez silnej regularizácie model poctivo natrénuje. λ = 0.01 len zaistí,
že pri silne korelovaných Lexical príznakoch nezačnú koeficienty
"bojovať" medzi sebou.

### 4.2 Linear Discriminant Analysis (LDA)

**Model:** predpokladá $x | y = c \sim \mathcal{N}(\mu_c, \Sigma)$, s
**rovnakou kovariančnou maticou** pre oba triedy. Rozhodovacia funkcia
je lineárna.

**Parametre:** žiadne. LDA nemá ladeľné hyperparametre.

#### Prečo LDA?
Je to **čistý lineárny baseline** bez regularizácie, ale s priaznivou
vlastnosťou — implicitná "shrinkage" cez spoločnú kovariančnú maticu
oboch tried. Po `log1p` + scale sú podmienené distribúcie aspoň
približne Gaussovské, takže predpoklad LDA je slušne splnený.

#### Prečo nie QDA (Quadratic DA)?
QDA odhaduje **zvlášť** kovariančnú maticu pre každú triedu, teda
2× viac parametrov. Dôsledky:
- Pri 7 binárnych Trust flagoch má trieda kovariančnú maticu s
  množstvom núl a **inverzia zlyhá** (singulárna matrix).
- QDA vyrába kvadratickú rozhodovaciu plochu → inú tried modelov
  než lineárne.

Pre "parametrický lineárny baseline" je LDA správna voľba.

### 4.3 Naive Bayes (NB)

**Model:** predpokladá **podmienenú nezávislosť** príznakov v triede:
$P(y | x) \propto P(y) \prod_j P(x_j | y)$.

**Parametre:** `fL = 1` (Laplaceov smoothing), `usekernel = TRUE`,
`adjust = 1` (bandwidth multiplier = default).

#### Prečo `usekernel = TRUE` (kernel density) a nie Gaussian NB?
Gaussian NB odhaduje $P(x_j | y)$ ako $\mathcal{N}(\mu_{j,y}, \sigma_{j,y})$.
Pre **binárne** príznaky (napr. `Robots` v Trust) sa v niektorej CV folde môže
stať, že variancia vo fold je **presne 0** (všetky príklady v triede
majú rovnakú hodnotu). Delenie nulou → NaN → pád modelu.

**Kernel density estimator** (Parzenovo okno) toto zvládne aj pri
nulovej variancii, lebo odhaduje hustotu cez šikmé Gaussovské jadrá
okolo pozorovaných bodov.

#### Prečo `fL = 1` (Laplace smoothing)?
Pre kategoriálne príznaky: ak niektorá kombinácia `(trieda, hodnota)`
nie je v tréningovej sade, $P(x_j = v | y) = 0$ a celý Bayesov produkt
sa vynásobí nulou → model vôbec nepredikuje. `fL = 1` pridá každému
count pseudo-count 1 → žiadna 0.

#### Prečo vôbec testujeme NB, keď EDA ukázala kolineárne príznaky?
Presne preto. NB predpokladá **podmienenú nezávislosť**, čo na našich
dátach **nie je** splnené (|r| > 0.7 v Lexical klastri). Chceme
empiricky zmerať, **koľko NB stratí** kvôli porušeniu tohto predpokladu.

#### Čo by sa stalo s iným `fL`

| Hodnota fL | Čo sa stane |
|------------|-------------|
| 0 | Niektorá kombinácia (trieda, hodnota) môže mať P = 0 → celý produkt Bayesovej pravdepodobnosti sa vynásobí nulou → model na týchto bodoch nevie predikovať |
| **1 (naša voľba, štandard)** | Každej kombinácii sa pridá 1 pseudo-count → P(x=v\|y) nikdy nie je 0 |
| 10 | Prílišné vyhladenie, reálne vzory v dátach sa "rozpustia" v pseudo-countoch → pokles AUC |

#### Čo by sa stalo s iným jadrom hustoty (`usekernel`)

| Voľba | Čo sa stane |
|-------|-------------|
| `FALSE` (Gaussian NB) | Pri nulovej variancii vo folde (binárny príznak, všetky body rovnaké) → delenie nulou → pád modelu |
| **`TRUE` (naša voľba, KDE)** | Kernel density estimator zvládne aj nulovú varianciu; odhaduje hustotu cez gaussovské jadrá okolo pozorovaných bodov |

---

## 5. Neparametrické modely — voľba a zdôvodnenie parametrov

### 5.1 Random Forest (RF)

**Model:** ensemble `ntree` decision trees; každý trénovaný na
bootstrap sample dát a na náhodnom podmnožine `mtry` príznakov pri
každom splite. Predikcia = priemer pravdepodobností stromov.

**Parametre:** `ntree = 300`, `mtry = floor(sqrt(p))`.

#### Prečo mtry = √p?
Je to **štandard pre klasifikáciu** (Breiman 2001).
- Pre p = 13 (Lexical): mtry = 3.
- Pre p = 34 (FullLite): mtry = 5.

Matematická intuícia:
- Menšie mtry → stromy sa viac líšia → väčšia **dekorelácia** →
  menšia variancia ensemblu.
- Väčšie mtry → individuálne silnejšie stromy, ale korelácia rastie →
  prírastok stromov prestáva pomáhať.

√p je empiricky dobrý kompromis; nič v EDA nás nenúti odchýliť sa.

#### Prečo 300 stromov?
- Out-of-bag AUC konverguje na tomto datasete po ~200–300 stromoch.
- 300 je **najmenšia hodnota, pri ktorej AUC už nerastie** — každý
  strom navyše je compute, za ktorý nič nedostaneme.
- Empiricky overené: prepočet s `ntree = 500` dáva totožné AUC v
  rámci 0.001 na všetkých 4 tiers, čiže pridávať stromy je len
  marketing stability, nie reálny zisk.

#### Prečo neladiť `maxdepth`, `nodesize`?
- RF je robustný voči týmto parametrom. Default `nodesize = 1` (plné
  stromy) je typicky optimálny pre klasifikáciu.
- Zámer Scenario 2 je **porovnať rodiny modelov**, nie ladiť
  jednotlivé. Viac hyperparametrov = väčšia plocha na cherry-picking
  = menšia metodologická férovosť.

#### Čo by sa stalo s iným `mtry`

| Hodnota | Čo sa stane |
|---------|-------------|
| 1 | Stromy sú takmer náhodné (každý split pozerá iba 1 príznak) → príliš dekorelované → individuálne slabé → pomalý konverg AUC |
| **√p (naša voľba)** | Štandardný kompromis medzi silou jednotlivých stromov a ich dekoreláciou |
| p (všetky príznaky) | "Bagged trees" bez náhodnosti, stromy sú si veľmi podobné → variancia ensemblu sa neznižuje → overfit podobný jednému stromu |

#### Čo by sa stalo s iným počtom stromov

| ntree | Čo sa stane |
|-------|-------------|
| 10 | Nestabilné, medzi behmi AUC kolíše o 0.01–0.02 |
| 100 | Už takmer stabilné, AUC dosiahne ~99 % konvergenčnej hodnoty |
| **300 (naša voľba)** | Najmenšia hodnota, kde AUC už neprirastá — optimum ceny a stability |
| 500 | Totožné AUC (rozdiel < 0.001), len ~1.7× pomalší tréning |
| 5000 | Prakticky identické ako 300, len ~17× dlhšie |

### 5.2 SVM s RBF jadrom

**Model:** nájdi nadrovinu v priestore, kam je dátami namapovaný cez
RBF jadro $K(x,y) = \exp(-\sigma \|x - y\|^2)$; táto nadrovina
maximalizuje margin medzi triedami.

**Parametre:** `C = 1`, `sigma = 0.1`.

#### Prečo RBF a nie iné jadro?
- **Lineárne:** prakticky ekvivalentné regularizovanej LR — nič nové.
- **Polynomiálne:** stupeň > 2 nafukuje feature priestor, extrémne
  náchylné na overfitting.
- **RBF:** kanonická **nelineárna neparametrická** alternatíva.
  Univerzálny aproximátor (môže aproximovať ľubovoľnú spojitú
  rozhodovaciu funkciu pri dostatku dát).

#### Prečo C = 1?
C je parameter **penalizácie chýb**: $\min \frac{1}{2}\|w\|^2 + C \sum \xi_i$,
kde $\xi_i$ sú slack variables (chyby).

- **Malé C** → veľké marginy, viac chýb povolených, underfit.
- **Veľké C** → malé marginy, chyby penalizované silno, overfit.
- **C = 1** je **typický default** pre štandardizované vstupy; zodpovedá
  predpokladu "trade-off je vyvážený".

#### Prečo σ = 0.1?
σ určuje šírku RBF jadra. Pri štandardizovaných vstupoch (každý
príznak má SD = 1) je $\|x - y\|^2$ typicky v ráde 1-10, takže
$\sigma \|x-y\|^2 \approx 0.1-1$, čo dáva $K(x,y) \in [0.37, 1]$ —
**pekný dynamický rozsah** jadra.

- **Príliš malé σ** (napr. 0.001) → jadro je skoro konštantné = 1 →
  model je takmer lineárny.
- **Príliš veľké σ** (napr. 10) → jadro rýchlo padá na 0 → každý
  bod ovplyvňuje iba svojich najbližších susedov → overfit.

#### Prečo sme neladili `C × σ` mriežku?
- Tuning by pridal 15-25× čas výpočtu.
- Naša otázka je *"aký je rozdiel medzi rodinami pri rozumných default
  parametroch?"*, nie *"aký je absolútne najlepší SVM?"*
- Tuning všetkých 6 modelov v rovnakom rozsahu by bol pre LDA (0
  hyperparametrov) zbytočný; nefér porovnanie.

#### Čo by sa stalo s iným C

| Hodnota C | Čo sa stane | Intuícia |
|-----------|-------------|----------|
| 0.01 | Margin extrémne široký, chyby takmer zadarmo → underfit | "Model si môže dovoliť prehliadnuť body" |
| 0.1 | Mierne pokojnejší SVM, pokles AUC o 0.01–0.02 na Lexical | Väčší margin, menej support vectors |
| **1 (naša voľba, štandard)** | Vyvážený trade-off | Default pre štandardizované vstupy |
| 10 | Agresívnejší fit, viac support vectors, mierne overfit | "Chyby sú veľmi drahé" |
| 100+ | Extrémny overfit, rozhodovacia plocha prispôsobená šumu | Train AUC ≈ 1, Test AUC výrazne nižší |

#### Čo by sa stalo s iným σ

| Hodnota σ | Čo sa stane | Intuícia |
|-----------|-------------|----------|
| 0.001 | RBF jadro je skoro konštantné (≈ 1 pre všetky páry bodov) → SVM sa správa takmer lineárne | Stratíme výhodu nelinearity |
| 0.01 | Jadro je veľmi hladké, deliaca plocha pokojná | Underfit pri zložitejších vzoroch |
| **0.1 (naša voľba)** | Rozumná šírka pre z-score vstupy, $K(x,y) \in [0.37, 1]$ typicky | Dobré dynamické rozpätie jadra |
| 1 | Ostrejšie jadro, každý bod ovplyvní iba tesných susedov | Začína sa overfit |
| 10 | Jadro takmer δ-funkcia, iba zhodné body majú nenulovú hodnotu → SVM v podstate memoruje trénovaciu sadu | Katastrofický overfit |

### 5.3 K-Nearest Neighbors (KNN)

**Model:** klasifikuj bod podľa väčšinového hlasovania **k najbližších
susedov** v tréningovej sade, vzdialenosť = Euklidovská.

**Parametre:** `k = 25`.

#### Prečo k = 25?
Rule-of-thumb: $k \approx \sqrt{n_{\text{train}}}$. Pri 24 k bodoch by to
bolo ~155, ale tam by sa Lexical signál už veľmi vyhladil.

- **k = 1:** overfit, naivný k outlierom (každý bod určuje sám).
- **k = 25:** stredný pesimistický kompromis — dostatočne veľká na
  vyhladenie šumu, dostatočne malá na zachytenie lokálnej štruktúry.
- **k = 155:** príliš hladké, Lexical by sa stratilo v priemere.

#### Prečo Euklidovská vzdialenosť (default)?
Po z-score sú všetky spojité príznaky v rovnakej škále (SD = 1), takže
Euklid je vyvážený. Pre čisto binárne priestory by sa viac hodila
Hamming/Jaccard vzdialenosť, ale `knn3` z caret podporuje hlavne Euklid.

#### Prečo jitter σ = 10⁻³ v Trust tier?
Trust má 7 binárnych príznakov. Mnohé trénovacie body majú **identické
súradnice** (napr. 200 bodov s hodnotou `(1,0,0,1,1,0,0)`). `knn3`
vyhlási chybu `"too many ties in knn"`.

**Riešenie:** pridáme gaussovský šum s SD = 10⁻³ = 0.1 % škály. To
rozbije tie bez zmeny rozhodnutia (0.001 je zanedbateľné v porovnaní s
veľkosťou cluster).

#### Čo by sa stalo s inou hodnotou k

| Hodnota k | Čo sa stane |
|-----------|-------------|
| 1 | Model je extrémne citlivý — outlier v susedstve určí rozhodnutie. Train AUC = 1 (každý bod je sám sebe suseda), Test AUC padá kvôli šumu |
| 5 | Mierne šetrnejšie, stále citlivé na lokálne anomálie |
| **25 (naša voľba)** | Kompromis: dostatočne veľké hlasovanie na vyhladenie šumu, stále citlivé na lokálnu štruktúru |
| 155 (≈√n) | Príliš hladké, lokálny phishing cluster sa stratí v priemere širokého susedstva |
| n = 24 000 | Každá predikcia je priemer celej trénovacej sady → model predikuje iba priemernú P(phishing) → AUC ≈ 0.5 |

#### Čo by sa stalo s inou hodnotou jittera

| Jitter SD | Čo sa stane |
|-----------|-------------|
| 0 | `knn3` zlyhá na Trust tier kvôli ties |
| **10⁻³ (naša voľba)** | Ties rozbité, šum zanedbateľný v porovnaní s unit distance medzi susedmi |
| 0.1 | Šum 10 % škály — začal by narúšať reálnu štruktúru, body z odlišných tried by sa miešali v susedstve |
| 1 | Šum rovnakej veľkosti ako signál → KNN by hlasoval takmer náhodne |

---

## 6. Porovnanie výsledkov

### 6.1 Súhrnná tabuľka (priemer CV AUC)

| Model | Lexical | Trust | Behavior | FullLite |
|-------|--------:|------:|---------:|---------:|
| LogReg-Ridge | 0.861 | 0.924 | 0.992 | 1.000 |
| LDA | 0.931 | 0.923 | 0.993 | 1.000 |
| NaiveBayes | 0.861 | 0.922 | 0.991 | 0.999 |
| Random Forest | 0.973 | 0.924 | **0.997** | **1.000** |
| **SVM-RBF** | **0.997** | 0.917 | 0.995 | 1.000 |
| KNN | 0.989 | **0.932** | 0.995 | 1.000 |

**Čo sa zmenilo oproti predošlej verzii:** po odstránení 6 near-leakerov
z Behavior (20→14 príznakov) Behavior viac nesaturuje presne na 1.0 —
modely sa rozprestreli v pásme 0.990–0.997. Gradient H1 je teraz
čitateľnejší: family contrast vidno nielen na Lexical, ale aj na
Behavior (najmä v Accuracy, viď §6.1.1).

### 6.1.0 Train vs. Test — diagnostika overfittingu

Každá per-model tabuľka v §4–§5 má okrem `CV ROC` a `Test AUC` aj nové
stĺpce **`Train AUC`** a **`Gap = Train − Test`**. Sú tam úmyselne,
pretože komisia sa skoro určite opýta *"ako viete, že modely
nepretrénovávate?"*.

#### Čo očakávame a prečo

**Parametrické modely (LR-Ridge, LDA, NB):**
- Majú málo efektívnych parametrov — Ridge navyše aktívne potláča
  koeficienty.
- **Nevedia zapamätať** 24 000 trénovacích riadkov.
- Preto `Train AUC ≈ Test AUC`, gap < 0.01.
- Ak by gap bol veľký, znamená to dierovú preprocessing pipeline alebo
  leakage (to tu nemáme — `preProcess` je fit raz na train, testy
  používajú tie isté mean/SD).

**Neparametrické modely (RF, SVM-RBF, KNN):**
- Random Forest: predikcia na trénovacích dátach je **takmer dokonalá**
  (~1.000), lebo každý bod bol v in-bag sade väčšiny stromov. To nie je
  bug — to je definícia baggingu.
- KNN (k=25): trénovací bod je svojím vlastným najbližším susedom →
  Train AUC blízko 1.0.
- SVM-RBF: pri C=1 a σ=0.1 si dokáže nasadiť flexibilnú hranicu, Train
  AUC typicky 0.99+.

**Takže veľký `Train − Test` gap na RF/KNN nie je alarm.** Je to ich
prirodzené správanie. Reálny test generalizácie je, či **`CV ROC` a
`Test AUC` sedia spolu**. Obe sú out-of-sample a preto merajú
generalizáciu poctivo.

#### Čo hľadať v tabuľkách

| Stĺpce na porovnanie | Čo znamená, keď sedia | Čo znamená, keď sa líšia |
|----------------------|------------------------|---------------------------|
| `Train AUC` vs. `Test AUC` | Model generalizuje (parametrické) | Normálne pre RF/KNN — ignoruj |
| **`CV ROC` vs. `Test AUC`** | **Generalizácia je reálna** | **Test set je šťastný/nešťastný** |
| `CV ROC` vs. tier | Signál v tieri je stabilný | Model je citlivý na fold zloženie |

Pravé tvrdenie pre obhajobu znie:
> *"Pre každý model sme porovnali `CV ROC` a `Test AUC`. Tieto dve
> hodnoty sa nelíšia o viac ako 0.01 na žiadnom tieri — to znamená, že
> náš test set reprezentuje generalizačnú výkonnosť verne a H1 gradient
> je meraný na skutočnej out-of-sample výkonnosti, nie na in-bag fite."*

#### Čo keby gap na RF bol podozrivý

Ak by `Test AUC < CV ROC − 0.02` na RF, znamenalo by to:
1. Trénovacia a testovacia sada sa líšia v distribúcii (unlikely tu, bolo
   `createDataPartition` stratifikované).
2. CV folds náhodou dostali ľahšie príklady — riešenie: opakované CV
   (repeated 5×5 CV) alebo väčší test set.
3. Skutočné pretrénovanie — riešenie: `max_nodes`, hlbšie pruning, menej
   stromov.

**V našich výsledkoch tento problém nenastáva** — CV a Test sa na
všetkých tiers zhodujú v rámci 0.01.

### 6.1.1 Klasifikačná kvalita nad rámec AUC

#### Prečo nestačí AUC
AUC ordinálne triedi body podľa skóre — ale dve veci potichu zakrýva:

1. **Saturáciu na horných úrovniach.** Na Behavior a FullLite má každý
   model AUC ≈ 0.99+, takže tabuľka AUC tam vidí len drobné rozdiely.
   Na Accuracy a F1 sú reziduálne rozdiely stále viditeľné (rozdiel
   medzi 86 % NB a 97 % RF na Behavior je **5× rozdiel chybovosti**).
2. **Typ chyby.** V bezpečnostnej aplikácii je **False Negative**
   (phishing, ktorý sme nezachytili) typicky drahší ako **False
   Positive** (legitímna stránka, ktorá sa zablokovala). AUC na toto
   nereaguje — rozklad Sensitivity / Specificity áno.

#### Rýchle pripomenutie pojmov
- **Accuracy** = (TP + TN) / N — podiel správnych predikcií.
- **F1** = harmonický priemer Precision a Recall.
- **Precision (PPV)** = TP / (TP + FP) — z URL, ktoré sme označili ako
  phishing, koľko ich naozaj bolo. **Vysoká Precision = málo falošných
  poplachov vzhľadom k počtu alarmov.**
- **Sensitivity (Recall, TPR)** = TP / (TP + FN) — aký podiel phishing
  URL sme správne zachytili. **Vysoká Sensitivity = málo chýb typu FN.**
- **Specificity (TNR)** = TN / (TN + FP) — aký podiel legitímnych sme
  správne neoznačili. **Vysoká Specificity = málo falošných poplachov.**

Všetky tieto metriky sú počítané pri **default prahu 0.5**.

Precision je čítaná priamo z held-out confusion matrix cez
`caret::confusionMatrix(...)$byClass["Precision"]`, teda $TP/(TP+FP)$.
Pri vyváženej test sade 1:1 (~50/50 po stratifikovanom splite) by
analytický vzorec `Prec = Sens / (Sens + (1 − Spec))` dal prakticky
identické hodnoty, no čítanie priamo z confusion matrix je presnejšie
a nezávisí na triednom pomere v test sade — odporúčaná cesta pre
akékoľvek budúce re-sampling experimenty.

#### Namerané hodnoty na test sade

| Model | Tier | Acc | F1 | Prec | Sens | Spec |
|-------|------|----:|---:|-----:|-----:|-----:|
| LogReg-Ridge | Lexical | 0.818 | 0.835 | 0.764 | 0.921 | 0.716 |
| LDA          | Lexical | 0.829 | 0.851 | 0.757 | 0.971 | 0.688 |
| NaiveBayes   | Lexical | 0.691 | 0.764 | **0.618** | **0.999** | **0.383** |
| RandomForest | Lexical | 0.856 | 0.871 | 0.792 | 0.967 | 0.745 |
| **SVM-RBF**  | Lexical | **0.984** | **0.984** | **0.983** | 0.985 | 0.983 |
| KNN          | Lexical | 0.934 | 0.934 | 0.925 | 0.944 | 0.923 |
| NaiveBayes   | Behavior | 0.864 | 0.843 | **0.995** | 0.732 | **0.996** |
| LDA          | Behavior | 0.943 | 0.941 | 0.979 | 0.905 | 0.981 |
| LogReg-Ridge | Behavior | 0.952 | 0.952 | 0.967 | 0.937 | 0.968 |
| RandomForest | Behavior | **0.975** | **0.975** | 0.978 | 0.972 | 0.978 |
| SVM-RBF      | Behavior | 0.968 | 0.968 | 0.970 | 0.966 | 0.970 |
| KNN          | Behavior | 0.967 | 0.967 | 0.967 | 0.968 | 0.967 |
| RandomForest | FullLite | **0.996** | **0.996** | 0.996 | 0.997 | 0.996 |

(Plná tabuľka všetkých 24 kombinácií je v `scenario_2.rmd` §6.1.)

#### Kľúčové pozorovania

**1. Praktický preklad H1 na Lexical.**
- SVM-RBF: Accuracy 0.984 (2 chyby zo 100).
- LR-Ridge: Accuracy 0.818 (18 chýb zo 100).
- **9× viac chýb pre parametrický model.** To je rozdiel medzi
  použiteľným filtrom a filtrom, ktorý ignorujeme v praxi.

**2. Naive Bayes na Lexical — poučná patológia.**
- Sens = **0.999**, Spec = **0.383**.
- Model predikuje "phishing" pre skoro všetko. Vysoká AUC (0.861) je
  zavádzajúca — pri prahu 0.5 je Spec katastrofálna.
- Priamy dôkaz, že **porušený predpoklad nezávislosti** (viď EDA
  §4.3) spôsobí systematický posun pravdepodobností. NB sa "bojí"
  viac phishingu než treba.
- V produkcii by prah 0.5 bolo potrebné posunúť výrazne vyššie
  (napr. na 0.9+) alebo model prekalibrovať.

**3. LDA vs. LR-Ridge na Lexical — napriek podobnej AUC rôzne chyby.**
- LDA: Sens 0.971 / Spec 0.688 — skôr prepúšťa legitímne ako
  phishing.
- LR-Ridge: Sens 0.921 / Spec 0.716 — trochu vyváženejší.
- Obidve sú však výrazne horšie ako SVM-RBF (0.985 / 0.983), ktorý je
  prakticky **symetrický v oboch smeroch**.

**4. Behavior je honest middle tier — AUC už nesaturuje, family
contrast vidno v Accuracy.**
- NB na Behavior: AUC 0.990, Acc 0.864, Sens 0.732 / Spec 0.996 —
  NB "sa bojí phishingu pri prahu 0.5" aj tu, len menej extrémne než
  na Lexical.
- RF na Behavior: AUC 0.996, Acc 0.975.
- **Rozdiel v chybovosti ~5×** (136 vs. 26 chýb na 1000 URL) pri
  rozdiele AUC len 0.006. Presne toto je informácia, ktorú 20-feature
  verzia Behavior strácala (tam bola NB Acc ≈ 0.97, teda 5× menej chýb
  než teraz — lebo leakery robili prácu za model).
- **Všetky 3 neparametrické modely (RF/SVM/KNN) sú balanced**
  (Sens ≈ Spec ≈ 0.97). Parametrické robia asymetrické chyby.

**5. Sens/Spec v bezpečnostnej úvahe.**
- Ak je **cena FN >> cena FP** (banka chce nulovú šancu na prepustenie
  phishingu), vyberieme model s vysokou Sensitivity a prah posunieme
  nižšie — akceptujeme viac falošných poplachov.
- Ak je **cena FP >> cena FN** (nechceme otravovať používateľa), ide o
  opačný kompromis.
- Tabuľka Sens/Spec dáva komisii presnú odpoveď na otázku *"aký typ
  chyby ten model robí?"* — čo AUC sama od seba nepovie.

#### Cost-weighted pohľad — čo tie metriky znamenajú ekonomicky

Phishing detektor robí **dva typy chýb s veľmi rôznou cenou**:

| Chyba | Čo znamená | Kto platí | Relatívna cena |
|-------|------------|-----------|-----------------|
| **FN** (False Negative) | prepustíme phishing URL | koncový používateľ → krádež hesla / peňazí / dát | **vysoká** (stovky až tisíce € na incident) |
| **FP** (False Positive) | zablokujeme legitímnu URL | používateľ nahnevaný, IT support ticket, strata dôvery | **nízka** (minúty času, pár € na ticket) |

V bezpečnostnej literatúre sa pre bankový / corporate phishing uvádza
pomer **cena(FN) ≈ 10–100 × cena(FP)**. Náš dataset je prakticky
vyvážený (43/57), takže expected loss zjednoduší sa na:

$$ \text{Loss} \approx P(\text{phish}) \cdot C_{FN} \cdot (1-\text{Sens}) + P(\text{legit}) \cdot C_{FP} \cdot (1-\text{Spec}) $$

#### Priame prepojenie na naše metriky
- **Sensitivity = 1 − miera FN** → *koľko phishingu sme zachytili*.
  **Priamo viazané na drahú chybu.** Sens = 0.95 = 5 zo 100 phishing
  URL prejde, v bankovom nasadení neprijateľné.
- **Specificity = 1 − miera FP** → *koľko legitímnych sme nezablokovali*.
  **Priamo viazané na lacnú, ale častú chybu.** Spec = 0.80 = 20 zo
  100 legitímnych URL falošne blokneme — používateľ filter obíde
  alebo ho vypne.

#### Cost interpretácia našich Lexical výsledkov

| Model | Sens | Spec | Produkčný verdikt |
|-------|-----:|-----:|-------------------|
| NaiveBayes | 0.999 | **0.383** | zachytí takmer všetko, ale 62 % legit blokuje → **nepoužiteľné** |
| LR-Ridge | 0.921 | 0.716 | 8 % phish prejde **a** 28 % FP — dvojnásobná bolesť |
| LDA | 0.971 | 0.688 | menej extrémny NB |
| RandomForest | 0.967 | 0.745 | prekvapivo nevyvážené — 25 % FP |
| **KNN** | 0.944 | 0.923 | vyvážený, produkčne použiteľný |
| **SVM-RBF** | **0.985** | **0.983** | **jasný víťaz** — FN aj FP pod 2 % |

#### Praktické dôsledky pre projekt
1. **H1 platí aj v cost-weighted zmysle**, nielen v AUC. Parametrické
   modely robia horšie **obidva typy chýb** na Lexical.
2. **Prah 0.5 je naivný.** V produkcii by sme ho ladili podľa business
   cost ratio. Napr. pri C_FN = 10 × C_FP by sme chceli Sens čo
   najvyššiu pri Spec ≥ 0.95 → pre NB by to znamenalo posun prahu na
   ~0.9+, pre SVM-RBF stačí ponechať 0.5.
3. **Odporučený first-line filter = SVM-RBF na Lexical** — nie preto,
   že má najvyššiu AUC, ale preto, že je **jediný s oboma metrikami
   > 0.98 bez ladenia prahu**.

#### Čo si zapamätať pre obhajobu

Keď komisia namietne *"AUC ≈ 1, takže všetko funguje"*:
1. **Na Lexical AUC nesaturuje** a ukazuje masívny rozdiel — tam
   funguje klasicky.
2. **Na horných úrovniach saturuje**, ale Accuracy a F1 odkrývajú, že
   rozdiely medzi modelmi sú stále rádovo odlišné v chybovosti.
3. **Sens/Spec rozklad je v bezpečnosti povinný** — dva modely s
   rovnakou Accuracy môžu robiť úplne iný typ chýb a v produkcii
   budú mať rôzny dopad na používateľa.

Keď komisia položí *"aká je obchodná hodnota toho modelu?"*:
> *"Pri cenovom pomere 10:1 FN:FP a 24 k predikciách denne by SVM-RBF
> oproti LR-Ridge ušetril rádovo stovky nezachytených phishing
> incidentov a tisíce falošných poplachov denne. AUC sama o sebe to
> nedokáže povedať — preto sme pridali Sens/Spec rozklad a cost-weighted
> interpretáciu."*

#### Accuracy a F1 v kontexte nášho projektu

Komisia sa môže opýtať *"čo konkrétne znamená Accuracy a F1 pre váš
projekt, keď už máte AUC?"*. Odpoveď má tri vrstvy.

**Accuracy — celková chybovosť pri prahu 0.5**

Vzorec: `(TP + TN) / N` — podiel všetkých správne klasifikovaných URL.

V našom projekte má Accuracy **zmysel**, lebo dataset je takmer
vyvážený (~43 % phish / 57 % legit). V silne nevyvážených úlohách (napr.
1 % phish / 99 % legit) by bola klamlivá — model *"všetko je legit"* by
mal 99 % Accuracy, ale nulovú užitočnosť.

Konkrétne čísla pre Lexical tier prekladajú AUC do praxe:

| Model    | Accuracy | Chýb na 1000 URL |
|----------|----------|------------------|
| SVM-RBF  | 0.984    | ~16              |
| KNN      | 0.934    | ~66              |
| RF       | 0.856    | ~144             |
| LDA      | 0.829    | ~171             |
| LR-Ridge | 0.818    | ~182             |
| NB       | 0.691    | ~309             |

SVM-RBF robí **~9× menej chýb** než LR-Ridge na tom istom tieri. To je
argument, ktorý komisia pochopí okamžite — nie abstraktný AUC 0.997 vs.
0.861.

**F1 — harmonický priemer Precision a Recall**

Vzorec: `2 · (Precision · Recall) / (Precision + Recall)`.

- **Precision** = `TP / (TP + FP)` — z URL, ktoré sme označili ako
  phish, koľko naozaj bolo phish.
- **Recall (= Sens)** = `TP / (TP + FN)` — z reálnych phishov koľko sme
  chytili.

F1 je vysoké **len vtedy, keď sú obe vysoké naraz**. Trestá modely,
ktoré sú dobré v jednej veci a zlé v druhej.

Prečo je F1 v našom projekte dôležitejšie než samotné Accuracy:
Accuracy nevidí **asymetriu FN vs. FP**. F1 ju aspoň čiastočne odhalí —
ak model všetko označí ako phish (vysoký Recall, nízka Precision), F1
padá.

Ukážka na **Naive Bayes (Lexical)**:
- Accuracy = 0.691 — pôsobí priemerne.
- Sens = 0.999, Spec = 0.383 — **patológia**.
- F1 ≈ 0.764 — signalizuje nerovnováhu, ktorú AUC (0.861) zakryje.

NB má rozumný AUC, lebo **rozlišuje poradie** skóre slušne, ale pri
prahu 0.5 hádže takmer všetko do phish triedy. Accuracy to odhalí
čiastočne, F1 presnejšie, Sens/Spec úplne.

**Ako tri metriky spolupracujú**

| Metrika     | Čo meria                              | Slabina                               |
|-------------|---------------------------------------|---------------------------------------|
| **AUC**     | Schopnosť zoraďovať (threshold-free)  | Nevie, ako sa rozhodne pri prahu 0.5  |
| **Accuracy**| Reálna chybovosť pri prahu 0.5        | Slepá voči asymetrii FN/FP            |
| **F1**      | Kvalita pozitívnej (phish) triedy     | Ignoruje TN                           |

Z toho plynie náš postup pri obhajobe:
1. **AUC vyberá modely** — ukazuje, ktorý model má najlepšie poradie
   skóre a je teda kandidát na nasadenie.
2. **Accuracy + F1 + Sens/Spec hodnotia praktickú kvalitu** pri prahu
   0.5 — odhalia modely, čo "vyzerajú dobre podľa AUC" ale pri
   rozhodovaní kolabujú (typicky NB).
3. **Cost-weighted pohľad vyberá prah** — ak FN je 10× drahšie než FP,
   posunieme prah tak, aby sme maximalizovali Sens na úkor Spec, a
   sledujeme očakávanú stratu, nie Accuracy.

**Krátka odpoveď pre komisiu:**
> *"Accuracy meria celkovú chybovosť pri prahu 0.5 a má zmysel, lebo
> náš dataset je takmer vyvážený. F1 je citlivejšie na nerovnováhu
> medzi Precision a Recall, takže odhalí patologické modely ako Naive
> Bayes, kde vysoký AUC maskuje kolaps specificity. Obe metriky
> dopĺňajú AUC — AUC povie, či model vie zoraďovať; Accuracy a F1
> povedia, ako dobre sa pri danom prahu skutočne rozhoduje."*

### 6.2 Párový Wilcoxonov test — ako čítať p-hodnotu

Test je **jednostranný** (`alternative = "greater"`): alternatíva
"neparametrické > parametrické".

**POZOR na podlahu p-hodnoty:** s 10 foldami je najmenšia možná
jednostranná p-hodnota **1/1024 ≈ 0.00098**. Ak všetkých 10 foldov
neparametrický prekonal parametrický, dostaneme presne túto hodnotu.
(V predošlej 5-fold verzii bola podlaha 1/32 ≈ 0.031 a všetky tiery
na ňu padali — test bol pri malom k prakticky nemý.)

**Namerané hodnoty pri 10 foldoch:**

| Tier | diff (np − p) | Wilcoxon p | Interpretácia |
|------|--------------:|-----------:|---------------|
| **Lexical** | **+0.102** | 0.00098 | na podlahe — každý z 10 foldov ide v smere H1, efekt masívny |
| Trust | +0.0019 | **0.019** | **mimo podlahy** — test korektne zachytil, že signál je slabý |
| Behavior | +0.004 | 0.00098 | na podlahe, ale diff je malý (~0.4 % AUC) — štatisticky konzistentné, prakticky bezvýznamné |
| FullLite | +0.0003 | 0.00098 | na podlahe, diff ~0 — saturované |

**Pravidlo obhajoby:** vždy uvádzať aj `diff`, aj `p`.
- **p-hodnota** odpovedá na otázku *"ide efekt konzistentne rovnakým
  smerom naprieč foldmi?"* Pri 10 foldoch to už aspoň rozlíši Trust.
- **diff** odpovedá na otázku *"je ten efekt veľký?"* Tam má p-hodnota
  svoj limit — Behavior (0.004) a Lexical (0.102) majú rovnakú p-hodnotu
  0.00098, hoci sa v praxi líšia rádovo.

### 6.3 Boxplots per úroveň
Každý bod na ploche = jedna CV fold. Farby: modrá = parametrický,
červená = neparametrický. Vizuálne je to najpresvedčivejší dôkaz H1:
na Lexical sú červené boxy **výrazne vyššie** než modré; na ďalších
úrovniach sa farby postupne miešajú.

---

## 7. Interpretácia výsledkov

### Hlavné pozorovania

**1. Na Lexical úrovni: H1 drvivo potvrdené**
- Najlepší neparametrický: SVM-RBF → CV AUC = **0.997**.
- Najlepší parametrický: LDA → CV AUC = **0.931**.
- **ΔAUC = 0.066** — viac ako **trojnásobok** prahu C1 (0.02).
- LR-Ridge a Naive Bayes klesajú až na ~0.861 → za LDA aj za nimi
  zostáva SVM-RBF s masívnym náskokom.
- RBF jadro a lokálne hlasovanie (KNN = 0.989) zachytávajú nelineárne
  **interakcie** typu `URLLength × NoOfDegits × NoOfSubDomain`,
  ktoré ani ridge-regularizovaný logit nedokáže modelovať.

#### Prečo je LDA na Lexical prekvapivo silná (0.931)?
Po `log1p` + scale sú podmienené distribúcie rozumne Gaussovské a LDA
má **implicitnú shrinkage** cez spoločnú kovariančnú maticu. Ridge-LR
s α=0 a malou λ nemôže "zabudnúť" kolineárne príznaky tak efektívne
ako LDA zmiešavajúca variability oboch tried.

**2. Na Trust úrovni: H1 konzistentný, ale prakticky zanedbateľný**
- Všetkých 6 modelov: 0.917–0.932.
- Diff ≈ +0.0019 → pri 10-fold CV Wilcoxon **p = 0.019** (nad podlahou
  1/1024). Smer efektu je konzistentný naprieč foldmi, ale amplitúda
  je zanedbateľná.
- Dôvod: 7 príznakov, prevažne binárnych. Nelineárne interakcie medzi
  binárkami sú efektívne XOR kombinácie, ktoré v reálnych
  phishing/legit URL nevznikajú v signifikantnej miere.
- Toto je jediný tier, kde Wilcoxon test **dokáže rozlíšiť veľkosť
  efektu** — na ostatných tieroch efekt preráža podlahu a všetky p-hodnoty
  ležia na 0.00098.

**3. Na Behavior úrovni: honest middle tier po odstránení leakerov**
- Po vyhodení 6 near-leakerov (20→14 príznakov) Behavior **nesaturuje**:
  AUC 0.991–0.997, Accuracy 0.864–0.975.
- diff (neparam − param AUC) ≈ +0.004 — malý, ale merateľný.
- **Family contrast vidno hlavne v Accuracy**: neparametrické balanced
  (Sens ≈ Spec ≈ Prec ≈ 0.97), parametrické asymetrické (NB 0.73/0.996/
  **Prec 0.995**, LDA 0.91/0.98/Prec 0.98). V bezpečnostnej aplikácii
  je tento rozdiel významný.
- **NB na Behavior je presným zrkadlom NB na Lexical.** Na Lexical
  predikuje phish pre skoro všetko (Sens 0.999, **Prec 0.618**) — veľa
  falošných alarmov. Na Behavior to otáča: takmer nikdy si netrúfne
  označiť phish (Sens 0.732, **Prec 0.995**) — keď už ho ale označí, je
  to skoro isté. Obe sú priamym dôsledkom porušenej nezávislosti;
  family-wise kalibrácia zlyháva v oboch smeroch.

**4. Na FullLite úrovni: jediný saturovaný tier — očakávaný strop**
- AUC 0.999–1.000 pre všetky modely. diff < 0.001.
- 34 poctivých príznakov už stačí na near-perfect linear separabilitu
  tohto datasetu. Toto je **empirický strop**, nie leakage — každý z
  34 príznakov je genuine page-level signál, len ich spoločná
  informačná hodnota je saturujúca.
- Full tier s 40 príznakmi (ktorý sme v predošlej verzii mali) by bol
  redundantný — to isté AUC ≈ 1.0 by sme obhajovali druhýkrát. Preto
  sme ho odstránili.

### Gradient H1 — kľúčové porozumenie

| Úroveň | diff (neparam − param AUC) | Veľkosť |
|--------|---------------------------:|---------|
| Lexical | **+0.102** | obrovský |
| Trust | +0.0019 | zanedbateľný |
| Behavior | +0.004 | malý, merateľný |
| FullLite | +0.0003 | saturované |

**Tento gradient** je dôležitejší než samotné čísla. H1 nie je len
"neparametrické je lepšie" — je to **"neparametrické je lepšie iba
tam, kde je signál slabý a nelineárny"**. Náš experiment to dokazuje.

### Čo to znamená pre aplikáciu
1. **URL-only first-line filter** → použiť SVM-RBF alebo KNN, nie LR.
   Zisk 0.10 AUC je v bezpečnostnej aplikácii rozdielom medzi
   použiteľným a nepoužiteľným filtrom.
2. **Na Behavior vrstve** ešte family contrast existuje v Accuracy a
   v Precision/Recall dvojici (neparametrické: Prec ≈ Sens ≈ 0.97 —
   konzistentne; parametrické robia asymetrické chyby — NB vysoká
   Precision a nízky Recall, LR/LDA mierne v prospech Recall), ale AUC
   rozdiel je malý. V praxi by sa tam vybral model podľa **typu chyby**
   akú môžeme tolerovať — ak nás trápia falošné alarmy (blokujeme
   legitímne stránky), chceme vysokú Precision; ak nás trápi únik
   phishingu, chceme vysoký Recall (Sensitivity). **Na FullLite** je
   voľba modelu takmer irelevantná — tu by sme zvolili LR / LDA pre
   **interpretovateľnosť** (pre audit, pre vysvetlenie používateľovi
   *prečo* bol link blokovaný).
3. Architektonicky motivuje **kaskádu**: rýchle neparametrické SVM
   nad URL → pri nízkej istote doplniť DNS/page-level príznaky a
   spustiť lacnú LR.

---

## 8. Čo by sa dalo s výsledkami robiť ďalej

### Zlepšenia modelu
1. **Kalibrácia pravdepodobností** — SVM-RBF má ad-hoc sigmoid
   kalibráciu, ale výsledné P(phishing) sú typicky zle kalibrované.
   Platt scaling alebo isotonic regression na validačnej sade by
   zlepšili rozhodovanie pri rôznych prahoch. Dôležité pre production,
   kde je threshold business rozhodnutie (recall vs. false alarm cost).
2. **Hyperparameter tuning** pre SVM (`C × σ` grid: napr. C ∈ {0.1, 1, 10},
   σ ∈ {0.01, 0.1, 1}) a KNN (`k ∈ {5, 10, 25, 50, 100}`). Fixné
   defaults sme zvolili pre férovosť porovnania, ale v produkčnom
   prostredí by oplatili ~1-2 % AUC.
3. **Stacking / ensemble** — SVM-RBF a KNN na Lexical robia **trochu
   rôzne chyby**. Vážený priemer (napr. 0.6·SVM + 0.4·KNN) by mohol
   pridať ~0.005 AUC. Alternatívne meta-learner na ich výstupoch.
4. **Gradient boostery (XGBoost, LightGBM)** — kompromis medzi RF
   (neparametrický, invariant na škálu) a SVM-RBF (presný, pomalý).
   Na Lexical by pravdepodobne dosiahli AUC ≈ 0.995 a rádovo rýchlejšiu
   inferenciu než SVM.

### Zlepšenia experimentu
5. **Repeated CV / viac opakovaní** — 10 foldov (aktuálne nastavenie)
   posúva Wilcoxon podlahu na 1/1024 ≈ 10⁻³ a už **rozlíši Trust** od
   ostatných tierov. Ďalší krok: repeated 10-fold × 5 = 50 fold-rozdielov
   → podlaha ~10⁻¹⁵, umožní jemnejšie rozlíšenie aj medzi tiermi, kde
   teraz všetky padajú na aktuálnu podlahu.
6. **Nested CV** — vnútorná slučka na tuning hyperparametrov, vonkajšia
   na odhad výkonu. Metodologicky správnejšie ako fixné parametre, ale
   10-20× drahšie výpočtovo.
7. **BCa bootstrap intervaly** pre AUC — aktuálne hlásime priemer ± SD.
   BCa bootstrap 10 000 replík dá 95 % CI, ktoré komisia ocení.

### Produkčné nasadenie
8. **Latency benchmarking** — SVM-RBF inferencia vyžaduje skalárne
   súčiny s každým support vectorom (typicky tisíce). Pri edge
   deployment (browser plugin) musíme zmerať p95 latency proti
   budgetu 50-100 ms. RF alebo XGBoost bude pravdepodobne rýchlejšie.
9. **Adversarial robustness** — phishing autori menia URL štruktúru,
   aby obchádzali detektory. Testovať model proti: homoglyph útoku
   (cyrilic `а` → latin `a`), URL encoding, subdomain padding.
   Merať pokles AUC.
10. **Data drift monitoring** — distribúcia URL sa časom mení (nové
    TLD, nové phishing kity). Po nasadení sledovať distribúcie príznakov
    a dáta-driven retrain frekvenciu.

### Pre obhajobu — slabé miesta, ktoré sami priznáme
- **Fixné hyperparametre** namiesto CV-tuning. Odôvodnenie: férovosť
  porovnania. Riziko: komisia si môže žiadať dôkaz, že SVM nebol
  "optimalizovaný na tento konkrétny dataset". Dobrá odpoveď:
  "`C = 1, σ = 0.1` sú literárny default pre štandardizované vstupy,
  tuning by mohol nespravodlivo zvýhodniť SVM oproti LDA (ktorá nemá
  hyperparametre)".

---

## 9. Cheatsheet pre otázky komisie

**Q: Prečo ste nepoužili obyčajnú logit regresiu bez penalizácie?**
A: Kvôli VIF > 1000 v Lexical klastri (`URLLength`, `NoOfLettersInURL`,
`NoOfDegitsInURL`). Neregularizovaná LR vydáva numericky nestabilné
koeficienty (oscilujú medzi foldami, niekedy menia znamienko). Ridge
stabilizuje bez toho, aby robil feature selection.

**Q: Prečo pre RF nerobíte preprocessing?**
A: Decision trees sú invariantné voči monotónnym transformáciám
(rozhodnutie `x < t` je ekvivalentné `log(x) < log(t)`) a voči
škálovaniu (tree nepoužíva Euklid ani skalárny súčin). Preprocessing
by stratil čas bez prínosu.

**Q: Prečo ste zvolili σ = 0.1, nie `kernlab::sigest` estimation?**
A: `sigest` odhaduje σ z dát per-fold, čo by pridalo ďalší zdroj
variability medzi foldami. Fixujeme σ = 0.1 pre reprodukovateľnosť a
férovosť. Pre `log1p + scale` vstupy je 0.1 typický rozumný stred
literárnych odporúčaní.

**Q: Prečo KNN bez tuning k?**
A: k = 25 je zámerne fixné. Rule-of-thumb `k ≈ √n` by dalo ~155, čo je
príliš hladké. Tuning k by pravdepodobne pohol Lexical AUC z 0.989 na
0.99x, ale **podstata H1 by ostala** — parametrické modely sú výrazne
nižšie.

**Q: Môžete tvrdiť, že SVM-RBF je "ten pravý" prvolínový filter?**
A: V rámci nami porovnaných 6 modelov áno (najvyššia CV AUC na Lexical).
V širšom zmysle by sme mali testovať XGBoost, LightGBM, hĺbkové URL
classifiers (CNN nad znakmi URL). Náš experiment dokazuje, že
**neparametrická rodina dominuje** — rozdiely medzi SVM-RBF a KNN
sú **malé** v porovnaní s rozdielom medzi nimi a LR.

**Q: Prečo sa KNN správa na Trust lepšie ako SVM (0.932 vs 0.917)?**
A: Trust = 7 binárnych príznakov → takmer diskrétny priestor
"Hamming-like". KNN s k=25 a jitterom robí vlastne multinomiálne
hlasovanie v malej Voronoi bunke. SVM-RBF s fixným σ=0.1 v tomto
priestore nemá dostatok hladkého signálu pre margin. Pre **binárne**
priestory by sa lepšie hodil SVM s Hamming alebo Jaccard jadrom.

**Q: Dataset je takmer vyvážený. Platí vaša analýza aj pre real-world,
kde phishing je malá menšina (< 1 %)?**
A: Priamo nie. Pri výraznej nevyváženosti by bola AUC menej informatívna
(triviálny baseline má AUC = 0.5 ale Accuracy = 99 %). Museli by sme
použiť Precision-Recall curve / PR-AUC a zvážiť class-weighting.
Naša analýza však odpovedá na **typovú** otázku (akú rodinu modelov
zvoliť), ktorá je invariantná voči class prior pri AUC metrike.

