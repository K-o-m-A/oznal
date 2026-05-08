# Scenár 2 a 4 — príprava na obhajobu

---

## 0. Najkratšia verzia pre úvod obhajoby

Scenár 2 testuje hypotézu, že **neparametrické modely majú najväčšiu výhodu vtedy, keď sú vstupné features slabé a signál je ukrytý v ich kombináciách**. V našom projekte je takým prípadom Lexical tier, teda modelovanie iba zo samotnej URL adresy.

Porovnali sme tri parametrické modely:

- Logistic Regression s ridge regularizáciou,
- LDA,
- Naive Bayes,

a tri neparametrické modely:

- Random Forest,
- SVM-RBF,
- KNN.

Každý model sme pustili na rovnaké štyri tiery:

- Lexical,
- Trust,
- Behavior bez near-leakerov,
- FullLite.

H1 je podporená: na Lexical tieri je rozdiel v `minSS` približne 0.30 v prospech neparametrických modelov, zatiaľ čo na FullLite prakticky mizne. To znamená, že nelineárne modely pomáhajú najviac presne tam, kde EDA očakávala: pri URL-only signáli.

Deploymentový víťaz je **SVM-RBF na Lexical tieri**, pretože pri prahu 0.5 drží vysokú Sensitivity aj Specificity a nepotrebuje threshold recalibration.

Scenár 4 potom vysvetľuje rozhodovanie Random Forest modelu pomocou jedného `rpart` surrogate stromu. Strom nie je náhrada za Random Forest, ale čitateľná vizualizácia toho, čo RF približne robí.

---

## 1. Slovník pojmov pre Scenár 2

### Parametrický model

Parametrický model má pevnejší matematický tvar. Napríklad logistická regresia hľadá vážený súčet features. Výhodou je jednoduchosť a interpretovateľnosť, nevýhodou je menšia schopnosť zachytiť zložité nelineárne vzťahy.

### Neparametrický model

Neparametrický model má flexibilnejší tvar rozhodovania. Neznamená to, že nemá žiadne parametre, ale že počet alebo tvar rozhodovania nie je pevne daný jednoduchou rovnicou. Random Forest, SVM-RBF a KNN sa vedia prispôsobiť zložitejším hraniciam medzi triedami.

### Tier

Tier je skupina features, ktoré model vidí. Tier nie je náhodné delenie stĺpcov, ale reprezentuje deployment náklady: URL string vieme mať hneď, obsah stránky je drahší.

### AUC

AUC meria, ako dobre model zoradí phishingové URL nad legitímne. Je threshold-free, teda nezávisí od konkrétneho prahu.

### Sensitivity

Sensitivity je podiel phishingových URL, ktoré model zachytil. Pri phishing detekcii je dôležitá, lebo nízka sensitivity znamená, že útoky prejdú.

### Specificity

Specificity je podiel legitímnych URL, ktoré model pustil. Nízka specificity znamená veľa false positive blokácií, čo je v korporátnom prostredí veľký problém.

### Precision

Precision hovorí, z blokovaných URL koľko bolo naozaj phishing. Ak je precision nízka, používatelia budú mať pocit, že proxy blokuje veľa normálnych stránok.

### minSS

`minSS = min(Sensitivity, Specificity)`. Je to hlavná deployment metrika H1, pretože hodnotí slabšiu stranu modelu. Model s Sensitivity 0.99 a Specificity 0.38 nie je dobrý proxy filter, aj keď chytá phishing.

### Ridge regularizácia

Ridge pridáva penalizáciu veľkých koeficientov. Pomáha pri kolinearite, keď sa features navzájom silno prekrývajú. V Scenári 2 ju používame pri logistickej regresii, lebo EDA našla VIF > 1000 v Lexical features.

### RBF kernel

RBF kernel v SVM umožňuje kresliť hladkú nelineárnu hranicu. Laicky: namiesto jednej rovnej čiary model dokáže vytvoriť zakrivenú hranicu podľa podobnosti bodov.

### Random Forest

Random Forest je veľa rozhodovacích stromov trénovaných na náhodných bootstrap vzorkách. Výsledná predikcia je hlasovanie stromov. Je presný, ale ťažko vysvetliteľný jedným diagramom.

### KNN

KNN rozhoduje podľa najbližších tréningových príkladov. Ak sa nová URL podobá na phishingové URL v tréningu, označí sa ako phishing.

### Surrogate tree

Surrogate tree je jednoduchší model, ktorý sa neučí pôvodný label, ale predikcie zložitejšieho modelu. V Scenári 4 sa `rpart` strom učí napodobniť Random Forest.

### Fidelity

Fidelity je zhoda surrogate stromu s pôvodným modelom. Ak má fidelity 0.96, strom dáva rovnakú triedu ako Random Forest v 96 % testovacích prípadov.

---

## 2. Hypotéza H1

H1:

> Rozdiel medzi parametrickými a neparametrickými modelmi je závislý od feature tieru. Najväčší rozdiel očakávame na Lexical tieri a tento rozdiel sa má zmenšovať, keď model dostane silnejšie Trust/Behavior signály.

### 2.1 Prečo toto dáva zmysel

EDA ukázala, že jednotlivé Lexical features sú samostatne slabšie než Trust/Behavior features. URL adresa často neobsahuje jeden jednoduchý signál typu „ak je toto 1, je to phishing“. Skôr ide o kombinácie:

- dlhá URL,
- veľa číslic,
- zvláštne znaky,
- veľa subdomén,
- netypická dĺžka TLD,
- čudné pokračovanie znakov.

Parametrické modely majú problém, ak je hranica medzi phishing a legitimate nelineárna. Neparametrické modely majú flexibilnejší tvar a vedia zachytiť interakcie.

### 2.2 Kritériá H1

| Kritérium | Čo musí platiť | Prečo |
|---|---|---|
| C1 | Δ minSS na Lexical >= 0.10 | rozdiel musí byť deploymentovo významný |
| C2 | gap(Lexical) > gap(FullLite) | rozdiel sa má zmenšiť, keď pridáme silnejšie features |
| C3 | ΔAUC na Lexical >= 0.02 | kontrola, že rozdiel existuje aj v poradí skóre |

C1 a C2 sú hlavné. C3 je sanity check.

### 2.3 Prečo minSS a nie iba AUC

AUC je veľmi užitočná, ale proxy potrebuje block/allow rozhodnutie pri prahu 0.5. Model môže mať dobré AUC, ale pri 0.5 môže blokovať veľa legitímnych stránok. Preto používame minSS:

- ak je Sensitivity slabá, minSS je nízke,
- ak je Specificity slabá, minSS je nízke,
- model musí byť vyvážený.

---

## 3. Feature tiery

| Tier | Počet features | Význam |
|---|---:|---|
| Lexical | 13 | čisté URL vlastnosti |
| Trust | 7 | HTTPS, title/domain dôvera, tematické flagy |
| Behavior | 14 | obsah stránky po odstránení near-leakerov |
| FullLite | 34 | Lexical + Trust + redukovaný Behavior |

### 3.1 Lexical

Lexical je hlavný deployment tier. Model vidí iba to, čo sa dá vytiahnuť z URL stringu pred načítaním stránky. Je najlacnejší a najrýchlejší, ale najťažší.

### 3.2 Trust

Trust obsahuje signály ako HTTPS a metadata o stránke. Tieto features sú často silnejšie než samotný URL string, ale nie sú úplne rovnakého typu ako čisté lexikálne count-features.

### 3.3 Behavior

Behavior obsahuje features odvodené z obsahu stránky. V Scenári 2 z neho vyhadzujeme šesť near-leakerov, aby Behavior tier nebol triviálne perfektný.

### 3.4 FullLite

FullLite je silnejší benchmark, ale bez šiestich extrémne silných Behavior features. Používame ho na overenie gradientu H1: keď signály zosilnejú, rozdiel medzi rodinami modelov by mal klesnúť.

---

## 4. Dáta, sampling a split

### 4.1 Prečo nepoužívame celý dataset

Dataset má približne 235k riadkov. Niektoré modely, najmä SVM-RBF, sú výpočtovo drahé. Trénovanie SVM na plnom datasete a vo všetkých foldoch by bolo veľmi pomalé.

Preto používame stratifikovaný subsample 30 000 riadkov:

- 15 000 phishing,
- 15 000 legitimate.

Po 80/20 splite máme približne:

- 24 000 tréningových riadkov,
- 6 000 testovacích riadkov.

### 4.2 Prečo stratifikovaný subsample

Stratifikácia zabezpečí, že v subdatasete aj splitoch ostane rovnaký pomer tried. Keďže hodnotíme Sensitivity a Specificity, nechceme, aby výsledky kolísali iba kvôli náhodnému posunu triedneho pomeru.

### 4.3 Prečo 80/20 split

80 % dáva dosť dát na trénovanie a 20 % dosť dát na nezávislý hold-out test. Pri 30k vzorke je 6k testovacích riadkov dostatočne veľa na stabilné metriky.

### 4.4 Prečo 10-fold CV

10-fold CV znamená, že tréningové dáta rozdelíme na 10 rovnakých častí. Postupne každú časť raz použijeme ako validačnú a zvyšných 9 na tréning — model teda fitujeme 10-krát a dostaneme 10 odhadov výkonu, ktoré spriemerujeme. Prečo práve 10:

- **Málo foldov (napr. 2–3):** každý fold trénuje na malej časti dát, odhad je pesimistický a kolíše.
- **Veľa foldov (extrém LOOCV, jeden riadok = jeden fold):** trénovacie množiny sa skoro nelíšia, odhady sú takmer rovnaké a výpočtovo je to neúnosné.
- **10 foldov:** každý model vidí 90 % dát (odhad nie je pesimistický), 10 čísel stačí na rozumný priemer aj smerodajnú odchýlku, a 10 fitov × 6 modelov = 60 fitov je ešte zvládnuteľné aj pre SVM-RBF a RF.

Navyše stratifikujeme — každý fold má rovnaký pomer Phishing/Legitimate, takže Sensitivity a Specificity nekolíšu kvôli triednej nerovnováhe. A všetky modely zdieľajú **rovnaké fold indexy**, takže rozdiely v metrikách porovnávame na rovnakých dátach — porovnanie je férové.

### 4.5 Prečo nie train/validation/test

V tomto scenári neladíme veľké hyperparameter gridy. Väčšinu hyperparametrov držíme fixne podľa konvenčných alebo EDA-odôvodnených hodnôt. Preto nám stačí CV na tréningu a samostatný test set na finálne hodnotenie.

---

## 5. Preprocessing

### 5.1 Recept A: log + standardizácia

Používa sa pre:

- Logistic Regression,
- LDA,
- Naive Bayes,
- SVM-RBF,
- KNN.

Kroky:

1. spojité features transformujeme cez `log1p`,
2. potom ich centrujeme a škálujeme,
3. binárne features nechávame bez zmeny.

`log1p(x)` znamená `log(1 + x)`. Je bezpečné pre nuly a znižuje vplyv extrémnych hodnôt.

### 5.2 Recept B: bez transformácie pre Random Forest

Random Forest dostáva surové dáta. Stromové modely sa rozhodujú podľa prahov a poradia hodnôt. Monotónna transformácia ako `log1p` by nezmenila podstatu splitov rovnakým spôsobom, akým pomáha lineárnym alebo distance-based modelom.

### 5.3 Prečo dva recepty nie sú nefér

Nie je cieľom dať všetkým modelom identický preprocessing za každú cenu. Cieľom je dať každej rodine primeraný preprocessing podľa jej matematických predpokladov:

- lineárne a vzdialenostné modely potrebujú škálovanie,
- stromy nie.

---

## 6. Parametrické modely

### 6.1 Logistic Regression s ridge

