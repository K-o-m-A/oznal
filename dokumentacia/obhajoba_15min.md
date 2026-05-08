# Obhajoba — 15 minútový hovorený text

Tento dokument je súvislý hovorený scenár pre 15 minútovú obhajobu. Je písaný tak, aby sa dal čítať priamo a aby obsah dával zmysel aj bez vizuálnych podkladov. Časové orientačné body sú v hraniciach jednotlivých sekcií. Predpokladáme, že obhajobu vedieme vo dvojici a striedame sa v sekciách (poznamenané pri každej časti).

---

## 1. Úvod a dataset (cca 0:00 – 1:30, osoba A)

Dobrý deň. Náš projekt sa zaoberá detekciou phishingových URL adries. Použili sme verejne dostupný dataset **PhiUSIIL Phishing URL Dataset**, ktorý obsahuje približne 235 tisíc riadkov a 50 prediktorov. Každý riadok reprezentuje jednu URL alebo stránku a label hovorí, či ide o phishing, alebo o legitímnu adresu.

Triedy sú v datasete približne vyvážené. To znamená, že nemusíme riešiť class imbalance, váženie tried ani SMOTE. Vyhli sme sa tak ďalšej vrstve metodických rozhodnutí, ktoré by skomplikovali porovnanie modelov. Zároveň v datasete nie sú chýbajúce hodnoty, takže nemusíme imputovať a žiadny model nie je porovnávaný po inom doplnení dát ako iný.

Z týchto 50 prediktorov sme však nepoužili všetky priamo. Niektoré sú identifikátory, niektoré sú už vypočítané skóre iných systémov a niektoré sú redundantné. To, čo sme s dátami spravili pred modelovaním, je veľká časť hodnoty našej EDA — a to je aj dôvod, prečo o tom hovoríme hneď na začiatku.

---

## 2. Rozdelenie features do rodín (cca 1:30 – 3:00, osoba A)

Najprv sme sa pýtali otázku, ktorá nemá v datasete priamu odpoveď: **kedy je daný feature reálne dostupný v deployment scenári?** Z toho vyplynulo naše delenie do troch rodín, ktoré nie je arbitrárne, ale odzrkadľuje deployment náklady.

Prvá rodina je **Lexical**. Sú to features získané priamo z textu URL adresy — dĺžka URL, počet číslic, počet subdomén, počet špeciálnych znakov, dĺžka TLD a podobne. Tieto features máme okamžite, ešte pred načítaním stránky. Sú teda najlacnejšie a v reálnom proxy nasadení ich vieme spočítať za pár mikrosekúnd.

Druhá rodina je **Trust**. Patrí sem `IsHTTPS`, prítomnosť titulu, doménové a obsahové flagy ako `Bank`, `Pay`, `Crypto`. Tieto features už vyžadujú nejakú znalosť o doméne alebo metadátach. Mimochodom, `IsHTTPS` sme zámerne nezaradili medzi Lexical, hoci textovo je v URL — v praxi je to bezpečnostná vlastnosť spojenia, nie čistý lexikálny počet.

Tretia rodina je **Behavior**. Tu sú features odvodené z obsahu stránky — počet iframe-ov, hidden fields, externých referencií, JavaScript a CSS súborov. Tieto features sú najsilnejšie, ale aj najdrahšie: predpokladajú, že stránku už máme stiahnutú a sparsovanú.

Toto delenie nám umožňuje pýtať sa nielen „aký je najlepší model“, ale „aký je najlepší model, ak proxy musí rozhodnúť hneď, len z URL stringu“.

---

## 3. Manuálne odstránenie features (cca 3:00 – 4:30, osoba A)

Z 50 prediktorov sme po EDA odstránili 10. Robíme to vedome a vieme každú skupinu odôvodniť.

Po prvé, **identifikátory** ako `FILENAME`, `URL`, `Domain`, `TLD` a `Title` nie sú numerické features. Z nich sú už odvodené počty a dĺžky, takže surový text ako prediktor nepotrebujeme.

Po druhé, **vypočítané skóre** ako `URLSimilarityIndex`, `TLDLegitimateProb`, `URLCharProb` a podobné. Tieto stĺpce nie sú surové merania, ale výstupy iných phishing detektorov alebo expertných pravidiel. Keby sme ich nechali, model by sa učil dôverovať cudziemu skóre. Komisia by sa potom oprávnene mohla pýtať, či nie sme len meta-klasifikátor nad hotovým skóre. Tomu sme sa chceli vyhnúť.

