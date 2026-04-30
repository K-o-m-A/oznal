# R package dependencies for the Shiny app and modelling notebooks.
# Install with:  Rscript requirements.R
pkgs <- c(
  "shiny", "DT", "tidyverse", "caret", "glmnet", "MASS", "klaR",
  "randomForest", "kernlab", "pROC", "digest", "rpart", "rpart.plot",
  "e1071", "ggrepel", "shinyjs", "callr",
  "ggcorrplot", "yardstick", "scales", "knitr", "rmarkdown"
)
# Use repos from R options if set (e.g. PPM in Docker), else fall back to CRAN.
repos <- getOption("repos")
if (is.null(repos) || identical(unname(repos["CRAN"]), "@CRAN@")) {
  repos <- c(CRAN = "https://cloud.r-project.org")
}
to_install <- setdiff(pkgs, rownames(installed.packages()))
if (length(to_install)) {
  install.packages(to_install, repos = repos)
}
invisible(lapply(pkgs, function(p) suppressPackageStartupMessages(
  library(p, character.only = TRUE)
)))
cat("All packages OK.\n")

