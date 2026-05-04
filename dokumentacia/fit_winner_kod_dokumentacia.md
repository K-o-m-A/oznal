# Dokumentácia kódu — `fit_winner.R`

Jednorazový skript, ktorý **natrénuje víťazný model** (SVM-RBF na Lexical tieri) a uloží **bohatý artefakt** `artifacts/winner_svm_lexical.rds`. Tento artefakt potom Shiny app číta v záložke „Winning Model".

**Spúšťa sa raz** (z Windows R / RStudio):
```r
setwd("C:/Users/frede/PycharmProjects/oznal-project")
source("fit_winner.R")
```

---

## Časť 1 — Setup

```r
suppressPackageStartupMessages({
  source("fit_core.R")
})

set.seed(2026)

ARTIFACTS_DIR <- "artifacts"
if (!dir.exists(ARTIFACTS_DIR)) dir.create(ARTIFACTS_DIR, showWarnings = FALSE)
WINNER_PATH <- file.path(ARTIFACTS_DIR, "winner_svm_lexical.rds")
```

**Čo to robí:** Načíta zdieľaný `fit_core.R` (ktorý dá k dispozícii `default_dataset_path`, `load_and_clean`, `make_splits`, `build_tiers`).

**Pozn.:** `source("fit_core.R")` sa volá z **identického seed-u** (2026) ako notebooky a Shiny — výsledky sú **plne reprodukovateľné**.

---

## Časť 2 — Načítanie dát + split

```r
dataset_path <- default_dataset_path()
if (is.na(dataset_path))
  stop("PhiUSIIL_Phishing_URL_Dataset.csv not found in project root or parent.")

message("[winner] loading dataset: ", dataset_path)
df <- load_and_clean(dataset_path)

message("[winner] building splits (n_sub=30000, p_train=0.8, k=10)")
splits <- make_splits(df, n_sub = 30000, p_train = 0.8, k_folds = 10)

tiers <- build_tiers()
lex   <- tiers$Lexical
```

**Čo to robí:** Identický pipeline ako Scenár 2 — načítaj, split, vyber Lexical features.

**`message(...)`** — výstup na **stderr** (na rozdiel od `cat` / `print` ktoré idú na stdout). Pri Rscript spúšťaní rozlišuje progress messages od skutočných výsledkov.

---

## Časť 3 — Fitovanie SVM-RBF na Lexical

```r
ctrl <- caret::trainControl(
  method          = "cv",
  index           = splits$fold_idx,
  classProbs      = TRUE,
  summaryFunction = caret::twoClassSummary,
  savePredictions = "final"
)

message("[winner] fitting SVM-RBF (C=1, sigma=0.1)... this takes a few minutes")
t0 <- Sys.time()
fit <- caret::train(
  label ~ .,
  data      = splits$train_std[, c("label", lex)],
  method    = "svmRadial",
  trControl = ctrl,
  metric    = "ROC",
  tuneGrid  = data.frame(C = 1, sigma = 0.1)
)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
```

**Čo to robí:** Identický fit ako v Scenári 2 (SVM-RBF, Lexical, C=1, σ=0.1, 10-fold CV).

**Prečo refit, keď je už natrénovaný v Scenári 2?**  
Notebookov cache (`scenario_2/artifacts/res_svm.rds`) obsahuje **metriky**, nie samotný **fitted model object**. Pre Shiny záložku „Winner showcase" potrebujeme objekt, ktorý dokáže **predikovať na nové URL** zadané používateľom v UI.

---

## Časť 4 — Test set evaluation a ROC

```r
te         <- splits$test_std[, c("label", lex)]
test_prob  <- predict(fit, te, type = "prob")[, "Phishing"]
test_label <- te$label
roc_obj    <- pROC::roc(test_label, test_prob,
                        levels = c("Legitimate", "Phishing"),
                        direction = "<", quiet = TRUE)
message(sprintf("[winner] test AUC = %.4f", as.numeric(roc_obj$auc)))
```

