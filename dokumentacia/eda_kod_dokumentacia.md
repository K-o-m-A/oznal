# Dokumentácia kódu — `eda.rmd`

Detailný popis každého chunku v EDA notebooku, s vysvetlením funkcií a dôvodov výberu balíkov.

---

## Ako túto dokumentáciu čítať

Každý chunk je popísaný v troch rovinách:

1. **Účel chunku** — čo má daná časť analyticky dosiahnuť.
2. **Mechanika kódu** — ako sa dáta transformujú krok po kroku.
3. **Použité funkcie a balíky** — odkiaľ funkcie pochádzajú a prečo sme zvolili práve túto implementáciu.

V EDA preferujeme **tidyverse štýl**, lebo notebook má byť čitateľný ako analytický príbeh. Pipe `%>%` umožňuje čítať transformáciu zhora nadol: „vezmi dáta, sprav krok 1, potom krok 2, potom vykresli“. Pri obhajobe je to zrozumiteľnejšie než veľa dočasných objektov a indexovania cez hranaté zátvorky.

### Základná tidyverse logika použitá v EDA

| Funkcia | Balík | Laické vysvetlenie | Prečo tu |
|---|---|---|---|
| `read_csv()` | readr | načíta CSV do tibble | rýchlejšie a čistejšie než base `read.csv()` |
| `%>%` | magrittr | pošli výsledok do ďalšieho kroku | čitateľný analytický tok |
| `mutate()` | dplyr | pridaj alebo zmeň stĺpec | tvorba labelov a pomocných metrík |
| `select()` | dplyr | vyber alebo odstráň stĺpce | čistenie datasetu a tvorba feature setov |
| `filter()` | dplyr | vyber riadky podľa podmienky | filtrovanie mapy features |
| `summarise()` | dplyr | zhrň skupinu do metrík | priemery, SD, VIF, počty |
| `pivot_longer()` | tidyr | široká tabuľka na dlhý formát | grafy a per-feature výpočty |
| `pivot_wider()` | tidyr | dlhá tabuľka na široký formát | porovnanie tried vedľa seba |
| `map_*()` | purrr | spusti funkciu pre každý prvok | výpočty cez veľa features |
| `ggplot()` | ggplot2 | vrstvové grafy | konzistentné vizualizácie |

Alternatívou by bol base R alebo `data.table`. `data.table` je veľmi rýchly, ale jeho syntax je pre laika menej priamočiara. Base R je dostupný všade, ale pri dlhších transformáciách sa kód horšie číta a ľahšie sa spraví chyba pri indexovaní.

---

## YAML hlavička

```
title: "Phishing URL Detection - Hypothesis & EDA"
output:
  html_notebook:
    toc: true
    toc_float: true
    theme: flatly
    highlight: tango
```

**Čo to robí:** Definuje výstupný formát ako interaktívny `html_notebook` s plávajúcim obsahom (`toc_float`). Témy `flatly` (čistý sivobiely look) a `highlight: tango` (farebný code-block).

**Prečo `html_notebook`, nie `html_document`?**  
Notebook umožňuje spustiť každý chunk samostatne v RStudio a uloží si výstup priamo v `.nb.html`. Pri obhajobe môžeme prezentovať statický HTML bez potreby spúšťať R.

---

## Chunk `libraries`

```r
library(tidyverse)
library(scales)
library(ggcorrplot)
library(yardstick)
```

**Čo to robí:** Načíta všetky balíky potrebné v notebooku.

| Balík | Z čoho je / čo poskytuje | Prečo zvolený |
|-------|--------------------------|---------------|
| `tidyverse` | meta-balík (dplyr, ggplot2, tidyr, readr, purrr, tibble, stringr, forcats) | **Konvenčný preferovaný stack pre dátovú analýzu v R**. Konzistentná pipe-syntax (`%>%`), čitateľnosť, párovanie krokov. Alternatíva by bola base R + `data.table` (rýchlejšie, ale menej čitateľné a divergentne syntakticky). |
| `scales` | formátovanie osí (`comma`, `percent`) | Default `ggplot2` ukáže `1e+05` namiesto `100,000`. `scales` to fixne. Bez alternatívy v base R. |
| `ggcorrplot` | korelačné heatmapy s `ggplot2` štýlom | Alternatívy: `corrplot` (base graphics, menej pekné), `ggcorr` z `GGally` (komplikovanejšie). `ggcorrplot` je najjednoduchšie API pre náš use-case. |
| `yardstick` | metriky klasifikácie ako `roc_auc_vec` | Tidymodels ekosystém — vektorové API (vstup vektor truth, vektor estimate). Alternatíva: `pROC::auc` (funguje, ale objektovo orientované, viac boilerplate-u). |

