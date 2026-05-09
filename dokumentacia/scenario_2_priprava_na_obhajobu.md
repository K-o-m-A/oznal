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

- `k`: malé `k` (napr. 1–3) = veľmi lokálne rozhodnutie, citlivé na šum a outliery (vysoká variancia). Veľké `k` = vyhladenie lokálnych rozdielov, hranica sa blíži globálnemu majoritnému hlasovaniu (vysoký bias).

**Prečo presne `k = 25`.** Pre náš tréning s 24 000 bodmi (≈12k Phishing, ≈12k Legitimate) je 25 kompromis z troch dôvodov:

1. **Dosť veľké, aby sa náhodný šum vypriemeroval.** Pri `k = 1` jeden mislabeled tréningový bod priamo prevráti predikciu pre celé okolie. Pri `k = 25` musí byť aspoň 13 z 25 najbližších bodov patrickej triedy — jednotlivé chybne označené body sú prebité majoritou. Z teórie kNN sa štandardne odporúča `k ≥ 5` práve preto, aby majoritný hlas nebol citlivý na 1–2 outlierov.
2. **Dosť malé, aby hranica zostala detailná.** Pri `k → ∞` všetky body dostanú tú istú predikciu (apriori pomer tried). Pri `k = 25` sa pozeráme do **veľmi lokálneho okolia** — spomedzi 24 000 bodov je 25 zhruba 0.1 %. Hranica medzi triedami si tak zachová tvar a nespriemeruje sa do globálneho šumu.
3. **Heuristika √N je horný odhad.** Klasická literatúra odporúča `k ≈ √N`, čo by pre nás bolo `√24000 ≈ 155`. To je v praxi často priveľa — privedie to k vyhladzovaniu lokálnych zhlukov, ktoré sú pri phishing URL relevantné (napr. malá skupina podobne formátovaných phishing URLs). `k = 25` leží medzi minimom (5) a `√N` heuristikou a empiricky funguje pre stredne veľké binárne klasifikačné úlohy. Tunovať `k` cez celý grid by sa dalo, ale Scenár 2 fixuje hyperparametre, takže volíme rozumný default.
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

Zadanie Scenára 4 žiada **vizualizovať rozhodovanie modelu** pomocou heatmap alebo stromov a porovnať vizualizáciu s podkladovým modelom. Cieľom je interpretovateľnosť: nielen merať, ako presne model klasifikuje, ale aj ukázať, **podľa čoho rozhoduje**. My sme zvolili stromový prístup pomocou tzv. **surrogate stromu**.

### 9.2 Prečo nie heatmap

Heatmapa korelácií alebo klastrovania ukazuje vzťahy **medzi features navzájom** — napríklad že `URLLength` a `NoOfLettersInURL` sú silne korelované. Neukazuje však, čo s tým robí konkrétny model. Inak povedané: heatmapa hovorí o dátach, nie o modeli. Pre Scenár 4 potrebujeme niečo, čo hovorí o **správaní modelu**, a to surrogate strom robí priamo — učí sa napodobniť Random Forest, takže jeho štruktúra zodpovedá rozhodovacej logike RF.

### 9.3 Prečo Random Forest ako teacher

Vybrali sme RF, lebo je presný, ale **neprehľadný**: skladá sa z 300 stromov, ktoré nezávisle hlasujú a predikcia je priemer hlasov. Žiadny jeden strom nie je „ten“ rozhodovací — každý vidí inú bootstrap vzorku a inú podmnožinu features. Pri pohľade na ensemble nie je možné jednoducho povedať, „RF rozhoduje takto“. Preto potrebujeme zjednodušeného **študenta**, ktorý sa od RF naučí, aký výstup pri akom vstupe má dať. SVM-RBF by sme tiež mohli vziať ako teacher, ale jeho rozhodovacia hranica leží v kernel priestore, ktorý sa stromom napodobňuje horšie. RF je stromový ensemble, takže prirodzene sa dá aproximovať jedným stromom.

### 9.4 Ako surrogate funguje

Kľúčový rozdiel oproti normálnemu trénovaniu:

- **Normálny model** sa učí: `features → skutočný label` (phishing/legit z datasetu).
- **Surrogate strom** sa učí: `features → predikcia Random Forest` (čo RF povedal pre daný riadok).

Konkrétny postup:

1. Natrénujeme RF na tréningových dátach so skutočnými labelmi.
2. Necháme RF predikovať na celom tréningovom sete — každý riadok teraz má dva labely: skutočný a RF predikciu.
3. Natrénujeme `rpart` strom, kde **target je RF predikcia**, nie skutočný label.
4. Strom sa teda neučí klasifikovať phishing — učí sa **kopírovať odpovede RF**.

**Fidelity** = podiel testovacích prípadov, kde strom dáva rovnakú odpoveď ako RF. Ak je fidelity 0.94, strom v 94 % prípadov reprodukuje RF rozhodnutie. Tree AUC oproti skutočnému labelu je vedľajšie — strom nie je náhrada RF, len jeho čitateľný portrét.

### 9.5 Prečo Lexical a FullLite

Surrogate trénujeme na dvoch tieroch zámerne, aby sme videli **dva rôzne typy pozorovania**:

- **Lexical** — RF je tu nelineárny a využíva interakcie medzi URL counts. Surrogate strom musí túto nelinearitu aproximovať postupnosťou splitov, čo je zaujímavá ukážka „ako stromová logika rozkladá nelineárne rozhodovanie“.
- **FullLite** — RF tu má aj silné Trust binárky (`HasSocialNet`, `IsHTTPS` atď.), ktoré sú prirodzene stromové. Očakávame **vysokú fidelity** a strom má slúžiť ako sanity check: ak by fidelity nebola vysoká aj tu, niečo by bolo zle s našou metodikou.

Trust samostatne je príliš malý (7 features, prevažne binárne) — strom by bol triviálny a nepriniesol nový pohľad. Behavior bez near-leakerov je kvalitatívne medzi Lexical a FullLite a nepridal by nový typ pozorovania.

### 9.6 Tuning surrogate stromu

Hyperparametre `rpart` stromu, ktoré tunujeme:

- **`maxdepth`** (3–7) — maximálna hĺbka stromu od koreňa po list. Hlbší strom = viac splitov = vyššia fidelity, ale horšia čitateľnosť.
- **`cp`** (complexity parameter) — pruning prah. Split sa pridá iba ak zlepší fit aspoň o `cp`. Vyšší `cp` = agresívnejšie orezávanie = jednoduchší strom.
- **`minbucket`** — minimálny počet riadkov v liste. Bránime sa pred splitom, ktorý by vyrobil mikro-list pre 2-3 riadky.

Hľadáme **najvyššiu fidelity pri zachovaní čitateľnosti**. Hlboký strom môže RF lepšie kopírovať, ale pri ústnom vysvetľovaní na projektore je nepoužiteľný — komisia by sa stratila vo vetvách.

### 9.7 Prečo cap <= 15 listov

Po tuningu sme mali kandidátske stromy s rôznymi počtami listov. Strom s 37 listami mal vyššiu fidelity, ale **človek ho nevie naraz pochopiť**. Pri obhajobe potrebujeme strom, ktorý vieme prejsť za 30 sekúnd a ukázať „toto je root, toto je druhý split, takto sa dospelo k phishing predikcii“. Empirické pravidlo z literatúry hovorí, že 10–15 listov je hranica zrozumiteľnosti. Preto sme z tuned kandidátov vybrali **najlepšieho s najviac 15 listami**.

Vedome obetujeme nejakú fidelity v prospech čitateľnosti — to je hlavné rozhodnutie Scenára 4. Numericky najlepší surrogate by bol pre obhajobu nepoužiteľný.

### 9.8 Výsledok pre Lexical

**Root split:** `NoOfOtherSpecialCharsInURL < 3`. To znamená, že najsilnejším jediným signálom, ktorým strom napodobňuje RF, je **počet ostatných špeciálnych znakov v URL**. Phishing URL majú typicky viac neobvyklých znakov (`%`, `=`, `&`, lomítka v zvláštnych pozíciách), legit URL majú týchto znakov málo.

Ďalšie features, ktoré sa objavia v horných vrstvách stromu:

- `NoOfDegitsInURL` — počet číslic,
- `NoOfSubDomain` — počet subdomén (phishing často reťazí subdomény typu `login.bank.security.evil.com`),
- `TLDLength` — dĺžka TLD (legit `.com`/`.sk` vs phishing dlhé alebo neobvyklé TLD),
- `CharContinuationRate` — miera, ako sa rovnaké znaky reťazia,
- `URLLength`, `NoOfLettersInURL` — celkové počty.

**Fidelity ~0.94**, Tree AUC výrazne nižšie než RF AUC. Strom **nie je náhrada RF**, je to **okno do jeho logiky** — ukazuje, ktoré features RF používa najviac a v akom poradí.

### 9.9 Výsledok pre FullLite

**Root split:** `HasSocialNet = 1`. Keď má model k dispozícii Trust a Behavior features, nemusí sa pretĺkať cez zložité URL counts — postačí mu jediný silný binárny signál. Phishing stránky typicky **nemajú odkazy na sociálne siete** (legit firmy ich majú v päte stránky).

V horných vrstvách dominujú **Trust binárky**:

- `HasCopyrightInfo` — phishing obvykle nemá copyright,
- `HasDescription` — meta-description je častejšia na legit,
- `IsHTTPS` — bezpečnostná vlastnosť spojenia,
- `HasSubmitButton` — phishing často má submit button (zachytávanie credentials).

**Fidelity ~0.97** — vyššia než na Lexical. Dáva to zmysel: stromová logika presne sedí na binárne Trust features, takže napodobnenie RF je jednoduchšie. To je **sanity check** — keby surrogate aj tu zlyhal, niečo je systematicky pokazené.

### 9.10 Variable importance cross-check

Riziko surrogate prístupu: strom sa môže nezávisle „uchýliť“ k inej feature než RF — môže byť čitateľný, ale **logiku RF nezachytí**. Preto robíme cross-check pomocou `randomForest::varImpPlot`:

1. Vytiahneme z RF zoznam features podľa **mean decrease in Gini** (RF interná dôležitosť feature).
2. Porovnáme s root splitom a hornými splitmi surrogate stromu.
3. Ak sa zhodujú, strom naozaj zachytáva to, čo RF považuje za dôležité.

Pre Lexical: `NoOfOtherSpecialCharsInURL` je v top 3 RF importance **a** zároveň root surrogate stromu. Pre FullLite: `HasSocialNet` je v top RF importance **a** root stromu. Cross-check teda potvrdzuje, že surrogate nie je iba ľubovoľný jednoduchý model, ale skutočne reprezentuje rozhodovanie RF.

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
prečo sm

