# Scenario 2 chunk-by-chunk dokumentácia

Tento dokument vysvetľuje všetky code-chunky zo `scenario_2.rmd` rovnakým štýlom ako `eda_chunk_documentation.md`. Texty v samotnom notebooku sa nemenili; dokumentácia iba opisuje, čo robí kód, prečo tam je a z akých balíkov pochádzajú použité funkcie.

## Konvencia

Každý chunk-doc obsahuje:
- **Účel** - stručne, čo chunk robí a prečo je potrebný.
- **Vysvetlenie kódu** - krok po kroku, ako kód pracuje.
- **Použité funkcie** - tabuľka funkcia → balík → účel.

## Konvencie tidyverse/tidymodels refaktoru

Notebook používa tidyverse dialekt všade tam, kde ide o manipuláciu s dátami, zoznamami, tabuľkami a metrikami. Modelové enginy (`caret`, `glmnet`, `MASS`, `klaR`, `randomForest`, `kernlab`, `rpart`) ostávajú, pretože tvoria jadro experimentu a nie sú nahraditeľné obyčajným `dplyr` kódom bez zmeny zadania.

| Pôvodne | Nová verzia | Dôvod |
|---------|-------------|-------|
| `pROC::roc()$auc` | `yardstick::roc_auc_vec()` | tidymodels metrika, kratší zápis |
| `knitr::kable()` / `kable()` | `library(knitr)` + `kable()` pre finálne prezentačné tabuľky | krajší HTML výpis a kratší zápis pri opakovanom použití |
| `sapply()` / `lapply()` | `select(where(...))`, `map()`, `map_int()` | tidyverse/purrr idiomatika |
| ručné `for` slučky cez tiers | `imap()` / `imap_dfr()` | menej boilerplate, explicitné názvy tiers |
| vnorený grid search `for` × `for` × `for` | `crossing()` + `pmap_dfr()` | grid je tabuľka, výsledky sú tibble |
| base subsetting `df[, cols]` pri dátach | `select(all_of(cols))`, `slice()` | bezpečnejší a čitateľnejší tidyselect |

---

## Chunk: `libraries`

### Účel
Načíta balíky potrebné pre scenár 2 a nastaví reprodukovateľný seed aj adresár pre cache/artifacts.

### Vysvetlenie kódu
- `library(tidyverse)` zapne dátovú manipuláciu (`dplyr`, `tidyr`, `purrr`, `readr`, `tibble`, `stringr`, `ggplot2`).
- Modelové balíky sa načítajú podľa rodín modelov: `caret` ako tréningový wrapper, `glmnet` pre ridge logistickú regresiu, `MASS` pre LDA, `klaR` pre Naive Bayes, `randomForest` pre RF a `kernlab` pre SVM-RBF.
- `yardstick` nahrádza `pROC` pri výpočte AUC.
- `knitr` poskytuje `kable()` pre finálne HTML tabuľky v reporte.
- `digest` vytvára fingerprinty pre cache, aby sa staré `.rds` výsledky nepoužili pri zmene tiers.
- `set.seed(2026)` stabilizuje sampling, jitter a modelové procedúry, ktoré používajú náhodnosť.
- `ARTIFACTS` drží cestu k cache adresáru a `dir.create()` ho vytvorí, ak ešte neexistuje.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `library()` | base R | načítanie balíkov |
| `set.seed()` | base R | reprodukovateľnosť náhodných krokov |
| `dir.create()` | base R | vytvorenie adresára pre cache |

---

## Chunk: `load-data`

### Účel
Nájde CSV dataset v koreňovom adresári alebo o úroveň vyššie, načíta ho a odstráni prípadný UTF-8 BOM z názvu prvého stĺpca.

### Vysvetlenie kódu
- `dataset_path` sa nastaví cez `if / else if / else`: najprv sa hľadá `PhiUSIIL_Phishing_URL_Dataset.csv` v aktuálnom adresári, potom v rodičovskom adresári.
- Ak súbor neexistuje ani na jednom mieste, `stop()` ukončí chunk s jasnou chybou.
- `read_csv(..., show_col_types = FALSE)` načíta dáta bez vypisovania typov stĺpcov.
- `rename_with(~ str_remove(.x, "^\\ufeff"))` aplikuje čistenie názvu na všetky stĺpce a odstráni BOM iba tam, kde sa nachádza.
- `cat()` vypíše rýchly sanity check s počtom riadkov a stĺpcov.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `file.exists()` | base R | kontrola existencie súboru |
| `stop()` | base R | explicitná chyba pri chýbajúcom datasete |
| `read_csv()` | `readr` (tidyverse) | načítanie CSV do tibble |
| `%>%` | `magrittr`/tidyverse | pipe operátor |
| `rename_with()` | `dplyr` (tidyverse) | úprava názvov stĺpcov funkciou |
| `str_remove()` | `stringr` (tidyverse) | odstránenie BOM regexom |
| `cat()`, `nrow()`, `ncol()` | base R | konzolový výpis rozmerov |

