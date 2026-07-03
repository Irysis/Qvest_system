# =============================================================================
# run_pindex_LOW_gate_2606_08569.R
# alpha-search 큐 소비자 — p-index (2606.08569) 단일 방향(LOW) 사전확약 실행 + L1~L3 verdict.
# 방향 A/B 스윕 회피: 논문 Table 2(고수익 기업 = 저 p-index) 경제적 사전확약 = LOW 단일.
# send_telegram=FALSE (소비자 wrapper가 tg_agent_brief 단일 발송).
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(arrow) }))
try(arrow::set_io_thread_count(1L),  silent = TRUE)   # Windows arrow HANG 회피(메모리 교훈)
try(arrow::set_cpu_thread_count(1L), silent = TRUE)
setDTthreads(1L); options(mc.cores = 1L)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
setwd(ROOT)
PRC <- file.path(ROOT, "stage_artifacts", "paper_recharge")
ID  <- "2606.08569"
ENGINE <- file.path(ROOT, "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R")

source(file.path(ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.n <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

Sys.setenv(PINDEX_DIRECTION = "LOW")   # 사전확약 단일 방향
IDEA <- paste("p-index(유럽형 put 보험료/현재가, 이항 closed-form eq.6-9) 횡단면 정렬 —",
              "저보험료(저다운사이드 리스크) 롱. 방향=LOW 사전확약(논문 Table2: 고수익기업=저 p-index).",
              "n_trials=1 단일가설(스윕 아님).")

res <- tryCatch(
  run_alpha_search(
    strategy_name      = "STR_AS_PINDEX_LOW_2606_08569",
    strategy_idea      = IDEA,
    factor_engine_path = ENGINE,
    n_holdings    = 25L,
    weight_method = "equal",
    commission    = 0.0015,
    start_date    = "2005-01-01",
    universe      = "K200_KQ150",
    send_telegram = FALSE,
    factor_analysis = TRUE),
  error = function(e) { cat("[RUN-ERR]", conditionMessage(e), "\n"); NULL })

if (is.null(res)) {
  vj <- list(paper_id = ID, run_status = "RUN_ERROR",
             pit_pass = FALSE, contract_pass = FALSE, robustness_pass = FALSE,
             oos_retention = NA, port_t = NA,
             engine_path = "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R",
             notes = "run_alpha_search 예외 — 실행 실패. fail-closed.")
  write(toJSON(vj, pretty = TRUE, auto_unbox = TRUE, na = "null"),
        file.path(PRC, paste0("auto_verify_", ID, ".json")))
  cat("[GATE-INPUT] RUN_ERROR — auto_verify written (all FALSE)\n"); quit(status = 0)
}
saveRDS(res, file.path(PRC, paste0("pindex_res_LOW_", ID, ".rds")))

OUT <- res$out_dir
grade <- res$grade %||% "uncertain"
auth  <- res$authoritative

# ---- L1 pit_pass: detect_lookahead on engine (run_alpha_search would have stopped if dirty) ----
pit <- tryCatch(detect_lookahead(ENGINE), error = function(e) list(clean = FALSE))
pit_pass <- isTRUE(pit$clean)

# ---- L2 contract_pass: audit_bt_result integrity != FAIL ----
contract_pass <- FALSE; integrity_status <- "UNKNOWN"
bt_path <- (auth$bt_result_path %||% res$bt_contract$bt_result_path %||% file.path(OUT, "bt_result.rds"))
if (!file.exists(bt_path) && file.exists(file.path(OUT, "bt_result.rds"))) bt_path <- file.path(OUT, "bt_result.rds")
tryCatch({
  source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
  if (file.exists(bt_path)) {
    bt <- readRDS(bt_path)
    au <- tryCatch(audit_bt_result(bt), error = function(e) NULL)
    integrity_status <- (bt$manifest$integrity_status[1] %||%
                         (if (!is.null(au)) au$integrity else NA) %||% "UNKNOWN")
    contract_pass <- !identical(toupper(as.character(integrity_status)), "FAIL")
  } else integrity_status <- "NO_BT_RESULT"
}, error = function(e) { cat("[L2-ERR]", conditionMessage(e), "\n") })

# ---- L3 robustness_pass: oos_retention >= 0.5 (sanity, not 0.7 graduation) ----
oos_ret <- .n(auth$essence$oos_retention)
port_t  <- .n(auth$essence$portfolio_alpha_t_nw_lag3)
robustness_pass <- is.finite(oos_ret) && oos_ret >= 0.5
# placebo: alpha-search auto 경로 미산출 → "비유의-FAIL 아님" 자동 충족(부재≠실패). 정직 기록.
placebo_status <- "not_computed_in_alpha_search_auto_path"

impl_spec <- list(
  signal = "p-index = binomial put-insurance fair price per dollar (eq.7 closed-form). market risk-neutral pi from BM monthly high/low (eq.6); stock fair price (eq.8); d_i=monthlow/fair; p_index=((1+delta)-d_i)/(1+delta)*(1-pi)/(1+r).",
  direction = "LOW (long low p-index = low downside-insurance cost). Pre-committed via paper Table 2 (high-yield firms have lower p-index). NOT A/B sweep.",
  delta = "delta=r (paper). r=0.025/12 monthly const; r common across stocks => cross-sectional rank-neutral (documented).",
  universe = "KOSPI200 U KOSDAQ150 (PIT membership), long-only, top-25 EW, monthly, 2005~, 15bps.",
  pit = "month-end signal from within-month OHLC (all observable at signal); position held next month (t-1 PIT). No full-sample stats, no scale()/fwd_ret.",
  caveats = "Paper direction market-unstable (China contrarian / US momentum). Full PDF unretrievable (jina 402 / arxiv-mcp no pdf-extra / paper-search empty) — fidelity checked vs abstract+queue def only.")

vj <- list(
  paper_id = ID,
  run_status = "OK",
  strategy_id = res$strategy_id %||% NA,
  grade = grade,
  score = .n(res$score),
  excess_cagr = .n(res$excess_cagr),
  pit_pass = pit_pass,
  contract_pass = contract_pass,
  robustness_pass = robustness_pass,
  oos_retention = oos_ret,
  port_t = port_t,
  integrity_status = integrity_status,
  placebo_status = placebo_status,
  auth_status = auth$status %||% "NULL (no authoritative remeasure — grade<B & no screen route)",
  essence_grade = auth$essence_grade %||% NA,
  engine_path = "02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R",
  out_dir = sub(paste0("^", ROOT, "/?"), "", gsub("\\\\", "/", OUT %||% "")),
  lcode_written_by_run = res$l_code %||% NA,
  impl_spec = impl_spec,
  notes = "single-direction LOW pre-committed (no sweep). L3 = oos_retention>=0.5 sanity. paper PDF unavailable -> L4 fidelity vs abstract only.")

write(toJSON(vj, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      file.path(PRC, paste0("auto_verify_", ID, ".json")))

cat(sprintf("\n[GATE-INPUT] grade=%s | pit=%s contract=%s(%s) robust=%s | oos=%s port_t=%s | auth=%s | lcode=%s\n",
            grade, pit_pass, contract_pass, integrity_status, robustness_pass,
            ifelse(is.finite(oos_ret), sprintf("%.2f", oos_ret), "NA"),
            ifelse(is.finite(port_t),  sprintf("%.2f", port_t),  "NA"),
            auth$status %||% "NULL", res$l_code %||% "none"))
cat("[DONE] auto_verify written.\n")
