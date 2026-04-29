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

message("[winner] building splits (n_sub=10000, p_train=0.8, k=10)")
splits <- make_splits(df, n_sub = 10000, p_train = 0.8, k_folds = 10)

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
