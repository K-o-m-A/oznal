# Dokumentácia kódu — `scenario_3.rmd`

Detailný popis každého chunku v Scenári 3.

---

## Ako túto dokumentáciu čítať

`scenario_3.rmd` je notebook o feature selection. Najdôležitejšie je sledovať rozdiel medzi tromi typmi objektov:

1. **Dáta po preprocessingu** — `train_std`, `test_std`, `predictors`, `lexical_predictors`.
2. **Fitted modely** — stepwise `glm` objekt a `cv.glmnet` objekty pre lasso/elastic-net.
3. **Vybrané features** — character vektory termov, ktoré prežili danú metódu.

V dokumentácii preto pri každom chunke rozlišujeme:

- ako vzniká vstupná tabuľka,
- ako sa fituje model,
- ako sa z modelu extrahuje support,
- ako sa počítajú metriky a diagnostiky.

### Prečo je tu menej `caret::train()`

Scenár 2 používa `caret`, lebo porovnáva veľa modelových rodín. Scenár 3 potrebuje priamy prístup k detailom feature-selection ciest:

- `MASS::stepAIC()` poskytuje AIC cestu a `keep` callback,
- `glmnet::cv.glmnet()` poskytuje lambda cestu a koeficienty pri `lambda.1se`.

Keby sme všetko obalili cez `caret`, prišli by sme o časť detailov potrebných pre diagnostické tabuľky. Tidyverse však stále používame na prípravu dát, skladanie tabuliek, `map_*` výpočty a vizualizácie.

### Najdôležitejšie funkčné rodiny

| Rodina | Funkcie | Prečo |
|---|---|---|
| split/preprocess | `createDataPartition`, `createFolds`, `preProcess` | porovnateľnosť so Scenárom 2 |
| stepwise | `glm`, `stepAIC`, `glm.control` | algoritmická FS cesta |
| glmnet | `model.matrix`, `cv.glmnet`, `coef`, `predict` | embedded FS a lambda cesta |
| tidyverse | `select`, `mutate`, `map_dfr`, `unnest`, `pivot_*` | čisté tabuľkové spracovanie výsledkov |
| yardstick | `roc_auc_vec`, `sens_vec`, `spec_vec`, `accuracy_vec` | jednotné metriky |

---

## Chunk `libraries`

```r
library(tidyverse)
library(caret)
library(glmnet)
library(MASS, exclude = "select")
library(yardstick)
library(knitr)
library(digest)

set.seed(2026)

ARTIFACTS <- "scenario_3/artifacts"
dir.create(ARTIFACTS, recursive = TRUE, showWarnings = FALSE)
GLMNET_LAMBDA_MIN_RATIO <- 1e-3
STEPWISE_GLM_MAXIT <- 100L
```

| Balík | Použitie | Prečo zvolený |
|-------|----------|---------------|
| `tidyverse` | dplyr, ggplot2, purrr, tidyr | Konzistentný stack pre dátovú prácu. |
| `caret` | `createDataPartition`, `createFolds`, `preProcess` | Pre konzistentnosť so Scenárom 2. |
| `glmnet` | `cv.glmnet` pre lasso/elastic-net | Štandardná C-implementácia coordinate descent-u. Bez alternatívy. |
| `MASS, exclude = "select"` | `stepAIC()` pre bidirectional selection | `MASS::select` koliduje s `dplyr::select`. |
| `yardstick` | `roc_auc_vec`, `sens_vec`, `spec_vec` | Vektorové metriky bez tvorby objektu. |
| `knitr` | `kable()` | Formátované tabuľky v HTML. |
| `digest` | hashovanie pre cache fingerprint | Bez alternatívy. |

**Konštanty:**
- `GLMNET_LAMBDA_MIN_RATIO = 1e-3` — `cv.glmnet` štandardne skúša `lambda.min/lambda.max = 1e-2`. Znížením na `1e-3` skúša širší rozsah, takže pri vysokom λ výber features sa rozoznáva lepšie.
- `STEPWISE_GLM_MAXIT = 100L` — pre `glm.control(maxit = 100)`. Default je 25, pri kompletnej separácii (čo je u nás na FullLite) potrebujeme viac iterácií.

---

## Chunk `load-data`