**Ako funguje.** Logistická regresia modeluje pravdepodobnosť phishingu ako sigmoidu z lineárnej kombinácie features: `P(phishing) = σ(β₀ + β₁x₁ + … + βₚxₚ)`. Učí sa váhy `βᵢ` maximalizáciou log-likelihood. Ridge varianta pridá pokutu `λ × Σβᵢ²`, ktorá optimalizátor núti držať váhy malé.

**Nastavenie.**

- `alpha = 0` (čistý ridge, bez L1 zložky),
- `lambda = 0.01`.

**Ako parametre menia model.**

- `alpha`: 0 = čistý ridge (drží všetky features, len ich váhy stláča); 1 = lasso (vyhadzuje features na nulu — feature selection); medzi tým je elastic net.
- `lambda`: väčšie `lambda` viac stláča koeficienty — model je stabilnejší, ale môže underfittovať. Menšie `lambda` sa blíži obyčajnej LR — pri kolinearite hrozia nestabilné koeficienty.

**Prečo ridge namiesto obyčajnej LR.** EDA ukázala v Lexical extrémnu kolinearitu (`URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL` sa pohybujú spolu, VIF > 1000). Obyčajná LR by mala (1) **nestabilné koeficienty** — váha by raz padla na `URLLength`, inokedy na `NoOfLettersInURL`, znamienka by sa medzi foldami menili; (2) **nedôveryhodné porovnanie** — nevedeli by sme, či je rozdiel oproti LDA/RF skutočný, alebo iba kolísanie LR. Ridge rozdelí váhu medzi korelované features rovnomerne. `lambda = 0.01` je minimálna stabilizácia, nie performance trik.

### 6.2 LDA

**Ako funguje.** Linear Discriminant Analysis predpokladá, že features v každej triede majú približne normálne rozdelenie a triedy zdieľajú spoločnú kovariančnú maticu. Z týchto predpokladov odvodí lineárnu rozhodovaciu hranicu medzi triedami pomocou Bayesovho pravidla.

**Nastavenie.** Bez explicitných hyperparametrov — `caret::train(method = "lda")` len odhadne priemery tried a spoločnú kovariančnú maticu z dát.

**Ako parametre menia model.** LDA má fixnú formu — meniť možno iba preprocessing (či transformovať features, či štandardizovať). Po `log1p` a štandardizácii sú features bližšie k normálnemu rozdeleniu, čo sedí LDA predpokladom.

**Prečo nie QDA.** QDA by mala samostatnú kovariančnú maticu pre každú triedu (kvadratická hranica). Pri korelovaných features je citlivejšia a menej stabilná. LDA je jednoduchší a robustnejší baseline.

### 6.3 Naive Bayes

**Ako funguje.** NB aplikuje Bayesovu vetu s **predpokladom podmienenej nezávislosti** features dané triedou: `P(trieda | x) ∝ P(trieda) × Π P(xᵢ | trieda)`. Každú feature modeluje samostatne, jej príspevky sa nasobia. S `usekernel = TRUE` modeluje `P(xᵢ | trieda)` neparametrickým kernel density estimátorom; bez neho predpokladá Gaussian.

**Nastavenie.**

- `usekernel = TRUE`,
- `fL = 1` (Laplace smoothing),
- `adjust = 1`.

**Ako parametre menia model.**

- `usekernel`: TRUE = flexibilnejší (KDE pre každú feature, nepredpokladá Gaussian); FALSE = čistý Gaussian NB, citlivejší na nesplnenú normalitu.
- `fL` (Laplace): 0 = bez smoothingu, model padne na nulu pri nepozorovaných kombináciách; vyššie hodnoty silnejšie vyhladzujú.
- `adjust`: násobok šírky kernelu pri `usekernel = TRUE`. Vyššie = hladšie odhady hustoty, nižšie = ostrejšie ale šumnejšie.

**Prečo ho vôbec mať.** EDA ukázala, že najmä Lexical features nezávislé nie sú, takže NB nečakáme ako víťaza. Je to baseline ukazujúci, **akú cenu má zlomený predpoklad nezávislosti** — keď NB výrazne zaostane, je to dôkaz, že interakcie medzi features sú dôležité.

---

## 7. Neparametrické modely

### 7.1 Random Forest

**Ako funguje.** RF je ensemble rozhodovacích stromov. Každý strom sa učí z **bootstrap vzorky** dát (sampling s nahradením) a pri každom splite vidí iba náhodnú podmnožinu `mtry` features. Predikcia: každý strom hlasuje, RF vráti priemer pravdepodobností. Náhodnosť (bootstrap + random feature subset) zabezpečí, že stromy sú dekorelovené, takže priemer má nižšiu varianciu než jeden strom.

**Nastavenie.**

- `ntree = 300`,
- `mtry = floor(sqrt(p))`.

**Ako parametre menia model.**

- `ntree`: viac stromov = stabilnejšie predikcie, ale dlhší tréning. Po istej hranici (~stovky) zlepšenie saturuje.
- `mtry`: menšie = stromy vidia menej features → väčšia diverzita, ale jednotlivé stromy sú slabšie. Väčšie = stromy sú silnejšie, ale podobnejšie (vyššia korelácia → menšia výhoda priemerovania). `sqrt(p)` je klasická heuristika pre klasifikáciu.
- Hĺbka stromov (default neorezáva): hlbšie = väčší fit na tréning; v RF sa overfit kompenzuje cez ensemble, preto sa stromy bežne pestujú do plnej hĺbky.

**Prečo bez preprocessingu.** RF rozhoduje podľa prahov na jednotlivých features (`x < threshold`), takže monotónne transformácie (log, štandardizácia) prahy nemenia. RF nechávame na surových dátach (Recept B).

### 7.2 SVM-RBF

**Ako funguje.** SVM hľadá rozhodovaciu hranicu, ktorá maximalizuje **margin** (vzdialenosť medzi hranicou a najbližšími bodmi tried). RBF (Gaussovský) kernel `K(x, x') = exp(-σ‖x − x'‖²)` meria podobnosť celých vektorov; hranica je tvarovaná podľa hustoty support vektorov v okolí. Výsledok je hladká nelineárna hranica v pôvodnom priestore.

**Nastavenie.**

- `C = 1`,
- `sigma = 0.1`.

**Ako parametre menia model.**

- `C` (soft-margin penalizácia): malé `C` = mäkký margin, model toleruje viac chýb na tréningu, hranica je hladšia (vyšší bias, nižšia variancia). Veľké `C` = tvrdý margin, model sa snaží klasifikovať tréning bez chyby (riziko overfitu).
- `sigma` (šírka RBF kernelu): malé `sigma` = široký kernel, hladká globálna hranica (môže underfittovať). Veľké `sigma` = úzky kernel, hranica sa silno prispôsobí lokálnym bodom (riziko overfitu).

**Prečo RBF a nie lineárne SVM.** Lineárne SVM by hľadalo rovinu v priestore features — správa sa podobne ako LR. Na Lexical to nestačí: (1) **phishing signál je interakcia, nie suma** — URL je podozrivá až vtedy, keď je *zároveň* dlhá, má veľa číslic, špeciálnych znakov a subdomén; lineárny model interakcie nezachytí, RBF cez podobnosť celých vektorov áno. (2) **Korelované features** — pri VIF > 1000 by lineárne SVM trpelo nestabilitou váh ako LR; RBF váhy jednotlivým features nepriraďuje. Empiricky: na Lexical má SVM-RBF výrazne vyššiu Sensitivity aj Specificity než LR-Ridge a LDA. Na FullLite, kde Behavior features dávajú silný lineárny signál, sa rozdiel zmenšuje. `C = 1`, `sigma = 0.1` sú rozumné defaulty pre štandardizované features.

### 7.3 KNN

**Ako funguje.** KNN nemá tréningovú fázu v klasickom zmysle — uloží si všetky tréningové body. Pri novej URL spočíta euklidovskú vzdialenosť ku všetkým tréningovým bodom, vyberie `k` najbližších a hlasuje (alebo priemeruje pravdepodobnosti).

**Nastavenie.**

- `k = 25`.

**Ako parametre menia model.**

- `k`: malé `k` (napr. 1–3) = veľmi lokálne rozhodnutie, citlivé na šum a outliery (vysoká variancia). Veľké `k` = vyhladenie lokálnych rozdielov, hranica sa blíži globálnemu majoritnému hlasovaniu (vysoký bias). 25 je rozumný kompromis pri 24k tréningových bodoch.
- Metrika vzdialenosti: euklidovská vyžaduje **štandardizáciu**, inak feature s väčšou škálou dominuje.
- Jitter (špeciálne pre Trust tier): Trust má iba 7 prevažne binárnych features → veľa identických riadkov vytvára ties. Malý Gaussian jitter rozbije zhody bez zmeny významu dát.

**Nevýhoda pri deploye.** KNN je drahý pri inferencii — každá nová URL si vyžaduje výpočet vzdialeností ku všetkým tréningovým bodom. Pre produkčný proxy je to horšie než model, ktorý po natrénovaní rozhoduje rýchlejšie (LR, LDA, RF, SVM).

---

## 8. Výsledky Scenára 2

### 8.1 Hlavný H1 verdikt

H1 je podporená:

- C1 drží: Lexical minSS gap je približne 0.30.
- C2 drží: gap sa na FullLite zrúti takmer na nulu.
- C3 drží: Lexical AUC gap je približne 0.064.

Konkrétne:

- SVM-RBF na Lexical má minSS približne 0.983.
- Najlepší parametrický champion na Lexical má minSS približne 0.688.
- Rozdiel je približne 0.295, čo je ďaleko nad prahom 0.10.

### 8.2 Interpretácia podľa tierov

#### Lexical

Najväčší rozdiel medzi rodinami. To je presne očakávané: URL-only features sú jednotlivo slabšie a nelineárne interakcie sú dôležité.

#### Trust

Rozdiel je menší. Trust má málo features a veľa binárnych flagov. Nie je tam až taký bohatý priestor pre nelineárne modely.

#### Behavior

Po odstránení near-leakerov je Behavior stredný prípad. Stále obsahuje stránkové signály, ale nie také, ktoré samostatne vyriešia úlohu.

#### FullLite

Všetky modely majú veľmi silný signál. Parametrické aj neparametrické modely saturujú, preto rozdiel mizne. To podporuje gradient H1.

### 8.3 Per-model komentár na Lexical tieri

#### LR-Ridge

Sensitivity je približne 0.921 a Specificity približne 0.716. Model chytí dosť phishingu, ale blokuje príliš veľa legitímnych URL. Ako proxy filter by bol problematický.

#### LDA

LDA má dobré AUC, ale zlý operating point pri 0.5 prahu. Sensitivity je vysoká, Specificity nízka. To znamená, že model vie prípady zoradiť, ale pravdepodobnosti nie sú dobre kalibrované na rozhodnutie pri 0.5.

#### Naive Bayes

Naive Bayes na Lexical takmer všetko tlačí smerom k phishingu. Sensitivity je skoro 1, ale Specificity je veľmi nízka. To je typický dôsledok porušeného predpokladu nezávislosti.

#### Random Forest

Random Forest má dobré AUC, ale pri threshold 0.5 má slabšiu Specificity. Je to skôr kalibračný problém než problém poradia. Threshold tuning by mu pomohol, ale H1 porovnáva všetky modely pri rovnakom prahu 0.5.

#### SVM-RBF

SVM-RBF je najlepší deployment kandidát. Má vysokú Sensitivity aj Specificity, takže pri 0.5 prahu funguje symetricky a nepotrebuje ďalšie nastavovanie threshold-u.

#### KNN

KNN je kvalitný na Lexical, ale prehráva so SVM z praktického hľadiska. Inferencia vyžaduje porovnanie s mnohými tréningovými vzorkami.

### 8.4 Prečo víťazí SVM-RBF

SVM-RBF spája dve výhody:

