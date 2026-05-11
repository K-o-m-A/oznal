# Obhajoba - 15 minútový hovorený text


## 1. Úvod a dataset

Dobrý deň. Náš projekt sa zaoberá detekciou phishingových URL adries. Použili sme verejne dostupný dataset **PhiUSIIL Phishing URL Dataset**, ktorý obsahuje približne 235 tisíc riadkov a 50 prediktorov. Každý riadok reprezentuje jednu URL alebo stránku a label hovorí, či ide o phishing, alebo o legitímnu adresu.
Triedy sú v datasete približne vyvážené.

Najprv sme sa pýtali otázku, ktorá nemá v datasete priamu odpoveď: **kedy sa k hodnote daného feature dostaneme?** Z toho vyplynulo že musíme features rozdeliť do troch rodín, ktoré odzrkadľuje deployment náklady.

Prvá rodina je **Lexical**. Sú to features získané priamo z textu URL adresy - dĺžka URL, počet číslic, počet subdomén, počet špeciálnych znakov a podobne. Tieto features máme okamžite, ešte pred načítaním stránky. Sú teda najlacnejšie a v reálnom proxy nasadení ich vieme rychlo vyhodnotiť.

Druhá rodina je **Trust**. Patrí sem `IsHTTPS`, prítomnosť titulu, doménové a obsahové flagy ako `Bank`, `Pay`, `Crypto`. Tieto features už vyžadujú nejakú znalosť o doméne alebo metadátach. Mimochodom, `IsHTTPS` sme zámerne nezaradili medzi Lexical, hoci textovo je v URL - v praxi je to bezpečnostná vlastnosť spojenia, a nepredpokladáme že použitie prehliadača, ktorý neblokoval priame pripojenie na http stránku.

Tretia rodina je **Behavior**. Tu sú features odvodené z obsahu stránky - počet iframe-ov, hidden fields, externých referencií, JavaScript a CSS súborov. Tieto features sú najsilnejšie, ale aj najdrahšie: predpokladajú, že stránku už máme stiahnutú a sparsovanú.

Toto delenie nám umožňuje pýtať sa nielen „aký je najlepší model“, ale „aký je najlepší model, ak proxy musí rozhodnúť hneď, len z URL stringu“.


Z týchto 50 prediktorov sme však nepoužili všetky priamo a časť z nich sme ručne odtránili na základe pozorvania dát. Niektoré sú sú už vypočítané skóre iných systémov, iné reprezuntujú samotný link či odménu a niektoré sú redundantné. 

Z 50 prediktorov sme po analýze datasetu odstránili 10 v štyroch skupinách:

- **identifikátory** (`FILENAME`, `URL`, `Domain`, `TLD`, `Title`) - surový text, počty a dĺžky z nich už máme odvodené;
  - **vypočítané skóre** (`URLSimilarityIndex`, `TLDLegitimateProb`, `URLCharProb`) - výstupy iných phishing detektorov; nechceli sme byť meta-klasifikátor nad cudzím skóre;
  - **redundantná binárka** `HasObfuscation` - duplikuje `NoOfObfuscatedChar > 0`;
  - **pomerové features** (`LetterRatioInURL`, `DegitRatioInURL`, `ObfuscationRatio`) - algebraicky odvodené od counts a dĺžky URL, pridávajú kolinearitu.

Ostáva 40 prediktorov: 13 Lexical, 7 Trust a 20 Behavior.

---

## 4. Reálny scenár a hypotézy

Na základe datasetu sme si teda stanovili reálny scenár, ktorý chceme modelovať.
Používateľ klikne na URL v e-maile. Korporátny proxy server musí veľmi rýchlo, ešte pred načítaním stránky, povedať či stránku blokovať alebo nie. 
Najlacnejší signál je samotný text URL. Ak Lexical-only model funguje dobre, máme rýchly prvý filter. Ak nestačí, treba siahnuť po drahších kombinovaných Trust alebo Behavior signáloch.

rozdeľujeme problém na dve hypotézy.

**H1** patrí do Scenára 2: rozdiel medzi parametrickými a neparametrickými modelmi je závislý od feature tieru. Najväčší rozdiel očakávame na Lexical, lebo URL features sú samostatne slabé a signál je v ich kombináciách. Na FullLite, kde sú silné Trust a Behavior features, by sa mal rozdiel zmenšiť. Konkrétne kritériá rozoberieme pri Scenári 2.