---

## Chunk: `exclusions`

### Účel
Zopakuje rovnaké vylúčenia feature-ov ako EDA, aby modely v scenári 2 bežali na rovnakom sete prediktorov.

### Vysvetlenie kódu
- `ID_COLS`, `SCORES`, `REDUNDANT_BINARY` a `RATIOS` definujú štyri skupiny stĺpcov, ktoré sa nemajú modelovať.
- `EXCLUDE_COLS` tieto skupiny spojí do jedného vektora.
- `mutate(label = factor(...))` prevedie pôvodnú binárnu label premennú na faktor s poradím úrovní `Phishing`, `Legitimate`. Toto poradie je dôležité pre `caret::twoClassSummary()` aj `yardstick::roc_auc_vec(event_level = "first")`.
- `select(-all_of(EXCLUDE_COLS))` odstráni identifikátory, skóre, redundantnú binárnu premennú a pomery.
- Výpis cez `cat()` potvrdí počet prediktorov po vylúčeniach.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `c()` | base R | definícia vektorov názvov stĺpcov |
| `mutate()` | `dplyr` | vytvorenie faktorovej label pre modelovanie |
| `factor()` | base R | explicitné poradie tried |
| `select()` | `dplyr` | odstránenie stĺpcov |
| `all_of()` | `tidyselect` | striktný výber podľa mien |
| `cat()`, `ncol()` | base R | sanity výpis |

---

## Chunk: `family-map`

### Účel
Definuje mapovanie feature-ov do rodín signálov a z nich vytvorí štyri modelovacie tiers: Lexical, Trust, Behavior a FullLite.

### Vysvetlenie kódu
- `tribble()` ručne vytvorí dvojstĺpcovú tabuľku `feature` / `family`.
- `LEAKY_BEHAVIOR` drží šesť Behavior count feature-ov, ktoré majú near-leaky univariate signal a preto sa vyraďujú z Behavior aj FullLite.
- `tiers` je pomenovaný list:
  - `Lexical`, `Trust` a `Behavior` sa skladajú z filtrovania `family_map`.
  - `Behavior` dodatočne odstraňuje `LEAKY_BEHAVIOR`.
  - `FullLite` berie všetky feature-y z mapy a tiež odstraňuje `LEAKY_BEHAVIOR`.
- `map_int(tiers, length)` vypíše počet feature-ov v každom tier.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `tribble()` | `tibble` | ručná konštrukcia mapy feature-ov |
| `filter()` | `dplyr` | výber rodiny feature-ov |
| `pull()` | `dplyr` | vytiahnutie stĺpca ako vektor |
| `setdiff()` | base R | odstránenie near-leaky feature-ov |
| `list()` | base R | pomenovaný zoznam tiers |
| `map_int()` | `purrr` | počet feature-ov v každom tier |

---

## Chunk: `subsample`

### Účel
Vytvorí stratifikovaný 30k subsample, aby boli pomalšie modely (najmä SVM-RBF a KNN) výpočtovo zvládnuteľné.

### Vysvetlenie kódu
- `N_SUB <- 30000` nastaví cieľový počet riadkov.
- `group_by(label)` rozdelí dáta podľa triedy.
- `slice_sample(n = N_SUB / 2)` vezme rovnaký počet riadkov z každej triedy, teda 15k phishing a 15k legitimate.
- `ungroup()` odstráni grouping, aby ďalšie operácie neboli nechtiac per-class.
- `count(label)` zobrazí kontrolu rovnováhy tried.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `group_by()` | `dplyr` | stratifikácia podľa label |
| `slice_sample()` | `dplyr` | náhodný výber v rámci tried |
| `ungroup()` | `dplyr` | zrušenie groupingu |
| `count()` | `dplyr` | kontrola počtu riadkov podľa triedy |

---

## Chunk: `splits`

### Účel
Vytvorí zdieľaný train/test split a zdieľané CV fold indexy pre všetky modely a tiers.

### Vysvetlenie kódu
- `createDataPartition(..., p = 0.8)` vytvorí stratifikovaný 80/20 split.
- `as.vector()` zjednoduší indexy z maticového tvaru na vektor.
- `slice(idx)` a `slice(-idx)` vytvoria tréningovú a testovaciu časť v tidyverse štýle.
- `createFolds(..., k = 10, returnTrain = TRUE)` vytvorí 10-fold CV indexy, ktoré používa každý model.
- `cat()` vypíše rozmery splitu a počet foldov.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `createDataPartition()` | `caret` | stratifikovaný train/test split |
| `as.vector()` | base R | zjednodušenie indexov |
| `slice()` | `dplyr` | výber riadkov podľa indexov |
| `createFolds()` | `caret` | zdieľané CV foldy |
| `cat()`, `nrow()`, `length()` | base R | sanity výpis |

---

