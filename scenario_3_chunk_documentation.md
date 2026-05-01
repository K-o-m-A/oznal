# Scenario 3 chunk-by-chunk dokumentácia

Tento dokument vysvetľuje všetky code chunky zo `scenario_3.rmd` rovnakým štýlom ako dokumentácia k `eda.rmd` a `scenario_2.rmd`. Texty v samotnom notebooku sa nemenili; dokumentácia iba opisuje, čo robí kód, prečo tam je a z akých balíkov pochádzajú použité funkcie.

## Konvencia

Každý chunk-doc obsahuje:
- **Účel** - stručne, čo chunk robí a prečo je potrebný.
- **Vysvetlenie kódu** - krok po kroku, ako kód pracuje.
- **Použité funkcie** - tabuľka funkcia -> balík -> účel.

## Konvencie tidyverse/tidymodels refaktoru

Notebook používa tidyverse dialekt tam, kde ide o manipuláciu s dátami, zoznamami, tabuľkami, metrikami a opakovaným skladaním výsledkov. Modelové enginy (`caret`, `glmnet`, `MASS`) ostávajú, pretože tvoria jadro experimentu: scenár porovnáva stepwise logistickú regresiu, lasso a elastic-net, takže ich nahradenie obyčajným `dplyr` kódom by zmenilo zadanie.

| Pôvodne | Nová verzia | Dôvod |
|---------|-------------|-------|
| `pROC::roc()$auc` | `yardstick::roc_auc_vec()` | tidymodels metrika, konzistentná s tidy ekosystémom |
| `knitr::kable()` / `kable()` | `library(knitr)` + `kable()` | krajší HTML výpis a kratší zápis pri opakovanom použití |
| `sapply()` / `lapply()` / `vapply()` | `select(where(...))`, `map_int()`, `map_lgl()` | tidyverse/purrr idiomatika |
| base data-frame subsetting pri dátach | `slice()`, `select(all_of(...))`, `mutate(across(...))` | čitateľnejší a bezpečnejší tidyselect zápis |
| ručný `for` loop cez CV foldy | `map2_dfr()` | fold výsledky sa skladajú priamo do tibble |

---

## Chunk: `libraries`

### Účel
Načíta balíky potrebné pre scenár 3, nastaví reprodukovateľný seed a vytvorí adresár pre cache/artifacts.

### Vysvetlenie kódu
- `library(tidyverse)` zapne základný tidyverse stack: `dplyr`, `tidyr`, `purrr`, `readr`, `tibble`, `stringr` a `ggplot2`.
- `caret` sa používa na stratifikovaný split, foldy a preprocessing cez `preProcess()`.
- `glmnet` poskytuje lasso a elastic-net logistickú regresiu s penalizáciou.
- `MASS` poskytuje `stepAIC()` pre bidirectional stepwise výber premenných; `exclude = "select"` zabraňuje konfliktu s `dplyr::select()`.
- `yardstick` poskytuje AUC, senzitivitu, špecificitu a accuracy v tidymodels štýle.
- `knitr` poskytuje `kable()` pre čitateľné HTML tabuľky.
- `digest` vytvára fingerprint pre cache, aby sa staré `.rds` výsledky nepoužili pri zmene vstupov.
- `set.seed(2026)` stabilizuje sampling a náhodné modelové kroky.
- `ARTIFACTS` drží cestu k cache adresáru a `dir.create()` ho vytvorí, ak ešte neexistuje.
- `GLMNET_LAMBDA_MIN_RATIO <- 1e-3` nastavuje spodný koniec penalizačnej cesty tak, aby `glmnet` nešiel do takmer nepenalizovaných lambd, ktoré na near-separable dátach spôsobujú konvergenčné warningy a nie sú potrebné pre `lambda.1se`.
- `STEPWISE_GLM_MAXIT <- 100L` zvyšuje počet IRLS iterácií pre nepenalizované stepwise GLM kandidáty oproti defaultu, aby sa znížil počet numerických konvergenčných diagnostík.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `library()` | base R | načítanie balíkov |
| `set.seed()` | base R | reprodukovateľnosť náhodných krokov |
| `dir.create()` | base R | vytvorenie adresára pre cache |

---

## Chunk: `load-data`

### Účel
Nájde CSV dataset v aktuálnom adresári alebo o úroveň vyššie, načíta ho a odstráni prípadný UTF-8 BOM z názvov stĺpcov.

