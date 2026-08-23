#!/usr/bin/env Rscript
#==============================================================================
# lean_carrier_from_btresult.R — lean 산출물 → **캐리어 패널** (v9.2 S3-③, 2026-08-24)
#
#------------------------------------------------------------------------------
# 왜 이것이 단일 최대 레버인가 — 비용 곡선이 뒤집힌다
#------------------------------------------------------------------------------
# 비중 규칙을 재는 축은 둘이고 서로 대체 불가다:
#   lean 축     엔진 런 1회 = 5~25분/arm. 선별이 같이 움직인다(현실적이지만 비싸고 통제가 약하다)
#   캐리어 축   선별 고정 = 초~분/arm. 차이가 **오직 가중 규칙 때문**이라고 말할 수 있다
# 지금까지 캐리어는 book(PG2)에서만 나왔다 — 즉 lean 라운드 수백 건이 캐리어를 못 낳았다.
# 그런데 `04_holdings.csv` 는 **모든 lean 런이 이미 생성**하고 date·ticker·actual_weight·
# signal_score 를 그대로 갖고 있다. 레시피는 extract_book_carrier.R:88-95 와 동일하다.
# ⇒ 엔진 런 1회가 캐리어를 낳고, N개 arm 이 그 위를 초 단위로 탄다.
#
#------------------------------------------------------------------------------
# ★fail-closed 두 축 (없으면 이 변환기는 위험 장치가 된다)
#------------------------------------------------------------------------------
# ① **자기검증**: 변환된 캐리어의 `strategy` arm(= 저장된 actual_weight passthrough)이
#    그 lean 런의 03_period_returns.csv 를 재현해야 한다. 재현 cor < 0.999 면 **저장 거부**.
#    (선례 = extract_book_carrier_d3.R 의 net 재현 cor 0.999916 검증.)
#    이 검사가 없으면 변환기가 조용히 틀린 패널을 만들고 **하류 arm 이 전부 틀린다** —
#    게다가 arm 들끼리는 서로 일관되므로 결과표만 봐서는 알 수 없다.
# ② **risk_controls 거부**: vol_target / dd_brake 가 걸린 런은 **경고가 아니라 거부**한다.
#    lean sim 은 일별 NAV + 월중 브레이크이고 캐리어는 월간 복리다 — 같은 대상이 아니다.
#    월간 계열은 월중 저점을 못 보므로 재현이 맞아도 그 둘은 다른 전략이다.
#
# 사용:
#   Rscript 02_Infrastructure/ops/lean_carrier_from_btresult.R <run_dir> [out_parquet]
#   source(...); lean_carrier_from_btresult("stage_artifacts/alpha_search/2026...")
#==============================================================================

suppressWarnings(suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
}))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

.lc_root <- function() {
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && dir.exists(file.path(v, "06_Registry"))) return(v)
  }
  if (dir.exists("06_Registry")) return(getwd())
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
}

# 오버레이/브레이크 표식 — 01_strategy_spec.json::risk_controls 와 manifest 에서 찾는다.
.LC_REJECT_TOKENS <- c("vol_target", "voltarget", "vol targeting", "dd_brake", "ddbrake",
                       "drawdown brake", "drawdown_brake", "exposure", "overlay")