**H2** patrí do Scenára 3: na Lexical poole existuje aspoň jedna feature-selection metóda, ktorá vyrobí kompaktný použiteľný URL filter. Konkrétne: aspoň 31 % redukcia (najviac 9 z 13 features), AUC nad 0.95 a operačný bod Sensitivity nad 0.94 a Specificity nad 0.75 pri prahu 0.5.

---

## 5. Čo ukázala EDA 

EDA potvrdila štyri kľúčové očakávania, na ktorých postavíme všetky tri scenáre.

**Prvé zistenie: Lexical features sú samostatne slabé.** Pre spojité features sme merali Standardised Mean Difference, pre binárne Cramérovo V. Obe sú normalizované do škály 0 až 1, takže výsledky sa dajú vizuálne porovnať. Ukázalo sa, že najsilnejšie samostatné signály patria do Trust a Behavior rodiny - `HasSocialNet`, `HasCopyrightInfo`, `IsHTTPS`. Lexical features majú stredné až slabé samostatné efekty. To znamená, že URL signál nie je v jednom prepínači, ale v kombinácii znakov. To je presne situácia, kde flexibilnejšie nelineárne modely mávajú výhodu.

**Druhé zistenie: Lexical features sú silne kolineárne.** Spočítali sme VIF - Variance Inflation Factor. Pre dĺžkové premenné ako `URLLength` a `NoOfLettersInURL` sme namerali VIF nad 1000. To je patologická redundancia. Pre obyčajnú logistickú regresiu by to znamenalo nestabilné koeficienty, ktoré pri minimálnej zmene dát skáču z jednej feature na druhú. Preto v Scenári 2 používame **ridge regularizáciu** ako stabilizačný zásah, nie ako trik na výkon.

**Tretie zistenie: spojité count features sú silne pravo-šikmé.** Spočítali sme skewness (Fisher–Pearson type 2) pre **všetky spojité features naprieč rodinami** (Lexical, Behavior). Z **22 spojitých features je 19 silne pravo-šikmých** (`|skew| > 2`) — z Lexical sú šikmé napríklad `URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL`, `NoOfSubDomain`, `NoOfQMarkInURL`, `NoOfOtherSpecialCharsInURL`; z Behavior `NoOfImage`, `NoOfJS`, `NoOfCSS`, `NoOfExternalRef`, `LineOfCode` a ďalšie. Väčšina URL alebo stránok má malé počty (krátke URL, jednoduché stránky), ale pár outlierov má stovky až tisíce. Pre LDA a Naive Bayes je to problém — predpokladajú približnú normalitu features. Pre vzdialenostné modely (SVM-RBF, KNN) by outliery dominovali euklidovskej vzdialenosti. Preto v Scenári 2 aplikujeme **`log1p` transformáciu** na spojité count features pred štandardizáciou — chvosty stlačí, rozdelenia sa priblížia k normálnemu, vzdialenosti sa stanú zmysluplnými.

**Štvrté zistenie: existujú near-leaker features.** V Behavior rodine sme našli šesť features, ktoré samostatne dosahujú univariate AUC nad 0.95 - napríklad `LineOfCode`, `NoOfExternalRef`, `NoOfImage`, `NoOfJS`, `NoOfCSS`. Inými slovami, jeden takýto stĺpec sám klasifikuje takmer perfektne. Pravdepodobné vysvetlenie je jednoduché: legitímne stránky sú často zložitejšie, majú viac kódu, viac obrázkov a referencií, zatiaľ čo phishingové stránky sú typicky jednoduché napodobeniny. Keby sme tieto features nechali vo Full tieri, všetky modely by saturovali pri AUC blízko 1.0 a rozdiel medzi rodinami by zmizol nie preto, že modely sú rovnako dobré, ale preto, že úloha by bola triviálna.

Preto sme zaviedli **FullLite tier**: Lexical plus Trust plus Behavior bez šiestich near-leakerov. FullLite má 34 features a stále silný signál, ale úloha už nie je triviálna a H1 gradient sa dá čítať.

---

## 6. Scenár 2 - porovnanie modelových rodín