---

## Chunk `load-data`

```r
raw <- read_csv("PhiUSIIL_Phishing_URL_Dataset.csv", show_col_types = FALSE) %>%
  rename_with(~ str_remove(.x, "^﻿"))
```

**Čo to robí:**
1. `read_csv()` z `readr` načíta CSV ako `tibble`.
2. `show_col_types = FALSE` potlačí výpis typov pri načítaní.
3. `rename_with()` aplikuje funkciu na všetky názvy stĺpcov.
4. Lambda `~ str_remove(.x, "^﻿")` odstráni **UTF-8 BOM** z prvého stĺpca, ak ho tam Excel pridal (zlomok znaku, ktorý spôsobuje, že prvý stĺpec sa volá napr. `﻿URL` namiesto `URL`).

**Použité funkcie:**
- `read_csv` (readr / tidyverse) — alternatíva `read.csv` v base R je 2–10× pomalšie a vracia `data.frame` s automatickou konverziou strings na factory (čo nechceme).
- `rename_with` (dplyr) — programatic rename. Alternatíva: `setNames(raw, sub("^﻿", "", names(raw)))` (base R, menej čitateľné).
- `str_remove` (stringr) — alternatíva `sub` (base R, regex syntax mierne odlišná).

---

## Chunk `define-roles`

```r
ID_COLS <- c("FILENAME", "URL", "Domain", "TLD", "Title")

df <- raw %>%
  mutate(label_bin = factor(label, levels = c(0, 1),
                            labels = c("Legitimate", "Phishing"))) %>%
  select(-all_of(ID_COLS))

features <- df %>% select(-label, -label_bin)

cat("Observations:", nrow(df), "\n")
cat("Predictors:  ", ncol(features), "\n")
```

**Čo to robí:**
1. Definuje vektor stĺpcov, ktoré nie sú prediktormi (identifikátory a free text).
2. Vytvorí **factor `label_bin`** — explicitne pomenuje úrovne `Legitimate` (0) a `Phishing` (1). Toto je dôležité, lebo modely potrebujú factor ako label, nie integer.
3. Odstráni identifikátory cez `select(-all_of(ID_COLS))` — `all_of()` overí, že všetky stĺpce existujú (na rozdiel od bare `-ID_COLS` ktoré by tichu zlyhalo, keby chýbal).
4. Vyrobí `features` matrix bez label-stĺpcov.

**Prečo `factor(..., levels = c(0,1), labels = c("Legitimate","Phishing"))`?** Explicitné levels zaručia poradie tried, ktoré sa nemení podľa abecedy. Pre AUC výpočet je dôležité, ktorá trieda je „pozitívna".

**Tidyverse výhody:**
- `mutate` + `select` v pipe-line je sebevysvetľujúca sekvencia transformácií.
- Alternatíva v base R: `df$label_bin <- factor(...)` + `df <- df[, !names(df) %in% ID_COLS]` — funkčné, ale rozdrobené, ťažšie sa číta.

---

## Chunk `family-map`

```r
family_map <- tribble(
  ~feature,                    ~family,
  "URLLength",                 "Lexical",
  ...
)
```

**Čo to robí:** Zostaví **rodinnú mapu** každého prediktora do troch rodín (Lexical / Trust / Behavior).

**Použitá funkcia:** `tribble` (tibble) — „transposed tibble". Umožňuje **riadkový zápis** namiesto stĺpcového. Alternatíva v base R: `data.frame(feature = c(...), family = c(...))` — pre 49 riadkov nečitateľné, lebo musíš napárovať indexy očami.

**Prečo lokálna mapa, nie joined zo zdroja datasetu?**  
Toto je **naša taxonómia**, nie vlastnosť datasetu. Vyplýva z biznis-rozhodnutia (ako drahé je každý signál získať v reálnom čase v proxy). Preto musí byť dokumentovaná v notebooku.

---

## Chunk `exclude-scores`

