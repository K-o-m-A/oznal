# Dokumentácia kódu — `scenario_2.rmd`

Detailný popis každého chunku v Scenári 2 (a 4) notebooku.

---

## Ako túto dokumentáciu čítať

`scenario_2.rmd` je dlhší než EDA, lebo obsahuje celý modelovací experiment. Preto je dobré čítať ho ako pipeline:

1. **Setup a dáta** — načítanie balíkov, datasetu, exclusions a tierov.
2. **Sampling a preprocessing** — rovnaké riadky, rovnaké foldy, dva preprocessing recepty.
3. **Fitovanie modelov** — šesť modelov cez spoločný helper.
4. **Agregácia výsledkov** — AUC, threshold metriky a H1 gap.
5. **Scenár 4** — RF teacher a surrogate strom.

Pri každom chunke vysvetľujeme nielen „čo robí kód“, ale aj **prečo je to metodicky potrebné**. Pri modeloch je dôležité rozlišovať:

- funkcie z **tidyverse** pre manipuláciu dát,
- funkcie z **caret** pre jednotné trénovanie modelov,
- backend balíky (`glmnet`, `MASS`, `klaR`, `randomForest`, `kernlab`, `rpart`), ktoré reálne fitujú konkrétne modely.

### Prečo kombinujeme tidyverse a caret

Tidyverse používame na dátovú prípravu, tabuľky a grafy. `caret` používame preto, že dáva jednotné API pre rôzne modely. Bez `caret` by každý model mal iný spôsob fitovania, predikcie, CV a metriky. S `caret::train()` vieme držať rovnakú štruktúru experimentu a meniť iba modelový backend.

| Vrstva | Typické funkcie | Úloha |
|---|---|---|
| tidyverse | `select`, `mutate`, `group_by`, `summarise`, `map_dfr` | príprava dát a skladanie výsledkov |
| caret | `train`, `trainControl`, `createDataPartition`, `createFolds`, `preProcess` | split, CV, preprocessing a jednotné fitovanie |
| yardstick | `roc_auc_vec`, `sens_vec`, `spec_vec` | metriky mimo caret objektov |
| knitr | `kable` | čitateľné tabuľky v HTML notebooku |

---

## Chunk `libraries`

```r
library(tidyverse)
library(caret)
library(glmnet)
library(MASS, exclude = "select")
library(klaR)
library(randomForest)
library(kernlab)
library(yardstick)
library(knitr)
library(digest)
library(rpart)

set.seed(2026)

ARTIFACTS <- "scenario_2/artifacts"
dir.create(ARTIFACTS, recursive = TRUE, showWarnings = FALSE)
```

| Balík | Čo poskytuje | Prečo zvolený |
|-------|--------------|---------------|
| `tidyverse` | dplyr, ggplot2, tidyr, purrr, ... | Konzistentná pipe-line syntax. |
| `caret` | unifikované API pre tréning modelov (`train`, `trainControl`) | **Štandardný R model wrapper** — jeden kód pre LR, LDA, NB, RF, SVM, KNN. Alternatíva `tidymodels` je novší ekosystém, ale vyžaduje viac infraštruktúry. |
| `glmnet` | regularizovaná regresia (lasso, ridge, elastic-net) | Najrýchlejšia C-implementácia coordinate descent-u. Bez alternatívy v R. |
| `MASS, exclude = "select"` | `lda()`, `stepAIC()` | `MASS::select` koliduje s `dplyr::select`, preto explicitne vylučujeme. |
| `klaR` | `NaiveBayes` cez `caret::method = "nb"` | Single-purpose, caret to ako backend volá. |
| `randomForest` | `randomForest()` | Originálna Breimanovho-Cutlera implementácia. Alternatíva `ranger` je rýchlejšia, ale `randomForest` má viac stability v caret-e. |
| `kernlab` | SVM (`ksvm`) cez `caret::method = "svmRadial"` | Default backend caret-u pre SVM. |
| `yardstick` | `roc_auc_vec`, `sens_vec`, `spec_vec` | Vektorové metriky. |
| `knitr` | `kable()` pre formátované tabuľky v HTML | Najjednoduchšie API pre tabuľky v notebookoch. |
| `digest` | `digest()` — hashovanie objektov pre cache fingerprint | Bez alternatívy v base R. |
| `rpart` | jednoduchý CART strom (pre Scenár 4 surrogate) | Klasický CART, široko používaný. |

**`set.seed(2026)`** — reproducibilita stratifikovaného samplingu, splitov a CV indexov.

**`dir.create(..., recursive = TRUE, showWarnings = FALSE)`** — vytvorí adresár `scenario_2/artifacts` ak neexistuje, neukáže warning ak už je tam.

---

## Chunk `load-data`

