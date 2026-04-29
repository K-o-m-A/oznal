# Príprava na obhajobu — `scenario_3.rmd` (stepwise vs. lasso vs. elastic-net)

---

## 0. O čom Task 3 vlastne je

Scenár 2 fixoval príznakový pool a porovnával rodiny modelov. Scenár 3 robí
opak: **fixuje model** (logistická regresia) a porovnáva, ako rôzne metódy
**výberu príznakov (feature selection, FS)** zredukujú primárny **Lexical
URL-only** pool na podmnožinu, ktorú treba reálne vyrátať pri každej predikcii.

Obhajiteľná business interpretácia: **URL-only filter je prvá a najlacnejšia
línia**. Task 3 preto primárne ukazuje, či sa dá 13 Lexical premenných zmenšiť
na kompaktnejší filter bez rozpadu AUC, Sensitivity a Specificity. FullLite je
sekundárny fallback/benchmark — ak URL-only nestačí a musíme ísť za URL do
Trust/Behavior signálov, nechceme nasadiť všetkých 34 FullLite premenných
naslepo, ale nájsť čo najmenší kombinovaný filter.

Na samotných URL featurách FS zredukuje 13 premenných na 9–11 a zároveň
stabilizuje kolineárny URL-only GLM. FullLite per-fold Wilcoxon ostáva až ako
sekundárny fallback/benchmark pre situáciu, keď URL-only nestačí.

Zadanie (bod 3) pýta porovnanie **jednej algoritmickej** FS metódy a **dvoch
embedded** metód. Vybrali sme:

- **Bidirekčný stepwise** (`MASS::stepAIC`, `direction = "both"`) — algoritmický
- **Lasso** (`glmnet`, α = 1) — embedded
- **Elastic-Net** (`glmnet`, α = 0.5) — embedded

**Ridge sme vynechali** s vedomým dôvodom: ridge nikdy nezeruje koeficienty, len
ich zmenšuje. V kontexte „koľko prediktorov nakoniec ostane" by ridge bol
trivialne 34 z 34 a nepriniesol by žiadnu informáciu k otázke, ktorú zadanie
kladie. Elastic-net je užitočnejší — sedí medzi lasso a ridge a ukazuje, čo
*mixovanie* ℓ1 a ℓ2 trestu robí so zoznamom vybraných príznakov.

---

## 1. Slovník pojmov pre Task 3

### Feature selection (FS) — algoritmická vs. embedded

**Algoritmická** (greedy, wrapper) — fituje sériu modelov, na základe nejakého
kritéria (AIC, BIC, p-value) v každom kroku zvolí najlepší pohyb (pridať /
odobrať jeden prediktor). Forward, backward, stepwise (mixed). **Nezávislá od
modelu** — môže sa kombinovať s GLM, LDA, čímkoľvek čo má likelihood / RSS.

**Embedded** — feature selection je **súčasťou samotného fitovania modelu**.
Penalizovaná likelihood: `min L(β) + λ · penalty(β)`. Ak penalta zeruje
koeficienty (ℓ1), fitting samotný robí selekciu. Lasso a elastic-net sú
embedded; ridge tiež penalizuje, ale `λ‖β‖²` má všade nenulovú deriváciu, takže
nikdy nezeruje koeficient na presne 0.

### AIC (Akaike Information Criterion)

`AIC = −2 · log L(β̂) + 2 · p`

Penalizuje pridanie každého prediktora konštantou 2. Stepwise akceptuje pohyb
iba ak AIC klesne. Praktická interpretácia: aby pridanie príznaku stálo za to,
musí zlepšiť log-likelihood aspoň o 1 (lebo `2·ΔlogL > 2`). To je **slabší prah
ako p < 0.05** (ten zhruba zodpovedá AIC poklesu o ~3.84).