```r
dataset_path <- if (file.exists("PhiUSIIL_Phishing_URL_Dataset.csv")) {
  ...
} else stop("PhiUSIIL_Phishing_URL_Dataset.csv not found")

raw <- read_csv(dataset_path, show_col_types = FALSE) %>%
  rename_with(~ str_remove(.x, "^﻿"))
```

**Identický pattern ako v Scenári 2** — nájde dataset v projekt-roote alebo o úroveň vyššie, načíta cez `read_csv`, odstráni UTF-8 BOM.

---

## Chunk `exclusions`

```r
ID_COLS          <- c("FILENAME", "URL", "Domain", "TLD", "Title")
SCORES           <- c(...)
REDUNDANT_BINARY <- "HasObfuscation"
RATIOS           <- c(...)
LEAKY_BEHAVIOR   <- c("LineOfCode", "NoOfExternalRef", "NoOfImage",
                      "NoOfSelfRef", "NoOfJS", "NoOfCSS")
EXCLUDE_COLS     <- c(ID_COLS, SCORES, REDUNDANT_BINARY, RATIOS, LEAKY_BEHAVIOR)

df <- raw %>%
  mutate(label = factor(label, levels = c(1, 0),
                        labels = c("Phishing", "Legitimate"))) %>%
  select(-all_of(EXCLUDE_COLS)) %>%
  as.data.frame()
```

**Čo to robí:** Aplikuje **rovnaké exclusions ako Scenár 2** + navyše už tu vyhadzuje 6 near-leakers (lebo Scenár 3 ich nikdy nepoužíva).

**Pozn.:** `as.data.frame()` na konci — `MASS::stepAIC` interaguje s base S3 metódami a tibble môže občas spôsobiť subtle bugs (s `[<-`, `is.data.frame`).

---

## Chunk `subsample-split`

```r
N_SUB <- 30000
df_sub <- df %>%
  group_by(label) %>%
  slice_sample(n = N_SUB / 2) %>%
  ungroup() %>%
  as.data.frame()

idx <- createDataPartition(df_sub$label, p = 0.8, list = FALSE) %>% as.vector()
train_raw <- df_sub %>% slice(idx)
test_raw <- df_sub %>% slice(-idx)
fold_idx <- createFolds(train_raw$label, k = 10, returnTrain = TRUE)
```

**Čo to robí:** **Identický 30k stratifikovaný subsample + 80/20 split + 10-fold CV ako Scenár 2.**

**Prečo identický?**  
Aby AUC reduced fitov v Scenári 3 mohlo byť priamo porovnané s LogReg-Ridge zo Scenára 2 bez **sample-size confound-u**.

**`as.vector()` po `createDataPartition`:**  
`createDataPartition` vracia matrix (1 stĺpec). `as.vector()` to flattnuje na vektor pre použitie v `slice()`.

**`slice(idx)` vs `slice(-idx)`:**  
`slice` je dplyr alternatíva pre `df[idx, ]`. `-idx` znamená všetky riadky **okrem** týchto.

---

## Chunk `recipes`

```r
feat <- df_sub %>% dplyr::select(-label)
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
  scaled <- d %>% select(all_of(continuous_features)) %>% predict(pp, .)
  d %>% mutate(across(all_of(continuous_features), ~ scaled[[cur_column()]]))
}

train_std <- replace_continuous(train_log)
test_std  <- replace_continuous(test_log)

predictors <- setdiff(names(train_std), "label")
lexical_predictors <- c("URLLength", "DomainLength", "IsDomainIP", ...)
lexical_predictors <- intersect(lexical_predictors, predictors)
primary_predictors <- lexical_predictors
```

**Čo to robí:** **Identický preprocessing ako Scenár 2** — `log1p` + center/scale.

**Nové premenné:**
- `predictors` — všetky stĺpce okrem label-u (= FullLite tier).
- `lexical_predictors` — explicitný zoznam 13 lexikálnych prediktorov.
- `intersect(lexical_predictors, predictors)` — defenzívna ochrana, ak by niektorý prediktor v dataset chýbal.
- `primary_predictors <- lexical_predictors` — alias pre čitateľnosť (primárny scenár je Lexical).

