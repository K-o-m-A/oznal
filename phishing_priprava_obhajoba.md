# Príprava na obhajobu — `phishing.rmd` (EDA a hypotézy)

---

## Úvod pre čitateľa bez strojového učenia

**O čom projekt je, ľudskou rečou.** Keď vám niekto pošle link, váš
firemný bezpečnostný filter (proxy) sa musí v zlomku sekundy rozhodnúť,
či stránku otvoriť alebo zablokovať. Najrýchlejšie vie pozrieť iba
samotnú adresu URL — bez toho, aby stránku stiahol. Otázka práce znie:
**stačí na rozoznanie phishingu pozrieť len text URL, alebo treba
aj obsah stránky?**

**Čo je hypotéza a prečo ich testujeme dve.**
- **H1 (Scenario 2)** skúma, *ktorý typ modelu* si poradí lepšie na
  slabom signáli (len URL). Modely delíme na „parametrické" (jednoduchší
  tvar, napr. regresia) a „neparametrické" (flexibilnejšie, napr. les
  rozhodovacích stromov). Tušíme, že keď je signál slabý, zložitejšie
  modely dokážu vyťažiť viac.
- **H2 (Scenario 5)** skúma, *ako drahé je zjednodušenie dát* (PCA =
  stlačenie mnohých stĺpcov do pár hlavných „smerov"). Keď je signál
  skrytý v kombináciách príznakov, stlačenie ho pokazí; keď je signál
  priamočiary, stlačenie je lacné.

**Čo je EDA a prečo je prvá.** *Exploratory Data Analysis* = pozriem sa
na dáta **predtým**, ako trénujem model. Spočítam základné štatistiky,
nakreslím grafy, pozriem koreláciu. Zmyslom je rozhodnúť, čo z dát má
zmysel do modelu dať, čo treba transformovať, a či hypotézy, ktoré chcem
testovať, majú vôbec v dátach základ. Bez EDA je modelovanie hádanie
naslepo.

---

## 0. Slovník pojmov — čo všetky skratky znamenajú

### AUC (Area Under the ROC Curve — plocha pod ROC krivkou)
**Najdôležitejšia metrika v tomto projekte.**

*Ľudskou rečou:* náhodne ťahám jednu phishing a jednu legitimate URL.
AUC hovorí, aká je pravdepodobnosť, že model dá phishingovej stránke
vyššie skóre ako legitímnej. AUC = 0.5 je mincovka, AUC = 1.0 je
dokonalý model. V bezpečnosti sú rozdiely typu 0.97 vs. 0.99 obrovské —
na miliónoch URL denne to robí státisíce chýb ročne.

- **Binárny klasifikátor** (model, ktorý predikuje jednu z dvoch tried —
  u nás phishing vs. legitimate) vracia pre každý príklad
  pravdepodobnosť P(phishing). Aby sme spravili tvrdé rozhodnutie,
  potrebujeme **prah** (napr. predikuj "phishing", ak P > 0.5).
- **ROC krivka** (Receiver Operating Characteristic) vykresľuje pre
  **všetky možné prahy** dvojicu:
  - os X: False Positive Rate = FP / (FP + TN) = aká časť legitimate
    stránok je chybne označená ako phishing,
  - os Y: True Positive Rate = TP / (TP + FN) = aká časť phishing
    stránok je správne odhalená.
  *Intuícia:* každý bod krivky zodpovedá jednému prahu. Ak prah zvýšim,
  model je prísnejší → menej phish zachytím, ale aj menej legit
  prezlobím (pohyb doľava-dole). Ak znížim, opak.
- **AUC** = integrál pod touto krivkou, hodnota medzi 0 a 1.
  - AUC = 1.0 → dokonalý klasifikátor,
  - AUC = 0.5 → náhodné hádanie,
  - AUC = 0.9 → výborný klasifikátor,
  - AUC = 0.8 → dobrý klasifikátor.
- **Prečo práve AUC a nie Accuracy?**
  1. AUC je **prahovo nezávislá**: porovnáva kvalitu *skóre*, nie
     konkrétneho rozhodnutia. Accuracy závisí od toho, kde nastavíme
     prah — ak ho zmeníme, accuracy vyskočí alebo klesne, ale model
     samotný sa nezlepšil. AUC tento efekt odstraňuje.
  2. AUC má štatistickú interpretáciu: *pravdepodobnosť, že náhodne
     vybraná phishing URL dostane vyššie skóre ako náhodne vybraná
     legitimate URL.*
  3. Na približne vyváženom datasete (43/57) sú AUC aj Accuracy
     informatívne, ale AUC sa nemení pri zmene prahu.


### FPR, TPR, Accuracy, Precision, Recall, F1
Základné metriky klasifikácie, všetky počítané z matice zámien
(confusion matrix — tabuľka, ktorá sčíta, ako často sa model pomýlil
v každom z dvoch možných smerov):

|              | skutočne Phishing | skutočne Legitimate |
|--------------|-------------------|---------------------|
| predikované Phishing   | **TP** (true positive) | **FP** (false positive) |
| predikované Legitimate | **FN** (false negative) | **TN** (true negative) |

*Ľudskou rečou:* TP = správne zablokovaný phish, FP = zablokovaná
nevinná stránka (používateľ zúri), FN = phish prešiel (používateľ
príde o heslo), TN = legit stránka prešla (normálny deň).

- **Accuracy** = (TP + TN) / (TP + FP + TN + FN) — aká časť predikcií je
  správna. *V praxi:* „v koľkých percentách prípadov má model pravdu."
- **Precision** = TP / (TP + FP) — zo všetkých, ktoré sme označili za
  phishing, aká časť naozaj phishingom je. *V praxi:* „keď model
  povie poplach, ako často má pravdu." Nízka Precision = veľa falošných
  poplachov, používatelia prestanú filtru veriť.
- **Sensitivity** (= Recall = True Positive Rate) = TP / (TP + FN) — zo
  všetkých skutočných phishing, koľko sme zachytili. *V praxi:*
  „koľko zlých stránok sme chytili z tých, čo tam naozaj boli." Nízka
  Sensitivity = phishing prešiel k používateľovi.
- **Specificity** (= True Negative Rate) = TN / (TN + FP) — zo všetkých
  legitímnych, koľko sme ich nesprávne neoznačili. *V praxi:* „ako často
  necháme nevinnú stránku na pokoji." Nízka Specificity = veľa falošných
  blokov.
- **F1** = harmonický priemer Precision a Recall =
  2·P·R / (P + R). Balancuje FP a FN chyby. *Prečo harmonický, nie
  aritmetický?* Aritmetický priemer 0.99 a 0.01 je 0.5, čo znie ako
  priemerný model — ale model, ktorý má Recall 0.01, je k ničomu.
  Harmonický priemer 0.99 a 0.01 je ≈ 0.02, čo odzrkadľuje realitu:
  keď jedno zo dvoch čísel skolabuje, F1 skolabuje s ním. F1 teda
  odhalí „polovičato použiteľné" modely, ktoré Accuracy skryje.

### Cross-Validation (CV, krížová validácia)
Metóda odhadu, ako dobre sa bude model chovať na neuvidených dátach.

*Ľudskou rečou:* nestačí otestovať model iba na jednom testovom balíku
— môže sa stať, že nám náhodou „padli" tie ľahšie URL do testu a
výsledok je krajší, než by model v realite zvládol. CV rozbije dáta na
10 približne rovnako veľkých kôpok, každú raz použije ako test (a
ostatných 9 na tréning), výsledky spriemeruje. Tým dostaneme
**10 odhadov** kvality namiesto jedného a vidíme aj **rozptyl** —
stabilný model má malý rozptyl, vrtkavý veľký.

Trénovacie dáta sa rozdelia na **k** rovnako veľkých častí (foldov):
- Pre každý fold: trénuj na zvyšných k-1 foldoch, vyhodnoť na tomto.
- Výsledok = priemer metriky naprieč foldami + smerodajná odchýlka.

**Stratified CV** = v každom folde zachová rovnaký pomer tried ako v
celej sade. Potrebné pre nerovnovážne, ale aj pre naše mierne
nevyvážené dáta. *Bez stratifikácie* by sa mohlo stať, že jeden fold
má napr. 90 % phish, iný 30 % — výsledky by boli nezmyselne rozhádzané.

**Prečo práve 10 foldov?** Kompromis medzi presnosťou odhadu (viac
foldov → menej šumu) a výpočtovým časom (viac foldov → viac tréningov).
10 je v literatúre de-facto štandard; pri 10 000+ trénovacích riadkoch
dáva veľmi stabilné odhady. *V práci sme začínali s 5, ale pri malom
počte foldov sa párový Wilcoxonov test rýchlo „zarazí" o minimálnu
dosiahnuteľnú p-hodnotu — viac v §6.*

### SMD (Standardized Mean Difference — štandardizovaný rozdiel priemerov)
Efektová veľkosť (effect size = miera, aký veľký je rozdiel, ktorú
neovplyvňuje veľkosť vzorky — na rozdiel od p-hodnoty) pre **spojitý**
príznak medzi dvomi triedami:
$$ \text{SMD} = \frac{|\mu_1 - \mu_0|}{\sqrt{(\sigma_0^2 + \sigma_1^2)/2}} $$

*Ľudskou rečou:* „o koľko sa priemer phishing URL líši od priemeru
legit URL, ak sa na to pozerám v jednotkách typického rozptylu v rámci
triedy." SMD = 1 znamená, že priemery sú od seba vzdialené presne
jednu smerodajnú odchýlku — vizuálne: dva zvony rozdelenia sa síce
prekrývajú, ale sú jasne posunuté.

Hovorí: *o koľko spoločných smerodajných odchýlok sa líšia priemery
dvoch tried.* Cohen's thumb rule (pravidlo Jacoba Cohena, psychológa
ktorý tieto hranice zaviedol v 80. rokoch):
- SMD < 0.2 → malý efekt (rozdelenia sa skoro prekrývajú),
- 0.2–0.5 → stredný,
- 0.5–0.8 → veľký,
- > 0.8 → veľmi veľký (rozdelenia sú viditeľne oddelené).

