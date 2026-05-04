# Scenár 3 — príprava na obhajobu

Tento dokument je rozšírená obhajobová verzia notebooku `scenario_3.rmd`. Scenár 3 nadväzuje na EDA a Scenár 2: keď už vieme, že URL-only filter má zmysel, pýtame sa, či ho vieme zmenšiť na menší počet prediktorov bez straty použiteľnej kvality.

---

## 0. Najkratšia verzia pre úvod obhajoby

Scenár 2 riešil otázku, **ktorá modelová rodina funguje lepšie pri fixnom predictor poole**. Scenár 3 drží modelovú rodinu jednoduchšiu a pýta sa inú otázku:

> Vieme z 13 lexikálnych URL features vybrať menšiu podmnožinu, ktorá stále drží AUC, Sensitivity a Specificity na použiteľnej úrovni?

Porovnávame tri feature-selection metódy:

- bidirectional stepwise cez `MASS::stepAIC`,
- lasso cez `glmnet` s `alpha = 1`,
- elastic-net cez `glmnet` s `alpha = 0.5`.

Primárny test je Lexical URL-only. H2 je podporená, pretože:

- stepwise vyberie 9 z 13 features a prejde všetky prahy,
- lasso tiež vyberie 9 z 13 features a prejde všetky prahy tesne,
- elastic-net vyberie 10 z 13 a tesne neprejde definované kritériá.

Najsilnejší obhajobový argument je, že stepwise a lasso sú úplne odlišné mechanizmy, ale zhodnú sa na rovnakom 9-feature core. To znamená, že tieto features nie sú náhodný výber jedného algoritmu, ale stabilný URL-only signál.

---

## 1. Slovník pojmov pre Scenár 3

### Feature selection

Feature selection je výber menšieho počtu prediktorov z pôvodnej množiny. Cieľom je odstrániť slabé, redundantné alebo nestabilné features a ponechať jadro signálu.

### Algoritmická feature selection

Algoritmická metóda explicitne skúša pridávať alebo odoberať features. Stepwise je takýto prístup: v každom kroku sa rozhodne, ktorý prediktor pridať alebo vyhodiť.

### Embedded feature selection

Embedded metóda robí výber priamo počas fitovania modelu. Lasso a elastic-net majú penalizáciu, ktorá niektoré koeficienty stlačí presne na nulu. Feature s nulovým koeficientom je vyradený.

### AIC

AIC je kritérium, ktoré vyvažuje kvalitu fitu a počet parametrov. Nižšie AIC je lepšie. Ak nový feature zlepší fit iba málo, AIC ho nemusí prijať, lebo trestá zbytočnú komplexitu.

### Lasso

Lasso používa L1 penalizáciu. Tá vie nastaviť niektoré koeficienty presne na nulu, takže robí feature selection.

### Ridge

Ridge používa L2 penalizáciu. Stabilizuje koeficienty, ale typicky ich nenuluje. Preto ridge nie je feature-selection metóda v zmysle „vyberieme 9 z 13“.

### Elastic-Net

Elastic-net kombinuje L1 a L2. Vie nuluť koeficienty ako lasso, ale zároveň je stabilnejší pri korelovaných features vďaka ridge zložke.

### Lambda

Lambda je sila penalizácie. Väčšia lambda znamená jednoduchší model a viac koeficientov stlačených k nule.

### `lambda.min`

`lambda.min` je hodnota lambdy s najnižšou CV chybou. Často dáva najlepšie číslo, ale môže ponechať viac features.

### `lambda.1se`

`lambda.1se` je najjednoduchší model, ktorého chyba je ešte v rámci jednej štandardnej chyby od minima. Je konzervatívnejší, menší a často stabilnejší.

### Support

Support je množina features, ktoré metóda ponechala. Ak má lasso 9-feature support, znamená to, že 9 koeficientov je nenulových.

---

## 2. Prečo Scenár 3 existuje

Scenár 2 ukázal, že Lexical URL-only model môže byť veľmi silný, najmä pri SVM-RBF. Ale deployment nie je iba o metrikách. Menší model má praktické výhody:

- jednoduchšie sa vysvetľuje,
- ľahšie sa implementuje,
- menej features znamená menej miest, kde sa môže pipeline rozbiť,
- menší feature set je stabilnejší pre monitoring,
- rýchlejšie sa dá prepočítať pri každom URL.

Scenár 3 preto hľadá kompaktný URL filter.

---

## 3. Hypotéza H2

H2:

> Na Lexical predictor poole existuje aspoň jedna feature-selection metóda, ktorá vyrobí kompaktný nasaditeľný URL filter so silnou hold-out kvalitou.

Kritériá:

| Kritérium | Prah | Význam |
|---|---:|---|
| C1 sparsity | k <= 9 z 13 | aspoň 30 % redukcia |
| C2 AUC | >= 0.95 | model stále dobre zoraďuje prípady |
| C3 operating point | Sens >= 0.94 a Spec >= 0.75 | model je použiteľný pri prahu 0.5 |

### 3.1 Prečo k <= 9

13 features je pôvodný Lexical pool. Deväť features znamená redukciu o 4, teda približne 31 %. To je dosť veľa na to, aby nešlo iba o kozmetické odstránenie jedného slabého stĺpca.

### 3.2 Prečo AUC >= 0.95

AUC 0.95 znamená veľmi dobrú schopnosť zoradiť phishing nad legitímne URL. Pre URL-only filter je to ambiciózne, ale realistické podľa výsledkov Scenára 2.

### 3.3 Prečo Sens >= 0.94 a Spec >= 0.75

Sensitivity musí byť vysoká, lebo phishing nechceme púšťať. Specificity prah 0.75 je nižší než Sensitivity prah, lebo URL-only filter je prvá línia a môže byť opatrnejší. Zároveň však nemôže blokovať príliš veľa legitímnych stránok.

---

## 4. Metódy výberu features

### 4.1 Bidirectional stepwise

Stepwise začína od jednoduchého modelu a v krokoch skúša pridať alebo odstrániť features. Bidirectional znamená, že sa vie vrátiť k predchádzajúcim rozhodnutiam. Nie je zamknutý iba do pridávania alebo iba do odoberania.

Prečo bidirectional:

- forward-only nevie vyhodiť feature, ktorý sa neskôr ukáže ako redundantný,
- backward-only začína z plného modelu, čo je pri kolinearite citlivé,
- bidirectional je flexibilnejší.

Stepwise vyberá podľa AIC, nie podľa p-hodnôt. P-hodnoty používame len diagnosticky, aby sme videli, či sa niektoré features počas cesty správajú nestabilne.

### 4.2 Lasso

Lasso je regularizovaná logistická regresia s L1 penalizáciou. Keď je feature slabý alebo redundantný, jeho koeficient môže padnúť presne na nulu. Tak feature vypadne.

Používame `lambda.1se`, nie `lambda.min`.

Prečo:

- `lambda.min` by mohla nechať viac features,
- `lambda.1se` preferuje menší model,
- deployment potrebuje stabilitu a jednoduchosť, nie posledné desatiny AUC.

### 4.3 Elastic-Net

Elastic-net kombinuje lasso a ridge. Pri `alpha = 0.5` je to stred medzi L1 a L2.

Prečo ho testujeme:

Lexical features sú korelované. Lasso si pri korelovaných features často vyberie jeden z nich a ostatné vynuluje. Elastic-net má tendenciu držať korelované features spolu, takže môže byť stabilnejší, ale nechá väčší support.

---

## 5. Setup zopakovaný zo Scenára 2

Aby bolo porovnanie férové, používame rovnaký základ:

- rovnaký 30k stratifikovaný subsample,
- rovnaký 80/20 split,
- rovnaké 10-fold CV indexy,
- rovnaký preprocessing `log1p` + `center/scale`,
- rovnaké exclusions a odstránenie near-leakerov pre FullLite.

Toto je dôležité, lebo nechceme, aby rozdiel oproti Scenáru 2 vznikol iba inou vzorkou alebo iným preprocessingom.

---

## 6. Primárny Lexical URL-only výsledok

Výsledky:

| Metóda | k z 13 | AUC | Sensitivity | Specificity | H2 |
|---|---:|---:|---:|---:|---|
| Stepwise | 9 | 0.957 | 0.949 | 0.839 | prejde |
| Lasso | 9 | 0.952 | 0.941 | 0.764 | prejde tesne |
| Elastic-Net | 10 | 0.944 | 0.936 | 0.749 | neprejde |

### 6.1 Interpretácia stepwise

Stepwise je najlepší praktický výsledok v tomto scenári. Vyberie 9 features a má najväčšiu rezervu najmä v Specificity. To znamená, že z troch redukovaných metód najlepšie zvláda legitímne URL pri prahu 0.5.

### 6.2 Interpretácia lasso

Lasso tiež vyberie 9 features a prejde všetky prahy, ale tesnejšie. Je veľmi dôležité, že sa zhodne so stepwise na rovnakom supporte. Dve rôzne metódy tým potvrdzujú rovnaké jadro.

### 6.3 Interpretácia elastic-net

Elastic-net ponechá 10 features, hlavne preto, že pri korelovaných features má tendenciu držať skupinu spolu. Pridá `DomainLength`, ktorý je korelovaný s dĺžkovými URL features. Je tesne pod kritériami, takže nie je H2 víťaz.