**`dplyr::select`** s explicitným namespacom — dôležité, lebo `MASS` má vlastný `select`. Aj keď sme `MASS` nahrali s `exclude = "select"`, je to safe-defaulting habit.

---

## Chunk `cache-helper`

```r
fp_inputs <- digest::digest(list(
  predictors = sort(predictors),
  n_train    = nrow(train_std),
  n_folds    = length(fold_idx),
  fold_sizes = map_int(fold_idx, length),
  glmnet_lambda_min_ratio = GLMNET_LAMBDA_MIN_RATIO,
  stepwise_glm_maxit = STEPWISE_GLM_MAXIT
))

run_or_load <- function(name, fn) {
  path <- file.path(ARTIFACTS, paste0(name, ".rds"))
  if (file.exists(path)) {
    cached <- readRDS(path)
    if (isTRUE(cached$fp == fp_inputs)) return(cached)
    cat(sprintf("  [%s] cache stale - refitting\n", name))
  }
  res <- fn()
  res$fp <- fp_inputs
  saveRDS(res, path)
  res
}
```

**Čo to robí:** Cache wrapper s fingerprint-om založeným na vstupoch.

**Fingerprint zložky:**
- `sort(predictors)` — keby sa zmenili stĺpce
- `n_train`, `n_folds`, `fold_sizes` — keby sa zmenil split
- konstanty hyperparametrov — keby sa zmenila configurácia

**Použité funkcie:**
- `digest::digest(list(...))` — hash celého listu (stabilný cez R verzie).
- `map_int(fold_idx, length)` — typesafe map vracajúci integer vektor.

**Prečo nehesujeme priamo objekty?**  
Stačí nám **hash konfigurácie**. Hashovanie celých dát by bolo pomalé.

---

## Chunk `stepwise-helper`

```r
step_keep <- function(model, AIC) {
  s <- tryCatch(summary(model)$coefficients, error = function(e) NULL)
  if (is.null(s) || nrow(s) == 0) {
    return(list(terms = character(0), p = numeric(0), AIC = AIC))
  }
  list(
    terms = rownames(s),
    p     = unname(s[, "Pr(>|z|)"]),
    AIC   = AIC
  )
}

STEPWISE_GLM_WARNINGS <- c(
  "fitted probabilities numerically 0 or 1",
  "algorithm did not converge"
)

muffle_stepwise_glm_warnings <- function(expr) {
  withCallingHandlers(expr, warning = function(w) {
    msg <- conditionMessage(w)
    if (any(map_lgl(STEPWISE_GLM_WARNINGS, ~ grepl(.x, msg, fixed = TRUE)))) {
      invokeRestart("muffleWarning")
    }
  })
}

fit_stepwise <- function(train_df, features = predictors) {
  null_mod <- muffle_stepwise_glm_warnings(
    glm(label ~ 1, data = train_df, family = binomial,
        control = glm.control(maxit = STEPWISE_GLM_MAXIT))
  )
  full_fm  <- as.formula(paste("label ~", paste(features, collapse = " + ")))
  out <- muffle_stepwise_glm_warnings(MASS::stepAIC(
    null_mod,
    scope     = list(lower = ~ 1, upper = full_fm),
    direction = "both",
    trace     = FALSE,
    keep      = step_keep
  ))
  out
}
```

**Čo to robí:** Definuje pomocné funkcie pre bidirectional stepwise s p-value loggingom.

### `step_keep` callback

`stepAIC` má `keep` argument — funkciu, ktorá pri každom kroku dostane aktuálny model a vráti čokoľvek, čo si chceme uložiť. Tu ukladáme:
- `terms` — názvy aktívnych prediktorov
- `p` — ich p-hodnoty
- `AIC` — aktuálne AIC

To nám neskôr umožňuje spätne **auditovať p-hodnoty na celej AIC ceste**.

**`tryCatch(..., error = function(e) NULL)`** — ak by `summary` zlyhalo (napr. v intercept-only modeli), vrátime NULL a pokračujeme.

**`unname(s[, "Pr(>|z|)"])`** — extrahuje p-value stĺpec a odstráni named atribút.

### `muffle_stepwise_glm_warnings`

Stepwise často generuje warnings (separation, non-convergence) v každom medzikroku. Bez muflingu by terminál vyzeral ako warning-spam.

