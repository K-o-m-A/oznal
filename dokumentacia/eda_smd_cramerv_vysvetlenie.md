# EDA — SMD a Cramérovo V: ako fungujú a čo znamenali pre náš dataset

Tento dokument vysvetľuje dve hlavné metriky **per-feature discriminative power**, ktoré sme v EDA použili na zistenie, ktoré features samostatne najlepšie rozlišujú phishing od legit URL: **Standardised Mean Difference (SMD)** pre spojité features a **Cramérovo V** pre binárne features. Pôvodný kód je v `eda.rmd`, chunk `discriminative-power`.

---

## 1. Prečo dve rôzne metriky

V datasete máme **dva typy features**:

- **Spojité (count) features** — `URLLength`, `NoOfImage`, `LineOfCode` a podobne. Hodnoty sú celé čísla od 0 vyššie.
- **Binárne features** — `IsHTTPS`, `HasTitle`, `Bank`, `HasSocialNet` a podobne. Hodnoty sú 0/1.

Pre obe potrebujeme jednu spoločnú otázku: **„Ako dobre táto feature sama o sebe rozlišuje phishing od legit?"** Lenže matematika je v každom prípade iná:

- Pre spojité features sa pýtame **„líšia sa priemery medzi triedami?"** — Standardised Mean Difference.
- Pre binárne features sa pýtame **„závisí hodnota feature od triedy?"** — Cramérovo V (založené na kontingenčnej tabuľke).

Obe metriky sme normalizovali na škálu 0–1, aby sa dali vizuálne porovnať na jednom grafe.

---

## 2. Standardised Mean Difference (SMD) pre spojité features

### 2.1 Vzorec

Pre každú spojitú feature `x` a triedy `0` (Legitimate) a `1` (Phishing):

```
SMD = |mean(x | trieda=1) − mean(x | trieda=0)| / sqrt((var(x | trieda=0) + var(x | trieda=1)) / 2 + ε)
```

V kóde:

```r
effect = abs(m_1 - m_0) / sqrt((s_0^2 + s_1^2) / 2 + 1e-9)
```

- `m_1`, `m_0` — priemery feature v phishing a legit triede.
- `s_0`, `s_1` — smerodajné odchýlky v každej triede.
- `1e-9` — tiny ridge proti deleniu nulou pri zero-variance feature.
- `abs(...)` — berieme absolútnu hodnotu, lebo nás nezaujíma smer rozdielu, len jeho veľkosť.

### 2.2 Intuícia

SMD odpovedá na otázku: **„O koľko smerodajných odchýlok je priemer phishing triedy ďalej od priemeru legit triedy?"**

