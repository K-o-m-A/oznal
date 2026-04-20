# Príprava na obhajobu — `phishing.rmd` (EDA a hypotézy)

Tento dokument je učebnou pomôckou k notebooku `phishing.rmd`. Prechádza
notebookom po sekciách a pre každý krok vysvetľuje **čo sa robí**,
**prečo sa to robí** a **čo má obhajujúci strážiť** pri otázkach komisie.

Pre pohodlie čitateľa sú všetky **odborné pojmy** (AUC, ROC, VIF, SMD,
Cramérove V, CV, Wilcoxon, ...) vysvetlené v sekcii **0. Slovník pojmov**
na začiatku. Odkazy na pojmy v ďalších sekciách ukazujú späť do slovníka.

---

## 0. Slovník pojmov — čo všetky skratky znamenajú

### EDA (Exploratory Data Analysis — prieskumná analýza dát)
Fáza pred modelovaním, v ktorej sa pozrieme na surové dáta: distribúcie,
chýbajúce hodnoty, korelácie, outliery. Cieľom NIE je trénovať model,
ale porozumieť štruktúre dát tak, aby sme vedeli správne zvoliť
preprocessing a typ modelu.

### AUC (Area Under the ROC Curve — plocha pod ROC krivkou)
**Najdôležitejšia metrika v tomto projekte.**
- **Binárny klasifikátor** vracia pre každý príklad pravdepodobnosť
  P(phishing). Aby sme spravili tvrdé rozhodnutie, potrebujeme **prah**
  (napr. predikuj "phishing", ak P > 0.5).
- **ROC krivka** (Receiver Operating Characteristic) vykresľuje pre
  **všetky možné prahy** dvojicu:
  - os X: False Positive Rate = FP / (FP + TN) = aká časť legitimate
    stránok je chybne označená ako phishing,
  - os Y: True Positive Rate = TP / (TP + FN) = aká časť phishing
    stránok je správne odhalená.
- **AUC** = integrál pod touto krivkou, hodnota medzi 0 a 1.
  - AUC = 1.0 → dokonalý klasifikátor,
  - AUC = 0.5 → náhodné hádanie,
  - AUC = 0.9 → výborný klasifikátor,
  - AUC = 0.8 → dobrý klasifikátor.
- **Prečo práve AUC a nie Accuracy?**
  1. AUC je **prahovo nezávislá**: porovnáva kvalitu *skóre*, nie
     konkrétneho rozhodnutia.
  2. AUC má štatistickú interpretáciu: *pravdepodobnosť, že náhodne
     vybraná phishing URL dostane vyššie skóre ako náhodne vybraná
     legitimate URL.*
  3. Na približne vyváženom datasete (43/57) sú AUC aj Accuracy
     informatívne, ale AUC sa nemení pri zmene prahu.

### ROC (Receiver Operating Characteristic)
Názov sa zachoval z radaru z 2. svetovej vojny: "krivka prijímača" pre
detekciu nepriateľských lietadiel. Dnes je to štandard v medicíne,
bezpečnosti a strojovom učení.

### FPR, TPR, Accuracy, Precision, Recall, F1
Základné metriky klasifikácie, všetky počítané z matice zámien
(confusion matrix):

|              | skutočne Phishing | skutočne Legitimate |
|--------------|-------------------|---------------------|
| predikované Phishing   | **TP** (true positive) | **FP** (false positive) |
| predikované Legitimate | **FN** (false negative) | **TN** (true negative) |

- **Accuracy** = (TP + TN) / (TP + FP + TN + FN) — aká časť predikcií je
  správna.
- **Precision** = TP / (TP + FP) — zo všetkých, ktoré sme označili za
  phishing, aká časť naozaj phishingom je.
- **Recall** (= Sensitivity, = TPR) = TP / (TP + FN) — zo všetkých
  skutočných phishing, koľko sme zachytili.
- **Specificity** = TN / (TN + FP) — zo všetkých legitímnych, koľko sme
  ich nesprávne neoznačili.
- **F1** = harmonický priemer Precision a Recall =
  2·P·R / (P + R). Balancuje FP a FN chyby.

