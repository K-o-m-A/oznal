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

**Prečo presne LR-Ridge a nie obyčajná LR.** Predstavme si, že má model rozhodnúť, koľkú váhu dá `URLLength` a koľkú `NoOfLettersInURL`. Lenže tieto dve features sa hýbu skoro rovnako — keď je URL dlhšia, prirodzene má aj viac písmen. Z pohľadu modelu je to ako keby ho dvaja ľudia hovorili to isté. Optimalizátor sa rozhoduje takmer náhodne: raz „počúvne“ dĺžku URL, inokedy počet písmen, niekedy si dá jednému plus a druhému mínus. Výsledné koeficienty sa pri každom novom rozdelení dát výrazne menia, niekedy aj prepnú znamienko.

To by spravilo náš experiment **nedôveryhodným**: keby LR vyšlo na jednom fold-e horšie než LDA, nevedeli by sme, či je to vlastnosť LR rodiny, alebo len fakt, že sa optimalizátor v tomto fold-e pokazil. Ridge dodá jemnú **„pokutu za veľké váhy“**, ktorá donúti model rozdeliť signál medzi korelované features rovnomerne namiesto náhodného hádzania na jednu z nich. Koeficienty sú tým fold-by-fold konzistentné a porovnanie LR voči LDA, RF, SVM má zmysel. Nie je to teda trik na lepší výkon — je to čisto **stabilizácia**, aby sme vôbec mohli hovoriť o „výkone LR“.

### 28.2 LDA — princíp a hyperparametre

**Princíp.** LDA (Linear Discriminant Analysis) je generatívny klasifikátor: namiesto modelovania `P(trieda | x)` priamo (ako logistická regresia) modeluje **rozdelenie features v každej triede** `P(x | trieda)` a `P(trieda)`, a cez Bayesovu vetu z toho odvodí `P(trieda | x)`.

Konkrétne predpoklady:

1. Vektor features `x` v každej triede `k` má **mnohorozmerné normálne rozdelenie** so svojim priemerom `μₖ` a **spoločnou kovariančnou maticou Σ** (rovnakou pre všetky triedy — to je kľúčové, odtiaľ pochádza „linear“ v názve).
2. Priori `πₖ = P(trieda = k)` sú odhadnuté z pomeru tried v tréningu.

Z týchto predpokladov sa odvodí **diskriminačná funkcia** `δₖ(x) = xᵀΣ⁻¹μₖ − ½μₖᵀΣ⁻¹μₖ + log(πₖ)`. Bod sa zaradí do triedy s najvyššou hodnotou `δₖ`. Keďže `δₖ` je v `x` lineárna a kovariančná matica je spoločná, **rozhodovacia hranica medzi dvomi triedami je lineárna** (rovina v priestore features).

Geometrická interpretácia: každú triedu reprezentuje stred `μₖ` a spoločná Σ definuje, ako sú dáta okolo stredu rozprestreté a korelované. Vzdialenosť bodu od stredu sa nemeria euklidovsky, ale **Mahalanobisovou vzdialenosťou** `(x − μₖ)ᵀΣ⁻¹(x − μₖ)`, ktorá zohľadňuje šírku a tvar oblaku — bod ďaleko v smere, kde sú dáta rozptýlené, je „bližšie“ než bod blízko v smere, kde sú zhustené. Bod sa zaradí do triedy, ktorej Mahalanobisove vzdialenosť je menšia, korigovane o `log(πₖ)`.

**Učené parametre.** Priemery `μ_phishing`, `μ_legit` (vektory dĺžky `p`) a spoločná kovariančná matica `Σ` (rozmer `p × p`) — všetky odhadnuté z tréningových dát maximálnou vierohodnosťou. Žiadny tuning hyperparameter v zmysle SVM-`C` alebo ridge-`λ`.

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

> SVM-RBF priraďuje každú novú URL na základe jej **podobnosti s tréningovými bodmi**. Pre každý support vector (phishing aj legit) sa spočíta, **ako blízko k nemu nový bod leží** podľa Gaussovskej vzdialenosti — čím bližšie, tým väčší vplyv má daný support vector na predikciu. Príspevky support vectorov sa sčítajú a model rozhodne podľa toho, či prevažuje váha phishing alebo legit support vectorov v okolí. Hyperparameter `sigma` určuje, **ako ďaleko siaha „okolie"** — malé `sigma` znamená, že vplyv má len naozaj blízke okolie, veľké `sigma` znamená, že aj vzdialenejšie body prispievajú.

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

**Geometrická intuícia.** SVM má dva ciele, ktoré sú v napätí: (1) **maximalizovať margin** — vzdialenosť medzi rozhodovacou hranicou a najbližšími bodmi tried, a (2) **minimalizovať klasifikačné chyby** na tréningu. Hyperparameter `C` určuje, ktorému cieľu dá optimalizátor väčšiu váhu. Nízke `C` uprednostní široký margin, aj keď to znamená, že niekoľko bodov skončí na nesprávnej strane hranice (mäkký margin). Vysoké `C` uprednostní bezchybnú klasifikáciu, aj keď to znamená úzky margin a hranicu, ktorá sa miestne ohýba okolo jednotlivých bodov (tvrdý margin).

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

**Geometrická intuícia.** Každý support vector prispieva k predikcii podľa Gaussovskej funkcie `exp(−σ‖x − xᵢ‖²)`. Hyperparameter `sigma` určuje, **ako rýchlo tento príspevok klesá so vzdialenosťou**:

- Pri **malom `sigma`** príspevok klesá pomaly. Aj vzdialenejšie support vectory ovplyvňujú predikciu, ich príspevky sa sčítavajú a vytvárajú **hladkú globálnu hranicu** (model rozhoduje v širokom kontexte).
- Pri **veľkom `sigma`** príspevok klesá rýchlo. Predikciu určujú prakticky len najbližšie support vectory, takže hranica sa **prispôsobuje lokálnym zhlukom** a stáva sa nelineárnou až fragmentovanou.

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