### 6.4 Deväťfeature core

Stepwise a lasso sa zhodnú na:

- `URLLength`,
- `NoOfLettersInURL`,
- `NoOfDegitsInURL`,
- `NoOfOtherSpecialCharsInURL`,
- `NoOfSubDomain`,
- `NoOfQMarkInURL`,
- `CharContinuationRate`,
- `TLDLength`,
- `IsDomainIP`.

Obhajobová pointa:

> Keď dva algoritmicky odlišné prístupy vyberú rovnakých 9 features, je to silnejší dôkaz než keby sme sa spoliehali iba na jednu metódu.

---

## 7. Diagnostika stepwise

Notebook ukladá p-hodnoty počas AIC cesty pomocou `keep` callbacku. To neznamená, že stepwise vyberá podľa p-hodnôt. Znamená to, že po výbere auditujeme, či features počas cesty menia signifikanciu.

V aktuálnom runi žiadny prediktor nemá `crosses_05 = TRUE`. To znamená, že žiadny aktívny feature neskáče cez hranicu 0.05 tam a späť.

Dôležité:

- URL length/count/special-char features majú silný signál,
- `IsDomainIP` a `NoOfQMarkInURL` sú slabšie a p-hodnoty čítame opatrne,
- AIC ich drží preto, že zlepšujú celkový model, nie preto, že samostatne dokazujú kauzalitu.

---

## 8. Diagnostika lasso a elastic-net

Pri lasso a elastic-net nemáme p-hodnoty. Namiesto toho čítame:

1. koeficienty pri `lambda.1se`,
2. najväčšiu lambdu, pri ktorej feature ešte zostáva aktívny.

### 8.1 Koeficienty pri `lambda.1se`

Nenulový koeficient znamená, že feature ostal v modeli. Nulový koeficient znamená, že ho penalizácia vyradila.

### 8.2 Active lambda

Ak feature prežije aj pri väčšej lambde, je silnejší. Ak sa objaví iba pri malej lambde, je slabší alebo redundantný.

### 8.3 Prečo je toto vhodné

Regularizované modely sa neinterpretujú cez p-hodnoty. Ich prirodzená interpretácia je cez penalizačnú cestu: kedy feature vypadne, pri akej sile penalizácie a s akým koeficientom.

---

## 9. FullLite stress test

Primárna H2 otázka je Lexical. FullLite používame inak: nie ako hlavný deployment verdikt, ale ako stress test feature-selection metód pri väčšom a miešanom poole 34 features.

### 9.1 Prečo FullLite nehodnotíme primárne cez AUC

FullLite je veľmi silný. V takom poole sú všetky metódy blízko perfektných metrík. AUC/Sens/Spec by teda neoddelili metódy zaujímavo. Zaujímavejšie je:

- koľko features nechajú,
- ako stabilný je počet features medzi foldmi,
- ktoré features tvoria robustné jadro.

### 9.2 Per-fold počty

Výsledný obraz:

- Stepwise necháva priemerne najmenej features, približne 17, ale má najväčší rozptyl.
- Lasso necháva približne 22 až 23 features.
- Elastic-net necháva približne 25 features a je najstabilnejší.

Interpretácia:

> Stepwise je najagresívnejší, ale menej stabilný. Elastic-net je najstabilnejší, ale najmenej úsporný. Lasso je medzi nimi.

### 9.3 Selection frequency

Notebook počíta, v koľkých z 10 foldov bol každý FullLite feature vybraný.

Univerzálne jadro 12 features sa objaví 10/10 vo všetkých metódach. Sú tam napríklad:

- `DomainLength`,
- `IsHTTPS`,
- URL counts,
- HTML `Has*` flagy.

To ukazuje, že FullLite signál má robustné jadro, na ktorom sa metódy zhodnú.

### 9.4 Kde sa metódy rozchádzajú

Rozchádzajú sa najmä pri korelovaných a slabších features:

- stepwise drží `URLLength`,
- lasso/elastic-net ho dropujú a používajú korelované náhradníky,
- lasso/elastic-net držia `Crypto` a `NoOfURLRedirect`,
- `IsDomainIP` je častejšie v regularizovaných metódach než v stepwise.

Sedem features nevybral nikto. To je užitočné pre interpretáciu: niektoré premenné nepridávajú stabilný signál v prítomnosti ostatných.

---

## 10. Prečo H2 nie je iba „ktorá metóda má najvyššie AUC“

H2 je deployment hypotéza. Nechceme len najvyššie číslo. Chceme menší model, ktorý stále spĺňa kvalitatívne prahy. Preto sa H2 skladá z troch častí:

- sparsity,
- AUC,
- operating point.

Elastic-net je blízko, ale neprejde, lebo nespĺňa definovaný sparsity limit a tesne nedrží aj metriky. To je dôležité: pravidlá sme definovali pred interpretáciou výsledku a držíme sa ich.

---

## 11. Obmedzenia a férové priznania

### 11.1 Stepwise je kritizovaná metóda

Áno, stepwise má zlú reputáciu pri inferenčnom štatistickom modelovaní, najmä keď sa p-hodnoty po stepwise interpretujú ako čisté testy. My ju používame inak:

- ako baseline algoritmickej feature selection,
- s AIC, nie p-value rozhodovaním,
- v porovnaní s lasso/elastic-net,
- s hold-out metrikami.

### 11.2 Lasso môže byť nestabilné pri korelovaných features

Áno. To je dôvod, prečo porovnávame aj elastic-net. Lasso vie z korelovanej skupiny vybrať jeden feature a ostatné vynulovať. Elastic-net môže držať skupinu spolu.

### 11.3 Elastic-net neprešiel, ale nie je zlý

Elastic-net je blízko. Jeho správanie je očakávané: stabilnejší, ale širší support. V našich pravidlách však cieľom bola aspoň 30 % redukcia a silný operating point.

### 11.4 Lexical výsledok je jeden hold-out

Primárne hodnotenie je na 20 % hold-out teste. FullLite používa foldovú distribúciu pre stabilitu supportu. Pri Lexical je výsledok jasný a support stepwise/lasso sa zhoduje, čo posilňuje dôveru.

---

## 12. Čo by sa stalo, keby...

### Keby sme použili ridge ako FS metódu

Ridge by stabilizoval koeficienty, ale nevyradil by features. Preto by nesplnil cieľ „vybrať najviac 9 z 13“.

### Keby sme použili `lambda.min`

Pravdepodobne by ostalo viac features a možno mierne lepšie AUC. Ale cieľ Scenára 3 je kompaktný deployment model. `lambda.1se` je vhodnejšie pravidlo pre jednoduchosť a stabilitu.

### Keby sme použili BIC namiesto AIC

BIC trestá počet parametrov silnejšie. Pri veľkom n by mohol byť agresívnejší a vybrať ešte menší model, ale s rizikom dropnutia slabších, no užitočných features. AIC je miernejší a vhodný baseline.

### Keby sme ladili alpha v elastic-net

Mohli by sme nájsť lepší kompromis medzi lasso a ridge. Ale Scenár 3 porovnáva jasné reprezentatívne metódy: lasso ako L1, elastic-net ako stred L1/L2. Alpha tuning by pridal ďalšiu vrstvu optimalizácie.

### Keby sme použili mutual information

Mutual information by hodnotilo features viac samostatne. My však chceme metódy, ktoré vyberajú features v kontexte logistického klasifikátora a ostatných features.

---

## 13. Časté otázky komisie

### Prečo práve tieto tri FS metódy?

Lebo pokrývajú dve rodiny: algoritmickú a embedded. Stepwise reprezentuje algoritmický výber, lasso a elastic-net embedded výber cez penalizáciu.

### Prečo držíte logistickú regresiu ako základ?

Lebo Scenár 3 má izolovať feature selection, nie porovnávať modelové rodiny. Ak by sme menili aj model, nevedeli by sme, či rozdiel spôsobila selekcia alebo klasifikátor.

### Prečo nie SVM-RBF, keď vyhral v Scenári 2?

SVM-RBF je výborný deployment kandidát, ale nie je prirodzená feature-selection metóda. Scenár 3 hľadá menší predictor set a preto používa lineárny model, kde koeficienty a nuly majú jasný význam.

### Prečo lasso a stepwise vybrali rovnakých 9 features?

Pretože tieto features tvoria silné jadro Lexical signálu. Stepwise ich vyberá cez zlepšenie AIC, lasso cez prežitie penalizácie. Zhoda dvoch mechanizmov posilňuje dôveru.

### Je stepwise víťaz, aj keď je menej stabilný na FullLite?

Pre primárny Lexical výsledok áno, lebo prejde H2 s najväčšou rezervou. FullLite ukazuje, že pri väčšom poole je stepwise agresívnejší a menej stabilný, čo férovo priznávame.

### Prečo elastic-net neprešiel, keď je stabilnejší?

Lebo stabilita nie je jediné kritérium. Elastic-net nechal 10 features a tesne nedosiahol prahy. Pre H2 sme vyžadovali kompaktnosť aj kvalitu.

### Prečo Specificity prah iba 0.75?