Bezrozmerné číslo → porovnateľné medzi príznakmi. *Prečo nie rovno
rozdiel priemerov v pôvodných jednotkách?* Lebo `URLLength` (v
znakoch) a `NoOfSubDomain` (počet) majú iné škály; bez normalizácie by
dlhšie URL dostávali umelo väčšiu „váhu".

### Cramérove V
Efektová veľkosť pre **dva kategoriálne** príznaky (u nás binárne —
hodnoty 0/1, napr. `HasTitle`, `Bank`, `IsHTTPS`), počítaná z
chi-squared testu nezávislosti:
$$ V = \sqrt{\chi^2 / (n \cdot (k-1))} $$
kde `k = min(počet riadkov, počet stĺpcov)`. Pre 2×2 tabuľku je V v
intervale [0, 1], 0 = nezávislé, 1 = perfektne závislé. Analogicky
**korelácia** pre binárne dáta.

*Ľudskou rečou:* keby som rozdelil URL na phish a legit a pozrel sa,
v koľkých percentách má každá z nich `HasTitle = 1`, Cramérove V meria,
ako silne sa tie percentá líšia. V = 0 znamená „obe triedy majú titulok
rovnako často, príznak nič nehovorí"; V ≈ 1 znamená „phishing skoro
nikdy nemá titulok, legit skoro vždy má — dokonalý rozlišovač".