### Cross-Validation (CV, krížová validácia)
Metóda odhadu, ako dobre sa bude model chovať na neuviedených dátach.
Trénovacie dáta sa rozdelia na **k** rovnako veľkých častí (foldov):
- Pre každý fold: trénuj na zvyšných k-1 foldoch, vyhodnoť na tomto.
- Výsledok = priemer metriky naprieč foldami + smerodajná odchýlka.

**Stratified CV** = v každom folde zachová rovnaký pomer tried ako v
celej sade. Potrebné pre nerovnovážne, ale aj pre naše mierne
nevyvážené dáta.

### SMD (Standardized Mean Difference — štandardizovaný rozdiel priemerov)
Efektová veľkosť pre **spojitý** príznak medzi dvomi triedami:
$$ \text{SMD} = \frac{|\mu_1 - \mu_0|}{\sqrt{(\sigma_0^2 + \sigma_1^2)/2}} $$

Hovorí: *o koľko spoločných smerodajných odchýlok sa líšia priemery
dvoch tried.* Cohen's thumb rule:
- SMD < 0.2 → malý efekt,
- 0.2–0.5 → stredný,
- 0.5–0.8 → veľký,
- > 0.8 → veľmi veľký.

Bezrozmerné číslo → porovnateľné medzi príznakmi.

### Cramérove V
Efektová veľkosť pre **dva kategoriálne** príznaky (u nás binárne),
počítaná z chi-squared testu nezávislosti:
$$ V = \sqrt{\chi^2 / (n \cdot (k-1))} $$
kde `k = min(počet riadkov, počet stĺpcov)`. Pre 2×2 tabuľku je V v
intervale [0, 1], 0 = nezávislé, 1 = perfektne závislé. Analogicky
**korelácia** pre binárne dáta.

### VIF (Variance Inflation Factor)
Diagnostika **multikolinearity**: o koľko sa variancia odhadu
koeficientu pre daný príznak *nafúkne* kvôli jeho korelácii s ostatnými
prediktormi.
$$ \text{VIF}_j = \frac{1}{1 - R_j^2} $$
kde $R_j^2$ je koeficient determinácie regresie j-teho prediktora na
ostatných prediktoroch.
- VIF = 1 → príznak je úplne nekorelovaný s ostatnými,
- VIF = 5 → hranica "mierne podozrivej" kolinearity,
- VIF > 10 → vážna kolinearita, odhady koeficientov sú nestabilné,
- VIF > 100 → takmer dokonalá lineárna závislosť, model je pravdepodobne
  degenerovaný.

### Multikolinearita
Stav, keď sú niektoré prediktory navzájom silne lineárne korelované.
Dôsledky:
- Koeficienty lineárnych modelov (LR, LDA) sú numericky nestabilné —
  malá zmena dát vyprodukuje veľkú zmenu koeficientov.
- Individuálne p-hodnoty koeficientov sú vysoké, hoci spoločne
  príznaky vysvetľujú veľkú časť variability.
- Výklad koeficientov (smer vplyvu, dôležitosť) prestáva byť spoľahlivý.

### Skewness (šikmosť)
Tretí štandardizovaný moment rozdelenia. Meria asymetriu:
- skew = 0 → symetrické (napr. normálne),
- skew > 0 → pravý chvost (dlhý chvost hore), napr. dĺžky URL,
- skew < 0 → ľavý chvost.

Pravidlo: |skew| > 2 → "heavily skewed". Ovplyvňuje modely, ktoré
predpokladajú normalitu (LR, LDA, Naive Bayes s Gaussom).

### log1p transformácia
`log1p(x) = log(1 + x)`. Používa sa namiesto `log(x)` pre dáta, ktoré
môžu byť **0** (počty, dĺžky). `log(0) = -∞`, ale `log1p(0) = 0`.
Aproximuje normálne rozdelenie pri pravostrannej šikmosti.

### Z-score (centrovanie a škálovanie, standardization)
$$ z_i = \frac{x_i - \bar{x}}{s_x} $$
Výsledok má priemer 0 a smerodajnú odchýlku 1. Nutné pre:
- **Distance-based metódy** (KNN, SVM s RBF jadrom): ak bez
  štandardizácie, jeden príznak s veľkou škálou (napr. URLLength)
  by úplne dominoval vzdialenosť.
