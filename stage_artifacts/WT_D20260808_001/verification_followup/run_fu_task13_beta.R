# =============================================================================
# run_fu_task13_beta.R — verification_followup ① F3 β-drag HAC 재산출 + ③ 섹터-중립 β
#
# ① 보고된 t −12.71 / −19.88 은 **겹치는 60개월 trailing 창** 위 gap 계열에 NW lag-3 을
#    얹은 값이다. 창이 60개월 겹치면 계열 ACF r1 ≈ 0.93 이고 lag-3 커널은 자기상관의
#    극히 일부만 흡수한다 ⇒ SE 과소 ⇒ |t| 과대. lag>=59 · Andrews 자동대역 ·
#    Hansen-Hodrick · 이동블록 부트스트랩(L=60) 4종으로 재산출한다.
# ③ 섹터 잔차 β 로 같은 gap 을 재산출 — gap 이 종목 저β 인가 섹터 구성인가.
#    ★판정은 ①의 교정된 SE 위에서만 (lag-3 재사용 금지).
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/verification_followup/run_fu_task13_beta.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
FU  <- file.path(OUT, "verification_followup")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
dir.create(FU, showWarnings = FALSE, recursive = TRUE)
say <- function(fmt, ...) cat(sprintf(paste0("[fu13] ", fmt, "\n"), ...))

FILT <- c("D03_EWMA", "Q01_EB")
set.seed(20260809L)

# ── HAC 도구상자 ─────────────────────────────────────────────────────────────
# 전부 "평균 = 0" 검정. lm(x ~ 1) 의 절편에 각 vcov 를 얹는다.
hac_t <- function(x, type, lag = NULL) {
  x <- x[is.finite(x)]; n <- length(x)
  fit <- lm(x ~ 1)
  V <- tryCatch(switch(type,
    NW  = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE),
    AND = sandwich::kernHAC(fit, kernel = "Quadratic Spectral", prewhite = FALSE,
                            bw = sandwich::bwAndrews, adjust = TRUE),
    HH  = sandwich::kernHAC(fit, kernel = "Truncated", bw = lag + 1, prewhite = FALSE, adjust = TRUE),
    stop("unknown type")), error = function(e) { say("  !! %s 실패: %s", type, conditionMessage(e)); NULL })
  if (is.null(V)) return(list(t = NA_real_, se = NA_real_, note = "vcov 실패"))
  v <- V[1, 1]
  if (!is.finite(v) || v <= 0)
    return(list(t = NA_real_, se = NA_real_,
                note = sprintf("비-PSD 분산 %.3e — 이 커널은 이 계열에서 유효 추정 불가", v)))
  se <- sqrt(v)
  list(t = mean(x)/se, se = se, note = "")
}
# 이동블록 부트스트랩 (블록 길이 L, B회) — 겹치는 창의 종속을 블록으로 보존
mbb_t <- function(x, L = 60L, B = 2000L) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n <= L) return(list(t = NA_real_, se = NA_real_, note = "n <= L"))
  nb <- ceiling(n / L); starts_max <- n - L + 1L
  m <- mean(x)
  bm <- numeric(B)
  for (b in seq_len(B)) {
    st <- sample.int(starts_max, nb, replace = TRUE)
    idx <- unlist(lapply(st, function(s) s:(s + L - 1L)))[seq_len(n)]
    bm[b] <- mean(x[idx])
  }
  se <- sd(bm)
  list(t = m/se, se = se, note = sprintf("B=%d · L=%d · 블록수 %d", B, L, nb))
}
acf1 <- function(x) { x <- x[is.finite(x)]; a <- acf(x, lag.max = 12, plot = FALSE)$acf
                      c(r1 = a[2], r6 = a[7], r12 = a[13]) }

