#!/usr/bin/env Rscript
# Build executable/direct runners for the remaining strategy-pool specs.
#
# Policy:
# - If a spec has an explicit Factor DB representation, generate an AlphaSearch
#   runner against fe_factor_combo.R.
# - If a spec is an overlay that the backtest harness supports, pass the actual
#   vol_target/dd_brake/weighting controls to AlphaSearch.
# - If a spec needs unavailable data, missing parent code, or unimplemented
#   component engines, write an explicit runnable contract that records why no
#   synthetic/proxy backtest was created.
# - Never inject a broad fallback factor basket for unmapped specs.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
}

args <- commandArgs(trailingOnly = TRUE)
plan_csv <- if (length(args) >= 1L) args[[1]] else {
  "stage_artifacts/batch_434/20260612_rerun_turnover1100_expanded/execution_plan.csv"
}
out_dir <- if (length(args) >= 2L) args[[2]] else {
  file.path("stage_artifacts", "batch_434",
            paste0(format(Sys.Date(), "%Y%m%d"), "_codegen_direct_409"))
}

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
plan_csv <- normalizePath(plan_csv, winslash = "/", mustWork = TRUE)
out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
runners_dir <- file.path(out_dir, "runners")
dir.create(runners_dir, recursive = TRUE, showWarnings = FALSE)

r_quote <- function(x) paste(deparse(as.character(x), control = "keepNA"), collapse = "")
slug <- function(x) gsub("[^A-Za-z0-9_.-]", "_", x)
clean_text <- function(x) {
  x <- paste(as.character(x %||% ""), collapse = " ")
  x <- gsub("[\r\n\t]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}
field <- function(x, name) if (is.list(x) && !is.null(x[[name]])) x[[name]] else NULL
flatten_text <- function(x) {
  if (is.null(x)) return(character())
  if (is.atomic(x)) return(as.character(x))
  if (is.list(x)) return(unlist(lapply(x, flatten_text), use.names = FALSE))
  character()
}
rel_path <- function(path) {
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  pref <- paste0(root, "/")
  if (startsWith(p, pref)) substring(p, nchar(pref) + 1L) else p
}

successful_items <- function() {
  files <- list.files(file.path(root, "stage_artifacts", "batch_434"),
                      pattern = "ready_run_summary\\.csv$",
                      recursive = TRUE, full.names = TRUE)
  if (!length(files)) return(character())
  rows <- rbindlist(lapply(files, function(f) {
    x <- tryCatch(fread(f), error = function(e) NULL)
    if (is.null(x) || !nrow(x) || !"exit_code" %in% names(x)) return(NULL)
    x
  }), fill = TRUE)
  if (!nrow(rows)) character() else unique(rows[exit_code == 0, item_id])
}

read_spec <- function(file) {
  path <- file.path(root, "qepm", "mailbox", "forge", "inbox_hold", file)
  if (!file.exists(path)) return(list(.missing = TRUE))
  tryCatch(fromJSON(path, simplifyVector = FALSE),
           error = function(e) list(.error = conditionMessage(e)))
}

latest_factor_names <- function() {
  cache_path <- file.path(root, "stage_artifacts", "batch_434", "factor_names_latest.txt")
  if (file.exists(cache_path)) {
    f <- readLines(cache_path, warn = FALSE)
    f <- f[nzchar(f)]
    if (length(f)) return(sort(unique(f)))
  }
  source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R"))
  dt <- load_month_factors(Sys.Date() - 14L)
  sort(unique(dt$Factor_Name))
}

factor_names <- latest_factor_names()

factor_groups <- list(
  defense = c("D01_IdioVol", "D02_Beta"),
  consensus = c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap"),
  industry_momentum = c("M07_IndMom"),
  momentum = c("M01_Mom_12_1", "M07_IndMom", "M05_Trended_Mom"),
  reversal = c("M11_ST_Reversal", "M12_LR_Reversal"),
  quality = c("Q01_GPA", "Q04_Piotroski_F", "Q09_CFOA", "Q07_Earnings_Stability"),
  value = c("V01_BM", "V03_CFP", "V10_FCF_Yield", "V11_Shareholder_Yield"),
  accrual = c("AC07_Operating_Accruals", "AC18_Accrual_Quality", "GR03_Asset_Growth"),
  liquidity = c("L01_Amihud", "L09_Amihud_20d", "L10_Amihud_Ratio", "L40_VWAP_Spread"),
  crowding = c("CR02_Volume_Concentration", "CR08_Volume_Price_Divergence",
               "CR04_Ownership_Concentration"),
  tail = c("D43_Skewness", "D44_Kurtosis", "D47_CVaR_5pct", "R03_CVaR_95", "R10_Cokurtosis"),
  investor_flow = c("INV01_Foreign_NetBuy_20d", "CR04_Ownership_Concentration")
)
factor_groups <- lapply(factor_groups, function(x) unique(intersect(x, factor_names)))

kw_rules <- list(
  list(group = "defense", p = "defense|defensive|low.?vol|idio.?vol|tail.?risk|downside|low.?beta|anti.?lottery|volatility"),
  list(group = "consensus", p = "consensus|revision|eps|earnings revision|sue|surprise|estimate|target.?price|tp.?gap|coverage"),
  list(group = "industry_momentum", p = "industry.?mom|indmom|sector.?mom"),
  list(group = "momentum", p = "stock.?momentum|price.?momentum|12.?1|52.?week|high.?52|trend|trended|macd|rsi"),
  list(group = "reversal", p = "reversal|contrarian|mean.?reversion|short.?term"),
  list(group = "quality", p = "quality|piotroski|profit|profitability|gross|cfo|roa|roe|margin|stability|persistence"),
  list(group = "value", p = "value|book.?to.?market|\\bbm\\b|cash.?flow|cfp|fcf|yield|pbr|per|ebit|ev|shareholder"),
  list(group = "accrual", p = "accrual|accruals|\\bnoa\\b|asset.?growth|investment|issuance"),
  list(group = "liquidity", p = "liquidity|amihud|spread|price.?impact|vwap"),
  list(group = "crowding", p = "crowding|crowd|concentration|divergence"),
  list(group = "tail", p = "skew|cokurt|kurt|coskew|cvar|var|expected.?shortfall"),
  list(group = "investor_flow", p = "ownership|foreign|institution|flow|order.?flow|netbuy")
)

# Parent templates are explicit reconstructions from local registry/distill notes.
# They are used only when the spec names the parent strategy.
parent_rules <- list(
  STR_1036 = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m",
               "M07_IndMom", "Q04_Piotroski_F", "V03_CFP"),
  STR_943 = c("C02_EPS_Chg_1m", "C01_SUE"),
  STR_1048 = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "M07_IndMom"),
  STR_1033 = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "M07_IndMom", "V03_CFP"),
  STR_1060 = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m",
               "M07_IndMom", "Q04_Piotroski_F", "V03_CFP")
)
parent_rules <- lapply(parent_rules, function(x) unique(intersect(x, factor_names)))