- **Regularizované modely** (Ridge, LASSO): penalizácia na koeficient
  by bola nespravodlivá, ak by mali príznaky rôzne škály.

### Párový Wilcoxonov signed-rank test
Neparametrická alternatíva párového t-testu. Porovnáva **páry**
pozorovaní (napr. AUC modelu A a B na tej istej CV fold), nepotrebuje
predpoklad normality. Testuje, či medián rozdielov je 0 vs. alternatíva.

**Prečo neparametrický?** AUC rozdiely medzi modelmi **nie sú**
zaručene normálne rozdelené, takže t-test by mohol dať zavádzajúcu
p-hodnotu. Wilcoxon je robustný voči neštandardnému rozdeleniu.

### Parametrický vs. neparametrický model
- **Parametrický** = model má pevný, dopredu daný počet parametrov,
  ktorý sa nemení s veľkosťou dát. Predpokladá tvar distribúcie
  (napr. logit → linearita log-odds, LDA → normalita) alebo tvar
  rozhodovacej plochy (nadrovina).
- **Neparametrický** = počet parametrov rastie s dátami, nerobí
  predpoklady o tvare distribúcie. Patria sem stromy / RF (počet
  listov rastie s dátami), KNN (uchováva celú trénovaciu sadu), SVM
  (počet support vectors rastí s dátami).

**Pozor na zmätok:** SVM je "parametrický" v zmysle hyperparametrov
(C, σ), ale **neparametrický** v štatistickom zmysle — nerobí
parametrický predpoklad o rozdelení.

---

## 1. Formulácia problému

### 1.1 Reálny scenár
Používateľ klikne na link. Prehliadač alebo corporate proxy musí
rozhodnúť **pred načítaním** stránky, či ide o phishing. Najlacnejší
signál v danom momente je samotný **text URL** — bez DNS dopytu, bez
stiahnutia HTML, bez vykreslenia.

### Prečo je tento scenár dôležitý
Každý filter v detekčnom reťazci (URL → trust → behavior) stojí rôzne
množstvo prostriedkov:
- **URL-only filter** (Lexical): mikrosekundy, lokálny regex/model.
- **Trust filter**: milisekundy, vyžaduje DNS dopyt, HTTPS handshake.
- **Behavior filter**: stovky milisekúnd, stiahnutie a parsing HTML.

Ak je URL-only dostatočný, môže blokovať najväčšie objemy pred tým,
ako sa platí za drahšie filtre.

### 1.2 Dataset PhiUSIIL
- ~235 000 URL (približne 43 % legitimate, 57 % phishing).
- 50 prediktívnych príznakov.
- Každý príznak patrí do jednej z **troch rodín** (naša taxonómia):

| Rodina | Povaha | Cena získania | Príklad |
|--------|--------|---------------|---------|
| Lexical | vlastnosti URL reťazca | zadarmo | `URLLength`, `NoOfDegitsInURL` |
| Trust | zhoda domény/titulku | nízka (DNS, TLD lookup) | `IsHTTPS`, `HasTitle` |
| Behavior | content stránky | vysoká (fetch + parse) | `NoOfiFrame`, `HasHiddenFields` |

### Dôležité body pre obhajobu
- Rodiny **nie sú vlastnosťou datasetu** — sú to naša dizajnová
  taxonómia podľa **kosts získania signálu**.
- `IsHTTPS` je technicky súčasťou URL (schéma http/https), ale
  zaraďujeme ho do Trust. Dôvod: moderné prehliadače aktívne
  vynucujú HTTPS pri citlivých interakciách, takže je to **trust
  signál**, nie lexikálny tip zadarmo. Ak by sme ho dali do Lexical,
  URLOnly tier by "podvádzal" cez binárku, ktorú v praxi zabezpečuje
  deployment, nie lexikálny obsah URL.

---

## 2. Hypotézy

### H1 (Scenario 2)
*Na URL-only úrovni neparametrické modely získajú štatisticky významne
viac signálu než parametrické.*

**Operacionalizácia:** aby sme sa vyhli vágnemu "významne viac", H1 je
definovaná cez tri konkrétne kritériá:

