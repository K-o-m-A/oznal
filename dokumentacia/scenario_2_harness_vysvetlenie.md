# Scenár 2 — vysvetlenie tréningovej infraštruktúry

Tento dokument vysvetľuje skupinu pomocných funkcií, ktoré tvoria **harness** Scenára 2 — t.j. infraštruktúru, ktorá zoberie model a tier features, natrénuje to v rovnakom režime ako všetky ostatné modely, vyhodnotí na hold-out teste, zacachuje výsledok a vypíše súhrn. Cieľom harnessu je, aby porovnanie šiestich modelov × štyroch tierov bolo úplne deterministické a férové.

---

## 1. `fit_one_tier()` — fit jedného modelu na jeden tier

```r
fit_one_tier <- function(tier_features, data_train, data_test, method,
                         tuneGrid = NULL, ...)
```

Funkcia, ktorá robí celý cyklus pre **jeden model na jednom tieri**: vyfiltruje features, natrénuje model cez `caret`, predikuje na trénoch aj teste a vráti zoznam metrík.

### 1.1 Vstupy

- `tier_features` — vektor mien stĺpcov, ktoré model uvidí (napr. 13 Lexical features).
- `data_train`, `data_test` — pred-rozdelený 80/20 split. Obsahujú stĺpec `label` (factor: `Phishing`/`Legitimate`) a všetky možné features.
- `method` — `caret` method-string: `"glmnet"`, `"lda"`, `"naive_bayes"`, `"rf"`, `"svmRadial"`, `"knn"`.
- `tuneGrid` — voliteľný `data.frame` s fixnými hyperparametrami (napr. `expand.grid(alpha = 0, lambda = 0.01)` pre LR-Ridge). Ak je `NULL`, `caret` použije svoj default grid alebo defaults metódy.
- `...` — ďalšie argumenty propagované do `caret::train` (napr. `preProcess = c("YeoJohnson", "center", "scale")`).

### 1.2 Príprava tréningového a testovacieho data framu

```r
tr <- data_train %>% select(label, all_of(tier_features))
te <- data_test  %>% select(label, all_of(tier_features))
```

Selekcia stĺpcov garantuje, že model uvidí **iba features daného tieru** — žiadne náhodné leakery z iných tierov. `all_of()` zlyhá, ak sa niektorá feature nenájde, čo je tu žiadúce: lepšie crash než tichý drop.

### 1.3 `trainControl` — režim cross-validation

```r
ctrl <- trainControl(
  method          = "cv",
  index           = fold_idx,
  classProbs      = TRUE,
  summaryFunction = twoClassSummary,
  savePredictions = "final"
)
```

Toto je **kľúčový bod férovosti**. Rozoberme jednotlivé argumenty:

- **`method = "cv"`** — k-fold cross-validation, nie repeated CV ani bootstrap. Dôvod: nechceme zvyšovať výpočtovú cenu a deterministicky chceme jeden priemer per fold.
- **`index = fold_idx`** — globálna premenná z R-kového skriptu, kde `fold_idx` je list 10 vektorov tréningových indexov vytvorený stratifikovaným `createFolds()` vopred. **Všetkých 6 modelov dostane TIE ISTÉ fold indexy**, takže rozdiely v metrikách sú párované fold-by-fold a nie zaťažené iným rozdelením dát. Bez tohto by bolo porovnanie LR vs LDA vs RF nedôveryhodné.
- **`classProbs = TRUE`** — okrem hard predikcie zachová aj `P(Phishing)` a `P(Legitimate)`. Potrebujeme ich na výpočet AUC.
- **`summaryFunction = twoClassSummary`** — `caret` v každom fold-e počíta `ROC`, `Sens`, `Spec`. Bez tohto by hlásilo iba accuracy.
- **`savePredictions = "final"`** — zachová predikcie z best-tune modelu cez všetky foldy. Užitočné pre post-hoc analýzu (napr. distribúcia skóre, kalibračné krivky).

### 1.4 Tréning a meranie času

```r
t0 <- Sys.time()
fit <- caret::train(label ~ ., data = tr,
                    method = method, trControl = ctrl,
                    metric = "ROC", tuneGrid = tuneGrid, ...)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
```