**Hypotéza H1 (pripomenutie).** Rozdiel medzi parametrickými a neparametrickými modelmi závisí od feature tieru. Najväčší rozdiel očakávame na Lexical, lebo URL features sú samostatne slabé a signál je v ich kombináciách. Na FullLite, kde sú silné Trust a Behavior features, by sa mal rozdiel zmenšiť.

Pôvodne sme chceli AUC ako hlavnú metriku - je to štandardná voľba a krásne sa porovnáv medzi modelmi. Pri pohľade na výsledky sme však zistili, že **AUC vie byť pri našej úlohe klamlivá**. AUC meria, ako dobre model **zoradí** phishing nad legit cez všetky možné prahy, ale neovorí nič o tom, ako sa správa pri konkrétnom prahu, ktorý reálne použijeme - v našom prípade 0.5.
Preto sme pridali dve metriky, ktoré priamo zodpovedajú tomu, čo proxy reálne robí:

- **Sensitivity** = `TP / (TP + FN)` -  aký podiel phishingu sme **chytili**
  - **Specificity** = `TN / (TN + FP)` -  aký podiel legit traffic-u sme **správne pustili**

A nakoniec **minSS** = minimum z týchto dvoch. minSS je low-bar metrika: zachytáva najslabšiu z dvoch zložiek. Model so Sensitivity 0.99 a Specificity 0.40 má minSS = 0.40 - bez ohľadu na to, ako pekne vyzerá AUC, ako binárny filter zlyhal. Práve preto je C1 (kritérium pre H1) postavené nad minSS, nie nad AUC.


Aby bola H1 potvrdená, musia platiť tri kritériá súčasne:

- **C1 - veľkosť rozdielu na Lexical.** Δ minSS medzi najlepším neparametrickým a najlepším parametrickým modelom musí byť aspoň **0.10**. Prah 0.10 je deploymentovo významný - rozdiel 10 percentuálnych bodov v tom, koľko phishingu chytíme alebo koľko legit URL pustíme, je v praxi citeľný.
  - **C2 - gradient cez tiery.** „Gap“ znamená jednoducho **o koľko je najlepší neparametrický model lepší než najlepší parametrický** na danom tieri. Spočítame ho na Lexical a na FullLite. Kritérium hovorí, že tento náskok má byť **väčší na Lexical než na FullLite** - teda neparametrické modely majú výraznejšie ťahať na slabom URL signáli, a keď dostanú silnejšie Trust a Behavior features, parametrické ich majú dobehnúť. Bez tohto kritéria by sme len ukázali, že neparametrické modely sú celkovo lepšie - H1 ale tvrdí niečo silnejšie, totiž že ich výhoda **závisí od tieru**.
  - **C3 - sanity check cez AUC.** Δ AUC na Lexical musí byť aspoň **0.02**. Je to kontrola, že rozdiel existuje nielen v operating pointe pri 0.5 prahu (minSS), ale aj v poradí skóre. Ak by C1 platilo a C3 nie, rozdiel by mohol byť iba kalibračný artefakt. C3 je vedľajšie - C1 a C2 sú hlavné kritériá.

**Experimentálny dizajn.** Porovnali sme tri parametrické modely - Logistic Regression Ridge, LDA, Naive Bayes - a tri neparametrické - Random Forest, SVM-RBF, KNN. Každý model sme pustili na rovnaké štyri tiery: Lexical, Trust, Behavior bez near-leakerov a FullLite. Stratifikovaný 30-tisícový subsample, 80-20 split, hyperparametre fixné a konvenčné, lebo cieľom je férové porovnanie rodín, nie leaderboard tuning.

**Prečo 10-fold cross-validation.** Tréningovú časť rozdelíme na 10 stratifikovaných foldov, každý model fitujeme 10-krát (na 9, validujeme na 10.) a spriemerujeme. Konkrétne nám to dalo:

1. **10 odhadov namiesto jedného** - vieme rozlíšiť skutočný rozdiel medzi modelmi od šumu jedného splitu (priemer + smerodajná odchýlka cez foldy). To je dôležité najmä preto, že **viaceré modely majú AUC veľmi blízko 1.0** - rozdiely medzi nimi sú malé a bez 10 čísel by sa nedali odlíšiť od náhodného kolísania jedného splitu.
   2. **Férové párované porovnanie** - všetkých 6 modelov zdieľa rovnaké fold indexy, takže rozdiely sa počítajú na tých istých validačných setoch fold-by-fold; oddelí sa variabilita modelu od variability splitu. Pri vysokých AUC, kde sú absolútne rozdiely tesné, je párovanie kritické - bez neho by šum dominoval.