## Chunk: `recipes`

### Účel
Pripraví dve verzie dát: raw dáta pre Random Forest a log-transformované/štandardizované dáta pre modely citlivé na škálu.

### Vysvetlenie kódu
- `feat <- df_sub %>% select(-label)` izoluje prediktory.
- `select(where(...))` nájde binárne feature-y: stĺpce, ktorých nenulové hodnoty patria do `{0, 1}`.
- `continuous_features` je rozdiel všetkých feature-ov a binárnych feature-ov.
- `apply_log()` používa `mutate(across(...))`, aby na všetky kontinuálne feature-y aplikoval `log1p(pmax(x, 0))`. `pmax()` chráni pred zápornými hodnotami a `log1p()` je stabilný log transform pre hodnoty vrátane nuly.
- `preProcess()` sa fitne na kontinuálne feature-y v tréningových dátach.
- `replace_continuous()` najprv vyrobí škálované kontinuálne stĺpce cez `predict(pp, ...)`, potom ich cez `mutate(across(..., cur_column()))` vloží späť do pôvodnej tabuľky.
- `train_std` a `test_std` sú štandardizované verzie pre LR/LDA/NB/SVM/KNN.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `select()` | `dplyr` | výber prediktorov |
| `where()` | `tidyselect` | výber stĺpcov podľa predikátu |
| `na.omit()` | stats/base R | ignorovanie NA pri binárnej kontrole |
| `%in%`, `all()` | base R | kontrola binárnych hodnôt |
| `names()` | base R | názvy feature-ov |
| `setdiff()` | base R | kontinuálne feature-y |
| `mutate()` / `across()` | `dplyr` | hromadná transformácia stĺpcov |
| `all_of()` | `tidyselect` | výber podľa vektora mien |
| `log1p()`, `pmax()` | base R | bezpečný log transform |
| `preProcess()` | `caret` | fit centrovania a škálovania |
| `predict()` | stats/caret | aplikovanie preprocessingu |
| `cur_column()` | `dplyr` | aktuálny názov stĺpca v `across()` |

---

## Chunk: `fit-utility`

### Účel
Definuje spoločnú infraštruktúru pre tréning modelov, cache výsledkov a výpis per-tier summary tabuliek.

### Vysvetlenie kódu
- `fit_one_tier()` dostane jeden tier, train/test dáta, caret method a prípadný `tuneGrid`.
- `select(label, all_of(tier_features))` zúži dáta na label a aktuálne feature-y.
- `trainControl()` nastaví 10-fold CV, spoločné foldy, class probabilities a `twoClassSummary()` pre ROC.
- `caret::train()` fitne model cez zvolený engine.
- Pravdepodobnosti triedy `Phishing` sa získajú cez `predict(..., type = "prob")`, konvertujú na tibble a vyberú cez `pull(Phishing)`.
- `roc_auc_vec(..., event_level = "first")` vypočíta AUC pre prvú faktorovú úroveň, teda `Phishing`.
- `confusionMatrix()` vytiahne Accuracy, F1, Precision, Sensitivity a Specificity.
- `tiers_fingerprint()` zoradí tiers a ich feature-y, potom ich zahashuje cez `digest()`.
- `fit_tiers()` je malý wrapper cez `imap(tiers, fitter)`, aby každý model nemusel ručne písať rovnakú slučku.
- `run_or_load()` používa `.rds` cache, overí tiers/schema/fingerprint a pri stale cache refitne model.
- `print_tier_summary()` z modelového výsledku skladá tibble s train AUC, CV ROC, test metrikami a časom tréningu a vypíše ju cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `select()` / `all_of()` | `dplyr` / `tidyselect` | subset dát na tier |
| `trainControl()` | `caret` | nastavenie CV a metrík |
| `twoClassSummary()` | `caret` | ROC summary pre klasifikáciu |
| `Sys.time()`, `difftime()` | base R | meranie času tréningu |
| `caret::train()` | `caret` | tréning modelu |
| `predict()` | stats/caret | predikcie tried a pravdepodobností |
| `as_tibble()` | `tibble` | konverzia probability outputu |
| `pull()` | `dplyr` | výber pravdepodobnosti `Phishing` |
| `roc_auc_vec()` | `yardstick` | AUC bez `pROC` |
| `confusionMatrix()` | `caret` | confusion-matrix metriky |
| `map()` / `imap()` / `imap_dfr()` | `purrr` | práca so zoznamami tiers |
| `digest::digest()` | `digest` | cache fingerprint |
| `file.path()`, `file.exists()` | base R | cesty ku cache |
| `readRDS()` / `saveRDS()` | base R | načítanie/uloženie cache |
| `setequal()`, `isTRUE()` | base R | validácia cache |
| `sprintf()`, `cat()` | base R | konzolové logovanie |
| `tibble()` | `tibble` | summary tabuľka |
| `kable()` | `knitr` | HTML výpis modelovej summary tabuľky |