```r
dataset_path <- if (file.exists("PhiUSIIL_Phishing_URL_Dataset.csv")) {
  "PhiUSIIL_Phishing_URL_Dataset.csv"
} else if (file.exists("../PhiUSIIL_Phishing_URL_Dataset.csv")) {
  "../PhiUSIIL_Phishing_URL_Dataset.csv"
} else stop("PhiUSIIL_Phishing_URL_Dataset.csv not found")

raw <- read_csv(dataset_path, show_col_types = FALSE) %>%
  rename_with(~ str_remove(.x, "^﻿"))
cat("Loaded", nrow(raw), "rows,", ncol(raw), "columns.\n")
```

**Čo to robí:** Hľadá CSV v aktuálnom adresári alebo o úroveň vyššie (užitočné, keď notebook bežiaci v sub-adresári chce súbor v projekt-roote).

**Použité funkcie:**
- `file.exists()` (base R).
- `if-else` (base R control flow).
- `stop(msg)` ukončí ak ani jeden súbor nenájdeme.
- `read_csv` (readr) — rýchle načítanie CSV.
- `rename_with(~ str_remove(.x, "^﻿"))` — odstráni UTF-8 BOM z prvého stĺpca (rovnaký pattern ako v EDA).

---

## Chunk `exclusions`

```r
ID_COLS          <- c("FILENAME", "URL", "Domain", "TLD", "Title")
SCORES           <- c(...)
REDUNDANT_BINARY <- "HasObfuscation"
RATIOS           <- c(...)
EXCLUDE_COLS     <- c(ID_COLS, SCORES, REDUNDANT_BINARY, RATIOS)

df <- raw %>%
  mutate(label = factor(label, levels = c(1, 0),
                        labels = c("Phishing", "Legitimate"))) %>%
  select(-all_of(EXCLUDE_COLS))
```

**Čo to robí:** Zopakuje EDA exclusions (sekcia 3.3 v eda.rmd) — rovnakú množinu features.

**Dôležitý detail — `levels = c(1, 0)` vs `c(0, 1)`:**  
V EDA sme mali `levels = c(0, 1)` s labels `c("Legitimate", "Phishing")`. Tu obraciame poradie na `c(1, 0)` s labels `c("Phishing", "Legitimate")`, takže **Phishing je prvý level**. To má dôsledok pre `caret`, ktorý štandardne berie prvý level ako pozitívnu triedu.

**Prečo `select(-all_of(EXCLUDE_COLS))`?**  
`all_of()` vynúti striktný match — ak by jeden zo stĺpcov chýbal, vyhodí error. To je bezpečnejšie ako `select(-EXCLUDE_COLS)` ktorá by sa správala mätúco s NSE (non-standard evaluation).

---

## Chunk `family-map`

```r
family_map <- tribble(
  ~feature, ~family,
  ...
)

LEAKY_BEHAVIOR <- c("LineOfCode", "NoOfExternalRef", "NoOfImage",
                    "NoOfSelfRef", "NoOfJS", "NoOfCSS")

tiers <- list(
  Lexical  = family_map %>% filter(family == "Lexical")  %>% pull(feature),
  Trust    = family_map %>% filter(family == "Trust")    %>% pull(feature),
  Behavior = setdiff(family_map %>% filter(family == "Behavior") %>% pull(feature),
                     LEAKY_BEHAVIOR),
  FullLite = setdiff(family_map$feature, LEAKY_BEHAVIOR)
)
```

**Čo to robí:** Definuje 4 tiery — 3 ablačné (Lexical, Trust, Behavior bez near-leakers) + FullLite (všetky bez near-leakers).

**Použité funkcie:**
- `tribble` (tibble) — riadkový zápis tabuľky.
- `filter` + `pull` (dplyr) — výber + extrakcia stĺpca.
- `setdiff(A, B)` (base R) — A bez prvkov B.
- `list(name = ..., name = ...)` — pomenovaný list.

**`sapply(tiers, length)`** vypíše počet features v každom tieri pre kontrolu (13, 7, 14, 34).

---

## Chunk `subsample`

```r
N_SUB <- 30000
df_sub <- df %>%
  group_by(label) %>%
  slice_sample(n = N_SUB / 2) %>%
  ungroup() %>%
  as.data.frame()

table(df_sub$label)
```

**Čo to robí:** **Stratifikovaný sub-sample** 30 000 riadkov — 15k z každej triedy.

**Použité funkcie:**
- `group_by(label)` — zoskupí podľa label-u, takže `slice_sample` operuje per-skupina.
- `slice_sample(n = 15000)` — náhodne vyberie n riadkov z každej skupiny. Alternatíva v base R: `sample.int + tapply` — viac kódu.
- `ungroup()` — odstráni grouping (inak by sa preniesol do ďalších operácií).
- `as.data.frame()` — caret občas nepreferuje tibble (interagujúci s base S3 metódami).

**Prečo 30k a stratifikované?**  
SVM-RBF je O(n²)–O(n³). Plný dataset = hodiny per fold. 30k = ~24k tréningových po splite, kde SVM beží ~5 min. Stratifikácia zaručí, že obe triedy majú rovnaký počet vzoriek (15k/15k) → vyvážené pri každom CV foldu.

---

## Chunk `splits`