### Vysvetlenie kódu
- `dataset_path` sa nastaví cez `if / else if / else`: najprv sa skúša lokálny CSV, potom rodičovský adresár.
- Ak súbor neexistuje ani na jednom mieste, `stop()` ukončí beh s jasnou chybou.
- `read_csv(..., show_col_types = FALSE)` načíta dataset bez vypisovania typov stĺpcov.
- `rename_with(~ str_remove(.x, "^\\ufeff"))` aplikuje čistenie na všetky názvy stĺpcov a odstráni BOM iba tam, kde sa nachádza.
- `cat()` vypíše rýchly sanity check s počtom riadkov a stĺpcov.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `file.exists()` | base R | kontrola existencie súboru |
| `stop()` | base R | explicitná chyba pri chýbajúcom datasete |
| `read_csv()` | `readr` | načítanie CSV do tibble |
| `%>%` | `magrittr`/tidyverse | pipe operátor |
| `rename_with()` | `dplyr` | úprava názvov stĺpcov funkciou |
| `str_remove()` | `stringr` | odstránenie BOM regexom |
| `cat()`, `nrow()`, `ncol()` | base R | konzolový výpis rozmerov |

---

## Chunk: `exclusions`

### Účel
Použije rovnaké EDA/Scenario 2 vylúčenia, aby scenár 3 pracoval s rovnakým očisteným prediktorovým priestorom.

### Vysvetlenie kódu
- `ID_COLS`, `SCORES`, `REDUNDANT_BINARY`, `RATIOS` a `LEAKY_BEHAVIOR` definujú skupiny stĺpcov, ktoré sa nemajú použiť ako prediktory.
- `EXCLUDE_COLS` tieto skupiny spojí do jedného vektora.
- `mutate(label = factor(...))` prevedie pôvodnú binárnu label premennú na faktor s poradím `Phishing`, `Legitimate`. Toto poradie je dôležité pre `yardstick` event-level aj pre modelové výstupy.
- `select(-all_of(EXCLUDE_COLS))` odstráni identifikátory, skóre, redundantnú binárnu premennú, pomery a near-leaky behavior count premenné.
- `as.data.frame()` ponecháva dátový objekt kompatibilný s modelovacími funkciami, ktoré historicky očakávajú data frame.
- `cat()` vypíše počet prediktorov po očistení.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | definícia vektorov názvov stĺpcov |
| `mutate()` | `dplyr` | transformácia label pre modelovanie |
| `factor()` | base R | explicitné poradie tried |
| `select()` | `dplyr` | odstránenie vylúčených stĺpcov |
| `all_of()` | `tidyselect` | striktný výber podľa mien |
| `as.data.frame()` | base R | kompatibilný data-frame objekt |
| `cat()`, `ncol()` | base R | sanity výpis |

---

## Chunk: `subsample-split`

### Účel
Vytvorí vyvážený 30k subsample, rozdelí ho na stratifikovaný 80/20 train/test split a pripraví 10 train foldov pre FullLite diagnostiku.

### Vysvetlenie kódu
- `N_SUB <- 30000` nastaví cieľový počet riadkov.
- `group_by(label)` rozdelí dáta podľa triedy.
- `slice_sample(n = N_SUB / 2)` vezme rovnaký počet riadkov z každej triedy.
- `ungroup()` odstráni grouping, aby ďalšie operácie neboli nechtiac per-class.
- `createDataPartition(..., p = 0.8)` vytvorí stratifikované indexy pre train set; `as.vector()` zjednoduší maticový výsledok.
- `slice(idx)` a `slice(-idx)` vytvoria tréningovú a testovaciu časť tidyverse zápisom.
- `createFolds(..., k = 10, returnTrain = TRUE)` vytvorí fold indexy používané vo FullLite per-fold benchmarku.
- `cat()` vypíše veľkosti splitu a počet foldov.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `group_by()` | `dplyr` | stratifikácia podľa label |
| `slice_sample()` | `dplyr` | náhodný výber v rámci tried |
| `ungroup()` | `dplyr` | zrušenie groupingu |
| `as.data.frame()` | base R | kompatibilita s modelovacími funkciami |
| `createDataPartition()` | `caret` | stratifikovaný train/test split |
| `as.vector()` | base R | zjednodušenie indexov |
| `slice()` | `dplyr` | výber riadkov podľa indexov |
| `createFolds()` | `caret` | vytvorenie CV fold indexov |
| `cat()`, `nrow()`, `length()` | base R | sanity výpis |

---

## Chunk: `recipes`

### Účel
Rozdelí prediktory na binárne a kontinuálne, aplikuje `log1p` na kontinuálne premenné a potom ich centruje/škáluje.

