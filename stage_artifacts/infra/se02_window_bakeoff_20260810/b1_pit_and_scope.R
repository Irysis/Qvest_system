#==============================================================================
# b1_pit_and_scope.R — SE02_Consensus_Revision 창 수리 (FQ-222)
#   (B) PIT 확인 + (D) 영향 범위. 읽기 전용. 재빌드 없음.
#
# 배경(확정, 재조사 불요): compute_crowding.R:422-424 SE02 는 date_rank==1 vs ==2,
#   즉 인접 **행** 차. 원천 eps_1y 는 관측 간격 중앙 1일 / 값 변경 간격 중앙 6일
#   ⇒ 창이 개정을 거의 못 담아 SE02 가 0 으로 붕괴.
#
# ★판별 축(교정본): "원천이 분기 계단인가"가 아니라 "창이 위치-기반인가
#   달력-기반인가". 같은 파일의 M26/M28/C14/C17 은 sig_date - 63L 이라 멀쩡하다.
#   ⇒ eps_1y 는 상시 개정 ⇒ .cons_quarters() (분기 런) 재사용은 **부적합 가설**
#      이며 본 스크립트 P2 에서 직접 확인한다(그대로 믿지 않는다).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
CD   <- file.path(ROOT, ".cache/consensus")
FDB  <- file.path(ROOT, ".cache/factor_db")

stopifnot(dir.exists(CD), dir.exists(FDB))
TOL <- 1e-12

rd_metric <- function(m) {
  p <- file.path(CD, paste0(m, ".parquet"))
  if (!file.exists(p)) stop(sprintf("[STOP] 원천 부재: %s", p))
  h <- as.data.table(read_parquet(p))
  if (!(m %in% names(h))) stop(sprintf("[STOP] %s 값 컬럼 부재 (%s)", m, paste(names(h), collapse=",")))
  h[, Date := as.Date(Date)]
  h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker", "Date"))
  h[]
}

E <- rd_metric("eps_1y")
cat(sprintf("eps_1y: %s행 · %d종목 · %s .. %s\n", format(nrow(E), big.mark=","),
            uniqueN(E$Ticker), min(E$Date), max(E$Date)))
if (nrow(E) == 0L) stop("[STOP] eps_1y 0행 — 0은 결론이 아니라 정지 신호")

# ── 변경 이벤트 표 (P1/P2 공용) ─────────────────────────────────────────────
E[, prev_v := shift(value), by = Ticker]
E[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]
CH <- E[chg == TRUE]

#==============================================================================
# P1 — 값 변경일의 달력 구조 (FQ-218 이 sue/esbr 에서 쓴 것과 동일한 검사)
#   FQ-218 결과: 값 변경 100% 가 4/6/9/12월 **첫 영업일** ⇒ 분기 일괄 공표일
#   eps_1y 가 같은 구조면 .cons_quarters 재사용이 맞고, 아니면 달력 lag 가 맞다.
#==============================================================================
CH[, `:=`(mon = as.integer(format(Date, "%m")),
          dom = as.integer(format(Date, "%d")),
          dow = format(Date, "%u"))]
p1 <- data.table(
  n_changes            = nrow(CH),
  frac_month_4_6_9_12  = mean(CH$mon %in% c(4L, 6L, 9L, 12L)),
  frac_dom_le5         = mean(CH$dom <= 5L),
  frac_weekend         = mean(CH$dow %in% c("6", "7")),
  n_weekend            = sum(CH$dow %in% c("6", "7")),
  chg_gap_med          = { ch2 <- copy(CH); setorderv(ch2, c("Ticker","Date"))
                           ch2[, g := as.integer(Date - shift(Date)), by = Ticker]
                           median(ch2$g, na.rm = TRUE) },
  chg_rate_per_row     = mean(E$chg, na.rm = TRUE))
cat("\n== P1 eps_1y 값 변경일의 달력 구조 ==\n"); print(p1)
fwrite(p1, file.path(OUT, "b1_p1_change_calendar.csv"))
p1_mon <- CH[, .N, by = mon][order(mon)]
p1_mon[, frac := N / sum(N)]
cat("-- 월별 변경 분포 (분기 일괄이면 4/6/9/12 에 몰린다) --\n"); print(p1_mon)
fwrite(p1_mon, file.path(OUT, "b1_p1_change_month_hist.csv"))