```r
idx       <- createDataPartition(df_sub$label, p = 0.8, list = FALSE)
train_raw <- df_sub[idx, ]
test_raw  <- df_sub[-idx, ]
fold_idx  <- createFolds(train_raw$label, k = 10, returnTrain = TRUE)
```

**Čo to robí:**
1. `createDataPartition` (caret) — **stratifikovaný 80/20 split** indexov. Vráti vektor riadkov pre train.
2. `createFolds(..., k = 10, returnTrain = TRUE)` — 10-fold CV indexy. `returnTrain = TRUE` znamená, že každý fold **obsahuje train indexy** (nie test indexy) — to je presne formát, ktorý caret očakáva v `trainControl(index = ...)`.

**Prečo stratifikovaný split, keď je trieda už 50/50?**  
Po sub-samplingu áno, ale aj so 50/50 splitom by náhodne vybraná 80% mohla mať mierny imbalance (napr. 49.7%/50.3%). Stratifikácia to vylúči.

**Prečo `list = FALSE`?**  
Default `TRUE` vráti list of resamples, my chceme 1 vektor.

---

## Chunk `recipes`

```r
feat <- df_sub %>% select(-label)
binary_features <- feat %>%
  select(where(~ all(na.omit(.x) %in% c(0, 1)))) %>%
  names()
continuous_features <- setdiff(names(feat), binary_features)

apply_log <- function(d, cols) {
  d %>%
    mutate(across(all_of(cols), ~ log1p(pmax(.x, 0))))
}
train_log <- apply_log(train_raw, continuous_features)
test_log  <- apply_log(test_raw,  continuous_features)

pp <- train_log %>%
  select(all_of(continuous_features)) %>%
  preProcess(method = c("center", "scale"))

replace_continuous <- function(d) {
  scaled <- d %>%
    select(all_of(continuous_features)) %>%
    predict(pp, .)

  d %>%
    mutate(across(all_of(continuous_features), ~ scaled[[cur_column()]]))
}

train_std <- replace_continuous(train_log)
test_std  <- replace_continuous(test_log)
```

**Čo to robí:** Aplikuje **Recept A** (`log1p` + center/scale pre LR, LDA, NB, SVM, KNN).

### `select(where(...))`

`where(~ all(na.omit(.x) %in% c(0, 1)))` — predikát, ktorý vyhľadá stĺpce kde všetky hodnoty (po vyhodení NA) sú 0 alebo 1.

### `apply_log` funkcia

`log1p(x) = log(1 + x)` — bezpečné pre x = 0 (ktoré by `log(0) = -Inf` rozbil). `pmax(x, 0)` zaisťuje, že žiadna hodnota nie je záporná (záporné counts by boli bug, ale chránime sa).

### `preProcess(method = c("center", "scale"))`

Z `caret`. **Naučí** sa stredy a smerodajné odchýlky z train setu. Použijeme rovnaký objekt `pp` aj na test (`predict(pp, test_log)`) — zaručuje, že **test je škálovaný train-statistikami**, čo je korektný protokol.

**Pozn.:** `preProcess` je nazvaný **raz na celom train** (nie per-fold). Pri 24k riadkoch a fixnom hyperparameteri je leakage ≪ noise. Per-fold preProcess by zdvojnásobil čas behu bez analytického prínosu.

### `mutate(across(all_of(cols), ~ scaled[[cur_column()]]))`

`cur_column()` v `across` lambda vracia meno aktuálneho stĺpca. Tým „prepisujeme" pôvodné spojité stĺpce ich zoškálovanými verziami.

---

## Chunk `fit-utility`

Najdôležitejší helper v notebooku — definuje **trojicu funkcií** používaných pri každom fitovaní.

### `fit_one_tier`

```r
fit_one_tier <- function(tier_features, data_train, data_test, method, tuneGrid = NULL, ...) {
  tr <- data_train %>% select(label, all_of(tier_features))
  te <- data_test %>% select(label, all_of(tier_features))

  ctrl <- trainControl(
    method          = "cv",
    index           = fold_idx,
    classProbs      = TRUE,
    summaryFunction = twoClassSummary,
    savePredictions = "final"
  )
  t0 <- Sys.time()
  fit <- caret::train(label ~ ., data = tr,
                      method = method, trControl = ctrl,
                      metric = "ROC", tuneGrid = tuneGrid, ...)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  test_prob <- predict(fit, te, type = "prob") %>% as_tibble() %>% pull(Phishing)
  test_pred <- predict(fit, te)
  test_auc  <- roc_auc_vec(te$label, test_prob, event_level = "first")
  cm <- caret::confusionMatrix(test_pred, te$label, positive = "Phishing")
  ...
}
```

**Čo to robí:** Pre jeden tier:
1. Vyberie len label + tier features
2. Definuje `trainControl` s 10-fold CV (cez `index = fold_idx` zaručíme **rovnaké foldy naprieč modelmi**)
3. Trénuje cez `caret::train` (jediný entry point pre 6 rôznych modelov)
4. Predikuje na test set + train set
5. Spočíta AUC, accuracy, F1, precision, sensitivity, specificity
6. Vráti list s **per-fold AUC**, train+test metrikami a časom