**Použité funkcie:**
- `withCallingHandlers(expr, warning = ...)` — base R mechanizmus pre handling conditions bez prerušenia execution.
- `invokeRestart("muffleWarning")` — silenuje konkrétny warning a pokračuje.
- `grepl(pattern, msg, fixed = TRUE)` — substring match.
- `map_lgl(STEPWISE_GLM_WARNINGS, ~ grepl(.x, msg, fixed = TRUE))` — kontrola viacerých vzorov.

### `fit_stepwise`

1. Fituje **null model** (`label ~ 1` — len intercept) — to je štartovací bod.
2. Konstruuje **full formula** zo všetkých features cez `as.formula(paste(...))`.
3. Volá `MASS::stepAIC` s:
   - `scope = list(lower = ~ 1, upper = full_fm)` — definuje rozsah search space (od null po full)
   - `direction = "both"` — bidirectional (môže pridávať aj odstraňovať v každom kroku)
   - `trace = FALSE` — neukáže verbose log
   - `keep = step_keep` — náš logging callback

**Prečo `glm.control(maxit = 100)`?**  
Default je 25 iterácií. Pri silnej separácii (logistic regression má perfektnú klasifikáciu) potrebuje viac iterácií, aby konvergoval (alebo aspoň muffled non-convergence warning).

---

## Chunk `lasso-helper`

```r
fit_glmnet <- function(train_df, alpha) {
  X <- model.matrix(label ~ . - 1, data = train_df)
  y <- train_df$label
  cvfit <- cv.glmnet(X, y, family = "binomial", alpha = alpha,
                     type.measure = "deviance", nfolds = 5,
                     lambda.min.ratio = GLMNET_LAMBDA_MIN_RATIO)
  cvfit
}

count_nonzero <- function(cvfit, s = "lambda.1se") {
  beta <- as.numeric(coef(cvfit, s = s))[-1]   # drop intercept
  sum(beta != 0)
}

selected_glmnet_terms <- function(cvfit, term_names, s = "lambda.1se") {
  beta <- as.numeric(coef(cvfit, s = s))[-1]   # drop intercept
  term_names[beta != 0]
}
```

**Čo to robí:** Wrapper na `cv.glmnet` + helpery pre extrakciu vybraných features.

### `model.matrix(label ~ . - 1, data = train_df)`

`glmnet` neprijíma formula API — potrebuje numeric matrix `X`. `model.matrix`:
- `label ~ .` — model so všetkými features
- `- 1` — bez intercept-u (glmnet pridá vlastný)

**Pozn.:** Pre faktorové features `model.matrix` urobí dummy-coding (one-hot). U nás sú všetky binárky už 0/1, takže žiadny rozdiel.

### `cv.glmnet`

- `family = "binomial"` — logistická regresia.
- `alpha` — mixing parameter (1 = lasso, 0 = ridge, 0.5 = elastic-net).
- `type.measure = "deviance"` — CV metrika je log-likelihood deviance (default pre binomial). Alternatíva `"auc"` by mohla dať mierne odlišné λ, ale deviance je štandardnejšia voľba.
- `nfolds = 5` — internal CV foldy. Default 10, ale 5 je rýchlejšie a dostatočne stabilné pri 24k riadkoch.
- `lambda.min.ratio = 1e-3` — širší rozsah skúšaných λ.

### `coef(cvfit, s = "lambda.1se")`

`s = "lambda.1se"` — extrahuje koeficienty **pri jeden-SE-pravidlom λ** (nie pri optimálnom). Toto vracia **sparse matrix** (1 stĺpec). `as.numeric(...)` flattnuje.

`[-1]` — odstráni intercept.

`beta != 0` — boolean vektor non-zero koeficientov = vybrané features.

---

## Chunk `lexical-final-check`