```r
SCORES <- c(
  "URLSimilarityIndex",
  "TLDLegitimateProb",
  "URLCharProb",
  "DomainTitleMatchScore",
  "URLTitleMatchScore"
)
cat("Computed scores to remove:", paste(SCORES, collapse = ", "), "\n")
```

**Čo to robí:** Definuje prvú skupinu stĺpcov, ktoré nechceme použiť ako vstup modelu. Nie sú to surové merania URL alebo stránky, ale už vypočítané skóre podobnosti, pravdepodobnosti alebo zhody. Laicky: dataset nám tu ponúka „pomôcky", ktoré už v sebe nesú rozhodovaciu logiku iného systému. Keby sme ich nechali, model by sa učil z cudzieho hodnotenia, nie z vlastností URL.

**Použité funkcie:** `c()` (base R) vytvorí character vektor názvov stĺpcov. `paste(..., collapse = ", ")` spojí názvy do jednej čitateľnej vety. `cat()` vypíše kontrolný text do notebooku.

**Prečo takto:** V tidyverse časti notebooku používame tieto vektory neskôr cez `all_of()`, takže je lepšie pomenovať skupinu explicitne a vedieť ju obhájiť ako samostatné rozhodnutie.

---

## Chunk `exclude-binary`

```r
REDUNDANT_BINARY <- "HasObfuscation"
cat("Redundant binary to remove:", REDUNDANT_BINARY, "\n")
```

**Čo to robí:** Označí binárny stĺpec `HasObfuscation` na odstránenie. Tento stĺpec hovorí len to, či je počet obfuskovaných znakov väčší ako nula. Keďže v dátach už máme presnejší počet `NoOfObfuscatedChar`, binárka nenesie novú informáciu.

**Použité funkcie:** Ide o jednoduché priradenie reťazca do premennej. `cat()` je len kontrolný výpis.

**Prečo ho vyhadzujeme:** Redundantná premenná vie niektorým modelom zbytočne zosilniť rovnaký signál dvakrát. Pre laika: ako keby sme v tabuľke mali vek človeka aj stĺpec „je starší ako 0 rokov" — druhý stĺpec nič nové nepridáva.

---

## Chunk `exclude-ratios`

```r
RATIOS <- c(
  "LetterRatioInURL",
  "DegitRatioInURL",
  "ObfuscationRatio",
  "SpacialCharRatioInURL"
)
cat("Linearly dependent ratios to remove:", paste(RATIOS, collapse = ", "), "\n")
```

**Čo to robí:** Definuje pomerové premenné, ktoré sú matematicky odvodené z existujúcich count-features a `URLLength`.

**Použité funkcie:** `c()`, `paste()` a `cat()` rovnako ako vyššie.

**Prečo pomery vyhadzujeme:** Ak má model zároveň `NoOfLettersInURL`, `URLLength` aj `LetterRatioInURL`, dostáva tú istú informáciu vo viacerých algebraicky previazaných formách. Pri lineárnych modeloch to spôsobuje kolinearitu a nestabilné koeficienty; pri stromoch to zasa vie umelo zvýhodniť jednu rodinu signálov.

---

## Chunk `apply-exclusions`

```r
EXCLUDE_COLS <- c(SCORES, REDUNDANT_BINARY, RATIOS)

df       <- df %>% select(-all_of(EXCLUDE_COLS))
features <- df %>% select(-label, -label_bin)
```

**Čo to robí:** Spojí všetky vylúčené skupiny do `EXCLUDE_COLS`, odstráni ich z pracovného datasetu `df` a nanovo vytvorí `features`, teda tabuľku prediktorov bez labelov.

**Použité funkcie:** `c()` spojí viaceré vektory do jedného. `%>%` (magrittr/tidyverse) posiela výsledok zľava doprava. `select()` (dplyr) vyberá alebo odstraňuje stĺpce. `all_of()` (tidyselect) je bezpečný výber podľa character vektora: ak by názov chýbal, R vyhodí chybu namiesto tichého ignorovania.

**Prečo tidyverse:** Alternatíva v base R by bola napr. `df <- df[, !names(df) %in% EXCLUDE_COLS]`. Funguje, ale v notebooku je menej čitateľná a menej bezpečná; `all_of()` lepšie komunikuje, že všetky názvy majú existovať.

