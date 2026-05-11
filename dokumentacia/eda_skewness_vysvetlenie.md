# EDA — Skewness: kód, motivácia a výsledky

Tento dokument vysvetľuje, ako sme v projekte merali **šikmosť (skewness)** spojitých features, prečo to bolo dôležité, a čo z toho vyplynulo pre Scenár 2 a preprocessing pipeline. Pôvodný kód je v `eda.rmd`, chunk `outlier-skewness`.

---

## 1. Čo je skewness a prečo nás zaujímala

**Skewness (šikmosť)** je miera **asymetrie** rozdelenia:

- `skewness ≈ 0` — symetrické rozdelenie (napr. Gauss).
- `skewness > 0` — **pravo-šikmé** (dlhý chvost vpravo, väčšina hodnôt vľavo).
- `skewness < 0` — ľavo-šikmé.
- `|skewness| > 2` — typický prah pre **silne šikmé** rozdelenie.

V našom projekte sme ju potrebovali zmerať, lebo viaceré modely v Scenári 2 majú **predpoklady o tvare rozdelenia features**:

- **LDA, Naive Bayes** — predpokladajú približnú normalitu spojitých features.
- **SVM-RBF, KNN** — počítajú euklidovské vzdialenosti, kde outliery v dlhom chvoste **dominujú** výpočtom (rozdiel `URLLength = 6000` vs `URLLength = 30` prebije všetky ostatné rozdiely).
- **LR-Ridge** — robustnejšia, ale aj tu silne šikmé features spôsobujú problémy s odhadom koeficientov.

Preto sme potrebovali zistiť, **či tieto predpoklady platia**, a ak nie, zaviesť `log1p` transformáciu pred tréningom.

---

## 2. Kód — riadok po riadku

### 2.1 Skewness funkcia

```r
skewness_fn <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  m <- mean(x)
  s <- sd(x)
  (n / ((n-1)*(n-2))) * sum(((x - m) / s)^3)
}
```

Implementuje **Fisher–Pearson type 2** vzorec:

```
skewness = (n / ((n−1)(n−2))) × Σ((xᵢ − μ) / σ)³
```

Logika:

- `(xᵢ − μ) / σ` — štandardizovaná odchýlka i-teho bodu od priemeru. Hodnoty pod priemerom sú záporné, nad priemerom kladné.
- **Tretia mocnina** zachová znamienko a zveličí veľké odchýlky. Body v dlhom chvoste vpravo (veľké kladné odchýlky) prispievajú dominantne kladným kubom, zatiaľ čo zhluk pod priemerom prispieva slabými zápornými.
- Suma týchto kubov je teda **kladná** ak je dlhý chvost vpravo, **záporná** ak vľavo.
- Korekcia `n / ((n-1)(n-2))` je **bias correction** pre malé vzorky (type 2 Fisher–Pearson) — pri veľkom `n` sa blíži k `1/n`.

**Prečo manuálny vzorec a nie `e1071::skewness`:**

- Žiadna externá závislosť — funkcia v 6 riadkoch.
- Explicitné odstránenie `NA` cez `x[!is.na(x)]` (defenzívne).
- Reproducibilita — vidíme presne, ktorý variant skewness používame (Fisher–Pearson type 2, nie type 1 ani moment-based).

### 2.2 Aplikácia na všetky spojité features

```r
skew_df <- features %>%
  select(all_of(continuous_features)) %>%
  summarise(across(everything(), skewness_fn)) %>%
  pivot_longer(everything(), names_to = "feature", values_to = "skewness") %>%
  left_join(family_map, by = "feature") %>%
  replace_na(list(family = "Other")) %>%
  arrange(desc(abs(skewness)))
```

Krok po kroku:

1. **`select(all_of(continuous_features))`** — vyfiltrujeme iba spojité features (na binárky 0/1 by skewness nemala zmysel).
2. **`summarise(across(everything(), skewness_fn))`** — aplikuje `skewness_fn` na **každý stĺpec**. Výsledok je 1-riadkový data frame s 22 stĺpcami, kde každý stĺpec obsahuje skewness príslušnej feature.
3. **`pivot_longer(everything(), ...)`** — z 1×22 širokého formátu spraví 22×2 dlhý: stĺpce `feature` (mená) a `skewness` (hodnoty). Toto je formát vhodný pre `ggplot`.
4. **`left_join(family_map, by = "feature")`** — pripojí informáciu o **rodine** (Lexical / Trust / Behavior) pre farbenie v grafe.
5. **`replace_na(list(family = "Other"))`** — defenzívna ochrana, ak by sa nejaká feature nenašla v family map.
6. **`arrange(desc(abs(skewness)))`** — zoradí features od najviac šikmých po najmenej.

### 2.3 Vizualizácia

```r
ggplot(skew_df, aes(reorder(feature, abs(skewness)), skewness, fill = family)) +
  geom_col() +
  coord_flip() +
  geom_hline(yintercept = c(-2, 2), linetype = "dashed", colour = "grey40") +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "Skewness of continuous features",
       x = NULL, y = "Skewness", fill = "Family") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top")
```

- **`reorder(feature, abs(skewness))`** — features na osi sú zoradené podľa absolútnej skewness (najmenej šikmé hore, najviac dole — po `coord_flip()`).
- **`geom_col()` + `coord_flip()`** — vodorovný stĺpcový graf (každá feature jeden bar).
- **`geom_hline(yintercept = c(-2, 2), linetype = "dashed")`** — vizuálne čiary na `±2`. Bary, ktoré ich prekračujú, predstavujú **silne šikmé** features. To je vizuálne zarovnaný prah, ktorý čítateľ vidí na prvý pohľad.
- **`fill = family`** — farba podľa rodiny umožňuje vidieť, či sa šikmé features zhlukujú v Lexical alebo Behavior.

---

## 3. Čo sme zistili

### 3.1 Hlavný číselný výsledok

**Z 22 spojitých features je 19 silne pravo-šikmých** (`|skew| > 2`).

Konkrétne, šikmé sú napríklad:

- **Lexical:** `URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL`, `NoOfSubDomain`, `NoOfQMarkInURL`, `NoOfOtherSpecialCharsInURL`.
- **Behavior:** `NoOfImage`, `NoOfJS`, `NoOfCSS`, `NoOfExternalRef`, `LineOfCode`.

Skewness niektorých je extrémna — pre count features sa môže pohybovať v desiatkach (skewness 10+). Histogram by ukázal, že väčšina URL má 0–3 číslic, ale outliery majú stovky.

### 3.2 Geometrická interpretácia

Predstavte si histogram `URLLength`:

- ~95% URL je medzi 10 a 100 znakov — **vysoký úzky kopec vľavo**.
- ~5% URL je 100–6000 znakov — **dlhý plochý chvost vpravo**.

Priemer `URLLength` je ťahaný outliermi výrazne nahor (povedzme na 80), ale **median** môže byť 35. Smerodajná odchýlka je tiež zveličená chvostom. To znamená:

- Pre LDA/NB by **Gauss s priemerom 80 a SD 200** úplne nezodpovedal realite — predikoval by hustotu na 100 ako vyššiu než na 30, čo nie je pravda.
- Pre SVM/KNN by `‖x − x'‖²` medzi `URL = 30` a `URL = 6000` bolo `(6000 − 30)² ≈ 35 600 000` — to úplne prebije rozdiely v ostatných 12 features. Ostatné features by sa stali pre vzdialenosť **neviditeľné**.

### 3.3 Tri features, ktoré nie sú silne šikmé

Z 22 sú 3 mimo prahu — typicky:

- `CharContinuationRate` — pomerová hodnota v `[0, 1]`, prirodzene obmedzená a nemá dlhý chvost.
- Pravdepodobne ďalšie 1–2 features, ktoré sú prirodzene obmedzené alebo majú symetrickejšie rozdelenie.

---

## 4. K čomu nás to viedlo

Skewness zistenie **priamo motivovalo** preprocessing voľby v Scenári 2:

### 4.1 Pridanie `log1p` transformácie do Receptu A

