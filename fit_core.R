# =============================================================================
# fit_core.R - shared fit logic + project metadata
# Sourced by both app.R (foreground) and the background callr::r_bg worker.
# Must NOT depend on shiny.
# =============================================================================

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

# -----------------------------------------------------------------------------
# Static project metadata (mirrors scenario_2.rmd S2.2 and S2.3)
# -----------------------------------------------------------------------------

ID_COLS          <- c("FILENAME", "URL", "Domain", "TLD", "Title")
SCORES           <- c("URLSimilarityIndex", "TLDLegitimateProb", "URLCharProb",
                      "DomainTitleMatchScore", "URLTitleMatchScore")
REDUNDANT_BINARY <- "HasObfuscation"
RATIOS           <- c("LetterRatioInURL", "DegitRatioInURL",
                      "ObfuscationRatio", "SpacialCharRatioInURL")
EXCLUDE_COLS     <- c(ID_COLS, SCORES, REDUNDANT_BINARY, RATIOS)

family_map <- tribble(
  ~feature,                     ~family,
  "URLLength",                  "Lexical",
  "DomainLength",               "Lexical",
  "IsDomainIP",                 "Lexical",
  "CharContinuationRate",       "Lexical",
  "TLDLength",                  "Lexical",
  "NoOfSubDomain",              "Lexical",
  "NoOfObfuscatedChar",         "Lexical",
  "NoOfLettersInURL",           "Lexical",
  "NoOfDegitsInURL",            "Lexical",
  "NoOfEqualsInURL",            "Lexical",
  "NoOfQMarkInURL",             "Lexical",
  "NoOfAmpersandInURL",         "Lexical",
  "NoOfOtherSpecialCharsInURL", "Lexical",
  "IsHTTPS",                    "Trust",
  "HasTitle",                   "Trust",
  "HasFavicon",                 "Trust",
  "Robots",                     "Trust",
  "Bank",                       "Trust",
  "Pay",                        "Trust",
  "Crypto",                     "Trust",
  "LineOfCode",                 "Behavior",
  "LargestLineLength",          "Behavior",
  "IsResponsive",               "Behavior",
  "NoOfURLRedirect",            "Behavior",
  "NoOfSelfRedirect",           "Behavior",
  "HasDescription",             "Behavior",
  "NoOfPopup",                  "Behavior",
  "NoOfiFrame",                 "Behavior",
  "HasExternalFormSubmit",      "Behavior",
  "HasSocialNet",               "Behavior",
  "HasSubmitButton",            "Behavior",
  "HasHiddenFields",            "Behavior",
  "HasPasswordField",           "Behavior",
  "HasCopyrightInfo",           "Behavior",
  "NoOfImage",                  "Behavior",
  "NoOfCSS",                    "Behavior",
  "NoOfJS",                     "Behavior",
  "NoOfSelfRef",                "Behavior",
  "NoOfEmptyRef",               "Behavior",
  "NoOfExternalRef",            "Behavior"
)

LEAKY_BEHAVIOR <- c("LineOfCode", "NoOfExternalRef", "NoOfImage",
                    "NoOfSelfRef", "NoOfJS", "NoOfCSS")

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
  "NaiveBayes"   = "nb",
  "RandomForest" = "rf",
  "SVM-RBF"      = "svm",
  "KNN"          = "knn"
)

MODEL_FAMILY <- c(
  lr  = "parametric",
  lda = "parametric",
  nb  = "parametric",
  rf  = "non-parametric",
  svm = "non-parametric",
  knn = "non-parametric"
)

# -----------------------------------------------------------------------------
# Data loading + splits (used only in the foreground / Shiny side)
# -----------------------------------------------------------------------------

default_dataset_path <- function() {
  candidates <- c("PhiUSIIL_Phishing_URL_Dataset.csv",
                  "../PhiUSIIL_Phishing_URL_Dataset.csv")
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[1] else NA_character_
}

load_and_clean <- function(path) {
  raw <- read_csv(path, show_col_types = FALSE)
  names(raw)[1] <- sub("^\xef\xbb\xbf", "", names(raw)[1], useBytes = TRUE)
  raw %>%
    mutate(label = factor(label, levels = c(1, 0),
                          labels = c("Phishing", "Legitimate"))) %>%
    select(-all_of(EXCLUDE_COLS)) %>%
    as.data.frame()
}

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

# -----------------------------------------------------------------------------
# Per-tier fit (called from background process)
# -----------------------------------------------------------------------------

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
  train_pred <- predict(fit, tr)
  train_auc  <- as.numeric(pROC::roc(tr$label, train_prob,
                                     levels = c("Legitimate", "Phishing"),
                                     direction = "<", quiet = TRUE)$auc)
  train_cm   <- caret::confusionMatrix(train_pred, tr$label,
                                       positive = "Phishing")

  list(
    cv_per_fold = fit$resample,
    train_auc   = train_auc,
    train_acc   = unname(train_cm$overall["Accuracy"]),
    test_auc    = test_auc,
    test_acc    = unname(cm$overall["Accuracy"]),
    test_f1     = unname(cm$byClass["F1"]),
    test_prec   = unname(cm$byClass["Precision"]),
    test_sens   = unname(cm$byClass["Sensitivity"]),
    test_spec   = unname(cm$byClass["Specificity"]),
    train_secs  = elapsed,
    roc_points  = {
      r <- pROC::roc(te$label, test_prob,
                     levels = c("Legitimate", "Phishing"),
                     direction = "<", quiet = TRUE)
      tibble(fpr = 1 - r$specificities, tpr = r$sensitivities)
    }
  )
}

jitter_features <- function(d, cols, sd = 1e-3) {
  for (c in cols) d[[c]] <- d[[c]] + rnorm(nrow(d), 0, sd)
  d
}

fit_model_for_tier <- function(model_id, tier_features, splits, params) {
  switch(model_id,
    lr  = fit_one_tier(tier_features, splits$train_std, splits$test_std,
                       splits$fold_idx, method = "glmnet",
                       tuneGrid = data.frame(alpha  = params$lr_alpha,
                                             lambda = params$lr_lambda)),
    lda = fit_one_tier(tier_features, splits$train_std, splits$test_std,
                       splits$fold_idx, method = "lda"),
    nb  = suppressWarnings(fit_one_tier(
            tier_features, splits$train_std, splits$test_std,
            splits$fold_idx, method = "nb",
            tuneGrid = data.frame(fL = params$nb_fL,
                                  usekernel = TRUE,
                                  adjust = params$nb_adjust))),
    rf  = fit_one_tier(tier_features, splits$train_raw, splits$test_raw,
                       splits$fold_idx, method = "rf",
                       tuneGrid = data.frame(
                         mtry = max(1, min(params$rf_mtry,
                                           length(tier_features)))),
                       ntree = params$rf_ntree),
    svm = fit_one_tier(tier_features, splits$train_std, splits$test_std,
                       splits$fold_idx, method = "svmRadial",
                       tuneGrid = data.frame(C     = params$svm_C,
                                             sigma = params$svm_sigma)),
    knn = {
      tr_j <- jitter_features(splits$train_std, tier_features)
      te_j <- jitter_features(splits$test_std,  tier_features)
      fit_one_tier(tier_features, tr_j, te_j, splits$fold_idx,
                   method = "knn",
                   tuneGrid = data.frame(k = params$knn_k))
    }
  )
}

# -----------------------------------------------------------------------------
# Background worker entry point
# Invoked by callr::r_bg(); reads inputs.rds, writes one rds per fitted combo
# plus a progress.rds file the foreground polls.
# -----------------------------------------------------------------------------

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

