# EDA chunk-by-chunk dokumentácia

Tento dokument zjednocuje pôvodné samostatné dokumenty z adresára `eda_chunks/`.
Každá sekcia vysvetľuje jeden code-chunk z `eda.rmd` (predtým `phishing.rmd`) a zachováva tabuľky použitých funkcií.

## Konvencia

Každý chunk-doc obsahuje:
- **Účel** - jedna-dve vety čo chunk robí a prečo.
- **Vysvetlenie kódu** - krok po kroku, čo sa deje.
- **Použité funkcie** - tabuľka funkcia → balík → účel.

## Konvencie tidyverse-only

Notebook po refaktore používa tidyverse dialekt pre dátové transformácie a vizualizácie, `tidymodels` pre `yardstick` a `knitr::kable()` iba ako R Markdown prezentačný helper pre krajšiu tabuľku. Nahradenia oproti pôvodnej `phishing.rmd`:

| Pôvodne | Nová verzia | Dôvod |
|---------|-------------|-------|
| `corrplot::corrplot` | `ggcorrplot::ggcorrplot` | krajší ggplot2 frontend pre korelačnú maticu |
| `pROC::roc()$auc` | `yardstick::roc_auc_vec` | tidymodels |
| `vapply(..., numeric(1))` | `purrr::map_dbl` | tidyverse-idiomatické |

---

## Chunk: `libraries`

### Účel
Načíta všetky balíky potrebné pre EDA notebook. Zámerne sú použité len balíky z tidyverse a jeho ekosystému (tidymodels, ggplot2-založené nástroje).

### Vysvetlenie kódu
```r
library(tidyverse)
library(scales)
library(ggcorrplot)
library(yardstick)
```

- `tidyverse` je meta-balík, ktorý naraz zaháji jadro (`dplyr`, `tidyr`, `ggplot2`, `readr`, `purrr`, `tibble`, `stringr`, `forcats`). Tieto sa používajú vo všetkých nasledujúcich chunkoch.
- `scales` poskytuje formátovacie pomôcky pre osi grafov (`percent`, `comma`, `expansion`). Je súčasťou tidyverse-ekosystému.
- `ggcorrplot` renderuje korelačnú maticu ako čitateľný `ggplot2` graf.
- `yardstick` je balík z `tidymodels`-ekosystému; používame z neho `roc_auc_vec()` pre rýchly výpočet AUC pri near-leaker analýze.

Hlavička chunku má `message=FALSE, warning=FALSE`, čo potlačí hlášky balíkov pri štarte.

### Použité funkcie
| Funkcia | Balík | Pôvod |
|---------|-------|-------|
| `library()` | base R | jadro |

---

## Chunk: `load-data`

### Účel
Načíta surový PhiUSIIL CSV dataset a hneď vyčistí UTF-8 BOM znak na začiatku prvého názvu stĺpca.

### Vysvetlenie kódu
```r
raw <- read_csv("PhiUSIIL_Phishing_URL_Dataset.csv", show_col_types = FALSE) %>%
  rename_with(~ str_remove(.x, "^﻿"))
```

- `read_csv()` z `readr` načíta CSV do `tibble`-u. Parameter `show_col_types = FALSE` potlačí dlhý log o detegovaných typoch stĺpcov.
- Pipe `%>%` posunie načítaný tibble do `rename_with()`.
- `rename_with(~ str_remove(.x, "^﻿"))` aplikuje na **všetky** názvy stĺpcov funkciu, ktorá odstráni úvodný UTF-8 BOM (`﻿`). BOM sa typicky objaví iba na úplne prvom stĺpci, ale `rename_with` to spracuje uniformne. Pôvodná verzia notebooku používala `map_chr` + `str_replace`, čo je viacero krokov pre rovnaký výsledok.

Lambda `~ str_remove(.x, "^﻿")` je purrr-style anonymná funkcia: `.x` je placeholder pre názov stĺpca.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `read_csv()` | `readr` (tidyverse) | načítanie CSV do tibble |
| `%>%` | `magrittr` (re-export tidyverse) | pipe operátor |
| `rename_with()` | `dplyr` (tidyverse) | premenovanie stĺpcov funkciou |
| `str_remove()` | `stringr` (tidyverse) | odstránenie regex matchu z reťazca |

---

## Chunk: `define-roles`

### Účel
Pripraví modelovací dataframe `df`: zo surového `raw` urobí binárny faktor `label_bin`, odhodí identifikátorové/textové stĺpce. Zároveň vytvorí čistú maticu prediktorov `features`.

### Vysvetlenie kódu
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