spec_text <- function(row, spec) {
  clean_text(c(
    row$title, row$item_id, row$family, row$bucket, row$reason, row$mapping_notes,
    spec$parent_strategy %||% NULL,
    flatten_text(spec$scope),
    flatten_text(spec$design),
    flatten_text(field(spec$hypothesis, "statement")),
    flatten_text(field(spec$hypothesis, "mechanism")),
    flatten_text(spec$hypothesis),
    flatten_text(spec$implementation),
    flatten_text(spec$implementation_notes),
    flatten_text(spec$detailed_instructions),
    flatten_text(spec$contract),
    flatten_text(spec$constraints),
    flatten_text(spec$metrics_target),
    flatten_text(spec$risk_notes)
  ))
}

pick_factors <- function(row, spec) {
  text <- spec_text(row, spec)
  text_lower <- tolower(text)
  factors <- character()
  sources <- character()

  direct <- unique(unlist(regmatches(text, gregexpr("[A-Z]{1,3}[0-9]{2}_[A-Za-z0-9_]+", text, perl = TRUE))))
  direct <- intersect(direct, factor_names)
  if (length(direct)) {
    factors <- c(factors, direct)
    sources <- c(sources, "factor_name")
  }

  for (nm in names(parent_rules)) {
    if (grepl(nm, text, fixed = TRUE) && length(parent_rules[[nm]])) {
      factors <- c(factors, parent_rules[[nm]])
      sources <- c(sources, paste0("parent:", nm))
    }
  }
  for (rule in kw_rules) {
    if (grepl(rule$p, text_lower, perl = TRUE) && length(factor_groups[[rule$group]])) {
      factors <- c(factors, factor_groups[[rule$group]])
      sources <- c(sources, paste0("keyword:", rule$group))
    }
  }

  factors <- unique(intersect(factors, factor_names))
  if (length(factors) > 10L && !length(direct)) factors <- factors[seq_len(10L)]

  quality <- if (length(direct)) {
    "FACTOR_NAME_EXTRACTED_FROM_SPEC"
  } else if (any(startsWith(sources, "parent:"))) {
    "PARENT_DIRECT_FACTOR_TEMPLATE"
  } else if (length(factors)) {
    "KEYWORD_DIRECT_FACTOR_FORMULA"
  } else {
    "NO_FACTOR_DB_MAPPING"
  }
  list(factors = factors, sources = unique(sources), quality = quality, text = text)
}

