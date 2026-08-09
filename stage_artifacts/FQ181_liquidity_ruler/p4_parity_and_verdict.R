## FQ-181 P4 — (A) 실데이터 하위호환 parity  +  (B) ④ 게이트 판정 영향 A/B
##
## (A) 교정 전(git fc33bb78) / 후 함수를 **같은 일간 패널**에 걸어
##     returns_dt · bench_dt 가 bit-동일한지(=자 교정이 수익·벤치를 침범 안 했는지) 확인.
##     liq_dt 만 달라야 하고, 그 차이가 P2 가 예측한 자 차이와 일치해야 한다.
##
## (B) WT-001 **미필터(superseded)** 패널에 유동성 자 A/B 를 각각 걸어 top-25 를 뽑고
##     canonical_screen_bt 로 PORT_t 를 실측 → HARD 게이트(2.95) 판정이 움직이는가.
##     ★소급 재작성 없음 — 구 산출물 불변, 비교값은 이 디렉터리에만.
##
## 산출: p4_parity_verdict.json

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")
LIQ_MIN <- 2e8
res <- list()

## ── 교정판 로드 ─────────────────────────────────────────────────────────────
source(file.path(QM, "02_Infrastructure/ramp/factor_validation.R"))
new_fn <- build_monthly_forward_returns
new_adv <- build_adv20_t1

## ── 구판 로드 (별도 env — 이름 충돌 방지) ───────────────────────────────────
legacy_env <- new.env()
suppressMessages(sys.source(file.path(OUT, "_legacy_factor_validation.R"), envir = legacy_env))
old_fn <- get("build_monthly_forward_returns", envir = legacy_env)
cat("[setup] 구판/교정판 함수 로드 완료\n")
cat(sprintf("[setup] 구판 시그니처 = %s | 교정판 = %s\n",
            paste(names(formals(old_fn)), collapse=","), paste(names(formals(new_fn)), collapse=",")))

## ══════════════════════════════════════════════════════════════════════════
## (A) 실데이터 parity
## ══════════════════════════════════════════════════════════════════════════
cat("\n=== (A) 하위호환 parity (실데이터) ===\n")
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
R <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select = all_of(.need)))
R[, Date := as.Date(Date)]
R <- R[Date >= as.Date("2018-01-01")]     # 비용 제한(asof_close 전체스캔) — parity 판정에 충분
D <- sort(unique(R$Date))
ME <- sort(unname(as.Date(vapply(split(D, format(D,"%Y-%m")), function(v) as.character(max(v)), character(1)))))
cat(sprintf("[A] 입력 실측: 행 %s · 거래일 %d · 월말 %d (%s..%s) · 월당 거래일 중앙 %d\n",
            format(nrow(R), big.mark=","), length(D), length(ME), min(ME), max(ME),
            as.integer(median(as.integer(table(format(D,"%Y-%m")))))))

t0 <- Sys.time(); f_old <- old_fn(R, ME); t_old <- as.numeric(difftime(Sys.time(), t0, units="secs"))
t0 <- Sys.time(); f_new <- suppressWarnings(new_fn(R, ME)); t_new <- as.numeric(difftime(Sys.time(), t0, units="secs"))
cat(sprintf("[A] 구판 %.1fs / 교정판 %.1fs\n", t_old, t_new))

ret_same   <- isTRUE(all.equal(f_old$returns_dt, f_new$returns_dt))
bench_same <- isTRUE(all.equal(f_old$bench_dt,   f_new$bench_dt))
fw_same    <- identical(f_old$ret_firewall_dropped, f_new$ret_firewall_dropped)
cat(sprintf("[A] returns_dt 동일 = %s (행 %s)\n", ret_same, format(nrow(f_new$returns_dt), big.mark=",")))
cat(sprintf("[A] bench_dt   동일 = %s\n", bench_same))
cat(sprintf("[A] ret_firewall_dropped 동일 = %s\n", fw_same))
cat(sprintf("[A] 구판 liq_ruler 필드 = %s (구판엔 없음이 정상) / 교정판 = %s\n",
            is.null(f_old$liq_ruler), f_new$liq_ruler))

L <- merge(f_old$liq_dt[, .(Date, Ticker, adv_old = adv)],
           f_new$liq_dt[, .(Date, Ticker, adv_new = adv)], by = c("Date","Ticker"))