- `ID_COLS` je vektor so stĺpcami, ktoré sú identifikátory/voľný text - nemajú prediktívnu hodnotu a nepatria do modelovania.
- `mutate(label_bin = factor(...))` pridá faktorovú verziu pôvodnej `label` (0/1 → "Legitimate"/"Phishing"). Túto faktorovú verziu používa `class-balance` chunk pre čitateľný graf.
- `select(-all_of(ID_COLS))` odstráni ID stĺpce. `all_of()` zaručí, že chyba sa zahlási hneď, ak by niektorý zo stĺpcov chýbal.
- `features <- df %>% select(-label, -label_bin)` vytvorí prediktorovú maticu - v EDA výpočtoch nechceme cieľovú premennú.
- `cat()` vypíše rýchly sanity check (počet pozorovaní + počet prediktorov).

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | vektor reťazcov |
| `mutate()` | `dplyr` (tidyverse) | pridanie nového stĺpca |
| `factor()` | base R | konverzia na faktor s explicitnými úrovňami a labelmi |
| `select()` | `dplyr` (tidyverse) | výber/odstránenie stĺpcov |
| `all_of()` | `tidyselect` (tidyverse) | striktný výber podľa vektora názvov |
| `cat()` | base R | konzolový výpis |
| `nrow()`, `ncol()` | base R | rozmery dataframe |

---

## Chunk: `family-map`

### Účel
Manuálne zmapuje každý prediktor do jednej z troch rodín (Lexical / Trust / Behavior) podľa toho, **ako drahé** je daný signál získať pri runtime: Lexical sa derivuje zo samotného URL stringu, Trust vyžaduje DNS/HTTPS lookup alebo parsovanie titulku, Behavior znamená stiahnutie a vykreslenie stránky.

### Vysvetlenie kódu
```r
family_map <- tribble(
  ~feature,                    ~family,
  "URLLength",                 "Lexical",
  "DomainLength",              "Lexical",
  ...
)
```

- `tribble()` je tidyverse-friendly konštruktor pre malý tibble po riadkoch (transposed tibble). Hlavička začína `~feature, ~family` - tilda označuje meno stĺpca.
- Každý nasledujúci pár `"Foo", "Bar"` je jeden záznam.
- Toto je **single source of truth** pre rozdelenie prediktorov - downstream chunky (`feature-tiers`, `discriminative-power`, `vif`, `skewness`, `near-leaker-auc`) sa naň pripájajú cez `left_join(by = "feature")`.

Klasifikácia je čisto naša taxonómia podľa nákladu signálu, nie atribút datasetu. Notebook `phishing.rmd` to vysvetľoval v markdowne nad chunk-om - poznámka napríklad pre `IsHTTPS` (formálne v URL stringu, ale browser ho už vynucuje, takže ho radíme do Trust).

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `tribble()` | `tibble` (tidyverse) | row-wise konštrukcia tibble-u |

---

## Chunk: `exclude-scores`

### Účel
Definuje computed probability/similarity score premenné, ktoré sa musia odstrániť, pretože už obsahujú výstup iného modelu alebo expertne vytvorené phishing skóre.

### Vysvetlenie kódu
```r
SCORES <- c(
  "URLSimilarityIndex",    # similarity to known-phishing URL patterns
  "TLDLegitimateProb",     # P(TLD is legitimate) from an external lookup
  "URLCharProb",           # P(character sequence) from a language model
  "DomainTitleMatchScore", # computed domain-title consistency score
  "URLTitleMatchScore"     # computed URL-title consistency score
)
cat("Computed scores to remove:", paste(SCORES, collapse = ", "), "\n")
```

- `SCORES` je character vektor piatich premenných, ktoré sa nepovažujú za raw URL signály.
- Komentáre pri jednotlivých položkách vysvetľujú, prečo ide o computed score.
- `cat()` zachováva pôvodný konzolový výpis, aby render ostal porovnateľný s uloženým Docker výstupom.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | vektor názvov stĺpcov |
| `cat()`, `paste()` | base R | konzolový výpis |

---

## Chunk: `exclude-binary`

### Účel
Definuje redundantnú binárnu premennú `HasObfuscation`, ktorá je odvodená priamo z počtu obfuskovaných znakov.

### Vysvetlenie kódu
```r
REDUNDANT_BINARY <- "HasObfuscation"
cat("Redundant binary to remove:", REDUNDANT_BINARY, "\n")
```

- `REDUNDANT_BINARY` drží jeden stĺpec, ktorý neobsahuje dodatočný signál nad `NoOfObfuscatedChar`.
- `cat()` vypíše názov odstraňovanej premennej.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `<-` | base R | priradenie názvu stĺpca |
| `cat()` | base R | konzolový výpis |

---

## Chunk: `exclude-ratios`