1. vie zachytiť nelineárne hranice,
2. po natrénovaní je praktickejší než KNN pri inferencii.

Random Forest je tiež silný, ale pri 0.5 prahu nie je tak vyvážený. LDA a LR sú jednoduchšie, ale na Lexical nedržia Specificity.

---

## 9. Scenár 4: vizualizácia rozhodovacej logiky

### 9.1 Čo požadoval Scenár 4

Scenár 4 žiada vizualizovať rozhodovanie modelu pomocou heatmap alebo stromov a porovnať vizualizáciu s podkladovým modelom. My sme zvolili stromový prístup.

### 9.2 Prečo nie heatmap

Heatmapa korelácií alebo klastrovania ukazuje vzťahy medzi features, ale neukazuje správanie konkrétneho modelu. Scenár 4 chceme interpretovať ako porovnanie vizualizácie s modelom. Preto surrogate strom dáva väčší zmysel: priamo sa učí napodobniť Random Forest.

### 9.3 Prečo Random Forest ako teacher

Random Forest je presný, ale neprehľadný. Má 300 stromov, ktoré hlasujú. Komisia alebo používateľ nevie jednoducho vidieť „pravidlo“, podľa ktorého RF rozhoduje. Surrogate strom je zjednodušený študent, ktorý sa učí predikcie RF.

### 9.4 Ako surrogate funguje

Normálny model sa učí:

> features → skutočný label.

Surrogate strom sa učí:

> features → predikcia Random Forest.

Potom meriame fidelity, teda koľko testovacích prípadov má strom rovnakú odpoveď ako RF.

### 9.5 Prečo Lexical a FullLite

Používame dva tiery:

- Lexical, lebo tam je Random Forest zaujímavý a nelineárny,
- FullLite, lebo tam očakávame vysokú fidelity ako sanity check.

Trust je príliš malý a binárny, Behavior je medzi týmito prípadmi a neprináša nový typ pozorovania.

### 9.6 Tuning surrogate stromu

Tunujeme:

- `maxdepth` od 3 do 7,
- `cp` ako pruning parameter,
- `minbucket` ako minimálna veľkosť listu.

Hľadáme vysokú fidelity, ale zároveň čitateľnosť. Hlboký strom môže lepšie kopírovať RF, ale pri ústnom vysvetľovaní na projektore je nepoužiteľný.

### 9.7 Prečo cap <= 15 listov

Strom s 37 listami môže mať vyššiu fidelity, ale človek ho nevie rýchlo pochopiť. Obhajobová vizualizácia má byť vysvetľujúca, nie iba numericky najlepšia. Preto vyberáme najlepší strom s najviac 15 listami.

### 9.8 Výsledok pre Lexical

Lexical surrogate má root split na `NoOfOtherSpecialCharsInURL < 3`. To znamená, že počet špeciálnych znakov je prvý veľký signál, ktorým sa dá približiť rozhodovanie RF.

Ďalšie dôležité features:

- `NoOfDegitsInURL`,
- `NoOfSubDomain`,
- `TLDLength`,
- `CharContinuationRate`,
- `URLLength`,
- `NoOfLettersInURL`.

Tree AUC je nižšie než RF AUC, takže strom nie je náhrada RF. Je to skôr okno do jeho logiky.

### 9.9 Výsledok pre FullLite

FullLite surrogate má root `HasSocialNet = 1`. V horných vrstvách dominujú Trust binárky:

- `HasCopyrightInfo`,
- `HasDescription`,
- `IsHTTPS`,
- `HasSubmitButton`.

To dáva zmysel: keď má model silnejšie Trust/Behavior signály, nemusí sa spoliehať iba na zložité URL counts.

### 9.10 Variable importance cross-check

Používame `randomForest::varImpPlot`, aby sme overili, či root split surrogate stromu je zároveň feature, ktorý RF považuje za dôležitý. Ak áno, strom nie je iba nezávislý jednoduchý model, ale naozaj zachytáva dôležitú časť RF logiky.

---

## 10. Obmedzenia a férové priznania

### 10.1 SVM hyperparametre nie sú rozsiahlo tunované

Používame fixné `C = 1`, `sigma = 0.1`. Rozsiahly grid search by bol drahý a zmenil by dôraz práce. Cieľom Scenára 2 je porovnať rodiny modelov, nie maximalizovať leaderboard.

### 10.2 RF threshold by sa dal kalibrovať

Random Forest by pravdepodobne vedel zlepšiť Specificity posunom threshold-u. Ale H1 porovnáva modely pri rovnakom 0.5 prahu, lebo proxy deployment má jednotný operačný bod.

### 10.3 Surrogate strom nie je plná interpretácia RF

Jeden strom nevie zachytiť všetky interakcie 300 stromov. Na Lexical vidno rozdiel medzi Tree AUC a RF AUC. Preto hovoríme, že surrogate je vizualizácia, nie náhrada.

### 10.4 Subsample môže mať variabilitu

Používame fixný seed a stratifikáciu. Výsledky sú reprodukovateľné v rámci notebooku. Pri inom subsample by čísla mohli mierne kolísať, ale veľkosť Lexical gapu je dosť veľká, aby hlavný záver nebol krehký.

---

## 11. Čo by sa stalo, keby...

### Keby sme použili celý dataset

Výsledky by mohli byť ešte stabilnejšie, ale SVM-RBF by bol výrazne pomalší. Pre porovnanie šiestich modelov na štyroch tieroch je 30k stratifikovaný subsample praktický kompromis.

### Keby sme nechali near-leakery

Full tier by bol takmer perfektne separovateľný a H1 gradient by sa nedal čítať. Modely by boli všetky „príliš dobré“.

### Keby sme tunovali threshold

Niektoré modely, najmä Random Forest, by sa zlepšili. Ale porovnanie by už nebolo jednotné pri prahu 0.5. Scenár 2 chce ukázať, ktorý model funguje priamo v default operačnom bode.

### Keby sme použili XGBoost

XGBoost by bol ďalší silný neparametrický/boosting model, ale nebol potrebný pre test H1. Zadanie a dizajn porovnávajú reprezentatívne rodiny; RF, SVM-RBF a KNN pokrývajú tri rôzne typy neparametrického správania.

---

## 12. Časté otázky komisie

### Prečo hodnotíte championov podľa minSS a nie podľa AUC?

Lebo proxy musí reálne rozhodnúť pri prahu 0.5. AUC je dobré na ranking, ale nezaručuje, že threshold 0.5 bude použiteľný. minSS penalizuje model, ktorý zlyhá na jednej strane.

### Prečo je LDA s dobrým AUC stále problematická?

LDA môže dobre zoradiť prípady, ale zle kalibrovať pravdepodobnosti. Pri prahu 0.5 potom blokuje príliš veľa legitímnych URL. V deployment-e je threshold správanie dôležité.

### Prečo Scenár 4 používa RF a nie SVM, keď SVM vyhráva?

Scenár 4 je o vizualizácii rozhodovacej logiky. RF je stromový ensemble a dá sa prirodzene aproximovať jedným surrogate stromom. SVM-RBF má rozhodovaciu hranicu v kernel priestore, ktorú je ťažšie vysvetliť jedným bežným stromovým diagramom.

### Prečo surrogate strom trénujete na predikciách RF, nie na labeloch?

Lebo cieľom nie je vytvoriť nový model, ale vysvetliť RF. Ak by sme strom trénovali na labeloch, bol by to samostatný CART model, nie vizualizácia RF správania.

### Prečo neukazujete všetky tiery v Scenári 4?

Lexical a FullLite reprezentujú dva dôležité extrémy: slabší URL-only signál a silný kombinovaný signál. Trust je príliš jednoduchý, Behavior nepridáva zásadne nový príbeh.

---

## 13. Finálny záver Scenára 2 a 4

Scenár 2 potvrdzuje H1: neparametrické modely majú najväčšiu výhodu na Lexical URL-only úlohe a táto výhoda mizne na silnejšom FullLite tieri. To presne zodpovedá EDA: slabšie individuálne URL features vyžadujú model, ktorý vie zachytiť ich kombinácie. Najlepší praktický kandidát je SVM-RBF na Lexical tieri.

Scenár 4 dopĺňa interpretovateľnosť: Random Forest je presný, ale nepriehľadný, preto ho aproximujeme jedným surrogate stromom. Strom ukazuje hlavné rozhodovacie vzory RF, ale zároveň priznávame, že nedokáže nahradiť celý 300-stromový ensemble.

---

## 14. Model-by-model hlboká obhajoba

Táto časť je určená na situáciu, keď sa komisia začne pýtať na konkrétne modely a ich nastavenia.

### 14.1 Logistic Regression Ridge — ako ju vysvetliť laikovi

Logistická regresia sa snaží každej feature priradiť váhu. Pozitívna váha tlačí predikciu smerom k phishingu, negatívna smerom k legitimate. Ak sú však features silno prepojené, model nevie stabilne rozhodnúť, komu priradiť zásluhu.

Príklad:

- `URLLength` je vysoké,
- `NoOfLettersInURL` je vysoké,
- `NoOfDegitsInURL` je vysoké.

Tieto veci sa prirodzene pohybujú spolu. Obyčajná LR môže raz dať veľkú váhu `URLLength`, inokedy `NoOfLettersInURL`. Ridge povie: „váhy môžu existovať, ale nesmú vybuchnúť“. Tým stabilizuje model.

Obhajobová formulácia:

> Ridge sme nepoužili ako trik na zvýšenie výkonu, ale ako minimálnu numerickú stabilizáciu po EDA zistení extrémnej kolinearity.

### 14.2 LDA — prečo je zaujímavá, aj keď nevyhrá

LDA je dobrá ako klasický parametrický baseline. Predstavuje si, že každá trieda má oblak bodov a hľadá hranicu, ktorá tieto oblaky rozdelí.

Prečo na Lexical zlyháva v 0.5 bode:

- vie relatívne dobre zoradiť prípady,
- ale predpoklad spoločnej kovariancie a približne normálnych rozdelení nie je úplne splnený,
- preto posterior pri 0.5 nie je deploymentovo dobrý.

To vysvetľuje rozdiel medzi AUC a Specificity.

### 14.3 Naive Bayes — prečo ho vôbec mať

Naive Bayes je zámerne jednoduchý model. Predpokladá, že features sú nezávislé po zohľadnení triedy. V našom Lexical poole to zjavne nie je pravda, pretože dĺžkové features spolu súvisia.

Prečo ho napriek tomu používame:

- je to štandardný parametrický baseline,
- ukazuje, čo sa stane, keď je predpoklad nezávislosti zlomený,
- poskytuje kontrast voči flexibilnejším modelom.

Keď NB na Lexical volá phishing takmer všade, nie je to náhodný bug. Je to interpretovateľný dôsledok toho, že podobný signál sa mu započíta viackrát.

### 14.4 Random Forest — presný, ale kalibračný problém

RF vytvorí veľa stromov a hlasuje. Je silný na nelinearity a interakcie. Na Lexical má dobré AUC, ale pri prahu 0.5 nie je taký vyvážený ako SVM.

Ako to vysvetliť:

> RF vie často správne zoradiť phishing nad legitimate, ale jeho hlasovacie pravdepodobnosti nemusia byť ideálne kalibrované tak, aby 0.5 bol najlepší deployment prah.

Prečo neladíme threshold:

> Lebo H1 porovnáva modelové rodiny pri rovnakom default prahu. Keby sme každému modelu ladili threshold, testovali by sme aj kalibráciu prahu, nielen modelovú rodinu.

### 14.5 SVM-RBF — prečo je deployment víťaz

SVM-RBF je vhodný pre Lexical, lebo URL phishing signál môže byť nelineárny. Napríklad samotná dĺžka URL nemusí stačiť, ale dlhá URL spolu s veľa číslicami, špeciálnymi znakmi a subdoménami môže byť veľmi podozrivá.

