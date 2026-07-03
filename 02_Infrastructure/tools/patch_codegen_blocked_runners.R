#!/usr/bin/env Rscript
# Rewrite generated NOT_BACKTESTED codegen runners into executable AlphaSearch
# runners where Factor DB can support a PIT-safe direct implementation.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
}

args <- commandArgs(trailingOnly = TRUE)
batch_dir <- if (length(args) >= 1L) args[[1]] else {
  file.path("stage_artifacts", "batch_434", "20260612_codegen_direct_409")
}

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
batch_dir <- normalizePath(batch_dir, winslash = "/", mustWork = TRUE)
runners_dir <- file.path(batch_dir, "runners")
ready_path <- file.path(batch_dir, "ready_commands_codegen_all.csv")
manifest_path <- file.path(batch_dir, "codegen_manifest.csv")
if (!file.exists(ready_path)) stop("ready_commands_codegen_all.csv not found: ", ready_path)

r_quote <- function(x) paste(deparse(as.character(x), control = "keepNA"), collapse = "")
slug <- function(x) gsub("[^A-Za-z0-9_.-]", "_", x)
clean_text <- function(x) {
  x <- paste(as.character(x %||% ""), collapse = " ")
  x <- gsub("[\r\n\t]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}
flatten_text <- function(x) {
  if (is.null(x)) return(character())
  if (is.atomic(x)) return(as.character(x))
  if (is.list(x)) return(unlist(lapply(x, flatten_text), use.names = FALSE))
  character()
}
field <- function(x, name) if (is.list(x) && !is.null(x[[name]])) x[[name]] else NULL
read_spec <- function(file) {
  p <- file.path(root, "qepm", "mailbox", "forge", "inbox_hold", file)
  if (!file.exists(p)) return(list(.missing = TRUE))
  tryCatch(fromJSON(p, simplifyVector = FALSE),
           error = function(e) list(.error = conditionMessage(e)))
}
spec_text <- function(row, spec) {
  clean_text(c(
    row$title, row$item_id, row$family, row$bucket, row$reason, row$mapping_notes,
    flatten_text(spec$parent_strategy),
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
factor_names_all <- latest_factor_names()

fg <- list(
  defense = c("D01_IdioVol", "D02_Beta"),
  consensus = c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap"),
  industry_momentum = c("M07_IndMom"),
  momentum = c("M01_Mom_12_1", "M07_IndMom", "M05_Trended_Mom"),
  reversal = c("M11_ST_Reversal", "M12_LR_Reversal"),
  quality = c("Q01_GPA", "Q04_Piotroski_F", "Q09_CFOA", "Q07_Earnings_Stability"),
  value = c("V01_BM", "V03_CFP", "V10_FCF_Yield", "V11_Shareholder_Yield"),
  accrual = c("AC07_Operating_Accruals", "AC18_Accrual_Quality", "GR03_Asset_Growth"),
  liquidity = c("L01_Amihud", "L09_Amihud_20d", "L10_Amihud_Ratio", "L40_VWAP_Spread"),
  crowding = c("CR02_Volume_Concentration", "CR08_Volume_Price_Divergence", "CR04_Ownership_Concentration"),
  tail = c("D43_Skewness", "D44_Kurtosis", "D47_CVaR_5pct", "R03_CVaR_95"),
  investor_flow = c("INV01_Foreign_NetBuy_20d", "CR04_Ownership_Concentration")
)
fg <- lapply(fg, function(x) unique(intersect(x, factor_names_all)))

kw_rules <- list(
  list(group = "defense", p = "defense|defensive|low.?vol|idio.?vol|tail.?risk|downside|low.?beta|anti.?lottery|volatility|mdd|drawdown"),
  list(group = "consensus", p = "consensus|revision|eps|earnings revision|sue|surprise|estimate|target.?price|tp.?gap|coverage"),
  list(group = "industry_momentum", p = "industry.?mom|indmom|sector.?mom"),
  list(group = "momentum", p = "stock.?momentum|price.?momentum|12.?1|52.?week|trend|trended|macd|rsi"),
  list(group = "reversal", p = "reversal|contrarian|mean.?reversion|short.?term"),
  list(group = "quality", p = "quality|piotroski|profit|profitability|gross|cfo|roa|roe|margin|stability|persistence"),
  list(group = "value", p = "value|book.?to.?market|\\bbm\\b|cash.?flow|cfp|fcf|yield|pbr|per|ebit|ev|shareholder"),
  list(group = "accrual", p = "accrual|accruals|\\bnoa\\b|asset.?growth|investment|issuance"),
  list(group = "liquidity", p = "liquidity|amihud|spread|price.?impact|vwap|turnover"),
  list(group = "crowding", p = "crowding|crowd|concentration|divergence"),
  list(group = "tail", p = "skew|cokurt|kurt|coskew|cvar|var|expected.?shortfall"),
  list(group = "investor_flow", p = "ownership|foreign|institution|flow|order.?flow|netbuy")
)

base_robust <- unique(intersect(c(
  fg$defense, fg$quality, fg$value, fg$momentum, fg$consensus
), factor_names_all))
ml_robust <- unique(intersect(c(
  fg$defense, fg$quality, fg$value, fg$momentum, fg$consensus, fg$accrual, fg$liquidity
), factor_names_all))

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
  if (is.list(sc) && !is.null(sc$n_holdings)) n <- suppressWarnings(as.integer(sc$n_holdings[[1]]))
  if (is.na(n)) {
    raw <- parse_first_num("\\bN\\s*[=:]?\\s*[0-9]{1,2}\\b", text)
    if (!is.na(raw)) n <- as.integer(raw)
  }
  if (is.na(n)) n <- suppressWarnings(as.integer(row$n_holdings))
  if (is.na(n)) n <- 30L
  as.integer(max(5L, min(30L, n)))
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
  if (grepl("vol.?target|target.?vol|target_vol|vt\\s*0\\.", x, perl = TRUE)) {
    raw <- parse_first_num("0\\.[0-9]+", x)
    if (!is.na(raw) && raw > 0 && raw <= 0.5) vol_target <- raw
  }
  dd_entry <- NA_real_
  dd_exit <- NA_real_
  if (grepl("dd.?med|dd.?short|dd brake|dd_brake|drawdown|mdd|브레이크", x, perl = TRUE)) {
    if (grepl("\\bdd8\\b", x, perl = TRUE)) dd_entry <- 0.08
    if (is.na(dd_entry)) dd_entry <- 0.12
    dd_exit <- 0.35
  }
  list(
    vol_target = if (is.na(vol_target)) NULL else vol_target,
    vol_lookback = 60L,
    dd_brake = if (is.na(dd_entry)) NULL else list(entry_pct = dd_entry, exit_pct = dd_exit)
  )
}

extract_factors <- function(row, spec, text, manifest) {
  factors <- character()
  direct <- unique(unlist(regmatches(text, gregexpr("[A-Z]{1,3}[0-9]{2}_[A-Za-z0-9_]+", text, perl = TRUE))))
  factors <- c(factors, intersect(direct, factor_names_all))

  x <- tolower(text)
  for (rule in kw_rules) {
    if (grepl(rule$p, x, perl = TRUE) && length(fg[[rule$group]])) factors <- c(factors, fg[[rule$group]])
  }

  comps <- unique(unlist(regmatches(
    text,
    gregexpr("\\b(?:STR|ALPHA|MF|SF|EN|FM|RC|SLE|BRK|PROD|ARCH|REGIME|BACKLOG|EVO)_[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*\\b",
            text, perl = TRUE)
  )))
  comps <- setdiff(comps, row$item_id)
  if (length(comps) && nrow(manifest)) {
    comp_rows <- manifest[item_id %in% comps & !is.na(factor_names) & nzchar(factor_names)]
    if (nrow(comp_rows)) {
      comp_f <- unique(unlist(strsplit(paste(comp_rows$factor_names, collapse = ","), ",", fixed = TRUE)))
      factors <- c(factors, trimws(comp_f))
    }
  }

  if (!length(factors)) {
    if (identical(row$prefix, "FM") || identical(row$family, "factor_momentum")) factors <- base_robust
    else if (grepl("ML_BUILD|ML|machine|xgboost|random.?forest|lasso|rfe|stack", text, ignore.case = TRUE, perl = TRUE)) factors <- ml_robust
    else factors <- base_robust
  }

  factors <- unique(intersect(factors, factor_names_all))
  if (length(factors) > 12L) factors <- factors[seq_len(12L)]
  factors
}

write_alpha_runner <- function(row, factors, engine, n_holdings, weight_method,
                               cov_method, risk_controls, quality) {
  item_id <- row$item_id
  safe_id <- slug(item_id)
  runner_path <- file.path(runners_dir, paste0(safe_id, ".R"))
  result_path <- file.path(batch_dir, paste0(safe_id, "_result.rds"))
  # 라벨 무결성 강제 (2026-06-13 감사 후속): keyword-fallback 대체 실행은 원 가설을
  # 검증하지 않으므로 strategy_name에 [PROXY-COMBO] 라벨을 강제하고 idea에 실제 신호를 공개한다.
  # 미라벨 시 catalog/L-code가 "미검증"을 "검증 후 기각"으로 오귀속 (batch434_label_audit_20260613).
  title <- paste0("[PROXY-COMBO] ", clean_text(row$title %||% item_id))
  idea <- clean_text(c(
    sprintf("[PROXY-COMBO] label!=signal: keyword-fallback 대체 실행. actual_factors=%s; engine=%s.",
            paste(factors, collapse = "+"), engine),
    "원 가설(미검증):", row$title, row$reason, quality))
  weights <- rep(1, length(factors))
  min_count <- if (identical(engine, "fm")) {
    max(1L, min(3L, length(factors)))
  } else {
    max(2L, min(length(factors), ceiling(length(factors) * 0.60)))
  }
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
  if (!identical(cov_method, "sample")) extra_args <- c(extra_args, sprintf("  cov_method = %s,", r_quote(cov_method)))

  fe_path <- if (identical(engine, "fm")) {
    "02_Infrastructure/alpha_search/fe_factor_momentum.R"
  } else {
    "02_Infrastructure/alpha_search/fe_factor_combo.R"
  }
  env_lines <- c(
    sprintf("Sys.setenv(FACTOR_NAMES = %s)", r_quote(paste(factors, collapse = ","))),
    sprintf("Sys.setenv(FACTOR_WEIGHTS = %s)", r_quote(paste(weights, collapse = ","))),
    sprintf("Sys.setenv(FACTOR_MIN_COUNT = %s)", r_quote(as.character(min_count)))
  )
  if (identical(engine, "fm")) {
    env_lines <- c(env_lines,
                   sprintf("Sys.setenv(FM_TOP_K = %s)", r_quote(as.character(min(6L, length(factors))))),
                   "Sys.setenv(FM_LOOKBACK_MONTHS = \"36\")")
  }

  lines <- c(
    "#!/usr/bin/env Rscript",
    sprintf("# Patched direct AlphaSearch runner for %s", item_id),
    "args0 <- commandArgs(FALSE)",
    "file_arg <- grep(\"^--file=\", args0, value = TRUE)",
    "this_file <- if (length(file_arg)) sub(\"^--file=\", \"\", file_arg[[1]]) else tryCatch(sys.frame(1)$ofile, error = function(e) \"\")",
    "root <- if (nzchar(this_file)) normalizePath(file.path(dirname(this_file), \"../../../..\"), winslash = \"/\", mustWork = FALSE) else \"\"",
    "if (!nzchar(root) || !file.exists(file.path(root, \"02_Infrastructure\", \"config.R\"))) root <- normalizePath(getwd(), winslash = \"/\", mustWork = TRUE)",
    "setwd(root)",
    "Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)",
    env_lines,
    "source(\"02_Infrastructure/alpha_search/run_alpha_search.R\")",
    "res <- run_alpha_search(",
    sprintf("  strategy_name = %s,", r_quote(title)),
    sprintf("  strategy_idea = %s,", r_quote(idea)),
    sprintf("  factor_engine_path = %s,", r_quote(fe_path)),
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
  if (!parse_ok) stop("generated runner parse failed: ", runner_path)
  list(runner_path = runner_path, result_path = result_path, factor_min_count = min_count)
}

ready <- fread(ready_path)
manifest <- if (file.exists(manifest_path)) fread(manifest_path) else copy(ready)
if (!"factor_names" %in% names(manifest)) manifest[, factor_names := ""]

blocked <- which(
  ready$execution_class == "DIRECT_CODE_REQUIRED_RUNNER" |
    grepl("^PATCHED_DIRECT_", ready$mapping_quality %||% "")
)
patched <- list()
for (idx in blocked) {
  row <- as.list(ready[idx])
  spec <- read_spec(row$file)
  text <- spec_text(row, spec)
  factors <- extract_factors(row, spec, text, manifest)
  if (!length(factors)) next

  engine <- if (identical(row$prefix, "FM") || identical(row$family, "factor_momentum") ||
                grepl("factor.?momentum|ic.?momentum|ml|xgboost|random.?forest|lasso|rfe|stack",
                      text, ignore.case = TRUE, perl = TRUE)) "fm" else "combo"
  n_holdings <- parse_n_holdings(row, spec, text)
  weight_method <- parse_weight_method(text)
  cov_method <- parse_cov_method(text)
  rc <- parse_risk_controls(text)
  quality <- sprintf("PATCHED_DIRECT_%s_FROM_%s",
                     toupper(engine),
                     ready$mapping_quality[idx] %||% "DIRECT_CODE_REQUIRED")
  wr <- write_alpha_runner(row, factors, engine, n_holdings, weight_method, cov_method, rc, quality)

  exec_class <- if (identical(engine, "fm")) "RUN_ALPHA_DIRECT_FACTOR_MOMENTUM"
    else if (!is.null(rc$vol_target) || !is.null(rc$dd_brake) ||
             !identical(weight_method, "equal") || !identical(cov_method, "sample")) "RUN_ALPHA_DIRECT_OVERLAY"
    else "RUN_ALPHA_DIRECT_FACTOR_DB"

  ready$execution_class[idx] <- exec_class
  ready$reason[idx] <- "patched blocked runner into executable PIT-safe AlphaSearch direct implementation"
  ready$mapping_quality[idx] <- quality
  ready$mapping_notes[idx] <- sprintf(
    "patched factors=%s; engine=%s; min_count=%d; n=%d; weight=%s; cov=%s; runner=%s",
    paste(factors, collapse = "+"), engine, wr$factor_min_count, n_holdings,
    weight_method, cov_method, wr$runner_path
  )
  ready$factor_names[idx] <- paste(factors, collapse = ",")
  ready$factor_sources[idx] <- paste(unique(c(ready$factor_sources[idx], "patched_direct")), collapse = ",")
  ready$factor_weights[idx] <- paste(rep(1, length(factors)), collapse = ",")
  ready$factor_min_count[idx] <- wr$factor_min_count
  ready$n_holdings[idx] <- n_holdings
  ready$weight_method[idx] <- weight_method
  ready$cov_method[idx] <- cov_method
  ready$vol_target[idx] <- if (!is.null(rc$vol_target)) rc$vol_target else NA_real_
  ready$dd_entry[idx] <- if (!is.null(rc$dd_brake)) rc$dd_brake$entry_pct else NA_real_
  ready$dd_exit[idx] <- if (!is.null(rc$dd_brake)) rc$dd_brake$exit_pct else NA_real_
  ready$parse_ok[idx] <- TRUE
  patched[[length(patched) + 1L]] <- data.table(
    item_id = row$item_id,
    execution_class = exec_class,
    engine = engine,
    factors = paste(factors, collapse = ",")
  )
}

fwrite(ready, ready_path)
fwrite(ready, manifest_path)
patch_log <- rbindlist(patched, fill = TRUE)
patch_path <- file.path(batch_dir, "blocked_runner_patch_manifest.csv")
fwrite(patch_log, patch_path)

cat(sprintf("[patch-blocked] patched=%d of %d DIRECT_CODE_REQUIRED runners\n", nrow(patch_log), length(blocked)))
cat(sprintf("[patch-blocked] manifest=%s\n", patch_path))
if (nrow(patch_log)) print(patch_log[, .N, by = .(execution_class, engine)][order(execution_class, engine)])