---

## Chunk: `fit-lr`

### Účel
Natrénuje ridge logistickú regresiu na všetkých štyroch tiers a vypíše jej summary.

### Vysvetlenie kódu
- `run_or_load("lr", ...)` najprv skúsi použiť cache `res_lr.rds`.
- `fit_tiers("LogReg-Ridge", "parametric", ...)` aplikuje rovnaký fitting callback na každý tier.
- Callback vypíše názov tier a počet feature-ov.
- `fit_one_tier(..., method = "glmnet")` spustí caret model s glmnet engine.
- `tibble(alpha = 0, lambda = 0.01)` fixuje čistý ridge (`alpha = 0`) a jednu hodnotu regularizácie.
- `print_tier_summary(res_lr)` vráti tibble s CV/test metrikami.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `run_or_load()` | lokálna funkcia | cache alebo refit |
| `fit_tiers()` | lokálna funkcia | aplikovanie modelu cez tiers |
| `cat()` / `sprintf()` | base R | fitting log |
| `length()` | base R | počet feature-ov |
| `fit_one_tier()` | lokálna funkcia | tréning a metriky |
| `tibble()` | `tibble` | tuneGrid pre glmnet |
| `print_tier_summary()` | lokálna funkcia | výpis výsledkov |

---

## Chunk: `fit-lda`

### Účel
Natrénuje Linear Discriminant Analysis ako parametric baseline bez hyperparametrov.

### Vysvetlenie kódu
- Cache kľúč je `lda`.
- `fit_tiers()` prechádza tiers cez `imap()`.
- Pre každý tier sa volá `fit_one_tier(..., method = "lda")`, čo v caret používa LDA implementáciu z `MASS`.
- Nie je potrebný `tuneGrid`, pretože LDA nemá v tomto nastavení hyperparametre.
- Summary tabuľka má rovnaký formát ako pri LR, aby sa modely dali priamo porovnávať.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `run_or_load()` | lokálna funkcia | cache/refit |
| `fit_tiers()` | lokálna funkcia | per-tier fitting |
| `fit_one_tier()` | lokálna funkcia + `caret`/`MASS` | tréning LDA |
| `cat()` / `sprintf()` | base R | logovanie |
| `print_tier_summary()` | lokálna funkcia | summary output |

---

## Chunk: `fit-nb`

### Účel
Natrénuje Naive Bayes na všetkých tiers a explicitne potlačí očakávané warningy z kernel density fitov.

### Vysvetlenie kódu
- `run_or_load("nb", ...)` používa cache pre NB.
- `fit_tiers("NaiveBayes", "parametric", ...)` prechádza tiers.
- `suppressWarnings()` obalí fitting, pretože NB s kernel density a binárnymi/konštantnými premennými môže produkovať varovania, ktoré nemenia zmysel experimentu.
- `method = "nb"` používa `klaR` engine cez caret.
- `tibble(fL = 1, usekernel = TRUE, adjust = 1)` definuje Laplace smoothing, kernel density a default bandwidth adjustment.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `run_or_load()` | lokálna funkcia | cache/refit |
| `fit_tiers()` | lokálna funkcia | per-tier fitting |
| `suppressWarnings()` | base R | potlačenie očakávaných NB warningov |
| `fit_one_tier()` | lokálna funkcia + `caret`/`klaR` | tréning NB |
| `tibble()` | `tibble` | tuneGrid pre NB |
| `print_tier_summary()` | lokálna funkcia | summary output |

---

## Chunk: `fit-rf`

### Účel
Natrénuje Random Forest ako stromový non-parametric model na raw dátach.

### Vysvetlenie kódu
- `fit_tiers("RandomForest", "non-parametric", ...)` prechádza všetky tiers.
- Pre každý tier sa vypočíta `p <- length(feats)` a `mtry <- max(1, floor(sqrt(p)))`.
- `fit_one_tier(..., train_raw, test_raw, method = "rf")` používa raw dáta, pretože RF nepotrebuje škálovanie ani log transform.
- `tibble(mtry = mtry)` je caret tuneGrid.
- `ntree = 300` sa posiela ako fixný argument do modelového enginu.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `run_or_load()` | lokálna funkcia | cache/refit |
| `fit_tiers()` | lokálna funkcia | per-tier fitting |
| `length()`, `sqrt()`, `floor()`, `max()` | base R | výpočet `mtry` |
| `fit_one_tier()` | lokálna funkcia + `caret`/`randomForest` | tréning RF |
| `tibble()` | `tibble` | tuneGrid pre RF |
| `print_tier_summary()` | lokálna funkcia | summary output |

---

## Chunk: `fit-svm`

### Účel
Natrénuje SVM s RBF kernelom na štandardizovaných dátach.