```r
metrics_from_prob <- function(prob_phishing, truth = test_std$label) {
  pred <- factor(if_else(prob_phishing >= 0.5, "Phishing", "Legitimate"),
                 levels = levels(truth))
  tibble(
    test_auc = roc_auc_vec(truth, prob_phishing, event_level = "first"),
    sensitivity = sens_vec(truth, pred, event_level = "first"),
    specificity = spec_vec(truth, pred, event_level = "first"),
    accuracy = accuracy_vec(truth, pred)
  )
}

predict_glm_phishing <- function(fit, test_df) {
  1 - as.numeric(predict(fit, newdata = test_df, type = "response"))
}

predict_glmnet_phishing <- function(cvfit, test_df, s = "lambda.1se") {
  X_test <- model.matrix(label ~ . - 1, data = test_df)
  1 - as.numeric(predict(cvfit, newx = X_test, s = s, type = "response"))
}
```

**Čo to robí:** Helpery pre konvertovanie pravdepodobností na metriky.

### Prečo `1 - predict(...)` ?

V Scenári 3 sme nastavili `levels = c(1, 0)` — **„Phishing" je prvý level, čo `glm`/`glmnet` interpretujú ako referenčnú triedu**. `predict(..., type = "response")` vráti `P(label = "Legitimate")` (druhý level). Preto `1 -` vráti `P(Phishing)`.

Toto je **subtil**, ale dôležitý detail — keby sme vrátili `predict()` priamo, AUC by bolo „naopak" (tj. 1 - AUC).

### `metrics_from_prob`

Konvertuje pravdepodobnosti pri prahu 0.5 na predikované triedy a spočíta 4 metriky.

**Použité funkcie:**
- `if_else(condition, yes, no)` (dplyr) — striktná verzia `ifelse` (zachová typy).
- `factor(..., levels = levels(truth))` — zaručí, že predikčný factor má rovnaké levels ako truth.
- `roc_auc_vec`, `sens_vec`, `spec_vec`, `accuracy_vec` (yardstick) — vektorové metriky.

### Hlavné fitovanie

```r
lexical_final <- run_or_load("lexical_final", function() {
  trn <- train_std %>% select(label, all_of(lexical_predictors))
  sw <- fit_stepwise(trn, lexical_predictors)
  cvl <- fit_glmnet(trn, alpha = 1)
  cve <- fit_glmnet(trn, alpha = 0.5)
  term_names <- colnames(model.matrix(label ~ . - 1, data = trn))
  list(
    stepwise_fit = sw,
    lasso_fit = cvl,
    en_fit = cve,
    sw_terms = setdiff(names(coef(sw)), "(Intercept)"),
    lasso_terms = selected_glmnet_terms(cvl, term_names),
    en_terms = selected_glmnet_terms(cve, term_names),
    X_names = term_names
  )
})
```

**Čo to robí:** Fituje všetky 3 metódy na lexikálnom train sete, vyextrahuje vybrané terms.

**`setdiff(names(coef(sw)), "(Intercept)")`** — `coef(sw)` vráti named numeric vektor s intercept-om; `setdiff` ho odstráni.

### Diagnostická tabuľka

```r
SPARSITY_MAX_K <- 9
MIN_TEST_AUC <- 0.95
MIN_SENSITIVITY <- 0.94
MIN_SPECIFICITY <- 0.75

lexical_diagnostic <- tibble(
  pool = "Lexical URL-only",
  method = c("Stepwise", "Lasso", "Elastic-Net"),
  k = c(length(lexical_final$sw_terms),
        length(lexical_final$lasso_terms), length(lexical_final$en_terms)),
  prob_phishing = list(
    predict_glm_phishing(lexical_final$stepwise_fit, test_lexical),
    predict_glmnet_phishing(lexical_final$lasso_fit, test_lexical),
    predict_glmnet_phishing(lexical_final$en_fit, test_lexical)
  )
) %>%
  mutate(metrics = map(prob_phishing, metrics_from_prob)) %>%
  unnest(metrics) %>%
  dplyr::select(-prob_phishing) %>%
  mutate(
    k_reduction = length(primary_predictors) - k,
    C1_sparsity = k <= SPARSITY_MAX_K,
    C2_auc = test_auc >= MIN_TEST_AUC,
    C3_operating_point = sensitivity >= MIN_SENSITIVITY & specificity >= MIN_SPECIFICITY,
    H2_pass = C1_sparsity & C2_auc & C3_operating_point
  )
```

**Čo to robí:** Pre každú z 3 metód spočíta metriky a kontroluje H2 kritériá.