parse_first_num <- function(pattern, text) {
  m <- regexpr(pattern, text, perl = TRUE, ignore.case = TRUE)
  if (m[1] < 0) return(NA_real_)
  hit <- regmatches(text, m)
  nums <- regmatches(hit, gregexpr("[0-9]+(?:\\.[0-9]+)?", hit, perl = TRUE))[[1]]
  if (!length(nums)) return(NA_real_)
  as.numeric(nums[[length(nums)]])
}

parse_n_holdings <- function(row, spec, text) {
  n <- NA_integer_
  sc <- field(spec, "scope")
  if (is.list(sc) && !is.null(sc$n_holdings)) {
    n <- suppressWarnings(as.integer(sc$n_holdings[[1]]))
  }
  if (is.na(n)) {
    raw <- parse_first_num("\\bN\\s*[=:]?\\s*[0-9]{1,2}\\b", text)
    if (!is.na(raw)) n <- as.integer(raw)
  }
  if (is.na(n)) n <- 30L
  n <- max(5L, min(30L, n))
  as.integer(n)
}

parse_weight_method <- function(text) {
  x <- tolower(text)
  if (grepl("\\bnco\\b|nested cluster", x, perl = TRUE)) return("nco")
  if (grepl("\\bhrp\\b|hierarchical risk parity|gerber", x, perl = TRUE)) return("hrp")
  if (grepl("min.?var|minimum variance", x, perl = TRUE)) return("minvar")
  if (grepl("risk.?parity|equal risk|erc", x, perl = TRUE)) return("riskparity")
  if (grepl("score.?weighted|score.?weight|conviction|rank.?weighted|softmax|tiered", x, perl = TRUE)) return("score_tilt")
  "equal"
}

parse_cov_method <- function(text) {
  x <- tolower(text)
  if (grepl("gerber|rmt|detoned", x, perl = TRUE)) return("gerber_rmt")
  if (grepl("ledoit|shrink", x, perl = TRUE)) return("ledoit_wolf")
  "sample"
}