RBF kernel vie takéto kombinácie zachytiť bez toho, aby sme ich ručne vytvárali.

Silná obhajobová veta:

> SVM-RBF vyhráva nie preto, že má iba najlepšie AUC, ale preto, že pri rovnakom 0.5 prahu drží naraz vysokú Sensitivity aj Specificity.

### 14.6 KNN — dobrý benchmark, horší deployment

KNN je intuitívny: nájdi podobné staré URL a hlasuj podľa nich. Na Lexical má dobrý výsledok, lebo podobnosť URL dáva zmysel. Ale pri každom novom kliknutí musí porovnávať s tréningovými dátami.

Pre proxy to znamená:

- vyššia latencia,
- vyššie nároky na pamäť,
- horšie škálovanie.

Preto KNN môže byť kvalitný model, ale nie najlepší praktický kandidát.

### 14.7 Rýchle vysvetlenie modelov a vplyv parametrov

Toto je časť, ktorú sa oplatí vedieť povedať ústne. Netreba zachádzať do matematických detailov; stačí vysvetliť princíp a čo by sa stalo, keby sme parameter zvýšili alebo znížili.

| Model | Ako funguje stručne | Parametre v našom riešení | Keď parameter zmeníme |
|---|---|---|---|
| **Logistic Regression Ridge** | Učí váhy features a cez sigmoid z nich robí pravdepodobnosť phishingu. Ridge drží váhy menšie a stabilnejšie. | `alpha = 0`, `lambda = 0.01` | Väčšie `lambda` viac stláča koeficienty, model je stabilnejší, ale môže podfitovať. Menšie `lambda` sa blíži obyčajnej LR, pri kolinearite hrozia nestabilné koeficienty. `alpha = 0` je čistý ridge; vyššie `alpha` by išlo smerom k lasso a začalo by vyhadzovať features. |
| **LDA** | Predstaví si každú triedu ako oblak bodov a hľadá lineárnu hranicu medzi triedami. | V `caret` bez tunovaného gridu | Nemáme hlavný tuning parameter ako pri SVM. Výsledok najviac ovplyvňuje preprocessing a platnosť predpokladu normálnych tried so spoločnou kovarianciou. Pri inom nastavení prior pravdepodobností by sa hranica posunula k triede, ktorú považujeme za častejšiu. |
| **Naive Bayes** | Pre každý feature odhaduje, ako pravdepodobný je pri phishing/legit triede, a tieto dôkazy násobí. „Naive“ znamená, že predpokladá nezávislosť features. | `usekernel = TRUE`, `fL = 1`, `adjust = 1` | `usekernel = TRUE` robí hladší negaussovský odhad rozdelenia; `FALSE` by bolo jednoduchšie, ale menej flexibilné. Väčšie `fL` viac vyhladzuje nulové/riedke kombinácie, menšie `fL` môže byť ostrejšie a citlivejšie. Väčšie `adjust` viac vyhladí kernel hustoty, menšie ju spraví zubatejšou. |
| **Random Forest** | Trénuje veľa rozhodovacích stromov a nechá ich hlasovať. Každý strom vidí trochu iné dáta a pri splite inú podmnožinu features. | `ntree = 300`, `mtry = sqrt(p)` | Väčšie `ntree` stabilizuje hlasovanie, ale predlžuje tréning; po istom bode už prínos saturuje. Menšie `ntree` je rýchlejšie, ale viac kolíše. Väčšie `mtry` dáva stromom viac features na výber, môžu byť silnejšie, ale podobnejšie. Menšie `mtry` zvyšuje rozmanitosť stromov, ale jednotlivé stromy môžu byť slabšie. |
| **SVM-RBF** | Hľadá hranicu medzi triedami s čo najväčším marginom. RBF kernel umožní zakrivenú nelineárnu hranicu. | `C = 1`, `sigma = 0.1` | Väčšie `C` viac trestá chyby na tréningu, hranica sa snaží viac prispôsobiť dátam a môže overfitovať. Menšie `C` dovolí viac chýb a je hladšie/robustnejšie, ale môže podfitovať. Väčšie `sigma` robí RBF lokálnejší a hranica môže byť zložitejšia. Menšie `sigma` robí hranicu hladšiu a globálnejšiu. |
| **KNN** | Pri novej URL nájde `k` najbližších tréningových príkladov a nechá ich hlasovať. | `k = 25`, jitter `sd = 1e-3` pri ties | Menšie `k` reaguje na lokálne detaily, ale je citlivé na šum. Väčšie `k` je stabilnejšie, ale môže zahladiť reálne lokálne rozdiely. Väčší jitter by mohol meniť význam binárnych features, menší jitter nemusí rozbiť ties. |
| **Surrogate `rpart` strom** | Jeden rozhodovací strom sa učí napodobniť predikcie Random Forest, nie priamo label. | `maxdepth`, `cp`, `minbucket`, cap `<= 15` listov | Väčší `maxdepth` vie lepšie kopírovať RF, ale strom je menej čitateľný. Väčšie `cp` viac prerezáva strom a zjednodušuje ho. Menší `cp` dovolí viac splitov. Väčšie `minbucket` núti väčšie listy a stabilnejšie pravidlá; menšie môže zachytiť detaily, ale aj šum. |

Krátka ústna verzia:

> Parametrické modely sú jednoduchšie a majú pevnejší tvar hranice. Neparametrické modely sú flexibilnejšie: RF skladá veľa stromov, SVM-RBF kreslí hladkú nelineárnu hranicu a KNN hlasuje podľa podobných príkladov. Parametre väčšinou riadia kompromis medzi jednoduchosťou a prispôsobením tréningovým dátam.

---

## 15. Tier-by-tier hlboká interpretácia

### 15.1 Lexical ako hlavný test schopnosti modelu

Lexical je najzaujímavejší, lebo:

- je najlacnejší,
- má slabšie samostatné features,
- obsahuje kolinearitu,
- potrebuje interakcie.

Ak by neparametrické modely mali byť niekde lepšie, je to práve tu. Výsledok to potvrdzuje.

### 15.2 Trust ako jednoduchý binárny priestor

Trust obsahuje málo features a veľa z nich sú binárne. Pri takom priestore nemá neparametrický model taký veľký priestor na objavovanie komplexných hraníc. Preto rozdiel modelových rodín nie je dramatický.

### 15.3 Behavior bez near-leakerov

Behavior je kompromis. Stále je obsahový a silnejší než Lexical, ale po odstránení near-leakerov už nie je triviálny. Je dobrý na overenie, či H1 nie je iba artefakt Lexical.

### 15.4 FullLite ako koncový bod gradientu

FullLite má dosť silný signál, aby aj parametrické modely fungovali veľmi dobre. Keď rozdiel medzi rodinami zmizne, nie je to problém, ale potvrdenie H1 gradientu:

> Flexibilita modelu je najdôležitejšia, keď je feature tier slabší.

---

## 16. Preprocessing obhajoba do hĺbky

### 16.1 Prečo log transformácia iba na spojité

Binárne features majú hodnoty 0/1. Log transformácia by ich významovo zmenila zbytočne. Spojité count-features majú dlhé chvosty, preto práve tie transformujeme.

### 16.2 Prečo `pmax(x, 0)`

`log1p` očakáva nezáporné hodnoty. Count-features by záporné byť nemali, ale `pmax(x, 0)` je defenzívna ochrana. Nezakrýva reálny problém, iba zabraňuje matematicky nemožnému logu zo zápornej hodnoty.

### 16.3 Prečo štandardizácia

SVM a KNN pracujú so vzdialenosťou alebo podobnosťou. Ak by jeden feature mal rozsah 0 až 1000 a iný 0 až 1, veľký feature by dominoval. Štandardizácia dáva features porovnateľnú mierku.

### 16.4 Prečo `preProcess` fitujeme na train

Parametre centrovania a škálovania sa učia z tréningových dát. Test dáta sa iba transformujú rovnakým objektom. To zabraňuje tomu, aby test set ovplyvnil preprocessing.

### 16.5 Prečo RF nechávame bez preprocessingu

Strom sa pýta otázky typu „je feature menší ako prah?“. Ak hodnoty monotónne zlogujeme, poradie bodov sa nezmení. Preto nie je potrebné stromom meniť mierku.

---

## 17. Ako čítať tabuľky výsledkov

### 17.1 CV AUC vs Test AUC

CV AUC je priemerný odhad z foldov na tréningovej časti. Test AUC je finálny hold-out. Ak sú podobné, výsledok je dôveryhodnejší.

### 17.2 Train AUC vs Test AUC

Train AUC môže byť vysoké najmä pri flexibilných modeloch. Samo osebe to nie je problém. Problém by bol, keby CV AUC bolo vysoké a Test AUC výrazne nižšie.

### 17.3 Accuracy

Accuracy je pri vyváženom datasete použiteľná, ale nestačí. Model môže mať dobrú accuracy a pritom mať zlú Specificity alebo Sensitivity.

### 17.4 F1

F1 kombinuje precision a recall, ale nezobrazuje Specificity. Pre proxy potrebujeme vidieť aj false positive stranu, preto F1 nie je hlavná metrika.

### 17.5 Precision

Precision je dôležitá pre dôveru používateľov. Ak proxy blokuje veľa legitímnych stránok, používatelia sa budú snažiť obchádzať ochranu.

### 17.6 Sensitivity/Specificity

Toto je najlepšie čitateľná dvojica pre obhajobu:

- Sensitivity = koľko útokov chytíme.
- Specificity = koľko dobrých stránok pustíme.

---

## 18. Detailné obhajobové formulácie pre H1

### 18.1 Hlavná veta

> H1 je podporená, pretože na najlacnejšom Lexical tieri je rozdiel medzi najlepším neparametrickým a parametrickým modelom veľký, ale na FullLite tieri mizne.

### 18.2 Prečo je to dôležité

> Znamená to, že flexibilita modelu má najväčšiu hodnotu tam, kde sú features slabšie a kombinované. Keď pridáme silné Trust/Behavior signály, aj jednoduchšie modely vedia úlohu vyriešiť.

### 18.3 Prečo to nie je iba náhoda jedného modelu

> Porovnávali sme tri modely v každej rodine, na rovnakých splitoch a rovnakých tieroch. Výsledok nie je „SVM náhodou vyhral“, ale tierový gradient celej rodiny.

### 18.4 Prečo sa zameriavame na Lexical

> Lexical je deploymentovo najlacnejší a teoreticky najťažší. Ak chceme rýchly proxy filter, toto je najdôležitejší prípad.

---

## 19. Scenár 4 — detailná obhajoba rozhodnutia

### 19.1 Prečo surrogate namiesto priameho RF vysvetlenia

Random Forest nemá jeden rozhodovací strom. Má 300 stromov. Môžeme pozerať variable importance, ale tá neukáže konkrétne pravidlá. Surrogate strom dá jeden približný diagram.

### 19.2 Čo surrogate zachytí

Zachytí najväčšie rozhodovacie vzory RF. Napríklad ak RF často používa špeciálne znaky v URL, surrogate ich môže dať blízko rootu.

### 19.3 Čo surrogate nezachytí

Nezachytí:

- hlasovanie 300 stromov,
- hlboké viacfeature interakcie,
- bagging variabilitu,
- všetky malé lokálne korekcie RF.

Preto ho neprezentujeme ako náhradu.

### 19.4 Prečo fidelity nestačí

Fidelity hovorí, ako často sa strom zhodne s RF. Ale treba ju rozdeliť:

- Sens vs RF,
- Spec vs RF.

Ak by strom kopíroval iba phishing triedu a legit triedu nie, overall fidelity by mohla vyzerať lepšie, než v skutočnosti je. Preto uvádzame per-class decomposition.

