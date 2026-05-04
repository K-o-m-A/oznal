# Dokumentácia kódu — `fit_core.R`

Centrálny súbor zdieľaný medzi **Shiny aplikáciou** (`app.R`) a **background workerom** (`callr::r_bg`). Obsahuje statickú metadátu projektu, helpery na načítanie a split datasetu, a fitovacie funkcie pre 6 modelov. **Nesmie závisieť od `shiny`**, lebo background worker `shiny` nemá.

---

## Časť 1 — Načítanie balíkov

```r
suppressPackageStartupMessages({
  library(tidyverse)
  library(caret)
  library(glmnet)
  library(MASS, exclude = "select")
  library(klaR)
  library(randomForest)
  library(kernlab)
  library(pROC)
})
```

**Čo to robí:** Nahrá všetky balíky **ticho** (bez startup banners).

**`suppressPackageStartupMessages({...})`** — wrapper, ktorý potlačí výstup typu „Loading required package: ...". Pri Shiny aplikácii by tieto banners zaplnili konzolu.

| Balík | Použitie |
|-------|----------|
| `tidyverse` | dplyr, ggplot2, purrr, ... |
| `caret` | unifikovaný model wrapper |
| `glmnet` | LR-Ridge |
| `MASS` (bez select) | LDA |
| `klaR` | Naive Bayes (cez caret) |
| `randomForest` | RF |
| `kernlab` | SVM-RBF (cez caret) |
| `pROC` | AUC + ROC krivky |

**Prečo `pROC` namiesto `yardstick` ako v notebookoch?**  
`pROC::roc` vracia bohatý objekt, ktorý zahrnuje **per-threshold sensitivity/specificity** body — to je presne to, čo potrebuje Shiny app pre interaktívne ROC krivky. `yardstick` má len skalárne metriky.

---

## Časť 2 — Statická metadáta projektu

```r
ID_COLS          <- c("FILENAME", "URL", "Domain", "TLD", "Title")
SCORES           <- c("URLSimilarityIndex", ...)
REDUNDANT_BINARY <- "HasObfuscation"
RATIOS           <- c("LetterRatioInURL", ...)
EXCLUDE_COLS     <- c(ID_COLS, SCORES, REDUNDANT_BINARY, RATIOS)

family_map <- tribble(
  ~feature, ~family,
  ...
)

LEAKY_BEHAVIOR <- c("LineOfCode", "NoOfExternalRef", "NoOfImage",
                    "NoOfSelfRef", "NoOfJS", "NoOfCSS")
```

**Čo to robí:** Replikuje EDA exclusions a family map z notebookov ako **single source of truth**.

**Prečo duplikujeme z notebookov?**  
Notebooky sú samostatné dokumenty (knit-ujú sa nezávisle). Shiny app sa však spúšťa **bez nich** — preto musí mať vlastnú kópiu metadát. Konzistencia je manuálna (commit to oboch + grep cross-check).

---

## Časť 3 — `build_tiers` a globálne konstanty

```r
build_tiers <- function() {
  list(
    Lexical  = family_map %>% filter(family == "Lexical")  %>% pull(feature),
    Trust    = family_map %>% filter(family == "Trust")    %>% pull(feature),
    Behavior = setdiff(
      family_map %>% filter(family == "Behavior") %>% pull(feature),
      LEAKY_BEHAVIOR
    ),
    FullLite = setdiff(family_map$feature, LEAKY_BEHAVIOR)
  )
}

TIERS_ALL <- names(build_tiers())

MODEL_CHOICES <- c(
  "LogReg-Ridge" = "lr",
  "LDA"          = "lda",
  ...
)

MODEL_FAMILY <- c(
  lr  = "parametric",
  ...
  knn = "non-parametric"
)
```

**Čo to robí:**
- `build_tiers()` — produkuje 4-tier list (zhodný so Scenár 2).
- `MODEL_CHOICES` — named character vektor pre Shiny `selectInput`. Mená sú user-facing labels („LogReg-Ridge"), hodnoty sú interné kľúče („lr").
- `MODEL_FAMILY` — mapuje kľúč na rodinu (parametric / non-parametric).