**AIC vs. BIC**: BIC má penaltu `log(n) · p`, čo je pre n = 24 000 zhruba
`10.1 · p`. **BIC je oveľa prísnejší** a vybral by menej príznakov. AIC je
default v `MASS::stepAIC` a v praxi sa používa častejšie pre prediktívne úlohy
(BIC je preferovaný keď chceme „pravdivý" model, AIC keď chceme dobrý model).

### Lasso (ℓ1 regularizácia)

`min −logL(β) + λ · Σ|β_j|`

ℓ1 norma má v 0 *nediferencovateľný roh*. Keď penalty člen pretláča koeficient
proti nule, väčšina koeficientov sa zachytí presne na 0 (KKT podmienky). Preto
lasso **prirodzene robí feature selection**.

**Slabosť**: keď sú dva príznaky silne korelované, lasso si z páru vyberie
*jeden, viac-menej náhodne*, a druhý zhodí. Cez foldy môže striedať, ktorý
ostane → nestabilná selekcia.

### Ridge (ℓ2 regularizácia)

`min −logL(β) + λ · Σβ_j²`

Penalta je hladká, gradient v 0 je 0. Optimum je vždy v interiéri parametrického
priestoru, koeficienty sa **kontrahujú smerom k nule, ale nedosiahnu ju**.
Stabilizuje fit pri kolinearite (ako v Scen. 2 §4.1), ale neredukuje
dimenzionálitu.

### Elastic-Net (ℓ1 + ℓ2)

`min −logL(β) + λ · [α·Σ|β_j| + (1−α)/2 · Σβ_j²]`

α = 1 ↔ čistý lasso. α = 0 ↔ čistý ridge. α = 0.5 sme vybrali ako konvenčný
50/50 split. **Grouping effect** (Zou & Hastie 2005): pri korelovaných
príznakoch ℓ2 zložka rozdeľuje váhu medzi nich, takže elastic-net má tendenciu
*ponechať celú skupinu* alebo zhodiť celú skupinu naraz — stabilnejšie ako
čisté lasso.

### `cv.glmnet` a `lambda.min` vs `lambda.1se`

`cv.glmnet` urobí **vnorenú k-fold CV** (default 10, my dáme 5 pre rýchlosť)
naprieč širokou λ mriežkou (~100 hodnôt). Pre každú λ má CV-deviance ± SE.

- `lambda.min` = λ s najnižšou CV deviance
- `lambda.1se` = **najväčšia λ, ktorej CV deviance je v rámci 1 SE od minima**

`lambda.1se` je default Tibshirani / Hastie odporúčanie pre **parsimoniu**:
prijíma malú stratu fit-u za významne menšiu množinu príznakov a stabilnejšiu
selekciu cez CV foldy. **My používame `lambda.1se`** pre obe lasso aj EN.

### Stepwise s `keep` callback-om

`MASS::stepAIC(..., keep = function(model, AIC) {...})` zavolá `keep` v každom
kroku selekcie a uloží return value. Použili sme to, aby sme v každom kroku
zachytili kompletnú `summary(model)$coefficients` tabuľku — vrátane p-hodnôt
všetkých aktuálne zaradených prediktorov. To dáva audit log: **„v kroku 7
sme pridali `URLLength` a tým `NoOfLettersInURL` prestal byť signifikantný
(p stúplo z 0.003 na 0.31)"**.

Preto tieto časti kódu samy osebe **nemajú tabuľkový výstup**: sú to helper
funkcie. `step_keep()` iba zbiera audit trail, `fit_stepwise()` iba vráti
vybraný GLM model a `fit_glmnet()` iba vráti penalizovaný fit. Skutočný výstup z
nich sa objaví až neskôr v D1/D2/D3 tabuľkách.

---

## 2. Hypotéza a kritérium

### H2 (primárne praktické tvrdenie)

> **Na Lexical URL-only poole vieme feature selection-om získať menší
> deployable URL filter než plných 13 lexical premenných bez rozpadu held-out
> AUC, Sensitivity a Specificity.**

### Praktické rozhodovacie kritérium

Na rovnakom 80/20 splite ako Scenár 2 skórujeme tri dohodnuté FS metódy:

- stepwise,
- lasso,
- elastic-net.

Plný 13-feature Lexical pool používame len ako menovateľ sparsity (`9/13`),
nie ako ďalší D3 model. **Akceptačné kritériá** musí splniť tá istá finálna
FS metóda naraz:

| # | čo meriame | prah |
|---|---|---|
| C1 | sparsita | aspoň jedna FS metóda má `k <= 9` (≥30 % redukcia) |
| C2 | ranking toho istého redukovaného fitu | AUC ≥ 0.95 |
| C3 | operating point toho istého redukovaného fitu | Sensitivity ≥ 0.94 a Specificity ≥ 0.75 pri prahu 0.5 |

Toto je vopred zadefinované **praktické akceptačné pravidlo**, nie dodatočný
inferenčný štatistický test. Nejde o produkčný claim, ale o interný benchmark na rovnakom datasete. D3
metriky počítame iba z troch dohodnutých finálnych modelov: stepwise používa
svoj vybraný GLM a lasso/EN svoje `cv.glmnet` fit-y. Ridge nepoužívame ani ako
baseline, lebo v Tasku 3 nerobí feature selection.

**Aktuálny výsledok:** stepwise a lasso zredukovali Lexical pool na 9 príznakov,
elastic-net na 11. Stepwise a lasso spĺňajú C1, všetky tri metódy spĺňajú C2
a C3. Popri AUC reportujeme aj Sensitivity a Specificity pri prahu 0.5, presne
kvôli otázke kolegu: proxy potrebuje vedieť nielen ranking, ale aj koľko
phishingov zachytí a koľko legit stránok nechá prejsť.

FullLite per-fold Wilcoxon je sekundárny benchmark: stará očakávaná veta
`lasso < stepwise` tam nevyšla; stepwise bol naopak sparsnejší (17.6 vs 26.7
príznaku). To nie je chyba, ale fallback výsledok.

### Prečo NIE H2 typu „lasso má lepšie test AUC"?

To by bola **iná** hypotéza, ktorá nemá nič spoločné s feature selection-om.
Pri FS nás primárne zaujíma **menší deployable set**, nie to, či penalizovaná
metóda náhodou vyhrá AUC o pár tisícin. AUC/Sensitivity/Specificity preto
reportujeme ako D3 sanity-check: redukcia featur nesmie rozbiť praktický
operating point.

### Prečo to stále držíme jednoduché?

Aby sme sa vyhli prekomplikovaniu Scen. 2 (4 tiery × 6 modelov × paired
Wilcoxon naprieč rodinami). H2 je jednoduché praktické tvrdenie: URL-only
filter vieme zmenšiť a Sens/Spec/AUC stále ukazujú použiteľný operating point.
Všetko ostatné (D1/D2/D3 v §6) sú deliverables, ktoré zadanie pýta priamo.

---

## 3. Prečo bidirekčný stepwise a nie forward / backward

| smer | sila | slabosť |
|---|---|---|
| forward | rýchly, stabilný keď p < n | **lock-in**: raz pridaný príznak nikdy neopustí, aj keď neskoršie pridanie iného by ho zbytočne dublovalo |
| backward | „uvidí" celý model naraz, dobrý pri kolinearite | nefunguje keď p ≈ n; vyžaduje fitovať plný model na začiatku (môže zlyhať číselne pri saturácii) |
| **mixed (both)** | reconsideruje predošlé rozhodnutia v každom kroku → **nepodlieha lock-in-u** | ~2× pomalší ako forward (v každom kroku robí add1 aj drop1) |

V našom prípade `n = 24000, p = 34` — backward by fungoval, ale lock-in pri
forward je principiálny problém pri korelovaných príznakoch (URL-length cluster
v EDA §4.3). **Mixed je jediná naozaj defensible voľba**, ak nemáme apriórny
dôvod fixovať smer.

---

## 4. Fitovanie — implementačné detaily a poradie v notebooku

V notebooku má ísť najprv **primárny Lexical výsledok** a až potom FullLite
fallback. Primárny Lexical výsledok fitujeme raz na 80 % tréningovej časti a skórujeme
na rovnakom 20 % test sete ako Scenár 2. FullLite per-fold loop je iba
sekundárny fallback benchmark. V oboch častiach sú metódy rovnaké:

1. **stepwise**: štart z `glm(label ~ 1)`, scope `~ .` nad aktuálnym poolom
   (Lexical pre primárny fit, FullLite pre fallback). AIC pravidlo, `keep`
   callback ukladá p-hodnoty.
2. **lasso**: `cv.glmnet(alpha = 1, family = "binomial", nfolds = 5)`, vytiahneme
   `coef(.., s = "lambda.1se")`, počet ne-nulových koeficientov bez interceptu.
3. **EN**: to isté so `alpha = 0.5`.

V primárnom Lexical fite dostane každá metóda rovnakých **24 000 tréningových
riadkov** a rovnaký 6 000-riadkový test set. Vo FullLite fallback foldoch
dostane každá metóda rovnakých **~21 600 in-fold tréningových riadkov**.

FullLite foldy sú **count benchmark**, nie fold-level performance CV. Preto nie
je fatálne, že preprocessing recipe je zdedená zo Scenára 2 a fitnutá na celom
train splite; keby sme reportovali foldové AUC/Sens/Spec, preprocessing by
musel byť fitnutý vnútri každého outer foldu. `glmnet` navyše pri fite opäť
štandardizuje stĺpce interne.

### Časová náročnosť (pozorovaná)

- `stepAIC` na 24k × 34 vo FullLite fallbacku je hlavný bottleneck. Bidirekčný robí v každom kroku
  až 34 add1 + ~k drop1 evaluácií.
- `cv.glmnet` (5-fold inner): ~5–10s per fold per α.

Aktuálny uložený beh `perfold.rds` trval ~2909 s, čiže približne **48.5 min**.
Po vytvorení cache je ďalší knit inštantný až po D3 tabuľku.

---

## 5. Interpretácia výsledkov (čo povedať pri obhajobe)

### Pozorované poradie

**Primárny Lexical výsledok:** plný URL-only filter má 13 príznakov. Stepwise a
lasso ponechali 9, elastic-net 11. Toto podporuje hlavnú praktickú pointu Tasku
3: URL-only filter sa dá zmenšiť a stále reportujeme AUC, Sensitivity a
Specificity na rovnakom test sete.

**D1 stačí ako tabuľka.** Heatmapa s modrými/sivými políčkami ukazuje to isté
ako D1 tabuľka (`x` = vybrané, prázdne = zhodené). Na obhajobu je lepšia
tabuľka, lebo presne pomenuje každý ponechaný a vyradený príznak.

**Fallback FullLite benchmark:** pôvodne sme čakali `k_lasso ≤ k_EN ≤ k_step`,
ale dáta ukázali opačnú praktickú pointu:

- **stepwise**: priemerne 17.6 príznaku,
- **lasso**: priemerne 26.7 príznaku,
- **elastic-net**: priemerne 28.0 príznaku.

Interpretácia pre FullLite: stepwise začína z nulového modelu a pridáva iba tie prediktory,
ktoré znížia AIC. Pri tejto dátovej matici to vedie k menšiemu aktívnemu setu
než `lambda.1se` v glmnet-e, ktorý stále drží veľa korelovaných FullLite
prediktorov. Toto nie je implementačná chyba; je to negatívny výsledok pre
pôvodnú FullLite očakávanú vetu.

### Ktoré príznaky stratia signifikanciu (D2)

**V stepwise trace-i**: na Lexical AIC ceste (10 krokov) **žiaden prediktor
neprešiel hranicu 0.05** — D2 tabuľka „predictors that crossed the 0.05 line"
v rendrovanom notebooku je prázdna a bidirekčný stepAIC v tomto behu robí čisto
forward (z aktívneho setu sa nič nevyhodí). Zaujímavé pozorovanie sú dva
binárne prediktory pridané na konci cesty: `IsDomainIP` vstupuje v kroku 9
s p ≈ 0.999 a `NoOfQMarkInURL` v kroku 10 s p ≈ 0.809; sú to binárne príznaky
s kvázi-separáciou, takže z-test je nestabilný, ale AIC ich chce, lebo
ΔAIC < −2 (každý z nich znižuje AIC). Toto je embedded analóg toho, čo by
lasso/EN pri vyššej λ zhodili — silne korelovaný / nízkovariančný binárny
indikátor, ktorého samostatný prínos je marginálny. Ostatné prediktory
(`NoOfOtherSpecialCharsInURL`, `NoOfSubDomain`, `NoOfDegitsInURL`, `TLDLength`,
`URLLength`, `NoOfLettersInURL`, `CharContinuationRate`) majú p ≈ 0 počas
celej cesty — to je core URL-length/URL-count cluster z EDA.

**V regularizačnej ceste**: príznaky aktívne ešte pri veľkej λ sú **„core"**.
Príznaky, ktoré sa objavia až pri malej λ, sú slabé samostatne alebo
kolineárne s niečím silnejším.

### Ako jednoducho vysvetliť D2 grafy

**Stepwise graf** nie je performance graf. Je to audit toho, ako sa správa
vybraný logistický GLM počas AIC cesty. GLM znamená **Generalized Linear
Model**; u nás konkrétne `glm(..., family = binomial)`, teda logistická regresia
pre binárny label phishing / legitimate. Os x sú kroky `stepAIC`, os y sú
p-hodnoty koeficientov v log mierke a červená čiara je p = 0.05. Bod pod čiarou
znamená, že daný prediktor je v tom medzikroku individuálne signifikantný;
chýbajúci bod znamená, že prediktor vtedy ešte nebol v aktívnom modeli. Samotné
farby v grafe nie sú dobrý spôsob identifikácie featur; graf slúži ako rýchly
prehľad, či niečo prechádza cez 0.05. Konkrétne názvy a hodnoty preto čítame
z pomenovanej D2 tabuľky pod grafom (`first_step`, `last_step`, `min_p`,
`max_p`, `final_p`, `crosses_05`).

**Lasso a elastic-net** sa technicky dajú ukázať ako klasické `glmnet`
regularizačné cesty, ale to je slabý prezentačný graf: farebné krivky sa
prekrývajú a bez labelov nevidno, ktorý feature je ktorý. Preto v reporte
uprednostňujeme dva čitateľnejšie D2 výstupy: pomenované nenulové koeficienty
pri `lambda.1se` a graf/tabuľku najväčšej λ, pri ktorej je každý feature ešte
aktívny. Nula pri `lambda.1se` znamená dropped feature; vyššia aktívna λ znamená
robustnejší feature, ktorý prežije aj silnejšiu penalizáciu.

**Čo sa z toho učíme:** stabilné jadro Lexical modelu tvoria dĺžkové, početné
a špeciálno-znakové URL príznaky. Lasso ukazuje, že kompaktný model s 9
prediktormi stačí; elastic-net ponechá 11, lebo pri korelovaných URL príznakoch
radšej zachová skupinu podobných signálov. Stepwise zároveň ukazuje, že AIC
môže ponechať aj slabšie binárne indikátory, ak zlepšia celkový fit, hoci ich
samostatná Wald p-hodnota je nestabilná.

### Test metriky (D3)

Pre primárny Lexical fit reportujeme **AUC, Sensitivity, Specificity a
Accuracy**. AUC je threshold-free ranking metrika; Sensitivity a Specificity pri
prahu 0.5 sú deployment otázka: koľko phishingov zachytíme a koľko legit
stránok necháme prejsť. Metriky rátame z finálnych fitov troch dohodnutých
metód; ridge do Tasku 3 nedávame. Pri FullLite benchmarku sú hodnoty skoro
dokonalé, preto ich interpretujeme iba ako interný ceiling, nie produkčný claim.

**Pozor na interpretáciu 0.9999.** Toto je interný výsledok na PhiUSIIL s
náhodným stratifikovaným splitom, nie garancia produkčnej presnosti. Dataset je
takmer separovateľný, lebo legitímne weby majú typicky bohatú štruktúru
(title, social linky, copyright, formuláre, viac referencií), kým veľa phishing
stránok sú plytké repliky. Aj po odstránení šiestich najsilnejších page-count
near-leakerov ostáva vo FullLite dosť Trust/Behavior signálu na skoro dokonalý
random test split. V realite by sme potrebovali temporal split, domain/campaign
holdout alebo externý novší phishing feed.

---

## 6. Očakávané otázky pri obhajobe

### „Prečo ste vynechali ridge keď je v zadaní?"

Zadanie hovorí *„two embedded feature-selection methods"*. Ridge **nerobí
feature selection** v zmysle „ktoré príznaky ostanú" — všetkých 34 ostáva, len
sú menšie. V kontexte Task 3, ktorý pýta **počet ponechaných featur** a
**ktoré stratia signifikanciu**, je ridge degenerovaný prípad (k = 34
konštantne). Lepšie strávenie slotu je elastic-net, ktorý odpovedá na otázku
„je čisté ℓ1 príliš agresívne?". Ridge by sme zaradili, keby cieľom bola
*koeficient stability* alebo *prediction shrinkage*, nie selection.

### „Prečo `lambda.1se` a nie `lambda.min`?"

`lambda.min` minimalizuje CV deviance, ale jeho selekcia je nestabilná naprieč
foldami a typicky ponechá oveľa viac príznakov (často takmer toľko ako
stepwise). `lambda.1se` prijíma malú stratu fit-u za **významne menšiu a
stabilnejšiu** selekciu — čo je presne to, čo Task 3 testuje. Tibshirani &
Hastie (ESL § 7.10) to odporúčajú ako default.

### „Prečo AIC a nie BIC pri stepwise?"

AIC je default `MASS::stepAIC` a v praxi sa používa pre prediktívne úlohy.
BIC s `n = 24000` má penalty `log(24000) ≈ 10.1` per parameter, čo by sa
*priblížilo k lasso* a oslabilo by kontrast hypotézy. Použiť BIC by znamenalo
pred-staviť ruky stepwise-u. AIC je férové porovnanie.

### „Prečo AUC aj Sensitivity/Specificity?"

AUC sama nestačí na deployment. Hovorí, či model vie zoradiť phishing vyššie
ako legit naprieč všetkými prahmi. Proxy však potrebuje konkrétny operating
point: **Sensitivity** = koľko phishingov zastavíme, **Specificity** = koľko
legit stránok pustíme. Preto sú Sens/Spec v D3 tabuľke explicitne vedľa AUC.

### „Prečo v D3 nie je full lexical baseline?"

Lebo by nás prinútil zaviesť ridge alebo ukazovať nekonvergujúci unpenalised
GLM. Dohoda pre Task 3 je porovnať presne tri FS metódy: bidirectional
stepwise, lasso a elastic-net. D3 preto skóruje iba **finálny model danej
metódy**: stepwise GLM, lasso cv.glmnet a EN cv.glmnet. Plných 13 lexical
featur používame iba ako menovateľ sparsity (`9/13`), nie ako ďalší model.

### „Je vôbec realistické mať AUC/Sens/Spec okolo 0.9999?"

Ako **produkčný claim nie**. Ako **benchmarkový výsledok na tomto datasete áno**.
Musíme to pomenovať presne: PhiUSIIL je v random splite veľmi ľahký, keď model
vidí Trust/Behavior signály. Výsledok hovorí, že v rámci tejto dátovej distribúcie
je FullLite takmer separovateľný. Nehovorí, že model bude mať 0.9999 na nových
phishing kampaniach o rok neskôr. Preto to v práci interpretujeme ako interný
strop/benchmark a porovnávame FS metódy medzi sebou, nie ako garanciu reálneho
nasadenia.

### „Stepwise dáva p-hodnoty, ale lasso nie. Ako interpretujete D2 pre lasso?"

Lasso/EN nemajú „p-hodnoty" v klasickom zmysle (penalizovaný odhad nemá
asymptoticky normálnu distribúciu okolo 0 keď je penalty active). Ekvivalentom
je **regularizačná cesta**: pre každý príznak existuje λ, pri ktorej sa
koeficient prvýkrát zeruje. Príznaky, ktoré sa zerujú pri malej λ, sú „slabé"
— analóg „p > 0.05". Príznaky prežívajúce vysokú λ sú „core" — analóg silne
signifikantných. Rangové poradie je porovnateľné medzi metódami, p-hodnoty
ako čísla nie.