### 19.5 Prečo varImpPlot ako cross-check

Ak root split surrogate stromu súhlasí s top RF importance feature, máme väčšiu dôveru, že strom naozaj odráža RF logiku. Ak by nesúhlasil, strom by mohol byť len náhodná zjednodušená aproximácia.

---

## 20. Možné námietky a najlepšie odpovede

### Námietka: „Prečo ste neladili viac hyperparametrov?“

Odpoveď:

> Cieľom nebol leaderboard tuning, ale férové porovnanie rodín modelov. Použili sme konvenčné nastavenia a rovnaký experimentálny setup. Rozsiahly tuning by pridal ďalšiu premennú a znížil čitateľnosť H1.

### Námietka: „SVM vyhral, ale nie je interpretovateľný.“

Odpoveď:

> Súhlasíme. Preto Scenár 4 rieši interpretovateľnosť na Random Forest cez surrogate strom. Deploymentový víťaz a vysvetľovací model nemusia byť ten istý objekt.

### Námietka: „Prečo nie threshold tuning?“

Odpoveď:

> Pretože H1 je definovaná pri default 0.5 prahu. Threshold tuning by bol ďalší optimalizačný krok, ktorý by niektoré modely zvýhodnil. V praxi by bol možný ako follow-up.

### Námietka: „Nie je 30k málo z 235k?“

Odpoveď:

> Je to stratifikovaný subsample s 15k príkladmi na triedu a 6k hold-out testom. Pre AUC a Sens/Spec je to veľká vzorka. Použili sme ho kvôli časovej náročnosti SVM-RBF.

### Námietka: „Prečo porovnávať Naive Bayes, keď viete, že predpoklad neplatí?“

Odpoveď:

> Práve preto. Je to reprezentant jednoduchého parametrického modelu a ukazuje, čo sa stane, keď nezávislostný predpoklad neplatí.

### Námietka: „Surrogate strom má nižšiu AUC než RF, načo je dobrý?“

Odpoveď:

> Nie je určený ako deployable replacement. Je to vizualizačný nástroj. Hodnotíme, ako dobre vysvetľuje RF cez fidelity, nie či prekoná RF na pravom labeli.

---

## 21. Tabuľka „ak sa opýtajú na parameter“

| Parameter | Krátka odpoveď |
|---|---|
| Ridge lambda 0.01 | malá stabilizácia pre kolinearitu, nie agresívny tuning |
| SVM C = 1 | štandardný kompromis medzi margin a chybami |
| SVM sigma = 0.1 | rozumné pre štandardizované features |
| RF ntree = 300 | stabilné hlasovanie bez zbytočného času navyše |
| RF mtry = sqrt(p) | klasická classification heuristika |
| KNN k = 25 | kompromis medzi šumom a prílišným vyhladením |
| jitter 1e-3 | rozbije ties v binárnom Trust priestore bez zmeny významu |
| maxdepth 3:7 | rozsah od čitateľného po dostatočne flexibilný surrogate |
| max 15 listov | cap pre čitateľnosť na projektore / pri ústnom vysvetlení |

---

## 22. Jednovetové pointy na zapamätanie

- **H1 nie je len o AUC, ale o použiteľnom 0.5 rozhodnutí.**
- **Najväčší rozdiel rodín je na Lexical, kde je signál najťažší.**
- **FullLite ukazuje, že keď sú features silné, rodinný rozdiel mizne.**
- **SVM-RBF je najlepší praktický Lexical model.**
- **KNN je kvalitný, ale inferenčne drahý.**
- **Random Forest je presný, ale na Lexical horšie kalibrovaný pri 0.5.**
- **Surrogate strom vysvetľuje RF, nenahrádza ho.**

---

## 23. Rozšírený Q&A bank pre Scenár 2

### „Prečo ste nepoužili tidymodels namiesto caret?“

`tidymodels` je moderný ekosystém, ale `caret` poskytuje stabilné jednotné rozhranie pre veľa klasických modelov vrátane LDA, NB, RF, SVM a KNN. Pre cieľ projektu bolo dôležitejšie mať porovnateľnú experimentálnu infraštruktúru než najnovší framework.

Krátka odpoveď:

> `caret` nám umožnil držať rovnaké CV indexy, metriky a fitovací pattern cez šesť rôznych modelov.

### „Prečo nie nested cross-validation?“

Nested CV je vhodná pri intenzívnom hyperparameter tuningu. My primárne netunujeme veľké gridy, ale porovnávame rodiny modelov pri fixných, obhájiteľných nastaveniach. Používame 10-fold CV na tréningovej časti a nezávislý 20 % hold-out test.

### „Prečo práve 10 foldov?“

10 je štandardný kompromis. Menej foldov znamená menšiu trénovaciu časť na fold a viac kolísavé odhady; viac foldov znamená skoro identické tréningy, ktoré priemer zbytočne nestabilizujú a výpočtovo to neúmerne predraží — najmä SVM-RBF a RF. Pri 10 foldoch trénuje každý model na 90 % dát a celkovo robíme 60 fitov (6 modelov × 10), čo je ešte zvládnuteľné.

### „Prečo SVM-RBF a KNN patria medzi neparametrické?“

SVM-RBF nemá jednoduchú fixnú lineárnu hranicu v pôvodnom priestore a dokáže sa prispôsobiť zložitej geometrii dát. KNN nemá explicitne naučenú rovnicu; rozhoduje podľa uložených tréningových príkladov. Oba sú flexibilnejšie než LR/LDA/NB.

### „Prečo RF na Lexical nemá takú Specificity ako SVM?“

RF hlasuje cez veľa stromov a jeho pravdepodobnosti nemusia byť kalibrované tak, aby 0.5 bol ideálny prah. AUC ukazuje, že ordering je dobrý, ale threshold 0.5 nie je optimálny.

### „Prečo netunovať threshold, keď by RF vyzeral lepšie?“

Pretože H1 bola definovaná pri default prahu 0.5 pre všetky modely. Threshold tuning by bol ďalšia vrstva optimalizácie. Dá sa uviesť ako možný follow-up, nie ako súčasť férového základného porovnania.

### „Čo ak by po threshold tuningu RF porazil SVM?“

Potom by RF bol silnejší kandidát v kalibrovanom deployment scenári. Ale náš záver je presne formulovaný: pri jednotnom 0.5 prahu je SVM-RBF najlepší Lexical model.

### „Prečo považujete KNN inference za problém?“

KNN pri predikcii potrebuje počítať vzdialenosť k tréningovým bodom. Pri 24k tréningových vzorkách je to oveľa drahšie než model, ktorý má kompaktnú naučenú hranicu. Pri vysokom proxy trafficu to môže byť prakticky významné.

### „Prečo Scenár 4 nevysvetľuje SVM, keď SVM vyhral?“

Lebo Scenár 4 je o vizualizácii rozhodovacej logiky cez strom/heatmapu. Random Forest je prirodzene stromový model a surrogate strom je vhodný spôsob, ako ho aproximovať. SVM-RBF by potreboval iné vysvetľovacie techniky.

### „Prečo ste nepoužili SHAP?“

SHAP by bol dobrý follow-up, ale je mimo jednoduchého tree/heatmap zadania a pridal by ďalšiu metodickú vrstvu. Surrogate strom je priamo vizuálny, čitateľný a nadväzuje na zadanie.

### „Prečo je surrogate optimalizovaný na test-set fidelity?“

Cieľ surrogate nie je vyrobiť nový classifier, ale ukázať, ako dobre jednoduchý strom kopíruje RF na dátach, ktoré RF nevidel pri trénovaní teacher hodnotenia. Fidelity na test sete priamo odpovedá, ako vizualizácia zachytáva modelové správanie mimo tréningu.

---

## 24. „Čo ak“ scenáre do hĺbky

### 24.1 Čo ak by sme použili Full namiesto FullLite

Očakávaný výsledok:

- všetky modely by mali veľmi vysoké AUC,
- rozdiely medzi rodinami by boli minimálne,
- H1 by nebola informatívna.

Pre obhajobu:

> FullLite nie je slabší modelovací svet, ale férovejší experimentálny svet pre otázku H1.

### 24.2 Čo ak by sme použili iba Lexical a nič iné

Vedeli by sme povedať, že SVM je dobrý URL-only model, ale nevedeli by sme overiť gradient H1. FullLite je potrebný ako kontrastný silnejší tier.

### 24.3 Čo ak by sme použili viac modelov

Mohli by sme pridať XGBoost, neural networks alebo calibrated ensembles. Ale H1 nepotrebuje všetky modely sveta. Potrebuje reprezentatívne porovnanie rodín. Príliš veľa modelov by znížilo čitateľnosť.

### 24.4 Čo ak by sme použili menej modelov

Ak by sme mali iba LR vs SVM, komisia by mohla povedať, že výsledok je špecifický pre tieto dva modely. Tri modely v každej rodine robia záver robustnejší.

### 24.5 Čo ak by sme nefixovali seed

Výsledky by sa mohli mierne meniť medzi behmi. Fixný seed zabezpečuje reprodukovateľnosť, čo je pri obhajobe a notebookoch dôležité.

---

## 25. Praktická prezentácia výsledkov

### Ako vysvetliť H1 tabuľku do 30 sekúnd

> V každom tieri sme vybrali najlepší parametrický a najlepší neparametrický model podľa minSS. Na Lexical je rozdiel približne 0.30 v prospech neparametrických, čo je výrazne nad prahom 0.10. Na FullLite rozdiel mizne. To je presne gradient, ktorý H1 predpovedala.

### Ako vysvetliť per-model Lexical tabuľku

> AUC samotné nestačí. LDA má dobré AUC, ale zlú Specificity. Naive Bayes chytí skoro všetok phishing, ale blokuje veľa legitímnych URL. SVM-RBF je jediný, ktorý drží vysokú Sensitivity aj Specificity pri 0.5 prahu.

### Ako vysvetliť surrogate strom

> Strom je zjednodušená mapa RF. Nehovoríme, že strom je lepší classifier. Hovoríme, že zachytáva hlavné pravidlá, ktorými RF rozhoduje, a meriame to cez fidelity.

### Ako priznať limity bez oslabenia práce

> Najväčšie limity sú fixné hyperparametre a jeden dataset. Ale pre zadanie je dôležitá transparentná hypotéza, férový split, rovnaké foldy a jasné deployment metriky. To sme splnili.

---

## 26. Obranná stratégia pri ťažkých otázkach

### Ak sa pýtajú na kalibráciu

Povedať:

> Kalibrácia je samostatná téma. My zámerne hodnotíme default 0.5 bod, lebo porovnávame modely v rovnakom operačnom režime. RF by kalibrácia pomohla, ale potom by sme porovnávali aj kalibračnú procedúru.

### Ak sa pýtajú na štatistickú významnosť rozdielov

Povedať:

> Primárne kritériá sú praktické prahy, nie p-hodnoty. Rozdiel na Lexical minSS je taký veľký, že je deploymentovo významný. CV foldy slúžia ako kontrola stability.

### Ak sa pýtajú na produkčné nasadenie

Povedať:

> Produkčne by nasledovala externá validácia, monitoring driftu, kalibrácia threshold-u a meranie latency. Tento projekt rieši analytický výber a porovnanie modelov na dostupnom datasete.

### Ak sa pýtajú na interpretovateľnosť SVM

Povedať:

> SVM je kvalitný kandidát, ale menej interpretovateľný. Preto máme separátny Scenár 4, ktorý ukazuje vysvetliteľnosť na RF cez surrogate. V praxi by sa dali doplniť SHAP alebo permutation importance pre SVM.

---

## 27. Checklist pred obhajobou Scenára 2