### Účel
Definuje ratio premenné, ktoré sú lineárne odvodené z count premenných a `URLLength`, preto nepridávajú nový signál a zvyšujú kolinearitu.

### Vysvetlenie kódu
```r
RATIOS <- c(
  "LetterRatioInURL",      # = NoOfLettersInURL / URLLength
  "DegitRatioInURL",       # = NoOfDegitsInURL / URLLength
  "ObfuscationRatio",      # = NoOfObfuscatedChar / URLLength
  "SpacialCharRatioInURL"  # = NoOfOtherSpecialCharsInURL / URLLength
)
cat("Linearly dependent ratios to remove:", paste(RATIOS, collapse = ", "), "\n")
```

- `RATIOS` je character vektor štyroch pomerových premenných.
- Komentáre uvádzajú presnú count/length interpretáciu každého ratio.
- `cat()` vypíše odstránené ratio premenné v jednom riadku.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | vektor názvov stĺpcov |
| `cat()`, `paste()` | base R | konzolový výpis |

---

## Chunk: `apply-exclusions`

### Účel
Aplikuje tri vyššie definované skupiny exklúzií na dátový rámec a obnoví `features` bez vylúčených stĺpcov.

### Vysvetlenie kódu
```r
EXCLUDE_COLS <- c(SCORES, REDUNDANT_BINARY, RATIOS)

df       <- df %>% select(-all_of(EXCLUDE_COLS))
features <- df %>% select(-label, -label_bin)

cat("\nFeatures after exclusion:", ncol(features), "\n")
cat("Removed:", paste(EXCLUDE_COLS, collapse = ", "), "\n")
```

- `EXCLUDE_COLS` spojí všetky tri skupiny do jedného vektora.
- `select(-all_of(EXCLUDE_COLS))` odstráni tieto stĺpce z modelovacieho dataframe.
- `features` sa znovu vytvorí bez cieľových premenných `label` a `label_bin`.
- Dva `cat()` výpisy zachovávajú pôvodné renderované outputy: počet prediktorov po exklúzii a zoznam odstránených stĺpcov.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | spojenie skupín exklúzií |
| `%>%` | `magrittr` | pipe |
| `select()` | `dplyr` (tidyverse) | odstránenie/výber stĺpcov |
| `all_of()` | `tidyselect` | striktný výber podľa názvov |
| `cat()`, `ncol()`, `paste()` | base R | konzolový výpis |

---

## Chunk: `family-map-update`

### Účel
Synchronizuje `family_map` s redukovaným feature setom po exklúziách.

### Vysvetlenie kódu
```r
family_map <- family_map %>%
  filter(!feature %in% EXCLUDE_COLS)

family_map %>% count(family) %>% print()
```

- `filter(!feature %in% EXCLUDE_COLS)` odstráni z mapy všetky feature-y, ktoré už v `features` neexistujú.
- `count(family)` vypíše finálne počty feature-ov v rodinách.
- `print()` zachová explicitný tibble výpis v renderi.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `filter()`, `count()` | `dplyr` (tidyverse) | filtrovanie a počítanie podľa rodiny |
| `%in%` | base R | členský test |
| `print()` | base R | explicitný výpis tibble |

---

## Chunk: `feature-types`

### Účel
Rozdelí prediktory na **binárne** (hodnoty len {0,1}) a **kontinuálne** (všetko ostatné). Tento split potrebuje `discriminative-power` chunk (rôzna metrika pre binárne vs kontinuálne) aj `vif`/`skewness` (počítajú sa iba na kontinuálnych).

Chunk má `include=FALSE` - výsledok sa nezobrazí v rendrovanom HTML, len sa pripravia premenné `binary_features` a `continuous_features`.

### Vysvetlenie kódu
```r
binary_features <- names(features)[map_lgl(features, ~ all(na.omit(.x) %in% c(0, 1)))]
continuous_features <- setdiff(names(features), binary_features)
```

- `map_lgl(features, ~ all(na.omit(.x) %in% c(0, 1)))` skontroluje každý stĺpec a vráti `TRUE`, ak všetky nenulové nechýbajúce hodnoty patria do `{0, 1}`.
- `na.omit(.x)` explicitne ignoruje prípadné chýbajúce hodnoty pri type-splite. V tomto datasete NA nie sú, ale zápis je robustný a používa čisté base R.
- `names(features)[...]` použije logický vektor ako index a vráti mená binárnych stĺpcov.
- `setdiff(names(features), binary_features)` je doplnok - všetko, čo nie je binárne.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `map_lgl()` | `purrr` (tidyverse) | aplikácia binárnej kontroly na každý stĺpec |
| `na.omit()` | stats/base R | ignorovanie chýbajúcich hodnôt |
| `all()` | base R | logická redukcia |
| `%in%` | base R | členský test |
| `names()` | base R | mená stĺpcov |
| `setdiff()` | base R | množinový rozdiel |