---

## Chunk `family-map-update`

```r
family_map <- family_map %>%
  filter(!feature %in% EXCLUDE_COLS)

family_map %>% count(family) %>% print()
```

**Čo to robí:** Aktualizuje mapu feature-rodín po odstránení stĺpcov. Ak stĺpec zmizol z dát, musí zmiznúť aj z `family_map`, inak by neskoršie tiery odkazovali na neexistujúce premenné.

**Použité funkcie:** `filter()` (dplyr) nechá iba riadky spĺňajúce podmienku. `%in%` (base R) testuje členstvo v zozname. `!` neguje podmienku, teda „nie je v EXCLUDE_COLS". `count(family)` (dplyr) spočíta počet features v každej rodine. `print()` vynúti zobrazenie tabuľky.

**Prečo je to dôležité:** Dataset a dokumentačná mapa musia zostať synchronizované. Toto je jednoduchá kontrola, že modelovacie tiery v Scenári 2 a 3 budú vychádzať z rovnakých vyčistených dát.

---

## Chunk `feature-types`

```r
binary_features <- names(features)[map_lgl(features, ~ all(na.omit(.x) %in% c(0, 1)))]
continuous_features <- setdiff(names(features), binary_features)
```

**Čo to robí:** Detekuje, ktoré stĺpce sú binárne (len 0/1 hodnoty) a ktoré spojité.

**Použité funkcie:**
- `map_lgl` (purrr) — map-uje funkciu cez stĺpce, vráti **logický vektor**. Alternatíva: `sapply(features, function(x) all(na.omit(x) %in% c(0,1)))` v base R — funkčné, ale `map_lgl` zaručuje typ návratu (logical).
- `na.omit` — odstráni NA pred kontrolou.
- `setdiff(A, B)` — base R množinová operácia A \ B.

**Prečo purrr namiesto base apply?**  
Purrr má **typovo bezpečné varianty** (`map_int`, `map_chr`, `map_dbl`, `map_lgl`) — ak by funkcia náhodou vrátila iný typ, dostaneme jasný error namiesto silent coercion.

---

## Chunk `feature-tiers`

```r
tier_lexical  <- family_map %>% filter(family == "Lexical")  %>% pull(feature)
tier_trust    <- family_map %>% filter(family == "Trust")    %>% pull(feature)
tier_behavior <- family_map %>% filter(family == "Behavior") %>% pull(feature)
tier_full     <- c(tier_lexical, tier_trust, tier_behavior)
```

**Čo to robí:** Z `family_map` extrahuje jednoduché character-vektory pre každý tier.

**Použité funkcie:**
- `filter(family == "X")` — výber riadkov.
- `pull(feature)` — extrahuje stĺpec ako vektor (na rozdiel od `select(feature)` ktoré vráti tibble).

**Prečo `pull` a nie `[[`?**  
`pull` funguje v pipe-line, `[[` vyžaduje break z pipe.

---

## Chunk `class-balance`

```r
df %>%
  count(label_bin) %>%
  mutate(pct = n / sum(n)) %>%
  ggplot(aes(label_bin, n, fill = label_bin)) +
  geom_col(width = 0.5, show.legend = FALSE) +
  geom_text(aes(label = percent(pct, 0.1)), vjust = -0.4, size = 4) +
  scale_fill_manual(values = c("steelblue", "firebrick")) +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, .1))) +
  labs(title = "Class distribution", x = NULL, y = "Count") +
  theme_minimal(base_size = 12)
```

**Čo to robí:**
1. `count(label_bin)` — spočítá riadky pre každú úroveň label-u (alias pre `group_by + summarise(n=n())`).
2. `mutate(pct = n / sum(n))` — pridá stĺpec percent.
3. ggplot pipeline so stĺpcami a textom percent nad nimi.

**Použité funkcie:**
- `count` (dplyr) — alternatíva `table(df$label_bin)` (base R) je menej tidy-konzistentná.
- `geom_col` — bar chart kde výška = `y` (rozdiel oproti `geom_bar` ktorý spočítáva sám).
- `percent`, `comma` (scales) — formátovanie.
- `theme_minimal` — ggplot téma.
- `expansion(mult = c(0, .1))` — kontrola padding-u — 0% dolu, 10% hore (aby text nad stĺpcami nebol odrezaný).