### Vysvetlenie kódu
- `feat <- df_sub %>% select(-label)` vytvorí feature-only tabuľku.
- `select(where(~ all(na.omit(.x) %in% c(0, 1))))` identifikuje binárne premenné. `na.omit()` zachováva pôvodnú logiku, kde prípadné `NA` nemajú rozhodovať o binárnosti stĺpca.
- `continuous_features` sú všetky zvyšné prediktory.
- `apply_log()` používa `mutate(across(...))`, aby na všetky kontinuálne stĺpce aplikoval `log1p(pmax(x, 0))`.
- `preProcess(..., method = c("center", "scale"))` odhadne centrovanie a škálovanie iba na train dátach a iba na kontinuálnych premenných.
- `replace_continuous()` vyberie kontinuálne stĺpce, aplikuje na ne `predict(pp, .)` a výsledné štandardizované hodnoty vloží späť cez `mutate(across(..., cur_column()))`.
- `predictors` je celý FullLite pool po preprocessingu bez `label`.
- `lexical_predictors` definuje URL-only prediktorový pool a `intersect()` ho zarovná s aktuálne dostupnými stĺpcami.
- `cat()` vypíše veľkosť FullLite aj Lexical poolu.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `select()` | `dplyr` | výber/odstránenie stĺpcov |
| `where()` | `tidyselect` | výber stĺpcov podľa predikátu |
| `na.omit()` | stats/base R | ignorovanie NA pri binárnej kontrole |
| `names()` | base R | získanie názvov stĺpcov |
| `setdiff()`, `intersect()` | base R | množinové operácie nad prediktormi |
| `mutate()` | `dplyr` | transformácia stĺpcov |
| `across()` | `dplyr` | aplikácia funkcie na viac stĺpcov |
| `all_of()` | `tidyselect` | výber podľa vektora názvov |
| `log1p()`, `pmax()` | base R | robustná log transformácia nezáporných hodnôt |
| `preProcess()` | `caret` | odhad centrovania a škálovania |
| `predict()` | stats/base R + `caret` metóda | aplikácia preprocessing objektu |
| `cur_column()` | `dplyr` | názov aktuálne spracovaného stĺpca |
| `cat()`, `length()` | base R | sanity výpis |

---

## Chunk: `cache-helper`

### Účel
Vytvorí fingerprint vstupov a helper, ktorý drahé modelové výpočty buď načíta z `.rds`, alebo ich prepočíta a uloží.

### Vysvetlenie kódu
- `digest::digest(list(...))` vytvorí hash z prediktorov, veľkosti train setu a fold štruktúry.
- `map_int(fold_idx, length)` zapíše veľkosť každého foldu purrr štýlom.
- `glmnet_lambda_min_ratio` je súčasť fingerprintu, takže sa cache prepočíta, ak sa zmení nastavenie penalizačnej cesty.
- `stepwise_glm_maxit` je tiež súčasť fingerprintu, aby sa per-fold stepwise cache prepočítala pri zmene GLM control nastavenia.
- `run_or_load(name, fn)` skladá cestu k `.rds` súboru.
- Ak cache existuje, `readRDS()` ju načíta a porovná uložený fingerprint s aktuálnym.
- Ak fingerprint sedí, funkcia vráti cache bez refitu.
- Ak cache chýba alebo je stale, zavolá sa `fn()`, výsledok dostane `fp`, uloží sa cez `saveRDS()` a vráti sa.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `digest()` | `digest` | fingerprint vstupov |
| `list()` | base R | zoskupenie cache vstupov |
| `sort()`, `nrow()`, `length()` | base R | hodnoty pre fingerprint |
| `map_int()` | `purrr` | veľkosti foldov |
| `file.path()` | base R | bezpečné skladanie cesty |
| `file.exists()` | base R | kontrola existencie cache |
| `readRDS()`, `saveRDS()` | base R | načítanie/uloženie R objektu |
| `isTRUE()` | base R | bezpečné porovnanie fingerprintu |
| `cat()`, `sprintf()` | base R | status výpis |

---

## Chunk: `stepwise-helper`

### Účel
Definuje helpery pre bidirectional stepwise logistickú regresiu cez `MASS::stepAIC()`.