**Prečo named character vektor pre `selectInput`?**  
Shiny `selectInput(choices = MODEL_CHOICES)` automaticky použije mená ako **labels v UI** a hodnoty ako **vrátený `input` vector**.

---

## Časť 4 — `default_dataset_path`

```r
default_dataset_path <- function() {
  candidates <- c("PhiUSIIL_Phishing_URL_Dataset.csv",
                  "../PhiUSIIL_Phishing_URL_Dataset.csv")
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[1] else NA_character_
}
```

**Čo to robí:** Hľadá CSV v aktuálnom adresári alebo o úroveň vyššie. Vráti cestu alebo `NA_character_`.

**Použité funkcie:**
- `file.exists(vec)` — vektorizované, vráti logický vektor.
- `candidates[hit]` — filtrovanie cez logical indexing.
- `NA_character_` — typed NA. Bez typu by `NA` bolo logical NA, čo by mohlo zlomiť volajúce miesto.

---

## Časť 5 — `load_and_clean`

```r
load_and_clean <- function(path) {
  raw <- read_csv(path, show_col_types = FALSE)
  names(raw)[1] <- sub("^\xef\xbb\xbf", "", names(raw)[1], useBytes = TRUE)
  raw %>%
    mutate(label = factor(label, levels = c(1, 0),
                          labels = c("Phishing", "Legitimate"))) %>%
    select(-all_of(EXCLUDE_COLS)) %>%
    as.data.frame()
}
```

**Čo to robí:** Načíta dataset, odstráni UTF-8 BOM, factor-uje label, vyhodí EXCLUDE_COLS, konvertuje na `data.frame`.

**Pozn.:** Tu je BOM odstránený **byte-wise** (`useBytes = TRUE`) — to je rozdiel oproti notebookom kde používame `str_remove(.x, "^﻿")`. Byte-wise je odolnejšie voči locale-nastaveniam OS, čo je dôležité pre Shiny app, ktorý môže bežať aj v Dockri.

**Prečo `as.data.frame()` na konci?**  
`caret`-ovský `train` občas má subtle bugs s tibble (S3 dispatch, indexing). Konverzia na klasický `data.frame` je defenzívna.

---

## Časť 6 — `make_splits`

```r
make_splits <- function(df, n_sub, p_train, k_folds) {
  half <- floor(n_sub / 2)
  df_sub <- df %>%
    group_by(label) %>%
    slice_sample(n = half) %>%
    ungroup() %>%
    as.data.frame()

  idx       <- createDataPartition(df_sub$label, p = p_train, list = FALSE)
  train_raw <- df_sub[idx, ]
  test_raw  <- df_sub[-idx, ]
  fold_idx  <- createFolds(train_raw$label, k = k_folds, returnTrain = TRUE)

  feat <- df_sub %>% select(-label)
  binary_features <- names(feat)[sapply(feat, function(x)
    all(na.omit(x) %in% c(0, 1)))]
  continuous_features <- setdiff(names(feat), binary_features)

  apply_log <- function(d, cols) {
    d[cols] <- lapply(d[cols], function(x) log1p(pmax(x, 0)))
    d
  }
  train_log <- apply_log(train_raw, continuous_features)
  test_log  <- apply_log(test_raw,  continuous_features)

  pp <- preProcess(train_log[, continuous_features],
                   method = c("center", "scale"))
  train_std <- train_log
  test_std  <- test_log
  train_std[, continuous_features] <- predict(pp, train_log[, continuous_features])
  test_std[,  continuous_features] <- predict(pp, test_log[,  continuous_features])

  list(train_raw = train_raw, test_raw = test_raw,
       train_std = train_std, test_std = test_std,
       fold_idx  = fold_idx,
       continuous_features = continuous_features,
       binary_features     = binary_features)
}
```

**Čo to robí:** **Jediný entry point** pre všetky split-y — produkuje:
- `train_raw`, `test_raw` — bez transformácií (pre RF)
- `train_std`, `test_std` — `log1p` + center/scale (pre LR/LDA/NB/SVM/KNN)
- `fold_idx` — 10-fold CV indexy
- zoznamy spojitých a binárnych features

