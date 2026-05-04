# EDA — príprava na obhajobu

Tento dokument je hovorená, obhajobová verzia notebooku `eda.rmd`. Je písaný tak, aby sa z neho dalo pripraviť na otázky komisie aj bez toho, aby čitateľ musel detailne poznať R alebo strojové učenie. Vecné tvrdenia vychádzajú z aktuálneho `eda.rmd`, nie zo starších odstránených dokumentácií.

---

## 0. Najkratšia verzia pre úvod obhajoby

Projekt rieši detekciu phishingových URL v situácii, kde používateľ klikne na odkaz a korporátny proxy server musí veľmi rýchlo rozhodnúť, či odkaz zablokuje alebo pustí. Najlacnejší signál je samotný text URL adresy, pretože ešte netreba robiť DNS lookup, sťahovať HTML ani analyzovať obsah stránky.

EDA mala tri hlavné úlohy:

1. **Pochopiť dataset** a rozdeliť features podľa toho, koľko stoja v reálnom nasadení.
2. **Odstrániť nefér alebo redundantné premenné**, aby modely neriešili úlohu pomocou skratky.
3. **Odôvodniť scenáre 2 a 3**, teda prečo porovnávame parametrické/neparametrické modely a prečo neskôr riešime výber menšieho počtu URL features.

Z EDA vyšlo, že samotné URL features sú jednotlivo slabšie než Trust a Behavior features, ale majú kombinovaný signál. To podporuje očakávanie, že nelineárne modely budú na URL-only úlohe silnejšie. Zároveň sme našli šesť extrémne silných Behavior features, ktoré by pri ponechaní „prebili“ celé porovnanie, preto sme zaviedli FullLite tier.

---

## 1. Slovník pojmov

### Phishing URL

Phishing URL je odkaz, ktorý sa tvári ako legitímna služba, ale v skutočnosti smeruje na podvodnú stránku. Útočník sa snaží používateľa presvedčiť, aby zadal heslo, údaje karty alebo iné citlivé informácie.

### Proxy server

Proxy server stojí medzi používateľom a internetom. Keď používateľ otvorí URL, proxy vie rozhodnúť, či požiadavku pustí ďalej, alebo ju zablokuje. V našom príbehu proxy potrebuje rýchly model, ktorý vie z URL alebo ďalších signálov povedať „block“ / „allow“.

### Feature / prediktor

Feature je stĺpec v datasete, ktorý model používa na rozhodovanie. Napríklad `URLLength` je dĺžka URL, `NoOfSubDomain` je počet subdomén, `IsHTTPS` hovorí, či stránka používa HTTPS.

### Label

Label je správna odpoveď, ktorú sa model učí predikovať. V datasete je to informácia, či je riadok phishing alebo legitimate.

### AUC

AUC meria, ako dobre model zoradí phishing vyššie než legitímne stránky. AUC = 1 je perfektné zoradenie, AUC = 0.5 je náhodné hádanie. AUC však nehovorí, čo sa stane pri konkrétnom prahu 0.5, kde sa model musí rozhodnúť.

### Sensitivity

Sensitivity hovorí, koľko phishingových URL model zachytil. Ak je sensitivity 0.95, model chytil 95 % phishingu a 5 % mu ušlo.

### Specificity

Specificity hovorí, koľko legitímnych URL model správne pustil. Ak je specificity 0.80, model pustil 80 % legitímnych a 20 % legitímnych by omylom zablokoval.

### minSS

`minSS = min(Sensitivity, Specificity)`. Je to metrika slabšej strany modelu. Ak model chytá phishing dobre, ale blokuje veľa legitímnych stránok, minSS bude nízke. Pre proxy je to užitočné, lebo model nemôže byť dobrý iba na jednej strane.

### Parametrický model

Parametrický model má relatívne pevný tvar rozhodovania. Napríklad logistická regresia hľadá hlavne lineárnu kombináciu features. Je jednoduchšia a interpretovateľnejšia, ale nemusí zachytiť zložité interakcie.

### Neparametrický model

Neparametrický model má flexibilnejší tvar. Random Forest, SVM-RBF alebo KNN sa vedia prispôsobiť nelineárnym vzťahom. Cena je vyššia výpočtová náročnosť alebo horšia interpretovateľnosť.

### SMD

SMD znamená standardised mean difference. Používame ho pre spojité features. Meria, o koľko sa priemer phishing triedy líši od priemeru legitimate triedy v jednotkách štandardnej odchýlky.

### Cramérovo V

Cramérovo V používame pre binárne features. Meria silu asociácie medzi binárnym feature a labelom. Je na škále 0 až 1, takže sa dá ľahko čítať podobne ako SMD.

### VIF

VIF meria multikolinearitu. Ak má feature vysoké VIF, znamená to, že ho vieme veľmi dobre vysvetliť ostatnými features. Pri lineárnych modeloch to spôsobuje nestabilné koeficienty.

### Skewness

Skewness je šikmosť rozdelenia. Pri count-features často vzniká dlhý pravý chvost: väčšina hodnôt je malá, ale pár URL má extrémne veľké hodnoty. Preto neskôr používame `log1p`.