**Prečo `index = fold_idx`, nie `number = 10`?**  
`number = 10` by vygeneroval **nové** foldy zakaždým. My chceme **identické foldy** medzi modelmi pre férové porovnanie — preto pevné `fold_idx`.

**`twoClassSummary` summaryFunction:**  
Z `caret`. Pre binárnu klasifikáciu vyrobí `ROC`, `Sens`, `Spec` per-fold. Bez tohto by bol default `defaultSummary` (Accuracy + Kappa).

**`roc_auc_vec(te$label, test_prob, event_level = "first")`:**  
Z `yardstick`. `event_level = "first"` znamená, že **prvý level** label-factor-u je pozitívna trieda — keďže sme nastavili `levels = c(1,0)` s labels `c("Phishing","Legitimate")`, prvý je „Phishing", takže to je správne pre AUC.

**`caret::confusionMatrix(positive = "Phishing")`:**  
Vyrobí confusion matrix s phishing ako pozitívnou triedou. `cm$byClass["Sensitivity"]` je `TP / (TP+FN)`, `cm$byClass["Specificity"]` je `TN / (TN+FP)`.

### `tiers_fingerprint`

```r
tiers_fingerprint <- function(x)
  x[sort(names(x))] %>%
    map(sort) %>%
    digest::digest()
```

**Čo to robí:** Vytvorí stabilný hash z definície tier-ov. Keď sa zoznam features zmení, hash sa zmení → cache invalidate-uje.

**Použité funkcie:**
- `x[sort(names(x))]` — usporiada list podľa názvov (deterministicky).
- `map(sort)` (purrr) — usporiada features v každom tieri.
- `digest::digest()` — MD5/SHA hash celého objektu.

### `fit_tiers`

```r
fit_tiers <- function(model, family, fitter) {
  list(
    model = model,
    family = family,
    by_tier = imap(tiers, fitter)
  )
}
```

**Čo to robí:** Pre daný model spustí `fitter(features, tier_name)` pre každý tier.

**`imap(tiers, fitter)`** (purrr) — `imap` je `map` s prístupom k indexu/kľúču. Volá `fitter(value, name)` pre každý prvok listu. Ekvivalent v base R: `mapply(fitter, tiers, names(tiers), SIMPLIFY = FALSE)` — ťažšie čitateľné.

### `run_or_load`

```r
run_or_load <- function(name, fn) {
  path <- file.path(ARTIFACTS, paste0("res_", name, ".rds"))
  fp   <- tiers_fingerprint(tiers)
  if (file.exists(path)) {
    cached <- readRDS(path)
    tiers_ok   <- setequal(names(cached$by_tier), names(tiers))
    schema_ok  <- all(c("train_auc", "train_acc", "test_prec") %in%
                      names(cached$by_tier[[1]]))
    fp_ok      <- isTRUE(cached$tiers_fp == fp)
    if (tiers_ok && schema_ok && fp_ok) return(cached)
    cat(sprintf("  [%s] cache stale (...) - refitting\n", name))
  }
  res <- fn()
  res$tiers_fp <- fp
  saveRDS(res, path)
  res
}
```

**Čo to robí:** Cache wrapper — ak existuje validný `.rds`, načítaj ho; inak spusti `fn()` a ulož.

**Validačné kritériá:**
1. `tiers_ok` — počet a názvy tier-ov sa nezmenili
2. `schema_ok` — výstupný list obsahuje očakávané polia (kontrola, či nejde o staršiu verziu)
3. `fp_ok` — hash tier-ov sa zhoduje

**`saveRDS / readRDS`** (base R) — binárny serializačný formát R. Alternatíva `qs::qsave` je rýchlejšia, ale pridáva závislosť.

### `print_tier_summary`

```r
print_tier_summary <- function(res) {
  tbl <- imap_dfr(res$by_tier, function(r, tier) {
    gap <- r$train_auc - r$test_auc
    tibble(...)
  })
  kable(tbl, ...)
}
```

**Čo to robí:** Vyrobí formátovanú tabuľku s metrikami pre každý tier.

**`imap_dfr`** (purrr) — `imap` ktoré spojí výsledky cez `bind_rows`. Vráti tibble.

**`sprintf("%.4f +/- %.4f", mean(r$cv_per_fold$ROC), sd(r$cv_per_fold$ROC))`** — formátovanie CV ROC ako "0.9234 +/- 0.0021".

---

## Chunky `fit-lr`, `fit-lda`, `fit-nb`, `fit-rf`, `fit-svm`, `fit-knn`

Všetky majú rovnaký pattern:

```r
res_lr <- run_or_load("lr", function() {
  fit_tiers("LogReg-Ridge", "parametric", function(feats, tier) {
    cat(sprintf("  LogReg-Ridge   [%-8s] fitting (%d features)...\n",
                tier, length(feats)))
    fit_one_tier(
      feats, train_std, test_std,
      method = "glmnet",
      tuneGrid = data.frame(alpha = 0, lambda = 0.01))
  })
})
print_tier_summary(res_lr)
```