Po tretie, **redundantná binárka** `HasObfuscation`. Tá hovorí len, či `NoOfObfuscatedChar` je väčšie ako nula. Keď máme presný počet, binárka nepridáva nič nové.

Po štvrté, **pomerové features** ako `LetterRatioInURL`, `DegitRatioInURL` a `ObfuscationRatio`. Tieto sú algebraicky odvodené od counts a dĺžky URL. Pre lineárne modely to spôsobuje kolinearitu, pre stromy to umelo posilňuje rovnakú rodinu signálov.

Po týchto exclusions ostáva 40 prediktorov: 13 Lexical, 7 Trust a 20 Behavior. Tento stav je východiskom pre EDA aj pre všetky tri scenáre.

---

## 4. Reálny scenár a hypotézy (cca 4:30 – 6:30, osoba A)

Predstavme si reálnu situáciu. Používateľ klikne na URL v e-maile, chate alebo vyhľadávači. Korporátny proxy server musí veľmi rýchlo, ešte pred načítaním stránky, povedať „block“ alebo „allow“. Najlacnejší signál je samotný text URL. Ak Lexical-only model funguje dobre, máme rýchly prvý filter. Ak nestačí, treba siahnuť po drahších Trust alebo Behavior signáloch.

Z tohto scenára plynú dve veci, ktoré opakovane spomíname.

Prvá: nehodnotíme len AUC. AUC je threshold-free metrika, hovorí, ako dobre model zoradí phishing nad legit. Lenže proxy nerobí ranking, robí binárne rozhodnutie pri prahu 0.5. Preto pozeráme aj **Sensitivity** (koľko phishingu chytíme), **Specificity** (koľko legit pustíme) a najmä **minSS** — minimum z týchto dvoch. Model so Sensitivity 0.99 a Specificity 0.40 nie je dobrý proxy filter.

Druhá: rozdeľujeme problém na dve hypotézy.

**H1** patrí do Scenára 2: rozdiel medzi parametrickými a neparametrickými modelmi je závislý od feature tieru. Najväčší rozdiel očakávame na Lexical, lebo URL features sú samostatne slabé a signál je v ich kombináciách. Na FullLite, kde sú silné Trust a Behavior features, by sa mal rozdiel zmenšiť. Kritérium: na Lexical Δ minSS aspoň 0.10, a tento gap musí byť väčší ako gap na FullLite.

**H2** patrí do Scenára 3: na Lexical poole existuje aspoň jedna feature-selection metóda, ktorá vyrobí kompaktný použiteľný URL filter. Konkrétne: aspoň 31 % redukcia (najviac 9 z 13 features), AUC nad 0.95 a operačný bod Sensitivity nad 0.94 a Specificity nad 0.75 pri prahu 0.5.

---

## 5. Čo ukázala EDA (cca 6:30 – 9:00, osoba A končí, osoba B preberá)

EDA potvrdila tri kľúčové očakávania, na ktorých postavíme všetky tri scenáre.

**Prvé zistenie: Lexical features sú samostatne slabé.** Pre spojité features sme merali Standardised Mean Difference, pre binárne Cramérovo V. Obe sú normalizované do škály 0 až 1, takže výsledky sa dajú vizuálne porovnať. Ukázalo sa, že najsilnejšie samostatné signály patria do Trust a Behavior rodiny — `HasSocialNet`, `HasCopyrightInfo`, `IsHTTPS`. Lexical features majú stredné až slabé samostatné efekty. To znamená, že URL signál nie je v jednom prepínači, ale v kombinácii znakov. To je presne situácia, kde flexibilnejšie nelineárne modely mávajú výhodu.

**Druhé zistenie: Lexical features sú silne kolineárne.** Spočítali sme VIF — Variance Inflation Factor. Pre dĺžkové premenné ako `URLLength` a `NoOfLettersInURL` sme namerali VIF nad 1000. To je patologická redundancia. Pre obyčajnú logistickú regresiu by to znamenalo nestabilné koeficienty, ktoré pri minimálnej zmene dát skáču z jednej feature na druhú. Preto v Scenári 2 používame **ridge regularizáciu** ako stabilizačný zásah, nie ako trik na výkon.