- Viem vysvetliť H1 bez matematických symbolov?
- Viem vysvetliť minSS na príklade?
- Viem povedať, prečo Lexical je najdôležitejší?
- Viem odôvodniť 30k subsample?
- Viem odôvodniť dva preprocessing recepty?
- Viem odôvodniť každý zo šiestich modelov?
- Viem vysvetliť, prečo SVM vyhral?
- Viem vysvetliť, prečo RF nie je víťaz pri 0.5?
- Viem vysvetliť, čo surrogate strom robí a nerobí?
- Viem priznať limity bez paniky?

---

## 28. Hlboké základy modelov pre obhajobu

Táto časť je doplnková teoretická vrstva pre situácie, keď komisia chce vidieť, že rozumieme **prečo modely fungujú tak, ako fungujú**, nielen **že sme ich pustili**. Pre každý model uvádzame: princíp, čo presne sa „učí“, na čom je citlivý, a najmä — ako sa zmena hyperparametra prejaví na rozhodovacej hranici, výkone na trénovacích dátach a generalizácii. Pre SVM-RBF je samostatná detailná sekcia 29.

### 28.1 Logistic Regression Ridge — princíp a hyperparametre

**Princíp.** Logistická regresia priraďuje každému feature váhu (koeficient). Pre nový vstup spočíta vážený súčet `z = β₀ + β₁x₁ + β₂x₂ + …` a tento súčet pretlačí cez sigmoidálnu funkciu `σ(z) = 1 / (1 + e^(-z))`, ktorá ho premení na pravdepodobnosť medzi 0 a 1. Učenie znamená nájsť také váhy, aby pre phishing prípady bol `σ(z)` čo najbližšie k 1 a pre legitímne k 0. Optimalizuje sa **maximum-likelihood** — váhy, ktoré maximalizujú pravdepodobnosť pozorovaných dát.

**Ridge zložka.** Ridge pridáva k optimalizovanej funkcii pokutu `λ × Σβᵢ²`. Pokuta penalizuje veľké váhy. Optimalizátor preto musí robiť kompromis: dobrý fit verzus malé váhy. Pri silnej kolinearite (čo je náš prípad — VIF > 1000 v Lexical) ridge zaručí, že váhy sa rozdelia približne rovnomerne medzi korelované features, namiesto aby sa skoro celá zhodila na jeden, ktorý sa pri novej dávke dát môže zmeniť o veľa.

**Vplyv `lambda` (λ).**
- `λ = 0` → klasická logistická regresia bez penalizácie. Pri kolinearite koeficienty „vybuchujú“ a sú nestabilné medzi splitmi.
- `λ veľmi malé (napr. 0.001)` → minimálna stabilizácia, ale stále môže byť citlivá.
- `λ = 0.01` (naša voľba) → mierne stiahnutie veľkých koeficientov, model je stabilný, fit zostáva kvalitný.
- `λ veľké (napr. 10)` → koeficienty sú stiahnuté blízko k nule, model sa približuje konštantnej predikcii. AUC klesá, model „podfituje“.

**Vplyv `alpha`.** `alpha` v `glmnet` je mixing parameter medzi L2 a L1 penalizáciou.
- `alpha = 0` (čistý ridge) — drží všetky features, len ich váhy stláča.
- `alpha = 0.5` (elastic-net) — kombinuje stláčanie s feature selection.
- `alpha = 1` (čistý lasso) — niektoré koeficienty hodí presne na nulu.

V Scenári 2 zámerne **nemeníme alpha**, lebo nechceme robiť feature selection (to je úloha Scenára 3). Chceme len stabilizáciu pri fixnom predictor poole.

**Prečo presne LR-Ridge a nie obyčajná LR.** EDA nám ukázala, že `URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL` a podobné spojité dĺžkové features sú silno korelované. Obyčajná logistická regresia by pri takejto kolinearite produkovala koeficienty, ktoré sa pri minimálnom pohybe v dátach výrazne menia. To by Scenár 2 spravilo nedôveryhodným, lebo by sme nevedeli, či rozdiel medzi modelmi je skutočný alebo iba náhodný posun koeficientov LR. Ridge tento problém technicky odstráni a nepridáva žiadnu pridanú interpretačnú vrstvu.

### 28.2 LDA — princíp a hyperparametre

**Princíp.** LDA (Linear Discriminant Analysis) si predstavuje každú triedu ako mnohorozmerný **gaussovský oblak** s vlastným priemerom a spoločnou kovariančnou maticou. Hľadá lineárnu hranicu, ktorá najlepšie oddeľuje stredy oblakov vzhľadom na to, ako sú „rozčapené“. Po fitnutí má model dva priemery (jeden pre Phishing, jeden pre Legitimate) a jednu kovariančnú maticu. Predikcia novej URL spočíva v tom, kam je „bližšie“ — meraná Mahalanobisovou vzdialenosťou — a doplní sa to o prior pravdepodobnosti tried.

**Učené parametre.** Priemer každej triedy a spoločná kovariančná matica. Žiadny tuning hyperparameter v zmysle SVM-`C`.

**Vplyv volieb.**
- **Prior.** Ak vynútime iný prior než tried-relatívnu frekvenciu, hranica sa posunie smerom k triede s nižším priorom (model je „prísnejší“ k nej). My držíme default `pi = empirický pomer tried`.
- **Predpoklad spoločnej kovariancie.** Keby sme prešli na **QDA**, každá trieda by dostala vlastnú kovarianciu. To je flexibilnejšie, ale pri korelovaných features s veľkým počtom dimenzií veľmi nestabilné. Pri 13 Lexical features by QDA odhadovala 2×13×13 parametrov vs LDA 13×13.
- **Standardizácia.** Predpoklad gaussovských tried je citlivý na šikmé features. Preto musíme aplikovať `log1p` + `center/scale`, inak by LDA bola úplne mimo, čo aj historicky pri prvom pokuse bez log transformácie ukazovala.

**Prečo LDA, keď nie je víťaz.** LDA je klasický parametrický baseline. Pri obhajobe je dôležitá ako kontrast: ukazuje, čo zvládne jednoduchý lineárny model s gaussovským predpokladom. Ak by LDA vyhrala, znamenalo by to, že tu žiaden interakčný signál nie je. To, že LDA dosiahne dobré AUC, ale slabú Specificity pri 0.5, je informatívny výsledok — model vie zoradiť, ale nevie kalibrovať pre reálne rozhodovanie.

### 28.3 Naive Bayes — princíp a hyperparametre

**Princíp.** Naive Bayes pre každú triedu odhadne, akú má distribúciu každý feature samostatne (`P(xᵢ | Phishing)` a `P(xᵢ | Legitimate)`). Pri predikcii všetky tieto pravdepodobnosti **vynásobí** a aplikuje Bayesov vzorec:

```
P(Phishing | x) ∝ P(Phishing) × ∏ P(xᵢ | Phishing)
```

„Naive“ predpoklad je, že features sú **podmienene nezávislé** — t.j. po zafixovaní triedy nie sú medzi sebou nijako previazané. Toto v reálnych dátach skoro nikdy neplatí.

**Vplyv `usekernel`.**
- `FALSE` → Gaussian NB. Každú spojitú feature aproximuje jediným gaussom (jeden priemer + jedna SD pre triedu). Rýchle, ale ak má feature dve módy alebo dlhý chvost, rozdelenie sedí zle.
- `TRUE` → kernel-density NB. Distribúciu odhadne neparametricky (ako vyhladený histogram). Flexibilnejšie pre nesymetrické features, čo je presne náš prípad. Cena je vyššia výpočtová náročnosť.

**Vplyv `fL` (Laplace smoothing).** Pre kategoriálne features (binárky) `fL = 1` znamená, že keď v tréningu nikto z triedy nemal `IsDomainIP = 1`, NB napriek tomu nepriradí pravdepodobnosti nulu — pripočíta jednu „pseudo-pozorovanie“. Bez toho by jediný neviditeľný kombinačný stav vynuloval celé násobenie a znehodnotil predikciu. `fL = 0` by znamenalo nekorigované MLE odhady.

**Vplyv `adjust`.** Multiplikátor šírky kernelu. `adjust = 1` je default. Väčšie hodnoty kernel viac vyhladzujú (rozdelenie je „rozliatejšie“), menšie ho robia detailnejšie a zubatejšie.

**Prečo NB, keď predpoklad neplatí.** EDA ukázala silné korelácie v Lexical poole. NB ich nedokáže reflektovať, lebo predpokladá nezávislosť. Keď ho na takom poole pustíme, započíta podobný signál (dĺžka, počet písmen, počet znakov) viackrát ako keby to bolo niečo nezávislé. Výsledok: skoro celý dataset zatlačí smerom k phishingu. To je presne to, čo vidíme v testoch — Sensitivity skoro 1, Specificity dramaticky nízka. Tento výsledok nie je bug, je **interpretovateľný dôsledok zlomeného predpokladu** a do obhajoby patrí ako kontrolný experiment.

### 28.4 Random Forest — princíp a hyperparametre

**Princíp.** RF natrénuje veľa rozhodovacích stromov a finálnu predikciu robí hlasovanie (alebo priemer pravdepodobností). Každý strom je trénovaný na **bootstrap vzorke** (náhodný výber s opakovaním z trénovacích dát) a pri každom splite vidí iba **náhodnú podmnožinu features** veľkosti `mtry`. Tieto dve nezávislosti zaručia, že stromy sú odlišné a ich chyby sa pri hlasovaní spriemerujú.

**Vplyv `ntree`.**
- Malé `ntree` (napr. 10) → hlasovanie je nestabilné, výsledok kolíše medzi behmi.
- Stredné `ntree` (50–200) → výsledok začína byť stabilný, ale ešte sa zlepšuje.
- `ntree = 300` (naša voľba) → zóna saturácie pre náš dataset, ďalší strom mení AUC iba o desatinky percenta.
- Veľmi veľké `ntree` (1000+) → marginálne zlepšenie, lineárny nárast času, žiadna nová informácia.

Dôležité: **`ntree` neovplyvňuje overfitting** v klasickom zmysle. Veľa stromov len zníži variancu hlasovania.

**Vplyv `mtry`.** Toto je hlavný regularizačný hyperparameter RF.
- `mtry = p` (všetky features) → každý strom je takmer identický, pretože vždy si zvolí ten najlepší globálny split. Stromy sú silne korelované, RF stráca diverzitu, hlasovanie nie je viac „inteligentné“ než jeden strom.
- `mtry = √p` (default pre klasifikáciu, naša voľba) → kompromis. Pri Lexical (13 features) `mtry = 3`, pri FullLite (34 features) `mtry = 5`. Dosť na to, aby mal každý strom z čoho vyberať silný feature, a dosť na to, aby boli stromy odlišné.
- `mtry = 1` → každý strom vidí len jeden feature pri každom splite. Stromy sú extrémne odlišné, ale tiež extrémne slabé. Variancia hlasovania je nízka, ale bias jednotlivých stromov je vysoký.

**Vplyv hĺbky stromov (`maxnodes`, `nodesize`).** V `randomForest` výsledné stromy idú do veľmi hlbokej hĺbky (v default mode bez pruning-u). To je zámerné — preto RF potrebuje hlasovanie na zníženie variance. Ak by sme nasilu hĺbku obmedzili, jednotlivé stromy by boli slabšie a strácali by sa interakcie.

**Prečo RF.** Pri Lexical signáli je rozhodovacia logika kombinatorická („dlhá URL **A** veľa číslic **A** veľa subdomén“). Stromy zachytávajú interakcie prirodzene, lebo každý split rozdelí priestor na osi jedného feature, a v ďalších úrovniach sa na túto časť priestoru aplikuje ďalší split iného feature. Bagging + náhodný `mtry` znížia varianciu týchto interakcií.

### 28.5 KNN — princíp a hyperparametre