| Kritérium | Obsah | Prah |
|-----------|-------|------|
| C1 | Rozdiel priemerných CV AUC medzi najlepším neparam. a najlepším param. modelom na Lexical | ≥ 0.02 |
| C2 | Párový Wilcoxonov test na 5 fold-AUCs | p < 0.05 |
| C3 | Gradient: rozdiel na Lexical > rozdiel na Full | gap(Lex) > gap(Full) |

H1 **podporená** iba ak C1 A C2 platia; C3 zosilňuje tvrdenie z
"statement o jednej úrovni" na **gradient**: *"výhoda neparametrických
sa zmenšuje, keď sa príznaková rodina stáva silnejšou"*.

### Prečo 0.02 a nie 0.05 alebo 0.01?
- 0.02 AUC je v literatúre vnímané ako "prakticky významný" rozdiel v
  binárnej klasifikácii.
- Je to **väčšie** ako bežný šum pri 5-foldnej CV na 24 000 trénovacích
  riadkoch (SD AUC ≈ 0.005), takže je štatisticky rozoznateľné.
- Menší prah (0.01) by mohol byť v hladine šumu; väčší (0.05) by bol
  zbytočne prísny — aj 0.03 AUC rozdiel je v bezpečnostnej aplikácii
  rozdielom medzi dobrým a výborným filtrom.

### H2 (Scenario 3)
Embedded výber (LASSO, ElasticNet, RF importance) ponechá **výrazne
menej** príznakov než algoritmický výber (stepwise, RFE), lebo
penalizácia zrazí kolineárne klastre na jedného prežijúceho.

### Prečo očakávame rozdiel medzi embedded a algoritmickým výberom
- **Algoritmický** hľadá kroky po kroku: "pomôže pridanie tohto
  príznaku, ak už mám tamtých?" Ak dva príznaky nesú podobný signál,
  môže si nechať obidva, lebo obidva marginálne pomáhajú.
- **Embedded** optimalizuje spoločnú stratu s penalizáciou. LASSO
  (L1-norm) má geometricky **ostré rohy** v bodoch, kde niektoré
  koeficienty = 0 → rieši rozmenené klastre tak, že ponechá jedného
  reprezentanta a ostatné zrazí na 0.

---

## 3. Načítanie a čistenie dát

### 3.1 Načítanie
UTF-8 BOM stripping: `names(raw) <- map_chr(names(raw), ~ str_replace(.x, "^\ufeff", ""))`.

**Prečo?** Windows/MS Excel často pridáva **Byte Order Mark** na začiatok
UTF-8 súborov. R-kové `read_csv` ho necháva ako súčasť názvu prvého
stĺpca, takže potom `features$FirstColumn` by nefungovalo — skutočný
názov je `"\ufeffFirstColumn"`.

### 3.2 Role stĺpcov
- `ID_COLS` (FILENAME, URL, Domain, TLD, Title) — voľný text, vylučujeme
  ich z modelovania. Surový URL text by sme mohli použiť pre
  character-level NN modely, ale Scenario 2 je o **ručne vytvorených
  numerických príznakoch**.
- `label_bin` = cieľ (Legitimate/Phishing ako faktor).

### 3.3 Vylúčenie príznakov — tri kategórie (KĽÚČOVÉ)

**Toto je pravdepodobne najdôležitejšia sekcia EDA pre obhajobu**, lebo
demonštruje, že sme dataset pochopili a nezačali sme "slepo" modelovať
na všetkých 50 príznakoch.

#### Kategória 1 — vypočítané pravdepodobnosti / skóre
Vylúčené: `URLSimilarityIndex`, `TLDLegitimateProb`, `URLCharProb`,
`DomainTitleMatchScore`, `URLTitleMatchScore`.

**Prečo?** Tieto príznaky **nie sú** surové merania URL. Sú to výstupy
**iných klasifikátorov** alebo expertných heuristík, ktoré v sebe už
nesú phishing-detection logiku. Ak by sme ich nechali v datasete:
- Trénovali by sme model na rozpoznanie "čo si myslí iný model".
- AUC by vyskočil na 0.99+, ale dokázali by sme len to, že *existuje
  lepší klasifikátor a my ho dokážeme napodobniť*, nie že sme porozumeli
  URL.