### Leakage a near-leaker

Leakage je únik informácie, ktorá by v reálnom čase nemala byť dostupná alebo by príliš priamo prezrádzala label. Near-leaker nie je úplne zakázaný stĺpec, ale je taký silný, že sám takmer vyrieši úlohu a zakryje rozdiely medzi modelmi.

---

## 2. Problém, ktorý riešime

### 2.1 Reálny scenár

Používateľ klikne na URL v e-maile, chate alebo výsledku vyhľadávania. Proxy server má rozhodnúť ešte pred načítaním stránky. Rozhodnutie musí byť rýchle, pretože oneskorenie pri každom kliknutí by bolo v praxi nepríjemné.

V tejto situácii existujú rôzne úrovne signálov:

| Úroveň | Ako rýchlo ju vieme získať | Príklad |
|---|---|---|
| Lexical | okamžite z textu URL | dĺžka URL, počet číslic, počet subdomén |
| Trust | treba už poznať doménu alebo metadata | HTTPS, doménové a title flagy |
| Behavior | treba analyzovať obsah stránky | iframe, hidden fields, externé referencie |

Najrýchlejšia je Lexical vrstva. Ak funguje dobre, proxy má lacný prvý filter. Ak nestačí, musí použiť drahšie signály.

### 2.2 Prečo nestačí povedať iba „model má vysoké AUC“

Proxy nerobí akademické hodnotenie skóre. V praxi musí vrátiť jednu odpoveď:

- phishing → blokovať,
- legitimate → pustiť.

Preto nás okrem AUC zaujíma aj threshold 0.5, teda čo sa stane pri reálnom rozhodnutí. Model môže mať dobré AUC, lebo vie prípady pekne zoradiť, ale pri prahu 0.5 môže blokovať veľa legitímnych stránok. Preto už v EDA pripravujeme metriky Sensitivity, Specificity a minSS.

---

## 3. Dataset PhiUSIIL

Dataset má približne 235 000 riadkov a 50 prediktorov. Každý riadok reprezentuje jednu URL alebo stránku a label hovorí, či ide o phishing alebo legitimate.

### 3.1 Naše delenie features

Rozdelenie do rodín nie je priamo dodané datasetom. Je to naše analytické rozhodnutie podľa deployment nákladov.

| Rodina | Význam | Príklady | Prečo je dôležitá |
|---|---|---|---|
| Lexical | vlastnosti samotného URL reťazca | `URLLength`, `NoOfSubDomain`, `NoOfOtherSpecialCharsInURL` | dá sa použiť pred načítaním stránky |
| Trust | dôvera a doménové vlastnosti | `IsHTTPS`, `HasTitle`, `Bank`, `Pay` | lacnejšie než plná analýza stránky, ale nie vždy úplne zadarmo |
| Behavior | obsahové a stránkové signály | `NoOfiFrame`, `HasHiddenFields`, `NoOfURLRedirect` | najsilnejšie, ale najdrahšie na získanie |

### 3.2 Dôležitý detail: `IsHTTPS`

`IsHTTPS` by sa dalo považovať za súčasť URL stringu, ale v projekte ho dávame do Trust rodiny. Dôvod je praktický: HTTPS nie je iba textový vzor v URL. V reálnom prehliadači je to bezpečnostná vlastnosť spojenia a prehliadače už dnes plain HTTP aktívne označujú ako nedôveryhodné. Ak by sme `IsHTTPS` dali do Lexical tieru, URL-only model by dostal signál, ktorý je skôr trust pravidlo než čistá lexikálna vlastnosť.

---

## 4. Hypotézy vychádzajúce z EDA

### 4.1 H1 pre Scenár 2

H1 hovorí, že rozdiel medzi parametrickými a neparametrickými modelmi závisí od tieru. Konkrétne očakávame najväčší rozdiel na Lexical tieri, lebo samotné URL features sú jednotlivo slabšie a signál je skôr v ich kombináciách.

Parametrické modely:

- Logistic Regression,
- LDA,
- Naive Bayes.

Neparametrické modely:

- Random Forest,
- SVM-RBF,
- KNN.

Pre obhajobu je dôležité povedať, že H1 nemeriame iba cez AUC. Primárne pozeráme `minSS`, teda slabšiu z dvojice Sensitivity/Specificity pri prahu 0.5. To lepšie zodpovedá proxy nasadeniu.

### 4.2 Kritériá H1

| Kritérium | Význam |
|---|---|
| C1: Δ minSS na Lexical >= 0.10 | non-parametrický champion musí byť výrazne lepší než parametrický champion na URL-only úlohe |
| C2: gap(Lexical) > gap(FullLite) | rozdiel sa má zmenšiť, keď pridáme silnejšie signály |
| C3: ΔAUC na Lexical >= 0.02 | sanity check, že rozdiel existuje aj v threshold-free poradí |

### 4.3 H2 pre Scenár 3

H2 sa pýta, či dokážeme zmenšiť URL-only filter bez veľkej straty kvality. Ak má Lexical tier 13 features, prakticky by bolo výhodné mať menší model, ktorý používa napríklad 9 features a stále dobre funguje.