**Princíp.** KNN sa neučí explicitnú rozhodovaciu hranicu. Pri predikcii novej URL spočíta vzdialenosť k všetkým tréningovým bodom, vyberie `k` najbližších a hlasuje. „Hranica“ vzniká implicitne podľa toho, kde sa hlasovanie prevažuje.

**Vplyv `k`.**
- `k = 1` → predikcia je trieda jediného najbližšieho suseda. Extrémna citlivosť na šum, model si pamätá každý outlier.
- `k = 5` → hladšie, ale stále lokálne.
- `k = 25` (naša voľba) → kompromis. Lokálne susedstvo rozhoduje, ale šum jedného alebo dvoch bodov nepreklopí výsledok.
- `k = 100+` → veľmi vyhladené, model „zabúda“ na lokálne rozdiely a preferuje globálnu väčšinu.

**Vplyv škálovania features.** KNN je skoro vždy závislý od distance metriky. Ak by sme nedali `log1p` + `center/scale`, feature s najväčším rozsahom (napr. `URLLength` 0–500) by úplne dominoval vzdialenosť, ostatné by boli ignorované. Naše scaling preto nie je kozmetika.

**Vplyv jitteru.** Pri Trust tieri máme 7 prevažne binárnych features. Veľa URL má úplne identický feature vektor → KNN má „too many ties“ a `caret::knn3` padne. Jitter so SD `1e-3` rozbije ties bez toho, aby reálne zmenil susedstvá (binárky stále budú blízko 0 alebo 1).

**Vplyv distance metriky.** Default je Euclidean. Mohli by sme použiť Manhattan, Mahalanobis, kosinusovú podobnosť — každá by dala iné susedstvá. Pri štandardizovaných číselných features je Euclidean rozumný default a nemá zmysel ho meniť bez konkrétneho dôvodu.

**Nevýhoda KNN pri inferencii.** Po natrénovaní KNN nemá kompaktnú reprezentáciu — celý tréningový set musí byť v pamäti a každá nová predikcia vyžaduje výpočet vzdialenosti k 24k bodom. Pre proxy s vysokým provozom je to praktická prekážka.

### 28.6 Surrogate `rpart` strom — princíp a hyperparametre

**Princíp.** CART strom rekurzívne delí priestor binárnymi splitmi tvaru `xᵢ < t`. Pri každom uzle vyberie ten split, ktorý najviac zníži Gini impurity (alebo entrópiu). V Scenári 4 sa tento strom učí **cieľovú premennú = predikcie RF**, nie pôvodné labely. Preto nehovorí „čo je phishing“, ale „ako rozhoduje RF“.

**Vplyv `maxdepth`.**
- `maxdepth = 3` → strom má najviac 8 listov. Veľmi čitateľný, ale málokedy stačí na zachytenie 300-stromového RF.
- `maxdepth = 5` → 32 listov, dobrý kompromis pre vizualizáciu.
- `maxdepth = 7` (max v gridi) → 128 listov, lepšia fidelity, ale strom už nie je čitateľný na projektore.

**Vplyv `cp` (complexity parameter).** Pruning prag — split sa povolí len ak zníži chybu o aspoň `cp`-násobok pôvodnej chyby.
- `cp = 1e-2` → silne prerezáva, malé stromy.
- `cp = 1e-3` → stredné prerezávanie.
- `cp = 1e-4` → minimálne prerezávanie, strom rastie skoro do `maxdepth`.

**Vplyv `minbucket`.** Minimálny počet pozorovaní v liste. Veľké hodnoty (napr. 100) bránia tomu, aby strom robil rozhodnutia na základe pár outlierov; malé (napr. 10) povolia veľmi špecifické pravidlá.

**Vplyv cap `≤ 15 listov`.** Tento cap nemá metodický pôvod, je čisto **vizualizačný**. Strom s 30+ listami môže mať vyššiu fidelity, ale na projektore ho nikto neprečíta. Zámerne obetujeme nejaký bod fidelity, aby vizualizácia fungovala.

---

## 29. SVM-RBF — detailná hĺbková obhajoba

Toto je najdôležitejšia časť pre obhajobu, lebo SVM-RBF je deployment víťaz Scenára 2 a komisia sa pravdepodobne najviac pýta práve naň.

### 29.1 Základná intuícia bez matematiky

SVM (Support Vector Machine) hľadá medzi triedami **najširšiu možnú „uličku“**. V dvoch dimenziách si to predstavte ako čiaru, ktorá rozdeľuje phishing a legit body, ale nie hocijakú — tú, okolo ktorej je z oboch strán **maximálne voľné okolie**. Body, ktoré tesne dotýkajú túto uličku, sa volajú **support vectors** a iba tieto body určujú kde čiara leží. Ostatné body sú nepodstatné.

V realite však triedy nie sú lineárne oddeliteľné jednou čiarou. Preto SVM používa **kernel trick** — body sa „virtuálne“ premietnu do priestoru s viac dimenziami, kde sú lineárne oddeliteľné. RBF (Radial Basis Function) kernel je špecifická voľba, ktorá zodpovedá premietnutiu do nekonečno-rozmerného priestoru, kde sa hranica skladá z **gaussovských kopcov** okolo support vectors.

Laická obhajobová formulácia:

> SVM-RBF si pred každý phishing support vector v okolí postaví guľový „výbuch“, ktorý hovorí: tu je phishing. To isté pre legit. Tieto výbuchy sa skladajú a tvoria zakrivenú hranicu, ktorá obtiaha komplikované zhluky bodov.

### 29.2 Matematický základ pre prípadnú techničku otázku

Optimalizačný problém pre SVM klasifikáciu (v duálnej forme so soft-margin):

```
maximalizuj:  Σαᵢ - ½ ΣᵢΣⱼ αᵢαⱼ yᵢyⱼ K(xᵢ, xⱼ)
podmienky:    0 ≤ αᵢ ≤ C,   Σαᵢyᵢ = 0
```

kde:
- `αᵢ` sú Lagrangeove násobky pre každý tréningový bod,
- `yᵢ ∈ {−1, +1}` je label,
- `K(xᵢ, xⱼ)` je **kernel funkcia**,
- `C` je regularizačný parameter (margin vs chyby).

Pre RBF kernel:

```
K(xᵢ, xⱼ) = exp(−σ × ‖xᵢ − xⱼ‖²)
```

kde `σ` (v `kernlab` sa nazýva `sigma`, v iných knižniciach `gamma`) je inverzná „šírka“ gaussovského zvonca okolo bodu. Pri obhajobe nemusíte recitovať tento vzorec, ale je dobré vedieť, že:

- kernel meria **podobnosť** dvoch bodov,
- veľká vzdialenosť → podobnosť padá k nule,
- `sigma` riadi, **ako rýchlo** podobnosť padá.

### 29.3 Hyperparameter `C` — soft-margin a tolerancia chýb

`C` je penalizácia za to, že tréningový bod leží na zlej strane hranice alebo vnútri uličky.

| `C` | Čo sa stane | Riziko |
|---|---|---|
| `C → 0` | Model toleruje skoro všetky chyby. Hranica je veľmi hladká, široká ulička. | **Underfitting** — model nezachytí ani jasné rozdiely. |
| `C = 0.1` | Mäkký margin, model dovolí veľa chýb. | Nízky výkon na komplexnejších problémoch. |
| `C = 1` (naša voľba) | Štandardný kompromis. Dovolí pár chýb, ale tlačí na čisté oddelenie. | Pri dobre škálovaných dátach je to overený default. |
| `C = 10` | Tvrdý margin. Model tlačí na takmer perfektné oddelenie. Hranica sa kriví okolo outlierov. | **Overfitting** — model zapamätáva šum. |
| `C → ∞` | Hard-margin SVM. Žiadna chyba na tréningu nie je dovolená. Existuje len ak sú dáta lineárne oddeliteľné v kernelovom priestore. | Extrémny overfitting alebo neexistencia riešenia. |

**Geometrická intuícia.** Predstavte si, že SVM kreslí cestu medzi dvoma hradbami bodov. `C` určuje, ako veľmi sa cesta smie ohýbať okolo jednotlivých bodov. Pri nízkom `C` je cesta širokou diaľnicou, ktorá ignoruje pár áut; pri vysokom `C` je úzkym chodníčkom, ktorý sa kľukatí, aby obtiahol každý bod.

**Prečo `C = 1` u nás.** Pri štandardizovaných features (`center/scale`) sú typické vzdialenosti medzi bodmi rádovo `1`. `C = 1` znamená, že chyba veľkosti jednej smerodajnej odchýlky je trestaná porovnateľne s margin objective. Je to **konvenčný štartovací bod** pred ladením, a pretože sa nám pri tomto nastavení podarilo prejsť cez všetky H1 prahy s veľkou rezervou, neexistovala metodicky čistá motivácia tunovať ďalej (tunovanie len `C` by zvýhodnilo SVM oproti ostatným modelom, ktorých hyperparametre sme tiež držali fixné).

### 29.4 Hyperparameter `sigma` — šírka kernelu

`sigma` riadi, **ako lokálne** rozhoduje SVM. Je to inverzia šírky gaussovského kernelu — väčšia `sigma` znamená **užší** kernel (vplyv bodu rýchlejšie padá so vzdialenosťou).

| `sigma` | Čo sa stane | Riziko |
|---|---|---|
| `sigma → 0` | Kernel je veľmi široký, každý bod ovplyvňuje takmer celý priestor. Hranica je takmer lineárna. | **Underfitting.** Pri lineárne neoddeliteľných dátach nemá kernel trik žiaden zmysel. |
| `sigma = 0.01` | Široký kernel, hladká globálna hranica. | Pri komplexných hraniciach môže podfitovať. |
| `sigma = 0.1` (naša voľba) | Stredne lokálny kernel. Vie sa kriviť, ale nie okolo každého bodu. | Pri 1/p ≈ 1/13 ≈ 0.077 (default `gamma` v sklearn pre `p = 13`) je 0.1 rozumne blízko. |
| `sigma = 1` | Úzky kernel. Hranica sa kriví okolo malých zhlukov. | Začínajúci overfitting. |
| `sigma → ∞` | Každý support vector vplýva iba na seba. Hranica je tisíce malých „bublín“ okolo trénovacích bodov. | **Extrémny overfitting** — model si zapamätá presne tréning a generalizuje zle. |

**Geometrická intuícia.** Každý support vector je „lampa“, ktorej svetlo dopadá na okolie. `sigma` určuje, ako ďaleko lampa svieti.
- Široký kernel (malé `sigma`) → susedné lampy sa prelínajú, krajinu osvetľuje plynulé svetlo, hranica je mäkký záhyb.
- Úzky kernel (veľké `sigma`) → každá lampa svieti len blízko seba, krajina je rozdrobená na ostrôvky svetla, hranica je hrboľatá.

**Vzťah `C` a `sigma`.** Sú v interakcii:
- vysoké `C` + vysoké `sigma` → extrémny overfitting (model si zapamätá tréning úplne presne),
- nízke `C` + nízke `sigma` → underfitting (skoro lineárna hladká hranica),
- vyvážené stredné hodnoty → dobrá generalizácia.

Pri Lexical po `log1p + center/scale` má `(C=1, sigma=0.1)` empiricky výborný výkon, lebo features sú normalizované na jednotkovú škálu a 13-rozmerný priestor nie je nadmerne riedky.

### 29.5 Prečo presne RBF a nie iný kernel

`kernlab` ponúka aj `linear`, `polynomial`, `tanh` (sigmoid), `laplacedot`, `besseldot` a iné kernely. Prečo RBF:

1. **Univerzálnosť.** RBF s vhodnou `sigma` dokáže aproximovať takmer ľubovoľnú spojitú funkciu (univerzálny aproximátor). Polynomiálny kernel je obmedzený stupňom `d`.
2. **Lokalita.** RBF je „lokálny“ — bod ovplyvňuje iba blízke okolie. Pre URL phishing dáva zmysel: dva URL s podobnými lexikálnymi znakmi sa správajú podobne, vzdialené URL sú prakticky nezávislé.
3. **Default v praxi.** RBF je default pre väčšinu SVM implementácií, lebo je robustný a nemá veľa hyperparametrov (iba `sigma`).
4. **Kompatibilita s `log1p + scale`.** Po našom preprocessingu sú vzdialenosti v rozumnej škále, čo je presne to, čo RBF potrebuje.

Linear kernel by bol ekvivalentom logistickej regresie — predpokladá lineárnu hranicu. EDA nám práve hovorí, že lineárna hranica nestačí.

Polynomial kernel by bol možný, ale mení tri hyperparametre (`degree`, `scale`, `offset`) a nemá lokalitu. Pre tabulárne dáta sa používa zriedkavo.

### 29.6 Prečo SVM-RBF vyhráva práve na Lexical

Tento argument je obhajobové jadro. Lexical signál má štyri vlastnosti, ktoré SVM-RBF zvláda lepšie než iné modely:

1. **Slabé jednotkové signály.** EDA: žiadny Lexical feature samostatne nemá veľmi vysokú SMD. Logistická regresia, ktorá hľadá lineárnu kombináciu, nemá dosť silných „lineárnych smerov“.
2. **Bohatý kombinatorický signál.** Phishing nemá jeden definujúci atribút; má kombinácie (dlhá URL + veľa číslic + podivné špeciálne znaky). RBF kernel zachytáva interakcie implicitne cez podobnosť bodov v originálnom priestore.
3. **Korelované features.** Ridge regularizácia stabilizuje LR, ale stále hľadá lineárnu hranicu. SVM s RBF nepotrebuje rozkladať váhy medzi korelovanými features — iba meria podobnosť celých vektorov.
4. **Stredná dimenzionalita.** 13 features po štandardizácii nie je príliš málo (RBF by sa stratil v 1D) ani príliš veľa (curse of dimensionality), je to ideálny rozsah pre RBF.

Random Forest má podobné výhody (interakcie), ale jeho hlasovacia pravdepodobnosť pri prahu 0.5 nie je tak dobre kalibrovaná ako rozhodovacia funkcia SVM. KNN je tiež podobnostný model, ale je inferenčne drahý.

### 29.7 Slabiny SVM-RBF, ktoré priznávame

1. **Interpretovateľnosť.** SVM-RBF nemá explicitné koeficienty per feature. Variable importance sa robí post-hoc cez permutation importance alebo SHAP, čo sme v projekte nerobili. Preto Scenár 4 vysvetľuje RF, nie SVM.
2. **Kalibrácia pravdepodobností.** Default Platt scaling v `kernlab` dáva rozumné, ale nie ideálne pravdepodobnosti. Pri 0.5 prahu nám to v Lexical nevadí, ale v iných deployment scenároch by sme mali kalibráciu overiť.
3. **Výpočtová náročnosť trénovania.** O(n²)–O(n³) je dôvod, prečo používame 30k subsample a nie celý 235k dataset. Inferencia je rýchlejšia (proporčná počtu support vectors).
4. **Tuning hyperparametrov je drahý.** Grid search nad `(C, sigma)` × CV by bol výpočtovo extrémne náročný. Preto držíme fixné rozumné defaulty.

Obhajobová veta:

> SVM-RBF je deployment kandidát, ale nie interpretačný kandidát. Tento rozdiel akceptujeme a v Scenári 4 vysvetľujeme RF, ktorý je síce o trochu slabší pri 0.5, ale prirodzene stromový.

### 29.8 Čo by sa stalo, keby sme zmenili `(C, sigma)`

| Zmena | Predpokladaný efekt |
|---|---|
| `C = 0.1, sigma = 0.1` | Mäkší margin, hladšia hranica. AUC by mierne kleslo, Sensitivity/Specificity by sa priblížili k LR-Ridge výsledkom. |
| `C = 10, sigma = 0.1` | Tvrdší margin, model si bude pamätať detaily. Train AUC blízko 1, test AUC pravdepodobne mierne klesne. Risk overfitting na konkrétnu sub-vzorku. |
| `C = 1, sigma = 1` | Úzky kernel, hranica sa rozpadne na lokálne ostrovy. Test Specificity klesne, lebo legit body v okolí phishingových sa preklopia. |
| `C = 1, sigma = 0.01` | Široký kernel, takmer lineárna hranica. Výsledok blízko SVM-Linear / LR. |
| `C = 100, sigma = 10` | Patologický overfitting — train accuracy ≈ 1, test accuracy ≈ random. |

Tento prehľad je dobré mať v hlave: ak sa komisia opýta „čo keby ste zvýšili sigma?“, viete povedať konkrétny smer dopadu, nie len „bolo by to iné“.

### 29.9 Ako vysvetliť SVM-RBF za 30 sekúnd

> SVM-RBF kreslí medzi triedami uličku s čo najväčšou rezervou. Lineárnu uličku by často nenašiel, preto používa RBF kernel — predstaví si, že okolo každého trénovacieho bodu je gaussovský zvon a rozhoduje sa podľa toho, či nový bod padne do oblasti, kde dominujú phishingové zvony alebo legitímne. Parameter `C` riadi, ako prísne má model trestať tréningové chyby; parameter `sigma` určuje, ako lokálne tieto zvony pôsobia. Pre Lexical signál, kde phishing nemá jeden definujúci atribút ale kombináciu znakov, je RBF prirodzená voľba a vyhráva s najlepším operačným bodom pri 0.5.

---

## 30. Detailné odôvodnenie výberu modelov pre H1

H1 nie je „nájsť najlepší model“, ale **otestovať, či je rozdiel medzi rodinami modelov závislý od tieru**. Aby tento test dával zmysel, výber modelov musí spĺňať tri vlastnosti:

1. **Reprezentatívnosť rodín.** Každá strana (parametrická vs neparametrická) musí mať modely, ktoré reprezentujú jej typický prístup, nie marginálne varianty.
2. **Diverzita vnútri rodiny.** Tri parametrické modely musia byť dosť odlišné, aby keby vyhrali rovnako, vedeli sme, že rodina je obmedzená — nielen jeden konkrétny model.
3. **Férovosť.** Žiadny model nesmie byť nasadený s extrémne vyladenými parametrami a iný s defaultmi; všetky majú konvenčné, EDA-podložené nastavenia.

### Parametrická rodina — prečo presne LR + LDA + NB

- **Logistic Regression (Ridge).** Najpoužívanejší klasifikátor v praxi. Učí sa lineárnu kombináciu features. Ridge rieši kolinearitu, ktorú v Scenári 2 nemôžeme ignorovať, ale neeviuje feature selection.
- **LDA.** Klasický generatívny model s gaussovským predpokladom. Má iné teoretické pozadie než LR (modeluje `P(x|y)` namiesto `P(y|x)`), ale výsledná hranica je tiež lineárna. Dôležitá ako kontrast: ak by LR a LDA dopadli rovnako, vieme, že lineárna hranica nestačí; ak by jeden vyhral, ide o vlastnosť konkrétneho modelu.
- **Naive Bayes.** Simulácia „čo sa stane, keď zlomíme nezávislostný predpoklad“. Bez NB by parametrická rodina vyzerala ako dvojica s dobrým AUC, len rozdielnou kalibráciou. NB pridáva „cenu zlomeného predpokladu“ a komisia vidí, že parametrické modely nie sú homogénna skupina.

### Neparametrická rodina — prečo presne RF + SVM-RBF + KNN

- **Random Forest.** Stromový ensemble, najpopulárnejší neparametrický model pre tabulárne dáta. Implicitne zachytáva interakcie, robustný voči preprocessingu.
- **SVM-RBF.** Geometricky-kernelový prístup. Úplne iná matematika než RF — RF rozdeľuje priestor osovými splitmi, SVM ho premietne do kernel priestoru a hľadá maximálny margin. Ak by oba vyhrali, vieme, že neparametrické modely sú robustne lepšie. Ak by jeden výrazne vyhral, mali by sme objasňovať prečo.
- **KNN.** Najjednoduchší neparametrický model bez explicitnej rozhodovacej hranice. Cash test: ak ani KNN, ktorý sa „neučí“ nič okrem uloženia trénovacích bodov, neprehrá s parametrickými, je to silný argument pre H1.

### Modely, ktoré sme zámerne nezahrnuli a prečo

- **XGBoost / LightGBM.** Bol by silný neparametrický model, ale do H1 nepridáva nový typ argumentu — RF už pokrýva stromový boosting/bagging svet. Pridanie by len rozriedilo porovnanie. Je to legitimný follow-up.
- **Neural network (MLP).** Tabelárne dáta majú zvyčajne lepšie výsledky s gradient boostingom alebo SVM. NN by vyžadoval ladenie architektúry, čo nie je v scope projektu.
- **QDA.** Mohol byť tretí parametrický baseline, ale pri korelovaných features je nestabilný a NB pokrýva „naivný“ koniec parametrickej škály lepšie.
- **Logistic regression bez regularizácie.** EDA-vylúčená zo zoznamu kvôli VIF > 1000.
- **SVM-Linear.** V kerneli by spadol blízko k LR. Nepridáva metodicky novú informáciu.

---

## 31. Detailné odôvodnenie hyperparametrov v Scenári 2

Tabuľka, ktorú mám pripravenú pre prípadnú detailnú otázku:

| Model | Parameter | Hodnota | Odôvodnenie | Aký by bol efekt zmeny |
|---|---|---|---|---|
| LR-Ridge | `alpha` | 0 | Čistý ridge, nie feature selection. | `alpha = 1` by hodil features, čo nepatrí do Scenára 2. |
| LR-Ridge | `lambda` | 0.01 | Mierne stiahnutie pri VIF > 1000. | `0` → nestabilita; `1` → underfitting, AUC klesá. |
| LDA | (žiadny tuning) | — | LDA nemá hlavný hyperparameter. | Iné prior alebo QDA by zmenili hranicu/stabilitu. |
| NB | `usekernel` | TRUE | Lexical features nie sú gaussovské. | FALSE → ešte horší fit pre šikmé features. |
| NB | `fL` | 1 | Laplace smoothing pre 0-počty. | 0 → riziko zero-probability v test sete. |
| NB | `adjust` | 1 | Default kernel bandwidth multiplikátor. | >1 vyhladí, <1 zaostrí. |
| RF | `ntree` | 300 | Saturácia AUC pre náš dataset. | Menej → variabilita; viac → marginálny zisk. |
| RF | `mtry` | sqrt(p) | Klasifikačná heuristika. | Vyššie → korelované stromy; nižšie → slabé stromy. |
| SVM-RBF | `C` | 1 | Štandardný kompromis pre štandardizované features. | Vyššie → overfitting; nižšie → underfitting. |
| SVM-RBF | `sigma` | 0.1 | Blízko 1/p ≈ 0.077, dobrý lokálnosť/hladkosť mix. | Vyššie → patchy hranica; nižšie → skoro lineárna. |
| KNN | `k` | 25 | Stabilný kompromis. | <10 → šum; >50 → vyhladenie reálnych rozdielov. |
| KNN | `jitter sd` | 1e-3 | Rozbije ties bez zmeny zmyslu. | Väčšie → mení binárne hodnoty; menšie → ties zostanú. |
| Surrogate | `maxdepth` | 3–7 | Spektrum čitateľnosti. | <3 → triviálne; >7 → na projektore nečitateľné. |
| Surrogate | `cp` | 1e-4..1e-2 | Rôzne sily prerezávania. | Vyššie → menšie stromy; nižšie → väčšie. |
| Surrogate | leaves cap | 15 | Vizualizačné kritérium. | Bez capu → fidelity vyššie, čitateľnosť nižšia. |