### Vysvetlenie kódu
- `step_keep(model, AIC)` je callback pre `stepAIC()`.
- `summary(model)$coefficients` vytiahne koeficientovú tabuľku aktuálneho GLM kroku.
- `tryCatch()` chráni callback pred zlyhaním pri neštandardnom medzikroku.
- Ak koeficienty chýbajú, vráti sa prázdny zoznam termov a p-hodnôt.
- Inak callback uloží názvy termov, ich `Pr(>|z|)` p-hodnoty a aktuálne AIC.
- `STEPWISE_GLM_WARNINGS` drží presný zoznam známych GLM diagnostík zo stepwise fitov: near-separation (`fitted probabilities numerically 0 or 1`) a IRLS konvergenciu (`algorithm did not converge`).
- `muffle_stepwise_glm_warnings()` cielene tlmí iba tieto známe GLM varovania z nepenalizovaných stepwise kandidátov. Netlmí iné warningy a nemení metódu výberu premenných.
- `fit_stepwise()` najprv fitne intercept-only logistickú regresiu.
- `glm.control(maxit = STEPWISE_GLM_MAXIT)` dáva GLM fitu viac iterácií než defaultných 25.
- `full_fm` vytvorí horný modelový scope zo zadaných feature-ov.
- `MASS::stepAIC(..., direction = "both")` môže v každom kroku pridávať aj odoberať premenné a je zabalené cez `muffle_stepwise_glm_warnings()`, aby report nebol zaplavený očakávanou stepwise GLM diagnostikou.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `tryCatch()` | base R | bezpečné zachytenie chyby v callbacku |
| `withCallingHandlers()` | base R | cielené zachytenie známeho GLM warningu |
| `grepl()` | base R | rozpoznanie konkrétneho warning textu |
| `map_lgl()` | `purrr` | kontrola warning textu voči zoznamu známych diagnostík |
| `conditionMessage()` | base R | text warningu |
| `invokeRestart()` | base R | umlčanie iba rozpoznaného warningu |
| `summary()` | stats/base R | koeficientová tabuľka GLM |
| `is.null()`, `nrow()` | base R | kontrola dostupnosti koeficientov |
| `return()` | base R | skorý návrat z helpera |
| `list()` | base R | štruktúra uložená v `keep` |
| `rownames()` | base R | názvy aktívnych termov |
| `unname()` | base R | odstránenie mien z p-hodnôt |
| `glm()` | stats | logistická regresia |
| `glm.control()` | stats | zvýšenie max počtu IRLS iterácií |
| `binomial()` | stats | binomická GLM rodina |
| `as.formula()` | stats | konštrukcia modelovej formuly |
| `paste()` | base R | skladanie formuly |
| `stepAIC()` | `MASS` | stepwise AIC výber premenných |

---

## Chunk: `lasso-helper`

### Účel
Definuje spoločné helpery pre lasso a elastic-net modely z `glmnet`.

### Vysvetlenie kódu
- `fit_glmnet(train_df, alpha)` vytvorí model matrix bez interceptu pomocou `model.matrix(label ~ . - 1, ...)`.
- `y <- train_df$label` vytiahne cieľovú premennú.
- `cv.glmnet()` fitne penalizovanú logistickú regresiu a interne vyberá lambda cez 5-fold CV.
- `lambda.min.ratio = GLMNET_LAMBDA_MIN_RATIO` skracuje extrémne nízky, takmer nepenalizovaný koniec lambda path. Scenár používa `lambda.1se`, takže nepotrebuje riskantné najmenšie lambdy, ktoré pri near-separation vyvolávali konvergenčný warning.
- Parameter `alpha = 1` znamená lasso, `alpha = 0.5` znamená elastic-net.
- `count_nonzero()` spočíta počet nenulových koeficientov pri zvolenom lambda a zahodí intercept.
- `selected_glmnet_terms()` používa tú istú koeficientovú logiku, ale vracia názvy prediktorov s nenulovým koeficientom. Vďaka tomu sa výber termov neopakuje ručne vo viacerých chunkoch.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `model.matrix()` | stats | vytvorenie numerickej matice prediktorov |
| `cv.glmnet()` | `glmnet` | cross-validated penalizovaná logistická regresia |
| `coef()` | stats/base R + `glmnet` metóda | extrakcia koeficientov |
| `as.numeric()` | base R | konverzia koeficientov na vektor |
| `sum()` | base R | počet nenulových koeficientov |

---

## Chunk: `lexical-final-check`

### Účel
Fitne tri feature-selection metódy na Lexical URL-only prediktoroch, vyhodnotí ich na hold-out teste a skontroluje H2 kritériá.