parse_risk_controls <- function(text) {
  x <- tolower(text)
  vol_target <- NA_real_
  v0 <- parse_first_num("(vol_target|target_vol)\\s*[=:]\\s*0\\.[0-9]+", x)
  if (!is.na(v0)) vol_target <- v0
  if (is.na(vol_target) && grepl("vol.?target|target.?vol|target_vol", x, perl = TRUE)) {
    pct <- parse_first_num("(target_vol|vol.?target|target.?vol)[^0-9]{0,20}[0-9]{1,2}(?:\\.[0-9]+)?\\s*%", x)
    if (!is.na(pct)) vol_target <- pct / 100
  }
  if (is.na(vol_target) && grepl("vol.?target|target.?vol", x, perl = TRUE)) {
    raw <- parse_first_num("0\\.[0-9]+", x)
    if (!is.na(raw)) vol_target <- raw
  }
  if (!is.na(vol_target) && (vol_target <= 0 || vol_target > 0.5)) vol_target <- NA_real_

  dd_entry <- NA_real_
  dd_exit <- NA_real_
  if (grepl("dd.?med|dd.?short|dd brake|dd_brake|dd start|dd_start|\\bdd[0-9]{1,2}\\b|\\bdd\\b\\s*(start|entry|full|exit)|브레이크", x, perl = TRUE)) {
    med <- regexpr("dd[_ ]?med[^0-9]{0,30}[0-9]{1,2}(?:\\.[0-9]+)?%?[^0-9]{0,10}[0-9]{1,2}(?:\\.[0-9]+)?%?", x, perl = TRUE)
    if (med[1] > 0) {
      nums <- regmatches(regmatches(x, med), gregexpr("[0-9]+(?:\\.[0-9]+)?", regmatches(x, med), perl = TRUE))[[1]]
      nums <- as.numeric(nums)
      if (length(nums)) dd_entry <- tail(nums, 1L) / ifelse(tail(nums, 1L) > 1, 100, 1)
    }
    if (is.na(dd_entry)) {
      raw <- parse_first_num("(dd start|dd_start|dd\\s*start|dd)[^0-9]{0,20}0\\.[0-9]+", x)
      if (!is.na(raw)) dd_entry <- raw
    }
    if (is.na(dd_entry)) {
      pct <- parse_first_num("(dd start|dd_start|dd\\s*start|dd\\s*entry)[^0-9]{0,20}[0-9]{1,2}(?:\\.[0-9]+)?\\s*%", x)
      if (!is.na(pct)) dd_entry <- pct / 100
    }
    if (is.na(dd_entry) && grepl("\\bdd8\\b", x, perl = TRUE)) dd_entry <- 0.08
    full_raw <- parse_first_num("(dd full|dd_full|dd\\s*exit|dd\\s*full|full hedge)[^0-9]{0,25}0\\.[0-9]+", x)
    if (!is.na(full_raw)) dd_exit <- full_raw
    if (is.na(dd_exit)) {
      full_pct <- parse_first_num("(dd full|dd_full|dd\\s*exit|dd\\s*full|full hedge)[^0-9]{0,25}[0-9]{1,2}(?:\\.[0-9]+)?\\s*%", x)
      if (!is.na(full_pct)) dd_exit <- full_pct / 100
    }
    if (is.na(dd_exit) && grepl("dd.?med[^\\n]{0,120}(0\\.35|35%)", x, perl = TRUE)) dd_exit <- 0.35
    if (is.na(dd_exit) && !is.na(dd_entry)) dd_exit <- min(0.35, max(0.15, dd_entry + 0.12))
  }
  if (!is.na(dd_entry) && (dd_entry <= 0 || dd_entry >= 0.5)) dd_entry <- NA_real_
  if (!is.na(dd_exit) && !is.na(dd_entry) && dd_exit <= dd_entry) dd_exit <- min(0.5, dd_entry + 0.10)

  list(
    vol_target = if (is.na(vol_target)) NULL else vol_target,
    vol_lookback = 60L,
    dd_brake = if (is.na(dd_entry)) NULL else list(entry_pct = dd_entry, exit_pct = dd_exit)
  )
}

is_data_blocked <- function(row, spec, text) {
  if (identical(row$execution_class, "DATA_FIRST")) return(TRUE)
  x <- tolower(text)
  grepl("option|implied vol|vkospi|nlp|news|sentiment|external|krx .*option|데이터 가용성|뉴스|옵션",
        x, perl = TRUE)
}

needs_component_engine <- function(row, text) {
  x <- tolower(text)
  row$prefix %in% c("EN", "PROD") ||
    grepl("ensemble|production|shortlist|final decision|ablation|compare|상관|기여|전략 간|전략별", x, perl = TRUE)
}

needs_factor_momentum_engine <- function(row, text) {
  identical(row$family, "factor_momentum") ||
    row$prefix == "FM" ||
    grepl("factor momentum|\\bfm\\b|ic momentum|factor return", tolower(text), perl = TRUE)
}

block_reason <- function(row, text, data_blocked, has_factor) {
  if (isTRUE(data_blocked)) return(c("DATA_REQUIRED_NO_BACKTEST",
                                     "Required external/non-cached data is unavailable. No synthetic backtest created."))
  if (identical(row$execution_class, "MISSING_BASE_CODE")) {
    return(c("DIRECT_CODE_REQUIRED_MISSING_BASE_CODE",
             "Original strategy rerun requested but target run_all.R/base strategy code is missing."))
  }
  if (identical(row$execution_class, "ML_BUILD_THEN_RUN")) {
    return(c("DIRECT_CODE_REQUIRED_ML_ENGINE",
             "Named ML model requires its own training/prediction pipeline; fe_ml cache is not substituted for a different model."))
  }
  if (needs_component_engine(row, text) && !has_factor) {
    return(c("DIRECT_CODE_REQUIRED_COMPONENT_RESULTS",
             "Strategy-level ensemble/production diagnostic needs component strategy score or result artifacts."))
  }
  if (needs_factor_momentum_engine(row, text) && !has_factor) {
    return(c("DIRECT_CODE_REQUIRED_FACTOR_MOMENTUM_ENGINE",
             "Factor-momentum timing requires expanding factor-return/IC engine, not a static factor basket."))
  }
  if (identical(row$execution_class, "DIAGNOSTIC_BUILD_THEN_RUN") && !has_factor) {
    return(c("DIRECT_CODE_REQUIRED_DIAGNOSTIC",
             "Diagnostic/sweep spec needs a purpose-built diagnostic runner or target artifacts."))
  }
  c("DIRECT_CODE_REQUIRED_UNMAPPED_SPEC",
    "No explicit Factor DB mapping or supported direct harness implementation was found.")
}