report_series <- function(g, label) {
  n <- sum(is.finite(g)); a <- acf1(g)
  say("--- %s (n=%d, 평균 %+.4f) ACF r1=%.3f r6=%.3f r12=%.3f", label, n, mean(g, na.rm=TRUE),
      a["r1"], a["r6"], a["r12"])
  res <- list(label = label, n = n, mean = mean(g, na.rm = TRUE),
              acf_r1 = unname(a["r1"]), acf_r6 = unname(a["r6"]), acf_r12 = unname(a["r12"]))
  specs <- list(list(k="nw_lag3", t="NW", l=3L), list(k="nw_lag59", t="NW", l=59L),
                list(k="nw_lag60", t="NW", l=60L), list(k="andrews_qs", t="AND", l=NULL),
                list(k="hansen_hodrick_59", t="HH", l=59L))
  for (s in specs) {
    r <- hac_t(g, s$t, s$l)
    res[[s$k]] <- list(t = r$t, se = r$se, note = r$note)
    say("    %-18s t = %s  se = %s %s", s$k,
        if (is.finite(r$t)) sprintf("%+7.3f", r$t) else "     NA",
        if (is.finite(r$se)) sprintf("%.5f", r$se) else "NA", r$note)
  }
  mb <- mbb_t(g, L = 60L, B = 2000L)
  res$mbb_L60 <- list(t = mb$t, se = mb$se, note = mb$note)
  say("    %-18s t = %+7.3f  se = %.5f  (%s)", "mbb_L60", mb$t, mb$se, mb$note)
  res
}

# ── 0. 입력 실측 ─────────────────────────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
say("INPUT base_panel nrow=%d n_month=%d %s~%s", nrow(BASE), uniqueN(BASE$Date), min(BASE$Date), max(BASE$Date))
say("INPUT tuned_panel nrow=%d n_month=%d %s~%s", nrow(TUNED), uniqueN(TUNED$Date), min(TUNED$Date), max(TUNED$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","K200","KQ150","Sector","Sector_Lv2")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d DAILY n_day=%d %s~%s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose = FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
SEC  <- RAWME[, .(Date, Ticker, Sector, Sector_Lv2)]
say("섹터 컬럼 실측: Sector 고유 %d (NA %.3f%%) · Sector_Lv2 고유 %d (NA %.3f%%)",
    uniqueN(SEC$Sector), 100*mean(is.na(SEC$Sector)),
    uniqueN(SEC$Sector_Lv2), 100*mean(is.na(SEC$Sector_Lv2)))
say("  Sector 상위 값: %s", paste(head(SEC[!is.na(Sector), .N, by=Sector][order(-N)]$Sector, 8), collapse=" | "))

fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date = as.Date(Date), Ticker, adv)]
say("INPUT fwd returns nrow=%d n_month=%d", nrow(returns_dt), uniqueN(returns_dt$Date))

score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date","Ticker"))
}
# eligible_set — 원 측정과 **동일 정의** (재현성 우선)
E <- merge(score_of("M01_PATHQ"), liq_dt, by = c("Date","Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(E, Date, -score); E[, rk := seq_len(.N), by = Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date, Ticker, fz = score, F_ = f)]))
FZ <- merge(FZ, E[, .(Date, Ticker)], by = c("Date","Ticker"))
FZ[, q_rank := frank(fz) / .N, by = .(Date, F_)]
say("eligible %d행 / %d개월 (원 측정 재현)", nrow(E), uniqueN(E$Date))

# ── 1. β 패널 (원 측정 §5 동일 재현) ─────────────────────────────────────────
say("=== 1. β 패널 재현 (trailing 60m, 최소 24관측, 당월 미포함) ===")
RM <- merge(returns_dt, bench_dt, by = "Date")
dts <- sort(unique(E$Date))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L, i-60L):(i-1L)]]
  bb <- w[, {
    ok <- is.finite(Ret_1m) & is.finite(BM_Ret)
    if (sum(ok) >= 24L && var(BM_Ret[ok]) > 0) .(beta = cov(Ret_1m[ok], BM_Ret[ok])/var(BM_Ret[ok]))
    else .(beta = NA_real_)
  }, by = Ticker][is.finite(beta)]
  bb[, Date := dts[i]]
  beta_l[[i]] <- bb[, .(Date, Ticker, beta)]
}
BETA <- rbindlist(beta_l)
say("β 패널 %d행 / %d개월 — 원 보고(259개월)와 대조", nrow(BETA), uniqueN(BETA$Date))