L <- L[!is.na(adv_old) & !is.na(adv_new)]
L[, `:=`(p_old = adv_old >= LIQ_MIN, p_new = adv_new >= LIQ_MIN)]
cat(sprintf("[A] liq_dt 대조 %s 종-월: 상관 %.4f · 판정 불일치 %.3f%% (구판만통과 %.3f%% / 교정만통과 %.3f%%)\n",
            format(nrow(L), big.mark=","), cor(L$adv_old, L$adv_new),
            100*L[, mean(p_old != p_new)], 100*L[, mean(p_old & !p_new)], 100*L[, mean(!p_old & p_new)]))

res$parity <- list(
  window = paste0(min(ME), "..", max(ME)), n_month_ends = length(ME),
  returns_dt_identical = ret_same, bench_dt_identical = bench_same,
  ret_firewall_identical = fw_same,
  legacy_has_liq_ruler_field = !is.null(f_old$liq_ruler), new_liq_ruler = f_new$liq_ruler,
  liq_rows = nrow(L), liq_correlation = cor(L$adv_old, L$adv_new),
  liq_disagree_pct = 100*L[, mean(p_old != p_new)],
  legacy_only_pct = 100*L[, mean(p_old & !p_new)], new_only_pct = 100*L[, mean(!p_old & p_new)],
  secs_legacy = t_old, secs_new = t_new)