write_blocked_runner <- function(row, quality, reason, text) {
  item_id <- row$item_id
  safe_id <- slug(item_id)
  runner_path <- file.path(runners_dir, paste0(safe_id, ".R"))
  result_path <- file.path(out_dir, paste0(safe_id, "_result.rds"))
  title <- clean_text(row$title %||% item_id)
  lines <- c(
    "#!/usr/bin/env Rscript",
    "suppressPackageStartupMessages(library(jsonlite))",
    sprintf("result_path <- %s", r_quote(result_path)),
    "dir.create(dirname(result_path), recursive = TRUE, showWarnings = FALSE)",
    "res <- list(",
    sprintf("  item_id = %s,", r_quote(item_id)),
    sprintf("  strategy_name = %s,", r_quote(title)),
    "  status = \"NOT_BACKTESTED\",",
    sprintf("  execution_class = %s,", r_quote(row$execution_class)),
    sprintf("  direct_status = %s,", r_quote(quality)),
    sprintf("  reason = %s,", r_quote(reason)),
    sprintf("  spec_excerpt = %s,", r_quote(substr(text, 1L, 800L))),
    "  validation = list(parse_ok = TRUE, pit_status = \"NOT_RUN\", contract_status = \"NO_SYNTHETIC_PROXY\"),",
    "  created_at = format(Sys.time(), \"%Y-%m-%dT%H:%M:%S%z\")",
    ")",
    "saveRDS(res, result_path)",
    "write_json(res, sub(\"\\\\.rds$\", \".json\", result_path), auto_unbox = TRUE, pretty = TRUE, na = \"null\")",
    sprintf("cat(%s)", r_quote(sprintf("[codegen-runner] NOT_BACKTESTED %s: %s\\n", item_id, quality)))
  )
  writeLines(lines, runner_path, useBytes = TRUE)
  Sys.chmod(runner_path, mode = "0755")
  parse_ok <- tryCatch({ parse(runner_path); TRUE }, error = function(e) FALSE)
  list(runner_path = runner_path, result_path = result_path, parse_ok = parse_ok)
}