**Prečo všetko v jednej funkcii?**  
Zaručí, že **všetky split-y vychádzajú z toho istého `df_sub` a `idx`**. Kdebysi to volal z viacerých miest s rôznymi seed-mi, dostal by si nekonzistentné výsledky.

**Pozn.:** Tu používame **base R indexing** (`df_sub[idx, ]`, `feat[cols]`) namiesto dplyr-u, lebo **base R je rýchlejšie pre malé operácie** a `caret::preProcess` interaguje s base S3.

**`apply_log` ako vnútorná funkcia** — používa `lapply` namiesto `mutate(across(...))`, lebo to je jednoduchšie pre raw `data.frame`.

**Návrat ako list:**  
`list(...)` — všetky potrebné objekty pre downstream fits. Volajúci robí `splits$train_std` a podobne.

---

## Časť 7 — `fit_one_tier`

```r
fit_one_tier <- function(tier_features, data_train, data_test, fold_idx,
                         method, tuneGrid = NULL, ...) {
  tr <- data_train[, c("label", tier_features)]
  te <- data_test[,  c("label", tier_features)]

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

  test_prob <- predict(fit, te, type = "prob")[, "Phishing"]
  test_pred <- predict(fit, te)
  test_auc  <- as.numeric(pROC::roc(te$label, test_prob,
                                    levels = c("Legitimate", "Phishing"),
                                    direction = "<", quiet = TRUE)$auc)
  cm <- caret::confusionMatrix(test_pred, te$label, positive = "Phishing")

  train_prob <- predict(fit, tr, type = "prob")[, "Phishing"]
  ...
  
  list(
    cv_per_fold = fit$resample,
    train_auc   = train_auc, train_acc = ...,
    test_auc    = test_auc, ..., test_spec = ...,
    train_secs  = elapsed,
    roc_points  = {
      r <- pROC::roc(te$label, test_prob,
                     levels = c("Legitimate", "Phishing"),
                     direction = "<", quiet = TRUE)
      tibble(fpr = 1 - r$specificities, tpr = r$sensitivities)
    }
  )
}
```

**Čo to robí:** **Identická funkcia ako v `scenario_2.rmd`**, len s navyše:
- `roc_points` v output-e — body ROC krivky pre interaktívne vykreslenie v Shiny
- `pROC::roc(...)` namiesto `yardstick::roc_auc_vec()` (potrebujeme objekt aj pre AUC aj pre body)

**Použité funkcie:**
- `pROC::roc(truth, prob, levels = c("Legitimate", "Phishing"), direction = "<")`:
  - `levels = c("L", "P")` — definuje, ktorá trieda je „pozitívna" (druhá je pozitívna pri default-e).
  - `direction = "<"` — vyšší prob → vyššia pravdepodobnosť pozitívnej triedy.
  - `quiet = TRUE` — neukáže warning o tom, že direction je explicit.
- `r$specificities` / `r$sensitivities` — vektory cez všetky thresholdy (z čoho zostavíme TPR/FPR krivku).

---

## Časť 8 — `jitter_features`

```r
jitter_features <- function(d, cols, sd = 1e-3) {
  for (c in cols) d[[c]] <- d[[c]] + rnorm(nrow(d), 0, sd)
  d
}
```

**Čo to robí:** Pridá Gaussian jitter na binárky pre KNN.

**Prečo `for` loop a nie `mutate(across)`?**  
Toto beží na raw `data.frame` (po make_splits), kde `mutate` by zmenil typ na tibble. `for` cez `[[<-` udržuje typ.

---

## Časť 9 — `fit_model_for_tier`