- `label ~ .` — formula syntax, target je `label`, prediktory sú všetky ostatné stĺpce v `tr` (čiže features daného tieru).
- `metric = "ROC"` — vyberie best-tune model podľa AUC, nie accuracy. Pri vyvážených triedach to nie je rozhodujúce, ale je to konzistentné s tým, že AUC nás zaujíma viac.
- `Sys.time()` ohraničenie meria **wall-clock čas** tréningu. Reportuje sa v `train_secs` a slúži ako fairness check: SVM-RBF a RF musia byť výrazne pomalšie než LR a LDA, inak je niečo zle.

### 1.5 Predikcia na testovacom sete

```r
test_prob <- predict(fit, te, type = "prob") %>%
  as_tibble() %>%
  pull(Phishing)
test_pred <- predict(fit, te)
test_auc  <- roc_auc_vec(te$label, test_prob, event_level = "first")
cm <- caret::confusionMatrix(test_pred, te$label, positive = "Phishing")
```

Dva paralelné výpočty:

1. **Soft predikcia** — `type = "prob"` vráti data frame so stĺpcami `Phishing` a `Legitimate`. Ťaháme `Phishing` (pravdepodobnosť pozitívnej triedy). Z toho `roc_auc_vec()` z `yardstick` spočíta AUC. `event_level = "first"` znamená, že prvá úroveň factoru je positive — preto musí byť factor `label` urobený s `levels = c("Phishing", "Legitimate")`, inak by AUC bola obrátená.
2. **Hard predikcia** — bez `type` vráti factor predikcií pri prahu 0.5. Z toho `caret::confusionMatrix()` s `positive = "Phishing"` vyrobí confusion matrix a spočíta Sens, Spec, Precision, F1, Accuracy.

### 1.6 Predikcia na tréningovom sete

```r
train_prob <- predict(fit, tr, type = "prob") %>% ...
train_auc  <- roc_auc_vec(tr$label, train_prob, ...)
train_cm   <- caret::confusionMatrix(train_pred, tr$label, ...)
```

Identický výpočet, ale na tréningových dátach. Slúži na **detekciu overfittingu**: ak `train_auc` je 1.0 a `test_auc` je 0.85, model overfittuje. Gap (`train_auc − test_auc`) sa neskôr reportuje v summary tabuľke.

Pozor: tréning AUC je **optimisticky biased**, pretože model dáta videl pri tréningu. Hodnota sama o sebe nič nehovorí; zaujíma nás **rozdiel** voči test AUC.

### 1.7 Výstup

```r
list(cv_per_fold = fit$resample,
     train_auc, train_acc, test_auc, test_acc,
     test_f1, test_prec, test_sens, test_spec,
     train_secs)
```

Plain list (nie S3 trieda). Konkrétne polia:

- **`cv_per_fold`** — `fit$resample` je data frame s 10 riadkami (jeden per fold) a stĺpcami `ROC`, `Sens`, `Spec`, `Resample`. Toto je hlavný zdroj fold-by-fold variability. Z neho sa neskôr počíta `mean ± sd` pre CV ROC v summary tabuľke.
- **`train_auc`, `train_acc`** — tréningové metriky pre overfit gap.
- **`test_auc`, `test_acc`, `test_f1`, `test_prec`, `test_sens`, `test_spec`** — hold-out metriky pri prahu 0.5. Hlavné metriky pre H1 sú `test_sens` a `test_spec`, z nich sa odvodí `minSS = min(sens, spec)`.
- **`train_secs`** — reálny čas tréningu (sec). Pre fairness check.

`unname()` je tam preto, že `caret::confusionMatrix$byClass` vracia named numeric vector, a my chceme čisté skaláre.

---

## 2. `tiers_fingerprint()` — odtlačok tier konfigurácie

```r
tiers_fingerprint <- function(x)
  x[sort(names(x))] %>%
    map(sort) %>%
    digest::digest()
```