write_alpha_runner <- function(row, factors, quality, text, n_holdings,
                               weight_method, cov_method, risk_controls) {
  item_id <- row$item_id
  safe_id <- slug(item_id)
  runner_path <- file.path(runners_dir, paste0(safe_id, ".R"))
  result_path <- file.path(out_dir, paste0(safe_id, "_result.rds"))
  title <- clean_text(row$title %||% item_id)
  idea <- clean_text(c(row$title, row$reason, row$mapping_notes))
  weights <- rep(1, length(factors))
  min_count <- length(factors)
  extra_args <- character()
  if (!is.null(risk_controls$vol_target)) {
    extra_args <- c(extra_args,
      sprintf("  vol_target = %.6f,", risk_controls$vol_target),
      sprintf("  vol_lookback = %dL,", as.integer(risk_controls$vol_lookback %||% 60L)))
  }
  if (!is.null(risk_controls$dd_brake)) {
    extra_args <- c(extra_args,
      sprintf("  dd_brake = list(entry_pct = %.6f, exit_pct = %.6f),",
              risk_controls$dd_brake$entry_pct, risk_controls$dd_brake$exit_pct))
  }
  if (!identical(cov_method, "sample")) {
    extra_args <- c(extra_args, sprintf("  cov_method = %s,", r_quote(cov_method)))
  }

  lines <- c(
    "#!/usr/bin/env Rscript",
    sprintf("# Generated direct AlphaSearch runner for %s", item_id),
    "args0 <- commandArgs(FALSE)",
    "file_arg <- grep(\"^--file=\", args0, value = TRUE)",
    "this_file <- if (length(file_arg)) sub(\"^--file=\", \"\", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) \"\")",
    "root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), \"../../../..\"), winslash = \"/\", mustWork = FALSE) else \"\"",
    "if (!nzchar(root) || !file.exists(file.path(root, \"02_Infrastructure\", \"config.R\"))) root <- normalizePath(getwd(), winslash = \"/\", mustWork = TRUE)",
    "setwd(root)",
    "Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)",
    sprintf("Sys.setenv(FACTOR_NAMES = %s)", r_quote(paste(factors, collapse = ","))),
    sprintf("Sys.setenv(FACTOR_WEIGHTS = %s)", r_quote(paste(weights, collapse = ","))),
    sprintf("Sys.setenv(FACTOR_MIN_COUNT = %s)", r_quote(as.character(min_count))),
    "source(\"02_Infrastructure/alpha_search/run_alpha_search.R\")",
    "res <- run_alpha_search(",
    sprintf("  strategy_name = %s,", r_quote(title)),
    sprintf("  strategy_idea = %s,", r_quote(idea)),
    "  factor_engine_path = \"02_Infrastructure/alpha_search/fe_factor_combo.R\",",
    sprintf("  n_holdings = %dL,", as.integer(n_holdings)),
    sprintf("  weight_method = %s,", r_quote(weight_method)),
    "  universe = \"ALL\",",
    "  send_telegram = TRUE,",
    "  tg_dry_run = FALSE,",
    "  factor_analysis = TRUE,",
    extra_args,
    "  use_default_buffer = TRUE",
    ")",
    sprintf("saveRDS(res, %s)", r_quote(result_path)),
    "cat(sprintf(\"[codegen-runner] DONE %s grade=%s score=%s -> %s\\n\",",
    sprintf("            %s, res$grade %%||%% NA_character_, res$score %%||%% NA_real_, %s))",
            r_quote(item_id), r_quote(result_path))
  )
  writeLines(lines, runner_path, useBytes = TRUE)
  Sys.chmod(runner_path, mode = "0755")
  parse_ok <- tryCatch({ parse(runner_path); TRUE }, error = function(e) FALSE)
  list(runner_path = runner_path, result_path = result_path, parse_ok = parse_ok,
       factor_weights = weights, factor_min_count = min_count)
}

plan <- fread(plan_csv)
ok_items <- successful_items()
remaining <- plan[!item_id %in% ok_items]
remaining <- remaining[execution_class != "RUN_EXISTING_R"]