**Premenné:**

| Model | `caret method` | `tuneGrid` | data |
|-------|----------------|-----------|------|
| LR-Ridge | `"glmnet"` | `alpha=0, lambda=0.01` | `train_std`, `test_std` (Recept A) |
| LDA | `"lda"` | (none) | `train_std`, `test_std` |
| Naive Bayes | `"nb"` | `fL=1, usekernel=TRUE, adjust=1` | `train_std`, `test_std` |
| Random Forest | `"rf"` | `mtry=floor(sqrt(p))`, ntree=300 | `train_raw`, `test_raw` (Recept B — žiadny preprocessing) |
| SVM-RBF | `"svmRadial"` | `C=1, sigma=0.1` | `train_std`, `test_std` |
| KNN | `"knn"` | `k=25` | jittered `train_std`, `test_std` |

**Pre KNN špecifika:**

```r
jitter_features <- function(d, cols, sd = 1e-3) {
  d %>%
    mutate(across(all_of(cols), ~ .x + rnorm(n(), 0, sd)))
}
```

`rnorm(n(), 0, 1e-3)` — pridá Gaussian noise s SD=10⁻³ na binárky, aby `caret::knn3` nepadol s "too many ties in knn" pri Trust tieri (7 binárok).

**Pre RF špecifika:**

```r
mtry <- max(1, floor(sqrt(p)))
```

Štandardná classification heuristika `mtry = √p`. `max(1, ...)` zaistí, že mtry nie je 0 ak by p bolo 0 (defenzívne).

`ntree = 300` — empirická hranica, kde AUC saturuje.

### Chunk `fit-lr`

**Čo to robí:** Spustí Logistic Regression s ridge regularizáciou cez `caret::method = "glmnet"`. Používa štandardizované dáta (`train_std`, `test_std`) a fixný `tuneGrid = data.frame(alpha = 0, lambda = 0.01)`.

**Použité funkcie a balíky:** `run_or_load()` je náš cache wrapper. `fit_tiers()` je náš helper, ktorý rovnaký model pustí cez všetky tiery. `glmnet` je backend pre regularizovanú regresiu. `data.frame()` vytvorí grid hyperparametrov pre `caret`.

**Prečo ridge:** V EDA sme našli extrémnu kolinearitu v lexikálnych dĺžkových premenných. Ridge (`alpha = 0`) nezahadzuje features, iba stabilizuje koeficienty. Lasso by už robilo feature selection, čo patrí až do Scenára 3.

### Chunk `fit-lda`

**Čo to robí:** Spustí Linear Discriminant Analysis (`caret::method = "lda"`) cez rovnaké tiery a rovnaký preprocessing ako LR.

**Použité funkcie a balíky:** Backend pochádza z balíka `MASS`. `caret` ho obalí jednotným tréningovým API, takže môžeme porovnať CV a test metriky rovnako ako pri ostatných modeloch.

**Prečo LDA:** Je to klasický parametrický model s jednoduchým predpokladom: v každej triede sú dáta približne gaussovské a triedy majú podobnú kovariančnú štruktúru. Po `log1p()` a škálovaní má férovú šancu, ale EDA zároveň naznačuje, že predpoklady nebudú dokonalé.

### Chunk `fit-nb`

**Čo to robí:** Spustí Naive Bayes (`caret::method = "nb"`) s `fL = 1`, `usekernel = TRUE`, `adjust = 1`.

**Použité funkcie a balíky:** `klaR` poskytuje backend `NaiveBayes`, `caret` ho trénuje cez jednotné rozhranie. `expand.grid()` vytvára kombináciu hyperparametrov.

**Prečo Naive Bayes:** Je to parametrický baseline, ktorý silno predpokladá nezávislosť features. My vieme, že lexikálne features nezávislé nie sú, takže tento model slúži aj ako meranie ceny zlomeného predpokladu.

### Chunk `fit-rf`

**Čo to robí:** Spustí Random Forest cez `caret::method = "rf"`. Ako jediný z hlavných modelov používa surové dáta (`train_raw`, `test_raw`), lebo stromom neprekáža šikmosť ani rozdielna škála.

**Použité funkcie a balíky:** Backend je `randomForest`. `floor(sqrt(p))` nastavuje klasickú hodnotu `mtry` pre klasifikáciu. `ntree = 300` nastavuje počet stromov.

**Prečo RF:** Je to neparametrický model vhodný na interakcie medzi features. V Scenári 4 ho používame ako „teacher" model, lebo je presný, ale ťažko vysvetliteľný jedným obrázkom.

### Chunk `fit-svm`

**Čo to robí:** Spustí SVM s RBF kernelom cez `caret::method = "svmRadial"`, fixne s `C = 1` a `sigma = 0.1`.

**Použité funkcie a balíky:** Backend je `kernlab`. RBF kernel modeluje hladké nelineárne hranice v štandardizovanom priestore.

**Prečo SVM-RBF:** Lexical tier má slabé jednotkové signály, ale veľa signálu v kombináciách. RBF kernel je silný práve v situácii, kde hranica medzi phishing a legit nie je lineárna.