- H1 (o sile URL signálu) by stratila význam, lebo `URLSimilarityIndex`
  už **je** URL-based klasifikátor.

#### Kategória 2 — redundantný binárny flag
Vylúčené: `HasObfuscation`.

**Prečo?** Definované ako `(NoOfObfuscatedChar > 0)`. Tento flag je
deterministickou funkciou iného príznaku, ktorý v datasete je. Pridáva 0
informácie, len zvyšuje dimenziu.

#### Kategória 3 — redundantné pomery
Vylúčené: `LetterRatioInURL`, `DegitRatioInURL`, `ObfuscationRatio`,
`SpacialCharRatioInURL`.

**Prečo?** Každý z týchto pomerov = `count / URLLength`, pričom **obe
zložky** sú v datasete ako samostatné príznaky. Dôsledky, ak ponecháme:
- **Perfektná lineárna závislosť** → VIF = ∞ → singulárny dizajnmatrix.
- LR / LDA padne alebo vydá numericky nezmyselné koeficienty.
- Aj LASSO by mal problém — nejednoznačná voľba medzi
  `count`, `URLLength`, `ratio`.

### Výsledok po vylúčení
Zostáva **40 prediktorov** (z pôvodných 50): 13 Lexical + 7 Trust + 20 Behavior.

### Možné námietky komisie
- *"Pomerové príznaky môžu niesť iný signál, naozaj sú redundantné?"*
  Nie. Sú to deterministické funkcie dvoch iných príznakov **v rovnakom
  datasete**. Nepridávajú žiadnu informáciu; vytvárajú iba numerickú
  redundanciu.
- *"URLSimilarityIndex predsa silne prediktívny — škoda ho vyhodiť."*
  Presne preto ho musíme vyhodiť. Silne prediktívny **lebo je to výstup
  iného klasifikátora**. Naším cieľom je zhodnotiť silu *surového*
  signálu URL.

---

## 4. Exploratory Data Analysis

### 4.1 Základný prehľad

#### 4.1.1 Rozdelenie tried
Dataset je ~43 % Legitimate / 57 % Phishing → **prakticky vyvážený**.

**Dôsledky:**
- Netreba resampling (SMOTE, undersampling).
- Netreba class-weighting.
- Accuracy je popri AUC platná metrika (pri silnej nevyváženosti, napr.
  99/1, by bola zavádzajúca).

#### 4.1.2 Chýbajúce hodnoty
Žiadne. Overené cez `colSums(is.na(features))`. Nepotrebujeme imputáciu
ani missing-indicator príznaky.

### 4.2 Diskriminačná sila príznakov — príprava H1

Pre každý príznak meriame, ako dobre oddeľuje triedy **sám o sebe**.

#### Prečo sa počíta dvomi rôznymi mierami?
SMD je zmysluplné iba pre spojité premenné (vyžaduje mean, SD). Pre
binárne premenné "pooled SD" degeneruje na funkciu marginálnej
proporcie a SMD stratí porovnateľnosť. **Cramérove V** je štandardná
efektová veľkosť pre 2×2 kontingenčnú tabuľku, ktorá býva v rovnakom
intervale [0,1] ako |korelácia|.

#### Kľúčový výsledok
Medián |SMD| je **najnižší v rodine Lexical**. To znamená:
- Žiaden jednotlivý lexikálny príznak sám osebe dobre neoddeľuje triedy.
- Klasifikátor musí **kombinovať viacero príznakov**.
- Lineárny model (LR, LDA) má na kombinácie menej flexibility ako RF
  alebo SVM s RBF jadrom.

**Toto je EDA dôkaz na podporu H1.** Neukazuje priamo nelinearitu, ale
ukazuje, že úloha vyžaduje viacrozmerné rozhodovanie, kde majú
neparametrické modely prirodzenú výhodu.

### 4.3 Multikolinearita — príprava H2

#### 4.3.1 Korelačná matica Lexical príznakov
Vizualizuje klaster korelovaných príznakov:
- `URLLength ↔ NoOfLettersInURL ↔ NoOfDegitsInURL` → r > 0.84.
- Tieto tri počty v podstate merajú to isté: "veľká URL".