- **SMD = 0** — priemery sú rovnaké, feature je úplne nediskriminačná.
- **SMD = 0.2** — malý efekt (Cohen's `d` interpretácia).
- **SMD = 0.5** — stredný efekt.
- **SMD = 0.8** — veľký efekt.
- **SMD ≥ 1.0** — veľmi silný efekt; rozdiel medzi priemermi je väčší než typická variancia.

Geometricky: predstavte si dva histogramy hodnoty feature pre obe triedy. Ak ležia takmer na sebe (rovnaké priemery, podobný rozptyl), SMD je blízko 0. Ak sú výrazne posunuté a úzke, SMD je vysoké.

### 2.3 Prečo práve tento tvar (Cohen's `d`)

Existujú aj iné mierky rozdielu priemerov, ale **Cohen's `d`** (čo je presne náš SMD) je štandard, lebo:

- **Štandardizovaná na rozdiel od neštandardizovaného `m_1 − m_0`.** Surový rozdiel priemerov závisí od jednotiek feature (`URLLength` v stovkách znakov vs `NoOfQMarkInURL` v jednotkách). Po delení smerodajnou odchýlkou sa SMD stáva **bezrozmerné** a porovnateľné medzi features.
- **Pooled variance** v menovateli (priemer rozptylov tried) zohľadňuje, že každá trieda má vlastný rozptyl. Alternatíva by bolo použiť variancu celého datasetu, čo by bolo menej presné pri triedach s rôznou variabilitou.
- **Konvencia v štatistike** — Cohen's `d` je defaultná effect-size metrika pre porovnanie dvoch skupín.

### 2.4 Naše výsledky pre SMD

Z `eda.rmd` chunk `discriminative-power` a `smd-by-family` sme získali:

**Lexical:**

- `CharContinuationRate` ~ 1.0 — jediný silný Lexical signál (outlier v rámci rodiny).
- `URLLength`, `NoOfDegitsInURL`, `NoOfQMarkInURL` ~ 0.35–0.5 — stredné efekty.
- Zvyšok rodiny klesá až k ~0.02 (veľmi slabé).
- **Median |SMD| pre Lexical: ~0.33.**

**Behavior:**

- `NoOfJS`, `NoOfSelfRef`, `NoOfImage`, `LineOfCode`, `NoOfExternalRef` v pásme 0.55–0.85 — silné efekty.
- **Median |SMD| pre Behavior: ~0.55.**

**Trust:** žiadne spojité features (rodina je celá binárna).

### 2.5 Čo to znamená pre H1

SMD potvrdzuje **prvý predpoklad H1**: typická Lexical feature **sama o sebe rozlišuje slabšie** než typická Behavior feature. Žiadny jednoduchý prah typu „ak `URLLength > 80`, je to phishing" nestačí na presnú klasifikáciu — Lexical signál je v **kombináciách** features, nie v individuálnych.

To je presne situácia, kde **neparametrické modely majú výhodu** — vedia kombinovať slabé signály do silnej rozhodovacej hranice. Parametrické modely (LR, LDA, NB) by zachytili každú feature izolovane a kombinácie by zachytili horšie.

---

## 3. Cramérovo V pre binárne features

### 3.1 Vzorec

Pre binárnu feature `x` a binárny label `y` postavíme **2×2 kontingenčnú tabuľku**:

|             | y = 0 (Legit) | y = 1 (Phishing) |
|-------------|--------------:|-----------------:|
| x = 0       | a             | b                |
| x = 1       | c             | d                |

Z nej spočítame **Pearson chi-square štatistiku** `χ²` (testuje, či sú riadky a stĺpce nezávislé). Cramérovo V je **normalizovaná verzia**:

```
V = sqrt(χ² / (n × (min(rows, cols) − 1)))
```

V kóde:

```r
cramers_v <- function(x, y) {
  tab <- table(x, y)
  if (any(dim(tab) < 2)) return(NA_real_)
  chi2 <- suppressWarnings(chisq.test(tab, correct = FALSE)$statistic)
  n <- sum(tab)
  as.numeric(sqrt(chi2 / (n * (min(dim(tab)) - 1))))
}
```

Pri 2×2 tabuľke je `min(dim) − 1 = 1`, takže to je `V = sqrt(χ² / n)`.

### 3.2 Intuícia

Cramérovo V odpovedá na otázku: **„Závisí hodnota feature od triedy, a ako silno?"**

- **V = 0** — feature je úplne nezávislá od triedy. Hodnoty 0/1 sa rozdeľujú medzi triedy presne podľa apriori distribúcie.
- **V = 1** — feature deterministicky určuje triedu. Ak `IsHTTPS = 0`, je to vždy phishing (alebo naopak).
- **0 < V < 1** — niekde medzi.

V zmysle Cohen's `w` (klasická interpretácia):

- 0.10 — malý efekt,
- 0.30 — stredný efekt,
- 0.50 — veľký efekt.

Cramérovo V > 0.5 je v praxi **veľmi silné** — feature sama dokáže klasifikáciu skoro spraviť.

### 3.3 Prečo Cramérovo V a nie napríklad Pearsonova korelácia

Pearson `r` je definovaný pre spojité veličiny a pri 0/1 dátach by bol matematicky platný (bol by ekvivalent **phi koeficientu**), ale Cramérovo V má dve výhody:

- **Generalizuje na viacúrovňové kategórie.** Ak by sme niekedy mali feature s troma úrovňami (napr. `tld_type ∈ {com, gov, other}`), phi koeficient by nestačil. Cramérovo V funguje pre `k × m` tabuľky.
- **Štandard v štatistike pre asociáciu medzi kategorickými premennými.** Konzistentné s tým, čo používa `ggcorrplot`, `vcd::assocstats` atď.

Pre náš prípad (2×2) je `V` numericky zhodné s absolútnou hodnotou phi koeficientu = `|r|`, ale notačne korektnejšie.

### 3.4 Naše výsledky pre Cramérovo V

Z grafu `discriminative-power`:

**Trust binárne features (silné signály):**

- `IsHTTPS` ≈ 0.60–0.70.
- Ostatné Trust binárky pripomínajú podobnú silu.

**Behavior binárne features (najsilnejšie):**

- `HasSocialNet` ≈ 0.75–0.80.
- `HasCopyrightInfo` ≈ 0.70.
- `HasDescription` ≈ 0.65.

**Lexical binárne features (slabé):**

- `IsDomainIP` ≈ 0.05 — najslabší signál v celom datasete.

### 3.5 Čo to znamená pre H1

Cramérovo V ukazuje **silný kontrast medzi rodinami**:

- Trust a Behavior majú binárky s `V` v pásme 0.6–0.8 — jediná takáto feature klasifikuje takmer perfektne.
- Lexical má **jedinú binárku** (`IsDomainIP`) a tá je takmer bezsignálová.

To znamená, že na **FullLite tieri** budú modely môcť „spadnúť" na pár silných Trust/Behavior binárok a dosiahnu vysoký výkon aj pri jednoduchom modeli (napr. LR alebo LDA). Naopak na **Lexical tieri** žiadny silný flag neexistuje a model musí kombinovať desiatky stredne slabých signálov.

To je **gradient H1**: najväčšia výhoda neparametrických modelov bude na Lexical (kde silné signály neexistujú a kombinácie sú nutné), na FullLite sa zmenší (lebo aj parametrické modely vedia využiť silné binárky).

---

## 4. Prečo sme tieto dve metriky kombinovali do jedného grafu

Obe sú normalizované do škály 0–1, takže **bary sa dajú porovnávať vizuálne**:

- `effect = 0.7` v SMD znamená „silný efekt v Cohen's `d` interpretácii",
- `effect = 0.7` v Cramérovom V znamená „silný efekt v Cohen's `w` interpretácii".

Hoci matematicky je to **úplne iný typ čísla**, na vizualizácii ide o ekvivalent „silný / slabý signál" pre laika a komisiu. Preto v `eda.rmd` ide o jeden `bind_rows(smd_df, cv_df)` s `facet_wrap(~ metric)` — dva panely vedľa seba s rovnakým farebným kódovaním rodín.

Dôležité: **nikdy nemiešame SMD a Cramérovo V do jedného number-crunchingu** (napr. by sme nemali počítať priemer cez obe). Pre rozhodovanie typu „ktorá feature je najsilnejšia v celom datasete" pozeráme **per-feature** v rámci tej istej metriky.

---

## 5. Limity a čo SMD/V nehovoria

### 5.1 SMD ignoruje tvar rozdelenia

SMD je založený na **priemeroch a smerodajných odchýlkach**, čo predpokladá približne normálne rozdelenie. Pri silne pravo-šikmých features (čo je 19 z 22 spojitých — viď osobitné zistenie EDA) je SMD **mierne podhodnotený** voči skutočnej diskriminačnej sile, lebo outliery zveličujú rozptyl v menovateli. Pre nás to znamená, že reálna sila Lexical features môže byť o niečo vyššia, než SMD ukazuje — ale gradient medzi Lexical a Behavior ostáva platný.

### 5.2 Cramérovo V meria iba marginálnu závislosť

V meria **závislosť dvoch premenných izolovane**. Nehovorí, či kombinácia dvoch binárok dokáže triedu rozlíšiť ešte lepšie. Pre H1 to nie je problém — H1 očakáva, že kombinácie features sú dôležité, a SMD/V nám dávajú **lower bound** sily individuálnych signálov.

### 5.3 Žiadna z metrík neukáže nelineárne vzťahy

SMD predpokladá lineárny posun medzi triedami. Cramérovo V predpokladá tabuľkovú asociáciu. Ak by nejaká feature mala **nelineárny vzťah s triedou** (napr. phishing je extrémne krátke alebo extrémne dlhé URL, ale nie stredné), SMD by tento U-shape signál nezachytil. Preto v EDA dopĺňame ešte **univariate AUC** (chunk `outlier-skewness` a `near-leaker-screen`), ktorý je voči tvaru robustnejší.

---

## 6. Zhrnutie

| Metrika | Pre aký typ feature | Vzorec | Naše výsledky |
|---|---|---|---|
| **SMD** (Cohen's d) | spojité | `|m₁ − m₀| / sqrt((s₀² + s₁²) / 2)` | Lexical median ~0.33, Behavior median ~0.55, `CharContinuationRate` outlier ~1.0 |
| **Cramérovo V** | binárne | `sqrt(χ² / (n × (min(dim) − 1)))` | Trust/Behavior binárky 0.6–0.8, Lexical jediná binárka `IsDomainIP` ~0.05 |

**Pre H1 to dohromady znamená:**

1. Lexical features sú **samostatne slabé** — žiadna jednotlivá feature nedokáže klasifikáciu.
2. Trust a Behavior obsahujú **silné individuálne signály**.
3. To predpovedá **najväčšiu výhodu neparametrických modelov na Lexical** (kde sú nutné kombinácie) a **zmenšenie na FullLite** (kde už aj jednotlivé features nesú silný signál).

Tieto dve metriky teda nie sú len opisné štatistiky — sú **predpovedným základom** pre celú H1 hypotézu Scenára 2.