**Použité funkcie:**
- `tibble(prob_phishing = list(...))` — list-column s tromi vektormi pravdepodobností.
- `map(prob_phishing, metrics_from_prob)` (purrr) — pre každý prob-vektor spočíta metriky → list-column tibble-ov.
- `unnest(metrics)` (tidyr) — rozbalí list-column metrík do stĺpcov.

**Pattern „kritériá ako boolean stĺpce":**  
`C1_sparsity = k <= 9` — TRUE/FALSE per metóda. Konečné `H2_pass = C1 & C2 & C3` (logical AND).

---

## Chunk `d1-table`

```r
all_terms <- sort(unique(c(lexical_final$sw_terms, lexical_final$lasso_terms, lexical_final$en_terms,
                           primary_predictors)))
d1 <- tibble(
  predictor = all_terms,
  stepwise    = if_else(predictor %in% lexical_final$sw_terms,    "x", ""),
  lasso       = if_else(predictor %in% lexical_final$lasso_terms, "x", ""),
  elastic_net = if_else(predictor %in% lexical_final$en_terms,    "x", "")
) %>%
  mutate(score = (stepwise == "x") + (lasso == "x") + (elastic_net == "x")) %>%
  arrange(desc(score), predictor)
```

**Čo to robí:** Vytvorí matrix typu „checklist" — riadky = features, stĺpce = metódy, "x" v bunke = vybrané.

**Trik:** `(stepwise == "x") + (lasso == "x") + (elastic_net == "x")` — logical sa konvertuje na 0/1, súčet udáva, **koľkokrát** bola feature vybraná. Slúži na sortovanie (top = vybraná všetkými).

---

## Chunk `stepwise` (p-value audit)

```r
keep_mat <- lexical_final$stepwise_fit$keep
n_steps <- if (is.matrix(keep_mat)) ncol(keep_mat) else length(keep_mat)

step_path <- map_dfr(seq_len(n_steps), function(i) {
  k_i <- if (is.matrix(keep_mat)) keep_mat[, i] else keep_mat[[i]]
  tibble(step = i,
         predictor = k_i$terms,
         p = k_i$p,
         AIC = k_i$AIC)
}) %>%
  filter(predictor != "(Intercept)")

step_path_summary <- step_path %>%
  group_by(predictor) %>%
  arrange(step, .by_group = TRUE) %>%
  summarise(
    first_step = min(step),
    last_step = max(step),
    min_p = min(p, na.rm = TRUE),
    max_p = max(p, na.rm = TRUE),
    final_p = dplyr::last(p),
    crosses_05 = any(p > 0.05) && any(p < 0.05),
    .groups = "drop"
  ) %>%
  arrange(desc(crosses_05), desc(max_p), predictor)
```

**Čo to robí:** Z `keep`-listu (snapshot pri každom kroku) zostaví **per-prediktor history p-hodnôt**.

**Použité funkcie:**
- `is.matrix(...)` — defenzívna ochrana, lebo `keep` môže byť uložené ako matrix alebo list (závisí od R verzie).
- `map_dfr(seq_len(n_steps), function(i) {...})` — zostaví long-format tibble (riadok = (step, predictor, p)).
- `summarise(crosses_05 = any(p > 0.05) && any(p < 0.05))` — flag, ak p prešlo cez 0.05 v ktoromkoľvek kroku.

**Prečo `dplyr::last(p)` a nie `tail(p, 1)`?**  
`dplyr::last` je explicit-named alternatíva, lepšie čitateľná v rámci dplyr pipeline.

---

## Chunk `d2-embedded-coefs`

```r
coef_at_lambda <- function(cvfit, label, s = "lambda.1se") {
  beta <- as.matrix(coef(cvfit, s = s))[-1, , drop = FALSE]
  tibble(
    predictor = rownames(beta),
    method = label,
    coefficient = as.numeric(beta[, 1]),
    retained = coefficient != 0
  )
}

embedded_coefs <- bind_rows(
  coef_at_lambda(lexical_final$lasso_fit, "lasso"),
  coef_at_lambda(lexical_final$en_fit,    "elastic-net")
)

embedded_coefs %>%
  filter(retained) %>%
  mutate(predictor = reorder(predictor, abs(coefficient))) %>%
  ggplot(aes(coefficient, predictor, fill = method)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ method, scales = "free_y") +
  geom_vline(xintercept = 0, colour = "grey50") +
  labs(...)
```