## ══════════════════════════════════════════════════════════════════════════
## (B) ④ 판정 영향 A/B — WT-001 미필터 패널
## ══════════════════════════════════════════════════════════════════════════
cat("\n=== (B) ④ 게이트 판정 영향 A/B ===\n")
sup <- "stage_artifacts/WT_D20260808_001/alpha_scores_superseded_20260809.parquet"
if (!file.exists(sup)) {
  cat("[B] 미필터 패널 부재 — 이 축 측정 불가(정지 신호 아님, 대상 부재).\n")
  res$verdict_ab <- list(status = "skipped", reason = paste("패널 부재:", sup))
} else {
  P <- as.data.table(read_parquet(sup))
  scol <- intersect(c("score","score_q01filtered"), names(P))[1]
  cat(sprintf("[B] 입력 실측: 행 %s · 월 %d · 기간 %s..%s · score 컬럼=%s\n",
              format(nrow(P), big.mark=","), uniqueN(P$Date), min(P$Date), max(P$Date), scol))
  P <- P[!is.na(get(scol))]
  PME <- sort(unique(as.Date(P$Date)))

  ## 두 자를 그 패널의 (Ticker, 월말) 에 붙인다
  R2 <- as.data.table(read_parquet(".cache/rawdata.parquet",
          col_select = all_of(c("Date","Ticker","Close","Vol","K200","KQ150","Size"))))
  R2[, Date := as.Date(Date)]
  D2 <- sort(unique(R2$Date))
  ME2 <- sort(unname(as.Date(vapply(split(D2, format(D2,"%Y-%m")), function(v) as.character(max(v)), character(1)))))
  ADV <- new_adv(R2[, .(Date, Ticker, Vol, Close)], at_dates = ME2)
  setnames(ADV, "adv", "advB")
  LEG <- R2[Date %in% ME2, .(Date, Ticker, advA = Vol * Close)]
  RUL <- merge(LEG, ADV, by = c("Date","Ticker"), all = TRUE)
  RUL[, ym := format(Date, "%Y-%m")]
  P[, ym := format(as.Date(Date), "%Y-%m")]
  PJ <- merge(P[, .(Ticker, Date = as.Date(Date), ym, score = get(scol))],
              RUL[, .(Ticker, ym, advA, advB)], by = c("Ticker","ym"), all.x = TRUE)
  cat(sprintf("[B] 자 매칭: A %s / B %s (결측 A %d · B %d)\n",
              format(sum(!is.na(PJ$advA)), big.mark=","), format(sum(!is.na(PJ$advB)), big.mark=","),
              sum(is.na(PJ$advA)), sum(is.na(PJ$advB))))

  ## forward return + 벤치 (계약 함수 경유 — 손계산 금지)
  fwd <- suppressWarnings(new_fn(R2[Date >= min(PME) - 40], PME))
  cat(sprintf("[B] forward 패널 liq_ruler = %s · returns %s 행\n",
              fwd$liq_ruler, format(nrow(fwd$returns_dt), big.mark=",")))

  ## top-25 선별 A/B (자로 거른 뒤 score 상위 25)
  topN <- function(dt, advcol, n = 25L) {
    x <- dt[!is.na(get(advcol)) & get(advcol) >= LIQ_MIN]
    x[order(-score), head(.SD, n), by = Date, .SDcols = c("Ticker","score")]
  }
  selA <- topN(PJ, "advA"); selB <- topN(PJ, "advB")
  ov <- merge(selA[, .(Date, Ticker, inA = TRUE)], selB[, .(Date, Ticker, inB = TRUE)],
              by = c("Date","Ticker"), all = TRUE)
  ov[is.na(inA), inA := FALSE]; ov[is.na(inB), inB := FALSE]
  bym <- ov[, .(n_only_A = sum(inA & !inB), n_only_B = sum(inB & !inA), n_both = sum(inA & inB)), by = Date]
  n_months_changed <- bym[n_only_A > 0 | n_only_B > 0, .N]
  cat(sprintf("[B] 선별 변화: 월 %d 개 중 %d 개월(%.1f%%)에서 top-25 구성이 달라짐 · 평균 교체 %.2f 종목/월\n",
              nrow(bym), n_months_changed, 100*n_months_changed/nrow(bym), bym[, mean(n_only_A)]))

  ## PORT_t 실측 (canonical_screen_bt — proxy 손계산 금지)
  source(file.path(QM, "02_Infrastructure/contracts/canonical_screen_bt.R"))
  run_cs <- function(sel, lab) {
    sc <- sel[, .(Date = as.Date(Date), Ticker, score)]
    tryCatch(canonical_screen_bt(sc, fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)],
                                 fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)],
                                 top_n = 25L, cost_bps_oneway = 15,
                                 run_id = paste0("fq181_", lab), strategy_id = paste0("FQ181_", lab)),
             error = function(e) list(metric_type = "error", note = conditionMessage(e)))
  }
  csA <- run_cs(selA, "rulerA_1day"); csB <- run_cs(selB, "rulerB_adv20t1")
  gv <- function(x, f) { v <- x[[f]]; if (is.null(v) || length(v) == 0) NA_real_ else as.numeric(v) }
  ptA <- gv(csA, "portfolio_alpha_t_nw_lag3"); ptB <- gv(csB, "portfolio_alpha_t_nw_lag3")
  cat(sprintf("[B] PORT_t(NW lag-3): 자A(구판 1일치) = %.4f · 자B(교정 20일 t-1) = %.4f · Δ = %+.4f\n",
              ptA, ptB, ptB - ptA))
  cat(sprintf("[B] HARD 게이트 2.95 판정: A = %s · B = %s → **판정 %s**\n",
              if (!is.na(ptA) && ptA >= 2.95) "PASS" else "FAIL",
              if (!is.na(ptB) && ptB >= 2.95) "PASS" else "FAIL",
              if (!is.na(ptA) && !is.na(ptB) && ((ptA >= 2.95) != (ptB >= 2.95))) "★뒤집힘(FLIP)" else "불변"))
  cat(sprintf("[B] net_sr A=%.4f B=%.4f · IR A=%.4f B=%.4f · n_months A=%s B=%s\n",
              gv(csA,"net_sr"), gv(csB,"net_sr"), gv(csA,"information_ratio"), gv(csB,"information_ratio"),
              gv(csA,"n_months"), gv(csB,"n_months")))

  res$verdict_ab <- list(
    panel = sup, score_col = scol, n_rows = nrow(P), n_months = nrow(bym),
    n_months_selection_changed = n_months_changed,
    pct_months_changed = 100*n_months_changed/nrow(bym),
    mean_names_swapped_per_month = bym[, mean(n_only_A)],
    port_t_rulerA = ptA, port_t_rulerB = ptB, delta = ptB - ptA,
    hard_gate = 2.95,
    verdict_A = if (!is.na(ptA) && ptA >= 2.95) "PASS" else "FAIL",
    verdict_B = if (!is.na(ptB) && ptB >= 2.95) "PASS" else "FAIL",
    flipped = !is.na(ptA) && !is.na(ptB) && ((ptA >= 2.95) != (ptB >= 2.95)),
    net_sr_A = gv(csA,"net_sr"), net_sr_B = gv(csB,"net_sr"),
    metric_type = "canonical_screen")
  fwrite(bym, file.path(OUT, "p4_selection_change_by_month.csv"))
}

write_json(res, file.path(OUT, "p4_parity_verdict.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p4_parity_verdict.json\n")