Naprieč celou maticou je **10 dvojíc** s |r| > 0.7 a **všetkých 10**
leží v tomto Lexical klastri. Trust a Behavior rodiny majú
`mean_abs_r ≈ 0.18` a `0.14` — nemajú problematický klaster.

#### 4.3.2 VIF — Variance Inflation Factor
(Definícia v slovníku §0.)

**Namerané hodnoty:**
- `URLLength` ~ VIF > 500,
- `NoOfLettersInURL` ~ VIF > 500,
- `NoOfDegitsInURL` ~ VIF > 200.

Binárne príznaky zámerne vylúčené z VIF výpočtu, lebo lineárna regresia
binárneho indikátora na spojitých prediktoroch nie je v rovnakej škále
informatívna.

#### Prečo je to dôležité pre H2
- **Algoritmické metódy** (stepwise, RFE) pridávajú/odoberajú jeden
  príznak naraz. Každý z troch kolineárnych príznakov prináša marginálny
  signál, takže sa často všetky tri udržia v konečnom modeli.
- **Embedded metódy** (LASSO, ElasticNet) s L1 penalizáciou hľadajú
  riedke riešenia. V klastri troch takmer identických príznakov je
  optimálne ponechať **jedného reprezentanta** a ostatné zraziť na 0.

### 4.4 Šikmosť

19 z 22 spojitých príznakov má |skew| > 2 — silne pravostranný chvost
(napr. väčšina URL je kratšia ako 100 znakov, ale existujú stovky
znakových "obludiek").

**Dôsledky pre modely:**
- **LR, LDA, NB-Gauss**: predpokladajú ± normalitu prediktorov →
  nevyhnutný `log1p` + center/scale transform.
- **Trees, RF**: invariantné na monotónne transformácie (rozhodnutie
  `x < 100` je ekvivalentné `log(x) < log(100)`) → transform zbytočný.
- **SVM, KNN**: distance-based, vyžadujú štandardizáciu. Bez nej by
  príznak s veľkou škálou (URLLength v stovkách) úplne dominoval
  vzdialenosti a ostatné (napr. TLDLength v jednotkách) by boli
  ignorované.

---

## 5. Zhrnutie EDA a implikácie pre modelovanie

### Near-perfect separabilita na Full tier
Po vylúčení scores v §3.3 stále platí, že na Full (40 príznakov) každý
typ modelu dosahuje AUC ≈ 0.99. Dôsledky:
- **H1 testujeme primárne na URLOnly (Lexical, 13 príznakov)**, kde
  modely skutočne líšia.
- H2 testujeme na Full, kde kolinearita driftujúca rozdiel embedded vs.
  algoritmický výber skutočne existuje.

### Implikácie pre Scenario 2 (H1)
| Zistenie z EDA | Implikácia pre modelovanie |
|----------------|----------------------------|
| Near-perfect AUC na Full | Testujeme H1 primárne na Lexical |
| Najnižšie SMD v Lexical | Najväčší param. vs. neparam. rozdiel sa čaká tu |
| Šikmosť v 19 z 22 príznakov | Log + scale pre LR/LDA/NB/SVM/KNN; RF bez transform |
| VIF > 500 | Ridge-regularizovaná LR na fairnej stabilite |

### Implikácie pre Scenario 3 (H2)
| Zistenie z EDA | Implikácia |
|----------------|------------|
| Kolineárny klaster URLLength/NoOfLetters/NoOfDegits | Najsilnejší test pre algoritmický vs. embedded výber |
| Trust binárky majú nízku vzájomnú koreláciu | Pravdepodobne sa zachovajú v **obidvoch** prístupoch (prekryv) |

---

## 6. Typické otázky komisie a návrhy odpovedí

**Q: Prečo ste nepoužili PCA na zníženie kolinearity?**
A: PCA by zničilo interpretovateľnosť — principálne komponenty sú
lineárne kombinácie pôvodných príznakov a nedá sa pekne povedať "je to
phishing preto, že PC3 = 2.7". Pre bezpečnostnú aplikáciu je
interpretovateľnosť dôležitá (audit, vysvetlenie používateľovi). H2 je
navyše **presne o tom**: porovnať dva prístupy k feature selection,
ktoré *zachovávajú* pôvodné príznaky.