**Prečo ggplot2, nie base plot?**  
`ggplot2` má **vrstvový grammar of graphics** — ľahko sa pridajú text nad stĺpce, manuálne farby, formátované osi. Base plot by vyžadoval volanie `text(...)` po `barplot(...)`, viac argumentov, menej čitateľné.

---

## Chunk `discriminative-power`

Tento chunk je zložitejší — meria **diskriminačnú silu každého feature**.

### Časť SMD (continuous features)

```r
smd_df <- df %>%
  select(label, all_of(continuous_features)) %>%
  pivot_longer(-label, names_to = "feature", values_to = "value") %>%
  group_by(feature, label) %>%
  summarise(m = mean(value, na.rm = TRUE), s = sd(value, na.rm = TRUE),
            .groups = "drop") %>%
  pivot_wider(names_from = label, values_from = c(m, s),
              names_glue = "{.value}_{label}") %>%
  transmute(
    feature,
    effect = abs(m_1 - m_0) / sqrt((s_0^2 + s_1^2) / 2 + 1e-9),
    metric = "SMD (continuous)"
  )
```

**Čo to robí:**
1. Vyberie label + spojité features.
2. `pivot_longer` — z širokého formátu (každý feature vlastný stĺpec) na dlhý (jeden stĺpec `feature`, jeden `value`).
3. Pre každú dvojicu (feature, label) spočíta priemer `m` a smerodajnú odchýlku `s`.
4. `pivot_wider` — z dlhého naspäť, ale teraz s 4 stĺpcami: `m_0`, `m_1`, `s_0`, `s_1`.
5. Spočíta **SMD** = `|m_1 - m_0| / sqrt((s_0² + s_1²) / 2)`. Pridáva sa `+ 1e-9` ako ochrana proti deleniu nulou.

**Čo je SMD?**  
**Standardised Mean Difference** — rozdiel priemerov v jednotkách smerodajnej odchýlky. Nezávisí od merných jednotiek, takže porovnanie cez features je férové.

**Použité funkcie:**
- `pivot_longer` / `pivot_wider` (tidyr) — moderné nástupcovia `gather` / `spread`.
- `group_by` + `summarise` (dplyr) — agregácia.
- `transmute` — `mutate` + `select` v jednom kroku, ponechá iba uvedené stĺpce.

### Časť Cramérovo V (binary features)

```r
cramers_v <- function(x, y) {
  tab <- table(x, y)
  if (any(dim(tab) < 2)) return(NA_real_)
  chi2 <- suppressWarnings(chisq.test(tab, correct = FALSE)$statistic)
  n <- sum(tab)
  as.numeric(sqrt(chi2 / (n * (min(dim(tab)) - 1))))
}

cv_df <- tibble(
  feature = binary_features,
  effect  = map_dbl(binary_features, ~ cramers_v(features[[.x]], df$label)),
  metric  = "Cramer's V (binary)"
)
```

**Čo to robí:**
1. Definuje funkciu **Cramérovo V** = `sqrt(chi² / (n × (min(rows,cols)-1)))` — normalizuje chi-squared štatistiku do škály 0–1.
2. Aplikuje ju na každý binárny prediktor.

**Prečo Cramér V pre binary, nie SMD?**  
SMD predpokladá spojitú distribúciu. Pre 0/1 by SMD bola degenerovaná (priemer = pravdepodobnosť 1, štandardná odchýlka = `√(p(1-p))`). Cramérovo V je **postavené na 2×2 contingency tabuľke**, čo presne sedí binárkam. Obe metriky sú normalizované na 0–1, takže výsledné grafy sa čítajú rovnako.

**Použité funkcie:**
- `table` (base R) — kontingenčná tabuľka.
- `chisq.test` (base R, balík `stats`) — chi-squared test.
- `suppressWarnings` — chisq.test varuje pri malých očakávaných početnostiach, čo nás v tomto kontexte nezaujíma.
- `map_dbl` (purrr) — type-safe map.

### Spojenie a vykreslenie

```r
discrim_df <- bind_rows(smd_df, cv_df) %>%
  left_join(family_map, by = "feature") %>%
  replace_na(list(family = "Other")) %>%
  arrange(desc(effect))

ggplot(discrim_df, aes(x = reorder(feature, effect), y = effect, fill = family)) +
  geom_col() +
  coord_flip() +
  facet_wrap(~ metric, scales = "free", ncol = 2) +
  scale_fill_brewer(palette = "Set2") +
  labs(...)
```