URL-only filter je prvá línia. Ak má byť veľmi rýchly a lacný, môže byť menej dokonalý než plný Behavior model. Ale 0.75 stále bráni tomu, aby filter blokoval väčšinu legitímnych stránok.

### Prečo je lasso pass „tesne“ stále pass?

Pretože vopred definované kritériá spĺňa. Zároveň v interpretácii uvádzame, že stepwise má väčšiu rezervu a je komfortnejší víťaz.

### Čo by ste nasadili?

Zo Scenára 2 by primárny kvalitatívny víťaz bol SVM-RBF na Lexical tieri. Zo Scenára 3 by 9-feature core slúžil ako kompaktná alternatíva alebo ako základ pre ľahší URL-only filter, keď je prioritou jednoduchosť.

---

## 14. Finálny záver Scenára 3

Scenár 3 podporuje H2. Stepwise a lasso zredukujú Lexical filter z 13 na 9 features a stále držia požadované AUC, Sensitivity a Specificity. Elastic-net je blízko, ale ponechá viac features a neprejde definované prahy.

Najdôležitejší záver nie je iba to, že stepwise vyhral. Dôležitejšie je, že stepwise a lasso — dve odlišné metódy — našli rovnaké 9-feature jadro. To robí výsledok obhájiteľnejší a ukazuje, že URL-only filter má kompaktnú, stabilnú štruktúru.

---

## 15. Detailná metodická obhajoba

### 15.1 Prečo Scenár 3 nemení modelovú rodinu

Ak by sme v Scenári 3 naraz menili aj feature selection metódu aj model, výsledok by sa ťažko interpretoval. Napríklad rozdiel medzi lasso-logreg a SVM na vybraných features by mohol byť spôsobený:

- inými features,
- inou modelovou rodinou,
- inou kalibráciou,
- inou nelinearitou.

Preto držíme klasifikátor lineárny/logistický a meníme hlavne spôsob výberu features. Tak vieme povedať, že Scenár 3 je o selekcii, nie o ďalšom modelovom súboji.

### 15.2 Prečo Scenár 3 nie je v rozpore so SVM víťazom

Scenár 2 hovorí:

> Ak chceme najlepšiu kvalitu na Lexical, SVM-RBF je najlepší kandidát.

Scenár 3 hovorí:

> Ak chceme menší, jednoduchší URL feature set, stepwise/lasso ukazujú 9-feature core.

Tieto závery sa dopĺňajú. SVM môže byť najlepší produkčný model, zatiaľ čo Scenár 3 pomáha pochopiť, ktoré URL features tvoria stabilné jadro signálu.

### 15.3 Prečo H2 používa prahy

Bez prahov by sme mohli výsledok interpretovať subjektívne:

- „9 features je dosť málo?“
- „AUC 0.944 je ešte dobré?“
- „Specificity 0.749 je skoro 0.75, počíta sa to?“

Prahy robia rozhodnutie transparentné. Elastic-net je veľmi blízko, ale podľa vopred daných pravidiel neprejde. To je metodicky čistejšie než dodatočne upraviť kritériá.

---

## 16. Feature-by-feature interpretácia 9-feature core

Táto časť pomáha vysvetliť, prečo vybrané features dávajú zmysel.

### `URLLength`

Dlhé URL môžu byť podozrivé, lebo phishing často používa dlhé cesty, tracking parametre alebo maskovanie. Samotná dĺžka nie je dôkaz phishingu, ale v kombinácii s inými znakmi je silný signál.

### `NoOfLettersInURL`

Počet písmen súvisí s dĺžkou a štruktúrou URL. Pomáha rozlíšiť, či je dlhá URL tvorená normálnym textom alebo inými znakmi.

### `NoOfDegitsInURL`

Veľa číslic v URL môže naznačovať generované tokeny, ID alebo obfuskované časti. Phishingové URL často používajú číselné sekvencie na maskovanie alebo unikátnosť.

### `NoOfOtherSpecialCharsInURL`

Špeciálne znaky sú dôležité, lebo môžu súvisieť s query parametrami, obfuskáciou alebo komplikovanou cestou. V Scenári 4 je tento feature dokonca root split Lexical surrogate stromu pre RF.

### `NoOfSubDomain`

Phishing často používa hlboké alebo zavádzajúce subdomény, napríklad aby legitímna značka vyzerala ako súčasť domény. Počet subdomén je preto dôležitý lexikálny signál.

### `NoOfQMarkInURL`

Otázniky súvisia s query stringami. Veľa alebo prítomnosť otáznikov môže naznačovať parametre, presmerovania alebo tracking. Tento feature je slabší, ale v kombinácii môže pomôcť.

### `CharContinuationRate`

