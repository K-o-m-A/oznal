# =============================================================================
# Phishing Detection - Scenario 2 Shiny Application
# Async fit via callr::r_bg() so the UI stays responsive AND can be cancelled.
# Mirrors the workflow defined in `scenario_2.rmd`.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(tidyverse)
  library(DT)
  library(ggrepel)
  library(shinyjs)
  library(callr)
  library(rpart)
})

set.seed(2026)

# Allow CSV uploads up to 200 MB (default Shiny limit is 5 MB).
options(shiny.maxRequestSize = 200 * 1024^2)

# Shared fit logic (also sourced by the background worker process).
CORE_PATH <- normalizePath("fit_core.R")
source(CORE_PATH)

# -----------------------------------------------------------------------------
# Persistence + background work directory
# -----------------------------------------------------------------------------
ARTIFACTS_DIR <- "artifacts"
SESSION_FILE  <- file.path(ARTIFACTS_DIR, "app_session.rds")
WORK_DIR      <- file.path(ARTIFACTS_DIR, "app_session")
WINNER_PATH   <- file.path(ARTIFACTS_DIR, "winner_svm_lexical.rds")
if (!dir.exists(ARTIFACTS_DIR)) dir.create(ARTIFACTS_DIR, showWarnings = FALSE)
if (!dir.exists(WORK_DIR))      dir.create(WORK_DIR,      showWarnings = FALSE)

# Pre-fitted winning model bundle (produced by fit_winner.R). NULL if missing
# - the Winner showcase tab degrades gracefully with a hint to run the script.
winner <- if (file.exists(WINNER_PATH))
  tryCatch(readRDS(WINNER_PATH), error = function(e) NULL) else NULL

save_session <- function(results, active_config = NULL) {
  payload <- list(results = results, active_config = active_config)
  tryCatch(saveRDS(payload, SESSION_FILE), error = function(e) NULL)
}
load_session <- function() {
  if (!file.exists(SESSION_FILE))
    return(list(results = list(), active_config = NULL))
  payload <- tryCatch(readRDS(SESSION_FILE), error = function(e) NULL)
  if (is.null(payload))
    return(list(results = list(), active_config = NULL))
  # Backward compat: older saves stored the results list directly.
  if (!is.list(payload) || !"results" %in% names(payload))
    return(list(results = payload, active_config = NULL))
  payload
}
clear_workdir <- function() {
  files <- list.files(WORK_DIR, full.names = TRUE)
  if (length(files)) unlink(files, force = TRUE)
}

