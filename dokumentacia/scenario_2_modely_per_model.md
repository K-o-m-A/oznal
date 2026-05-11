# Scenár 2 — per-model komentár (Lexical tier, prah 0.5)

Pre každý zo šiestich modelov uvádzame:

1. **Prečo sme ho vybrali** — jedna veta zdôvodňujúca jeho miesto v experimentálnom dizajne.
2. **Hyperparametre a ich zdôvodnenie** — konkrétne nastavenie použité v `scenario_2.rmd` a prečo sme ho zvolili.
3. **Výsledky a interpretácia** — Sens/Spec pri prahu 0.5 a komentár, ako efektívne model zachytáva phishing.

---

## Logistic Regression Ridge

*Vybrali sme ho ako lineárny baseline parametrickej rodiny — najpoužívanejší klasifikátor v praxi a referenčný bod, voči ktorému meriame výhodu nelineárnych modelov.*

**Hyperparametre:**

- `alpha = 0` (čistý ridge — drží všetky features, len ich váhy stláča; nechceme robiť feature selection, to je úloha Scenára 3),
- `lambda = 0.01` (malá stabilizácia ako reakcia na VIF > 1000 v Lexical, nie agresívny tuning).

**Výsledky:** Sensitivity ~0.92, Specificity ~0.72. Chytí väčšinu phishingu, ale blokuje aj približne 28 % legitímnych URL. Ako proxy filter by spôsoboval výrazné množstvo false positives — na firemnom traffic-u by to znamenalo blokáciu množstva neškodných stránok. Lineárna hranica jednoducho nestačí na URL signál, kde rozhoduje kombinácia znakov.

---

## LDA

*Vybrali sme ho ako druhý lineárny zástupca s odlišnou matematikou — generatívny model cez Bayesovu vetu, ktorý dopĺňa LR z iného teoretického uhla a overuje, či zlyhanie lineárnej rodiny nie je špecifické pre LR.*

**Hyperparametre:** žiadne laditeľné — `caret::train(method = "lda")` priamo odhadne priemery tried a spoločnú kovariančnú maticu z dát maximálnou vierohodnosťou; štandardizovaný vstup z Receptu A (`log1p + center/scale`) zabezpečí, že odhady kovariancie nie sú dominované outliermi.

**Výsledky:** Operating point pri 0.5 je nevyvážený — Sensitivity vysoká (cez 0.9), Specificity výrazne nižšia. Model síce phishing rozpoznáva, ale za cenu blokovania veľkého počtu legit URL. Pri prahu 0.5 nie je dobre kalibrovaný a ako binárny filter prakticky nepoužiteľný.

---

## Naive Bayes

*Vybrali sme ho zámerne ako kontrolný príklad — EDA našla v Lexical extrémnu kolinearitu (VIF > 1000), takže predpoklad podmienenej nezávislosti NB je tu zaručene porušený a chceli sme empiricky ukázať jeho cenu.*

**Hyperparametre:**

- `usekernel = TRUE` (kernel density estimation pre spojité features namiesto rigidného Gauss predpokladu — naše count features sú silne pravo-šikmé a Trust binárky sú bimodálne),
- `fL = 1` (Laplace smoothing zabráni nulovým posteriorom pri nepozorovaných kombináciách v malých foldoch),
- `adjust = 1` (default šírka kernelu — netunujeme, lebo cieľom je zmerať cenu zlomenej nezávislosti, nie ju maskovať flexibilnejšou bandwidth).

**Výsledky:** Sensitivity skoro 1.0, Specificity dramaticky nízka. Model takmer všetko označuje za phishing — to nie je bug, ale priamy dôsledok zlomeného predpokladu nezávislosti: `URLLength`, `NoOfLettersInURL` a `NoOfDegitsInURL` sú silne korelované, NB ten istý signál opakovane započíta a posunie pravdepodobnosť phishingu k 1. Pre detekciu nepoužiteľný, ale primárne aj tak slúžil na ukázanie, akú cenu má ignorovanie korelácií.

---

## Random Forest

*Vybrali sme ho ako stromový ensemble zástupca neparametrickej rodiny — robustný k škálam, automaticky zachytáva nelineárne interakcie a má rozumnú interpretovateľnosť cez variable importance, ktorú využívame v Scenári 4.*

**Hyperparametre:**

- `mtry = floor(sqrt(p))` (klasická heuristika pre klasifikáciu — zabezpečí dekoreláciu stromov a tým výhodu priemerovania ensemble),
- `ntree = 300` (kompromis medzi stabilitou a tréningovým časom; viac stromov by zlepšenie už len marginalizovalo).

RF dostáva surové dáta z Receptu B **bez `log1p` a `center/scale`** — stromové prahy sú invariantné voči monotónnym transformáciám.

**Výsledky:** Sensitivity vysoká, ale Specificity pri 0.5 výrazne slabšia než SVM. RF zachytáva nelineárne interakcie cez ensemble stromov, no jeho hlasovacia pravdepodobnosť nie je natívne kalibrovaná na 0.5 — phishingový hlas má tendenciu vyhrávať, takže model pustí menej phishingu, ale zase blokuje viac legit. S threshold tuningom by sa pravdepodobne približoval SVM, ale H1 porovnáva všetky modely pri rovnakom prahu.