rows <- vector("list", nrow(remaining))
for (i in seq_len(nrow(remaining))) {
  row <- as.list(remaining[i])
  spec <- read_spec(row$file)
  text <- spec_text(row, spec)
  pick <- pick_factors(row, spec)
  n_holdings <- parse_n_holdings(row, spec, text)
  weight_method <- parse_weight_method(text)
  cov_method <- parse_cov_method(text)
  rc <- parse_risk_controls(text)
  data_blocked <- is_data_blocked(row, spec, text)
  has_factor <- length(pick$factors) > 0L

  supported_direct <- has_factor && !data_blocked && !identical(row$execution_class, "MISSING_BASE_CODE")
  if (supported_direct && identical(row$execution_class, "ML_BUILD_THEN_RUN")) {
    supported_direct <- FALSE
  }

  if (supported_direct) {
    has_overlay <- !is.null(rc$vol_target) || !is.null(rc$dd_brake) ||
      !identical(weight_method, "equal") || !identical(cov_method, "sample")
    exec_class <- if (has_overlay) "RUN_ALPHA_DIRECT_OVERLAY" else "RUN_ALPHA_DIRECT_FACTOR_DB"
    quality <- if (has_overlay) {
      paste0("DIRECT_OVERLAY_", pick$quality)
    } else {
      paste0("DIRECT_", pick$quality)
    }
    wr <- write_alpha_runner(row, pick$factors, quality, text, n_holdings,
                             weight_method, cov_method, rc)
    reason <- "generated direct AlphaSearch runner; no broad fallback factors used"
    mapping_notes <- sprintf("factors=%s; sources=%s; min_count=%d; n=%d; weight=%s; cov=%s; vol_target=%s; dd_brake=%s; runner=%s",
                             paste(pick$factors, collapse = "+"),
                             paste(pick$sources, collapse = "+"),
                             wr$factor_min_count, n_holdings, weight_method, cov_method,
                             ifelse(is.null(rc$vol_target), "none", sprintf("%.4f", rc$vol_target)),
                             ifelse(is.null(rc$dd_brake), "none",
                                    sprintf("%.4f/%.4f", rc$dd_brake$entry_pct, rc$dd_brake$exit_pct)),
                             rel_path(wr$runner_path))
  } else {
    br <- block_reason(row, text, data_blocked, has_factor)
    exec_class <- if (isTRUE(data_blocked)) "DATA_BLOCKED_RUNNER" else "DIRECT_CODE_REQUIRED_RUNNER"
    quality <- br[[1]]
    wr <- write_blocked_runner(row, quality, br[[2]], text)
    reason <- br[[2]]
    mapping_notes <- sprintf("%s; no fallback/proxy factor basket generated; runner=%s",
                             br[[1]], rel_path(wr$runner_path))
  }

  rows[[i]] <- data.table(
    status = row$status,
    item_id = row$item_id,
    priority_score = row$priority_score,
    bucket = row$bucket,
    prefix = row$prefix,
    family = row$family,
    execution_class = exec_class,
    original_execution_class = row$execution_class,
    run_dir = root,
    runnable_command = sprintf("Rscript %s", shQuote(wr$runner_path)),
    title = row$title,
    file = row$file,
    reason = reason,
    mapping_quality = quality,
    mapping_notes = mapping_notes,
    runner_path = wr$runner_path,
    result_path = wr$result_path,
    factor_names = paste(pick$factors, collapse = ","),
    factor_sources = paste(pick$sources, collapse = ","),
    factor_weights = if (has_factor) paste(rep(1, length(pick$factors)), collapse = ",") else "",
    factor_min_count = if (has_factor) length(pick$factors) else NA_integer_,
    n_holdings = if (supported_direct) n_holdings else NA_integer_,
    weight_method = if (supported_direct) weight_method else NA_character_,
    cov_method = if (supported_direct) cov_method else NA_character_,
    vol_target = if (!is.null(rc$vol_target) && supported_direct) rc$vol_target else NA_real_,
    dd_entry = if (!is.null(rc$dd_brake) && supported_direct) rc$dd_brake$entry_pct else NA_real_,
    dd_exit = if (!is.null(rc$dd_brake) && supported_direct) rc$dd_brake$exit_pct else NA_real_,
    parse_ok = wr$parse_ok,
    stringsAsFactors = FALSE
  )
}

queue <- rbindlist(rows, fill = TRUE)
queue[, priority_sort := suppressWarnings(as.numeric(priority_score))]
queue[is.na(priority_sort), priority_sort := -Inf]
setorder(queue, -priority_sort, item_id)
queue[, priority_sort := NULL]

queue_path <- file.path(out_dir, "ready_commands_codegen_all.csv")
manifest_path <- file.path(out_dir, "codegen_manifest.csv")
summary_path <- file.path(out_dir, "codegen_summary.csv")
fwrite(queue, queue_path)
fwrite(queue, manifest_path)
summary <- queue[, .N, by = .(execution_class, mapping_quality, parse_ok)][order(execution_class, mapping_quality)]
fwrite(summary, summary_path)

chunk_size <- suppressWarnings(as.integer(Sys.getenv("QVEST_CODEGEN_CHUNK_SIZE", "24")))
if (is.na(chunk_size) || chunk_size < 1L) chunk_size <- 24L
queue[, chunk_id := ceiling(seq_len(.N) / chunk_size)]
for (ch in sort(unique(queue$chunk_id))) {
  chunk_path <- file.path(out_dir, sprintf("ready_commands_chunk_%03d.csv", ch))
  fwrite(queue[chunk_id == ch][, chunk_id := NULL], chunk_path)
}
queue[, chunk_id := NULL]

if (!all(queue$parse_ok)) {
  bad <- queue[parse_ok != TRUE, .(item_id, runner_path)]
  print(bad)
  stop("[codegen] generated runner parse failure")
}

cat(sprintf("[codegen-direct] remaining=%d\n", nrow(queue)))
cat(sprintf("[codegen-direct] queue=%s\n", queue_path))
cat(sprintf("[codegen-direct] manifest=%s\n", manifest_path))
cat(sprintf("[codegen-direct] summary=%s\n", summary_path))
cat(sprintf("[codegen-direct] chunks=%d size=%d\n", max(ceiling(seq_len(nrow(queue)) / chunk_size)), chunk_size))
print(summary)