**Tretie zistenie: existujú near-leaker features.** V Behavior rodine sme našli šesť features, ktoré samostatne dosahujú univariate AUC nad 0.95 — napríklad `LineOfCode`, `NoOfExternalRef`, `NoOfImage`, `NoOfJS`, `NoOfCSS`. Inými slovami, jeden takýto stĺpec sám klasifikuje takmer perfektne. Pravdepodobné vysvetlenie je jednoduché: legitímne stránky sú často zložitejšie, majú viac kódu, viac obrázkov a referencií, zatiaľ čo phishingové stránky sú typicky jednoduché napodobeniny. Keby sme tieto features nechali vo Full tieri, všetky modely by saturovali pri AUC blízko 1.0 a rozdiel medzi rodinami by zmizol nie preto, že modely sú rovnako dobré, ale preto, že úloha by bola triviálna.

Preto sme zaviedli **FullLite tier**: Lexical plus Trust plus Behavior bez šiestich near-leakerov. FullLite má 34 features a stále silný signál, ale úloha už nie je triviálna a H1 gradient sa dá čítať.

EDA tým pádom nie je len opis dát. Je to návrh experimentu: motivuje ridge, motivuje `log1p` transformáciu pre dlhé pravé chvosty count features, motivuje štandardizáciu pre vzdialenostné modely a motivuje FullLite namiesto Full.

---

## 6. Scenár 2 — porovnanie modelových rodín (cca 9:00 – 11:30, osoba B)

V Scenári 2 sme porovnali tri parametrické modely — Logistic Regression Ridge, LDA a Naive Bayes — a tri neparametrické — Random Forest, SVM-RBF a KNN. Každý model sme pustili na rovnaké štyri tiery: Lexical, Trust, Behavior bez near-leakerov a FullLite. Použili sme stratifikovaný 30-tisícový subsample, 80-20 split a 10-fold CV. Hyperparametre sme držali fixné a konvenčné, lebo cieľom je férové porovnanie rodín, nie leaderboard tuning.

**H1 sa potvrdila.** Na Lexical tieri je rozdiel v minSS približne 0.30 medzi najlepším neparametrickým a najlepším parametrickým modelom — výrazne nad našim prahom 0.10. Na FullLite tento rozdiel klesá takmer na nulu. To je presne gradient, ktorý hypotéza predpovedala.

Deploymentový víťaz na Lexical je **SVM-RBF**. Má vysokú Sensitivity aj vysokú Specificity pri prahu 0.5. Vysvetlím prečo.

SVM-RBF hľadá medzi triedami ulicu s maximálnym voľným okolím. RBF kernel umožňuje, aby táto ulica bola nelineárna — predstavme si, že okolo každého support vectora je gaussovský zvon a model rozhoduje podľa toho, či nový bod padne do oblasti, kde dominujú phishingové zvony alebo legit. Parametre `C` a `sigma` riadia, ako prísne sa trestajú tréningové chyby a ako lokálne zvony pôsobia.

Pri Lexical signáli, kde phishing nemá jeden definujúci atribút, ale kombináciu znakov — dlhá URL plus veľa číslic plus podivné špeciálne znaky plus veľa subdomén — je RBF prirodzená voľba. Random Forest je tiež silný, ale jeho hlasovacia pravdepodobnosť pri 0.5 nie je tak dobre kalibrovaná. Pri Lexical má RF dobré AUC, ale slabšiu Specificity. KNN dosahuje porovnateľnú kvalitu ako SVM, ale pri inferencii musí pre každú novú URL spočítať vzdialenosť ku všetkým 24-tisícom trénovacích bodov. Pre proxy s vysokým provozom je to praktická prekážka.

Z parametrických modelov LR-Ridge dosahuje Sensitivity okolo 0.92, ale Specificity len 0.72 — model chytí phishing, ale blokuje veľa legit URL. LDA má dobré AUC, ale slabú kalibráciu pri 0.5. Naive Bayes zaujímavo dopadol nevyvážene — Sensitivity skoro 1, Specificity dramaticky nízka. To nie je bug, je to interpretovateľný dôsledok zlomeného predpokladu nezávislosti: dĺžka URL, počet písmen a počet číslic spolu úzko súvisia, takže NB ten istý signál opakovane započíta.

---

## 7. Scenár 3 — feature selection (cca 11:30 – 13:00, osoba B)

Scenár 3 sa pýta inú otázku: dokážeme z 13 lexikálnych features vybrať menšiu podmnožinu, ktorá si zachová kvalitu? Cieľom je kompaktný, ľahko nasaditeľný URL filter ako alternatíva k SVM, ktorý je síce kvalitatívne najlepší, ale interpretačne ťažší.