---

## Chunk: `feature-tiers`

### Účel
Z `family_map` vyextrahuje názvy featur pre každú rodinu zvlášť (`tier_lexical`, `tier_trust`, `tier_behavior`) a ich uniót (`tier_full`). Tieto vektory sú baseline pre testovanie H1: scenario_2 notebook ich rovnako definuje a navyše stripne 6 near-leakerov pre **FullLite** tier (34 featur).

### Vysvetlenie kódu
```r
tier_lexical  <- family_map %>% filter(family == "Lexical")  %>% pull(feature)
tier_trust    <- family_map %>% filter(family == "Trust")    %>% pull(feature)
tier_behavior <- family_map %>% filter(family == "Behavior") %>% pull(feature)
tier_full     <- c(tier_lexical, tier_trust, tier_behavior)

cat("URLOnly tier (Lexical, ", length(tier_lexical),  " features)\n", sep = "")
cat("Trust tier              (", length(tier_trust),    " features)\n", sep = "")
cat("Behavior tier           (", length(tier_behavior), " features)\n", sep = "")
cat("Full tier               (", length(tier_full),     " features)\n", sep = "")
```

- `filter(family == "Lexical")` vyfiltruje riadky kde rodina je "Lexical".
- `pull(feature)` vytiahne stĺpec ako vektor (ekvivalent `df$feature`, ale piped-friendly).
- `c(...)` spojí všetky tri tiers do jedného vektora pre `tier_full`.
- `cat()` so `sep = ""` zlepí všetky kúsky bez medzier - výpis vyzerá ako tabuľka.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `filter()` | `dplyr` (tidyverse) | filter podľa predikátu |
| `pull()` | `dplyr` (tidyverse) | extrakcia stĺpca ako vektora |
| `c()` | base R | spojenie vektorov |
| `cat()` | base R | konzolový výpis |
| `length()` | base R | dĺžka vektora |

---

## Chunk: `class-balance`

### Účel
Vykreslí stĺpcový graf rozdelenia tried (Legitimate vs Phishing) s percentom nad každým stĺpcom. Cieľ je ukázať, že dataset je približne vyvážený - nepotrebujeme resampling ani class-weighting.

### Vysvetlenie kódu
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

- `count(label_bin)` urobí frequency table (ekvivalent `group_by + summarise(n=n())`).
- `mutate(pct = n / sum(n))` pridá stĺpec s pomerom triedy.
- `ggplot(aes(...))` zaháji grafiku, mapuje x = trieda, y = počet, fill = trieda (kvôli farebnému rozdielu).
- `geom_col` nakreslí stĺpce. `width=0.5` ich zúži, `show.legend=FALSE` skryje legendu (farby sú samovysvetľujúce z popiskov).
- `geom_text(aes(label = percent(pct, 0.1)))` pridá nad každý stĺpec percentuálny popisok. `percent()` zo `scales` formátuje `0.512` → "51.2%". `vjust=-0.4` ho posunie tesne nad stĺpec.
- `scale_fill_manual(values = c("steelblue","firebrick"))` priradí konkrétne farby triedam (modrá pre legit, červená pre phishing).
- `scale_y_continuous(labels = comma, expand = expansion(mult=c(0,.1)))` formátuje os Y s tisícovkovým oddeľovačom (`comma` zo `scales`) a rozšíri os hore o 10% pre miesto na popisky.
- `labs(...)` nastaví titulok a popisky osí.
- `theme_minimal()` čistá svetlá téma.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `count()` | `dplyr` (tidyverse) | count po skupinách |
| `mutate()` | `dplyr` (tidyverse) | nový stĺpec |
| `sum()` | base R | súčet |
| `ggplot()`, `aes()` | `ggplot2` (tidyverse) | inicializácia grafu, mapovanie estetiky |
| `geom_col()`, `geom_text()` | `ggplot2` | stĺpce a textové popisky |
| `scale_fill_manual()` | `ggplot2` | manuálne nastavenie farieb |
| `scale_y_continuous()` | `ggplot2` | nastavenie y-osi |
| `labs()`, `theme_minimal()` | `ggplot2` | popisky a téma |
| `expansion()` | `ggplot2` | násobné rozšírenie osi |
| `percent()`, `comma()` | `scales` (tidyverse-ekosystém) | formátovacie funkcie pre osi/popisky |

---

## Chunk: `discriminative-power`

### Účel
Spočíta veľkosť efektu pre každú prediktor-cieľ dvojicu - zvlášť pre kontinuálne (SMD = standardised mean difference) a binárne (Cramérova V pre 2x2 tabuľku). Vykreslí jeden bar-plot s dvoma fasetmi. Toto je kľúčový dôkaz pre H1: chceme vidieť, že Lexical featury majú per-feature najnižšiu silu.