Tento feature zachytáva charakter pokračovania znakov v URL. EDA ho ukázala ako jednu z najsilnejších lexikálnych výnimiek. Preto nie je prekvapivé, že ho metódy držia.

### `TLDLength`

TLD a jeho dĺžka môžu zachytávať netypické alebo menej bežné doménové koncovky. Nie je to samostatný dôkaz, ale dopĺňa štruktúru URL.

### `IsDomainIP`

Ak doména vyzerá ako IP adresa, je to podozrivé, hoci v EDA samotná binárka nebola veľmi silná. V kombinácii s ostatnými features môže zlepšiť AIC alebo logistickú hranicu.

---

## 17. Prečo niektoré features vypadnú

### `DomainLength`

Elastic-net ho drží, stepwise a lasso nie. To dáva zmysel, lebo `DomainLength` je korelovaný s inými dĺžkovými features. Elastic-net rád drží korelovanú skupinu širšie, lasso/stepwise sú prísnejšie.

### `NoOfObfuscatedChar`

Aj keď znie intuitívne dôležito, v prítomnosti iných špeciálnych znakov a count features nemusí pridávať unikátny signál. Ak ho metódy dropnú, neznamená to, že je úplne irelevantný izolovane, ale že je redundantný v spoločnom modeli.

### `NoOfEqualsInURL`, `NoOfAmpersandInURL`

Tieto query-related znaky môžu byť slabšie alebo prekrývané s inými features. Ak hlavný signál query štruktúry zachytáva `NoOfQMarkInURL` alebo špeciálne znaky, tieto dodatočné counts môžu byť nepotrebné.

---

## 18. Ako obhájiť stepwise napriek kritike

Stepwise má v štatistike zlú povesť, ale kritika má kontext. Najväčší problém vzniká, keď niekto:

- robí stepwise,
- potom reportuje p-hodnoty ako keby model nebol vybraný,
- tvrdí kauzálne závery.

My to nerobíme. Používame stepwise ako praktickú feature-selection metódu a výsledok hodnotíme na hold-out teste.

Dobrá odpoveď:

> Stepwise nepoužívame na inferenčné tvrdenie typu „tento koeficient je kauzálne významný“. Používame ho ako algoritmický baseline pre výber kompaktného supportu a porovnávame ho s embedded regularizovanými metódami.

---

## 19. Ako obhájiť lasso a elastic-net

### 19.1 Lasso

Lasso je vhodné, keď chceme sparsity. Je prirodzená metóda pre otázku „ktoré koeficienty môžu byť nula?“.

Slabina:

- pri korelovaných features môže vybrať jednu premennú zo skupiny a ostatné zahodiť.

Preto výsledok lasso neberieme izolovane, ale porovnávame so stepwise a elastic-net.

### 19.2 Elastic-net

Elastic-net rieši časť slabiny lasso. Ridge zložka stabilizuje korelované skupiny. Cena je väčší support.

Presne toto vidíme:

- elastic-net je stabilnejší,
- ale necháva viac features,
- preto nesplní náš sparsity prah.

To je dobrý výsledok, lebo správanie zodpovedá teórii.

---

## 20. Ako čítať FullLite stress test

FullLite stress test nie je druhá H2. Je to doplnková analýza stability.

### 20.1 Čo znamená mean k

Mean k je priemerný počet features, ktoré metóda nechá cez foldy. Nižšie mean k znamená agresívnejšiu redukciu.

### 20.2 Čo znamená range

Range ukazuje stabilitu počtu. Ak metóda raz vyberie 16 a inokedy 20, je menej stabilná než metóda, ktorá skoro vždy vyberie 25.

### 20.3 Čo znamená selection frequency

Ak feature vyberie metóda 10/10 foldov, je robustný. Ak 1/10, je krehký. Ak 0/10, pravdepodobne v danom poole nepridáva unikátny signál.

### 20.4 Ako interpretovať univerzálne jadro

Features vybrané 10/10 všetkými metódami sú najsilnejší FullLite core. Sú to signály, na ktorých sa zhodnú aj rozdielne algoritmy.

---

## 21. Možné námietky a najlepšie odpovede

### „Prečo ste nepoužili všetky možné FS metódy?“

Odpoveď:

> Cieľom nebolo vyčerpať katalóg metód, ale porovnať reprezentatívne rodiny. Stepwise reprezentuje algoritmický výber, lasso a elastic-net embedded penalizačný výber.

### „Prečo nepoužívate nested CV?“

Odpoveď:

> Primárny cieľ je interpretovať support a hold-out kvalitu pri fixnom splite porovnateľnom so Scenárom 2. Pri lasso/EN prebieha vnútorné CV v `cv.glmnet`; finálne hodnotenie je na hold-out teste.