#==============================================================================
# P2 — 분기 런(.cons_quarters) 가설의 직접 반증/입증
#   런 = 값이 바뀌지 않고 이어지는 구간. 상시 개정이면 런 길이가 짧아
#   "최근 n 런" 이 분기가 아니라 며칠~몇주가 된다.
#==============================================================================
E[, newrun := is.na(prev_v) | abs(value - prev_v) > TOL]
E[, runid := cumsum(newrun)]
RT <- E[, .(Ticker = Ticker[1L], run_start = min(Date), run_end = max(Date),
            run_days = as.integer(max(Date) - min(Date)) + 1L), by = runid]
p2 <- data.table(
  n_runs        = nrow(RT),
  run_days_p50  = as.numeric(quantile(RT$run_days, .50)),
  run_days_p90  = as.numeric(quantile(RT$run_days, .90)),
  run_days_p99  = as.numeric(quantile(RT$run_days, .99)),
  runs_per_year_med = { rr <- RT[, .N, by = .(Ticker, yr = format(run_start, "%Y"))]
                        median(rr$N) })
cat("\n== P2 런 길이 (분기 계단이면 p50 ~90일, 상시 개정이면 훨씬 짧다) ==\n")
print(p2)
fwrite(p2, file.path(OUT, "b1_p2_run_length.csv"))

#==============================================================================
# P3 — 벤더 자체 변화율(eps_chg_1m / eps_chg_3m)과의 정합
#   우리 패널로 계산한 L일 개정률이 벤더의 자체 개정률과 일치하면,
#   레벨 패널의 Date 스탬프 = 벤더 관측일(= 가용일)임이 **독립 확인**된다.
#   (효력일/회계일 스탬프면 정합이 깨진다)
#   ★같은 측정이 K5(비중복)의 근거이기도 하다 — 방향만 반대로 읽는다.
#==============================================================================
E1 <- rd_metric("eps_chg_1m"); setnames(E1, "value", "vendor_1m")
E3 <- rd_metric("eps_chg_3m"); setnames(E3, "value", "vendor_3m")

EK <- E[, .(Ticker, Date, value)]; EK[, obs_date := Date]
# dt 는 항상 **새로 만들어진** 부분집합이 들어온다(원본 참조수정 아님).
# 행 부분집합은 key 를 떨어뜨리므로 여기서 다시 건다.
last_at <- function(dt, when) {
  if (!nrow(dt)) return(dt[0L])
  setkeyv(dt, c("Ticker", "Date"))
  tk <- unique(dt$Ticker)
  q  <- data.table(Ticker = tk, Date = as.Date(rep(when, length(tk))))
  setkeyv(q, c("Ticker", "Date"))
  dt[q, roll = TRUE]
}
SIG_P3 <- as.Date(c("2008-12-31", "2014-03-31", "2020-06-30", "2026-06-30"))
LAGS_P3 <- c(21L, 30L, 63L, 91L, 126L)