Cramérova V je ponechaná ako explicitný helper cez kontingenčnú tabuľku a `chisq.test`, pretože je čitateľnejšia a štatisticky jasnejšia než skrátený 2x2 ekvivalent cez `abs(cor(...))`.

### Vysvetlenie kódu
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

- `pivot_longer(-label, ...)` premieta kontinuálne stĺpce do long formátu (jeden riadok = (feature, hodnota)).
- `group_by(feature, label) %>% summarise(m=mean(value, na.rm=TRUE), s=sd(value, na.rm=TRUE))` spočíta priemer a SD pre každú dvojicu (feature × class), pričom explicitne ignoruje prípadné NA.
- `pivot_wider(names_glue = "{.value}_{label}")` rozprestrie naspäť, výsledné stĺpce sú `m_0, m_1, s_0, s_1`.
- `transmute(effect = abs(m_1-m_0) / sqrt((s_0^2+s_1^2)/2 + 1e-9))` aplikuje vzorec SMD: rozdiel priemerov delený pooled SD. `+ 1e-9` chráni pred delením nulou pri konštantných featurách.

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

- `cramers_v(x, y)` vytvorí 2x2 kontingenčnú tabuľku cez `table(x, y)`.
- `if (any(dim(tab) < 2)) return(NA_real_)` ošetrí degenerovaný prípad, keď premenná alebo label nemá dve úrovne.
- `chisq.test(tab, correct = FALSE)$statistic` vypočíta chí-kvadrát štatistiku bez Yatesovej korekcie; `suppressWarnings()` potlačí varovanie pri malých očakávaných počtoch.
- `sqrt(chi2 / (n * (min(dim(tab)) - 1)))` je všeobecný vzorec pre Cramérovu V.
- `map_dbl(binary_features, ~ cramers_v(features[[.x]], df$label))` aplikuje helper na každý binárny prediktor.
- `tibble(feature = ..., effect = ..., metric = ...)` vytvorí long tabuľku efektov bez ďalšieho pivotovania.

```r
discrim_df <- bind_rows(smd_df, cv_df) %>%
  left_join(family_map, by = "feature") %>%
  replace_na(list(family = "Other")) %>%
  arrange(desc(effect))
```

- `bind_rows` vertikálne spojí SMD a Cramérove V do jednej tabuľky (rovnaké stĺpce: feature, effect, metric).
- `left_join(family_map, by="feature")` pridá rodinu pre farbenie. `replace_na(list(family="Other"))` ošetrí featury, čo by v `family_map` chýbali.
- `arrange(desc(effect))` zoradí zostupne podľa efektu.

```r
ggplot(discrim_df, aes(reorder(feature, effect), effect, fill = family)) +
  geom_col() + coord_flip() +
  facet_wrap(~ metric, scales = "free", ncol = 2) +
  scale_fill_brewer(palette = "Set2") +
  labs(...) + theme_minimal(...) + theme(legend.position = "top")
```