# Transform a one-row data.frame of RAW lexical feature values into the
# standardized space the SVM-RBF was trained on. Mirrors fit_core.R:148-160.
winner_transform <- function(raw_row, w) {
  for (c in w$pp_continuous)
    raw_row[[c]] <- log1p(pmax(raw_row[[c]], 0))
  if (length(w$pp_continuous))
    raw_row[, w$pp_continuous] <- predict(
      w$pp, raw_row[, w$pp_continuous, drop = FALSE])
  raw_row[, w$features, drop = FALSE]
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------

ui <- navbarPage(
  title = "Phishing Detection",
  id = "navbar",
  selected = "scenario_2",
  header = tagList(
    useShinyjs(),
    tags$head(tags$style(HTML("
    details.hp-section {
      border: 1px solid #d1d5db;
      border-radius: 6px;
      padding: 4px 10px;
      margin-bottom: 8px;
      background: #f9fafb;
      transition: background 0.15s, border-color 0.15s;
    }
    details.hp-section[open] {
      background: #ffffff;
      border-color: #4C78A8;
      padding-bottom: 8px;
    }
    details.hp-section > summary {
      cursor: pointer;
      font-weight: 600;
      color: #1f2937;
      padding: 6px 2px;
      list-style: none;
      outline: none;
      user-select: none;
    }
    details.hp-section > summary::-webkit-details-marker { display: none; }
    details.hp-section > summary::before {
      content: '\\25B8';
      display: inline-block;
      width: 14px;
      color: #4C78A8;
      transition: transform 0.15s;
    }
    details.hp-section[open] > summary::before {
      transform: rotate(90deg);
    }
    details.hp-section > summary:hover { color: #4C78A8; }
    details.hp-section .form-group { margin-bottom: 6px; }

    .config-panel {
      background: #f0f7ff;
      border-left: 4px solid #4C78A8;
      padding: 10px 14px;
      margin-bottom: 14px;
      border-radius: 4px;
      font-size: 13px;
      line-height: 1.55;
    }
    .config-panel .config-meta { color: #6b7280; font-size: 12px; }
    .config-panel .config-row  { margin-top: 4px; }
    .config-panel .config-model {
      display: inline-block;
      margin-right: 14px;
      margin-bottom: 2px;
    }
    .config-panel .config-model strong { color: #1f2937; }
    .config-panel .config-model code {
      color: #4C78A8;
      background: #e9f0fa;
      padding: 1px 5px;
      border-radius: 3px;
      font-size: 12px;
    }
    .config-panel .config-empty { color: #9ca3af; font-style: italic; }

    .navbar .container-fluid > .navbar-header .navbar-brand { font-weight: 600; }
    .tab-content { padding-top: 12px; }
    "
    )))
  ),

  # ---- EDA tab ------------------------------------------------------------
  # tabPanel("EDA", value = "eda",
  #   uiOutput("eda_data_hint"),
  #   fluidRow(
  #     column(7,
  #       h4("Class balance"),
  #       plotOutput("eda_class_balance", height = "320px")
  #     ),
  #     column(5,
  #       h4("Feature counts per tier"),
  #       tableOutput("eda_tier_counts"),
  #       helpText("Tier definitions from ", code("build_tiers()"),
  #                " in fit_core.R; FullLite drops 6 leaky Behavior features.")
  #     )
  #   ),
  #   hr(),
  #   h5("Split info"),
  #   verbatimTextOutput("split_info"),
  #   br(),
  #   h5("Train head"),
  #   DTOutput("train_head_dt")
  # ),

  # ---- Scenario 2 tab -----------------------------------------------------
  tabPanel("Scenario 2", value = "scenario_2",
    sidebarLayout(
      sidebarPanel(
        width = 4,

        h4("1. Data"),
        fileInput("csv_file", "Upload PhiUSIIL CSV (optional)",
                  accept = c(".csv")),
        helpText("If empty, the app loads ",
                 code("PhiUSIIL_Phishing_URL_Dataset.csv"),
                 " from the working directory. Max upload: 200 MB."),
        actionButton("load_btn", "Load & prepare data",
                     icon = icon("download"),
                     class = "btn-primary"),
        br(), br(),
        verbatimTextOutput("data_status"),

        hr(),
        h4("2. Splits"),
        sliderInput("n_sub", "Stratified subsample size",
                    min = 2000, max = 60000, value = 30000, step = 2000),
        sliderInput("p_train", "Train share",
                    min = 0.5, max = 0.9, value = 0.8, step = 0.05),
        sliderInput("k_folds", "CV folds", min = 3, max = 10, value = 10),

        hr(),
        h4("3. Feature families (tiers)"),
        checkboxInput("tier_all", strong("All (select every tier)"),
                      value = TRUE),
        checkboxGroupInput("tiers_sel", NULL,
                           choices  = TIERS_ALL,
                           selected = TIERS_ALL),

        hr(),
        h4("4. Models"),
        checkboxInput("model_all", strong("All (select every model)"),
                      value = TRUE),
        checkboxGroupInput("models_sel", NULL,
                           choices  = MODEL_CHOICES,
                           selected = unname(MODEL_CHOICES)),
        helpText("Unchecked models are hidden from all tabs immediately. ",
                 "Press Refit to (re)train the checked ones."),

        hr(),
        h4("5. Hyperparameters"),
        helpText("Click a model to expand its tunable parameters. ",
                 "LDA has no tunable hyperparameters."),
        tags$details(class = "hp-section",
          tags$summary("LogReg-Ridge"),
          sliderInput("lr_alpha",  "alpha (0=ridge,1=lasso)",
                      0, 1, 0, step = 0.05),
          sliderInput("lr_lambda", "lambda",
                      0, 1, 0.01, step = 0.005)
        ),
        tags$details(class = "hp-section",
          tags$summary("NaiveBayes"),
          sliderInput("nb_fL",     "Laplace smoothing fL", 0, 5, 1, step = 0.5),
          sliderInput("nb_adjust", "Kernel bandwidth adjust",
                      0.5, 3, 1, step = 0.1)
        ),
        tags$details(class = "hp-section",
          tags$summary("RandomForest"),
          sliderInput("rf_ntree", "ntree",  50, 800, 300, step = 50),
          sliderInput("rf_mtry",  "mtry (capped at #features)",
                      1, 20, 5, step = 1)
        ),
        tags$details(class = "hp-section",
          tags$summary("SVM-RBF"),
          sliderInput("svm_C",     "Cost C",     0.1, 10, 1, step = 0.1),
          sliderInput("svm_sigma", "RBF sigma", 0.01, 1, 0.1, step = 0.01)
        ),
        tags$details(class = "hp-section",
          tags$summary("KNN"),
          sliderInput("knn_k", "k", 1, 75, 25, step = 2)
        ),

        hr(),
        actionButton("refit_btn", "Refit selected models",
                     icon = icon("play"),
                     class = "btn-success btn-block"),
        actionButton("cancel_btn", "Cancel running fit",
                     icon = icon("stop"),
                     class = "btn-warning btn-block",
                     style = "margin-top:6px;"),
        actionButton("clear_btn", "Clear cached results",
                     icon = icon("trash"),
                     class = "btn-outline-danger btn-block",
                     style = "margin-top:6px;"),
        helpText("Fit runs in a background R process - the UI stays responsive ",
                 "and you can hit Cancel anytime. Results persist across page ",
                 "refreshes (cached in artifacts/app_session.rds)."),
        br(),
        div(style = "padding:8px;background:#F4F8FB;border-left:3px solid #4C78A8;",
            strong("Status:"), br(),
            verbatimTextOutput("fit_status", placeholder = TRUE))
      ),

      mainPanel(
        width = 8,
        uiOutput("active_config_panel"),
        tabsetPanel(
          id = "s2_tabs",
          tabPanel("Summary table",
            br(),
            DTOutput("summary_dt"),
            helpText(strong("Full overview"),
                     ": CV AUC (mean+/-SD across folds), Train vs Test AUC, ",
                     "train-test Gap (overfit indicator), and threshold-0.5 ",
                     "metrics. Sensitivity / Specificity highlighted - they ",
                     "drive the corporate-proxy decision (cf. scenario_2.rmd S6.1.1).")
          ),
          tabPanel("AUC by tier",
            br(),
            plotOutput("auc_plot", height = "520px"),
            helpText("Mean CV ROC across folds with +/- 1 SD error bars. ",
                     "X-axis is zoomed to the data range so small differences ",
                     "are visible.")
          ),
          tabPanel("Quality @ 0.5",
            br(),
            DTOutput("quality_dt"),
            helpText(strong("Stripped-down view"),
                     " of the Summary table: only the classification metrics ",
                     "at the default 0.5 probability threshold (no AUC, no ",
                     "training cost). Useful when you only care about the ",
                     "operating point that would actually ship.")
          ),
          tabPanel("ROC curves",
            br(),
            plotOutput("roc_plot", height = "550px")
          ),
          tabPanel("Sens vs Spec",
            br(),
            plotOutput("sens_spec_plot", height = "550px"),
            helpText("Top-right corner = ideal model (catches all phish AND ",
                     "lets all legit through). Each point is one (model, tier) ",
                     "combination at the default 0.5 threshold.")
          ),
          tabPanel("Wilcoxon (H1)",
            br(),
            helpText("Per-tier paired Wilcoxon (non-parametric > parametric) ",
                     "across CV folds - needs >=1 model from each family selected."),
            DTOutput("wilcox_dt")
          )
        )
      )
    )
  ),

  # ---- Winning Model tab --------------------------------------------------
  tabPanel("Winning Model", value = "winner",
    br(),
    uiOutput("winner_info_card"),
    uiOutput("winner_body")
  ),

  # ---- Scenario 4 tab -----------------------------------------------------
  tabPanel("Scenario 4", value = "scenario_4",
    br(),
    helpText(strong("Task 4 - visualising the RF decision rule."),
             " A single rpart tree trained on the RF's own predictions ",
             "(not the ground-truth label). The metric we optimise is ",
             strong("fidelity = share of test rows on which the tree ",
                    "and the RF agree"),
             "; it is decomposed into ",
             code("Sens vs RF"), " / ", code("Spec vs RF"),
             " so the per-class agreement is visible - same Sens/Spec ",
             "framing we use everywhere else."),
    fluidRow(
      column(4,
        selectInput("task4_tier", "Tier",
                    choices  = c("Lexical", "FullLite"),
                    selected = "Lexical")
      ),
      column(4,
        sliderInput("task4_maxdepth", "Max depth (upper bound)",
                    min = 3, max = 7, value = 7, step = 1)
      ),
      column(4,
        sliderInput("task4_max_leaves", "Readability cap (leaves)",
                    min = 5, max = 30, value = 15, step = 1)
      )
    ),
    verbatimTextOutput("task4_status"),
    plotOutput("task4_tree_plot", height = "520px"),
    br(),
    h5("Selected tree vs RF (per-class agreement + deployment Sens/Spec)"),
    DTOutput("task4_metrics_dt"),
    br(),
    h5("Fidelity saturation - best (cp, minbucket) per depth"),
    DTOutput("task4_depth_dt")
  ),

  # ---- Scenario 3 tab -----------------------------------------------------
  tabPanel("Scenario 3", value = "scenario_3",
    br(),
    helpText(strong("Task 3 - feature-selection comparison."),
             " Compares one algorithmic FS method (bidirectional ",
             "stepwise, AIC) and two embedded ones (lasso alpha=1, ",
             "elastic-net alpha=0.5). The primary result is Lexical ",
             "URL-only; FullLite is kept as a fallback benchmark. ",
             "All numbers come from cached fits in ",
             code("scenario_3/artifacts/"), "; re-knit ",
             code("scenario_3.rmd"), " to refresh."),
    verbatimTextOutput("s3_status"),
    br(),
    h5("Primary Lexical URL-only H2 result (AUC, Sensitivity, Specificity, H2 criteria)"),
    DTOutput("s3_h2_dt"),
    helpText("Final fits scored on the held-out 20% test split. AUC checks ",
             "ranking; Sensitivity and Specificity check the threshold-0.5 ",
             "operating point. C1/C2/C3 columns track the H2 criteria."),
    br(),
    h5("Selected predictors per method"),
    DTOutput("s3_d1_dt"),
    helpText("x = retained by the FS method; blank = dropped."),
    br(),
    h5("Stepwise: p-value audit along the AIC path"),
    DTOutput("s3_step_path_dt"),
    helpText("Per-predictor audit of the two-sided z-test p-value across ",
             "stepAIC steps: first/last step active, min/max/final p, and ",
             "a flag for any movement across the 0.05 line. This is an ",
             "audit of the selected logistic GLM, not a performance curve."),
    br(),
    h5("Lasso / Elastic-Net: coefficients retained at lambda.1se"),
    plotOutput("s3_embedded_coef_plot", height = "450px"),
    helpText("Only non-zero coefficients are shown; zero means the feature ",
             "was dropped by that embedded method."),
    br(),
    h5("Lasso / Elastic-Net: largest lambda where each predictor is active"),
    DTOutput("s3_embedded_lambda_dt"),
    helpText("Larger value = retained under stronger regularisation. ",
             "'(never)' means the feature never enters the path. ",
             "Elastic-net tends to keep groups of correlated URL predictors ",
             "instead of dropping them as aggressively as lasso."),
    br(),
    h5("Secondary FullLite fallback predictor counts (10 outer CV folds)"),
    plotOutput("s3_perfold_plot", height = "350px"),
    helpText("Fallback-only diagnostic: selected-predictor counts on the 34-feature FullLite pool. ",
             "This is not the primary Lexical Task 3 claim."),
    br(),
    h5("Secondary FullLite fallback predictor counts"),
    DTOutput("s3_perfold_dt"),
    helpText("Per-fold selected-predictor counts for stepwise, lasso and elastic-net."),
    br(),
    h5("Average selected-predictor count across folds"),
    DTOutput("s3_fulllite_mean_dt"),
    helpText("One-decimal mean k values across the 10 CV folds. "),
    br(),
    h5("FullLite selection frequency across folds"),
    DTOutput("s3_fulllite_freq_dt")
  )
)

# -----------------------------------------------------------------------------
# Server
# -----------------------------------------------------------------------------

server <- function(input, output, session) {

  cached_session <- load_session()
  rv <- reactiveValues(
    df             = NULL,
    splits         = NULL,
    splits_params  = NULL,                    # params used to build rv$splits
    results        = cached_session$results,
    active_config  = cached_session$active_config,  # snapshot at last Refit
    last_err       = NULL,
    fit_status     = {
      n0 <- length(cached_session$results)
      if (n0) sprintf("Loaded %d cached fit(s) from %s.", n0, SESSION_FILE)
      else "No fitted models yet - press Refit."
    },
    is_fitting   = FALSE,
    bg_proc      = NULL,
    bg_total     = 0L,
    bg_collected = character(0)  # absolute paths of res_*.rds already pulled
  )

  # ---- Tier <-> All sync ----------------------------------------------------
  # "All" acts as a toggle: ticking selects every tier, unticking clears all.
  observeEvent(input$tier_all, {
    if (isTRUE(input$tier_all)) {
      updateCheckboxGroupInput(session, "tiers_sel", selected = TIERS_ALL)
    } else if (length(input$tiers_sel) == length(TIERS_ALL)) {
      updateCheckboxGroupInput(session, "tiers_sel",
                               selected = character(0))
    }
  })
  observeEvent(input$tiers_sel, {
    is_all <- setequal(input$tiers_sel, TIERS_ALL)
    if (is_all != isTRUE(input$tier_all)) {
      updateCheckboxInput(session, "tier_all", value = is_all)
    }
  }, ignoreNULL = FALSE)

  # ---- Model <-> All sync ---------------------------------------------------
  # "All" acts as a toggle: ticking selects every model, unticking clears all.
  observeEvent(input$model_all, {
    if (isTRUE(input$model_all)) {
      updateCheckboxGroupInput(session, "models_sel",
                               selected = unname(MODEL_CHOICES))
    } else if (length(input$models_sel) == length(MODEL_CHOICES)) {
      updateCheckboxGroupInput(session, "models_sel",
                               selected = character(0))
    }
  })
  observeEvent(input$models_sel, {
    is_all <- setequal(input$models_sel, unname(MODEL_CHOICES))
    if (is_all != isTRUE(input$model_all)) {
      updateCheckboxInput(session, "model_all", value = is_all)
    }
  }, ignoreNULL = FALSE)

  # ---- Cache controls ------------------------------------------------------
  observeEvent(input$clear_btn, {
    rv$results       <- list()
    rv$active_config <- NULL
    rv$fit_status    <- "Cache cleared. Press Refit to retrain."
    save_session(list(), NULL)
    clear_workdir()
    showNotification("Cleared cached fit results.", type = "message")
  })

  # ---- Data load -----------------------------------------------------------
  observeEvent(input$load_btn, {
    rv$last_err <- NULL
    path <- if (!is.null(input$csv_file))
      input$csv_file$datapath else default_dataset_path()
    if (is.na(path) || !file.exists(path)) {
      rv$last_err <- "Dataset CSV not found. Upload one or place it in the project root."
      return()
    }
    withProgress(message = "Loading & cleaning dataset...", value = 0.3, {
      rv$df <- load_and_clean(path)
      incProgress(0.5, detail = sprintf("%d rows loaded", nrow(rv$df)))
      rv$splits        <- make_splits(rv$df, input$n_sub, input$p_train,
                                      input$k_folds)
      rv$splits_params <- list(n_sub = input$n_sub, p_train = input$p_train,
                               k_folds = input$k_folds)
    })
    rv$results       <- list()
    rv$active_config <- NULL
    save_session(list(), NULL); clear_workdir()
  })

  # NB: split sliders no longer auto-resplit / wipe results. Splits are
  # rebuilt at Refit time so currently-displayed fits stay visible while the
  # user is just exploring different settings.

  output$data_status <- renderText({
    if (!is.null(rv$last_err)) return(paste("ERROR:", rv$last_err))
    if (is.null(rv$df))        return("No data loaded yet.")
    sprintf("Loaded %d rows x %d cols (after EDA exclusions: %d predictors).",
            nrow(rv$df), ncol(rv$df), ncol(rv$df) - 1)
  })

  output$split_info <- renderText({
    s <- rv$splits
    if (is.null(s)) return("Load data first.")
    sprintf(paste(
      "Train: %d rows", "Test: %d rows", "CV folds: %d",
      "Continuous features: %d  |  Binary features: %d", sep = "\n"),
      nrow(s$train_raw), nrow(s$test_raw), length(s$fold_idx),
      length(s$continuous_features), length(s$binary_features))
  })

  output$train_head_dt <- renderDT({
    s <- rv$splits
    if (is.null(s)) return(NULL)
    datatable(head(s$train_raw, 50), options = list(scrollX = TRUE, dom = "tip"))
  })

  # ---- EDA tab outputs -----------------------------------------------------
  output$eda_data_hint <- renderUI({
    if (!is.null(rv$df)) return(NULL)
    div(class = "config-panel",
        strong("Data nie su nahrane. "),
        span(class = "config-meta",
             "Otvor tab ", tags$code("Scenario 2"),
             " a klikni na ", tags$code("Load & prepare data"),
             ". EDA grafy sa potom vykreslia automaticky."))
  })

  output$eda_class_balance <- renderPlot({
    req(rv$df)
    rv$df %>%
      count(label) %>%
      mutate(pct = n / sum(n)) %>%
      ggplot(aes(label, n, fill = label)) +
      geom_col(width = 0.6, show.legend = FALSE) +
      geom_text(aes(label = sprintf("%s (%.1f%%)",
                                    format(n, big.mark = ","),
                                    100 * pct)),
                vjust = -0.4, size = 4.4) +
      scale_fill_manual(values = c(Phishing   = "#C62828",
                                   Legitimate = "#2E7D32")) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
      labs(x = NULL, y = "Pocet URL") +
      theme_minimal(base_size = 13)
  })

  output$eda_tier_counts <- renderTable({
    req(rv$df)
    tiers <- build_tiers()
    tibble(
      Tier     = names(tiers),
      Features = vapply(tiers, length, integer(1))
    )
  }, striped = TRUE, bordered = TRUE, align = "lc", digits = 0)

  # ---- REFIT (spawns background worker) ------------------------------------
  observeEvent(input$refit_btn, {
    if (isTRUE(rv$is_fitting)) {
      showNotification("Already fitting - press Cancel first.", type = "warning")
      return()
    }
    if (is.null(rv$df)) {
      showNotification("Load data first.", type = "warning")
      return()
    }
    tiers_active  <- intersect(input$tiers_sel, TIERS_ALL)
    models_active <- intersect(input$models_sel, unname(MODEL_CHOICES))
    if (!length(tiers_active) || !length(models_active)) {
      showNotification("Select at least one tier AND one model.", type = "warning")
      return()
    }

    # Rebuild splits if the slider values drifted from the splits we have on
    # hand. When that happens, any cached results are stale (built on a
    # different train/test partition) so wipe them.
    cur_split_params <- list(n_sub  = input$n_sub,
                             p_train = input$p_train,
                             k_folds = input$k_folds)
    if (is.null(rv$splits) ||
        !identical(rv$splits_params, cur_split_params)) {
      withProgress(message = "Re-splitting (slider values changed)...",
                   value = 0.5, {
        rv$splits        <- make_splits(rv$df, cur_split_params$n_sub,
                                        cur_split_params$p_train,
                                        cur_split_params$k_folds)
        rv$splits_params <- cur_split_params
      })
      if (length(rv$results)) {
        showNotification(paste("Splits changed - cleared previous results",
                               "(they were trained on a different partition)."),
                         type = "warning", duration = 6)
      }
      rv$results       <- list()
      rv$active_config <- NULL
    }

    combos <- expand.grid(model = models_active, tier = tiers_active,
                          stringsAsFactors = FALSE)
    params <- list(
      lr_alpha  = input$lr_alpha,  lr_lambda = input$lr_lambda,
      nb_fL     = input$nb_fL,     nb_adjust = input$nb_adjust,
      rf_ntree  = input$rf_ntree,  rf_mtry   = input$rf_mtry,
      svm_C     = input$svm_C,     svm_sigma = input$svm_sigma,
      knn_k     = input$knn_k
    )

    # Snapshot the configuration this Refit will use. The header panel reads
    # from this snapshot so it always reflects what the displayed tables were
    # actually fit with - not whatever the sidebar sliders happen to show now.
    rv$active_config <- list(
      models   = models_active,
      tiers    = tiers_active,
      splits   = cur_split_params,
      params   = params,
      fit_time = Sys.time()
    )

    # Wipe stale per-combo result files so polling only picks up THIS run's.
    clear_workdir()
    saveRDS(
      list(splits = rv$splits, combos = combos, params = params,
           tiers_def = build_tiers()),
      file.path(WORK_DIR, "inputs.rds")
    )

    # Spawn the background process. r_bg returns immediately.
    proc <- callr::r_bg(
      func = run_fits_bg,
      args = list(work_dir  = normalizePath(WORK_DIR),
                  core_path = CORE_PATH),
      stdout = file.path(WORK_DIR, "stdout.log"),
      stderr = file.path(WORK_DIR, "stderr.log"),
      supervise = TRUE
    )

    rv$bg_proc      <- proc
    rv$bg_total     <- nrow(combos)
    rv$bg_collected <- character(0)
    rv$is_fitting   <- TRUE
    rv$fit_status   <- sprintf(
      "Started background fit: 0/%d combos. UI stays responsive; press Cancel to stop.",
      nrow(combos))

    shinyjs::disable("refit_btn")
    shinyjs::html("refit_btn",
                  '<i class="fa fa-spinner fa-spin"></i> Fitting in background...')
    showNotification(sprintf("Background fit started (%d combos).", nrow(combos)),
                     type = "message")
  })

  # ---- CANCEL --------------------------------------------------------------
  observeEvent(input$cancel_btn, {
    if (!isTRUE(rv$is_fitting) || is.null(rv$bg_proc)) {
      showNotification("Nothing to cancel.", type = "message")
      return()
    }
    tryCatch(rv$bg_proc$kill(), error = function(e) NULL)
    rv$is_fitting <- FALSE
    rv$bg_proc    <- NULL
    rv$fit_status <- sprintf(
      "CANCELLED. Kept %d partial result(s) collected so far.",
      length(rv$bg_collected))
    save_session(reactiveValuesToList(rv)$results, rv$active_config)
    shinyjs::enable("refit_btn")
    shinyjs::html("refit_btn",
                  '<i class="fa fa-play"></i> Refit selected models')
    showNotification("Background fit cancelled.", type = "warning")
  })

  # ---- POLLING: runs every 1.5s while a bg fit is alive --------------------
  observe({
    if (!isTRUE(rv$is_fitting)) return()
    invalidateLater(1500, session)

    proc <- rv$bg_proc
    if (is.null(proc)) return()

    # 1) Read progress file -------------------------------------------------
    prog_file <- file.path(WORK_DIR, "progress.rds")
    if (file.exists(prog_file)) {
      prog <- tryCatch(readRDS(prog_file), error = function(e) NULL)
      if (!is.null(prog)) {
        elapsed <- round(as.numeric(difftime(prog$t_now, prog$t_start,
                                             units = "secs")), 1)
        rv$fit_status <- sprintf(
          "Fitting %d/%d (%s). %.1fs elapsed. %d results collected.",
          prog$i, prog$n, prog$current, elapsed, length(rv$bg_collected))
      }
    }

    # 2) Pick up newly written per-combo result files ----------------------
    res_files <- list.files(WORK_DIR, pattern = "^res_.*\\.rds$",
                            full.names = TRUE)
    new_keys <- character(0)
    for (f in res_files) {
      if (f %in% rv$bg_collected) next
      payload <- tryCatch(readRDS(f), error = function(e) NULL)
      if (is.null(payload)) next
      key <- paste(payload$model, payload$tier, sep = "::")
      if (is.list(payload$res) && !is.null(payload$res$error)) {
        showNotification(sprintf("FAILED: %s / %s - %s",
                                 payload$model, payload$tier,
                                 payload$res$error),
                         type = "error", duration = 10)
      } else if (is.list(payload$res)) {
        rv$results[[key]] <- payload$res
        new_keys <- c(new_keys, key)
      }
      rv$bg_collected <- c(rv$bg_collected, f)
    }
    if (length(new_keys)) {
      save_session(reactiveValuesToList(rv)$results, rv$active_config)
    }

    # 3) Detect completion --------------------------------------------------
    if (!proc$is_alive()) {
      rv$is_fitting <- FALSE
      rv$bg_proc    <- NULL
      rv$fit_status <- sprintf(
        "Done. Collected %d / %d combos. %d results in memory.",
        length(rv$bg_collected), rv$bg_total, length(rv$results))
      save_session(reactiveValuesToList(rv)$results, rv$active_config)
      shinyjs::enable("refit_btn")
      shinyjs::html("refit_btn",
                    '<i class="fa fa-play"></i> Refit selected models')
      showNotification(sprintf("Refit finished (%d/%d).",
                               length(rv$bg_collected), rv$bg_total),
                       type = "message")
    }
  })

  # ---- Outputs --------------------------------------------------------------
  output$fit_status <- renderText({ rv$fit_status })

  selected_model_labels <- reactive({
    ids <- intersect(input$models_sel, unname(MODEL_CHOICES))
    names(MODEL_CHOICES)[match(ids, MODEL_CHOICES)]
  })

  # Active-setup banner shown above every tab. Reads from the snapshot taken
  # at the last Refit (rv$active_config), NOT from live sidebar sliders, so
  # it always describes the configuration the visible tables were fit with.
  # Moving a slider doesn't change this header until the user hits Refit.
  output$active_config_panel <- renderUI({
    cfg <- rv$active_config

    if (is.null(cfg) && !length(rv$results)) {
      return(div(class = "config-panel",
                 strong("Active setup "),
                 span(class = "config-empty",
                      "No fit run yet - adjust the sidebar and press Refit.")))
    }
    if (is.null(cfg)) {
      # Cached results loaded from an older session file with no snapshot.
      return(div(class = "config-panel",
                 strong("Active setup "),
                 span(class = "config-meta",
                      sprintf(paste0("(%d cached result(s) - configuration ",
                                     "snapshot unavailable; press Refit to ",
                                     "refresh)"),
                              length(rv$results)))))
    }

    hp_chip <- function(m_id) {
      label <- names(MODEL_CHOICES)[match(m_id, MODEL_CHOICES)]
      p <- cfg$params
      params <- switch(m_id,
        "lr"  = sprintf("alpha=%.2f, lambda=%.3f", p$lr_alpha, p$lr_lambda),
        "nb"  = sprintf("fL=%.1f, adjust=%.1f",    p$nb_fL,    p$nb_adjust),
        "rf"  = sprintf("ntree=%d, mtry=%d",
                        as.integer(p$rf_ntree), as.integer(p$rf_mtry)),
        "svm" = sprintf("C=%.2f, sigma=%.3f",      p$svm_C,    p$svm_sigma),
        "knn" = sprintf("k=%d",                    as.integer(p$knn_k)),
        "lda" = "no tunable hyperparameters",
        "—"
      )
      span(class = "config-model",
           strong(paste0(label, ":")), " ", tags$code(params))
    }

    meta <- sprintf(paste0("%d model(s) x %d tier(s) | n_sub=%s, ",
                           "train=%.0f%%, k=%d folds"),
                    length(cfg$models), length(cfg$tiers),
                    format(cfg$splits$n_sub, big.mark = ","),
                    100 * cfg$splits$p_train, cfg$splits$k_folds)

    fit_age <- if (!is.null(cfg$fit_time))
      sprintf(" - fit at %s", format(cfg$fit_time, "%H:%M:%S"))
    else ""

    div(class = "config-panel",
        strong("Active setup "),
        span(class = "config-meta", sprintf("(%s%s)", meta, fit_age)),
        div(class = "config-row", lapply(cfg$models, hp_chip)))
  })

  results_long <- reactive({
    if (!length(rv$results)) return(NULL)
    map_dfr(names(rv$results), function(key) {
      r <- rv$results[[key]]
      if (is.null(r)) return(NULL)
      parts <- strsplit(key, "::", fixed = TRUE)[[1]]
      m_id <- parts[1]; tier <- parts[2]
      tibble(
        model       = names(MODEL_CHOICES)[match(m_id, MODEL_CHOICES)],
        model_id    = m_id,
        family      = MODEL_FAMILY[[m_id]],
        tier        = tier,
        cv_auc_mean = mean(r$cv_per_fold$ROC),
        cv_auc_sd   = sd(r$cv_per_fold$ROC),
        train_auc   = r$train_auc,
        test_auc    = r$test_auc,
        gap         = r$train_auc - r$test_auc,
        accuracy    = r$test_acc,
        f1          = r$test_f1,
        precision   = r$test_prec,
        sensitivity = r$test_sens,
        specificity = r$test_spec,
        train_secs  = r$train_secs
      )
    }) %>%
      filter(tier %in% input$tiers_sel,
             model %in% selected_model_labels()) %>%
      mutate(tier = factor(tier, levels = TIERS_ALL)) %>%
      arrange(tier, family, desc(cv_auc_mean))
  })

  folds_long <- reactive({
    if (!length(rv$results)) return(NULL)
    map_dfr(names(rv$results), function(key) {
      r <- rv$results[[key]]
      if (is.null(r)) return(NULL)
      parts <- strsplit(key, "::", fixed = TRUE)[[1]]
      m_id <- parts[1]; tier <- parts[2]
      r$cv_per_fold %>%
        transmute(
          model    = names(MODEL_CHOICES)[match(m_id, MODEL_CHOICES)],
          family   = MODEL_FAMILY[[m_id]],
          tier     = tier,
          fold     = Resample,
          auc      = ROC
        )
    }) %>%
      filter(tier %in% input$tiers_sel,
             model %in% selected_model_labels()) %>%
      mutate(tier = factor(tier, levels = TIERS_ALL))
  })

  empty_table <- function(rv_results) {
    msg <- if (!length(rv_results))
      "No fitted models yet - press Refit."
    else
      "No results match current tier/model filter."
    datatable(data.frame(Note = msg),
              options = list(dom = "t"), rownames = FALSE)
  }

  output$summary_dt <- renderDT({
    d <- results_long()
    if (is.null(d) || !nrow(d)) return(empty_table(rv$results))
    d %>%
      transmute(Model = model, Family = family, Tier = tier,
                `CV AUC mean` = round(cv_auc_mean, 4),
                `CV AUC sd`   = round(cv_auc_sd,   4),
                `Train AUC`   = round(train_auc,   4),
                `Test AUC`    = round(test_auc,    4),
                Gap           = round(gap,         4),
                Accuracy      = round(accuracy,    4),
                F1            = round(f1,          4),
                Sensitivity   = round(sensitivity, 4),
                Specificity   = round(specificity, 4),
                `Train (s)`   = round(train_secs,  1)) %>%
      datatable(options = list(pageLength = 25, dom = "tip", scrollX = TRUE),
                rownames = FALSE) %>%
      formatStyle(c("Sensitivity", "Specificity"),
                  fontWeight = "bold",
                  backgroundColor = "#FFF7E6")
  })

  output$quality_dt <- renderDT({
    d <- results_long()
    if (is.null(d) || !nrow(d)) return(empty_table(rv$results))
    d %>%
      transmute(Model = model, Family = family, Tier = tier,
                Accuracy    = round(accuracy,    4),
                F1          = round(f1,          4),
                Precision   = round(precision,   4),
                Sensitivity = round(sensitivity, 4),
                Specificity = round(specificity, 4)) %>%
      datatable(options = list(pageLength = 25, dom = "tip"),
                rownames = FALSE)
  })

  output$auc_plot <- renderPlot({
    d <- results_long()
    if (is.null(d) || !nrow(d)) return(NULL)

    d <- d %>%
      group_by(tier) %>%
      mutate(model = forcats::fct_reorder(model, cv_auc_mean)) %>%
      ungroup()

    family_palette <- c("parametric"     = "#4C78A8",
                        "non-parametric" = "#E45756")
    x_min <- max(0.4, min(d$cv_auc_mean - d$cv_auc_sd, na.rm = TRUE) - 0.01)

    ggplot(d, aes(x = cv_auc_mean, y = model, colour = family)) +
      geom_errorbar(aes(xmin = pmax(cv_auc_mean - cv_auc_sd, 0),
                        xmax = pmin(cv_auc_mean + cv_auc_sd, 1)),
                    orientation = "y", width = 0.25, linewidth = 0.6) +
      geom_point(size = 3.5) +
      geom_text(aes(label = sprintf("%.4f", cv_auc_mean)),
                hjust = -0.2, size = 3.2, colour = "grey25",
                show.legend = FALSE) +
      scale_colour_manual(values = family_palette) +
      facet_wrap(~ tier, ncol = 2, scales = "free_y") +
      coord_cartesian(xlim = c(x_min, 1.01)) +
      labs(x = "CV ROC (mean +/- SD across folds)",
           y = NULL, colour = "Family",
           title = "Per-tier CV AUC, models ranked within each tier",
           subtitle = "X-axis zoomed to data range so tight differences stay visible") +
      theme_minimal(base_size = 13) +
      theme(panel.grid.major.y = element_blank(),
            strip.text = element_text(face = "bold", hjust = 0),
            legend.position = "top")
  })

  output$roc_plot <- renderPlot({
    if (!length(rv$results)) return(NULL)
    sel_models <- selected_model_labels()
    pts <- map_dfr(names(rv$results), function(key) {
      r <- rv$results[[key]]
      if (is.null(r)) return(NULL)
      parts <- strsplit(key, "::", fixed = TRUE)[[1]]
      m_id <- parts[1]; tier <- parts[2]
      r$roc_points %>%
        mutate(model = names(MODEL_CHOICES)[match(m_id, MODEL_CHOICES)],
               tier  = tier)
    }) %>%
      filter(tier %in% input$tiers_sel,
             model %in% sel_models) %>%
      mutate(tier = factor(tier, levels = TIERS_ALL))

    if (!nrow(pts)) return(NULL)

    auc_lab <- results_long() %>%
      transmute(tier, model,
                lab = sprintf("%-12s %.4f", model, test_auc)) %>%
      group_by(tier) %>%
      summarise(text = paste(lab, collapse = "\n"), .groups = "drop")

    ggplot(pts, aes(fpr, tpr, colour = model)) +
      geom_abline(slope = 1, intercept = 0,
                  linetype = "dashed", colour = "grey70") +
      geom_line(linewidth = 0.8) +
      geom_text(data = auc_lab,
                aes(x = 0.55, y = 0.18, label = text),
                inherit.aes = FALSE, hjust = 0, vjust = 0,
                family = "mono", size = 3.2, colour = "grey25") +
      scale_x_continuous(breaks = c(0, 0.05, 0.1, 0.25, 0.5, 1)) +
      facet_wrap(~ tier, scales = "fixed") +
      coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
      labs(x = "False positive rate (1 - Specificity)",
           y = "True positive rate (Sensitivity)",
           colour = "Model",
           title = "Held-out test ROC curves",
           subtitle = "Numbers = test-set AUC per model.") +
      theme_minimal(base_size = 13) +
      theme(strip.text = element_text(face = "bold"))
  })

  output$wilcox_dt <- renderDT({
    d <- folds_long()
    if (is.null(d) || !nrow(d)) return(NULL)
    families_present <- unique(d$family)
    if (length(families_present) < 2) {
      return(datatable(data.frame(
        Note = "Need at least one parametric AND one non-parametric model fitted."
      ), options = list(dom = "t"), rownames = FALSE))
    }
    res <- d %>%
      group_by(tier, fold, family) %>%
      summarise(auc = mean(auc), .groups = "drop") %>%
      pivot_wider(names_from = family, values_from = auc) %>%
      group_by(tier) %>%
      summarise(
        mean_param   = mean(parametric, na.rm = TRUE),
        mean_nonparm = mean(`non-parametric`, na.rm = TRUE),
        diff         = mean(`non-parametric` - parametric, na.rm = TRUE),
        wilcox_p     = tryCatch(
          wilcox.test(`non-parametric`, parametric, paired = TRUE,
                      alternative = "greater")$p.value,
          error = function(e) NA_real_),
        .groups = "drop"
      ) %>%
      mutate(across(c(mean_param, mean_nonparm, diff), ~ round(.x, 4)),
             wilcox_p = signif(wilcox_p, 3))
    datatable(res, options = list(dom = "t"), rownames = FALSE)
  })

  output$sens_spec_plot <- renderPlot({
    d <- results_long()
    if (is.null(d) || !nrow(d)) return(NULL)
    tier_palette <- c("Lexical"  = "#E45756",
                      "Trust"    = "#F58518",
                      "Behavior" = "#54A24B",
                      "FullLite" = "#4C78A8")
    ggplot(d, aes(x = specificity, y = sensitivity,
                  colour = tier, shape = family)) +
      geom_hline(yintercept = 0.95, linetype = "dotted", colour = "grey60") +
      geom_vline(xintercept = 0.95, linetype = "dotted", colour = "grey60") +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                  colour = "grey80") +
      geom_point(size = 4, alpha = 0.9, stroke = 1.2) +
      ggrepel::geom_text_repel(aes(label = model),
                               size = 3.3, max.overlaps = 50,
                               box.padding = 0.4, show.legend = FALSE) +
      scale_colour_manual(values = tier_palette, drop = FALSE) +
      scale_shape_manual(values = c("parametric" = 16,
                                    "non-parametric" = 17)) +
      coord_cartesian(xlim = c(0.3, 1.01), ylim = c(0.3, 1.01)) +
      labs(x = "Specificity (legit not blocked)",
           y = "Sensitivity (phish caught)",
           colour = "Tier", shape = "Family",
           title = "Operating point at threshold 0.5",
           subtitle = "Dotted lines = 95% target on each axis; dashed line = symmetry") +
      theme_minimal(base_size = 13)
  })

  # ---- Task 4: surrogate tree tab -----------------------------------------
  # Reads the cached surrogate grid produced by scenario_2.rmd S7.2
  # (scenario_2/artifacts/surrogate_<tier>.rds). No re-fitting in the app:
  # the notebook is the single source of truth for Task 4.

  SURROGATE_DIR <- "scenario_2/artifacts"

  surrogate_cache <- reactive({
    tier <- input$task4_tier
    path <- file.path(SURROGATE_DIR,
                      sprintf("surrogate_%s.rds", tolower(tier)))
    if (!file.exists(path)) return(NULL)
    tryCatch(readRDS(path)$data, error = function(e) NULL)
  })

  output$task4_status <- renderText({
    tier <- input$task4_tier
    path <- file.path(SURROGATE_DIR,
                      sprintf("surrogate_%s.rds", tolower(tier)))
    cache <- surrogate_cache()
    if (is.null(cache)) {
      return(sprintf(paste(
        "No cached surrogate for '%s'.",
        "Knit scenario_2.rmd (section 7) to generate '%s';",
        "it runs the rpart grid and writes the .rds the app reads here.",
        sep = "\n"), tier, path))
    }
    n_leaves <- max(cache$results$leaves)
    sprintf("Loaded %d grid rows for '%s'. Max leaves in grid: %d.",
            nrow(cache$results), tier, n_leaves)
  })

  # Picks the same winner scenario_2.rmd S7.4 plots: the highest-fidelity
  # tree in the whole grid subject to (depth <= slider, leaves <= cap).
  # Using "<=" (not "==") on depth means the default (depth=7, cap=15)
  # reproduces the RMD winner; lowering the slider then restricts the
  # search to shallower trees if the user wants a more readable one.
  task4_selected_tree <- reactive({
    cache <- surrogate_cache()
    if (is.null(cache)) return(NULL)
    md_cap <- input$task4_maxdepth
    cap    <- input$task4_max_leaves
    pick <- cache$results %>%
      filter(maxdepth <= md_cap, leaves <= cap) %>%
      arrange(desc(fidelity), leaves) %>%
      slice_head(n = 1)
    if (!nrow(pick)) return(NULL)
    key <- sprintf("md=%d_cp=%.0e_mb=%d",
                   pick$maxdepth, pick$cp, pick$minbucket)
    list(row = pick, tree = cache$trees[[key]])
  })

  output$task4_tree_plot <- renderPlot({
    sel <- task4_selected_tree()
    if (is.null(sel)) {
      plot.new()
      title(main = "No tree matches the current maxdepth / leaves cap.")
      return()
    }
    if (requireNamespace("rpart.plot", quietly = TRUE)) {
      rpart.plot::rpart.plot(
        sel$tree, type = 2, extra = 104, fallen.leaves = TRUE,
        box.palette = c("#D73027", "#1A9850"),
        main = sprintf("%s surrogate - depth %d, %d leaves, fidelity %.3f",
                       input$task4_tier, sel$row$maxdepth,
                       sel$row$leaves, sel$row$fidelity)
      )
    } else {
      plot(sel$tree, uniform = TRUE, margin = 0.12,
           main = sprintf("%s surrogate tree", input$task4_tier))
      text(sel$tree, use.n = TRUE, cex = 0.65)
    }
  })

  output$task4_metrics_dt <- renderDT({
    sel <- task4_selected_tree()
    if (is.null(sel)) return(NULL)
    r <- sel$row
    tibble(
      Tier          = input$task4_tier,
      MaxDepth      = r$maxdepth,
      cp            = formatC(r$cp, format = "e", digits = 0),
      minbucket     = r$minbucket,
      Leaves        = r$leaves,
      Fidelity      = round(r$fidelity,   4),
      `Sens vs RF`  = round(r$sens_vs_rf, 4),
      `Spec vs RF`  = round(r$spec_vs_rf, 4),
      `Tree Sens`   = round(r$tree_sens,  4),
      `Tree Spec`   = round(r$tree_spec,  4),
      `RF Sens`     = round(r$rf_sens,    4),
      `RF Spec`     = round(r$rf_spec,    4),
      `Tree AUC`    = round(r$auc,        4)
    ) %>%
      datatable(options = list(dom = "t", scrollX = TRUE), rownames = FALSE)
  })

  output$task4_depth_dt <- renderDT({
    cache <- surrogate_cache()
    if (is.null(cache)) return(NULL)
    cache$results %>%
      group_by(maxdepth) %>%
      slice_max(fidelity, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      arrange(maxdepth) %>%
      transmute(MaxDepth     = maxdepth,
                Leaves       = leaves,
                Fidelity     = round(fidelity,   4),
                `Sens vs RF` = round(sens_vs_rf, 4),
                `Spec vs RF` = round(spec_vs_rf, 4),
                `Tree AUC`   = round(auc,        4)) %>%
      datatable(options = list(dom = "t"), rownames = FALSE)
  })

  # ---- Scenario 3: feature-selection comparison tab -----------------------
  # Reads cached fits produced by scenario_3.rmd. Read-only viewer; the
  # notebook is the single source of truth for Task 3.

  S3_DIR <- "scenario_3/artifacts"
  S3_FULLLITE_FEATURES <- build_tiers()[["FullLite"]]

  s3_read <- function(name) {
    path <- file.path(S3_DIR, paste0(name, ".rds"))
    if (!file.exists(path)) return(NULL)
    tryCatch(readRDS(path), error = function(e) NULL)
  }
  s3_perfold <- reactive(s3_read("perfold"))
  s3_finals  <- reactive(s3_read("lexical_final"))
  s3_d3_data <- reactive({
    s3_read("d3_lexical_fs_metrics")
  })

  output$s3_status <- renderText({
    fp <- s3_finals(); d3 <- s3_d3_data()
    if (is.null(fp) || is.null(d3)) {
      return(paste(
        "No cached Scenario 3 fits found.",
        sprintf("Expected primary files: %s/{lexical_final,d3_lexical_fs_metrics}.rds", S3_DIR),
        "Run: rmarkdown::render('scenario_3.rmd') to populate the cache.",
        sep = "\n"))
    }
    pf <- s3_perfold()
    sprintf("Loaded Lexical primary fits (%d selected by stepwise, %d by lasso, %d by EN). FullLite fallback folds: %s.",
            length(fp$sw_terms), length(fp$lasso_terms), length(fp$en_terms),
            if (is.null(pf)) "not cached" else paste0(length(pf$k_step), " folds"))
  })

  output$s3_h2_dt <- renderDT({
    d3 <- s3_d3_data()
    if (is.null(d3) || is.null(d3$table)) return(NULL)
    d3$table %>%
      mutate(across(where(is.numeric), ~ round(.x, 4))) %>%
      datatable(options = list(dom = "t"), rownames = FALSE)
  })

  output$s3_perfold_plot <- renderPlot({
    pf <- s3_perfold()
    if (is.null(pf)) return(NULL)
    pool <- length(S3_FULLLITE_FEATURES)
    long <- tibble(
      fold   = rep(seq_along(pf$k_step), 3),
      method = rep(c("stepwise", "lasso", "elastic-net"),
                   each = length(pf$k_step)),
      k      = c(pf$k_step, pf$k_lasso, pf$k_en)
    ) %>%
      mutate(method = factor(method,
                             levels = c("stepwise", "elastic-net", "lasso")))
    p <- ggplot(long, aes(method, k, fill = method)) +
      geom_boxplot(alpha = 0.6, outlier.shape = NA) +
      geom_point(position = position_jitter(width = 0.1, seed = 1), size = 1.6) +
      labs(x = NULL, y = "selected predictors per fold") +
      theme_minimal(base_size = 13) + theme(legend.position = "none")
    p + geom_hline(yintercept = pool, linetype = "dashed",
                   colour = "grey40") +
      annotate("text", x = 0.6, y = pool + 0.3,
               label = sprintf("FullLite pool = %d", pool),
               hjust = 0, size = 3.4, colour = "grey30")
  })

  output$s3_perfold_dt <- renderDT({
    pf <- s3_perfold()
    if (is.null(pf) || is.null(pf$k_step)) return(NULL)
    tibble(
      fold = seq_along(pf$k_step),
      k_step = pf$k_step,
      k_lasso = pf$k_lasso,
      k_en = pf$k_en
    ) %>%
      datatable(options = list(dom = "tp", pageLength = 10), rownames = FALSE,
                caption = "FullLite stress test: selected-predictor count per CV fold (out of 34 candidates).")
  })

  output$s3_fulllite_mean_dt <- renderDT({
    pf <- s3_perfold()
    if (is.null(pf) || is.null(pf$k_step)) return(NULL)
    tibble(
      metric = c("mean k (stepwise)", "mean k (lasso)", "mean k (elastic-net)"),
      value = c(sprintf("%.1f", mean(pf$k_step)),
                sprintf("%.1f", mean(pf$k_lasso)),
                sprintf("%.1f", mean(pf$k_en)))
    ) %>%
      datatable(options = list(dom = "t"), rownames = FALSE,
                caption = "Average selected-predictor count across folds for each FS method.")
  })

  output$s3_d1_dt <- renderDT({
    fp <- s3_finals()
    if (is.null(fp)) return(NULL)
    all_terms <- sort(unique(c(fp$sw_terms, fp$lasso_terms,
                               fp$en_terms, fp$X_names)))
    d1 <- tibble(
      predictor   = all_terms,
      stepwise    = predictor %in% fp$sw_terms,
      lasso       = predictor %in% fp$lasso_terms,
      elastic_net = predictor %in% fp$en_terms
    ) %>%
      mutate(score = stepwise + lasso + elastic_net) %>%
      arrange(desc(score), predictor)
    d1 %>%
      transmute(
        predictor,
        stepwise = ifelse(stepwise, "x", ""),
        lasso = ifelse(lasso, "x", ""),
        elastic_net = ifelse(elastic_net, "x", "")
      ) %>%
      datatable(options = list(dom = "t", pageLength = 20),
                rownames = FALSE)
  })

  s3_step_path_data <- function(fp) {
    keep_mat <- fp$stepwise_fit$keep
    n_steps <- if (is.matrix(keep_mat)) ncol(keep_mat) else length(keep_mat)
    map_dfr(seq_len(n_steps), function(i) {
      k_i <- if (is.matrix(keep_mat)) keep_mat[, i] else keep_mat[[i]]
      tibble(step = i, predictor = k_i$terms, p = k_i$p, AIC = k_i$AIC)
    }) %>% filter(predictor != "(Intercept)")
  }

  output$s3_step_path_dt <- renderDT({
    fp <- s3_finals()
    if (is.null(fp) || is.null(fp$stepwise_fit$keep)) return(NULL)
    s3_step_path_data(fp) %>%
      group_by(predictor) %>%
      arrange(step, .by_group = TRUE) %>%
      summarise(
        first_step = min(step),
        last_step = max(step),
        min_p = min(p, na.rm = TRUE),
        max_p = max(p, na.rm = TRUE),
        final_p = dplyr::last(p),
        crosses_05 = any(p > 0.05) && any(p < 0.05),
        .groups = "drop"
      ) %>%
      arrange(desc(crosses_05), desc(max_p), predictor) %>%
      mutate(across(c(min_p, max_p, final_p), ~ signif(.x, 3))) %>%
      datatable(options = list(dom = "t", pageLength = 12),
                rownames = FALSE)
  })

  s3_coef_at_lambda <- function(cvfit, label, s = "lambda.1se") {
    beta <- as.matrix(coef(cvfit, s = s))[-1, , drop = FALSE]
    tibble(
      predictor = rownames(beta),
      method = label,
      coefficient = as.numeric(beta[, 1]),
      retained = coefficient != 0
    )
  }

  s3_active_lambda_table <- function(cvfit, label) {
    beta_path <- as.matrix(coef(cvfit$glmnet.fit))[-1, , drop = FALSE]
    lambdas <- cvfit$glmnet.fit$lambda
    beta_path %>%
      as_tibble(rownames = "predictor") %>%
      rename_with(~ as.character(seq_along(lambdas)), -predictor) %>%
      pivot_longer(-predictor, names_to = "lambda_index",
                   values_to = "coefficient") %>%
      mutate(lambda = lambdas[as.integer(lambda_index)]) %>%
      filter(coefficient != 0) %>%
      summarise(active_lambda = max(lambda), .by = predictor) %>%
      right_join(tibble(predictor = rownames(beta_path)), by = "predictor") %>%
      mutate(method = label) %>%
      select(predictor, active_lambda, method)
  }

  output$s3_embedded_coef_plot <- renderPlot({
    fp <- s3_finals()
    if (is.null(fp)) return(NULL)
    bind_rows(
      s3_coef_at_lambda(fp$lasso_fit, "lasso"),
      s3_coef_at_lambda(fp$en_fit, "elastic-net")
    ) %>%
      filter(retained) %>%
      mutate(predictor = reorder(predictor, abs(coefficient))) %>%
      ggplot(aes(coefficient, predictor, fill = method)) +
      geom_col(show.legend = FALSE) +
      facet_wrap(~ method, scales = "free_y") +
      geom_vline(xintercept = 0, colour = "grey50") +
      labs(
        x = "Coefficient at lambda.1se",
        y = NULL
      ) +
      theme_minimal(base_size = 12)
  })

  output$s3_embedded_lambda_dt <- renderDT({
    fp <- s3_finals()
    if (is.null(fp)) return(NULL)
    bind_rows(
      s3_active_lambda_table(fp$lasso_fit, "lasso"),
      s3_active_lambda_table(fp$en_fit, "elastic-net")
    ) %>%
      pivot_wider(names_from = method, values_from = active_lambda) %>%
      mutate(across(c(lasso, `elastic-net`),
                    ~ if_else(is.na(.x), "(never)", as.character(signif(.x, 3))))) %>%
      arrange(predictor) %>%
      datatable(options = list(dom = "t", pageLength = 20),
                rownames = FALSE,
                caption = paste("Largest lambda at which each predictor is active.",
                                "Larger = retained under stronger regularisation."))
  })

  output$s3_d3_dt <- renderDT({
    d3 <- s3_d3_data()
    if (is.null(d3) || is.null(d3$table)) return(NULL)
    d3$table %>%
      mutate(across(where(is.numeric), ~ round(.x, 4))) %>%
      datatable(options = list(dom = "t"), rownames = FALSE)
  })

  output$s3_fulllite_freq_dt <- renderDT({
    pf <- s3_perfold()
    if (is.null(pf) || is.null(pf$step_terms)) return(NULL)
    n_folds <- length(pf$step_terms)
    count_in_folds <- function(term_lists, term) {
      sum(vapply(term_lists, function(tl) term %in% tl, logical(1)))
    }
    all_terms <- sort(unique(c(unlist(pf$step_terms, use.names = FALSE),
                               unlist(pf$lasso_terms, use.names = FALSE),
                               unlist(pf$en_terms, use.names = FALSE),
                               S3_FULLLITE_FEATURES)))
    if (!length(all_terms)) return(NULL)
    tibble(
      predictor   = all_terms,
      stepwise    = vapply(all_terms, count_in_folds, integer(1),
                           term_lists = pf$step_terms),
      lasso       = vapply(all_terms, count_in_folds, integer(1),
                           term_lists = pf$lasso_terms),
      elastic_net = vapply(all_terms, count_in_folds, integer(1),
                           term_lists = pf$en_terms)
    ) %>%
      mutate(score = stepwise + lasso + elastic_net) %>%
      arrange(desc(score), predictor) %>%
      dplyr::select(-score) %>%
      datatable(
        options = list(dom = "tp", pageLength = 15),
        rownames = FALSE,
        caption = sprintf(
          "FullLite predictors: number of CV folds (out of %d) in which each FS method retained each predictor.",
          n_folds))
  })

  # ---------------------------------------------------------------------------
  # Winner showcase tab - SVM-RBF on Lexical (loaded from artifacts/winner_svm_lexical.rds).
  # Two interactive controls: classification threshold + per-feature URL inputs.
  # All visualizations recompute reactively without a refit.
  # ---------------------------------------------------------------------------

  output$winner_info_card <- renderUI({
    if (is.null(winner)) return(NULL)
    m <- winner$meta
    div(class = "config-panel",
        strong("Winning model: "),
        tags$code(sprintf("%s on %s tier", m$model, m$tier)),
        span(class = "config-meta",
             sprintf(" - %d features, train n=%s, test n=%s, test AUC=%.4f",
                     m$n_features,
                     format(m$n_train, big.mark = ","),
                     format(m$n_test,  big.mark = ","),
                     m$test_auc)),
        div(class = "config-row",
            span(class = "config-model",
                 strong("Hyperparams: "),
                 tags$code(sprintf("C=%g, sigma=%g", m$C, m$sigma)))))
  })

  output$winner_body <- renderUI({
    if (is.null(winner)) {
      return(div(
        style = "padding:18px;background:#FFF7E6;border-left:4px solid #E0A800;
                 border-radius:4px;margin-top:10px;",
        h4("Winning model artefakt nenajdeny"),
        p("Subor ", tags$code(WINNER_PATH), " neexistuje. ",
          "Spusti v R / RStudio (na Windows strane, nie WSL):"),
        tags$pre("setwd(\"C:/Users/frede/PycharmProjects/oznal-project\")\nsource(\"fit_winner.R\")"),
        p("Trvanie: par minut. Vytvori sa artefakt s natrenovanym SVM-RBF ",
          "modelom + test pravdepodobnostami, ktore tento tab pouziva na ",
          "real-time vizualizacie a predikcie.")
      ))
    }

    feat_inputs <- lapply(winner$features, function(f) {
      stat <- winner$feature_stats[[f]]
      id   <- paste0("winner_", f)
      if (isTRUE(stat$is_binary)) {
        selectInput(id, f,
                    choices  = c("0" = 0, "1" = 1),
                    selected = as.character(round(stat$median)))
      } else {
        lo <- floor(stat$min); hi <- ceiling(stat$max)
        # slider needs hi > lo - guard against degenerate constants
        if (hi <= lo) hi <- lo + 1
        sliderInput(id, f, min = lo, max = hi,
                    value = round(stat$median), step = 1)
      }
    })

    fluidRow(
      column(4,
        h4("Nastavenia"),
        sliderInput("winner_threshold",
                    "Klasifikacny prah (Phishing ak prob >= prah)",
                    min = 0, max = 1, value = 0.5, step = 0.01),
        actionButton("winner_reset", "Reset na defaulty",
                     class = "btn-default", style = "margin-bottom:10px;"),
        tags$details(class = "hp-section", open = NA,
          tags$summary(sprintf("URL features (%d)", length(winner$features))),
          helpText("Hodnoty pre hypoteticku URL. Predikcia sa prepocita ",
                   "real-time pri kazdej zmene."),
          do.call(tagList, feat_inputs))
      ),
      column(8,
        h4("Live predikcia hypotetickej URL"),
        uiOutput("winner_verdict"),
        br(),
        h4("Vykon na test sete pri zvolenom prahu"),
        uiOutput("winner_metrics_row"),
        br(),
        fluidRow(
          column(6,
            h5("Confusion matrix"),
            tableOutput("winner_cm_table")),
          column(6,
            h5("ROC krivka + operating point"),
            plotOutput("winner_roc_plot", height = "260px"))
        ),
        br(),
        h5("Histogram predikovanych pravdepodobnosti (test set)"),
        plotOutput("winner_hist_plot", height = "260px"),
        helpText("Cervena ciara = aktualny prah. Sirka prekryvu medzi ",
                 "triedami pri tejto hodnote = miera neistoty modelu.")
      )
    )
  })

  winner_metrics <- reactive({
    req(winner)
    thr <- input$winner_threshold
    pred <- factor(ifelse(winner$test_prob >= thr, "Phishing", "Legitimate"),
                   levels = c("Phishing", "Legitimate"))
    cm <- caret::confusionMatrix(pred, winner$test_label, positive = "Phishing")
    list(
      cm   = cm$table,
      acc  = unname(cm$overall["Accuracy"]),
      sens = unname(cm$byClass["Sensitivity"]),
      spec = unname(cm$byClass["Specificity"]),
      f1   = unname(cm$byClass["F1"])
    )
  })

  winner_user_prob <- reactive({
    req(winner)
    vals <- lapply(winner$features, function(f) {
      v <- input[[paste0("winner_", f)]]
      req(v)
      as.numeric(v)
    })
    raw <- as.data.frame(setNames(vals, winner$features),
                         stringsAsFactors = FALSE)
    std <- winner_transform(raw, winner)
    as.numeric(predict(winner$fit, std, type = "prob")[, "Phishing"])
  })

  output$winner_verdict <- renderUI({
    req(winner)
    p   <- winner_user_prob()
    thr <- input$winner_threshold
    is_phish <- p >= thr
    bg <- if (is_phish) "#FDECEA" else "#E8F5E9"
    bd <- if (is_phish) "#C62828" else "#2E7D32"
    label <- if (is_phish) "PHISHING" else "LEGITIMATE"
    div(style = sprintf(
        "padding:14px 18px;background:%s;border-left:6px solid %s;
         border-radius:4px;font-size:18px;", bg, bd),
        strong(style = sprintf("color:%s;font-size:22px;", bd), label),
        span(style = "margin-left:14px;color:#333;",
             sprintf("Prob(Phishing) = %.4f", p)),
        span(style = "margin-left:14px;color:#666;font-size:13px;",
             sprintf("(prah = %.2f)", thr)))
  })

  output$winner_metrics_row <- renderUI({
    m <- winner_metrics()
    chip <- function(label, value, color) {
      div(style = sprintf(
          "display:inline-block;padding:8px 14px;margin-right:10px;
           background:%s;border-radius:4px;border:1px solid #d1d5db;",
          color),
          strong(label), ": ", sprintf("%.4f", value))
    }
    tagList(
      chip("Accuracy",    m$acc,  "#F0F7FF"),
      chip("Sensitivity", m$sens, "#FFF7E6"),
      chip("Specificity", m$spec, "#FFF7E6"),
      chip("F1",          m$f1,   "#F0F7FF")
    )
  })

  output$winner_cm_table <- renderTable({
    cm <- winner_metrics()$cm
    df <- as.data.frame.matrix(cm)
    df <- cbind(`Predicted \\ Actual` = rownames(df), df)
    df
  }, striped = TRUE, bordered = TRUE, align = "lcc", rownames = FALSE)

  output$winner_roc_plot <- renderPlot({
    req(winner)
    m <- winner_metrics()
    roc_df <- tibble(
      fpr = 1 - winner$roc_obj$specificities,
      tpr = winner$roc_obj$sensitivities
    )
    op <- tibble(fpr = 1 - m$spec, tpr = m$sens)
    ggplot(roc_df, aes(fpr, tpr)) +
      geom_abline(slope = 1, intercept = 0,
                  colour = "grey70", linetype = "dashed") +
      geom_path(colour = "#4C78A8", linewidth = 0.9) +
      geom_point(data = op, colour = "#C62828", size = 4) +
      geom_text(data = op,
                aes(label = sprintf("(%.3f, %.3f)", fpr, tpr)),
                hjust = -0.15, vjust = 0.5, size = 3.6, colour = "#C62828") +
      coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
      labs(x = "False positive rate (1 - Specificity)",
           y = "True positive rate (Sensitivity)") +
      theme_minimal(base_size = 12)
  })

  output$winner_hist_plot <- renderPlot({
    req(winner)
    thr <- input$winner_threshold
    df <- tibble(prob = winner$test_prob,
                 class = winner$test_label)
    ggplot(df, aes(prob, fill = class)) +
      geom_histogram(bins = 50, position = "identity", alpha = 0.55,
                     colour = "white", linewidth = 0.1) +
      geom_vline(xintercept = thr, colour = "#C62828",
                 linewidth = 0.9, linetype = "dashed") +
      scale_fill_manual(values = c(Phishing = "#C62828",
                                   Legitimate = "#2E7D32")) +
      labs(x = "Predicted P(Phishing)", y = "Pocet test URLs",
           fill = NULL) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "top")
  })

  observeEvent(input$winner_reset, {
    req(winner)
    for (f in winner$features) {
      stat <- winner$feature_stats[[f]]
      id   <- paste0("winner_", f)
      if (isTRUE(stat$is_binary)) {
        updateSelectInput(session, id,
                          selected = as.character(round(stat$median)))
      } else {
        updateSliderInput(session, id, value = round(stat$median))
      }
    }
    updateSliderInput(session, "winner_threshold", value = 0.5)
  })

  # On disconnect: kill orphan background process so it doesn't keep burning CPU.
  session$onSessionEnded(function() {
    isolate({
      if (!is.null(rv$bg_proc) && inherits(rv$bg_proc, "process") &&
          rv$bg_proc$is_alive()) {
        try(rv$bg_proc$kill(), silent = TRUE)
      }
    })
  })
}

shinyApp(ui, server)