### Chunk `fit-knn`

**Čo to robí:** Spustí KNN (`caret::method = "knn"`) s `k = 25`. Pred fitovaním používa `jitter_features()` na drobné rozbitie úplných tie situácií.

**Použité funkcie a balíky:** `mutate(across(...))` (dplyr) pridáva jitter do vybraných features. `rnorm()` (base R) generuje malý gaussovský šum. `caret` trénuje KNN jednotne s ostatnými modelmi.

**Prečo KNN:** Je to najjednoduchší neparametrický model: rozhoduje podľa podobných historických URL. Je dobrý benchmark, ale deploymentovo drahší, lebo pri inferencii musí porovnávať nové URL s tréningovými vzorkami.

---

## Chunk `build-long`

```r
all_results <- list(res_lr, res_lda, res_nb, res_rf, res_svm, res_knn)

auc_long <- map_dfr(all_results, function(r) {
  imap_dfr(r$by_tier, function(tier_result, tier)
    tier_result$cv_per_fold %>%
      transmute(model = r$model, family = r$family, tier = tier,
                fold = Resample, auc = ROC))
})

test_tbl <- map_dfr(all_results, function(r) {
  imap_dfr(r$by_tier, function(t, tier) {
    tibble(model = r$model, family = r$family, tier = tier,
           train_auc = t$train_auc, ...)
  })
})

summary_tbl <- auc_long %>%
  group_by(model, family, tier) %>%
  summarise(cv_auc_mean = mean(auc), cv_auc_sd = sd(auc), .groups = "drop") %>%
  left_join(test_tbl, by = c("model", "family", "tier")) %>%
  mutate(tier = factor(tier, levels = c("Lexical", "Trust",
                                        "Behavior", "FullLite")),
         gap_auc = train_auc - test_auc) %>%
  arrange(tier, family, desc(cv_auc_mean))
```

**Čo to robí:** Konsoliduje všetky výsledky 6 modelov × 4 tiery do dvoch dlhých tabuliek (CV foldy + test metriky), spojí ich a vyrobí súhrnnú tabuľku.

**Použité funkcie:**
- `map_dfr` (purrr) — map + `bind_rows`. Pre každý model vráti tibble, automaticky spojí.
- `imap_dfr` — index-aware variant (potrebujeme názov tieru).
- `transmute` — `mutate` + `select` v jednom (zachovať len uvedené stĺpce).
- `factor(tier, levels = ...)` — explicitné poradie pre zobrazenie (Lexical → FullLite).

**Prečo two-step (long → wide)?**  
Long format umožňuje agregáciu cez foldy (CV mean/sd). Test metriky nie sú per-fold, sú jedno číslo, takže ich pridáme cez `left_join` po agregácii.

---

## Chunk `quality-table`

```r
quality_tbl <- test_tbl %>%
  mutate(tier = factor(tier, levels = c("Lexical", "Trust", "Behavior", "FullLite"))) %>%
  arrange(tier, family, desc(test_f1)) %>%
  transmute(Model = model, Family = family, Tier = tier,
            Accuracy    = round(test_acc,  4),
            ...)
```

**Čo to robí:** Renderuje tabuľku threshold-0.5 metrík (Accuracy, F1, Precision, Sensitivity, Specificity).

**Prečo threshold-0.5 metriky popri AUC?**  
AUC je threshold-free (ranking metrika). Proxy musí pri každom kliku vrátiť block/allow → potrebujeme **operating-point** metriky. F1 spája Precision a Sensitivity, ale skrýva Specificity — preto reportujeme všetky tri.

---

## Chunk `h1-minss`

```r
gap_tbl <- test_tbl %>%
  mutate(minSS = pmin(test_sens, test_spec)) %>%
  group_by(tier, family) %>%
  summarise(minSS = max(minSS),
            auc   = max(test_auc), .groups = "drop") %>%
  pivot_wider(names_from = family, values_from = c(minSS, auc)) %>%
  mutate(gap_minSS = `minSS_non-parametric` - minSS_parametric,
         gap_auc   = `auc_non-parametric`   - auc_parametric,
         tier = factor(tier, levels = c("Lexical", "Trust", "Behavior", "FullLite"))) %>%
  arrange(tier)
```

**Čo to robí:** Pre každý tier spočíta **gap** medzi najlepším non-param a najlepším param championom — primárna H1 metrika.

**Použité funkcie:**
- `pmin(a, b)` — element-wise minimum (parallel min). Vráti vektor.
- `pivot_wider` (tidyr) — z dlhého formátu (riadok = tier×family) na široký (riadok = tier, stĺpce = minSS_param, minSS_non-param, ...).
- Backticks `` `minSS_non-parametric` `` — názvy stĺpcov s pomlčkou potrebujú backticks.

**Champion selekcia cez `max(minSS)`:**  
Pre každú (tier, family) vyberieme **model s najvyššou minSS** ako championa. Toto je deployment-relevantná voľba — neignorujeme AUC, ale primárne hodnotíme operating-point.

---