- `reorder(feature, effect)` zoradí featury na osi podľa efektu.
- `coord_flip()` otočí osi - horizontálne stĺpce sú čitateľnejšie pri 30+ featurách.
- `facet_wrap(~ metric, scales="free")` rozdelí graf na dva panely (SMD vs Cramér's V), každý so svojou x-osou.
- `scale_fill_brewer(palette = "Set2")` priradí farby rodinám z ColorBrewer palety.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `select()`, `mutate()`, `summarise()`, `transmute()`, `group_by()`, `arrange()`, `desc()`, `left_join()`, `bind_rows()` | `dplyr` (tidyverse) | manipulácia dát |
| `pivot_longer()`, `pivot_wider()`, `replace_na()` | `tidyr` (tidyverse) | reshape, NA handling |
| `all_of()` | `tidyselect` (tidyverse) | výberové helpery |
| `ggplot()`, `aes()`, `geom_col()`, `coord_flip()`, `facet_wrap()`, `scale_fill_brewer()`, `labs()`, `theme_minimal()`, `theme()` | `ggplot2` (tidyverse) | grafika |
| `map_dbl()` | `purrr` (tidyverse) | aplikácia Cramér helpera na binárne prediktory |
| `tibble()` | `tibble` (tidyverse) | tabuľka binárnych efektov |
| `mean()`, `sd()`, `abs()`, `sqrt()`, `sum()`, `min()`, `dim()`, `any()`, `as.numeric()`, `table()`, `return()` | base R | štatistické primitíva a kontingenčná tabuľka |
| `chisq.test()` | `stats` (base R) | chí-kvadrát štatistika pre Cramérovu V |
| `suppressWarnings()` | base R | potlačenie varovania z `chisq.test()` pri malých očakávaných počtoch |
| `reorder()` | `stats` (base R) | usporiadanie faktorových úrovní |

---

## Chunk: `smd-by-family`

### Účel
Z `discrim_df` vyfiltruje len kontinuálne SMD efekty a vykreslí boxplot per rodina. Vizuálny dôkaz pre H1: medián SMD je v Lexical rodine najnižší a má najmenší rozptyl, takže jednotlivé Lexical featury sú slabšie predikátory než Trust/Behavior.

### Vysvetlenie kódu
```r
discrim_df %>%
  filter(metric == "SMD (continuous)", family != "Other") %>%
  ggplot(aes(family, effect, fill = family)) +
  geom_boxplot(alpha = 0.7, show.legend = FALSE) +
  geom_jitter(width = 0.15, alpha = 0.5, size = 2) +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "SMD distribution by family (continuous features only)",
       x = NULL, y = "| SMD |") +
  theme_minimal(base_size = 12)
```

- `filter(metric == "SMD (continuous)", family != "Other")` ponechá iba SMD riadky pre známe rodiny.
- `aes(family, effect, fill = family)` mapuje x = rodina, y = veľkosť efektu, výplň = rodina.
- `geom_boxplot(alpha=0.7)` priesvitné boxploty, `geom_jitter(width=0.15)` overlay s individuálnymi bodmi (pre každý feature jeden bod). `alpha=0.5` body čiastočne priesvitné, aby sa neprekrývali s boxom.
- Spoločný `fill` pre box aj body znamená, že `geom_jitter` automaticky preberá farbu z `aes()`.
- `theme_minimal(base_size=12)` čistá téma, mierne väčšie písmo.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `filter()` | `dplyr` (tidyverse) | filter riadkov |
| `ggplot()`, `aes()` | `ggplot2` (tidyverse) | inicializácia, mapovanie |
| `geom_boxplot()`, `geom_jitter()` | `ggplot2` | boxplot + jittered body |
| `scale_fill_brewer()` | `ggplot2` | ColorBrewer paleta |
| `labs()`, `theme_minimal()` | `ggplot2` | popisky a téma |

---

## Chunk: `cor-lexical`

### Účel
Vykreslí korelačnú maticu medzi Lexical featurami pomocou `ggcorrplot`. Vizualizuje silnú kolinearitu vnútri Lexical klastra (`URLLength`, `NoOfLettersInURL`, `NoOfDegitsInURL` a ďalšie), ktorá motivuje použitie Ridge regularizácie v Scenario 2.

### Vysvetlenie kódu
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

- `select(all_of(tier_lexical))` zúži `features` na 13 Lexical stĺpcov.
- `cor(use = "pairwise.complete.obs")` vráti maticu Pearsonových korelácií. Parameter `use` znamená: pre každú dvojicu prediktorov použij iba riadky, kde nie je NA. (V tomto datasete NA nie sú, ale je to robustnejší default.)
- `ggcorrplot(...)` zobrazí maticu ako čitateľný korelačný heatmap graf:
  - `type = "lower"` vykreslí len dolný trojuholník, pretože matica je symetrická.
  - `hc.order = TRUE` zoskupí korelované featury vedľa seba pomocou hierarchického zhlukovania.
  - `lab = TRUE, lab_size = 2.5` vpíše číselné koeficienty do políčok.
  - `colors = c("firebrick", "white", "steelblue")` nastaví farebnú škálu red = -1, white = 0, blue = +1.
- `suppressWarnings(...)` je tu len lokálne okolo `ggcorrplot`, pretože balík interne používa deprecated ggplot2 API a vie vyprodukovať warning, ktorý nemení graf ani výpočty.

Pôvodná verzia notebooku používala `corrplot::corrplot`; aktuálna verzia používa `ggcorrplot`, ktorý dáva krajší `ggplot2` výstup v notebooku.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `select()` | `dplyr` (tidyverse) | výber stĺpcov |
| `all_of()` | `tidyselect` (tidyverse) | striktný výber |
| `cor()` | `stats` (base R) | korelačná matica |
| `ggcorrplot()` | `ggcorrplot` | korelačný graf nad ggplot2 |
| `suppressWarnings()` | base R | lokálne skrytie interného deprecated warningu z `ggcorrplot` |

---

## Chunk: `vif`

### Účel
Vypočíta Variance Inflation Factor (VIF) pre každú kontinuálnu featuru. VIF kvantifikuje, koľko sa rozptyl koeficientu v lineárnom modeli zväčší kvôli kolinearite s ostatnými prediktormi. VIF > 10 = závažná kolinearita. Spolu s `cor-lexical` chunkom potvrdzuje, že Lexical klaster vyžaduje Ridge.

### Vysvetlenie kódu
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

vif_df %>%
  transmute(Feature = feature,
            Family  = family,
            VIF     = round(vif, 2),
            Severity = severity) %>%
  knitr::kable(caption = "Variance Inflation Factors - continuous features")
```

**Cieľ**: VIF stĺpca i = 1 / (1 - R²ᵢ), kde R²ᵢ je z lineárnej regresie i-teho stĺpca na všetkých ostatných.

- `X_vif <- features %>% select(all_of(continuous_features))` - design matica len kontinuálnych prediktorov.
- `map_dbl(names(X_vif), ~ {...})` - pre každý feature spustí lambdu, ktorá vráti VIF (numeric). `map_dbl` (purrr) je tidyverse-ekvivalent k base `vapply(..., numeric(1))`.
- Vnútri lambdy:
  - `setdiff(names(X_vif), .x)` - všetky stĺpce okrem aktuálneho `.x`.
  - `reformulate(predictors, response = .x)` postaví formula objekt `feature ~ ostatné`.
  - `lm(fmla, data = X_vif)` natrénuje lineárnu regresiu.
  - `summary(...)$r.squared` extrahuje R².
  - `1 / (1 - r2)` je definícia VIF.
- `tibble(feature, vif)` zabalí výsledky.
- `left_join(family_map)` priradí rodinu pre downstream filtrovanie/farbenie.
- `case_when(...)` klasifikuje VIF do troch úrovní závažnosti.
- `arrange(desc(vif))` zoradí zostupne.
- `transmute(Feature=..., Family=..., VIF=round(vif, 2), Severity=...)` pripraví finálnu prezentačnú tabuľku s čitateľne zaokrúhlenými VIF hodnotami.
- `knitr::kable(...)` vyrenderuje tabuľku vo finálnom HTML krajšie ako default tibble print. Používame kvalifikované volanie `knitr::kable()`, takže netreba pripájať celý balík cez `library(knitr)`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `select()`, `mutate()`, `arrange()`, `desc()`, `case_when()`, `left_join()`, `transmute()` | `dplyr` (tidyverse) | manipulácia |
| `all_of()` | `tidyselect` (tidyverse) | výber |
| `tibble()` | `tibble` (tidyverse) | konštrukcia tibble |
| `map_dbl()` | `purrr` (tidyverse) | vektorová iterácia → double |
| `replace_na()` | `tidyr` (tidyverse) | náhrada NA |
| `names()`, `setdiff()`, `round()` | base R | mená, množinový rozdiel a zaokrúhlenie |
| `reformulate()`, `lm()`, `summary()` | `stats` (base R) | konštrukcia formula, lineárna regresia, summary stats |
| `kable()` | `knitr` | render HTML tabuľky |

---

## Chunk: `skewness`

### Účel
Vypočíta šikmosť (skewness) všetkých kontinuálnych prediktorov a vykreslí ju ako horizontálny bar-plot s referenčnými čiarami v ±2. Featury s `|skewness| > 2` sú silne pravostranne skosené - dôvod prečo LR/LDA potrebujú log-transformáciu, kým stromové modely nie.

### Vysvetlenie kódu
```r
skewness_fn <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x); m <- mean(x); s <- sd(x)
  (n / ((n - 1) * (n - 2))) * sum(((x - m) / s)^3)
}
```
Vlastná funkcia pre šikmosť (vzorec G1 - bias-corrected). Tidyverse nemá vstavanú skewness funkciu. Implementácia stojí na base R primitívoch (`mean`, `sd`, `length`, `sum`).

```r
skew_df <- features %>%
  select(all_of(continuous_features)) %>%
  summarise(across(everything(), skewness_fn)) %>%
  pivot_longer(everything(), names_to = "feature", values_to = "skewness") %>%
  left_join(family_map, by = "feature") %>%
  replace_na(list(family = "Other")) %>%
  arrange(desc(abs(skewness)))