Funkcia, ktorá pre daný `tiers` list (napr. `list(Lexical = c("URLLength", ...), Trust = c(...))`) vyrobí **deterministický hash**, podľa ktorého vieme rozhodnúť, či je nakešovaný výsledok stále platný.

### 2.1 Prečo dva `sort()`

```r
x[sort(names(x))]   # sort kľúčov (názvov tierov)
%>% map(sort)       # sort hodnôt (názvov features v každom tieri)
```

`tiers` je named list. Hash by mal byť **invariantný voči poradiu**:

- Keby sme tiery v zozname preusporiadali (`Lexical, Trust, …` vs `Trust, Lexical, …`), výsledok je sémanticky rovnaký a hash má byť rovnaký.
- Keby sme features v rámci jedného tieru preusporiadali, model sa správa rovnako (poradie features `caret`-u nevadí), takže hash má byť tiež rovnaký.

`sort()` cez kľúče aj cez hodnoty zabezpečí kanonickú formu pred hashovaním.

### 2.2 `digest::digest()`

`digest` knižnica vyrobí MD5 hash zo serializovanej R štruktúry. Výsledok je krátky string, napríklad `"a3f8b2c1d4e5..."`. V cache porovnávame iba tento string.

### 2.3 Načo to slúži

Cache (viď nasledujúca sekcia) si pri uložení zapamätá fingerprint **vstupných tierov**. Pri ďalšom spustení sa fingerprint prepočíta a porovná. Ak niekto medzitým upravil definíciu tiera (napr. pridal feature do Lexical alebo zmenil mená), fingerprint sa zmení a cache je invalidovaný — nakešovaný výsledok by nezodpovedal aktuálnemu kódu.

---

## 3. `fit_tiers()` — fit jedného modelu cez všetky tiery

```r
fit_tiers <- function(model, family, fitter) {
  list(
    model = model,
    family = family,
    by_tier = imap(tiers, fitter)
  )
}
```

Wrapper, ktorý zoberie model a aplikuje **rovnakú fit funkciu** na všetky tiery v globálnom `tiers` liste.

### 3.1 Argumenty

- **`model`** — display name, napr. `"LR-Ridge"`, `"SVM-RBF"`. Slúži iba na účely výpisu.
- **`family`** — `"parametric"` alebo `"non-parametric"`. Slúži na neskoršie filtrovanie pri H1 vyhodnotení (porovnávame najlepšieho z parametrickej rodiny vs najlepšieho z neparametrickej).
- **`fitter`** — closure, ktorá zachytáva model-špecifické nastavenie. Príklad:

  ```r
  lr_fitter <- function(features, tier_name) {
    fit_one_tier(features, train_df, test_df,
                 method = "glmnet",
                 tuneGrid = expand.grid(alpha = 0, lambda = 0.01),
                 preProcess = c("YeoJohnson", "center", "scale"))
  }
  ```

### 3.2 `imap(tiers, fitter)`

`imap` je z `purrr` a iteruje cez `(value, name)` páry namiesto iba `value`. Ekvivalentne:

```r
purrr::map2(tiers, names(tiers), fitter)
```

Pre každý tier zavolá `fitter(features, tier_name)`. Výsledok je named list, kde kľúče sú mená tierov a hodnoty sú fit-results z `fit_one_tier`.

### 3.3 Štruktúra výstupu

```r
list(
  model = "LR-Ridge",
  family = "parametric",
  by_tier = list(
    Lexical  = <fit_one_tier output>,
    Trust    = <fit_one_tier output>,
    Behavior = <fit_one_tier output>,
    FullLite = <fit_one_tier output>
  )
)
```

Tento `res` objekt je to, čo sa cacheuje na disk a neskôr používa na vyhodnotenie a tlač.

---