### Vysvetlenie kódu
- `metrics_from_prob()` vytvorí triednu predikciu pri prahu 0.5 pomocou `if_else()` a vráti jeden riadok metrík.
- `roc_auc_vec(..., event_level = "first")`, `sens_vec()`, `spec_vec()` a `accuracy_vec()` vypočítajú testovacie metriky pre prvú faktorovú úroveň, teda `Phishing`.
- `predict_glm_phishing()` vracia pravdepodobnosť phishingu zo stepwise GLM. Keďže GLM response reprezentuje druhú faktorovú úroveň, používa sa `1 - response`.
- `predict_glmnet_phishing()` analogicky skóruje `glmnet` model na test model matrix.
- `run_or_load("lexical_final", ...)` cache-uje finálne Lexical fitnutia.
- Vnútri cache bloku sa vyberú `label + lexical_predictors`, fitne sa stepwise, lasso a elastic-net a uloží sa aj zoznam vybraných termov.
- `selected_glmnet_terms()` extrahuje lasso/elastic-net support pri `lambda.1se`.
- `test_lexical` obsahuje test set obmedzený na Lexical pool.
- Konštanty `SPARSITY_MAX_K`, `MIN_TEST_AUC`, `MIN_SENSITIVITY` a `MIN_SPECIFICITY` kodifikujú H2 prahy.
- `lexical_diagnostic` skladá metódy, počty vybraných premenných, predikované pravdepodobnosti, metriky a boolean výsledky kritérií.
- Finálny `transmute()` formátuje metriky a `kable()` ich zobrazí ako reportovateľnú tabuľku.
- `saveRDS()` uloží metrickú tabuľku pre prípadné ďalšie porovnania.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `tibble()` | `tibble` | tabuľková štruktúra metrík |
| `factor()` | base R | triedna predikcia s rovnakými levelmi |
| `if_else()` | `dplyr` | vektorizovaný threshold na triedy |
| `levels()` | base R | zachovanie poradia tried |
| `roc_auc_vec()` | `yardstick` | AUC z pravdepodobností |
| `sens_vec()` | `yardstick` | senzitivita |
| `spec_vec()` | `yardstick` | špecificita |
| `accuracy_vec()` | `yardstick` | accuracy |
| `predict()` | stats/base R + modelové metódy | skórovanie GLM a glmnet modelov |
| `model.matrix()` | stats | testovacia matica pre glmnet |
| `select()` | `dplyr` | výber Lexical stĺpcov |
| `all_of()` | `tidyselect` | výber podľa vektora názvov |
| `setdiff()` | base R | odstránenie interceptu zo stepwise termov |
| `map()` | `purrr` | aplikácia metriky na list-column pravdepodobností |
| `unnest()` | `tidyr` | rozbalenie metric tibble list-column |
| `mutate()` | `dplyr` | výpočet kritérií H2 |
| `transmute()` | `dplyr` | finálny výstupný prehľad |
| `sprintf()` | base R | formátovanie čísel |
| `kable()` | `knitr` | HTML výpis reportovej tabuľky |
| `saveRDS()` | base R | uloženie metrického artefaktu |

---

## Chunk: `d1-table`

### Účel
Zobrazí, ktoré Lexical URL prediktory vybrala každá z troch feature-selection metód.

### Vysvetlenie kódu
- `all_terms` spojí stepwise, lasso, elastic-net a celý Lexical pool, odstráni duplicity a zoradí názvy.
- `tibble()` vytvorí jeden riadok na prediktor.
- Stĺpce `stepwise`, `lasso` a `elastic_net` označujú výber prediktora znakom `"x"`.
- `if_else()` nahrádza základné `ifelse()` a drží typ výstupu jasne ako character.
- `score` počíta, koľkými metódami bol prediktor vybraný.
- `arrange(desc(score), predictor)` posunie robustnejšie/core prediktory vyššie.
- Finálny výstup odstráni pomocný `score` a vypíše tabuľku cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | spojenie vektorov termov |
| `unique()` | base R | odstránenie duplicít |
| `sort()` | base R | abecedné zoradenie |
| `tibble()` | `tibble` | konštrukcia výstupnej tabuľky |
| `if_else()` | `dplyr` | označenie vybraných prediktorov |
| `%in%` | base R | membership test |
| `mutate()` | `dplyr` | výpočet selection score |
| `arrange()` | `dplyr` | zoradenie výstupu |
| `desc()` | `dplyr` | zostupné zoradenie |
| `select()` | `dplyr` | odstránenie pomocného stĺpca |
| `kable()` | `knitr` | HTML výpis tabuľky |

---

## Chunk: `stepwise`

### Účel
Rozbalí `stepAIC` audit trail a zosumarizuje vývoj p-hodnôt aktívnych termov počas stepwise AIC cesty.