Používame tri feature-selection metódy:

- bidirectional stepwise,
- lasso,
- elastic-net.

H2 je podporená, ak aspoň jedna metóda vyberie najviac 9 z 13 lexikálnych features a zároveň dosiahne AUC >= 0.95, Sensitivity >= 0.94 a Specificity >= 0.75.

---

## 5. Čistenie dát

EDA najprv odstraňuje stĺpce, ktoré by zhoršili férovosť alebo interpretáciu modelovania.

### 5.1 Identifikačné stĺpce

Stĺpce ako `FILENAME`, `URL`, `Domain`, `TLD`, `Title` nie sú numerické features pre modelovanie v tejto podobe. Sú to identifikátory alebo text. Z URL textu už máme odvodené numerické lexikálne features, takže surový string nepoužívame priamo.

### 5.2 Vypočítané skóre

Odstránené:

- `URLSimilarityIndex`,
- `TLDLegitimateProb`,
- `URLCharProb`,
- `DomainTitleMatchScore`,
- `URLTitleMatchScore`.

Tieto stĺpce nie sú surové merania. Sú to výstupy iných skórovacích alebo expertných pravidiel. Keby sme ich nechali, model by sa mohol naučiť „dôverovať cudziemu skóre“ namiesto toho, aby sa učil z vlastností URL a stránky.

Obhajobová veta:

> Tieto skóre sme odstránili, lebo by z projektu spravili meta-klasifikátor nad už hotovými detektormi. Cieľom bolo porovnať modely na surovších features.

### 5.3 Redundantná binárna premenná

`HasObfuscation` je redundantná voči `NoOfObfuscatedChar`. Ak počet obfuskovaných znakov existuje, binárka „je počet väčší ako nula“ neprináša novú informáciu.

### 5.4 Redundantné pomery

Odstránené pomery:

- `LetterRatioInURL`,
- `DegitRatioInURL`,
- `ObfuscationRatio`,
- `SpacialCharRatioInURL`.

Tieto pomery sú odvodené z count-features a `URLLength`. Napríklad pomer písmen v URL je počet písmen delený dĺžkou URL. Ak máme obe zložky, pomer nepridáva nezávislý signál a spôsobuje lineárnu závislosť.

### 5.5 Výsledok čistenia

Po odstránení týchto stĺpcov ostane 40 prediktorov:

- 13 Lexical,
- 7 Trust,
- 20 Behavior.

Neskôr pre Scenár 2 a 3 odstraňujeme ešte šesť near-leaker Behavior features z Behavior/FullLite modelovania, aby sa porovnanie modelov nenasýtilo jedným extrémne silným signálom.

---

## 6. EDA zistenia

### 6.1 Triedy sú približne vyvážené

Notebook ukazuje, že phishing a legitimate triedy sú približne 50/50. To je dôležité, lebo pri silnom class imbalance by sme museli riešiť váhy tried, resampling alebo iné metriky. Tu triedna rovnováha znamená, že základné porovnanie modelov je jednoduchšie.

Obhajobová odpoveď:

> Dataset nie je extrémne nevyvážený, preto sme nepotrebovali class weighting. To nám umožňuje porovnávať Sensitivity a Specificity bez toho, aby výsledky boli primárne dôsledkom resamplingu.

### 6.2 Chýbajúce hodnoty

Notebook uvádza, že v prediktoroch nie sú chýbajúce hodnoty. To zjednodušuje pipeline: nemusíme robiť imputáciu, nemusíme rozhodovať medzi median/mode imputáciou a nehrozí, že rôzne modely budú porovnávané po rôznych úpravách chýbajúcich dát.

### 6.3 Diskriminačná sila features

EDA meria, ako silno jednotlivé features samostatne odlišujú phishing od legitimate.

Pre spojité features používame SMD. Pre binárne features používame Cramérovo V. Dôvod je jednoduchý: spojité a binárne premenné majú inú matematickú povahu, ale obe metriky sa dajú čítať ako „čím vyššie, tým viac feature oddeľuje triedy“.

### 6.4 Čo sme zistili pri binárnych features

Najsilnejšie binárne features sú z Trust alebo Behavior rodiny:

- `HasSocialNet`,
- `HasCopyrightInfo`,
- `HasDescription`,
- `IsHTTPS`.

Jediná lexikálna binárka `IsDomainIP` je veľmi slabá. To znamená, že samotný URL string neobsahuje jednoduchý binárny prepínač typu „ak áno, tak phishing“. Lexical úloha je preto ťažšia.

### 6.5 Čo sme zistili pri spojitých features

`CharContinuationRate` je silný lexikálny feature, ale väčšina Lexical features má nižšiu samostatnú silu. Behavior spojité features majú vyšší medián SMD. To podporuje H1: ak jednotlivé URL features nie sú silné samostatne, model musí využiť ich kombinácie.

Obhajobová pointa:

> Lexical tier nie je bez signálu, ale signál nie je uložený v jednom jednoduchom stĺpci. Preto očakávame, že flexibilnejšie modely budú na Lexical úlohe lepšie.