p3 <- list()
for (sd_ in SIG_P3) {
  sd_ <- as.Date(sd_, origin = "1970-01-01")
  cur <- last_at(EK[Date <= sd_], sd_)[!is.na(value), .(Ticker, v_now = value, d_now = obs_date)]
  v1 <- last_at(E1[Date <= sd_][, .(Ticker, Date, vendor_1m, obs_date = Date)], sd_)[!is.na(vendor_1m), .(Ticker, vendor_1m)]
  v3 <- last_at(E3[Date <= sd_][, .(Ticker, Date, vendor_3m, obs_date = Date)], sd_)[!is.na(vendor_3m), .(Ticker, vendor_3m)]
  for (L in LAGS_P3) {
    lg <- last_at(EK[Date <= sd_ - L], sd_ - L)[!is.na(value), .(Ticker, v_lag = value)]
    cm <- merge(cur, lg, by = "Ticker")
    cm <- cm[abs(v_lag) > 1e-6]
    if (nrow(cm) < 30L) next
    cm[, ours := (v_now - v_lag) / abs(v_lag)]
    a <- merge(cm, v1, by = "Ticker"); b <- merge(cm, v3, by = "Ticker")
    p3[[length(p3)+1L]] <- data.table(
      sig_date = sd_, lag_days = L, n = nrow(cm),
      rho_vs_vendor_1m = if (nrow(a) > 30L) suppressWarnings(cor(a$ours, a$vendor_1m, method="spearman", use="complete.obs")) else NA_real_,
      rho_vs_vendor_3m = if (nrow(b) > 30L) suppressWarnings(cor(b$ours, b$vendor_3m, method="spearman", use="complete.obs")) else NA_real_)
  }
}
P3 <- rbindlist(p3)
cat("\n== P3 우리 L일 개정률 vs 벤더 자체 개정률 (스탬프 정합 + 중복 진단) ==\n")
print(P3)
fwrite(P3, file.path(OUT, "b1_p3_vendor_agreement.csv"))

#==============================================================================
# P4 — same-day 노출 (lag1 스트레스). registry availability 는 T-1 선언인데
#      코드 강제점은 Date <= sig_d (same-day 허용) — known_discrepancy 등재분.
#      차분 팩터에서 이 비대칭이 실제로 값을 바꾸는지 잰다.
#==============================================================================
p4 <- list()
for (sd_ in SIG_P3) {
  sd_ <- as.Date(sd_, origin = "1970-01-01")
  for (L in c(21L, 63L, 126L)) {
    mk <- function(anchor) {
      cu <- last_at(EK[Date <= anchor], anchor)[!is.na(value), .(Ticker, v_now = value, d_now = obs_date)]
      lg <- last_at(EK[Date <= anchor - L], anchor - L)[!is.na(value), .(Ticker, v_lag = value)]
      m  <- merge(cu, lg, by = "Ticker")[abs(v_lag) > 1e-6]
      m[, se := (v_now - v_lag) / abs(v_lag)][]
    }
    a <- mk(sd_); b <- mk(sd_ - 1L)
    j <- merge(a[, .(Ticker, se_t0 = se, d_now)], b[, .(Ticker, se_t1 = se)], by = "Ticker")
    if (nrow(j) < 30L) next
    p4[[length(p4)+1L]] <- data.table(
      sig_date = sd_, lag_days = L, n = nrow(j),
      frac_anchor_is_sameday = mean(j$d_now == sd_),
      rho_t0_vs_t1 = suppressWarnings(cor(j$se_t0, j$se_t1, method = "spearman")),
      frac_identical = mean(abs(j$se_t0 - j$se_t1) < TOL))
  }
}
P4 <- rbindlist(p4)
cat("\n== P4 same-day 노출 (lag1 스트레스) ==\n"); print(P4)
fwrite(P4, file.path(OUT, "b1_p4_sameday_lag1.csv"))

#==============================================================================
# D — 영향 범위: SE02 배출월 + FQ-218/219 재빌드월과의 겹침 + 저장 산출물 실측
#   ★사전 확인은 registry 가 아니라 **산출물**에서 (메모리 규약)
#==============================================================================
led <- fread(file.path(FDB, "emission_ledger.csv"))
se02_m <- sort(unique(led[Factor_Name == "SE02_Consensus_Revision", ym]))
if (!length(se02_m)) stop("[STOP] SE02 배출 원장 0건 — 정지 신호")
fq218 <- sort(unique(led[Factor_Name %in% c("C10_SUE_Persistence","C13_Revision_Breadth_3m",
                                            "C15_Forecast_Error_Trend"), ym]))
fq219 <- sort(unique(led[Factor_Name %in% c("C11_Earnings_Streak","M25_Earnings_Mom_Streak"), ym]))
m32   <- sort(unique(led[Factor_Name == "M32_Composite_Mom_v2", ym]))
unionC <- sort(union(fq218, union(fq219, intersect(m32, fq219))))
cat(sprintf("\n== D 재빌드 범위 ==\nSE02 배출월 %d (%s..%s)\n통합C(FQ218+219) %d\nSE02 \\ C = %d개월\nC \\ SE02 = %d개월\n",
            length(se02_m), min(se02_m), max(se02_m), length(unionC),
            length(setdiff(se02_m, unionC)), length(setdiff(unionC, se02_m))))