## Chunky pre Scenár 4

### `task4-setup`

```r
library(rpart)
has_rpart_plot <- requireNamespace("rpart.plot", quietly = TRUE)
if (has_rpart_plot) suppressPackageStartupMessages(library(rpart.plot))

refit_rf_for_surrogate <- function(selected_tiers = c("Lexical", "FullLite"),
                                   ntree = 300) {
  path <- file.path(ARTIFACTS, "rf_for_surrogate.rds")
  rf_seed <- 20260430L
  fp <- digest::digest(list(...))
  if (file.exists(path)) {
    cached <- readRDS(path)
    if (isTRUE(cached$fp == fp)) return(cached$by_tier)
  }
  ...
  by_tier <- map(set_names(selected_tiers), function(tier) {
    feats <- tiers[[tier]]
    mtry  <- max(1, floor(sqrt(length(feats))))
    set.seed(rf_seed + match(tier, selected_tiers))
    fit <- randomForest(
      x     = train_raw %>% select(all_of(feats)),
      y     = train_raw$label,
      ntree = ntree,
      mtry  = mtry
    )
    fit
  })
  saveRDS(list(by_tier = by_tier, fp = fp), path)
  by_tier
}

rf_teachers <- refit_rf_for_surrogate()
```

**Prečo refit RF?**  
`fit_one_tier` v cache neuchováva fitted model objekt (kvôli veľkosti). Preto pre Scenár 4 musíme RF refit-núť — máme aspoň fixný seed pre reprodukciu.

**`requireNamespace("rpart.plot", quietly = TRUE)`** — graceful fallback. Ak `rpart.plot` nie je k dispozícii, použije sa primitívne `plot(tree)` z base.

**`set.seed(rf_seed + match(tier, selected_tiers))`** — rôzny seed per tier, ale deterministický.

### `task4-grid`

```r
tune_surrogate_tree <- function(tier, rf_fit,
                                maxdepths  = 3:7,
                                cps        = c(1e-4, 1e-3, 1e-2),
                                minbuckets = c(10, 30, 100)) {
  feats <- tiers[[tier]]
  tr_x  <- train_raw %>% select(all_of(feats))
  te_x  <- test_raw %>% select(all_of(feats))

  teacher_train <- predict(rf_fit, tr_x)
  teacher_test  <- predict(rf_fit, te_x)
  truth_test    <- test_raw$label

  rf_sens <- mean(teacher_test[truth_test == "Phishing"]   == "Phishing")
  rf_spec <- mean(teacher_test[truth_test == "Legitimate"] == "Legitimate")

  tr_data <- tr_x
  tr_data$teacher_label <- teacher_train

  scored <- crossing(maxdepth = maxdepths, cp = cps, minbucket = minbuckets) %>%
    pmap_dfr(function(maxdepth, cp, minbucket) {
    ...
    tree <- rpart(
      teacher_label ~ ., data = tr_data,
      method  = "class",
      model   = TRUE,
      control = rpart.control(maxdepth = md, cp = cpv,
                              minbucket = mb, xval = 0)
    )
    ...
    fidelity <- mean(pr_class == teacher_test)
    sens_vs_rf <- mean(pr_class[teacher_test == "Phishing"] == "Phishing")
    spec_vs_rf <- mean(pr_class[teacher_test == "Legitimate"] == "Legitimate")
    ...
  })
  ...
}
```

**Čo to robí:** Grid-search nad 5 × 3 × 3 = 45 kombináciami `(maxdepth, cp, minbucket)` pre `rpart`.

**Kľúčová idea — `tr_data$teacher_label <- teacher_train`:**  
Cieľová premenná stromu je **predikcia RF**, nie skutočný label. Strom sa učí RF imitovať.

**Použité funkcie:**
- `crossing(...)` (tidyr) — Cartesian product → tibble s 45 riadkami.
- `pmap_dfr(...)` (purrr) — map cez riadky tibble (každý riadok = jedna kombinácia parametrov).
- `rpart(formula, method = "class", control = rpart.control(...))` — fituje strom.
- `model = TRUE` — uloží training data v strome (potrebné pre niektoré rpart.plot funkcie).
- `xval = 0` — vypneme internú CV (robíme vlastnú evaluáciu).

**Metriky v každej kombinácii:**
- `fidelity` — overall agreement strom vs RF na test sete
- `sens_vs_rf`, `spec_vs_rf` — per-class fidelity
- `tree_sens`, `tree_spec` — strom vs ground truth (deployment view)
- `auc` — strom vs ground truth ako AUC

**`tibble(..., tree = list(tree))`** — uloží objekt stromu **ako list-column**, takže môžeme neskôr extrahovať vyhratý strom pre vykreslenie.

### `task4-depth-curve`

