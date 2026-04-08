# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

R-based capstone project for phishing URL detection. The work is split across phases:
1. **EDA + hypothesis design** — `phishing.rmd` (current phase)
2. **Modeling** — classification models, feature selection, Shiny app, executive summary (planned)

## Working with the Notebook

Render the R Notebook to HTML:
```r
rmarkdown::render("phishing.rmd")
```

Or knit from within RStudio. The output is `phishing.nb.html`.

## Dataset

`PhiUSIIL_Phishing_URL_Dataset.csv` — has a UTF-8 BOM on the first column name (`FILENAME`). The notebook strips it via `str_replace(.x, "^\\ufeff", "")`.

- Target column: `label` (0 = legitimate, 1 = phishing)
- ~54 features covering lexical URL structure, trust/consistency signals, and page behavior
- Exclude from modeling: `FILENAME`, `URL`, `Domain`, `TLD`, `Title`, `label`, `label_bin`

## Architecture

The `phishing.rmd` notebook is the single source of truth. All preprocessing, EDA, and (future) modeling lives there. Features are organized into three families:

- **Lexical**: URL length, subdomains, digit/special-char ratios, etc.
- **Trust**: similarity index, TLD probability, domain/title match scores, HTTPS, favicon
- **Behavior**: redirects, iframes, popups, hidden fields, external form submit

## Planned Modeling Scenarios

Two required scenarios for the capstone:
1. **Parametric vs non-parametric** model comparison (logistic regression, LDA, QDA vs. tree-based, KNN, SVM)
2. **Algorithmic vs embedded feature selection** (e.g., RFE vs. LASSO/random forest importance)