**Použité funkcie:**
- `bind_rows` (dplyr) — vertikálny union dvoch tibble. Alternatíva `rbind` v base R funguje, ale `bind_rows` je tolerantnejší k nezhodám stĺpcov.
- `left_join(by = "feature")` (dplyr) — pridá stĺpec `family` z mapy.
- `replace_na` (tidyr) — namiesto NA dosadí "Other" pre features mimo mapy.
- `coord_flip` — horizontálne stĺpce (rotácia 90°), lebo názvy features sú dlhé.
- `facet_wrap(~ metric, scales = "free")` — dva subgraf-y vedľa seba (SMD vs Cramer V), oddelené škály.
- `scale_fill_brewer(palette = "Set2")` — farebne odlišné rodiny z RColorBrewer paliet.

---

## Chunk `smd-by-family`

```r
discrim_df %>%
  filter(metric == "SMD (continuous)", family != "Other") %>%
  ggplot(aes(family, effect, fill = family)) +
  geom_boxplot(alpha = 0.7, show.legend = FALSE) +
  geom_jitter(width = 0.15, alpha = 0.5, size = 2) +
  ...
```

**Čo to robí:** Boxplot SMD distribúcie per family, s jitterovými bodmi navrchu.

**Použité funkcie:**
- `geom_boxplot(alpha = 0.7)` — priehľadný box (aby boli vidno body za ním).
- `geom_jitter(width = 0.15)` — náhodný horizontálny posun bodov, aby sa neprekrývali.

**Prečo box + jitter, nie len box?**  
Box plot ukazuje agregované percentily, ale skrýva, **koľko features daný „outlier" predstavuje**. Jittered body ukážu individuálne hodnoty — je vidno, že napr. Lexical má jeden silný outlier (CharContinuationRate).

---

## Chunk `cor-lexical`

```r
lexical_cor <- features %>%
  select(all_of(tier_lexical)) %>%
  cor(use = "pairwise.complete.obs")

suppressWarnings(
  ggcorrplot(
    lexical_cor,
    type     = "lower",
    hc.order = TRUE,
    lab      = TRUE,
    lab_size = 2.5,
    colors   = c("firebrick", "white", "steelblue"),
    title    = "Correlation - Lexical features"
  )
)
```

**Čo to robí:**
1. `cor(...)` — Pearsonova korelačná matica. `use = "pairwise.complete.obs"` rátá korelácie z dvojíc bez NA pre konkrétny pair.
2. `ggcorrplot` vykreslí ako heatmapu.
3. `type = "lower"` — len spodný trojuholník (matica je symetrická, druhý je nadbytočný).
4. `hc.order = TRUE` — preusporiada features hierarchickým klastrovaním, takže korelované sa zoskupia.
5. `lab = TRUE` — vypíše hodnoty do buniek.

**Prečo `pairwise.complete.obs`, nie `complete.obs`?**  
`complete.obs` vyhodí celý riadok pri ľubovoľnom NA, čo môže pri 13 features veľmi znížiť veľkosť vzorky. `pairwise` zachováva každý pair samostatne. (V tomto datasete je NA = 0, ale princíp drží.)

---

## Chunk `vif`

```r
X_vif <- features %>% select(all_of(continuous_features))

vif_df <- tibble(
  feature = names(X_vif),
  vif = map_dbl(names(X_vif), ~ {
    fmla <- reformulate(setdiff(names(X_vif), .x), response = .x)
    1 / (1 - summary(lm(fmla, data = X_vif))$r.squared)
  })
) %>%
  left_join(family_map, by = "feature") %>%
  replace_na(list(family = "Other")) %>%
  mutate(severity = case_when(
    vif > 10 ~ "severe (> 10)",
    vif >= 5 ~ "moderate (5-10)",
    TRUE     ~ "ok (< 5)"
  )) %>%
  arrange(desc(vif))
```

**Čo to robí:** Spočíta **VIF (Variance Inflation Factor)** pre každý spojitý feature.

**Definícia VIF:**  
Pre feature `x_i`, VIF = `1 / (1 - R²)`, kde `R²` je z regresie `x_i` na všetkých ostatných features.
- VIF = 1 → `x_i` je nezávislá od ostatných.
- VIF > 10 → silná kolinearita, koeficienty LR sú nestabilné.