```
- `summarise(across(everything(), skewness_fn))` aplikuje `skewness_fn` na každý kontinuálny stĺpec (single-row tibble).
- `pivot_longer(everything(), ...)` rozbalí do long formátu (feature × skewness).
- `left_join(family_map)` doplní rodinu.
- `arrange(desc(abs(skewness)))` zoradí zostupne podľa absolútnej hodnoty (najsilnejšie skosenia hore).

```r
ggplot(skew_df, aes(reorder(feature, abs(skewness)), skewness, fill = family)) +
  geom_col() + coord_flip() +
  geom_hline(yintercept = c(-2, 2), linetype = "dashed", colour = "grey40") +
  scale_fill_brewer(palette = "Set2") +
  labs(...) + theme_minimal(...) + theme(legend.position = "top")
```
- `reorder(feature, abs(skewness))` zoradí featury na osi.
- `geom_hline(yintercept = c(-2, 2), linetype = "dashed")` vykreslí dva referenčné prahy ±2 (heuristický cutoff pre "ťažko skosené").
- `coord_flip()` horizontálna orientácia.

```r
cat("Features with |skewness| > 2:",
    sum(abs(skew_df$skewness) > 2), "of", nrow(skew_df), "\n")
cat("These are:\n")
skew_df %>% filter(abs(skewness) > 2) %>% select(feature, skewness, family) %>% print()
```
- `sum(abs(skew_df$skewness) > 2)` spočíta featury prekračujúce prah (logické TRUE/FALSE sa kastne na 0/1).
- `cat("These are:\n")` zachová pôvodný čitateľný konzolový popis zo starého renderu.
- `print()` explicitne vypíše detailný tibble s premennými nad prahom, aby renderovaný výstup ostal porovnateľný s uloženým Docker outputom.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `select()`, `summarise()`, `mutate()`, `arrange()`, `desc()`, `left_join()`, `filter()`, `across()` | `dplyr` (tidyverse) | manipulácia dát |
| `all_of()`, `everything()` | `tidyselect` (tidyverse) | výberové helpery |
| `pivot_longer()`, `replace_na()` | `tidyr` (tidyverse) | reshape, NA handling |
| `ggplot()`, `aes()`, `geom_col()`, `geom_hline()`, `coord_flip()`, `scale_fill_brewer()`, `labs()`, `theme_minimal()`, `theme()` | `ggplot2` (tidyverse) | grafika |
| `mean()`, `sd()`, `sum()`, `length()`, `abs()`, `cat()`, `nrow()` | base R | štatistika a primitíva |
| `reorder()` | `stats` (base R) | usporiadanie faktorových úrovní |

---

## Chunk: `near-leaker-auc`

### Účel
Pre každú Behavior featuru spočíta **univariátny AUC** - diskriminačnú silu featury samej osebe (bez modelu). Six near-leakers (`LineOfCode`, `NoOfExternalRef`, `NoOfImage`, `NoOfSelfRef`, `NoOfJS`, `NoOfCSS`) majú AUC > 0.95, čo by v "Full" tieri saturovalo akýkoľvek model na AUC ≈ 1.0 a zničilo by H1 kontrast. Preto Scenario 2 ich strihá → **FullLite** tier.

V pôvodnej verzii sa AUC rátalo cez `pROC::roc()$auc`. V novej verzii cez `yardstick::roc_auc_vec()` z tidymodels-ekosystému.

### Vysvetlenie kódu
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

cat("Behavior features ranked by univariate AUC:\n")
print(univariate_aucs, n = Inf)
cat("\nNear-leakers (univariate AUC > 0.95):\n")
cat(paste(LEAKY_BEHAVIOR, collapse = ", "), "\n")
```