---

## SVM-RBF

*Vybrali sme ho ako kernel-based zástupca neparametrickej rodiny — RBF kernel meria podobnosť celých vektorov, takže prirodzene zachytí kombinácie features, na ktoré H1 ukazuje, a nepriraďuje váhy jednotlivým features (čo ho robí imúnnym voči VIF > 1000 v Lexical); zároveň je štandardná baseline v phishing literatúre.*

**Hyperparametre:**

- `C = 1` (štandardný kompromis medzi širokým marginom a toleranciou tréningových chýb — pri štandardizovaných features je `1` overený default),
- `sigma = 0.1` (stredne lokálny RBF kernel — vie sa kriviť, ale nie okolo každého bodu; blízko sklearn defaultu `1/p ≈ 0.077` pre 13 Lexical features).

**Výsledky:** Sensitivity aj Specificity blízko 0.98, minSS ~0.98 — **najefektívnejší model na zachytávanie phishingu z URL stringu**. Chytí takmer všetok phishing a zároveň takmer nikdy nezablokuje legit URL. RBF kernel umožňuje hladkú nelineárnu hranicu, ktorá zachytí, či nový bod leží v oblasti, kde dominujú phishingové alebo legit support vectory. Pri Lexical signáli, kde phishing nemá jeden definujúci atribút, ale kombináciu znakov (dlhá URL + veľa číslic + špeciálne znaky + veľa subdomén), je RBF prirodzená voľba. Pri 0.5 prahu funguje symetricky a nepotrebuje threshold recalibration.

**Literárna podpora.** SVM s RBF kernelom je v phishing URL literatúre štandardná baseline. Používajú ho napríklad:

- **Sahingoz et al.**, *„A novel lightweight URL phishing detection system using SVM and similarity index"*, Human-centric Computing and Information Sciences (Springer, 2018) — SVM-RBF so 6 lexikálnymi features, ~95.8 % accuracy.
- **„Phishing Detection Using Machine Learning Techniques"** (arXiv:2009.11116, 2020) — SVM-RBF dosahuje 0.9706 accuracy na phishing dataset.
- **„A SVM-based Technique to Detect Phishing URLs"**, Information Technology Journal (2012) — jedna z prvých prác, ktoré zaviedli SVM s nelineárnym kernelom ako baseline pre URL phishing detection.
- **„An application for predicting phishing attacks: A case of implementing a support vector machine learning model"**, Cyber Security and Applications (Elsevier, 2024).

Náš SVM-RBF teda nie je exotická voľba — zapadá do zavedenej tradície a naše čísla (minSS ~0.98) sú konzistentné s tým, čo táto literatúra reportuje.

---

## KNN

*Vybrali sme ho ako instance-based zástupca neparametrickej rodiny — najjednoduchší možný „flexibilný" model bez akejkoľvek štrukturálnej parametrizácie, ktorý dopĺňa RF (rule-based) a SVM (kernel-based) ako tretí typologický uhol pohľadu na neparametriku, čo robí podporu H1 robustnou.*

**Hyperparametre:**

- `k = 25` (kompromis: dosť veľké, aby majoritný hlas bol robustný voči 1–2 mislabeled bodom, a dosť malé, aby hranica zostala lokálna pri 24k tréningových bodoch).

**Trust tier dostane navyše Gaussian jitter** (SD = 10⁻³) cez `jitter_features()` — Trust má 7 prevažne binárnych features, takže veľa tréningových bodov má identické súradnice a `caret::knn3` by spadol s chybou „too many ties in knn"; jitter rozbije zhody bez zmeny významu dát.

**Výsledky:** Sensitivity aj Specificity porovnateľné so SVM, takže ako klasifikátor je rovnako efektívny. Problém je pri inferencii — pre každú novú URL musí spočítať vzdialenosť ku všetkým 24-tisícom trénovacích bodov. Pre proxy s vysokým provozom je to praktická prekážka — kvalita áno, deployment cena nie.

---

## Celkové zhodnotenie

Tri parametrické modely (LR-Ridge, LDA, NB) na Lexical zlyhávajú v Specificity — Sensitivity majú vysokú, ale za cenu nadmernej blokácie legit URL. Všetky majú lineárny alebo aditívny tvar a phishing signál v kombináciách znakov nezachytia. Tri neparametrické modely (RF, SVM-RBF, KNN) Sensitivity aj Specificity vyvažujú lepšie, ale RF má kalibračný problém pri 0.5 (Specificity zaostáva) a KNN je drahý pri inferencii. SVM-RBF jediný drží **obe metriky vysoko súčasne** a po natrénovaní je to fixný malý model — kvalita zachytenia phishingu aj deploymentová praktickosť.

## Záver Scenára 2

H1 je potvrdená: na Lexical tieri je gap v minSS približne 0.30 medzi najlepším neparametrickým modelom (SVM-RBF, ~0.98) a najlepším parametrickým (~0.69), výrazne nad prahom 0.10. Na FullLite tento gap klesá takmer na nulu — keď modely dostanú silné Trust a Behavior features, parametrické aj neparametrické saturujú a rozdiel mizne. Deploymentový víťaz pre URL-only proxy je **SVM-RBF na Lexical tieri**.