#' @param run_dir stage_artifacts/alpha_search/<run> (04_holdings.csv 보유)
#' @param out     parquet 경로. NULL 이면 06_Registry/lean_carrier/carrier_<run>.parquet
#' @param min_cor 자기검증 문턱 (fail-closed)
lean_carrier_from_btresult <- function(run_dir, out = NULL, min_cor = 0.999,
                                       rawdata = NULL, root = .lc_root(), quiet = FALSE) {
  rd  <- if (dir.exists(run_dir)) run_dir else file.path(root, run_dir)
  if (!dir.exists(rd)) stop("[lean_carrier] run_dir 부재: ", run_dir)
  run_id <- basename(normalizePath(rd, winslash = "/", mustWork = FALSE))
  hp  <- file.path(rd, "04_holdings.csv")
  prp <- file.path(rd, "03_period_returns.csv")
  if (!file.exists(hp)) stop("[lean_carrier] 04_holdings.csv 부재: ", hp)

  # ── ① risk_controls 거부 (경고 아님) ───────────────────────────────────────
  sp <- file.path(rd, "01_strategy_spec.json")
  spec <- if (file.exists(sp)) tryCatch(fromJSON(sp, simplifyVector = TRUE), error = function(e) list()) else list()
  rc <- tolower(paste(as.character(spec$risk_controls %||% ""),
                      as.character(spec$weighting_method %||% ""), collapse = " "))
  hit <- .LC_REJECT_TOKENS[vapply(.LC_REJECT_TOKENS, function(t) grepl(t, rc, fixed = TRUE), logical(1))]
  if (length(hit))
    stop(sprintf(paste0("[lean_carrier] 거부 — risk_controls 에 %s 검출.\n",
                        "  lean sim 은 일별 NAV + 월중 브레이크이고 캐리어는 월간 복리다 — **같은 대상이 아니다**.\n",
                        "  월간 계열은 월중 저점을 못 본다(실측: exposure≡1 재구성만으로 MDD −9.07pp).\n",
                        "  risk_controls: %s"),
                 paste(hit, collapse = ", "), as.character(spec$risk_controls %||% "?")))

  H <- fread(hp)
  need <- c("date", "ticker", "actual_weight", "signal_score")
  if (!all(need %in% names(H)))
    stop(sprintf("[lean_carrier] 04_holdings.csv 컬럼 결손: %s",
                 paste(setdiff(need, names(H)), collapse = ", ")))
  H[, date := as.Date(date)]
  H <- H[!is.na(date) & !is.na(ticker) & is.finite(actual_weight) & actual_weight > 0]
  if (!nrow(H)) stop("[lean_carrier] 유효 보유행 0")

  dts <- sort(unique(H$date))
  if (length(dts) < 6L) stop(sprintf("[lean_carrier] 리밸일 %d개 — 캐리어로 쓰기엔 부족", length(dts)))
  # 마지막 리밸일은 forward 창이 열려 있어 캐리어 행이 될 수 없다(eval_date 미확정).
  per <- data.table(decision_date = dts[-length(dts)], next_decision = dts[-1L])

  # ── ret_fwd: extract_book_carrier.R:88-95 verbatim ─────────────────────────
  #   start_d = 첫 raw Date >= decision_date · end_d = 첫 raw Date >= next_decision
  #   ret_fwd = prod(1+Ret)-1 over (start_d, end_d]   ← C2 준수(매수일 당일 수익 제외)
  rp <- rawdata %||% file.path(root, ".cache", "rawdata.parquet")
  if (!file.exists(rp)) stop("[lean_carrier] rawdata 부재: ", rp)
  tks <- unique(H$ticker)
  raw <- as.data.table(read_parquet(rp, col_select = c("Date", "Ticker", "Ret")))
  raw <- raw[Ticker %in% tks]
  raw[, Date := as.Date(Date)]
  setkey(raw, Date)
  rdates <- sort(unique(raw$Date))
  .first_ge <- function(d) { i <- findInterval(d - 1e-9, rdates) + 1L
                             if (i > length(rdates)) NA else rdates[i] }
  per[, start_d := as.Date(vapply(decision_date, function(d) as.character(.first_ge(d)), character(1)))]
  per[, end_d   := as.Date(vapply(next_decision, function(d) as.character(.first_ge(d)), character(1)))]
  per <- per[!is.na(start_d) & !is.na(end_d) & end_d > start_d]
  if (!nrow(per)) stop("[lean_carrier] 유효 보유창 0 — rawdata 달력과 리밸일이 안 맞는다")

  rows <- vector("list", nrow(per))
  for (i in seq_len(nrow(per))) {
    dd <- per$decision_date[i]; sd_i <- per$start_d[i]; ed <- per$end_d[i]
    hi <- H[date == dd, .(Ticker = ticker, weight_strategy = as.numeric(actual_weight),
                          score = as.numeric(signal_score))]
    if (!nrow(hi)) next
    hi <- hi[, .(weight_strategy = sum(weight_strategy), score = mean(score)), by = Ticker]
    hi[, weight_strategy := weight_strategy / sum(weight_strategy)]     # 재정규화(현금 잔여 제거)
    pd <- raw[Date > sd_i & Date <= ed & Ticker %in% hi$Ticker, .(Date, Ticker, Ret)]
    sr <- pd[, .(ret_fwd = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    hi <- merge(hi, sr, by = "Ticker", all.x = TRUE)
    hi[is.na(ret_fwd), ret_fwd := 0]
    setorder(hi, -score); hi[, rank := seq_len(.N)]
    rows[[i]] <- hi[, .(decision_date = dd, eval_date = ed, Ticker, score,
                        weight_strategy, ret_fwd, rank, selected = TRUE)]
  }
  P <- rbindlist(Filter(Negate(is.null), rows), use.names = TRUE)
  if (!nrow(P)) stop("[lean_carrier] 추출 행 0")

  # ── ② 자기검증 — strategy arm 이 lean 런의 03_period_returns 를 재현하는가 ──
  M <- P[, .(port_ret_gross_recon = sum(weight_strategy * ret_fwd)), by = .(decision_date, eval_date)]
  setorder(M, eval_date)
  val <- list(status = "SKIPPED", reason = "03_period_returns.csv 부재")
  if (file.exists(prp)) {
    PR <- fread(prp)
    if (!all(c("date", "ret_gross") %in% names(PR))) {
      val <- list(status = "SKIPPED", reason = "03_period_returns 컬럼 결손(date/ret_gross)")
    } else {
      PR[, d := as.Date(date)]; PR[, rg := as.numeric(ret_gross)]
      PR <- PR[!is.na(d) & is.finite(rg)]
      # 일별 계열이면 같은 (start_d, eval_date] 창으로 복리 — 월간 계열이면 창 안 합산.
      ref <- vapply(seq_len(nrow(per)), function(i) {
        v <- PR[d > per$start_d[i] & d <= per$end_d[i], rg]
        if (!length(v)) NA_real_ else prod(1 + v) - 1
      }, numeric(1))
      CMP <- merge(M, data.table(eval_date = per$end_d, ret_ref = ref), by = "eval_date")
      CMP <- CMP[is.finite(ret_ref) & is.finite(port_ret_gross_recon)]
      if (nrow(CMP) < 12L) {
        val <- list(status = "FAIL", reason = sprintf("정렬 표본 %d(<12) — 재현 검증 불가", nrow(CMP)))
      } else {
        cr <- suppressWarnings(stats::cor(CMP$port_ret_gross_recon, CMP$ret_ref))
        md <- max(abs(CMP$port_ret_gross_recon - CMP$ret_ref))
        val <- list(status = if (is.finite(cr) && cr >= min_cor) "PASS" else "FAIL",
                    n = nrow(CMP), cor = round(cr, 6), max_abs_diff = signif(md, 4),
                    min_cor = min_cor,
                    note = "recon = Σ w_strategy·ret_fwd (gross) vs 03_period_returns 창내 복리")
      }
    }
  }
  if (!quiet)
    cat(sprintf("[lean_carrier] %s — months=%d rows=%d | VALIDATE %s (cor=%s max|diff|=%s n=%s)\n",
                run_id, nrow(M), nrow(P), val$status, as.character(val$cor %||% NA),
                as.character(val$max_abs_diff %||% NA), as.character(val$n %||% NA)))

  if (!identical(val$status, "PASS"))
    stop(sprintf(paste0("[lean_carrier] ★저장 거부 — 자기검증 %s (%s).\n",
                        "  재현이 안 되는 패널은 하류 arm 을 **전부** 틀리게 만들고, arm 끼리는 ",
                        "일관되므로 결과표만으로는 잡히지 않는다."),
                 val$status, as.character(val$reason %||% sprintf("cor=%s < %s", val$cor, min_cor))))

  # ── 저장 ───────────────────────────────────────────────────────────────────
  outdir <- file.path(root, "06_Registry", "lean_carrier")
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  op <- out %||% file.path(outdir, sprintf("carrier_%s.parquet", run_id))
  write_parquet(P, op)
  meta <- list(
    schema = "lean_carrier_v1", run_id = run_id, source_run_dir = run_dir,
    parquet = op, n_months = nrow(M), n_rows = nrow(P),
    decision_first = as.character(min(P$decision_date)), eval_last = as.character(max(P$eval_date)),
    recipe = "extract_book_carrier.R:88-95 verbatim — ret_fwd = prod(1+Ret)-1 over (start_d, end_d]",
    basis = "monthly_recon",
    basis_warning = paste0("★월간 복리 계열이다. 일별 NAV(daily_native) 와 직접 비교 금지 — ",
                           "exposure≡1 재구성만으로 MDD −9.07pp / Calmar +11.3% 가 난다(basis 착시)."),
    strategy_id = as.character(spec$strategy_id %||% NA_character_),
    strategy_name = as.character(spec$strategy_name %||% NA_character_),
    weighting_method = as.character(spec$weighting_method %||% NA_character_),
    risk_controls = as.character(spec$risk_controls %||% NA_character_),
    cost_model = as.character(spec$cost_model %||% NA_character_),
    validation = val,
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    generator = "02_Infrastructure/ops/lean_carrier_from_btresult.R")
  mp <- sub("\\.parquet$", "_meta.json", op)
  writeLines(as.character(toJSON(meta, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)), mp)
  if (!quiet) cat(sprintf("[lean_carrier] 저장 %s (+meta)\n", op))
  invisible(list(parquet = op, meta = mp, panel = P, monthly = M, validation = val))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (!length(a)) {
    cat("usage: Rscript 02_Infrastructure/ops/lean_carrier_from_btresult.R <run_dir> [out_parquet]\n")
    quit(save = "no", status = 2)
  }
  r <- tryCatch(lean_carrier_from_btresult(a[1], out = if (length(a) > 1) a[2] else NULL),
                error = function(e) { cat(conditionMessage(e), "\n"); NULL })
  quit(save = "no", status = if (is.null(r)) 1 else 0)
}