### Vysvetlenie kódu
- `keep_mat <- lexical_final$stepwise_fit$keep` vytiahne objekty uložené callbackom `step_keep()`.
- `n_steps` určí počet AIC krokov bez ohľadu na to, či je `keep` uložený ako matrix alebo list.
- `map_dfr(seq_len(n_steps), ...)` prejde každý krok a poskladá výsledky do jedného tibble.
- Z každého kroku sa vytiahnu termy, p-hodnoty a AIC.
- `filter(predictor != "(Intercept)")` odstráni intercept z feature auditu.
- `group_by(predictor)` a `summarise()` vytvoria feature-level audit: prvý/posledný krok, min/max/final p-hodnotu a to, či p-hodnota prešla cez hranicu 0.05.
- `dplyr::last(p)` berie poslednú p-hodnotu po zoradení krokov v rámci prediktora.
- `arrange(desc(crosses_05), desc(max_p), predictor)` dáva najproblematickejšie alebo najnestabilnejšie termy na začiatok.
- Finálny výstup zaokrúhli p-hodnoty cez `signif()` a zobrazí audit cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `is.matrix()` | base R | rozlíšenie tvaru `keep` objektu |
| `ncol()`, `length()` | base R | počet krokov |
| `map_dfr()` | `purrr` | skladanie krokov do tibble |
| `seq_len()` | base R | bezpečná sekvencia krokov |
| `tibble()` | `tibble` | tabuľka krokovej cesty |
| `filter()` | `dplyr` | odstránenie interceptu |
| `group_by()` | `dplyr` | zoskupenie podľa prediktora |
| `arrange()` | `dplyr` | zoradenie krokov a summary |
| `summarise()` | `dplyr` | feature-level audit |
| `min()`, `max()`, `any()` | base R | summary štatistiky |
| `last()` | `dplyr` | posledná p-hodnota |
| `across()` | `dplyr` | hromadné formátovanie p-hodnôt |
| `signif()` | base R | zaokrúhlenie p-hodnôt |
| `kable()` | `knitr` | HTML výpis audit tabuľky |

---

## Chunk: `d2-embedded-coefs`

### Účel
Zobrazí pomenované nenulové lasso a elastic-net koeficienty pri finálnom `lambda.1se`.

### Vysvetlenie kódu
- `coef_at_lambda()` vytiahne koeficienty z `glmnet` modelu pri zadanom lambda.
- Intercept sa odstráni maticovým slicingom `[-1, , drop = FALSE]`, pretože reportujeme iba prediktory.
- Helper skladá tibble s názvom prediktora, názvom metódy, numerickým koeficientom a flagom `retained`.
- `bind_rows()` spojí lasso a elastic-net koeficienty do jedného long formátu.
- Graf filtruje iba retained prediktory, reorderuje ich podľa absolútnej veľkosti koeficientu a kreslí horizontálne stĺpcové grafy cez `geom_col()`.
- `facet_wrap(~ method, scales = "free_y")` oddelí lasso a elastic-net, pretože nemusia mať rovnaký počet retained prediktorov.
- `geom_vline(xintercept = 0)` pridáva nulovú referenciu pre znamienko koeficientu.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `coef()` | stats/base R + `glmnet` metóda | extrakcia penalizovaných koeficientov |
| `as.matrix()` | base R | konverzia sparse koeficientov |
| `tibble()` | `tibble` | helper výstup |
| `rownames()` | base R | názvy prediktorov z koeficientovej matice |
| `as.numeric()` | base R | numerický koeficient |
| `bind_rows()` | `dplyr` | spojenie metód |
| `filter()` | `dplyr` | ponechanie nenulových koeficientov |
| `mutate()` | `dplyr` | reorder prediktorov |
| `reorder()` | stats | zoradenie faktorov podľa hodnoty |
| `abs()` | base R | veľkosť koeficientu |
| `ggplot()`, `aes()` | `ggplot2` | základ grafu |
| `geom_col()`, `geom_vline()` | `ggplot2` | stĺpce a nulová os |
| `facet_wrap()` | `ggplot2` | oddelenie metód |
| `labs()` | `ggplot2` | titulky a osi |
| `theme_minimal()` | `ggplot2` | vizuálny štýl |

---

## Chunk: `d2-zero-lambda`

### Účel
Pre každý prediktor vypočíta najväčšiu lambda hodnotu, pri ktorej bol koeficient ešte nenulový, teda mieru robustnosti voči regularizácii.