### Vysvetlenie kódu
- Cache kľúč je `svm`.
- `fit_tiers("SVM-RBF", "non-parametric", ...)` aplikuje rovnaký SVM setup na každý tier.
- `fit_one_tier(..., train_std, test_std, method = "svmRadial")` používa log-transformované a centrované/škálované dáta.
- `tibble(C = 1, sigma = 0.1)` fixuje cenu margin chýb a šírku RBF kernelu.
- Summary output používa rovnakú štruktúru ako ostatné modely.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `run_or_load()` | lokálna funkcia | cache/refit |
| `fit_tiers()` | lokálna funkcia | per-tier fitting |
| `fit_one_tier()` | lokálna funkcia + `caret`/`kernlab` | tréning SVM-RBF |
| `tibble()` | `tibble` | tuneGrid pre SVM |
| `print_tier_summary()` | lokálna funkcia | summary output |

---

## Chunk: `fit-knn`

### Účel
Natrénuje KNN na štandardizovaných dátach a pridá minimálny jitter, aby sa rozbili úplné ties v binárnych tiers.

### Vysvetlenie kódu
- `jitter_features()` používa `mutate(across(...))` na pridanie malého normálneho šumu do vybraných feature-ov.
- `rnorm(n(), 0, sd)` generuje jitter pre každý riadok a stĺpec v aktuálnom tier.
- `fit_tiers("KNN", "non-parametric", ...)` prechádza tiers.
- Pred fittingom sa vytvoria `tr_j` a `te_j`, jitterované verzie train/test dát.
- `fit_one_tier(..., method = "knn", tuneGrid = tibble(k = 25))` fitne KNN s fixným `k`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `mutate()` / `across()` | `dplyr` | hromadná úprava feature-ov |
| `all_of()` | `tidyselect` | výber stĺpcov tier |
| `rnorm()` | stats | jitter |
| `n()` | `dplyr` | počet riadkov v mutate kontexte |
| `run_or_load()` | lokálna funkcia | cache/refit |
| `fit_tiers()` | lokálna funkcia | per-tier fitting |
| `fit_one_tier()` | lokálna funkcia + `caret` | tréning KNN |
| `tibble()` | `tibble` | tuneGrid pre KNN |

---

## Chunk: `build-long`

### Účel
Zjednotí výsledky všetkých modelov do dlhých tabuliek pre agregácie, porovnania a finálny summary output.

### Vysvetlenie kódu
- `all_results` je list šiestich modelových objektov.
- `auc_long` pre každý model a tier rozbalí `cv_per_fold` na riadky s `model`, `family`, `tier`, `fold` a `auc`.
- `test_tbl` pre každý model a tier vyberie train/test metriky uložené vo výsledku.
- `summary_tbl` spojí CV AUC summary s test metrikami cez `left_join()`.
- `mutate(tier = factor(...))` fixuje poradie tiers vo výpisoch.
- `gap_auc = train_auc - test_auc` ukazuje train/test rozdiel.
- Posledný pipeline zaokrúhľuje numerické metriky a vypíše finálnu tabuľku cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `list()` | base R | kolekcia modelových výsledkov |
| `map_dfr()` / `imap_dfr()` | `purrr` | skladanie výsledkov do tibble |
| `transmute()` | `dplyr` | výber a premenovanie CV stĺpcov |
| `tibble()` | `tibble` | test summary riadky |
| `group_by()` / `summarise()` | `dplyr` | CV priemer a SD |
| `mean()` / `sd()` | base R/stats | agregácia AUC |
| `left_join()` | `dplyr` | spojenie CV a test metrík |
| `mutate()` / `across()` | `dplyr` | odvodené stĺpce a zaokrúhlenie |
| `factor()` | base R | poradie tiers |
| `arrange()` | `dplyr` | zoradenie výstupu |
| `round()` | base R | formátovanie metrík |
| `kable()` | `knitr` | HTML výpis summary tabuľky |

---

## Chunk: `quality-table`

### Účel
Vytvorí tabuľku threshold-dependent metrík na test sete: Accuracy, F1, Precision, Sensitivity a Specificity.

### Vysvetlenie kódu
- Vstupom je `test_tbl` z predchádzajúceho chunku.
- `mutate(tier = factor(...))` opäť nastaví poradie tiers.
- `arrange(tier, family, desc(test_f1))` zoradí modely v rámci tier/family podľa F1.
- `transmute()` vyberie iba relevantné stĺpce a rovno ich premenuje na report-friendly názvy.
- `round(..., 4)` dá metriky na štyri desatinné miesta.
- `kable()` vypíše finálnu quality tabuľku v čitateľnejšom HTML formáte.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `mutate()` | `dplyr` | nastavenie poradia tiers |
| `factor()` | base R | explicitné poradie |
| `arrange()` / `desc()` | `dplyr` | zoradenie |
| `transmute()` | `dplyr` | výber a premenovanie metrík |
| `round()` | base R | zaokrúhlenie |
| `kable()` | `knitr` | HTML výpis quality tabuľky |

---

## Chunk: `h1-minss`