**Čo to robí:** Bar chart koeficientov pri `lambda.1se` per metóda.

**`drop = FALSE`** — zachová matrix štruktúru aj pri 1 stĺpci (inak by `[, , drop = TRUE]` to flattnulo na vektor).

**`reorder(predictor, abs(coefficient))`** — usporiada faktor podľa absolútnej hodnoty koeficientu (najsilnejšie hore).

**`facet_wrap(~ method, scales = "free_y")`** — dva subgraf-y vedľa seba s nezávislými y-osami.

---

## Chunk `d2-zero-lambda`

```r
active_lambda_table <- function(cvfit, label) {
  beta_path <- as.matrix(coef(cvfit$glmnet.fit))[-1, , drop = FALSE]
  lambdas <- cvfit$glmnet.fit$lambda

  beta_path %>%
    as_tibble(rownames = "predictor") %>%
    rename_with(~ as.character(seq_along(lambdas)), -predictor) %>%
    pivot_longer(-predictor, names_to = "lambda_index", values_to = "coefficient") %>%
    mutate(lambda = lambdas[as.integer(lambda_index)]) %>%
    filter(coefficient != 0) %>%
    summarise(active_lambda = max(lambda), .by = predictor) %>%
    right_join(tibble(predictor = rownames(beta_path)), by = "predictor") %>%
    mutate(method = label) %>%
    select(predictor, active_lambda, method) %>%
    arrange(desc(active_lambda))
}
```

**Čo to robí:** Pre každý prediktor zistí **najväčšiu λ, pri ktorej je koeficient ešte nenulový**.

**Pochopenie logiky:**  
`cvfit$glmnet.fit$lambda` — vektor všetkých skúšaných λ (typicky 100 hodnôt).
`coef(cvfit$glmnet.fit)` — matrix koeficientov, riadky = features, stĺpce = λ hodnoty.

Pre každý feature:
- `coefficient != 0` — indikátor aktivity pri každom λ
- `max(lambda)` v aktívnych pozíciách = **najväčšia λ, pri ktorej feature ešte „prežil"**

**Interpretácia:** Veľká active_lambda = silný signál (prežije aj pod silnou penalizáciou). Malá = slabý signál (klesne pod nulu už pri malom penalty).

**Použité funkcie:**
- `as_tibble(rownames = "predictor")` — z matrix → tibble s rownames v stĺpci.
- `rename_with(~ as.character(seq_along(lambdas)), -predictor)` — premenuje stĺpce na "1", "2", "3", ... `-predictor` znamená „okrem stĺpca predictor".
- `pivot_longer` — z širokého na dlhý formát.
- `summarise(active_lambda = max(lambda), .by = predictor)` — `.by` argument je novší dplyr alternatíva pre `group_by + summarise`.
- `right_join(tibble(predictor = rownames(beta_path)), ...)` — zaručí, že aj features s len-zero koeficientami ostanú v tabuľke (s NA).

---

## Chunk `perfold-fit`

```r
perfold <- run_or_load("perfold", function() {
  fit_fold <- function(rows, k) {
    trn <- train_std %>%
      slice(rows) %>%
      select(label, all_of(predictors))

    sw   <- fit_stepwise(trn, predictors)
    sw_terms <- setdiff(names(coef(sw)), "(Intercept)")

    cvl <- fit_glmnet(trn, alpha = 1)
    lasso_names <- colnames(model.matrix(label ~ . - 1, data = trn))
    lasso_terms <- selected_glmnet_terms(cvl, lasso_names)

    cve <- fit_glmnet(trn, alpha = 0.5)
    en_terms <- selected_glmnet_terms(cve, lasso_names)

    tibble(
      fold = k,
      k_step = length(sw_terms),
      k_lasso = length(lasso_terms),
      k_en = length(en_terms),
      step_terms = list(sw_terms),
      lasso_terms = list(lasso_terms),
      en_terms = list(en_terms)
    )
  }

  fold_results <- map2_dfr(fold_idx, seq_along(fold_idx), fit_fold)
  ...
})
```