### 6.6 Kolinearita v Lexical features

Lexikálne features ako `URLLength`, `NoOfLettersInURL` a `NoOfDegitsInURL` merajú prekrývajúce sa vlastnosti tej istej URL. Dlhšia URL prirodzene často obsahuje viac písmen aj viac znakov. Korelácie a VIF ukazujú, že tieto premenné sú veľmi previazané.

Pre lineárne modely je to problém. Ak dva stĺpce hovoria takmer to isté, logistická regresia môže medzi ne arbitrárne rozdeliť koeficienty. Malá zmena dát potom spôsobí veľkú zmenu koeficientov.

Riešenie pre Scenár 2:

- obyčajnú neregularizovanú LR nepoužívame,
- používame ridge regularizáciu,
- ridge stabilizuje koeficienty, ale nerobí feature selection.

### 6.7 Šikmosť spojitých prediktorov

Mnohé count-features sú extrémne pravostranné. Väčšina URL má nízke počty, ale niektoré majú veľa znakov, skriptov, obrázkov alebo referencií.

Dôsledok pre modelovanie:

- LR a LDA potrebujú `log1p` a štandardizáciu.
- SVM a KNN potrebujú škálovanie, lebo pracujú so vzdialenosťami.
- Random Forest nepotrebuje škálovanie ani log transformáciu, lebo stromy sa rozhodujú podľa prahov a poradia hodnôt.

### 6.8 Near-leaker analýza

Najdôležitejšia EDA časť pre dizajn Scenára 2 je near-leaker analýza. Notebook meria univariate AUC pre Behavior features, teda schopnosť jedného feature samostatne odlíšiť phishing od legitimate.

Šesť Behavior features má AUC nad 0.95:

- `LineOfCode`,
- `NoOfExternalRef`,
- `NoOfImage`,
- `NoOfSelfRef`,
- `NoOfJS`,
- `NoOfCSS`.

Tieto features sú tak silné, že model by s nimi veľmi ľahko dosiahol AUC blízko 1.0. Dôvod je pravdepodobne praktický: legitímne stránky sú komplexné, majú veľa HTML, CSS, JS, obrázkov a referencií, zatiaľ čo phishing stránky sú často jednoduché napodobeniny.

Prečo je to problém:

> Ak necháme near-leakery vo Full tieri, všetky modely budú vyzerať takmer perfektne a rozdiel medzi parametrickými a neparametrickými modelmi zmizne. Potom by sme netestovali H1, ale iba to, že šesť page-count features je extrémne silných.

Preto vzniká FullLite:

- Lexical,
- Trust,
- Behavior bez šiestich near-leakerov.

---

## 7. Ako EDA priamo vedie do Scenára 2

EDA dáva Scenáru 2 tieto rozhodnutia:

### 7.1 Prečo Lexical ako hlavný tier

Lexical je najlacnejší pre proxy. Zároveň EDA ukázala, že jednotlivé Lexical features sú slabšie, takže je tam priestor na rozdiel medzi modelovými rodinami. To je presne miesto, kde H1 má najväčší zmysel.

### 7.2 Prečo porovnávať parametrické a neparametrické modely

Parametrické modely sú jednoduchšie a interpretovateľnejšie, ale menej flexibilné. Neparametrické vedia zachytiť interakcie. EDA naznačuje, že Lexical signál je skôr v kombináciách než v jednom silnom feature, preto je porovnanie modelových rodín opodstatnené.

### 7.3 Prečo FullLite namiesto Full

Full by obsahoval near-leakery a bol by príliš ľahký. FullLite je kompromis: stále obsahuje viac signálov než Lexical, ale nie také, ktoré samostatne vyriešia úlohu.

### 7.4 Prečo log transformácia a škálovanie

Šikmosť a vzdialenostné modely vyžadujú robustný preprocessing. Preto Scenár 2 používa `log1p` pre spojité features a následné `center/scale` pre modely, ktoré na škálu reagujú.

---

## 8. Ako EDA priamo vedie do Scenára 3

Scenár 3 sa pýta, či vieme z 13 lexikálnych features vybrať menšiu podmnožinu. EDA ukazuje dva dôvody, prečo je to dôležité:

1. Lexical features sú korelované, takže nie všetky musia niesť unikátny signál.
2. Deploymentový model by mal byť čo najjednoduchší, ak nestratí kvalitu.

Preto porovnávame stepwise, lasso a elastic-net:

- stepwise reprezentuje algoritmický výber,
- lasso reprezentuje embedded výber cez L1 penalizáciu,
- elastic-net testuje, či kombinácia L1/L2 pomáha pri korelovaných features.

---

## 9. Hlavné obhajobové tvrdenia

### Tvrdenie 1: Dataset sme nebrali ako čiernu skrinku

Najprv sme z neho odstránili stĺpce, ktoré by vytvorili nefér skratky alebo redundancie. Až potom sme definovali modelovacie tiery.

### Tvrdenie 2: Lexical tier je realisticky najdôležitejší

Proxy vie URL string spracovať okamžite. Preto má zmysel pýtať sa, či URL-only model stačí ako prvá línia obrany.