### Účel
Vyhodnotí H1 cez deployment metric `minSS = min(Sensitivity, Specificity)` a porovná najlepší parametric vs non-parametric model v každom tier.

### Vysvetlenie kódu
- `mutate(minSS = pmin(test_sens, test_spec))` vypočíta slabšiu z dvoch operating-point metrík.
- `group_by(tier, family)` delí modely na parametric/non-parametric v každom tier.
- `summarise(minSS = max(minSS), auc = max(test_auc))` vyberá najlepší family-level champion pre daný tier.
- `pivot_wider()` dá parametric a non-parametric hodnoty vedľa seba.
- `gap_minSS` a `gap_auc` počítajú rozdiel non-parametric mínus parametric.
- Posledný pipeline zaokrúhľuje numerické stĺpce a vypíše výsledok cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `mutate()` | `dplyr` | výpočet gap metrík |
| `pmin()` | base R | minimum zo Sens/Spec |
| `group_by()` / `summarise()` | `dplyr` | výber champion hodnoty |
| `max()` | base R | najlepšia metrika v skupine |
| `pivot_wider()` | `tidyr` | parametric/non-parametric vedľa seba |
| `factor()` | base R | poradie tiers |
| `arrange()` | `dplyr` | zoradenie podľa tier |
| `across()` / `where()` | `dplyr`/`tidyselect` | zaokrúhlenie numeric stĺpcov |
| `round()` | base R | formátovanie |
| `kable()` | `knitr` | HTML výpis H1 gap tabuľky |

---

## Chunk: `h1-wilcoxon`

### Účel
Robí paired Wilcoxon sanity check na per-fold CV AUC medzi najlepším non-parametric a parametric championom.

### Vysvetlenie kódu
- `champions` vyberie pre každú kombináciu `tier`/`family` model s najvyšším `minSS`.
- `distinct(tier) %>% pull(tier) %>% map_dfr(...)` iteruje cez tiers tidyverse štýlom.
- V každom tier sa nájde `par_model` a `nonpar_model`.
- Z `auc_long` sa vytiahnu ich fold-level AUC hodnoty a zoradia podľa `fold`, aby párovanie sedelo.
- `wilcox.test(..., paired = TRUE, alternative = "greater")` testuje, či non-parametric champion má vyššie AUC.
- Výstup obsahuje tier, názvy championov, medián ΔAUC, Wilcoxon V a p-value.
- Posledný pipeline nastaví poradie tiers, formát p-value a vypíše výsledok cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `mutate()` | `dplyr` | výpočet minSS |
| `group_by()` / `slice_max()` / `ungroup()` | `dplyr` | výber champion modelov |
| `select()` | `dplyr` | zúženie stĺpcov |
| `distinct()` | `dplyr` | unikátne tiers |
| `pull()` | `dplyr` | vektor tiers/modelov/AUC |
| `map_dfr()` | `purrr` | iterácia cez tiers |
| `filter()` / `arrange()` | `dplyr` | výber fold AUC |
| `wilcox.test()` | stats | paired Wilcoxon test |
| `suppressWarnings()` | base R | potlačenie warningov pri ties |
| `tibble()` | `tibble` | riadok výsledku testu |
| `median()` | stats/base R | medián rozdielov |
| `unname()` | base R | odstránenie mena štatistiky |
| `format.pval()` | base R | čitateľné p-value |
| `kable()` | `knitr` | HTML výpis Wilcoxon tabuľky |

---

## Chunk: `task4-setup`

### Účel
Pripraví RF teacher modely pre surrogate-tree analýzu v scenári 4.

### Vysvetlenie kódu
- `library(rpart)` načíta balík pre single decision tree.
- `requireNamespace("rpart.plot", quietly = TRUE)` zistí, či je dostupné krajšie kreslenie stromu.
- `refit_rf_for_surrogate()` refitne Random Forest iba pre vybrané tiers (`Lexical`, `FullLite`), pretože pôvodná cache z `fit_one_tier()` neukladá fitted model object.
- `rf_seed` nastavuje lokálny seed pre teacher modely, aby surrogate výsledky nezáviseli od toho, či sa predchádzajúce modely načítali z cache alebo refitovali.
- Fingerprint obsahuje selected tiers, zoradené feature-y, počet stromov, počet train riadkov, seed a schema verziu.
- Pri validnej cache sa vracia `cached$by_tier`.
- Inak sa cez `map(set_names(selected_tiers), ...)` natrénuje RF teacher pre každý tier.
- `train_raw %>% select(all_of(feats))` dodá Random Forestu iba feature-y daného tier.
- Výsledný list teacher modelov sa uloží do `.rds`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `library()` | base R | načítanie `rpart` |
| `requireNamespace()` | base R | voliteľná kontrola `rpart.plot` |
| `suppressPackageStartupMessages()` | base R | tiché načítanie plot balíka |
| `file.path()` / `file.exists()` | base R | cache cesta a kontrola |
| `digest::digest()` | `digest` | fingerprint cache |
| `map()` / `set_names()` | `purrr` | pomenovaná iterácia cez tiers |
| `sort()` | base R | stabilné feature poradie |
| `readRDS()` / `saveRDS()` | base R | cache I/O |
| `isTRUE()` | base R | bezpečná validácia fingerprintu |
| `set.seed()` | base R | deterministický RF teacher |
| `match()` | base R | tier-specific seed offset |
| `select()` / `all_of()` | `dplyr` / `tidyselect` | výber teacher feature-ov |
| `randomForest()` | `randomForest` | RF teacher fit |
| `sqrt()` / `floor()` / `max()` | base R | výpočet `mtry` |
| `Sys.time()` / `difftime()` | base R | časovanie |