### „Nie je Specificity 0.764 pri lasso nízka?“

Odpoveď:

> Je tesná, preto aj píšeme, že lasso prechádza tesne. Stepwise je komfortnejší výsledok. Lasso je dôležité hlavne preto, že nezávisle potvrdzuje rovnaký 9-feature core.

### „Elastic-net neprešiel, znamená to, že je zlý?“

Odpoveď:

> Nie. Znamená to, že pri našich prahoch nie je najkompaktnejší deployable víťaz. Jeho širší a stabilnejší support je očakávaný pri korelovaných features.

### „Prečo p-hodnoty pri stepwise vôbec ukazujete?“

Odpoveď:

> Nie ako rozhodovacie kritérium, ale ako audit. Chceme vidieť, či sa počas AIC cesty niektoré features správajú nestabilne. Výber samotný je podľa AIC.

### „Prečo 9 features, nie 8 alebo 10?“

Odpoveď:

> 9 z 13 je približne 31 % redukcia. Je to vopred stanovený kompromis: dosť prísny, aby redukcia bola významná, ale nie tak prísny, aby sme umelo nútili model stratiť kvalitu.

---

## 22. Krátke odpovede na parameter otázky

| Otázka | Odpoveď |
|---|---|
| Prečo `alpha = 1` pri lasso? | Čistá L1 penalizácia, štandard pre sparsity. |
| Prečo `alpha = 0.5` pri EN? | Stred medzi lasso a ridge, reprezentatívny kompromis. |
| Prečo `lambda.1se`? | Menší stabilnejší model v rámci 1 SE od optima. |
| Prečo AIC? | Vyvažuje fit a počet parametrov bez príliš agresívneho trestu BIC. |
| Prečo rovnaký split ako Scenár 2? | Aby rozdiely neboli spôsobené iným datasetom. |
| Prečo FullLite ako stress test? | Väčší zmiešaný pool lepšie ukáže stabilitu výberu. |

---

## 23. Jednovetové pointy na zapamätanie

- **Scenár 3 je o menšom feature sete, nie o ďalšom modelovom leaderboarde.**
- **Stepwise a lasso našli rovnakých 9 Lexical features.**
- **Elastic-net je stabilnejší, ale širší.**
- **`lambda.1se` preferuje jednoduchosť pred poslednou desatinou výkonu.**
- **FullLite ukazuje stabilitu selekcie, nie hlavný deployment verdikt.**
- **H2 je podporená, lebo existujú až dve metódy, ktoré prejdú prahy.**

---

## 24. Rozšírený Q&A bank pre Scenár 3

### „Prečo feature selection, keď SVM-RBF funguje výborne?“

Lebo výkon nie je jediný cieľ. Menší feature set je jednoduchší, lacnejší, interpretovateľnejší a vhodný ako fallback alebo lightweight variant. Scenár 3 nám tiež povie, ktoré URL features sú jadro signálu.

### „Prečo feature selection nerobíte priamo na SVM?“

SVM nemá prirodzené nulové koeficienty pre pôvodné features pri RBF kerneli. Dá sa robiť wrapper selection, ale bola by výpočtovo drahšia a menej priamo interpretovateľná. Lasso/stepwise dávajú jasný support.

### „Prečo Stepwise vyhráva, keď je stará metóda?“

V tejto úlohe nejde o inferenčné p-hodnoty, ale o praktický výber supportu. Stepwise výsledok navyše potvrdzuje lasso, čo znižuje riziko, že ide o náhodný artefakt stepwise.

### „Prečo lasso nevyhlásite za hlavného víťaza, keď je modernejšie?“

Lasso prejde, ale tesne. Stepwise má lepšiu Specificity rezervu. Modernosť metódy nie je rozhodovacie kritérium; kritériá sú sparsity, AUC a operating point.

### „Prečo elastic-net dopadol horšie, hoci má riešiť koreláciu?“

Elastic-net koreláciu rieši tak, že drží korelované features spolu. To zlepšuje stabilitu, ale znižuje sparsity. Keďže H2 vyžaduje k <= 9, elastic-net so supportom 10 neprejde.

### „Prečo nepoužívate p-hodnoty pri lasso?“

Lasso nie je klasický inferenčný model s jednoduchými p-hodnotami po selekcii. Jeho interpretácia je penalizačná cesta a nulové/nenulové koeficienty.

### „Prečo stepwise p-hodnoty označujete len ako audit?“

Pretože po selekcii nie sú klasické p-hodnoty vhodné ako čisté inferenčné testy. Používame ich na kontrolu stability počas AIC cesty, nie ako hlavný dôkaz.

