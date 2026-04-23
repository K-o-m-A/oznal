# Headless smoke test for app.R: source helpers, load tiny subsample,
# run one fit per model on a single tier, verify the result schema.
source("app.R", echo = FALSE, local = FALSE)

# Stop the shinyApp() call from launching (it returns an app object — fine).
cat("Sourced app.R; helpers loaded.\n")

ds <- default_dataset_path()
stopifnot(!is.na(ds))
df <- load_and_clean(ds)
cat(sprintf("Loaded %d rows × %d cols\n", nrow(df), ncol(df)))

splits <- make_splits(df, n_sub = 2000, p_train = 0.8, k_folds = 3)
cat(sprintf("Splits: train=%d test=%d folds=%d\n",
            nrow(splits$train_raw), nrow(splits$test_raw),
            length(splits$fold_idx)))

tiers_def <- build_tiers()
params <- list(
  lr_alpha = 0, lr_lambda = 0.01,
  nb_fL = 1, nb_adjust = 1,
  rf_ntree = 50, rf_mtry = 3,
  svm_C = 1, svm_sigma = 0.1,
  knn_k = 15
)

for (m in c("lr","lda","nb","rf","svm","knn")) {
  t0 <- Sys.time()
  r <- tryCatch(
    fit_model_for_tier(m, tiers_def[["Lexical"]], splits, params),
    error = function(e) { cat("FAIL", m, ":", conditionMessage(e), "\n"); NULL }
  )
  if (!is.null(r)) {
    cat(sprintf("OK  %-3s  test_auc=%.4f  acc=%.4f  f1=%.4f  in %.1fs\n",
                m, r$test_auc, r$test_acc, r$test_f1,
                as.numeric(difftime(Sys.time(), t0, units="secs"))))
  }
}
cat("Smoke test complete.\n")