---

## Chunk: `task4-grid`

### Účel
Naladí surrogate `rpart` strom cez malý grid a vyhodnotí jeho fidelity voči RF teacherovi aj metriky voči ground truth.

### Vysvetlenie kódu
- `tune_surrogate_tree()` dostane tier, RF fit a grid parametrov `maxdepth`, `cp`, `minbucket`.
- `tr_x` a `te_x` sú train/test feature tabuľky pre daný tier.
- `teacher_train` a `teacher_test` sú RF predikcie; tie tvoria target pre surrogate strom.
- `rf_sens` a `rf_spec` sú referenčné RF operating-point hodnoty voči skutočnej label.
- `tr_data$teacher_label <- teacher_train` pridá teacher target do tréningovej tabuľky.
- `crossing(maxdepth, cp, minbucket)` vytvorí celý grid ako tibble.
- `pmap_dfr()` pre každý riadok gridu:
  - vytvorí `key`,
  - fitne `rpart()` strom,
  - predikuje class aj probability na teste,
  - spočíta počet leaves,
  - vypočíta overall fidelity, Sens/Spec vs RF, Sens/Spec vs truth a AUC.
- `deframe()` premení dvojstĺpcový tibble `key`/`tree` na pomenovaný list stromov.
- `load_surrogate()` pridáva cache vrstvu pre celý tuned surrogate objekt; jej fingerprint obsahuje aj digest RF teachera, takže sa grid preráta pri zmene teacher modelu.
- `surr_lex`, `surr_full` a `all_surr` sú hotové výsledky pre Lexical a FullLite.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `select()` / `all_of()` | `dplyr` / `tidyselect` | tier feature-y |
| `predict()` | stats/randomForest/rpart | teacher a tree predikcie |
| `mean()` | base R | fidelity a Sens/Spec |
| `crossing()` | `tidyr` | grid hyperparametrov |
| `pmap_dfr()` | `purrr` | iterácia cez grid do tibble |
| `sprintf()` | base R | stabilný key pre strom |
| `rpart()` | `rpart` | fit surrogate stromu |
| `rpart.control()` | `rpart` | nastavenie maxdepth/cp/minbucket |
| `sum()` | base R | počet listov |
| `roc_auc_vec()` | `yardstick` | AUC bez `pROC` |
| `tibble()` | `tibble` | výsledok jednej grid kombinácie |
| `list()` | base R | uloženie stromu v list-column |
| `deframe()` | `tibble` | pomenovaný list stromov |
| `bind_rows()` | `dplyr` | spojenie Lexical/FullLite výsledkov |
| `digest::digest()` | `digest` | fingerprint surrogate cache vrátane RF teachera |
| `readRDS()` / `saveRDS()` | base R | surrogate cache |

---

## Chunk: `task4-depth-curve`

### Účel
Vyrobí tabuľku najlepšieho surrogate stromu pre každý `maxdepth` a porovná jeho AUC s RF reference AUC.

### Vysvetlenie kódu
- `rf_ref` ručne zoberie RF AUC/Sens/Spec pre Lexical a FullLite z výsledku `res_rf`.
- `all_surr %>% group_by(tier, maxdepth)` rozdelí grid výsledky podľa tier a hĺbky.
- `arrange(desc(fidelity), leaves, .by_group = TRUE) %>% slice_head(n = 1)` vyberá najvyššiu fidelity a pri ties preferuje menej leaves.
- `left_join(rf_ref, by = "tier")` doplní RF reference metriky.
- `transmute()` vytvorí finálnu tabuľku s readable názvami stĺpcov a zaokrúhlením.
- `depth_tbl` sa vypíše cez `kable()` s captionom vysvetľujúcim fidelity a per-class decomposition.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `tibble()` | `tibble` | RF reference tabuľka |
| `group_by()` | `dplyr` | skupiny tier × depth |
| `arrange()` / `desc()` | `dplyr` | výber najlepšej fidelity |
| `slice_head()` | `dplyr` | prvý riadok po zoradení |
| `ungroup()` | `dplyr` | zrušenie groupingu |
| `left_join()` | `dplyr` | doplnenie RF metrík |
| `mutate()` | `dplyr` | poradie tiers |
| `factor()` | base R | explicitné poradie |
| `transmute()` | `dplyr` | finálny tvar tabuľky |
| `round()` | base R | zaokrúhlenie |
| `kable()` | `knitr` | HTML výpis depth tabuľky |