**Čo to robí:** Skóruje na test sete a vytvorí kompletný `pROC::roc` objekt (so všetkými per-threshold sensitivity/specificity bodmi pre interaktívnu ROC krivku v Shiny).

---

## Časť 5 — Pre-fit hyperparameter grid

```r
C_GRID     <- c(0.1, 0.25, 0.5, 1, 2, 5, 10)
SIGMA_GRID <- c(0.01, 0.025, 0.05, 0.1)
hp_combos  <- expand.grid(C = C_GRID, sigma = SIGMA_GRID,
                          KEEP.OUT.ATTRS = FALSE)
n_combos   <- nrow(hp_combos)
message(sprintf("[winner] pre-fitting (C, sigma) grid: %d combos", n_combos))

ctrl_single <- caret::trainControl(method = "none", classProbs = TRUE)
hp_results  <- list()
g0 <- Sys.time()
for (i in seq_len(n_combos)) {
  C_val <- hp_combos$C[i]; s_val <- hp_combos$sigma[i]
  key   <- sprintf("C=%g_s=%g", C_val, s_val)
  ti    <- Sys.time()
  cell <- tryCatch({
    fit_i <- caret::train(
      label ~ ., data = splits$train_std[, c("label", lex)],
      method = "svmRadial", trControl = ctrl_single,
      tuneGrid = data.frame(C = C_val, sigma = s_val)
    )
    prob_i <- as.numeric(
      predict(fit_i, splits$test_std[, c("label", lex)], type = "prob")[, "Phishing"])
    if (anyNA(prob_i))
      stop("kernlab returned NA probabilities (numerical instability)")
    auc_i <- as.numeric(pROC::roc(...)$auc)
    list(test_prob = prob_i, test_auc = auc_i)
  }, error = function(e) {
    message(sprintf("[grid %2d/%d] C=%-5g sigma=%-6g SKIPPED: %s",
                    i, n_combos, C_val, s_val, conditionMessage(e)))
    NULL
  })
  if (!is.null(cell)) {
    hp_results[[key]] <- cell
    ...
  }
}
```

**Čo to robí:** Predspraví **7 × 4 = 28 fitov** pre rôzne (C, sigma) kombinácie. Toto umožňuje Shiny app záložke „Winner showcase" **prepnúť hyperparametre cez slidre v UI** bez opätovného fitovania (každý fit by trval ~30s, pri každom posune slidra by používateľ čakal).

**Use-case:** Používateľ presúva slider C alebo sigma → app spočíta `key = "C=2_s=0.05"` → **lookup v `hp_results`** → okamžite zobrazí ROC + metriky.

**`expand.grid(C = ..., sigma = ..., KEEP.OUT.ATTRS = FALSE)`** — Cartesian product. `KEEP.OUT.ATTRS = FALSE` neulpí na atribútoch.

**`trainControl(method = "none")`** — žiadny CV, len jeden fit (lebo tu nás zaujíma test-set AUC, nie CV stabilita).

**`tryCatch(..., error = ...)`:**  
Pri vysokých sigma + nízkych C má kernlab numerickú nestabilitu (line search fails, NaN pravdepodobnosti). Zachytíme error a kombináciu **preskočíme** (ostatné pokračujú).

**Komentár v kóde** vysvetľuje, prečo sigma > 0.1 je vyhodené z gridu — empiricky to padá.

**`anyNA(prob_i)`** — defenzívna kontrola: aj keď kernlab nezhodí error, môže vrátiť NaN. Vtedy explicitne stopneme.

---

## Časť 6 — Feature stats (pre UI sliders)

```r
raw_lex <- splits$train_raw[, lex]
feature_stats <- lapply(raw_lex, function(x) {
  list(
    min       = min(x, na.rm = TRUE),
    max       = max(x, na.rm = TRUE),
    median    = stats::median(x, na.rm = TRUE),
    q05       = unname(stats::quantile(x, 0.05, na.rm = TRUE)),
    q95       = unname(stats::quantile(x, 0.95, na.rm = TRUE)),
    is_binary = all(stats::na.omit(x) %in% c(0, 1))
  )
})
```

