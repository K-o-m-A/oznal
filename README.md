# Phishing Detection — Capstone Project

R Markdown notebooks (`phishing.rmd`, `scenario_2.rmd`) plus a Shiny
application (`app.R`) for interactive model exploration.

## Run the Shiny app

```powershell
Rscript requirements.R
Rscript -e "shiny::runApp('app.R', launch.browser = TRUE)"
```

The app expects `PhiUSIIL_Phishing_URL_Dataset.csv` next to `app.R`
(or upload it from the **Data** sidebar panel).

## What the app does (mirrors `scenario_2.rmd`)

1. **Load & clean** PhiUSIIL CSV — strips BOM, drops EDA-excluded columns
   (IDs, computed scores, redundant binaries, linearly-dependent ratios).
2. **Stratified subsample → 80/20 split → k-fold CV indices** shared
   across every (model × tier) combination so results stay paired.
3. **Tier checkboxes**: `Lexical` / `Trust` / `Behavior` / `FullLite`.
   The dedicated **All** checkbox ticks every tier on; un-ticking it
   leaves the current selection intact.
4. **Model checkboxes**: pick any subset of LogReg-Ridge, LDA, NaiveBayes,
   RandomForest, SVM-RBF, KNN.
5. **Hyperparameter sliders** for each model (λ, ntree/mtry, C/σ, k …).
6. **Refit selected models** button — only fits the (model × tier)
   combinations that are currently selected and shows a progress bar.
7. **Outputs** (auto-update as the tier filter changes):
   - `Summary table` — CV ROC ± SD, Train AUC, Test AUC, gap, accuracy, F1, fit time.
   - `AUC by tier` — bar plot grouped by family (parametric vs non-param).
   - `Quality @ 0.5` — Accuracy / F1 / Precision / Sens / Spec at the default 0.5 threshold.
   - `ROC curves` — held-out test ROC per model, faceted by tier.
   - `Wilcoxon (H1)` — per-tier paired Wilcoxon (non-param > param).
   - `Data preview` — split sizes and the first 50 training rows.

## Files

| File                         | Purpose                              |
|------------------------------|--------------------------------------|
| `phishing.rmd`               | EDA notebook                         |
| `scenario_2.rmd`             | Scenario 2 modelling notebook        |
| `app.R`                      | Shiny application                    |
| `requirements.R`             | Installs all R packages              |
| `scenario_2/artifacts/*.rds` | Cached fits used by `scenario_2.rmd` |