a
**Prečo prah 0.5.** Po prvé, je to **prirodzený default** - model vráti pravdepodobnosť phishingu medzi 0 a 1, a 0.5 znamená „phishing je pravdepodobnejší než legit“. Po druhé, **triedy v datasete sú približne vyvážené** (~50/50), takže 0.5 zodpovedá apriori rovnováhe a nie je potrebné ho posúvať kvôli class imbalance. Po tretie, **je to štandardný operating point v phishing literatúre aj v ML knižniciach**:

- **Akademická literatúra na phishing URL detekcii.** Liu et al., *„Efficient Phishing URL Detection Using Graph-based Machine Learning and Loopy Belief Propagation“* (arXiv:2501.06912, 2025) — autori cez grid search a ROC analýzu reportujú, že **optimálny prah je 0.5** pre balansovanie sensitivity/specificity. Druhým príkladom je *„Phishing Attack Detection on URLs using KNN, RF, DT with GA and K-fold Cross Validation Approach“* (IJRISS, 2024), kde KNN drží **discrimination threshold 0.50** a RF 0.48 na phishing URL klasifikácii.
  - **ML knižnice.** `caret::predict()`, `sklearn`, `glmnet`, `randomForest::predict()` — všetky používajú prah 0.5 ako default pri binárnej klasifikácii.
  - **Komerčné proxy systémy.** Zscaler vo svojej dokumentácii „Blocking the Unknown Threat with Machine Learning“ uvádza, že ich klasifikátor vracia ML score, na ktoré admin **nastavuje threshold** — defaultný operating point je nastaviteľný, ale štandardne sa používa balancovaná hodnota.

Keby sme prah ladili pre každý model zvlášť, miešali by sme dve veci: kvalitu modelu a kvalitu kalibrácie. Cieľ Scenára 2 je porovnanie modelových rodín, preto držíme prah jednotný.

Keby triedy **neboli vyvážené** - napríklad pri reálnom traffic-u, kde phishing tvorí len malé percento URL - 0.5 by ako default už nestačil. Modely trénované na nevyváženom datasete by predikovali pravdepodobnosti posunuté smerom k majoritnej triede a pri 0. takom prípade by sa prah musel kalibrovať buď podľa apriori distribúcie (napr. posun na pomer tried), alebo cez ROC/PR krivku na validačnom sete s ohľadom na náklady false positive vs false negative. To je samostatná úloha, ktorá by patrila pred deployment, ale nie do porovnania modelových rodín.



**Logistic Regression Ridge.** Sensitivity ~0.92, Specificity ~0.72. Chytí väčšinu phishingu, ale blokuje aj približne 28 % legitímnych URL. Ako proxy filter by spôsoboval výrazné množstvo false positives - na firemnom traffic-u by to znamenalo blokáciu množstva neškodných stránok. Lineárna hranica jednoducho nestačí na URL signál, kde rozhoduje kombinácia znakov.

**LDA.** Operating point pri 0.5 je nevyvážený - Sensitivity vysoká (cez 0.9), Specificity výrazne nižšia. Model síce phishing rozpoznáva, ale za cenu blokovania veľkého počtu legit URL. Pri prahu 0.5 nie je dobre kalibrovaný a ako binárny filter prakticky nepoužiteľný.

**Naive Bayes.** Sensitivity skoro 1.0, Specificity dramaticky nízka. Model takmer všetko označuje za phishing - to nie je bug, ale priamy dôsledok zlomeného predpokladu nezávislosti: `URLLength`, `NoOfLettersInURL` a `NoOfDegitsInURL` sú silne korelované, NB ten istý signál opakovane započíta a posunie pravdepodobnosť phishingu k 1. Pre detekciu nepoužiteľný, ale priortine aj tak slúžil na  ukazanie, akú cenu má ignorovanie korelácií.

**Random Forest.** Sensitivity vysoká, ale Specificity pri 0.5 výrazne slabšia než SVM. RF zachytáva nelineárne interakcie cez ensemble stromov, no jeho hlasovacia pravdepodobnosť nie je natívne kalibrovaná na 0.5 - phishingový hlas má tendenciu vyhrávať, takže model pustí menej phishingu, ale zase blokuje viac legit. S threshold tuningom by sa pravdepodobne približoval SVM, ale H1 porovnáva všetky modely pri rovnakom prahu.