- `behavior_feats` = vektor mien Behavior featur z `family_map`.
- `label_factor`: `roc_auc_vec` vyžaduje `truth` ako faktor s explicitnými úrovňami.
- `map_dbl(behavior_feats, ~ ...)` iteruje po Behavior featurách:
  - `roc_auc_vec(truth, estimate, event_level="second")` z `yardstick` vráti AUC. `event_level="second"` znamená, že druhá úroveň faktora (`1` = phishing) je pozitívna trieda.
  - AUC sa nesymetrizuje, aby hodnoty ostali zhodné s pôvodným Docker renderom založeným na fixnom smere AUC.
- `arrange(desc(auc))` zoradí zostupne.
- `filter(auc > 0.95) %>% pull(feature)` vytiahne mená near-leakerov - tento vektor používa Scenario 2 notebook na konštrukciu **FullLite** tieru.
- Posledné riadky vypíšu nadpis, celú AUC tabuľku cez `print(..., n = Inf)` a sumár near-leakerov. `paste(..., collapse = ", ")` spojí vektor mien do jedného CSV-string-u.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `%>%` | `magrittr` | pipe |
| `filter()`, `pull()`, `arrange()`, `desc()` | `dplyr` (tidyverse) | manipulácia |
| `tibble()` | `tibble` (tidyverse) | konštrukcia tibble |
| `map_dbl()` | `purrr` (tidyverse) | iterácia vracajúca double |
| `roc_auc_vec()` | `yardstick` (tidymodels) | AUC pre vektorové vstupy |
| `factor()` | base R | faktorová konverzia s úrovňami |
| `cat()`, `paste()`, `print()` | base R | výpis a spojenie reťazcov |
