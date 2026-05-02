# =============================================================================
# fit_winner.R - jednorazovo natrénuj víťazný model (SVM-RBF na Lexical tieri)
# a ulož bohatý artefakt artifacts/winner_svm_lexical.rds, ktorý "Winner showcase"
# tab v app.R číta pri štarte.
#
# Spúšťa sa z Windows R / RStudio:
#   setwd("C:/Users/frede/PycharmProjects/oznal-project")
#   source("fit_winner.R")
# =============================================================================

suppressPackageStartupMessages({
  source("fit_core.R")
})

set.seed(2026)

ARTIFACTS_DIR <- "artifacts"
if (!dir.exists(ARTIFACTS_DIR)) dir.create(ARTIFACTS_DIR, showWarnings = FALSE)
WINNER_PATH <- file.path(ARTIFACTS_DIR, "winner_svm_lexical.rds")

dataset_path <- default_dataset_path()
if (is.na(dataset_path))
  stop("PhiUSIIL_Phishing_URL_Dataset.csv not found in project root or parent.")

message("[winner] loading dataset: ", dataset_path)
df <- load_and_clean(dataset_path)

message("[winner] building splits (n_sub=30000, p_train=0.8, k=10)")
splits <- make_splits(df, n_sub = 30000, p_train = 0.8, k_folds = 10)

tiers <- build_tiers()
lex   <- tiers$Lexical
message("[winner] lexical features (", length(lex), "): ",
        paste(lex, collapse = ", "))

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
message(sprintf("[winner] fit done in %.1fs", elapsed))

te         <- splits$test_std[, c("label", lex)]
test_prob  <- predict(fit, te, type = "prob")[, "Phishing"]
test_label <- te$label
roc_obj    <- pROC::roc(test_label, test_prob,
                        levels = c("Legitimate", "Phishing"),
                        direction = "<", quiet = TRUE)
message(sprintf("[winner] test AUC = %.4f", as.numeric(roc_obj$auc)))

# Pre-fit a (C, sigma) grid so the Winner showcase tab in app.R can switch
# hyperparameters via O(1) lookup instead of refitting on each slider drag.
# Single fit per cell (no CV) - same eval as the headline model, ~30s each.
#
# sigma > 0.1 was dropped: kernlab's class-prob calc fails ("line search
# fails") at high sigma + low C on this data, returning NAs and breaking the
# downstream ROC. Combos below all converged in prior runs.
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
    auc_i <- as.numeric(pROC::roc(
      splits$test_std$label, prob_i,
      levels = c("Legitimate", "Phishing"), direction = "<", quiet = TRUE)$auc)
    list(test_prob = prob_i, test_auc = auc_i)
  }, error = function(e) {
    message(sprintf("[grid %2d/%d] C=%-5g sigma=%-6g SKIPPED: %s",
                    i, n_combos, C_val, s_val, conditionMessage(e)))
    NULL
  })
  if (!is.null(cell)) {
    hp_results[[key]] <- cell
    message(sprintf("[grid %2d/%d] C=%-5g sigma=%-6g AUC=%.4f (%.1fs)",
                    i, n_combos, C_val, s_val, cell$test_auc,
                    as.numeric(difftime(Sys.time(), ti, units = "secs"))))
  }
}
message(sprintf("[winner] grid done in %.1fs (%d/%d combos succeeded)",
                as.numeric(difftime(Sys.time(), g0, units = "secs")),
                length(hp_results), n_combos))

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

# pp restricted to Lexical features only. Per-column center/scale is
# independent so this gives bit-for-bit identical standardization to the
# full-dataset pp used during training, but the bundle stays self-contained.
pp_continuous <- intersect(splits$continuous_features, lex)
pp_binary     <- intersect(splits$binary_features,     lex)

train_lex_log <- splits$train_raw[, lex, drop = FALSE]
train_lex_log[pp_continuous] <- lapply(train_lex_log[pp_continuous],
                                       function(x) log1p(pmax(x, 0)))
pp <- caret::preProcess(train_lex_log[, pp_continuous, drop = FALSE],
                        method = c("center", "scale"))

bundle <- list(
  fit            = fit,
  pp             = pp,
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

invisible(bundle)