**SVM-RBF.** Sensitivity aj Specificity blízko 0.98, minSS ~0.98 - najefektívnejší model na zachytávanie phishingu z URL stringu. Chytí takmer všetok phishing a zároveň takmer nikdy nezablokuje legit URL. SVM hľadá medzi triedami ulicu s maximálnym voľným okolím; RBF kernel umožňuje, aby bola nelineárna - okolo každého support vectora je gaussovský zvon a model rozhoduje podľa toho, či nový bod padne do oblasti, kde dominujú phishingové alebo legit zvony. Pri Lexical signáli, kde phishing nemá jeden definujúci atribút, ale kombináciu znakov (dlhá URL + veľa číslic + špeciálne znaky + veľa subdomén), je RBF prirodzená voľba. Pri 0.5 prahu funguje symetricky a nepotrebuje threshold recalibration.

SVM s RBF kernelom je v phishing URL literatúre štandardná baseline. Používajú ho napríklad:

- **Sahingoz et al.**, *„A novel lightweight URL phishing detection system using SVM and similarity index"*, Human-centric Computing and Information Sciences (Springer, 2018) — SVM-RBF so 6 lexikálnymi features, ~95.8% accuracy.
  - **„Phishing Detection Using Machine Learning Techniques"** (arXiv:2009.11116, 2020) — SVM-RBF dosahuje 0.9706 accuracy na phishing dataset.
  - **„A SVM-based Technique to Detect Phishing URLs"**, Information Technology Journal (2012) — jedna z prvých prác, ktoré zaviedli SVM s nelineárnym kernelom ako baseline pre URL phishing detection.
  - **„An application for predicting phishing attacks: A case of implementing a support vector machine learning model"**, Cyber Security and Applications (Elsevier, 2024).

Náš SVM-RBF teda nie je exotická voľba — zapadá do zavedenej tradície a naše čísla (minSS ~0.98) sú konzistentné s tým, čo táto literatúra reportuje.

**KNN.** Sensitivity aj Specificity porovnateľné so SVM, takže ako klasifikátor je rovnako efektívny. Problém je pri inferencii - pre každú novú URL musí spočítať vzdialenosť ku všetkým 24-tisícom trénovacích bodov. Pre proxy s vysokým provozom je to praktická prekážka - kvalita áno, deployment cena nie.

**Celkové zhodnotenie.** Tri parametrické modely (LR-Ridge, LDA, NB) na Lexical zlyhávajú v Specificity - Sensitivity majú vysokú, ale za cenu nadmernej blokácie legit URL. Všetky majú lineárny alebo aditívny tvar a phishing signál v kombináciách znakov nezachytia. Tri neparametrické modely (RF, SVM-RBF, KNN) Sensitivity aj Specificity vyvažujú lepšie, ale RF má kalibračný problém pri 0.5 (Specificity zaostáva) a KNN je drahý pri inferencii. SVM-RBF jediný drží **obe metriky vysoko súčasne** a po natrénovaní je to fixný malý model - kvalita zachytenia phishingu aj deploymentová praktickosť.

**Záver Scenára 2.** H1 je potvrdená: na Lexical tieri je gap v minSS približne 0.30 medzi najlepším neparametrickým modelom (SVM-RBF, ~0.98) a najlepším parametrickým (~0.69), výrazne nad prahom 0.10. Na FullLite tento gap klesá takmer na nulu - keď modely dostanú silné Trust a Behavior features, parametrické aj neparametrické saturujú a rozdiel mizne. Deploymentový víťaz pre URL-only proxy je **SVM-RBF na Lexical tieri**.

---

## 7. Scenár 3 - feature selection

Scenár 3 sa pýta inú otázku: dokážeme z 13 lexikálnych features vybrať menšiu podmnožinu, ktorá si zachová kvalitu? Cieľom je kompaktný, ľahko nasaditeľný URL filter ako alternatíva k SVM, ktorý je síce kvalitatívne najlepší, ale interpretačne ťažší.

Porovnali sme tri metódy: **bidirectional stepwise** s AIC kritériom ako algoritmický výber, **lasso** s L1 penalizáciou ako embedded výber, a **elastic-net** s alfa 0.5 ako kompromis medzi L1 a L2. Klasifikátor je vo všetkých prípadoch logistický model, takže rozdiel medzi metódami je čistý rozdiel feature selection mechanizmu.