**Q: Prečo nie SMOTE, keď signál v Lexical je slabý?**
A: Slabosť signálu ≠ class imbalance. Dataset je vyvážený (43/57);
SMOTE by nič nepomohlo. Problém je, že per-feature SMD je malé —
triedy sú ťažko rozlíšiteľné aj pri dostatku príkladov. Riešenie je
**lepší model** (neparametrický), nie viac dát.

**Q: Prečo ste vylúčili `URLSimilarityIndex`? Je to silný prediktor.**
A: Presne preto. Je to výstup iného klasifikátora, nie surové meranie
URL. Modelovať by sme potom kvalitu toho klasifikátora, nie URL. Cieľ
H1 je zhodnotiť signál v **surovom** URL reťazci.

**Q: Prečo AUC a nie iná metrika?**
A: Tri dôvody: (1) prahovo nezávislá, (2) interpretovateľná ako
P(score(phishing) > score(legit)) pre náhodné páry, (3) dataset je
vyvážený, takže AUC nie je zavádzajúca (na 99/1 dátach by bola).

**Q: Ako viete, že rozdiely medzi foldami nie sú iba náhodný šum?**
A: Párový Wilcoxonov test + veľkosť efektu. Na Lexical diff ≈ 0.10
AUC, čo je násobok SD per-fold AUC (~0.005). S 5 foldami je minimálne
dosiahnuteľné p = 1/32 ≈ 0.031 (dolná podlaha testovej štatistiky), čo
dosahujú všetky úrovne okrem FullLite. Detailnejšia diskusia v Scenario 2 §6.2.

**Q: Čo v budúcnosti? Je 235 k URL reprezentatívnych?**
A: PhiUSIIL je zhromaždený v jednom časovom okne (~2021), takže
nemodeluje časový drift phishing kit autorov. V produkčnom nasadení by
bol potrebný kontinuálny retraining. Toto je limitácia, ktorú
priznávame.

---

## 7. Návrhy ďalšej práce

### Rozšírenia dát a príznakov
1. **Word-piece / character n-gram embeddingy URL** — jemný Lexical
   signál, ktorý náš ručne vytvorený count-set iba hrubo aproximuje.
2. **Doménovo podložené feature engineering** — napr. Levenshteinova
   vzdialenosť URL od top-1000 brandových domén
   (apple.com → aple.com). Pozor: toto nepatrí do Lexical (vyžaduje
   externý lookup), ale do Trust.
3. **Časové trendy** — phishing kit autori sa prispôsobujú. Retraining,
   detekcia driftu, sliding-window validation.

### Rozšírenia modelovania
4. **Character-level CNN / Transformer** nad surovým URL textom.
   Eliminoval by potrebu ručne navrhnutých count príznakov.
5. **Adversariálne testovanie** — simulovať homoglyph útok (cyrilic `а`
   namiesto latin `a`), URL encoding, subdomain padding. Merať pokles
   AUC nášho filtra.
6. **Kalibrácia pravdepodobností** (Platt scaling, isotonic regression).
   AUC hovorí o ordinálnom skóre, ale pre threshold-based rozhodovanie
   v produkcii potrebujeme dobre kalibrované P(phishing).
7. **Multi-class extension** — okrem Legitimate/Phishing rozlíšiť typ
   phishing kampaňe (bank, crypto, social). Phishing rodina je v
   datasete označiteľná pomocou `Bank`, `Pay`, `Crypto` flagov.

### Rozšírenia metodiky
8. **Repeated k-fold CV** (napr. 5×5 = 25 foldov) — odstráni podlahu
   p-hodnoty 1/32 a umožní jemnejšie rozlíšenie efektov medzi úrovňami.
9. **Nested CV** pre hyperparameter tuning — externá slučka na odhad
   výkonu, vnútorná na voľbu parametrov. Metodologicky správnejšie, ale
   výpočtovo drahšie.
10. **BCa bootstrap** pre 95 % intervaly spoľahlivosti AUC, nielen
    mean ± SD.