RES <- list(meta = list(
  script = "verification_followup/run_fu_task13_beta.R", run_at = as.character(Sys.time()),
  metric_type = "diag",
  beta_panel = list(rows = nrow(BETA), months = uniqueN(BETA$Date),
                    window = "trailing 60m 겹침(overlapping) · 최소 24관측 · 당월 미포함(PIT)")))

# ── 2. ① gap 계열 HAC 재산출 ─────────────────────────────────────────────────
say("=== 2. ① F3 gap HAC 재산출 (겹치는 창 대응) ===")
raw_gap <- list()
for (f in FILT) {
  D <- merge(FZ[F_ == f, .(Date, Ticker, q_rank)], BETA, by = c("Date","Ticker"))
  s <- D[, .(b_top = median(beta[q_rank > 0.8]), b_med = median(beta),
             b_bot = median(beta[q_rank <= 0.2])), by = Date]
  s <- s[is.finite(b_top) & is.finite(b_med)][order(Date)]
  g <- s$b_top - s$b_med
  raw_gap[[f]] <- list(s = s, g = g)
  say("[%s] 최상위분위 β 평균 %.4f · 유니버스 중앙 %.4f · gap %+.4f",
      f, mean(s$b_top), mean(s$b_med), mean(g))
  RES$task1_raw_gap[[f]] <- c(list(beta_top_median = mean(s$b_top),
                                   beta_universe_median = mean(s$b_med)),
                              report_series(g, sprintf("%s raw gap (top20%%−중앙)", f)))
}

# ── 3. ③ 섹터-중립 β gap ─────────────────────────────────────────────────────
say("=== 3. ③ 섹터 잔차 β 로 같은 gap 재산출 ===")
BS <- merge(BETA, SEC, by = c("Date","Ticker"), all.x = TRUE)
say("β×섹터 매칭: %d행 · Sector NA %.3f%% · Sector_Lv2 NA %.3f%%",
    nrow(BS), 100*mean(is.na(BS$Sector)), 100*mean(is.na(BS$Sector_Lv2)))

resid_by_sector <- function(dt, seccol) {
  # 월별 섹터 평균 제거. 셀 <3 종목은 OTHER 로 묶는다(단일 셀 잔차=0 인공물 방지).
  x <- dt[!is.na(get(seccol)) & is.finite(beta)]
  x[, sec_ := as.character(get(seccol))]
  x[, ncell := .N, by = .(Date, sec_)]
  x[ncell < 3L, sec_ := "OTHER_SMALL"]
  x[, beta_res := beta - mean(beta), by = .(Date, sec_)]
  x[, .(Date, Ticker, beta_res, sec_)]
}

for (seccol in c("Sector", "Sector_Lv2")) {
  RSD <- resid_by_sector(BS, seccol)
  say("[%s] 잔차 패널 %d행 · 월평균 섹터 셀 %.1f개",
      seccol, nrow(RSD), RSD[, uniqueN(sec_), by = Date][, mean(V1)])
  for (f in FILT) {
    D <- merge(FZ[F_ == f, .(Date, Ticker, q_rank)], RSD, by = c("Date","Ticker"))
    s <- D[, .(r_top = median(beta_res[q_rank > 0.8]), r_med = median(beta_res)), by = Date]
    s <- s[is.finite(r_top) & is.finite(r_med)][order(Date)]
    g <- s$r_top - s$r_med
    key <- sprintf("%s__%s", f, seccol)
    rr <- report_series(g, sprintf("%s 섹터잔차 gap [%s]", f, seccol))
    # 잔존율 = 섹터잔차 gap / 원 gap (공통 월로 정렬해 비교)
    graw <- raw_gap[[f]]$s[Date %in% s$Date]
    ret_ratio <- mean(g) / mean(graw$b_top - graw$b_med)
    rr$retention_vs_raw <- ret_ratio
    rr$n_common <- nrow(graw)
    say("    → 잔존율 = 섹터잔차 gap / 원 gap = %+.4f / %+.4f = **%.3f** (공통 %d개월)",
        mean(g), mean(graw$b_top - graw$b_med), ret_ratio, nrow(graw))
    RES$task3_sector_gap[[key]] <- rr
  }
}

saveRDS(RES, file.path(FU, "fu_task13_results.rds"))
say("=== ①③ 완료 → verification_followup/fu_task13_results.rds ===")