## 4. `run_or_load()` — kešovacia vrstva

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
    cat(sprintf("  [%s] cache stale (tiers_ok=%s, schema_ok=%s, fp_ok=%s) - refitting\n",
                name, tiers_ok, schema_ok, fp_ok))
  }
  res <- fn()
  res$tiers_fp <- fp
  saveRDS(res, path)
  res
}
```

Ochrana pred opakovaným tréningom drahých modelov (najmä SVM-RBF, ktoré trvajú minúty na fold).

### 4.1 Cesta a fingerprint

```r
path <- file.path(ARTIFACTS, paste0("res_", name, ".rds"))
fp   <- tiers_fingerprint(tiers)
```

`ARTIFACTS` je globálna konštanta s priečinkom (napr. `scenario_2/artifacts`). `name` je krátky identifikátor modelu, napr. `"lr"`, `"svm"`. Výsledná cesta: `scenario_2/artifacts/res_svm.rds`.

`fp` je aktuálny fingerprint vstupnej tier konfigurácie.

### 4.2 Tri kontroly platnosti cache

```r
tiers_ok   <- setequal(names(cached$by_tier), names(tiers))
schema_ok  <- all(c("train_auc", "train_acc", "test_prec") %in%
                  names(cached$by_tier[[1]]))
fp_ok      <- isTRUE(cached$tiers_fp == fp)
```

Cache sa použije **iba ak prejdú všetky tri**:

1. **`tiers_ok`** — zoznam tierov vo cache je rovnaký ako aktuálny. Ak niekto pridal nový tier, cache je nepoužiteľný (chýba mu nový tier).
2. **`schema_ok`** — payload obsahuje očakávané kľúče (`train_auc`, `train_acc`, `test_prec`). Ak sa medzitým rozšírilo `fit_one_tier` o nové výstupné polia, starý cache by neobsahoval nové kľúče a downstream kód by spadol. Tu si vyberáme niekoľko reprezentatívnych kľúčov ako proxy schema kontrolu — necheckujeme všetkých 10 polí, ale aspoň tie, ktoré pribudli najneskôr.
3. **`fp_ok`** — fingerprint vstupných tierov sa zhoduje. Ak niekto upravil definíciu Lexical (napr. pridal feature), fingerprint sa zmení a cache sa invaliduje.

`isTRUE()` chráni pred situáciou, kedy `cached$tiers_fp` neexistuje (`NULL == fp` vráti `logical(0)`, čo nie je TRUE ani FALSE).

### 4.3 Fallback — refit

Ak ktorákoľvek kontrola zlyhá, vypíše sa diagnostická hláška, ktorá hovorí **ktorá** kontrola padla. Potom sa pustí `fn()` (čo je v praxi closure okolo `fit_tiers(...)`), výsledok sa doplní o aktuálny fingerprint a uloží sa.

```r
res <- fn()
res$tiers_fp <- fp
saveRDS(res, path)
res
```

`fn()` je no-arg closure preto, aby drahá operácia (tréning) prebehla **iba ak naozaj treba**. Keby sme namiesto toho prijímali už hotový výsledok, fitting by sa robil aj v prípade hit-u.

### 4.4 Praktický dôsledok

Na čistom stroji (cache ešte neexistuje) sa všetkých 6 modelov natrénuje. Pri ďalšom kompile dokumentu (`Knit`) sa tréning preskočí a načíta sa z disku — to môže rozdiel medzi 30 minútami a 5 sekundami pre SVM-RBF. Pri editácii kódu (napr. zmena `tuneGrid`) treba cache manuálne zmazať alebo zmeniť `name`, lebo tieto zmeny harness sám nedetekuje (kontroluje sa iba `tiers` fingerprint).

---

## 5. `print_tier_summary()` — formátovanie výstupu

```r
print_tier_summary <- function(res) {
  tbl <- imap_dfr(res$by_tier, function(r, tier) {
    gap <- r$train_auc - r$test_auc
    tibble(...)
  })
  kable(tbl, ...)
}
```

Funkcia, ktorá z `res$by_tier` (named list 4 tierov × 10 metrík) vyrobí jednu pekne formátovanú tabuľku s riadkom per tier.

### 5.1 `imap_dfr`

Iteruje cez tiery a každú iteráciu zlepí do jedného data framu (`_dfr` = "data frame, row-bound"). V každej iterácii vyrobí jednoriadkový tibble s formátovanými hodnotami.

### 5.2 Stĺpce a ich význam

- **`Tier`** — Lexical/Trust/Behavior/FullLite.
- **`Train AUC`** — AUC na tréningu, optimisticky biased.
- **`CV ROC`** — `mean(fit$resample$ROC) ± sd(...)`. Hlavný odhad „ako bude model fungovať na nevidených dátach“. SD je tu kľúčové — ukazuje, ako stabilné sú výsledky cez foldy.
- **`Test AUC`** — AUC na hold-out 20% sete.
- **`Gap`** — `train_auc − test_auc`. Veľký kladný gap = overfitting.
- **`Accuracy`, `F1`, `Prec`, `Sens`, `Spec`** — všetko pri prahu 0.5 na hold-out sete.
- **`Train (s)`** — wall-clock čas tréningu.

### 5.3 `sprintf` formátovania

- `%.4f` — 4 desatinné miesta. Pri AUC ~0.95+ je 4 miest nutných na rozlíšenie modelov.
- `%+.4f` — vynúti znamienko (`+0.0123` alebo `−0.0045`). Pri Gap je to čitateľnosť: pozitívny gap = overfit, negatívny = underfit (zriedkavé).
- `%.4f +/- %.4f` — vlastný formát pre CV ROC, lebo `kable` natívne nepodporuje "mean±sd" v jednom stĺpci.

### 5.4 `kable(..., align = "lrrrrrrrrrr")`

Markdown tabuľka. `align`:

- `l` pre prvý stĺpec (Tier — text, ľavo).
- `r` pre 10 nasledujúcich stĺpcov (čísla, pravo). To je 1 + 10 = 11 znakov, čo zodpovedá 11 stĺpcom v tibble.

`caption` je dynamický string `"<model> - <family>"`, takže každá tabuľka má v nadpise napríklad „LR-Ridge - parametric“.

---

## 6. Ako celý harness ide do seba

Typické použitie v hlavnom skripte:

```r
# 1. Setup (raz)
ARTIFACTS <- "scenario_2/artifacts"
tiers <- list(Lexical = ..., Trust = ..., Behavior = ..., FullLite = ...)
fold_idx <- caret::createFolds(train_df$label, k = 10,
                               returnTrain = TRUE)