Porovnali sme tri metódy: **bidirectional stepwise** s AIC kritériom ako algoritmický výber, **lasso** s L1 penalizáciou ako embedded výber, a **elastic-net** s alfa 0.5 ako kompromis medzi L1 a L2. Klasifikátor je vo všetkých prípadoch logistický model, takže rozdiel medzi metódami je čistý rozdiel feature selection mechanizmu.

Stepwise vybral 9 features z 13 a prešiel všetky tri prahy s pohodlnou rezervou. Lasso vybral takisto 9 features a prešiel tesne. Elastic-net nechal 10 features, čím nesplnil sparsity prah, a tesne nedosiahol ani operačný bod.

**Najsilnejší obhajobový argument je, že stepwise a lasso sa zhodli na tom istom 9-feature jadre**, hoci pracujú úplne odlišne. Stepwise pridáva a odoberá podľa AIC. Lasso tlačí koeficienty k nule cez penalizáciu. Keď dva odlišné mechanizmy nájdu rovnakých 9 features, je to silný dôkaz, že nejde o náhodný artefakt jednej metódy, ale o stabilné jadro URL signálu.

Toto jadro tvoria: `URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL`, `NoOfOtherSpecialCharsInURL`, `NoOfSubDomain`, `NoOfQMarkInURL`, `CharContinuationRate`, `TLDLength` a `IsDomainIP`.

Elastic-net je blízko, ale neprešiel — nie preto, že je zlý, ale preto, že podľa teórie pri korelovaných features drží skupinu spolu, čo zvyšuje stabilitu, ale znižuje sparsity. Toto očakávané správanie sme priznali.

---

## 8. Scenár 4 — vizualizácia rozhodovania (cca 13:00 – 14:00, osoba B)

Scenár 4 dopĺňa interpretovateľnosť. Random Forest je presný, ale je to ensemble 300 stromov, ktorý sa nedá vizualizovať jedným diagramom. Preto sme natrénovali **surrogate strom**. Cieľová premenná tohto stromu nie je skutočný label, ale **predikcia Random Forest**. Strom sa teda neučí klasifikovať phishing — učí sa **napodobniť RF**.

Meriame fidelity, teda zhodu stromu s RF. Pri cape do 15 listov, aby strom bol čitateľný, dosahujeme fidelity okolo 0.94 na Lexical a okolo 0.97 na FullLite. Strom nie je náhrada za RF; je to vizualizačný nástroj. Tree AUC je nižší než RF AUC, čo otvorene priznávame.

Na Lexical má root split `NoOfOtherSpecialCharsInURL`, čo prekvapivo súhlasí aj s top variable importance v RF. To je dobrý cross-check — vizualizácia naozaj zachytáva to, čo RF považuje za dôležité.

---

## 9. Čo by sa dalo robiť inak (cca 14:00 – 15:00, obaja)

Záverom poctivo priznávame, čo sú limity a čo by bolo možné v ďalšom kroku.

Po prvé, **hyperparametre sme držali fixné**. Cieľom bolo férové porovnanie rodín, nie leaderboard. Rozsiahly grid search by mohol zlepšiť SVM alebo RF, ale za cenu toho, že by sme nevedeli, či výhra je dôsledok modelu alebo tunovania.

Po druhé, **threshold sme nekalibrovali**. Random Forest by pravdepodobne vedel posunom prahu zlepšiť Specificity. Ale H1 porovnáva modely pri jednotnom 0.5 bode, ktorý zodpovedá default deploymentu.

Po tretie, **použili sme 30-tisícový subsample**, lebo SVM-RBF má kvadratickú zložitosť v počte bodov. Plný 235-tisícový dataset by SVM trénoval hodiny per fold. Pri 30k máme stále 6-tisícový hold-out test, čo je metricky stabilné.

Po štvrté, **dataset je verejný a nemusí presne reprezentovať budúci firemný traffic**. Behavior near-leakery môžu byť datasetovo špecifické. Produkčné nasadenie by potrebovalo externú validáciu, monitoring driftu a kalibráciu prahu.

Ako follow-up by sme zvážili pridanie XGBoost-u alebo SHAP explainability pre SVM. Mohli by sme tiež skúsiť stability selection vo feature selection alebo character-level NLP modely nad surovým URL textom. To je však mimo aktuálneho zadania.

**Na záver:** projekt ukazuje, že na URL-only úlohe má SVM-RBF najlepší operačný bod, že 9 z 13 lexikálnych features tvorí stabilné jadro signálu, a že neparametrické modely majú najväčšiu výhodu práve tam, kde je signál najslabší a najťažší. Ďakujeme za pozornosť a sme pripravení odpovedať na otázky.