### „Prečo iba 1 base klasifikátor (logistická regresia)?"

Cieľom Task 3 je **kontrast medzi FS metódami**, nie medzi modelmi. Fixovaním
modelu vidíme rozdiel iba kvôli FS, nie kvôli model-family confound-u.
Logistická regresia je natívna pre všetky tri metódy: stepAIC pracuje na
GLM-och, glmnet má `family = "binomial"`. Použiť napr. RF s embedded importance
by zaviedlo iný typ FS (variable importance threshold), ktorý zadanie nepýta.

### „Prečo rovnaký subsample / split ako Scen 2?"

Aby D3 metriky redukovaných fitov boli priamo porovnateľné so Scen. 2 —
*„kompaktný URL-only filter má AUC/Sens/Spec na tom istom held-out sete"* je
tvrdenie, ktoré dáva zmysel iba ak je test set ten istý. FullLite fallback tým
pádom tiež používa rovnaký split.
Použili sme `set.seed(2026)` a identický `slice_sample` + `createDataPartition`
+ `createFolds` reťazec — bit-for-bit identické indexy.

### „Čo by sa stalo s α-tuningom v elastic-net?"

α = 0.5 je konvencia. Reálna optimálna α je niekde medzi 0.5 a 1, dala by sa
nájsť ďalším vnoreným CV (`caret::train(method = "glmnet")` to robí). My to
**nerobíme zámerne** — H2 je o porovnaní troch *konkrétnych* metód, nie o
hľadaní najlepšej α. Tuning α je ortogonálny experiment.