# 2. Per-model fitter
lr_fitter <- function(features, tier_name) { fit_one_tier(...) }

# 3. Run with caching
res_lr <- run_or_load("lr",
                      function() fit_tiers("LR-Ridge", "parametric", lr_fitter))

# 4. Print
print_tier_summary(res_lr)
```

### Tok dát

1. `run_or_load("lr", ...)` skontroluje cache. Ak je platná, vráti uložený `res`.
2. Ak nie, zavolá `fit_tiers("LR-Ridge", "parametric", lr_fitter)`.
3. `fit_tiers` pre každý tier zavolá `lr_fitter(features, tier_name)`.
4. `lr_fitter` zavolá `fit_one_tier` s konkrétnymi `method`, `tuneGrid`, `preProcess`.
5. `fit_one_tier` urobí CV tréning, predikcie, metriky a vráti list.
6. Výsledný `res` má `model`, `family`, `by_tier` (4 entry) a `tiers_fp`.
7. Uloží sa do `res_lr.rds`.
8. `print_tier_summary(res_lr)` vyrobí Markdown tabuľku.

Pre 6 modelov sa 1.–7. opakuje, ale 7-zľava cache zachytí už natrénované modely a preskočí.

### Prečo tento dizajn

- **Reproducibilita** — fixné `fold_idx`, fixné `tuneGrid`, fixné seed-y → rovnaké čísla pri každom behu.
- **Férovosť** — všetky modely zdieľajú fold indexy, rovnakú `fit_one_tier` infraštruktúru, rovnaký set metrík.
- **Rýchlosť kompilácie** — cache zabráni re-fittingu, čo je pri SVM-RBF kritické (minúty per fold).
- **Detekcia driftu** — fingerprint a schema check varujú, ak sa medzitým niečo zmenilo a cache už nezodpovedá kódu.
- **Modulárnosť** — pridanie nového modelu (napr. XGBoost) je `xgb_fitter <- function(...) fit_one_tier(...)` plus jeden `run_or_load` riadok. Zvyšok harnessu sa nemení.
