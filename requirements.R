# R package dependencies for the Shiny app and scenario_2 notebook.
# Install with:  Rscript requirements.R
pkgs <- c(
  "shiny", "DT", "tidyverse", "caret", "glmnet", "MASS", "klaR",
  "randomForest", "kernlab", "pROC", "digest", "rpart", "rpart.plot",
  "e1071", "ggrepel", "shinyjs", "callr"
)
to_install <- setdiff(pkgs, rownames(installed.packages()))
if (length(to_install)) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
}
invisible(lapply(pkgs, function(p) suppressPackageStartupMessages(
  library(p, character.only = TRUE)
)))
cat("All packages OK.\n")