**Použité funkcie:**
- `map_dbl(names(X_vif), ~ {...})` — pre každý feature spustí blok kódu, ktorý vráti double.
- `reformulate(predictors, response = ...)` — programatic vytvorenie formuly. Alternatíva: `as.formula(paste(...))` — reformulate je bezpečnejšie pri špeciálnych znakoch.
- `setdiff(names(X_vif), .x)` — všetky stĺpce **okrem** aktuálneho.
- `lm(formula, data = ...)` (base R) — lineárny model.
- `summary(lm)$r.squared` — extrahuje R² zo summary objektu.
- `case_when` (dplyr) — vektorizovaný if-else, alternatíva pre nested `ifelse`.

**Prečo nepoužijete `car::vif`?**  
`car` je veľký balík, máme len jednu funkciu odtiaľ. Manuálny výpočet je 4 riadky kódu — explicitné a bez závislosti.

**Použitie `knitr::kable`:**  
Renderuje tibble ako pekná tabuľka v HTML output-e. Bez `kable` by sa zobrazila ako plain text.

---

## Chunk `outlier-skewness`

```r
skewness_fn <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  m <- mean(x)
  s <- sd(x)
  (n / ((n-1)*(n-2))) * sum(((x - m) / s)^3)
}

skew_df <- features %>%
  select(all_of(continuous_features)) %>%
  summarise(across(everything(), skewness_fn)) %>%
  pivot_longer(everything(), names_to = "feature", values_to = "skewness") %>%
  ...
```

**Čo to robí:** Spočíta **skewness** (Fisher-Pearson, type 2) pre každý spojitý feature.

**Vzorec:** `n / ((n-1)(n-2)) × Σ((x-m)/s)³`. Symetrická distribúcia má skewness ≈ 0; pravo-skewed (long right tail) > 0; ľavo-skewed < 0. |skew| > 2 sa typicky berie ako „silne šikmá".

**Použité funkcie:**
- `across(everything(), skewness_fn)` (dplyr) — aplikuje funkciu na všetky stĺpce. Alternatíva: `summarise(across(everything(), ~ skewness_fn(.)))` (rovnaké).
- `pivot_longer(everything(), ...)` — z 1-riadkového výstupu agregácie urobí dlhý formát.

**Prečo manuálny skewness, nie `e1071::skewness`?**  
Je to 4 riadky, vyhneme sa importu balíka len pre jednu funkciu.

**`geom_hline(yintercept = c(-2, 2), linetype = "dashed")`:**  
Pridá horizontálne čiary pri |skew| = 2 (vizuálny prah).

---

## Chunk `near-leaker-auc`

```r
behavior_feats <- family_map %>% filter(family == "Behavior") %>% pull(feature)
label_factor   <- factor(df$label, levels = c(0, 1))

univariate_aucs <- tibble(
  feature = behavior_feats,
  auc = map_dbl(behavior_feats, ~
    roc_auc_vec(
      truth       = label_factor,
      estimate    = features[[.x]],
      event_level = "second"
    )
  )
) %>%
  arrange(desc(auc))

LEAKY_BEHAVIOR <- univariate_aucs %>%
  filter(auc > 0.95) %>%
  pull(feature)
```

**Čo to robí:** Pre každý Behavior feature spočíta **univariate AUC** — AUC pri použití samotného feature ako skóre.

**Použité funkcie:**
- `roc_auc_vec(truth, estimate, event_level = "second")` (yardstick) — vektorové AUC. `event_level = "second"` znamená, že "phishing" (level 2 v c(0,1)) je pozitívna trieda.

**Prečo yardstick a nie `pROC::auc`?**  
Yardstick je **tidymodels-konzistentný** a má `_vec` varianty pre čisto vektorové vstupy bez tvorby ROC objektu. Pre map-ovanie cez 20 features je to úspornejšie.

**Hranica 0.95:**  
Empiricky stanovená — features s univariate AUC > 0.95 môžu samé takmer perfektne klasifikovať dataset, čím sa eliminuje potreba modelu. Tieto „near-leakers" identifikujeme tu a vyhodíme ich z FullLite tieru v Scenári 2 a 3.