*Prečo nie obyčajná korelácia?* Pearson korelácia pre binárne dáta
**technicky** funguje (vyjde „phi koeficient"), ale interpretácia je
menej intuitívna a pre nebinárne kategoriálne premenné úplne padá.
Cramérove V je všeobecnejšia forma, ktorá sa škáluje rovnako na
2×2 aj na 5×3 tabuľky.

### VIF (Variance Inflation Factor)
Diagnostika **multikolinearity**: o koľko sa variancia odhadu
koeficientu pre daný príznak *nafúkne* kvôli jeho korelácii s ostatnými
prediktormi.
$$ \text{VIF}_j = \frac{1}{1 - R_j^2} $$
kde $R_j^2$ je koeficient determinácie (podiel variability j-teho
príznaku, ktorý sa dá vysvetliť ostatnými) regresie j-teho prediktora na
ostatných prediktoroch.

*Ľudskou rečou:* VIF 10 znamená, že odhad váhy daného príznaku je
10-krát „nestabilnejší", než by bol, keby bol príznak nezávislý od
ostatných. Prakticky: ak pridám alebo odoberiem pár URL z tréningu,
koeficient pri kolineárnom príznaku sa môže drasticky zmeniť —
model mi nepovie nič o „skutočnom vplyve" tohto príznaku.

- VIF = 1 → príznak je úplne nekorelovaný s ostatnými,
- VIF = 5 → hranica "mierne podozrivej" kolinearity,
- VIF > 10 → vážna kolinearita, odhady koeficientov sú nestabilné,
- VIF > 100 → takmer dokonalá lineárna závislosť, model je pravdepodobne
  degenerovaný.

### Multikolinearita
Stav, keď sú niektoré prediktory navzájom silne lineárne korelované.

*Ľudskou rečou:* dva príznaky, ktoré vlastne merajú to isté (napr.
`URLLength` v znakoch a `NoOfLettersInURL` v počte písmen — väčšina
URL je text, takže tieto dve čísla sú takmer identické). Model má
problém rozhodnúť, „ktorému z týchto dvojičiek" prisúdiť váhu, a
výsledok je rozdelený náhodne medzi nimi.

Dôsledky:
- Koeficienty lineárnych modelov (LR, LDA) sú numericky nestabilné —
  malá zmena dát vyprodukuje veľkú zmenu koeficientov.
- Individuálne p-hodnoty koeficientov sú vysoké, hoci spoločne
  príznaky vysvetľujú veľkú časť variability.
- Výklad koeficientov (smer vplyvu, dôležitosť) prestáva byť spoľahlivý.
- *Čo to NEznamená:* prediktívny výkon modelu (AUC, Accuracy) zvyčajne
  netrpí — model stále vie predpovedať. Trpí len *interpretácia*
  jednotlivých váh.

### Skewness (šikmosť)
Tretí štandardizovaný moment rozdelenia. Meria asymetriu:
- skew = 0 → symetrické (napr. normálne rozdelenie — zvon),
- skew > 0 → pravý chvost (dlhý chvost hore), napr. dĺžky URL,
- skew < 0 → ľavý chvost.

*Ľudskou rečou:* väčšina URL má napr. 40–80 znakov, ale existuje zopár
obluďakov so 700 znakmi — histogram vyzerá ako skala s dlhým „ocasom"
doprava. To je pravostranná (pozitívna) šikmosť. Linearizovaným
modelom (LR, LDA) ten ocas pokazí odhad priemeru a rozptylu, akoby ich
„niekto potiahol za chvost".

Pravidlo: |skew| > 2 → "heavily skewed". Ovplyvňuje modely, ktoré
predpokladajú normalitu (LR, LDA, Naive Bayes s Gaussom).

### log1p transformácia
`log1p(x) = log(1 + x)`. Používa sa namiesto `log(x)` pre dáta, ktoré
môžu byť **0** (počty, dĺžky). `log(0) = -∞`, ale `log1p(0) = 0`.
Aproximuje normálne rozdelenie pri pravostrannej šikmosti.

*Ľudskou rečou:* logaritmus „stlačí" veľké čísla. URL s 40 znakmi ostane
blízko hodnoty 3.7, ale URL so 700 znakmi klesne na ~6.6 namiesto 700 —
rozdiel medzi „normálnou" a „obrovskou" URL sa zmenší z ~17× na ~1.8×.
Histogram po log-transformácii vyzerá podstatne bližšie k zvonu, čo
parametrické modely potrebujú.

### Z-score (centrovanie a škálovanie, standardization)
$$ z_i = \frac{x_i - \bar{x}}{s_x} $$
Výsledok má priemer 0 a smerodajnú odchýlku 1.

*Ľudskou rečou:* premením hodnoty tak, aby každý príznak bol vyjadrený
v „koľko smerodajných odchýlok od svojho priemeru". Tým zrušíme vplyv
jednotiek (znaky vs. počet bodiek) a škál.

Nutné pre:
- **Distance-based metódy** (KNN, SVM s RBF jadrom — modely, ktoré
  fungujú na vzdialenosti medzi bodmi): ak bez štandardizácie, jeden
  príznak s veľkou škálou (napr. URLLength v stovkách) by úplne
  dominoval vzdialenosť a `TLDLength` (v jednotkách) by bol ignorovaný.
- **Regularizované modely** (Ridge, LASSO — modely, ktoré „trestajú"
  veľké koeficienty, aby model nepreučil): penalizácia na koeficient by
  bola nespravodlivá, ak by mali príznaky rôzne škály — väčšia škála by
  dostala umelo menší koeficient.

### Párový Wilcoxonov signed-rank test
Neparametrická alternatíva párového t-testu. Porovnáva **páry**
pozorovaní (napr. AUC modelu A a B na tej istej CV fold), nepotrebuje
predpoklad normality. Testuje, či medián rozdielov je 0 vs. alternatíva.

*Ľudskou rečou:* mám 10 foldov a na každom AUC dvoch modelov. Spočítam
rozdiel A−B pre každý fold → 10 rozdielov. Ak sú všetky kladné, je
veľmi nepravdepodobné, že A a B sú rovnako dobré. Wilcoxon presne
vyčísli tú nepravdepodobnosť pomocou poradia rozdielov (nie ich
hodnôt), čo je robustné voči extrémom.

**Prečo neparametrický?** AUC rozdiely medzi modelmi **nie sú**
zaručene normálne rozdelené, takže t-test by mohol dať zavádzajúcu
p-hodnotu. Wilcoxon je robustný voči neštandardnému rozdeleniu.

**Minimálna dosiahnuteľná p-hodnota závisí od počtu foldov.** Pri
n párovaných pozorovaniach je pre jednostranný test floor
≈ `1/2^n` (najextrémnejšia možná konfigurácia — všetkých n rozdielov
má rovnaké znamienko). Pre 5 foldov → 1/32 ≈ 0.031, pre 10 foldov →
1/1024 ≈ 0.001. Preto má zmysel mať dosť foldov — pri malom počte
by sa aj „jasné víťazstvá" zarazili o ten istý floor a test by
nerozlišoval.

### Parametrický vs. neparametrický model
- **Parametrický** = model má pevný, dopredu daný počet parametrov,
  ktorý sa nemení s veľkosťou dát. Predpokladá tvar distribúcie
  (napr. logit → linearita log-odds, LDA → normalita) alebo tvar
  rozhodovacej plochy (nadrovina — rovná „čiara" v priestore príznakov,
  ktorá oddeľuje triedy).
- **Neparametrický** = počet parametrov rastie s dátami, nerobí
  predpoklady o tvare distribúcie. Patria sem stromy / RF (počet
  listov rastie s dátami), KNN (uchováva celú trénovaciu sadu), SVM
  (počet support vectors rastí s dátami).

*Ľudskou rečou:* parametrický model je ako šablóna — má pevný tvar
a dáta iba „dotvoria" jeho parametre. Neparametrický je ako plastelína
— tvar si vyrobí priamo podľa dát, bez predpokladu ako to má
vyzerať. Plastelína je flexibilnejšia (lepšie zachytí kľukaté
vzorce), ale stojí viac pamäte a času.

**Analógia:** Predstav si, že učíš niekoho rozpoznať chutný vs.
nechutný koláč.
- **Parametrický prístup:** „Chutnosť = 0.4·(sladkosť) + 0.3·(mäkkosť) +
  0.3·(vôňa)." Jednoduchá formulka, pevné váhy, funguje pri
  priamočiarom vzorci.
- **Neparametrický prístup:** „Ak sladkosť > 7 a mäkkosť > 5, je
  chutný. Ak sladkosť > 7 ale mäkkosť < 5, záleží od vône." Rozvetvené
  pravidlá, ktoré si model odvodí sám — funguje aj keď je vzťah
  zložitý.

**Pozor na zmätok:** SVM je "parametrický" v zmysle hyperparametrov
(C, σ), ale **neparametrický** v štatistickom zmysle — nerobí
parametrický predpoklad o rozdelení.

### PCA (Principal Component Analysis, analýza hlavných komponentov)
Technika, ktorá z mnohých korelovaných príznakov vyrobí **menší počet
nových príznakov** (tzv. hlavných komponentov, PC), z ktorých každý je
lineárnou kombináciou pôvodných a ktoré sú medzi sebou **nekorelované**.

*Ľudskou rečou:* Predstav si, že máš 40 meradiel URL a mnohé z nich
merajú skoro to isté (dĺžka, počet písmen, počet číslic — všetky rastú
s „veľkosťou URL"). PCA nájde skrytú os „veľkosť URL" a stlačí tie
vzájomne závislé merania do jedného čísla. Urobí to pre každú
„nezávislú dimenziu variability" v dátach. Výsledok: pár nových
súradníc namiesto pôvodných 40.

- **PC1** je smer, v ktorom sa dáta najviac líšia (najväčšia variabilita).
- **PC2** je smer kolmý na PC1 s druhou najväčšou variabilitou. Atď.
- **Variance explained** = koľko percent pôvodnej variability dát daná
  os zachytáva. Scree plot to vykresľuje kumulatívne.

**Dôležité a kontraintuitívne:** PCA hľadá smery **najväčšej
variability**, nie smery, ktoré najlepšie oddeľujú triedy. Tie dve
veci nemusia súhlasiť — os s najväčšou varianciou môže biť kolmá na
os, kde sa phish oddelí od legit. Preto v EDA dopĺňame scree plot
o „AUC každého PC" — aby sme videli, kde žije trieda, nie len kde je
variabilita.

### LDA projekcia (Linear Discriminant Analysis ako dimenzionality reduction)
Podobne ako PCA zmenší počet rozmerov, ale **s využitím triednej
informácie** — hľadá os, na ktorej sú priemery tried od seba čo
najďalej vzhľadom na ich vnútroskupinový rozptyl.

*Ľudskou rečou:* PCA si povie „kde sú dáta najviac rozhádzané", LDA
si povie „kde je phish vs. legit najviac oddelený". Pre binárnu
klasifikáciu LDA vyrobí iba jednu jedinú os (dve triedy → k−1 = 1
smer), ale často je to tá najužitočnejšia os pre klasifikáciu.

### Stratifikovaný split (stratified split / sampling)
Delenie dát na tréning a test tak, aby **pomer tried** ostal v oboch
častiach rovnaký ako v celej sade.

*Ľudskou rečou:* keby som dáta jednoducho zamiešal a odrezal prvých
80 %, mohlo by sa stať, že phish a legit sa rozložia nerovnomerne.
Stratifikácia to nedovolí: zvlášť zamiešam phish, zvlášť legit, a z
každej skupiny odoberiem 80 %. V scenario_2 ideme ešte ďalej — na
začiatku si cielene vyberieme **presne 15 000 phish + 15 000 legit**,
takže test set je nútene 1:1. Tento detail sa vráti pri výpočte
Precision (§6 Q na konci).

### Overfitting (preučenie modelu)
Model sa „naučí naspamäť" trénovaciu sadu vrátane jej šumu, takže na
tréningu má skvelé výsledky, ale na nových dátach padne.

*Ľudskou rečou:* ako keby sa študent nabifľoval odpovede z jedného
konkrétneho testu — na tom teste dostane 100 %, ale na inom teste s
rovnakou látkou prepadne, lebo otázky sú formulované inak.

**Ako to detekujeme?** Porovnaním **Train AUC** vs. **Test AUC** (alebo
Train vs. CV AUC). Veľká medzera = overfit; podobné čísla = zdravý
model. Modelovacia časť projektu zámerne reportuje train aj test AUC,
aby sa nič nezatajilo.

### Leakage (únik informácie, data leakage)
Keď sa do modelu dostane informácia, ktorá by v produkcii nebola
dostupná (napr. výstup iného klasifikátora ako príznak) alebo ktorá
nepriamo prezrádza cieľ. Dôsledok: model vyzerá lepšie, ako v
skutočnosti je.

*V našom projekte:* `URLSimilarityIndex` je sám výstup detekčného
modelu — keby sme ho nechali ako príznak, „podvádzali" by sme. Šesť
Behavior počtov (`LineOfCode` atď.) má univariátne AUC > 0.95, čiže
sami o sebe skoro dokonale oddeľujú phish od legit — tzv. **near-leakers**:
nie je to technicky leakage, ale také silné indikátory, že model sa nič
iné nenaučí. Preto v scenario_2 používame ich oklieštenú verziu
(**FullLite**).

---

## 1. Formulácia problému

### 1.1 Reálny scenár
Používateľ klikne na link. Prehliadač alebo corporate proxy (= firemný
server, ktorý kontroluje web prevádzku zamestnancov) musí rozhodnúť
**pred načítaním** stránky, či ide o phishing (podvodnú stránku, ktorá
sa vydáva za dôveryhodnú s cieľom vylákať heslá alebo platobné údaje).
Najlacnejší signál v danom momente je samotný **text URL** — bez DNS
dopytu (preklad `banka.sk` → IP adresa), bez stiahnutia HTML, bez
vykreslenia.

*Ľudskou rečou:* proxy je strážnik pri bráne firemnej siete. Každú
sekundu musí otvoriť tisíce balíčkov (URL) a rozhodnúť: pustiť dnu,
alebo zahodiť. Nemá čas každý rozbaliť — tak najprv iba pozrie
„adresu na obálke" (samotný text URL). Otázka, ktorú projekt rieši:
**stačí strážnikovi adresa na obálke, alebo musí balíček aj otvoriť?**

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

*Ľudskou rečou:* keď má model k dispozícii iba text URL (bez obsahu
stránky, bez DNS), signál na rozlíšenie phish vs. legit je slabý a
skrytý v **kombináciách** príznakov (napr. „URL dlhšia ako 100 znakov
s viac ako 3 subdoménami a s číslicami v prvých 10 znakoch"). Modely
typu lineárna regresia také kombinácie nedokážu dobre zachytiť —
narozdiel od lesa rozhodovacích stromov, ktorý si pravidlá „ak-tak"
vytvorí sám. H1 tvrdí, že v slabom režime (URL-only) je ten rozdiel
viditeľný, nie len náhodný šum.

**Operacionalizácia (= preklad vágneho „významne viac" do konkrétnych
overiteľných čísel):** aby sme sa vyhli vágnemu "významne viac", H1 je
definovaná cez tri konkrétne kritériá:

| Kritérium | Obsah | Prah |
|-----------|-------|------|
| C1 | Rozdiel priemerných CV AUC medzi najlepším neparam. a najlepším param. modelom na Lexical | ≥ 0.02 |
| C2 | Párový Wilcoxonov test na 10 fold-AUCs | p < 0.05 |
| C3 | Gradient: rozdiel na Lexical > rozdiel na FullLite | gap(Lex) > gap(FullLite) |

H1 **podporená** iba ak C1 A C2 platia; C3 zosilňuje tvrdenie z
"statement o jednej úrovni" na **gradient**: *"výhoda neparametrických
sa zmenšuje, keď sa príznaková rodina stáva silnejšou"*.

### Prečo 0.02 a nie 0.05 alebo 0.01?
- 0.02 AUC je v literatúre vnímané ako "prakticky významný" rozdiel v
  binárnej klasifikácii.
- Je to **väčšie** ako bežný šum pri 10-foldnej CV na 24 000 trénovacích
  riadkoch (SD AUC ≈ 0.005), takže je štatisticky rozoznateľné.
- Menší prah (0.01) by mohol byť v hladine šumu; väčší (0.05) by bol
  zbytočne prísny — aj 0.03 AUC rozdiel je v bezpečnostnej aplikácii
  rozdielom medzi dobrým a výborným filtrom.

### H2 (Scenario 5)
*Cena lineárnej redukcie dimenzionality nie je rovnaká v každej rodine
príznakov.*

*Ľudskou rečou:* „redukcia dimenzionality" = zobrať 40 stĺpcov a stlačiť
ich do 3 alebo 10 nových, ktoré zachytávajú to podstatné. Keď tie 3-10
nových stĺpcov pošleme klasifikátoru, ako veľmi stratí presnosť oproti
tomu, keď by videl všetkých 40? **H2 tvrdí, že to záleží od rodiny
príznakov** — niekde je tá strata malá (kompresia „lacná"), inde veľká
(kompresia „drahá"). Dôvod: keď signál žije v **interakciách** medzi
príznakmi (URL-only), lineárna kompresia tie interakcie vyžehlí a
stratíš signál. Keď signál žije **priamo v hodnotách** jednotlivých
príznakov (Behavior), kompresia mu neublíži.

Každú rodinu môžeme stlačiť do menšieho počtu osí cez PCA (unsupervised
= nepozerá na cieľovú premennú) alebo LDA projekciu (supervised =
využíva triednu informáciu). Tvrdíme, že táto "compression penalty"
nie je rovnomerná:
- na Lexical je veľký (signál je v interakciách, lineárna projekcia ho
  časť zmaže),
- na Behavior/FullLite je malý (silný, viac aditívny signál).

| Kritérium | Obsah | Prah |
|-----------|-------|------|
| C1 | Pokles AUC: raw Lexical vs. Lexical komprimovaný na 3 PC (najlepší downstream model) | ΔAUC ≥ 0.05 |
| C2 | Pokles AUC: raw FullLite vs. FullLite komprimovaný na 10 PC (ten istý model) | ΔAUC ≤ 0.01 |
| C3 | Gradient poklesu | drop(Lexical) > drop(FullLite) |

H2 je podporená iba ak C1 aj C2 platia na rovnakej rodine klasifikátora.
C3 mení tvrdenie na gradient: čím slabší tier, tým drahšia kompresia.

---

## 3. Načítanie a čistenie dát

### 3.1 Načítanie

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

*Ľudskou rečou:* dataset obsahuje 50 „ukazovateľov" každej URL. Nie
všetky sú však poctivé merania. Niektoré sú v skutočnosti výstupy
iných detekčných algoritmov (nie surový fakt o URL, ale „čo si myslel
iný model"). Iné sú duplicity (dve merania, ktoré dávajú to isté
číslo). Treťia skupina sú pomery typu „počet X lomeno dĺžka URL", ktoré
sa dajú dopočítať z dvoch iných stĺpcov, ktoré už v datasete sú. Ak
by sme všetky tieto nechali v modelovaní, model by sa buď „naučil
tipovať iný model" (neprezradí to nič o URL samotnej), alebo by mal
chaos v stĺpcoch, ktoré hovoria to isté. Preto ich vyraďujeme **pred**
modelovaním, aby sme dali férovú odpoveď na to, koľko signálu je
naozaj v surovej URL.

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

*Ľudskou rečou:* predstav si, že máš jediný ukazovateľ a chceš ním
rozhodovať phish vs. legit. Napr. „URL dlhšia ako 100 znakov → phish".
Diskriminačná sila = aká časť URL sa dá takto správne zaradiť. Ak
je sila nízka, žiadny jednotlivý ukazovateľ úlohu nevyrieši a model
musí ukazovateľe **kombinovať**.

#### Prečo sa počíta dvomi rôznymi mierami?
SMD je zmysluplné iba pre spojité premenné (vyžaduje mean, SD). Pre
binárne premenné "pooled SD" degeneruje na funkciu marginálnej
proporcie a SMD stratí porovnateľnosť. **Cramérove V** je štandardná
efektová veľkosť pre 2×2 kontingenčnú tabuľku, ktorá býva v rovnakom
intervale [0,1] ako |korelácia|.

*Ľudskou rečou:* Na spojité čísla (dĺžka URL v znakoch) sa pýtame
„o koľko smerodajných odchýlok sa líšia priemery dvoch tried?". Na
binárky (má titulok / nemá) sa tá otázka nedá položiť (nemá zmysel
hovoriť o „smerodajnej odchýlke" binárnej 0/1 v tomto kontexte), tak
sa pýtame „ako veľmi sa líši percento `HasTitle = 1` medzi phish a
legit?". Cieľ oboch otázok je rovnaký — kvantifikovať rozlišovaciu
silu jediného príznaku — ale matematika je iná.

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

*Ľudskou rečou:* Ak dva ukazovatele merajú takmer to isté, jeden z nich
je redundantný — a lineárny model z toho bude zmätený. Tu sa
pozrieme, ktoré Lexical príznaky sú „dvojičky", lebo to má dve
dôsledky: (1) pre scenario_2 to znamená používať regularizovanú regresiu
(Ridge), nie obyčajnú; (2) pre scenario_5 to znamená, že Lexical je
v princípe stlačiteľný — ale to nezaručuje, že ho stlačiť bez straty
**klasifikačnej** presnosti, to testuje §4.5.

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
- Kolineárny Lexical klaster znamená, že veľká časť variability žije v
  pár smeroch. To zvádza k záveru, že PCA kompresia bude "lacná".
- Ale H2 rieši inú otázku: či tieto dominantné smery variability nesú aj
  triedový signál. Preto po korelácii/VIF potrebujeme ešte PCA diagnostiku
  s AUC na jednotlivých PC (sekcia 4.5).

### 4.4 Šikmosť

*Ľudskou rečou:* väčšina URL je krátka (40–80 znakov), ale zopár je
extrémne dlhých — histogram má vysoký vrchol vľavo a dlhý tenký
„chvost" doprava. Tento tvar je typický pre počty a dĺžky (cena,
čas-do-udalosti, počet kliknutí...), ale nie je dobrý pre lineárne
modely, ktoré predpokladajú, že dáta vyzerajú ako zvonec.

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

### 4.5 Kde leží triedový signál po PCA (kľúč k H2)

Sekcia 4.3 ukázala varianciu a kolinearitu. To však ešte nehovorí, či
hlavné komponenty nesú aj separáciu Phishing vs Legitimate.

**Najdôležitejší rozdiel celej sekcie, povedaný nahlas:**
*variability* (kde sú dáta rozhádzané) a *triedový signál* (kde sa
phish oddelí od legit) **nie sú to isté**. PCA optimalizuje prvé,
nie druhé. Bežná chyba pri interpretácii: „scree plot ukazuje že 3 PC
stačí na 90 % variancie, takže 3 PC stačí aj na klasifikáciu" — a to
nie je automaticky pravda.

*Ľudskou rečou — analógia:* predstav si mapu parkoviska zhora. Autá
sú rozhádzané v smere sever-juh (to je smer najväčšej variancie = PC1).
Ale otázka, ktorú chceš zodpovedať, je „ktoré auto je červené a ktoré
modré", a farba v skutočnosti súvisí s parkovacím miestom, ktoré beží
východ-západ (kolmo na PC1). Ak stlačíš mapu iba na os sever-juh,
dostaneš síce „čo najviac informácie o polohe áut", ale **stratíš
celú informáciu o farbe**. PCA by v tomto príklade bolo pre
klasifikáciu katastrofálne napriek tomu, že zachytáva 100 % variancie
v osi sever-juh.

#### 4.5.1 Scree intuícia (koľko PC treba na 90 % variability)
Scree plot vykresľuje kumulatívne, aké percento variability dáva
postupne 1 PC, 2 PC, 3 PC atď. Hľadáme „lakeť" krivky — bod, kde
pridanie ďalšej PC už prináša málo.
- Lexical dosiahne ~90 % variability už pri 3-4 PC. (Lexical má veľa
  korelovaných počtov okolo dĺžky URL, takže sa dá stlačiť.)
- Trust minie prakticky všetky svoje smery (binárne, slabo korelované
  — každý príznak je „svoj" smer).
- Behavior a Full potrebujú viac komponentov (10+).

Toto je iba "variance picture". Samotná variancia nemusí byť rovnaká vec
ako klasifikačný signál — preto 4.5.2.

#### 4.5.2 AUC na jednotlivých PC (kde je diskriminačný signál)
Pre každú PC zvlášť spočítame univariátnu AUC (len tá jedna os ako
klasifikátor). Hovorí nám: „ak by som mal k dispozícii iba tento
jeden smer, ako dobre by som rozlíšil phish od legit?"

- Na Lexical má PC1 veľa variability, ale separačný signál je rozliaty do
  viacerých PC s nižšou AUC. → Variance a trieda si **nesadli**.
- Na Behavior/Full prvé 2-3 PC nesú silný signál (vysoké AUC), takže
  kompresia je lacnejšia. → Variance aj trieda si **sadli**.

**Interpretácia pre H2:**
- "málo PC na 90 % variance" automaticky neznamená "málo PC stačí na
  klasifikáciu".
- Práve preto v Scenario 5 čakáme veľký pokles po kompresii na Lexical a
  malý pokles na FullLite. Scenario 5 to potom kvantifikuje
  naozajstným trénovaním modelov na PC-komprimovaných dátach.

---

## 5. Zhrnutie EDA a implikácie pre modelovanie

### Near-perfect separabilita na Full a prechod na FullLite
Po vylúčení príznakov v §3.3 zostáva 40 feature (13 Lexical, 7 Trust,
20 Behavior). Keď je Behavior plný, úloha je takmer saturovaná (AUC ~1.0)
a rozdiely medzi modelovými rodinami sa stierajú.

Pre H1 preto používame **FullLite** (34 feature): z Behavior odoberieme
6 near-leakerov (`LineOfCode`, `NoOfJS`, `NoOfCSS`, `NoOfImage`,
`NoOfSelfRef`, `NoOfExternalRef`). Takto je porovnanie medzi tiermi
informatívne a nie "utopené" v saturácii.

### Implikácie pre Scenario 2 (H1)
| Zistenie z EDA | Implikácia pre modelovanie |
|----------------|----------------------------|
| Near-perfect AUC na Full | Testujeme H1 primárne na Lexical |
| Najnižšie SMD v Lexical | Najväčší param. vs. neparam. rozdiel sa čaká na URLOnly |
| Šikmosť v 19 z 22 príznakov | Log + scale pre LR/LDA/NB/SVM/KNN; RF bez transform |
| VIF > 500 | Ridge-regularizovaná LR na fairnej stabilite |

### Implikácie pre Scenario 5 (H2)
| Zistenie z EDA | Implikácia |
|----------------|------------|
| Lexical: nízky per-feature signal + signál rozliaty naprieč PC | Kompresia na 3 PC má mať citeľný AUC pokles |
| Behavior/Full: silný signál v prvých PC | Kompresia má byť lacná (malý AUC pokles) |
| Kolineárny URL-length klaster | Variancia je low-rank, ale to samo o sebe nezaručuje low-loss kompresiu |
| Trust binárky majú nízku vzájomnú koreláciu | Trust minie viac PC na varianciu; krátka projekcia môže rýchlo strácať informáciu |

---

## 6. Typické otázky komisie a návrhy odpovedí

**Q: Prečo vôbec používate PCA, keď znižuje interpretovateľnosť?**
A: V tomto projekte PCA nepoužívame ako finálny produkčný model, ale ako
kontrolovaný experiment pre H2: meriame, koľko výkonu stratí každý tier
po kompresii. Tým testujeme, kde je signál "komprimovateľný" a kde nie.
Interpretovateľný baseline zostáva na pôvodných príznakoch.

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

**Q: Ako odôvodňujete vetu *"the deployment cost is not a ranking — it
is a single block/allow verdict at threshold 0.5 per click"*? Prečo
práve threshold 0.5 a prečo binárne rozhodnutie ako gating metric, keď
máte AUC?**

A: Tá veta sa obhajuje cez tri previazané argumenty.

**1. Reálny proxy nerobí ranking, robí binárne rozhodnutie.**
Používateľ klikne na URL → proxy musí odpovedať buď *allow* (preposlanie
spojenia) alebo *block* (warning stránka). Neexistuje stav „počkaj,
najprv ohodnotím všetkých 235 tisíc URL a uvidím, kde si v poradí". AUC
meria *kvalitu rebríčka* naprieč celým datasetom — to je užitočné pri
výbere modelu, ale **nie pri klike**. Pri klike máš jednu URL, jeden
score, jednu hranicu, jeden výrok. Toto je doménovo-fyzická vlastnosť
proxy nasadenia, nie ľubovoľná voľba.

**2. Threshold 0.5 je obhájiteľný default, nie arbitrárny.**
Tri dôvody, prečo ho zvoliť:
- **Bayes-optimal pri vyrovnaných triedach a neznámych nákladoch.**
  Trieda balance je 57 % phishing / 43 % legitimate (§4.1.1 EDA) —
  dostatočne blízko 50/50, aby 0.5 nebol skreslený. Asymetrický
  threshold by vyžadoval explicitný **cost ratio** (false-block vs.
  missed-phish), ktorý projekt nemá business-validovaný.
- **Defaultný výstup `predict()` v R / caret.** Reprodukovateľnosť:
  ktokoľvek to spustí, dostane tie isté čísla bez tunenia.
- **Fair comparison medzi šiestimi modelmi.** Keby sme každému modelu
  naladili optimálny per-model threshold z ROC kriviek, neporovnávali
  by sme **inductive bias rodín** (čo H1 tvrdí), ale schopnosť modelu
  byť doladený. Spoločný threshold 0.5 udržuje porovnanie čisté —
  rozdiely v Sens/Spec odrážajú vlastnosti modelu, nie tuning.

**3. Z toho vyplýva výber metricu.** Akonáhle prijmeš (1) + (2), AUC
nemôže byť deployment metric — je z definície threshold-free. Sens a
Spec pri 0.5 hovoria, koľko phishingu prejde a koľko legit URL je
zablokovaných **v reálnom nasadení**. minSS = min(Sens, Spec) je
*najslabší smer* — max z dvoch chybových typov pri zvolenom operating
point. Manažérska otázka *"keď to nasadíme, koľko percent buď
používateľov uvidí broken link, alebo phisher prejde?"* sa zodpovedá
presne týmto číslom.

**Ako to ustáť, ak komisia zatlačí ďalej:**

- *„Prečo nie tuned threshold per model?"* → „Lebo to mení predmet
  hypotézy. H1 testuje rozdiely medzi rodinami modelov pri **rovnakom**
  operating point — tuned threshold by miešal rodinné rozdiely s
  tuning-schopnosťou. Pri tom by SVM-RBF aj NB s prepočítaným cut-om
  mohli vyzerať podobne, ale nasadenie by stále malo NB pathology — náš
  metric to musí vidieť."
- *„Prečo nie cost-sensitive threshold?"* → „Nemáme validovaný cost
  ratio od stakeholdera. 0.5 je default, ktorý nepredpokladá nič; ak by
  zákazník neskôr dodal pomer (napr. 10:1 v prospech catching phish),
  threshold sa preladí, ale **rebríček modelov sa nezmení** — len
  posunutý operating point. AUC + Sens/Spec krivka v `scenario_2.rmd`
  §6 dávajú všetko, čo je na prepočet potrebné."
- *„Prečo nie F1 alebo BalAcc?"* → „F1 ignoruje TN (Specificity) a v
  proxy kontexte je false-block reálnym nákladom (helpdesk, broken
  portal). BalAcc je priemer Sens a Spec — minSS je striktnejší (worst
  case), čo lepšie zodpovedá manažérskej otázke 'aký je najhorší smer
  chyby pri nasadení'."

**Sumár jednou vetou na obhajobu:** *„Proxy je per-click binárny
rozhodovač, threshold 0.5 je default zachovávajúci fair comparison
medzi rodinami, takže jediný metric, ktorý meria reálne nasadenie, je
threshold-závislý — a zo všetkých takých metrík je minSS najprísnejší
voči asymetrickým nákladom, ktoré zatiaľ nemáme business-validované."*

**Q: Ako viete, že rozdiely medzi foldami nie sú iba náhodný šum?**
A: Párový Wilcoxonov test + veľkosť efektu.

*Ľudskou rečou:* 10-krát som rozdelil trénovacie dáta na 10 kúskov,
zakaždým som na 9 z nich vytrénoval oba modely a na tom desiatom
odmeral AUC. Porovnávam tie isté foldy (páry), takže šum zo splitu sa
odpočíta.

Čísla: na Lexical je rozdiel ≈ 0.10 AUC, zatiaľ čo smerodajná odchýlka
per-fold AUC je ~0.005 — rozdiel je rádovo väčší ako šum. Pri 10
párovaných pozorovaniach je najmenšia dosiahnuteľná p-hodnota
jednostranného Wilcoxonu `1/2^10 = 1/1024 ≈ 0.001` — ten floor
trafia tri zo štyroch tierov (Lexical, Behavior, FullLite = každý
neparam. fold bije svoj spárovaný param. fold). Trust ako jediný dá
p ≈ 0.019 — nie je na floore, čo správne signalizuje, že tam je
kontrast medzi rodinami modelov slabší. Staršia 5-foldná verzia mala
floor `1/32 ≈ 0.031`, tam by všetky tiery kolabovali na to isté
číslo. Detailnejšia diskusia v `scenario_2.rmd` (§6.2).

**Q: Čo v budúcnosti? Je 235 k URL reprezentatívnych?**
A: PhiUSIIL je zhromaždený v jednom časovom okne (~2021), takže
nemodeluje časový drift phishing kit autorov. V produkčnom nasadení by
bol potrebný kontinuálny retraining. Toto je limitácia, ktorú
priznávame.

**Q: Prečo je v `scenario_2.rmd` Precision počítaná vzorcom a nie
priamo z confusion matrix?**
A: Vzorec `Prec = Sens / (Sens + (1 − Spec))` je **matematicky
identický** s `TP / (TP + FP)` **za podmienky, že pozitívnych a
negatívnych príkladov v teste je rovnako**. V scenario_2 tú podmienku
forsujeme explicitne: subsampling v §3.1 berie presne 15 000 phish +
15 000 legit, stratifikovaný 80/20 split z toho spraví presne 3000/3000
testov — teda prevalencia je presne 50/50, nie približne.

*Ľudskou rečou:* keď sú obe triedy rovnako početné, „koľko z alarmov
je pravdivých" sa dá odvodiť čisto zo senzitivity a špecificity bez
toho, aby sme sa pozreli do tabuľky. Nie je to aproximácia, je to
identita.

**Čo na tom môže byť problém?** Ak by sa subsampling niekedy zmenil
(napr. na 60/40), vzorec by prestal platiť a dal by tichú chybu.
Robustnejší kód by čítal priamo `cm$byClass["Precision"]` z
confusionMatrix — výsledok pri súčasnom 50/50 splite je identický,
ale kód prežije zmeny.

**Treba kvôli prechodu na priame CM pretrénovať?** Nie. Cache v
`scenario_2/artifacts/res_*.rds` síce `test_prec` priamo neukladá (iba
`test_sens`, `test_spec`), ale keď sa do `fit_one_tier` doplní
`test_prec = unname(cm$byClass["Precision"])` a v `test_tbl` sa nechá
fallback na vzorec pre staré cache, čísla budú rovnaké a nič sa
nepretréňuje. Pretrénovanie je potrebné len vtedy, keď sa zmení dátový
podklad alebo metóda trénovania — kozmetický prechod na CM do tejto
kategórie nepatrí.