**Čo to robí:** Pre každý lexikálny feature spočíta štatistiky, ktoré Shiny použije na **inteligentné defaulty slider-ov**.

**Use-case:** Používateľ otvorí Winner záložku → app vidí slider pre `URLLength` s rozsahom `min` až `max` a default-om `median`. Pre binárky `IsDomainIP` je to namiesto slidra **checkbox**.

**`unname(...)`** — `quantile` vracia named vektor („5%", „95%"). `unname` odstráni mená pre čistejší rds.

---

## Časť 7 — Pre-fit preProcess pre Lexical only

```r
pp_continuous <- intersect(splits$continuous_features, lex)
pp_binary     <- intersect(splits$binary_features,     lex)

train_lex_log <- splits$train_raw[, lex, drop = FALSE]
train_lex_log[pp_continuous] <- lapply(train_lex_log[pp_continuous],
                                       function(x) log1p(pmax(x, 0)))
pp <- caret::preProcess(train_lex_log[, pp_continuous, drop = FALSE],
                        method = c("center", "scale"))
```

**Čo to robí:** Vyrobí `pp` objekt **fitovaný iba na Lexical features**, takže Shiny dokáže škálovať user-poskytnuté URL **bez závislosti na celom datasete**.

**Komentár v kóde:**  
> *„Per-column center/scale je nezávislé, takže to dá bit-for-bit identické škálovanie ako pri tréningu, ale bundle ostáva self-contained."*

**`drop = FALSE`** — pri jednom stĺpci nezredukuje na vector.

**Use-case:** Používateľ zadá `URLLength = 50, NoOfDegitsInURL = 3, ...` → app aplikuje `log1p` + `predict(pp, user_data)` → predikuje SVM.

---

## Časť 8 — Bundle a uloženie

```r
bundle <- list(
  fit            = fit,                    # caret train object
  pp             = pp,                     # preProcess object
  pp_continuous  = pp_continuous,
  pp_binary      = pp_binary,
  features       = lex,
  feature_stats  = feature_stats,
  test_prob      = as.numeric(test_prob),
  test_label     = test_label,
  roc_obj        = roc_obj,
  hp_grid        = list(C = C_GRID, sigma = SIGMA_GRID),
  hp_results     = hp_results,
  meta = list(
    model      = "SVM-RBF",
    tier       = "Lexical",
    C          = 1,
    sigma      = 0.1,
    n_train    = nrow(splits$train_std),
    n_test     = nrow(splits$test_std),
    n_features = length(lex),
    test_auc   = as.numeric(roc_obj$auc),
    fit_time   = Sys.time(),
    train_secs = elapsed
  )
)

saveRDS(bundle, WINNER_PATH)
message("[winner] saved -> ", WINNER_PATH)
message(sprintf("[winner] file size: %.1f MB",
                file.info(WINNER_PATH)$size / 1024^2))
```

**Čo to robí:** Skompletizuje **všetko, čo Shiny potrebuje**, do jedného RDS súboru.

**Štruktúra bundle-u:**

| Pole | Účel |
|------|------|
| `fit` | model objekt — na predikciu |
| `pp`, `pp_continuous`, `pp_binary` | preprocessing objekty pre user input |
| `features` | zoznam features v správnom poradí |
| `feature_stats` | min/max/median/q05/q95 pre slider defaulty |
| `test_prob`, `test_label` | test-set výsledky pre histogram + ROC |
| `roc_obj` | `pROC::roc` objekt s celou krivkou |
| `hp_grid`, `hp_results` | pre-fitované (C, sigma) kombinácie |
| `meta` | textová metadata pre info-card v UI |

**Veľkosť výsledku:** SVM s 24k vzoriek a Lexical (13 features) má niekoľko desiatok MB (väčšinu zaberá `fit` so support vectors).

**`file.info(...)$size / 1024^2`** — veľkosť v MB pre log.

**`invisible(bundle)`** — vráti bundle ako návratovú hodnotu, ale tichu (nepríde do konzoly pri `source()`).