Stepwise vybral 9 features z 13 a prešiel všetky tri prahy s pohodlnou rezervou. Lasso vybral takisto 9 features a prešiel tesne. Elastic-net nechal 10 features, čím nesplnil sparsity prah, a tesne nedosiahol ani operačný bod.

**Najsilnejší obhajobový argument je, že stepwise a lasso sa zhodli na tom istom 9-feature jadre**, hoci pracujú úplne odlišne. Stepwise pridáva a odoberá podľa AIC. Lasso tlačí koeficienty k nule cez penalizáciu. Keď dva odlišné mechanizmy nájdu rovnakých 9 features, je to silný dôkaz, že nejde o náhodný artefakt jednej metódy, ale o stabilné jadro URL signálu.

Toto jadro tvoria: `URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL`, `NoOfOtherSpecialCharsInURL`, `NoOfSubDomain`, `NoOfQMarkInURL`, `CharContinuationRate`, `TLDLength` a `IsDomainIP`.

Elastic-net je blízko, ale neprešiel - nie preto, že je zlý, ale preto, že podľa teórie pri korelovaných features drží skupinu spolu, čo zvyšuje stabilitu, ale znižuje sparsity. Toto očakávané správanie sme priznali.

---

## 8. Scenár 4 - vizualizácia rozhodovania

Scenár 4 dopĺňa interpretovateľnosť. Random Forest je presný, ale je to ensemble 300 stromov, ktorý sa nedá vizualizovať jedným diagramom. Preto sme natrénovali **surrogate strom**. Cieľová premenná tohto stromu nie je skutočný label, ale **predikcia Random Forest**. Strom sa teda neučí klasifikovať phishing - učí sa **napodobniť RF**.

Meriame fidelity, teda zhodu stromu s RF. Pri cape do 15 listov, aby strom bol čitateľný, dosahujeme fidelity okolo 0.94 na Lexical a okolo 0.97 na FullLite. Strom nie je náhrada za RF; je to vizualizačný nástroj. Tree AUC je nižší než RF AUC, čo otvorene priznávame.

Na Lexical má root split `NoOfOtherSpecialCharsInURL`, čo prekvapivo súhlasí aj s top variable importance v RF. To je dobrý cross-check - vizualizácia naozaj zachytáva to, čo RF považuje za dôležité.

---

## 9. Čo by sa dalo robiť inak

Záverom poctivo priznávame, čo sú limity a čo by bolo možné v ďalšom kroku.

Po prvé, **hyperparametre sme držali fixné**. Cieľom bolo férové porovnanie rodín, nie leaderboard. Rozsiahly grid search by mohol zlepšiť SVM alebo RF, ale za cenu toho, že by sme nevedeli, či výhra je dôsledok modelu alebo tunovania.

Po druhé, **threshold sme nekalibrovali**. Random Forest by pravdepodobne vedel posunom prahu zlepšiť Specificity. Ale H1 porovnáva modely pri jednotnom 0.5 bode, ktorý zodpovedá default deploymentu.

Po tretie, **použili sme 30-tisícový subsample**, lebo SVM-RBF má kvadratickú zložitosť v počte bodov. Plný 235-tisícový dataset by SVM trénoval hodiny per fold. Pri 30k máme stále 6-tisícový hold-out test, čo je metricky stabilné.

Po štvrté, **dataset je verejný a nemusí presne reprezentovať budúci firemný traffic**. Behavior near-leakery môžu byť datasetovo špecifické. Produkčné nasadenie by potrebovalo externú validáciu, monitoring driftu a kalibráciu prahu.

Ako follow-up by sme zvážili pridanie XGBoost-u alebo SHAP explainability pre SVM. Mohli by sme tiež skúsiť stability selection vo feature selection alebo character-level NLP modely nad surovým URL textom. To je však mimo aktuálneho zadania.

**Na záver:** projekt ukazuje, že na URL-only úlohe má SVM-RBF najlepší operačný bod, že 9 z 13 lexikálnych features tvorí stabilné jadro signálu, a že neparametrické modely majú najväčšiu výhodu práve tam, kde je signál najslabší a najťažší. Ďakujeme za pozornosť a sme pripravení odpovedať na otázky.
