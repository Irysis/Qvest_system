# verify_r44.R — R44 Ret sanity 방화벽 회귀검증 (WT-D20260715_013)
#   규율: 단일스레드 · arrow io(2) · read-only(pin) · rawdata/book/05_Production 무변경.
#   방화벽 로직은 오염만 제거·정당 데이터 불변(known-case parity) 실증.
suppressWarnings(suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
}))
data.table::setDTthreads(1)
arrow::set_io_thread_count(2)      # ★io(1)=parquet read HANG (memory: rawdata full-load segfault)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Sys.setenv(QM_ROOT = QM)
OUT <- file.path(QM, "stage_artifacts/WT_D20260715_013")

PIN <- file.path(QM, ".cache/pin/rawdata_r9_pin_20260715.parquet")   # R40 pin (vintage 고정, §7)
PIN_TAG <- "rawdata_r9_pin_20260715 (R40 pin, byte-identical to live 2026-07-15)"
cat("== R44 방화벽 회귀검증 ==\n pin:", basename(PIN), "\n")

# ── 방화벽 + 소비면 함수 로드 (실제 배선된 코드) ──────────────────────────────
source(file.path(QM, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(QM, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(QM, "02_Infrastructure/ramp/factor_validation.R"))
# rawdata_sanitize.R는 config/calendar를 요구 — ret_sanity_firewall 정의만 안전 추출
local({
  txt <- readLines(file.path(QM, "02_Infrastructure/data/rawdata_sanitize.R"), warn = FALSE)
  b0 <- grep("^ret_sanity_firewall <- function", txt); b1 <- grep("^sanitize_rawdata <- function", txt)
  eval(parse(text = paste(txt[b0:(b1[1]-1)], collapse = "\n")), envir = globalenv())
})
stopifnot(exists("ret_sanity_firewall"), exists("canonical_screen_bt"), exists("build_monthly_forward_returns"))

BOOK <- c("A005930","A000660","A319660","A034730","A095610","A011070","A007340",
          "A023530","A004170","A402340","A222800","A003030","A290650","A189300")
ANOM <- c("A063350","A008480","A025930","A003190","A010120","A277810",
          "A328130","A183300","A058610","A454910")   # R43 in-universe 이상 종목

# ── 로드 (col_select 최소 — full-column 2.5GB 회피) ───────────────────────────
cols <- c("Date","Ticker","Close","Ret","K200","KQ150","Vol","Size")
raw <- as.data.table(read_parquet(PIN, col_select = tidyselect::all_of(cols)))
cat(sprintf(" loaded: %s rows × %d cols | Ret max=%.1f (오염 vintage 확인)\n",
            format(nrow(raw), big.mark=","), ncol(raw), max(raw$Ret, na.rm=TRUE)))

# 파이프라인 Step5와 동일하게 prevClose/gapdays/Ret 준비 (recompute = parity)
setorder(raw, Ticker, Date)
raw[, Ret_stored := Ret]
raw[, prevClose := shift(Close), by = Ticker]
raw[, gapdays   := as.integer(Date - shift(Date)), by = Ticker]
raw[, Ret := Close / prevClose - 1]
# stored vs recompute spot-check (첫날 NA 제외)
sc <- raw[!is.na(Ret) & !is.na(Ret_stored), max(abs(Ret - Ret_stored))]
cat(sprintf(" stored vs recompute Ret max|Δ|=%.3e (≈0 = 파이프라인 정합)\n", sc))

# ═══ TEST A: 방화벽 분류 census 교차검증 (R43 대조) ══════════════════════════
fw <- ret_sanity_firewall(raw)                       # prevClose/gapdays 존재 → copy 안 함
iso <- fw$isolation
cntA <- list(
  total_abs_gt_0.31 = raw[!is.na(Ret) & abs(Ret) > 0.31, .N],
  total_abs_gt_1.0  = raw[!is.na(Ret) & abs(Ret) > 1.0, .N],
  hard = fw$counts$hard, suspect = fw$counts$suspect,
  hard_in_universe = fw$counts$hard_in_universe,
  suspect_in_universe = fw$counts$suspect_in_universe,
  isolation_rows = nrow(iso),
  iso_in_universe = iso[in_universe == TRUE, .N]
)
cat("\n[TEST A] 방화벽 census 교차검증 (R43: |Ret|>0.31=2,760 · |Ret|>1.0=343 · 유니버스 17)\n")
print(cntA)
iso_univ <- iso[in_universe == TRUE][order(-abs(Ret))]
cat(sprintf(" 유니버스內 격리 %d행 (R43 = 17):\n", nrow(iso_univ)))
print(iso_univ)
fwrite(iso_univ, file.path(OUT, "firewall_isolation_IN_UNIVERSE.csv"))
fwrite(iso,      file.path(OUT, "firewall_isolation_ALL.csv"))
# cause 분해
cat(" cause 분해 (전체):\n"); print(iso[, .N, by = .(action, cause)][order(-N)])

# ═══ TEST B: 현 북 14보유 parity (오염 ZERO 실증) ═══════════════════════════
book_iso <- iso[Ticker %in% BOOK]
cat(sprintf("\n[TEST B] 현 북 14보유 방화벽 격리 = %d행 (기대 0 — R43 오염 ZERO)\n", nrow(book_iso)))
if (nrow(book_iso) > 0) print(book_iso)
book_parity_pass <- nrow(book_iso) == 0L

# ═══ TEST C: 유니버스 월패널 parity (HARD 격리 前/後 동일) ═══════════════════
# 방화벽 적용 rawdata = HARD 격리 Ret:=NA → 행 제거 (Step5와 동일 소비)
raw_fw <- copy(raw)
raw_fw[fw$mask_hard, Ret := NA_real_]
raw_fw <- raw_fw[!is.na(Ret)]
cat(sprintf("\n[TEST C] HARD 격리로 제거된 행 = %s (전체 대비 %.4f%%)\n",
            format(nrow(raw) - nrow(raw_fw) - raw[is.na(Ret), .N], big.mark=","),
            100*(nrow(raw)-nrow(raw_fw))/nrow(raw)))
# 영향 종목(book+anom)만 월패널 前/後 비교 (경량)
sub_tickers <- unique(c(BOOK, ANOM))
sig_dates <- raw[, .(md = max(Date)), by = .(ym = format(Date, "%Y%m"))]$md
sig_dates <- sort(unique(sig_dates))
cols_keep <- c("Date","Ticker","Close","K200","KQ150","Vol","Size")
mk_panel <- function(dd) build_monthly_forward_returns(dd[Ticker %in% sub_tickers, ..cols_keep], sig_dates)$returns_dt
p_before <- mk_panel(raw)
p_after  <- mk_panel(raw_fw)
setkey(p_before, Date, Ticker); setkey(p_after, Date, Ticker)
mrg <- merge(p_before, p_after, by = c("Date","Ticker"), all = TRUE, suffixes = c("_b","_a"))
mrg[, dabs := abs(fifelse(is.na(Ret_1m_b),0,Ret_1m_b) - fifelse(is.na(Ret_1m_a),0,Ret_1m_a))]
panel_max_delta <- mrg[, max(dabs, na.rm = TRUE)]
panel_n_diff <- mrg[dabs > 1e-12 | is.na(Ret_1m_b) != is.na(Ret_1m_a), .N]
cat(sprintf(" 월패널(book+anom %d종목) 前/後 max|Δ Ret_1m|=%.3e · 상이 행=%d (기대 0 — HARD는 월중일·월말 close 불변)\n",
            length(sub_tickers), panel_max_delta, panel_n_diff))
panel_parity_pass <- (panel_max_delta < 1e-9) && (panel_n_diff == 0L)
# book 종목만 별도 확인
book_rows_panel <- mrg[Ticker %in% BOOK, .N]
cat(sprintf(" book 14 월패널 행=%d · book 상이=%d\n", book_rows_panel, mrg[Ticker %in% BOOK & (dabs>1e-12), .N]))

# ═══ TEST D: canonical_screen_bt 가드 (clean parity + 오염 catch) ════════════
cat("\n[TEST D] canonical_screen_bt Ret_1m 가드\n")
# clean 월패널 (유니버스 2018-2024 subset — book+anom + 랜덤 유니버스 보강)
set.seed(44)
univ_sample <- raw[(K200==TRUE|KQ150==TRUE) & Date >= as.Date("2018-01-01"), unique(Ticker)]
univ_sample <- unique(c(BOOK, sample(univ_sample, min(120, length(univ_sample)))))
sig_d <- sig_dates[sig_dates >= as.Date("2018-01-01") & sig_dates <= as.Date("2024-12-31")]
fwd <- build_monthly_forward_returns(raw_fw[Ticker %in% univ_sample, ..cols_keep], sig_d)
ret_clean <- fwd$returns_dt; bench <- fwd$bench_dt; liq <- fwd$liq_dt
cat(sprintf(" clean 월패널: %d 종목-월 · max|Ret_1m|=%.3f (가드 5.0 미달=inert 기대)\n",
            nrow(ret_clean), max(abs(ret_clean$Ret_1m))))
# 임의 score = -Size rank (가치무관, 재현성만) — 가드 parity 목적
sc_dt <- raw[Ticker %in% univ_sample & Date %in% sig_d, .(Date, Ticker, score = -log(pmax(Size,1)))]
# (D1) clean 실행: 경고 없어야 함
warns <- character(0)
cs_clean <- withCallingHandlers(
  canonical_screen_bt(sc_dt, ret_clean, bench, top_n = 20L, liq_dt = liq,
                      run_id = "r44_clean", strategy_id = "R44_CLEAN", diag_dual_basis = FALSE),
  warning = function(w){ warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
guard_warns_clean <- sum(grepl("sanity 방화벽", warns))
cat(sprintf(" (D1) clean: PORT_t=%.3f · net_sr=%.3f · n_months=%d · 가드경고=%d (기대 0)\n",
            cs_clean$portfolio_alpha_t_nw_lag3, cs_clean$net_sr, cs_clean$n_months, guard_warns_clean))
# (D2) 오염 주입: 한 종목-월 Ret_1m=67000 (monster) → 가드가 격리해야 finite
ret_bad <- copy(ret_clean)
victim_date <- ret_bad[, .N, by = Date][which.max(N), Date]
victim_tick <- sc_dt[Date == victim_date][order(-score)][1, Ticker]   # top-score = 선택될 종목
ret_bad[Date == victim_date & Ticker == victim_tick, Ret_1m := 67000]
if (ret_bad[Date == victim_date & Ticker == victim_tick, .N] == 0)   # 혹 미존재 시 append
  ret_bad <- rbind(ret_bad, data.table(Date=victim_date, Ticker=victim_tick, Ret_1m=67000))
warns2 <- character(0)
cs_bad <- withCallingHandlers(
  canonical_screen_bt(sc_dt, ret_bad, bench, top_n = 20L, liq_dt = liq,
                      run_id = "r44_bad", strategy_id = "R44_BAD", diag_dual_basis = FALSE),
  warning = function(w){ warns2 <<- c(warns2, conditionMessage(w)); invokeRestart("muffleWarning") })
guard_warns_bad <- sum(grepl("sanity 방화벽", warns2))
guard_finite <- is.finite(cs_bad$portfolio_alpha_t_nw_lag3) && is.finite(cs_bad$net_sr)
# 가드 없었으면 monster가 그 달 port_gross를 폭발시켜 net_sr 비정상 — 가드 결과가 clean과 동일해야
guard_matches_clean <- abs(cs_bad$net_sr - cs_clean$net_sr) < 1e-6 &&
                       abs(cs_bad$portfolio_alpha_t_nw_lag3 - cs_clean$portfolio_alpha_t_nw_lag3) < 1e-6
cat(sprintf(" (D2) 오염주입(%s@%s Ret_1m=67000): 가드경고=%d · PORT_t=%.3f finite=%s · clean과일치=%s\n",
            victim_tick, format(victim_date), guard_warns_bad,
            cs_bad$portfolio_alpha_t_nw_lag3, guard_finite, guard_matches_clean))

testD_pass <- (guard_warns_clean == 0) && (guard_warns_bad >= 1) && guard_finite && guard_matches_clean

# ═══ 종합 판정 ══════════════════════════════════════════════════════════════
res <- list(
  wt = "WT-D20260715_013", round = "R44", as_of = "2026-07-15",
  pin_tag = PIN_TAG,
  testA_firewall_census = cntA,
  testA_matches_r43 = list(
    abs_gt_0.31 = cntA$total_abs_gt_0.31, r43_ref = 2760,
    abs_gt_1.0 = cntA$total_abs_gt_1.0, r43_ref_1 = 343,
    in_universe_iso = cntA$iso_in_universe, r43_ref_univ = 17),
  testB_book_parity_pass = book_parity_pass, book_iso_rows = nrow(book_iso),
  testC_panel_parity_pass = panel_parity_pass, panel_max_delta = panel_max_delta,
  panel_hard_rows_removed = as.integer(nrow(raw) - nrow(raw_fw) - raw[is.na(Ret), .N]),  # HARD만(첫날 NA 제외)
  testD = list(pass = testD_pass, warns_clean = guard_warns_clean, warns_bad = guard_warns_bad,
               finite = guard_finite, matches_clean = guard_matches_clean,
               clean_port_t = cs_clean$portfolio_alpha_t_nw_lag3, clean_net_sr = cs_clean$net_sr),
  overall_pass = book_parity_pass && panel_parity_pass && testD_pass,
  stored_vs_recompute_max_delta = sc,
  constraints = "read-only pin · rawdata/book_state/05_Production 무변경 · DART API 0 · 단일스레드 · io(2)"
)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = 8),
           file.path(OUT, "r44_verify_results.json"))
cat("\n== 종합 ==\n")
cat(sprintf(" A(census R43정합): |Ret|>0.31 %d/2760 · |Ret|>1.0 %d/343 · 유니버스 %d/17\n",
            cntA$total_abs_gt_0.31, cntA$total_abs_gt_1.0, cntA$iso_in_universe))
cat(sprintf(" B(북 parity): %s (격리 %d행)\n", book_parity_pass, nrow(book_iso)))
cat(sprintf(" C(월패널 parity): %s (max|Δ|=%.2e)\n", panel_parity_pass, panel_max_delta))
cat(sprintf(" D(가드 clean-inert+catch): %s\n", testD_pass))
cat(sprintf(" OVERALL: %s\n", res$overall_pass))
cat(" → r44_verify_results.json 기록 완료\n")