### „Prečo H2 nemá prah pre precision?“

Scenár 3 nadväzuje na H1 operating point cez Sensitivity a Specificity. Precision závisí aj od prevalencie a v tomto vyváženom datasete by bola doplnková. Hlavné proxy riziká pokrývajú Sens/Spec.

### „Prečo na FullLite nerobíte H2 pass/fail?“

H2 je formulovaná pre Lexical URL-only filter. FullLite je sekundárny stress test, kde je signál silný a otázka sa mení na stabilitu a počet features.

---

## 25. Praktický naratív výsledkov

### Ako vysvetliť H2 tabuľku do 30 sekúnd

> Tri metódy sme fitli na rovnakom Lexical poole. Stepwise a lasso znížili počet features z 13 na 9 a splnili AUC aj Sens/Spec prahy. Elastic-net nechal 10 features a tesne neprešiel. H2 teda platí, lebo existujú až dve metódy, ktoré vytvoria kompaktný použiteľný URL filter.

### Ako vysvetliť rovnaký 9-feature support

> Stepwise a lasso rozmýšľajú úplne inak. Stepwise skúša AIC kroky, lasso tlačí koeficienty penalizáciou k nule. Keď obe metódy skončia pri rovnakých deviatich features, je to silný signál, že nejde o náhodnú špecialitu jednej metódy.

### Ako vysvetliť FullLite boxplot

> Boxplot nehovorí, ktorý model je najpresnejší. Hovorí, koľko features metódy typicky nechávajú cez foldy. Stepwise je najúspornejší, elastic-net najstabilnejší a najširší, lasso je medzi nimi.

---

## 26. Hlbšie metodické limity

### 26.1 Post-selection bias

Každá feature-selection metóda môže mať post-selection bias: po výbere features sa model môže zdať istejší, než by bol pri plnom zohľadnení výberového procesu. My preto neinterpretujeme koeficienty ako kauzálne dôkazy a pozeráme hold-out metriky.

### 26.2 Stabilita supportu

Lexical support vyzerá stabilný, lebo stepwise a lasso sa zhodujú. FullLite ukazuje, že pri väčšom poole môžu byť rozdiely väčšie. Preto by produkčné nasadenie malo support monitorovať pri nových dátach.

### 26.3 Prahy sú projektové rozhodnutie

Hodnoty 9 features, AUC 0.95, Sens 0.94 a Spec 0.75 nie sú prírodné konštanty. Sú to praktické kritériá pre tento projekt. Ich sila je v tom, že sú explicitné a aplikované konzistentne.

### 26.4 Korelácia medzi features

Pri korelovaných features nie je vždy dôležité, ktorý konkrétny člen skupiny vyhrá. Dôležité je, či skupina signálov ostáva reprezentovaná. Preto interpretujeme 9-feature core ako štruktúru URL signálu, nie ako absolútny večný zoznam.

---

## 27. Ak komisia tlačí na alternatívy

### Forward/backward stepwise

Forward-only by sa nevedel vrátiť a vyhodiť skorý zlý feature. Backward-only by začínal z plného modelu, čo je horšie pri kolinearite. Bidirectional je rozumnejší kompromis.

### BIC

BIC by bol prísnejší. Mohol by vybrať menej features, ale pri veľkom n by mohol až príliš tvrdo penalizovať slabšie užitočné signály. AIC je miernejší baseline.

### Recursive feature elimination

RFE je wrapper metóda a môže byť výpočtovo drahšia. Tiež silno závisí od zvoleného modelu. Scenár 3 chcel porovnať jasné algorithmic vs embedded prístupy.

### Mutual information

Mutual information môže byť užitočný filter, ale často hodnotí features jednotlivo. My chceme selection v kontexte modelu, kde feature môže byť dôležitý až v kombinácii s ostatnými.

### Stability selection

Stability selection by bola výborný follow-up, najmä pre korelované features. V našom notebooku FullLite fold frequency čiastočne slúži podobnému účelu: ukazuje, ako často feature prežíva cez resampling.

---

## 28. Checklist pred obhajobou Scenára 3

- Viem vysvetliť rozdiel medzi Scenárom 2 a 3?
- Viem povedať, prečo držíme logistický základ?
- Viem vysvetliť stepwise bez obhajovania p-hodnôt ako kauzálnych?
- Viem vysvetliť `lambda.1se`?
- Viem vysvetliť rozdiel lasso vs elastic-net?
- Viem vymenovať aspoň 5 z 9 core features a ich význam?
- Viem povedať, prečo elastic-net neprešiel?
- Viem vysvetliť FullLite stress test?
- Viem priznať post-selection bias?
- Viem formulovať finálny H2 verdikt jednou vetou?