### „Wilcoxon na 10 foldoch má floor `1/2^10`. Nie je to slabý test?"

Áno, je. **Effect size dôležitejší ako p-hodnota** pri tomto sample budgete.
Reportujeme aj `mean(k_step) − mean(k_lasso)` v absolútnych príznakoch, čo
hovorí pravdivý príbeh. Keby sme chceli silnejší test, zvýšili by sme k na
20 alebo 30 (floor `1/2^20 ≈ 1e-6`), ale za cenu 2–3× dlhšieho behu. 10
foldov je rovnaký počet ako Scen 2, čím udržiavame paritu.

---

## 7. Čo sa NESMIE pomýliť

- **Ridge ≠ feature selection** — ak sa nás opýtajú „aký je váš tretí FS
  postup", odpoveď nie je „ridge", ale „zámerne sme ho vynechali, namiesto
  toho používame elastic-net, vysvetlenie viď §0".
- **`lambda.1se` nie je magic number** — je to konvencia preferujúca parsimoniu;
  konkrétna λ sa mení per-fold (CV ju vyberá).
- **Stepwise p-hodnoty NIE SÚ rovnaké ako p-hodnoty z `glm(... bez selekcie)`**
  — sú overoptimistické (post-selection inference problém). Reportujeme ich
  ako *deskriptívne hodnoty pozdĺž cesty*, nie ako finálne inferenčné tvrdenia.
  Ak by niekto chcel formálne post-selection p-hodnoty, treba metódy ako
  `selectiveInference` package — to je nad rámec Task 3.
- **AIC nemá jednotku „dobrý vs. zlý" v absolútnom zmysle** — porovnávajú sa
  iba *rozdiely* AIC medzi modelmi na *rovnakých* dátach. Nepoužívať na
  cross-dataset porovnanie.
- **FullLite negatívny výsledok nie je problém.** Pôvodný fallback predpoklad
  bol lasso < stepwise, ale výsledok je stepwise < lasso. Na obhajobe to treba
  povedať priamo ako sekundárny benchmark. Primárny Task 3 je Lexical URL-only:
  porovnal tri FS metódy, reportoval počty, signifikanciu/cesty a
  AUC/Sensitivity/Specificity sanity-check.