```r
rf_ref <- tibble(
  tier    = c("Lexical", "FullLite"),
  rf_auc  = c(res_rf$by_tier[["Lexical"]]$test_auc,
              res_rf$by_tier[["FullLite"]]$test_auc),
  rf_sens = c(res_rf$by_tier[["Lexical"]]$test_sens,
              res_rf$by_tier[["FullLite"]]$test_sens),
  rf_spec = c(res_rf$by_tier[["Lexical"]]$test_spec,
              res_rf$by_tier[["FullLite"]]$test_spec)
)

depth_tbl <- all_surr %>%
  group_by(tier, maxdepth) %>%
  arrange(desc(fidelity), leaves, .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  left_join(rf_ref, by = "tier") %>%
  transmute(...)
```

**Čo to robí:** Z výsledkov grid-searchu vyberie najlepší surrogate strom pre každú dvojicu `(tier, maxdepth)` a vytvorí tabuľku, ktorá ukazuje, ako sa fidelity zlepšuje s hĺbkou stromu.

**Použité funkcie:**
- `tibble()` (tibble/tidyverse) vytvorí malú referenčnú tabuľku s metrikami pôvodného RF.
- `group_by(tier, maxdepth)` (dplyr) rozdelí výsledky podľa tieru a maximálnej hĺbky.
- `arrange(desc(fidelity), leaves, .by_group = TRUE)` zoradí najprv podľa najvyššej zhody so RF, potom podľa menšieho počtu listov.
- `slice_head(n = 1)` vezme najlepší riadok z každej skupiny.
- `left_join(rf_ref, by = "tier")` pripojí RF referenčné AUC/Sens/Spec.
- `mutate(tier = factor(...))` vynúti poradie tierov vo výstupe.
- `transmute()` naraz vyberie a premenuje stĺpce pre finálnu tabuľku.
- `round()` zaokrúhli metriky na čitateľné štyri desatinné miesta.
- `kable()` (knitr) vykreslí tabuľku do HTML notebooku.

**Prečo je chunk dôležitý:** Bez tejto tabuľky by sme videli iba finálny vybraný strom. Depth curve ukazuje trade-off: hlbší strom lepšie kopíruje RF, ale rýchlo sa stáva nečitateľným. Preto potom zavádzame cap `<= 15` listov pre stromy, ktoré chceme ukázať na obhajobe.

**Prečo tidyverse:** `group_by()` + `slice_head()` je čitateľnejšie než ručné delenie dataframe-u cez `split()` a cyklus. Tu nejde len o výpočet, ale aj o auditovateľnosť: z kódu je jasné, že víťaz sa vyberá zvlášť pre každý tier a každú hĺbku.

### `task4-winners`

```r
MAX_PLOT_LEAVES <- 15L

winners <- all_surr %>%
  filter(leaves <= MAX_PLOT_LEAVES) %>%
  group_by(tier) %>%
  slice_max(fidelity, n = 1, with_ties = TRUE) %>%
  slice_min(leaves,   n = 1, with_ties = FALSE) %>%
  ungroup()
```

**Čo to robí:** Vyberie najfidelitnejší strom v rámci čitateľnosti capu (≤ 15 listov).

**Použité funkcie:**
- `slice_max(fidelity, n = 1, with_ties = TRUE)` — najvyššia fidelity, zachová ties.
- `slice_min(leaves, n = 1, with_ties = FALSE)` — z ties vyberie najmenej listov, ostatné odstráni.

### `task4-tree-lexical` a `task4-tree-fulllite`

```r
key_lex <- winners %>% filter(tier == "Lexical") %>%
  transmute(key = sprintf("md=%d_cp=%.0e_mb=%d", maxdepth, cp, minbucket)) %>%
  pull(key)
tree_lex <- surr_lex$trees[[key_lex]]

if (has_rpart_plot) {
  rpart.plot::rpart.plot(tree_lex, type = 2, extra = 104, fallen.leaves = TRUE,
                         box.palette = c("#D73027", "#1A9850"), main = ...)
} else {
  plot(tree_lex, uniform = TRUE, margin = 0.12, ...)
  text(tree_lex, use.n = TRUE, cex = 0.65)
}
```

**Čo to robí:** Vykreslí surrogate strom s farebne odlíšenými listami (červená phishing, zelená legitimate).

**`type = 2, extra = 104`** — rpart.plot kódy pre štýl uzlov a percent + count v listoch.

**Fallback `plot + text`** — ak `rpart.plot` nie je k dispozícii, použije primitívne base graphics.

### `task4-varimp`

```r
op <- par(mfrow = c(1, 2), mar = c(4, 7, 3, 1))
randomForest::varImpPlot(rf_teachers[["Lexical"]], n.var = ...)
randomForest::varImpPlot(rf_teachers[["FullLite"]], n.var = 10)
par(op)
```

**Čo to robí:** Variable importance plot priamo z RF (per-feature importance podľa Gini impurity decrease).

**`par(mfrow = c(1, 2))`** — base graphics layout: 1 riadok × 2 stĺpce, dva grafy vedľa seba.

**`par(op)` na konci** — obnoví pôvodné graphics nastavenia (best practice).

**Účel:** Cross-check, či root split surrogate stromu je aj **top-feature RF**. Ak áno, strom skutočne reflektuje rozhodovaciu logiku RF, nie len iný model so zhodnou test-set predikciou.