### Tvrdenie 3: FullLite je metodicky nutný

Naivný Full tier by bol príliš ľahký kvôli šiestim near-leakerom. FullLite zachováva silnejší benchmark, ale bez toho, aby zničil porovnanie modelov.

### Tvrdenie 4: Preprocessing nie je náhodný

`log1p` vyplýva zo šikmosti. Ridge vyplýva z kolinearity. Neškálovanie Random Forest vyplýva z povahy stromov. Tieto rozhodnutia sú priamo odôvodnené EDA.

---

## 10. Čo by sa stalo, keby sme urobili iné rozhodnutia

### Keby sme nechali vypočítané skóre

Model by pravdepodobne dosiahol lepšie čísla, ale nebolo by jasné, či sa učí phishing vlastnosti alebo len kopíruje už hotové skóre. Obhajobovo by to bolo slabšie.

### Keby sme nechali redundantné ratio features

Lineárne modely by mali viac kolinearity a koeficienty by sa horšie interpretovali. Výsledky by mohli byť numericky nestabilnejšie.

### Keby sme nechali near-leakery vo Full

Full modely by sa nasýtili pri AUC približne 1.0. Potom by H1 nebola férová, lebo rozdiel medzi modelmi by zmizol nie preto, že modely sú rovnako dobré, ale preto, že pár features je samo osebe takmer perfektných.

### Keby sme neškálovali SVM/KNN

Features s veľkými číselnými rozsahmi by dominovali vzdialenosti. Model by nerozhodoval férovo podľa všetkých features, ale podľa tých, ktoré majú najväčšie jednotky.

### Keby sme nepoužili `log1p`

Extrémne hodnoty v dlhých pravých chvostoch by silno ovplyvnili lineárne modely. `log1p` stláča extrémy, ale zachováva poradie.

---

## 11. Časté otázky komisie

### Prečo ste nepoužili všetkých 50 prediktorov?

Lebo nie všetky sú vhodné ako férové vstupy. Niektoré sú identifikátory alebo texty, niektoré sú už vypočítané skóre iných systémov, niektoré sú redundantné odvodeniny. Cieľom bolo modelovať z interpretovateľných, surovejších signálov.

### Prečo sú SMD a Cramérovo V dve rôzne metriky?

Lebo spojité a binárne features majú inú matematiku. SMD je vhodné pre rozdiel priemerov spojitých premenných. Cramérovo V je vhodné pre asociáciu v kontingenčnej tabuľke pri binárnych premenných. Obe však dávajú čitateľnú škálu 0 až 1.

### Prečo riešite minSS, keď EDA ešte netrénuje modely?

EDA formuluje problém a hypotézy. Keďže deployment je block/allow pri prahu 0.5, už pri formulácii hypotéz definujeme, že neskôr nebude stačiť len AUC. minSS je spôsob, ako hodnotiť slabšiu stranu modelu.

### Prečo nepoužívate class weighting?

Dataset je približne vyvážený. Class weighting je užitočný pri silnom imbalance, napríklad 1 % phishing a 99 % legit. Tu by pridával ďalšie rozhodnutie bez jasnej potreby.

### Nie sú near-leakery legitímne features?

Môžu byť legitímne v inom deployment scenári, kde už máme stiahnutý obsah stránky. Ale v našom porovnaní modelových rodín by príliš dominovali. Preto ich neoznačujeme ako „zlé“, ale ako nevhodné pre H1 kontrast.

### Prečo FullLite stále obsahuje Behavior features?

Lebo nechceme porovnávať iba URL-only svet. FullLite je realistický silnejší benchmark, ktorý ukazuje, čo sa stane, keď proxy alebo pipeline má k dispozícii viac signálov, ale bez šiestich premenných, ktoré úlohu takmer vyriešia samé.

### Prečo `IsHTTPS` nie je v Lexical?

V praxi HTTPS reprezentuje trust/security vlastnosť spojenia. Aj keď sa textovo objaví v URL, deploymentovo nie je rovnakého typu ako počet znakov alebo subdomén. Preto ho dávame do Trust.

### Čo je najväčšie riziko EDA?

Najväčšie riziko je, že datasetové Behavior features môžu odrážať špecifiká datasetu, nie univerzálny internet. Preto kladieme dôraz na URL-only Lexical model ako prvú líniu a Behavior/FullLite používame opatrne.

---

## 12. Finálny záver EDA

EDA ukazuje, že problém nie je triviálny iba na samotnom URL, ale URL obsahuje dosť signálu na zmysluplný prvý filter. Lexical features sú samostatne slabšie a korelované, čo motivuje nelineárne modely a regularizáciu. Behavior features obsahujú extrémne silné signály, preto ich musíme kontrolovať cez FullLite. Tým EDA pripravuje metodicky čistý základ pre Scenár 2, Scenár 3 a Scenár 4.

---

## 13. Slide-by-slide naratív pre prezentáciu

Táto časť je praktický scenár, ako EDA odprezentovať nahlas. Nie je nutné povedať všetko, ale pomáha držať logiku.

### Slide 1: Čo riešime

Začal by som vetou:

> Riešime phishing detekciu v momente kliknutia na URL. Cieľ nie je len dostať vysoké AUC, ale vyrobiť rozhodnutie, ktoré vie proxy použiť okamžite: block alebo allow.

Potom treba hneď vysvetliť, prečo je URL-only dôležité:

- URL máme k dispozícii ešte pred načítaním stránky.
- Je to najlacnejší signál.
- Ak URL-only model funguje, šetrí čas aj infraštruktúru.
- Ak nefunguje, musíme ísť do drahších signálov.

### Slide 2: Dataset a rodiny features

Tu treba ukázať tabuľku Lexical / Trust / Behavior.

Hovorené vysvetlenie:

> Dataset sme nerozdelili podľa toho, ako sa stĺpce volajú, ale podľa toho, koľko by stálo získať ich v reálnom proxy scenári. Lexical je takmer zadarmo, Behavior je najdrahší, pretože už vyžaduje poznať obsah stránky.

Dôležitá obhajobová veta:

> Toto delenie je naše deploymentové rozhodnutie, nie vlastnosť datasetu.

### Slide 3: Čistenie features

Treba vysvetliť tri kategórie:

1. computed scores,
2. redundantná binárka,
3. redundantné ratios.

Hovorená verzia:

> Nechceli sme modelu nechať skratky. Ak v datasete existuje stĺpec, ktorý je už výstupom iného scoring systému, model by sa neučil phishing z URL, ale iba by kopíroval cudzie skóre. Ak existuje stĺpec odvodený z iných stĺpcov, nechceli sme zbytočne zavádzať kolinearitu.

### Slide 4: Diskriminačná sila

Tu treba povedať, prečo sú dva grafy alebo dve metriky.

> Spojité features a binárne features sa nedajú férovo merať jednou jednoduchou mierou. Preto pre spojité používame SMD a pre binárne Cramérovo V. Čitateľsky ich berieme rovnako: vyššie znamená silnejší samostatný signál.

Pointa:

> Najsilnejšie samostatné binárne signály nie sú Lexical. Lexical je slabší per-feature, preto tam očakávame väčšiu výhodu modelov, ktoré vedia kombinovať features.

### Slide 5: Kolinearita

Tu treba vysvetliť, že korelácia nie je chyba datasetu, ale prirodzený dôsledok URL.

> Dĺžka URL, počet písmen a počet číslic nie sú nezávislé. Dlhšia URL často obsahuje viac všetkého. Pre človeka je to intuitívne, pre lineárny model je to numerický problém.

Prečo to dôležité:

> Preto v Scenári 2 nepoužívame obyčajnú logistickú regresiu, ale ridge variant.

### Slide 6: Šikmosť

Hovorená verzia:

> Count-features majú dlhé chvosty. Väčšina stránok má málo určitých prvkov, ale niektoré majú extrémne veľa. Log transformácia pomáha, aby pár extrémov neriadilo celý lineárny model.

Treba zdôrazniť:

- `log1p` je bezpečné pre nuly,
- škálovanie je nutné pre SVM/KNN,
- RF transformáciu nepotrebuje.

### Slide 7: Near-leakers

Toto je kritická časť.

> Našli sme šesť Behavior features, ktoré majú samostatne AUC nad 0.95. To znamená, že jeden stĺpec takmer vyrieši klasifikáciu. Ak by sme ich nechali vo Full tieri, všetky modely by vyzerali perfektné a Scenár 2 by už neporovnával modelové rodiny.

Treba povedať:

> Preto nevznikol Full, ale FullLite.

### Slide 8: Prechod do scenárov

Záver EDA má byť most:

- Scenár 2: či nelineárne modely lepšie využijú slabší Lexical signál.
- Scenár 3: či z Lexical features vieme vybrať menší stabilný core.
- Scenár 4: ako vysvetliť rozhodovanie zložitejšieho modelu.

---

## 14. Detailné vysvetlenie jednotlivých rozhodnutí

### 14.1 Prečo nezačať rovno modelovaním

Ak by sme rovno fitovali modely, mohli by sme získať vysoké čísla, ale nevedeli by sme, prečo. EDA pred modelovaním je dôležitá z troch dôvodov:

1. identifikuje problematické features,
2. navrhuje preprocessing,
3. pomáha formulovať hypotézy tak, aby boli testovateľné.

Bez EDA by napríklad nebolo jasné, prečo FullLite existuje. Mohlo by to vyzerať ako účelové odstraňovanie silných features. EDA ukazuje, že to nie je účelové, ale metodicky nutné pre H1.

### 14.2 Prečo odstránenie skóre nie je strata informácie

Áno, odstránením skóre pravdepodobne znížime maximálny výkon. Ale cieľ projektu nie je dosiahnuť najvyšší možný výkon za každú cenu. Cieľom je porovnať modely na features, ktoré reprezentujú merateľné vlastnosti URL alebo stránky.

Ak by sme nechali `URLSimilarityIndex`, komisia by sa oprávnene mohla opýtať:

> Nie je váš model dobrý len preto, že dataset už obsahuje iný phishing scoring?