```r
fit_model_for_tier <- function(model_id, tier_features, splits, params) {
  switch(model_id,
    lr  = fit_one_tier(tier_features, splits$train_std, splits$test_std,
                       splits$fold_idx, method = "glmnet",
                       tuneGrid = data.frame(alpha  = params$lr_alpha,
                                             lambda = params$lr_lambda)),
    lda = fit_one_tier(tier_features, splits$train_std, splits$test_std,
                       splits$fold_idx, method = "lda"),
    nb  = suppressWarnings(fit_one_tier(...)),
    rf  = fit_one_tier(tier_features, splits$train_raw, splits$test_raw, ...),
    svm = fit_one_tier(...),
    knn = {
      tr_j <- jitter_features(splits$train_std, tier_features)
      te_j <- jitter_features(splits$test_std,  tier_features)
      fit_one_tier(tier_features, tr_j, te_j, splits$fold_idx,
                   method = "knn",
                   tuneGrid = data.frame(k = params$knn_k))
    }
  )
}
```

**Čo to robí:** **Dispatcher** — pre daný `model_id` zavolá `fit_one_tier` so správnymi argumentami.

**Použité funkcie:**
- `switch(x, case1 = expr1, case2 = expr2, ...)` (base R) — väčší a čistejší ako `if-else if-else if-...`.

**Hyperparametre cez `params` list:**  
`params$lr_alpha`, `params$rf_ntree`, ... — Shiny app posiela jeden list, používateľ ho môže meniť cez slidery v UI. Z toho dostávame **konzistentnú konfiguráciu pre všetky modely**.

**`suppressWarnings` len pre NB:**  
Naive Bayes generuje warnings o features so zero variance per třídu — neaplikovateľné v praxi, ale spam-uje konzolu.

---

## Časť 10 — `run_fits_bg` (background worker entry point)

```r
run_fits_bg <- function(work_dir, core_path) {
  source(core_path)

  inputs    <- readRDS(file.path(work_dir, "inputs.rds"))
  splits    <- inputs$splits
  combos    <- inputs$combos
  params    <- inputs$params
  tiers_def <- inputs$tiers_def

  n <- nrow(combos)
  t_start <- Sys.time()

  write_progress <- function(i, current, status) {
    saveRDS(
      list(i = i, n = n, current = current, status = status,
           t_start = t_start, t_now = Sys.time()),
      file.path(work_dir, "progress.rds")
    )
  }

  write_progress(0, "(starting)", "starting")

  for (i in seq_len(n)) {
    m <- combos$model[i]
    t <- combos$tier[i]
    write_progress(i, sprintf("%s on %s", m, t), "fitting")

    res <- tryCatch(
      fit_model_for_tier(m, tiers_def[[t]], splits, params),
      error = function(e) list(error = conditionMessage(e))
    )
    saveRDS(
      list(model = m, tier = t, res = res),
      file.path(work_dir, sprintf("res_%s__%s.rds", m, t))
    )
  }

  write_progress(n, "(done)", "done")
  invisible(TRUE)
}
```

**Čo to robí:** **Toto je entry point pre background process** spustený cez `callr::r_bg()` zo Shiny aplikácie.

**Mechanizmus:**
1. Shiny app uloží `inputs.rds` (splits, combos, params) do `work_dir`.
2. Background R process **sourcuje `fit_core.R`** a volá `run_fits_bg(work_dir, core_path)`.
3. Pre každú kombináciu (model, tier):
   - Aktualizuje `progress.rds` (Shiny UI ho periodicky číta cez `invalidateLater`).
   - Fituje model.
   - Uloží výsledok do `res_<model>__<tier>.rds`.
4. Po dokončení napíše `status = "done"` do progress.

**Prečo background process?**  
Fitovanie 6 modelov × 4 tier = 24 fitov = niekoľko minút. Bez background-u by Shiny UI **úplne zamrzlo**. `callr::r_bg` spustí samostatný R proces, takže UI ostane responzívne.

**`tryCatch(...) ` per-fit:**  
Ak by jeden fit zlyhal (napr. SVM kernlab problem na malom Trust tieri), zachytíme error a uložíme `list(error = msg)` namiesto výsledku. Ostatné fity pokračujú.

**Súborová komunikácia (RDS files), nie shared memory:**  
`callr` background process je **úplne nezávislý R**, nezdieľa pamäť. Komunikácia ide cez disk — `saveRDS` v workerovi, `readRDS` v Shiny app-e. Trochu pomalšie, ale **robustné** (worker môže crashnúť bez zhodenia UI).