extra <- setdiff(se02_m, unionC)
cat(sprintf("SE02 단독 추가월: %s\n", paste(extra, collapse = ", ")))
ex_rows <- led[Factor_Name == "SE02_Consensus_Revision" & ym %in% extra,
               .(ym, n_rows, n_tickers)][order(ym)]
cat("-- 추가월의 실제 규모 --\n"); print(ex_rows)
fwrite(ex_rows, file.path(OUT, "b1_d_extra_months.csv"))
fwrite(data.table(ym = sort(union(se02_m, unionC))), file.path(OUT, "b1_d_union_months.csv"))

# 저장 산출물에서 SE02 죽은 달(Z 전건 NA / 횡단면 sd 0) 전수
cat("\n-- 저장 factor_db 에서 SE02 실태 전수 (318개월) --\n")
sc <- list()
for (k in seq_along(se02_m)) {
  ym <- se02_m[k]
  f <- file.path(FDB, sprintf("factor_db_%s.parquet", ym))
  if (!file.exists(f)) { sc[[length(sc)+1L]] <- data.table(ym=ym, n=NA_integer_, file_missing=TRUE); next }
  D <- tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
  if (is.null(D)) { sc[[length(sc)+1L]] <- data.table(ym=ym, n=NA_integer_, file_missing=TRUE); next }
  d <- D[Factor_Name == "SE02_Consensus_Revision"]
  if (!nrow(d)) { sc[[length(sc)+1L]] <- data.table(ym=ym, n=0L, file_missing=FALSE); next }
  rv <- d$Raw_Value
  tb <- sort(table(round(rv, 12)), decreasing = TRUE)
  sc[[length(sc)+1L]] <- data.table(
    ym = ym, n = nrow(d), file_missing = FALSE,
    frac_zero  = mean(abs(rv) < TOL, na.rm = TRUE),
    sd_raw     = sd(rv, na.rm = TRUE),
    n_distinct = uniqueN(round(rv, 12)),
    modal_frac = as.numeric(tb[1]) / sum(!is.na(rv)),
    z_na_frac  = if ("Z_Score" %in% names(d)) mean(is.na(d$Z_Score)) else NA_real_,
    cov_frac   = if ("Coverage" %in% names(d)) mean(d$Coverage, na.rm = TRUE) else NA_real_)
  if (k %% 60 == 0) cat(sprintf("  [%d/%d]\n", k, length(se02_m)))
}
SC <- rbindlist(sc, fill = TRUE)
fwrite(SC, file.path(OUT, "b1_d_stored_se02_all_months.csv"))
cat(sprintf("파일 부재 %d · 0행 %d · Z 전건 NA 월 %d · modal_frac>=0.9 월 %d / %d\n",
            sum(SC$file_missing %in% TRUE), sum(SC$n %in% 0L),
            sum(SC$z_na_frac >= 0.999, na.rm = TRUE),
            sum(SC$modal_frac >= 0.9, na.rm = TRUE), nrow(SC)))
cat(sprintf("frac_zero 요약: p10=%.3f p50=%.3f p90=%.3f · min=%.3f max=%.3f\n",
            quantile(SC$frac_zero,.1,na.rm=TRUE), median(SC$frac_zero,na.rm=TRUE),
            quantile(SC$frac_zero,.9,na.rm=TRUE), min(SC$frac_zero,na.rm=TRUE),
            max(SC$frac_zero,na.rm=TRUE)))
dead <- SC[z_na_frac >= 0.999 | (!is.na(sd_raw) & sd_raw < 1e-12)]
cat(sprintf("죽은 달(Z 전건 NA 또는 sd 0) %d개: %s\n", nrow(dead),
            paste(head(dead$ym, 40), collapse = ", ")))
fwrite(dead, file.path(OUT, "b1_d_dead_months.csv"))

cat("\n[b1 완료]\n")