### Vysvetlenie kódu
- `active_lambda_table()` vytiahne celú glmnet koeficientovú cestu bez interceptu.
- `lambdas <- cvfit$glmnet.fit$lambda` drží reálne lambda hodnoty v rovnakom poradí ako stĺpce koeficientovej matice.
- Matica sa prevedie na tibble s `predictor` stĺpcom.
- `rename_with(~ as.character(seq_along(lambdas)), -predictor)` premenuje lambda stĺpce na číselné indexy, aby sa dali bezpečne mapovať späť na `lambdas`.
- `pivot_longer()` prevedie wide koeficientovú cestu na long formát: prediktor, lambda index, koeficient.
- `mutate(lambda = lambdas[as.integer(lambda_index)])` priradí skutočnú lambda hodnotu ku každému riadku.
- `filter(coefficient != 0)` nechá iba aktívne koeficienty.
- `summarise(active_lambda = max(lambda), .by = predictor)` vyberie najväčšiu lambda, pri ktorej bol prediktor aktívny.
- `right_join()` vráti späť aj prediktory, ktoré nikdy neboli aktívne, s `NA` hodnotou.
- `embedded_lambda` spojí lasso a elastic-net výsledky.
- `pivot_wider()` vytvorí porovnávaciu tabuľku metóda vedľa metódy; `NA` sa formátuje ako `"(never)"`.
- `kable()` ponecháva čitateľný HTML výpis.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `coef()` | stats/base R + `glmnet` metóda | koeficientová cesta |
| `as.matrix()` | base R | konverzia sparse koeficientov |
| `as_tibble()` | `tibble` | matica na tibble |
| `rename_with()` | `dplyr` | bezpečné premenovanie lambda stĺpcov |
| `seq_along()` | base R | indexy lambda hodnôt |
| `pivot_longer()` | `tidyr` | wide-to-long transformácia |
| `mutate()` | `dplyr` | pridanie skutočnej lambda hodnoty |
| `as.integer()` | base R | konverzia indexu |
| `filter()` | `dplyr` | ponechanie aktívnych koeficientov |
| `summarise()` | `dplyr` | najväčšia aktívna lambda |
| `max()` | base R | maximum lambda hodnoty |
| `right_join()` | `dplyr` | doplnenie nikdy aktívnych prediktorov |
| `bind_rows()` | `dplyr` | spojenie metód |
| `pivot_wider()` | `tidyr` | porovnávacia wide tabuľka |
| `across()` | `dplyr` | formátovanie oboch metód |
| `if_else()` | `dplyr` | nahradenie NA textom |
| `is.na()` | base R | detekcia neaktívnych prediktorov |
| `signif()` | base R | zaokrúhlenie lambda |
| `arrange()` | `dplyr` | zoradenie tabuľky |
| `kable()` | `knitr` | HTML výpis tabuľky |

---

## Chunk: `perfold-fit`

### Účel
Na 10 FullLite foldoch opakovane fitne stepwise, lasso a elastic-net a uloží počty aj konkrétne zoznamy vybraných prediktorov.

### Vysvetlenie kódu
- Celý výpočet je zabalený do `run_or_load("perfold", ...)`, pretože ide o najdrahší blok scenára.
- `t0 <- Sys.time()` odmeria začiatok výpočtu.
- `fit_fold(rows, k)` je vnútorný helper pre jeden fold.
- `slice(rows)` vyberie train riadky daného foldu a `select(label, all_of(predictors))` obmedzí dáta na FullLite pool.
- `fit_stepwise()`, `fit_glmnet(alpha = 1)` a `fit_glmnet(alpha = 0.5)` fitnú tri porovnávané metódy.
- `selected_glmnet_terms()` extrahuje nenulové lasso/elastic-net termy pri `lambda.1se`.
- `cat(sprintf(...))` a `flush.console()` vypíšu začiatok fold-u ešte pred pomalým stepwise fitom a potom aj finálny počet vybraných prediktorov po dobehnutí fold-u.
- Helper vracia tibble s fold číslom, počtami vybraných prediktorov a list-column stĺpcami so samotnými termami.
- `map2_dfr(fold_idx, seq_along(fold_idx), fit_fold)` prejde všetky foldy a poskladá ich do jednej tabuľky.
- Výsledný cache objekt zachováva pôvodné vektory `k_step`, `k_lasso`, `k_en` aj listy termov pre nadväzujúce chunky.
- Finálny tibble na konci chunku zobrazí počet vybraných prediktorov na fold cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `Sys.time()` | base R | meranie času |
| `slice()` | `dplyr` | výber fold train riadkov |
| `select()` | `dplyr` | výber FullLite stĺpcov |
| `all_of()` | `tidyselect` | výber podľa názvov prediktorov |
| `setdiff()` | base R | odstránenie interceptu |
| `coef()` | stats/base R | koeficienty stepwise modelu |
| `model.matrix()` | stats | názvy model-matrix stĺpcov |
| `cat()`, `sprintf()` | base R | status výpis foldov |
| `flush.console()` | utils/base R | okamžité odoslanie progress výpisu v interaktívnej konzole |
| `tibble()` | `tibble` | per-fold výsledok |
| `list()` | base R | uloženie termov do list-column |
| `map2_dfr()` | `purrr` | iterácia cez fold indexy a fold čísla |
| `seq_along()` | base R | fold čísla |
| `difftime()` | base R | elapsed time |
| `as.numeric()` | base R | konverzia elapsed time |
| `kable()` | `knitr` | HTML výpis per-fold tabuľky |

---

## Chunk: `fulllite-mean`

### Účel
Zosumarizuje priemerný počet vybraných FullLite prediktorov pre stepwise, lasso a elastic-net.