Odstránením tejto skupiny sa tejto námietke vyhneme.

### 14.3 Prečo redundantné ratios škodia najmä interpretácii

Pomerové features môžu byť prediktívne, ale sú odvodené. Ak model dostane počet písmen, dĺžku URL aj pomer písmen, dostáva rovnakú informáciu vo viacerých podobách. Pri lineárnych modeloch to spôsobuje:

- nestabilné koeficienty,
- nafúknutú dôležitosť jednej rodiny signálov,
- ťažšie vysvetlenie, prečo model používa práve pomer a nie počet.

Preto je čistejšie nechať základné counts a dĺžku.

### 14.4 Prečo neodstraňujeme všetku kolinearitu

Kolinearita sama o sebe nie je vždy dôvod vyhodiť features. Pri Lexical dĺžkovom klastri by sme mohli odstrániť napríklad `NoOfLettersInURL`, ale prišli by sme o potenciálne užitočný signál. Namiesto toho:

- v Scenári 2 používame ridge,
- v Scenári 3 necháme feature-selection metódy rozhodnúť, čo ostane.

To je lepšie než ručne odstrániť veľa stĺpcov už v EDA.

### 14.5 Prečo je FullLite lepší názov než „clean full“

FullLite presne komunikuje, že nejde o celý Full. Je to plný kombinovaný tier po odľahčení od near-leakerov. Názov zároveň upozorňuje, že sme neurobili všeobecné čistenie všetkého slabého, ale konkrétne odstránenie saturujúcich Behavior counts.

---

## 15. EDA ako argumentačný reťazec

Celý EDA príbeh sa dá povedať ako logický reťazec:

1. Chceme rýchlu phishing detekciu pred načítaním stránky.
2. Najlacnejší signál je URL string.
3. Dataset obsahuje features z rôznych deployment vrstiev.
4. Niektoré features sú nefér alebo redundantné, preto ich odstránime.
5. Lexical features sú samostatne slabšie a korelované.
6. Slabší samostatný signál znamená, že model musí využiť kombinácie.
7. Preto očakávame výhodu neparametrických modelov na Lexical tieri.
8. Behavior obsahuje near-leakery, preto Full tier upravíme na FullLite.
9. Tým vzniká férový základ pre Scenár 2 a 3.

Ak sa pri obhajobe stratíte, vráťte sa k tomuto reťazcu.

---

## 16. Silné a slabé stránky EDA

### Silné stránky

- EDA je naviazaná na reálny deployment scenár.
- Feature tiery majú praktické odôvodnenie.
- Exclusions sú explicitné a vysvetlené.
- Near-leaker analýza predchádza nefér interpretácii modelov.
- Preprocessing v modelovaní vyplýva z nameraných vlastností dát.

### Slabé stránky

- Dataset je verejný a nemusí presne reprezentovať budúci firemný traffic.
- Behavior near-leakery môžu byť datasetovo špecifické.
- EDA nemeria kauzalitu, iba asociácie.
- Lexical/Trust/Behavior rozdelenie je naše rozhodnutie, nie univerzálny štandard.

### Ako slabé stránky priznať

Dobrá formulácia:

> EDA neprehlasuje, že tieto vzťahy budú navždy platiť na každom internete. Používame ju na metodicky čisté nastavenie experimentov v tomto datasete a na transparentné oddelenie lacných a drahých signálov.

---

## 17. Rýchle odpovede na „prečo“ otázky

| Otázka | Krátka odpoveď |
|---|---|
| Prečo Lexical? | Je najlacnejší a dostupný pred načítaním stránky. |
| Prečo Trust mimo Lexical? | Ide o dôverový/deployment signál, nie čistý textový count. |
| Prečo Behavior near-leakery von? | Saturujú modely a zakrývajú H1 kontrast. |
| Prečo SMD? | Pre spojité features meria rozdiel tried v SD jednotkách. |
| Prečo Cramérovo V? | Pre binárne features je vhodnejšie než SMD. |
| Prečo ridge neskôr? | VIF ukazuje extrémnu kolinearitu. |
| Prečo log1p? | Count-features majú dlhé pravé chvosty. |
| Prečo FullLite? | Silnejší benchmark bez triviálnych near-leakerov. |

---

## 18. Jednovetové pointy na zapamätanie

- **EDA nebola iba popis dát, ale návrh experimentu.**
- **Lexical je najlacnejší, ale najťažší tier.**
- **Trust a Behavior majú silnejšie samostatné signály.**
- **Near-leakery by spravili Full tier príliš ľahký.**
- **FullLite existuje preto, aby H1 nebola zničená saturáciou.**
- **Ridge, log transformácia a škálovanie nie sú náhodné — vyplývajú z EDA.**

---

## 19. Rozšírený Q&A bank

### „Nie je odstraňovanie near-leakerov manipulácia výsledkov?“

Nie. Manipulácia by bola, keby sme ich odstránili potichu po tom, čo sa nám nehodia výsledky. My ich identifikujeme explicitne v EDA cez univariate AUC a vysvetľujeme, čo by spravili s experimentom. Navyše ich neodstraňujeme zo sveta navždy — len z tierov, kde by znemožnili test H1. Ak by cieľom bol čisto najlepší možný produkčný model po načítaní stránky, tieto features by sa dali znova zvážiť.