---

## Chunk: `task4-winners`

### Účel
Vyberie jeden strom na vykreslenie pre každý tier: najvyššia fidelity pri cap-e `leaves <= 15`.

### Vysvetlenie kódu
- `MAX_PLOT_LEAVES <- 15L` nastaví readability limit.
- `filter(leaves <= MAX_PLOT_LEAVES)` odstráni príliš veľké stromy.
- `group_by(tier)` vyberá winner zvlášť pre Lexical a FullLite.
- `slice_max(fidelity, ..., with_ties = TRUE)` ponechá všetky najlepšie fidelity ties.
- `slice_min(leaves, ..., with_ties = FALSE)` z týchto ties vyberie menší strom.
- Výstupná tabuľka zaokrúhli fidelity, Sens/Spec a AUC stĺpce, vyberie parametre winner stromu a vypíše ich cez `kable()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `filter()` | `dplyr` | readability cap |
| `group_by()` / `ungroup()` | `dplyr` | výber winnera per tier |
| `slice_max()` / `slice_min()` | `dplyr` | najvyššia fidelity, najmenej leaves |
| `mutate()` / `across()` | `dplyr` | zaokrúhlenie metrík |
| `select()` | `dplyr` | finálne stĺpce |
| `round()` | base R | formátovanie |
| `kable()` | `knitr` | HTML výpis winner tabuľky |

---

## Chunk: `task4-tree-lexical`

### Účel
Vykreslí víťazný surrogate strom pre Lexical tier.

### Vysvetlenie kódu
- `winners %>% filter(tier == "Lexical")` vyberie riadok winnera.
- `transmute(key = sprintf(...))` z parametrov stromu rekonštruuje cache key.
- `pull(key)` vytiahne key ako scalar.
- `tree_lex <- surr_lex$trees[[key_lex]]` vyberie fitted `rpart` objekt.
- Ak existuje `rpart.plot`, použije sa `rpart.plot::rpart.plot()` s farebnou paletou a fidelity v titulku.
- Inak sa použije fallback cez base `plot()` a `text()`.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `filter()` | `dplyr` | výber Lexical winnera |
| `transmute()` | `dplyr` | zostavenie key |
| `sprintf()` | base R | formát key/titulku |
| `pull()` | `dplyr` | získanie key |
| `rpart.plot::rpart.plot()` | `rpart.plot` | pekný stromový diagram |
| `plot()` / `text()` | graphics/base R | fallback vykreslenie stromu |

---

## Chunk: `task4-tree-fulllite`

### Účel
Vykreslí víťazný surrogate strom pre FullLite tier.

### Vysvetlenie kódu
- Logika je rovnaká ako pri Lexical strome, ale filtruje sa `tier == "FullLite"`.
- Key sa rekonštruuje z `maxdepth`, `cp` a `minbucket`.
- `tree_full` sa vyberie zo `surr_full$trees`.
- Pri dostupnom `rpart.plot` sa použije detailnejší stromový diagram; inak base fallback.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `filter()` | `dplyr` | výber FullLite winnera |
| `transmute()` | `dplyr` | zostavenie key |
| `sprintf()` | base R | formát key/titulku |
| `pull()` | `dplyr` | získanie key |
| `rpart.plot::rpart.plot()` | `rpart.plot` | pekný stromový diagram |
| `plot()` / `text()` | graphics/base R | fallback vykreslenie stromu |

---

## Chunk: `task4-varimp`

### Účel
Vykreslí RF variable importance pre Lexical a FullLite teacher modely ako cross-check surrogate koreňových splitov.

### Vysvetlenie kódu
- Komentár v chunku vysvetľuje Windows/UTF-8 dôvod, prečo sa v tituloch grafov používa obyčajný hyphen namiesto em-dash.
- `par(mfrow = c(1, 2), mar = c(4, 7, 3, 1))` nastaví dva grafy vedľa seba a širší ľavý okraj pre názvy premenných.
- `randomForest::varImpPlot()` vykreslí top premenné pre Lexical RF a FullLite RF.
- Pri Lexical sa `n.var` obmedzí na `min(10, length(tiers[["Lexical"]]))`, aby sa nepýtalo viac premenných, než tier má.
- `par(op)` obnoví pôvodné grafické nastavenia.

### Použité funkcie
| Funkcia | Balík | Účel |
|---------|-------|------|
| `par()` | graphics | layout grafov a obnovenie nastavení |
| `c()` | base R | grafické parametre |
| `randomForest::varImpPlot()` | `randomForest` | variable importance graf |
| `min()` / `length()` | base R | počet zobrazovaných premenných |