### Vysvetlenie kódu
- `mean_step`, `mean_lasso` a `mean_en` berú priemer z per-fold počtov uložených v cache objekte `perfold`.
- `tibble()` skladá tri reportovateľné riadky: priemerné `k` pre stepwise, lasso a elastic-net.
- `sprintf("%.1f", ...)` formátuje priemery na jedno desatinné miesto.
- `kable()` vypíše krátku summary tabuľku.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `mean()` | base R | priemerný počet vybraných prediktorov |
| `tibble()` | `tibble` | výstupná tabuľka |
| `c()` | base R | vektory metrík a hodnôt |
| `sprintf()` | base R | formátovanie priemerov |
| `kable()` | `knitr` | HTML výpis summary tabuľky |

---

## Chunk: `fulllite-perfold-plot`

### Účel
Zobrazí rozdelenie počtu vybraných FullLite prediktorov naprieč 10 foldmi pre každú metódu.

### Vysvetlenie kódu
- `tibble()` najprv vytvorí wide tabuľku: jeden riadok na fold a jeden stĺpec na metódu.
- `pivot_longer(-fold, names_to = "method", values_to = "k")` preklopí tabuľku do long formátu vhodného pre `ggplot2`.
- `factor(method, levels = ...)` nastaví stabilné poradie metód v grafe.
- `ggplot()` vytvorí boxplot počtov vybraných prediktorov podľa metódy.
- `geom_boxplot()` ukáže medián, kvartily a rozptyl počtu vybraných prediktorov.
- `geom_point(position_jitter(...))` pridá jednotlivé fold hodnoty.
- `geom_hline(yintercept = length(predictors))` ukáže veľkosť celého FullLite poolu ako referenciu.
- `annotate()` k referenčnej čiare doplní textový popis.
- `theme_minimal()` a odstránenie legendy udržia graf čistý.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `tibble()` | `tibble` | wide per-fold tabuľka |
| `seq_along()` | base R | fold čísla |
| `pivot_longer()` | `tidyr` | long formát pre graf |
| `mutate()` | `dplyr` | nastavenie faktora metódy |
| `factor()` | base R | poradie metód |
| `ggplot()`, `aes()` | `ggplot2` | základ grafu |
| `geom_boxplot()` | `ggplot2` | rozdelenie počtov |
| `geom_point()` | `ggplot2` | jednotlivé fold hodnoty |
| `position_jitter()` | `ggplot2` | jemné rozptýlenie bodov |
| `geom_hline()` | `ggplot2` | referencia veľkosti poolu |
| `annotate()` | `ggplot2` | text v grafe |
| `sprintf()` | base R | text anotácie |
| `labs()` | `ggplot2` | titulky a osi |
| `theme_minimal()`, `theme()` | `ggplot2` | štýl grafu |

---

## Chunk: `fulllite-selection-frequency`

### Účel
Spočíta, v koľkých z 10 FullLite foldov každá metóda vybrala každý prediktor.

### Vysvetlenie kódu
- `n_folds <- length(fold_idx)` uloží počet foldov pre interpretáciu výsledkov.
- `count_in_folds(term_lists, term)` používa `map_lgl()` na kontrolu, či sa daný term nachádza v každom fold zozname, a `sum()` spočíta počet výskytov.
- `all_fulllite_terms` spojí termy vybrané stepwise, lasso, elastic-net a celý `predictors` pool.
- `flatten_chr()` zmení listy termov na znakové vektory.
- `unique()` a `sort()` odstránia duplicity a zoradia názvy.
- `d1_full` vytvorí jeden riadok na prediktor.
- `map_int()` pre každý prediktor vypočíta počet foldov, kde ho vybrala konkrétna metóda.
- `score = stepwise + lasso + elastic_net` je pomocné zoradenie podľa celkovej robustnosti naprieč metódami.
- Finálny výstup odstráni pomocný `score` a zobrazí frekvencie výberu cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `length()` | base R | počet foldov |
| `map_lgl()` | `purrr` | membership test pre každý fold |
| `%in%` | base R | kontrola prítomnosti termu |
| `sum()` | base R | počet foldov, kde je term prítomný |
| `flatten_chr()` | `purrr` | list termov na znakový vektor |
| `c()` | base R | spojenie termov |
| `unique()` | base R | odstránenie duplicít |
| `sort()` | base R | zoradenie termov |
| `tibble()` | `tibble` | výstupná frekvenčná tabuľka |
| `map_int()` | `purrr` | výpočet integer frekvencií |
| `mutate()` | `dplyr` | pomocný robustnostný score |
| `arrange()` | `dplyr` | zoradenie podľa score |
| `desc()` | `dplyr` | zostupné zoradenie |
| `select()` | `dplyr` | odstránenie pomocného stĺpca |
| `kable()` | `knitr` | HTML výpis tabuľky |