**Čo to robí:** Pre každý z 10 fold-ov fituje 3 metódy na FullLite a uloží **počet** + **zoznam vybraných features**.

**`map2_dfr(fold_idx, seq_along(fold_idx), fit_fold)`** (purrr) — `map2` cez dva paralelné argumenty (rows + fold-id), spojí cez `bind_rows`.

**`step_terms = list(sw_terms)`** — list-column trick na uloženie vektora variabilnej dĺžky v tibble bunke.

**`flush.console()`** — v tradičných run-och pri neinteraktívnom mode by sa `cat`-výstup neflusol pred koncom; toto vynúti okamžité zobrazenie.

---

## Chunk `fulllite-mean`

```r
mean_step  <- mean(perfold$k_step)
mean_lasso <- mean(perfold$k_lasso)
mean_en    <- mean(perfold$k_en)

tibble(
  metric = c("mean k (stepwise)", "mean k (lasso)", "mean k (elastic-net)"),
  value  = c(sprintf("%.1f", mean_step),
             sprintf("%.1f", mean_lasso),
             sprintf("%.1f", mean_en))
) %>% kable(...)
```

**Čo to robí:** Spočíta priemerný počet vybraných features per metóda cez 10 fold-ov.

---

## Chunk `fulllite-perfold-plot`

```r
perfold_long <- tibble(
  fold = seq_along(fold_idx),
  stepwise = perfold$k_step,
  lasso = perfold$k_lasso,
  `elastic-net` = perfold$k_en
) %>%
  pivot_longer(-fold, names_to = "method", values_to = "k") %>%
  mutate(method = factor(method, levels = c("stepwise", "elastic-net", "lasso")))

ggplot(perfold_long, aes(method, k, fill = method)) +
  geom_boxplot(alpha = 0.6, outlier.shape = NA) +
  geom_point(position = position_jitter(width = 0.1, seed = 1), size = 1.4) +
  geom_hline(yintercept = length(predictors), linetype = "dashed", colour = "grey40") +
  ...
```

**Čo to robí:** Box + jitter plot per-fold počtov pre 3 metódy.

**`position_jitter(seed = 1)`** — deterministický jitter (ten istý layout pri každom knit-e).

**`geom_hline(yintercept = length(predictors), linetype = "dashed")`** — referenčná čiara pri „celom pool-e" (34).

**`outlier.shape = NA`** — schová boxplot outliers (lebo body sú ukázané cez `geom_point` jitter).

---

## Chunk `fulllite-selection-frequency`

```r
n_folds <- length(fold_idx)

count_in_folds <- function(term_lists, term) {
  sum(map_lgl(term_lists, ~ term %in% .x))
}

all_fulllite_terms <- sort(unique(c(
  flatten_chr(perfold$step_terms),
  flatten_chr(perfold$lasso_terms),
  flatten_chr(perfold$en_terms),
  predictors
)))

d1_full <- tibble(
  predictor   = all_fulllite_terms,
  stepwise    = map_int(predictor, ~ count_in_folds(perfold$step_terms, .x)),
  lasso       = map_int(predictor, ~ count_in_folds(perfold$lasso_terms, .x)),
  elastic_net = map_int(predictor, ~ count_in_folds(perfold$en_terms, .x))
) %>%
  mutate(score = stepwise + lasso + elastic_net) %>%
  arrange(desc(score), predictor) %>%
  dplyr::select(-score)
```

**Čo to robí:** Pre každý FullLite prediktor spočíta, **v koľkých fold-och ho každá metóda zachovala**.

**Použité funkcie:**
- `flatten_chr` (purrr) — flattnuje list character vektorov do single character vektora. Alternatíva `unlist(...)` (base R) — funguje, ale nie je type-safe.
- `count_in_folds` — pre daný term spočíta, v koľkých listoch sa nachádza.
- `map_int` — pre každý prediktor spustí count → integer vektor.

**Interpretácia:**
- Stĺpec hodnotou 10 = vždy vybraný (robust core)
- Hodnota 0 = nikdy nevybraný
- Medzihodnoty = nestabilný výber

**Sortovanie podľa `score = sum`** — robust core (10+10+10 = 30) hore, never-selected (0+0+0 = 0) dole.