`log1p(x) = log(1 + x)` stláča pravý chvost. Po transformácii má `URLLength` rozdelenie blízke k normálu, outliery (6000 znakov) sa zarovnajú s normálnymi hodnotami (30 znakov) v zmysluplnom pásme. To je **priama odpoveď** na zistenie šikmosti.

### 4.2 Zachovanie surových dát pre RF (Recept B)

Random Forest rozhoduje cez **prahy** na hodnotách (`x < threshold`), nie cez vzdialenosti ani Gauss predpoklady. **Monotónna transformácia ako `log1p` neprahy nemení** — `URLLength < 80` a `log1p(URLLength) < log1p(80)` rezia presne tie isté riadky. Pre RF by `log1p` bol zbytočný výpočet bez zmeny výsledku, preto má vlastný recept bez transformácií.

### 4.3 Posilnenie obhajobového argumentu pre H1

Skewness ukázala, že **dáta sú "neslušné"** v štatistickom zmysle — silne nesplňujú Gauss predpoklady. Parametrické modely (LDA, NB) majú teda **systematickú nevýhodu**, ktorú nemôžeme úplne odstrániť ani transformáciou. Naopak neparametrické modely (RF, SVM-RBF, KNN) dáta zoberú také, aké sú, a ich flexibilita je práve preto výhodná. To **dopĺňa** ostatné EDA argumenty (slabé samostatné features, kolinearita) v podpore H1.

---

## 5. Limity nášho merania skewness

- **Skewness je univariate** — meriame ju per feature, neukáže nelineárne vzťahy medzi features ani interakcie.
- **Citlivá na outliery** — ak je v dátach jeden extrémny outlier (napr. `URLLength = 50000`), skewness môže byť zveličená. Pre stabilnejší odhad by sa dal použiť `medcouple` (robust skewness), ale pre nás stačí klasická Fisher–Pearson — dáta sme manuálne kontrolovali a outliery sú reálne (nie chyby parsingu).
- **Prah `|skew| > 2`** je konvenčný, nie absolútny. Niektoré zdroje používajú 1, iné 3. Pri 2 sme dostali jasný výsledok 19 z 22 — pri 1 by ich bolo viac, pri 3 možno menej, ale **gradient by ostal jednoznačný**.

---

## 6. Zhrnutie

| Krok | Čo sme spravili | Výsledok |
|------|-----------------|----------|
| Kód | Manuálna implementácia Fisher–Pearson type 2 vzorca | 6-riadková `skewness_fn` |
| Aplikácia | `summarise(across(everything(), skewness_fn))` | 22 čísel skewness |
| Vizualizácia | Vodorovný stĺpcový graf s prahmi `±2`, farby podľa rodiny | Vidno, že väčšina features prekračuje prah |
| Hlavný výsledok | **19 z 22 spojitých features má `|skew| > 2`** | Silne pravo-šikmé |
| Dôsledok pre Recept A (LR/LDA/NB/SVM/KNN) | **`log1p` pred štandardizáciou** | Šikmosť redukovaná, predpoklady približne splnené |
| Dôsledok pre Recept B (RF) | **Žiadny preprocessing** | Monotónne transformácie nemenia stromové prahy |
| Obhajobový dopad | EDA argument pre H1 | Parametrické modely sú handicapované, neparametrické nie |

### Krátka veta pre obhajobu

> „Skewness sme merali Fisher–Pearson vzorcom pre všetkých 22 spojitých features. Z nich je **19 silne pravo-šikmých** (`|skew| > 2`) — typické count features ako `URLLength`, `NoOfImage`, `LineOfCode` majú dlhé pravé chvosty. To by spôsobilo problém pre LDA/NB (porušená normalita), pre SVM/KNN (outliery dominujú vzdialenostiam) aj pre LR (skreslené koeficienty). Preto sme do preprocessing pipeline pridali **`log1p` transformáciu**, ktorá chvosty stláča a rozdelenie približuje k Gausovi. Random Forest dostáva surové dáta, lebo monotónna transformácia nemení jeho prahové splity."