Krátka odpoveď:

> Nevyhadzujeme ich preto, že sú zlé, ale preto, že sú príliš silné na otázku, ktorú v H1 testujeme.

### „Prečo ste si tiery definovali sami?“

Dataset nehovorí, ktoré features sú lacné alebo drahé v proxy deployment-e. To je architektonická otázka. Preto sme museli vytvoriť vlastnú mapu podľa toho, či feature pochádza z URL stringu, trust/metadát alebo obsahu stránky.

Krátka odpoveď:

> Tiery sú súčasťou návrhu riešenia, nie slepé prevzatie datasetu.

### „Prečo nie všetko hodiť do jedného modelu a neriešiť tiery?“

Lebo by sme stratili informáciu o nákladoch. Jeden veľký model môže byť presný, ale v reálnom proxy nemusí byť dostupný včas. Tierovanie odpovedá na otázku, čo vieme rozhodnúť rýchlo a čo až po drahšej analýze.

### „Čo ak Behavior near-leakery nie sú leakage, ale legitímny signál?“

Môžu byť legitímny signál pre page-level filter. Ale pre URL-first filter dostupné nie sú a pre H1 by spôsobili saturáciu. Preto ich interpretujeme ako near-leakery vzhľadom na konkrétnu experimentálnu otázku.

### „Prečo nepoužiť text URL priamo cez NLP?“

To by bol iný typ projektu. Dataset už poskytuje ručne odvodené URL features. Priame NLP alebo character-level modely by vyžadovali inú pipeline, tokenizáciu, iné modely a inú interpretáciu. Náš projekt sa drží tabuľkového ML nad existujúcimi features.

### „Prečo EDA používa univariate AUC pri near-leakeroch?“

Pretože chceme vedieť, či jeden stĺpec sám takmer rieši úlohu. Ak feature samostatne dosiahne AUC > 0.95, nie je to len silný člen tímu — je to skoro samostatný klasifikátor.

### „Prečo Cramérovo V a nie chi-square p-value?“

P-hodnota pri veľkom datasete bude často extrémne malá aj pre malé efekty. Cramérovo V meria veľkosť efektu, čo je pre EDA užitočnejšie. Nechceme len vedieť, či vzťah existuje, ale či je silný.

### „Prečo SMD a nie Cohenovo d?“

SMD je v podstate rovnaká rodina myšlienky ako Cohenovo d: rozdiel priemerov v jednotkách variability. V dokumente používame názov SMD, lebo je popisnejší a priamo hovorí, čo počítame.

### „Prečo ste neodstránili outliery?“

Outliery v URL dĺžkach a count-features môžu byť reálny phishing signál. Ich slepé odstránenie by mohlo vyhodiť dôležité prípady. Namiesto toho používame log transformáciu, ktorá zníži extrémny vplyv, ale ponechá informáciu.

### „Čo je najdôležitejšia vec z EDA?“

Najdôležitejšie je, že EDA vytvorila férový experimentálny dizajn: vyčistené features, deployment tiery, FullLite a preprocessing rozhodnutia. Bez toho by modelové výsledky boli menej obhájiteľné.

---

## 20. Checklist pred obhajobou EDA

Pred obhajobou si treba vedieť odpovedať:

- Viem jednou vetou vysvetliť reálny proxy scenár?
- Viem vysvetliť rozdiel Lexical / Trust / Behavior?
- Viem povedať, prečo `IsHTTPS` nie je Lexical?
- Viem vymenovať tri skupiny odstránených features?
- Viem vysvetliť near-leaker bez toho, aby to znelo ako manipulácia?
- Viem vysvetliť, prečo FullLite existuje?
- Viem vysvetliť, prečo Lexical očakáva nelineárne modely?
- Viem povedať, ako EDA odôvodňuje Scenár 2?
- Viem povedať, ako EDA odôvodňuje Scenár 3?

---

## 21. Ak komisia tlačí na metodiku

### Ak sa pýtajú na štatistickú prísnosť

Povedať:

> EDA používame primárne na návrh experimentu, nie na finálne inferenčné testovanie. Finálne hypotézy sa overujú v modelovacích scenároch na hold-out/test metrikách.

### Ak sa pýtajú na generalizáciu

Povedať:

> Generalizácia mimo datasetu by vyžadovala externý validačný dataset alebo produkčný traffic. V rámci zadania transparentne oddeľujeme train/test a interpretujeme výsledky ako datasetovo podložené, nie univerzálnu pravdu o celom internete.

### Ak sa pýtajú na causalitu

Povedať:

> Netvrdíme kauzalitu. Tvrdíme prediktívnu použiteľnosť features v danom datasete a deploymentovo motivované delenie signálov.

### Ak sa pýtajú na alternatívne delenie tierov

Povedať:

> Alternatívne delenia sú možné. Naše delenie je obhájiteľné podľa okamihu dostupnosti signálu v proxy pipeline. Preto je relevantné pre náš reálny scenár.
