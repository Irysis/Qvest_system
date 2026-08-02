# =============================================================================
# run_wt009_tuned.R — WT-D20260802_009 튜닝 패널 5종 (사전등록 정의 그대로)
#   P1 V01_SECREL: base z 섹터 내 재표준화 (min 8, 소섹터 OTHER 풀)
#   P2 M01_PATHQ : 부호있는 경로효율 E = Σlr / Σ|lr|, 창 [n-251, n-21], n>252
#   P3 D03_EWMA  : EWMA vol half-life 63d, 창 252행, n>=120, raw = -sigma
#   P4 Q01_EB    : w=1/(1+Var_36m(z_{t-1..t-36})), tuned = w*z, 이력<12 → 중앙값 w
#   P5 V06_EB    : P4 동일 수식
#   orientation 상속(P2/P3): s_t = sign(Spearman(base_z, tuned_raw)), |rho|<0.1 → 직전월
#   PIT: 전 계산 trailing only. 저장 Ret 참값 사용(재계산 금지). 적합 파라미터 0.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_009/run_wt009_tuned.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[wt009t] ", fmt, "\n"), ...))

BASE <- as.data.table(read_parquet(file.path(OUT, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))
SEC <- as.data.table(read_parquet(file.path(OUT, "sector_panel.parquet")))
SEC[, Date := as.Date(Date)]

# 월별 CS winsorize 3sd + z (WT-006 규약 재사용)
cs_z <- function(dt, col, orient = +1) {
  d <- dt[is.finite(get(col)), .(Date, Ticker, x = orient * get(col))]
  d[, {
    mu <- mean(x); s <- sd(x)
    if (!is.finite(s) || s <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
    else {
      xw <- pmin(pmax(x, mu - 3 * s), mu + 3 * s)
      list(Ticker = Ticker, score = (xw - mean(xw)) / sd(xw))
    }
  }, by = Date][is.finite(score)]
}

# orientation 상속 (사전등록 규칙)
inherit_sign <- function(base_z, tuned_raw_scored) {
  m <- merge(base_z[, .(Date, Ticker, bz = z)],
             tuned_raw_scored[, .(Date, Ticker, score)], by = c("Date", "Ticker"))
  rho <- m[, .(rho = suppressWarnings(cor(bz, score, method = "spearman")), n = .N), by = Date]
  setorder(rho, Date)
  rho[, s := fifelse(abs(rho) >= 0.10, sign(rho), NA_real_)]
  rho[, s := nafill(s, type = "locf")]
  rho[is.na(s), s := 1]
  n_fallback <- rho[abs(rho) < 0.10, .N]
  out <- merge(tuned_raw_scored, rho[, .(Date, s)], by = "Date")
  out[, score := score * s][, s := NULL]
  list(panel = out, sign_tab = rho[, .(Date, rho, s)], n_fallback = n_fallback)
}

# ── P1 V01_SECREL ────────────────────────────────────────────────────────────
bz_v01 <- BASE[Factor_Name == "V01_BM", .(Date, Ticker, z)]
p1 <- merge(bz_v01, SEC, by = c("Date", "Ticker"), all.x = TRUE)
p1[is.na(Sector), Sector := "UNKNOWN"]
p1[, n_sec := .N, by = .(Date, Sector)]
p1[, grp := fifelse(n_sec >= 8L, Sector, "OTHER_POOL")]
p1[, score := {
  mu <- mean(z); s <- sd(z)
  if (!is.finite(s) || s < 1e-8) rep(0, .N) else (z - mu) / s
}, by = .(Date, grp)]
TUNED_P1 <- p1[is.finite(score), .(Date, Ticker, score)]
say("P1 V01_SECREL: %d행, 월평균 그룹 %.1f", nrow(TUNED_P1),
    p1[, uniqueN(grp), by = Date][, mean(V1)])

# ── P2/P3 일간 재료 ──────────────────────────────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Ret", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
univ_all <- unique(BASE$Ticker)
D <- RAW[Ticker %chin% univ_all & !is.na(Ret), .(Date, Ticker, Ret)]
rm(RAW); gc(verbose = FALSE)
setkey(D, Ticker, Date)
say("일간 유효행 %d", nrow(D))

t0 <- Sys.time()
res2 <- vector("list", length(SIG)); res3 <- vector("list", length(SIG))
for (si in seq_along(SIG)) {
  sd_ <- SIG[si]
  W <- D[Date > sd_ - 550L & Date <= sd_]          # 캘린더 pre-slice (성능)
  W <- W[, tail(.SD, 252L), by = Ticker]   # 최근 252 거래행 (base 창 미러)
  f <- W[, {
    n <- .N
    # P2: 경로효율 (n>252 base 요건 → 252행 확보 = n==252 필요, skip 21)
    e_val <- NA_real_
    if (n == 252L) {
      lr <- log(1 + Ret[1:(n - 21L)])
      lr <- lr[is.finite(lr)]
      if (length(lr) >= 150L) {
        tv <- sum(abs(lr))
        if (tv > 1e-8) e_val <- sum(lr) / tv
      }
    }
    # P3: EWMA vol (n>=120)
    v_val <- NA_real_
    if (n >= 120L) {
      age <- (n - 1L):0L
      w <- 0.5^(age / 63)
      v_val <- -sqrt(sum(w * Ret^2) / sum(w))
    }
    list(E = e_val, negsig = v_val)
  }, by = Ticker]
  f[, Date := sd_]
  res2[[si]] <- f[is.finite(E), .(Date, Ticker, E)]
  res3[[si]] <- f[is.finite(negsig), .(Date, Ticker, negsig)]
  if (si %% 40L == 0L) say("  daily %d/%d (%s) %.0fs", si, length(SIG),
      format(sd_, "%Y-%m"), as.numeric(difftime(Sys.time(), t0, units = "secs")))
}
PQ <- rbindlist(res2); EW <- rbindlist(res3)
say("P2 raw %d행 / P3 raw %d행 (%.1f min)", nrow(PQ), nrow(EW),
    as.numeric(difftime(Sys.time(), t0, units = "mins")))
write_parquet(PQ, file.path(OUT, "raw_pathq.parquet"))
write_parquet(EW, file.path(OUT, "raw_ewma.parquet"))

z2 <- cs_z(PQ, "E", +1)
r2 <- inherit_sign(BASE[Factor_Name == "M01_Mom_12_1", .(Date, Ticker, z)], z2)
TUNED_P2 <- r2$panel
say("P2 M01_PATHQ: %d행, orientation fallback %d개월, rho 중앙값 %+.3f",
    nrow(TUNED_P2), r2$n_fallback, r2$sign_tab[, median(rho, na.rm = TRUE)])

z3 <- cs_z(EW, "negsig", +1)
r3 <- inherit_sign(BASE[Factor_Name == "D03_RealVol", .(Date, Ticker, z)], z3)
TUNED_P3 <- r3$panel
say("P3 D03_EWMA: %d행, orientation fallback %d개월, rho 중앙값 %+.3f",
    nrow(TUNED_P3), r3$n_fallback, r3$sign_tab[, median(rho, na.rm = TRUE)])

# ── P4/P5 EB shrinkage ───────────────────────────────────────────────────────
eb_shrink <- function(fac_name) {
  bz <- BASE[Factor_Name == fac_name, .(Date, Ticker, z)]
  setorder(bz, Ticker, Date)
  bz[, idx := match(Date, SIG)]
  # trailing 36m (t-1..t-36, 당월 미포함) 분산 — 종목별 월 인덱스 창
  out <- vector("list", length(SIG))
  for (si in seq_along(SIG)) {
    cur <- bz[idx == si]
    if (nrow(cur) == 0L) next
    lo <- si - 36L; hi <- si - 1L
    hh <- bz[idx >= lo & idx <= hi & Ticker %chin% cur$Ticker,
             .(sig2 = { v <- var(z); if (.N >= 12L && is.finite(v)) v else NA_real_ }),
             by = Ticker]
    cur <- merge(cur, hh, by = "Ticker", all.x = TRUE)
    cur[, w := 1 / (1 + sig2)]
    med_w <- cur[is.finite(w), median(w)]
    if (!is.finite(med_w)) med_w <- 1
    cur[!is.finite(w), w := med_w]
    out[[si]] <- cur[, .(Date, Ticker, score = w * z, w, sig2)]
  }
  rbindlist(out)
}
t1 <- Sys.time()
eb4 <- eb_shrink("Q01_GPA")
eb5 <- eb_shrink("V06_fDY")
say("P4 Q01_EB: %d행 w[%.2f, %.2f] med %.2f | P5 V06_EB: %d행 w med %.2f (%.1f min)",
    nrow(eb4), eb4[, min(w)], eb4[, max(w)], eb4[, median(w)],
    nrow(eb5), eb5[, median(w)], as.numeric(difftime(Sys.time(), t1, units = "mins")))
write_parquet(eb4, file.path(OUT, "eb_q01_detail.parquet"))
write_parquet(eb5, file.path(OUT, "eb_v06_detail.parquet"))
TUNED_P4 <- eb4[is.finite(score), .(Date, Ticker, score)]
TUNED_P5 <- eb5[is.finite(score), .(Date, Ticker, score)]

# ── 저장 (long 통합) ─────────────────────────────────────────────────────────
TUNED <- rbindlist(list(
  TUNED_P1[, .(Date, Ticker, score, Factor_Name = "V01_SECREL")],
  TUNED_P2[, .(Date, Ticker, score, Factor_Name = "M01_PATHQ")],
  TUNED_P3[, .(Date, Ticker, score, Factor_Name = "D03_EWMA")],
  TUNED_P4[, .(Date, Ticker, score, Factor_Name = "Q01_EB")],
  TUNED_P5[, .(Date, Ticker, score, Factor_Name = "V06_EB")]))
write_parquet(TUNED, file.path(OUT, "tuned_panel.parquet"))
saveRDS(list(sign_p2 = r2$sign_tab, sign_p3 = r3$sign_tab,
             fallback = c(P2 = r2$n_fallback, P3 = r3$n_fallback)),
        file.path(OUT, "orientation_meta.rds"))
say("저장 완료 — tuned_panel.parquet (%d행)", nrow(TUNED))
