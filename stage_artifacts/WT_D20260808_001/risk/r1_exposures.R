# =============================================================================
# r1_exposures.R — Step 1/3: Exposure matrix B (월간, trailing PIT) + specific risk 재료
#   Σ = BΩB' + D 의 B 를 만든다. 성과 산출 없음 — metric_type = risk_estimate
#   PIT: 모든 노출은 sig_date 이전 실현치만 사용(trailing). C1 rolling only.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt, ...) cat(sprintf(paste0("[r1] ", fmt, "\n"), ...))

# ── 입력 실측 (가정 금지) ────────────────────────────────────────────────────
FW <- readRDS("stage_artifacts/WT_D20260808_001/fwd_cache.rds")
RET <- as.data.table(FW$returns_dt); RET[, Date := as.Date(Date)]
BEN <- as.data.table(FW$bench_dt);   BEN[, Date := as.Date(Date)]
LIQ <- as.data.table(FW$liq_dt);     LIQ[, Date := as.Date(Date)]
say("returns_dt rows=%d 종목-월 | 월 %d (%s~%s) | 관측단위 월간(계약 build_monthly_forward_returns)",
    nrow(RET), uniqueN(RET$Date), as.character(min(RET$Date)), as.character(max(RET$Date)))
say("bench_dt rows=%d | Ret_1m 은 [d0,d1] forward — d0 시점 exposure 와 짝지음", nrow(BEN))

TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
W <- dcast(TUNED, Date + Ticker ~ Factor_Name, value.var = "score")
say("tuned wide rows=%d cols=[%s]", nrow(W), paste(names(W), collapse = ","))

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","Sector","K200","KQ150")))
raw[, Date := as.Date(Date)]
say("rawdata rows=%d (일간 %d일). Sector 수준 %d개", nrow(raw), uniqueN(raw$Date), uniqueN(raw$Sector))

sig_dates <- sort(unique(RET$Date))
say("sig_dates = %d (%s ~ %s)", length(sig_dates), as.character(min(sig_dates)), as.character(max(sig_dates)))

# 월말 스냅샷 (Size / Sector / ADTV20)
raw[, adtv := Close * Vol]
setorder(raw, Ticker, Date)
raw[, adtv20 := frollmean(adtv, 20, align = "right"), by = Ticker]
snap <- raw[Date %in% sig_dates, .(Date, Ticker, Size, Sector, adtv20, K200, KQ150)]
say("월말 스냅샷 rows=%d | adtv20 non-NA %.3f | Size non-NA %.3f",
    nrow(snap), mean(!is.na(snap$adtv20)), mean(!is.na(snap$Size)))

# ── trailing 60m β / idio vol (PIT: d 이전 실현 Ret_1m 만) ───────────────────
# Ret_1m@Date=d 는 [d, d+1] 수익 ⇒ d 시점에 사용 가능한 관측은 Date <= d-1개월.
RW <- dcast(RET, Date ~ Ticker, value.var = "Ret_1m")
dates_all <- RW$Date
RM <- as.matrix(RW[, -1]); rownames(RM) <- as.character(dates_all)
bvec <- BEN[match(dates_all, BEN$Date)]$BM_Ret
say("수익 행렬 %d x %d | bench 결측 %d", nrow(RM), ncol(RM), sum(is.na(bvec)))

WIN <- 60L; MINOBS <- 24L
beta_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  idx <- which(dates_all < d)                       # 엄격히 d 이전 실현월만
  if (length(idx) < MINOBS) next
  idx <- tail(idx, WIN)
  X <- RM[idx, , drop = FALSE]; b <- bvec[idx]
  ok <- !is.na(b)
  X <- X[ok, , drop = FALSE]; b <- b[ok]
  n_ok <- colSums(!is.na(X))
  keep <- which(n_ok >= MINOBS)
  if (!length(keep)) next
  Xk <- X[, keep, drop = FALSE]
  bc <- b - mean(b)
  # per-column pairwise (NA 존재) — 결측을 그 열에서만 제외
  bet <- numeric(length(keep)); ivol <- numeric(length(keep)); tvol <- numeric(length(keep))
  for (j in seq_along(keep)) {
    y <- Xk[, j]; m <- !is.na(y)
    yy <- y[m]; bb <- b[m]
    bbc <- bb - mean(bb); yyc <- yy - mean(yy)
    vb <- sum(bbc^2)
    if (vb <= 0) { bet[j] <- NA_real_; ivol[j] <- NA_real_; tvol[j] <- NA_real_; next }
    sl <- sum(bbc * yyc) / vb
    res <- yyc - sl * bbc
    bet[j] <- sl
    ivol[j] <- sqrt(sum(res^2) / max(1L, (length(yy) - 2L)))
    tvol[j] <- stats::sd(yy)
  }
  beta_list[[i]] <- data.table(Date = d, Ticker = colnames(Xk),
                               beta_60m = bet, ivol_60m = ivol, tvol_60m = tvol,
                               n_obs_beta = n_ok[keep])
  if (i %% 60 == 0) say("  beta %d/%d (%s)", i, length(sig_dates), as.character(d))
}
BETA <- rbindlist(beta_list)
say("BETA 패널 rows=%d | 월 %d | beta 중앙 %.3f | 결측 %.4f",
    nrow(BETA), uniqueN(BETA$Date), median(BETA$beta_60m, na.rm=TRUE), mean(is.na(BETA$beta_60m)))

# ── exposure 조립 ────────────────────────────────────────────────────────────
E <- merge(RET[, .(Date, Ticker, Ret_1m)], BETA, by = c("Date","Ticker"), all.x = TRUE)
E <- merge(E, snap, by = c("Date","Ticker"), all.x = TRUE)
E <- merge(E, W[, .(Date, Ticker, M01_PATHQ, Q01_EB, V01_SECREL, D03_EWMA)],
           by = c("Date","Ticker"), all.x = TRUE)
say("exposure 조립 rows=%d | beta 결측 %.3f | Size 결측 %.3f | Sector 결측 %.3f",
    nrow(E), mean(is.na(E$beta_60m)), mean(is.na(E$Size)), mean(is.na(E$Sector)))

zs <- function(x) {  # 횡단면 winsorize(3sd) + z
  m <- is.finite(x); if (sum(m) < 5) return(rep(NA_real_, length(x)))
  mu <- mean(x[m]); sd0 <- stats::sd(x[m]); if (!is.finite(sd0) || sd0 <= 0) return(rep(0, length(x)))
  y <- pmin(pmax(x, mu - 3*sd0), mu + 3*sd0)
  (y - mean(y[m])) / stats::sd(y[m])
}
E[, `:=`(
  X_BETA = zs(beta_60m),
  X_SIZE = zs(log(pmax(Size, 1))),
  X_IVOL = zs(ivol_60m),
  X_LIQ  = zs(log(pmax(adtv20, 1))),
  X_MOM  = zs(M01_PATHQ),
  X_QUAL = zs(Q01_EB),
  X_VAL  = zs(V01_SECREL),
  X_D03  = zs(D03_EWMA)
), by = Date]

say("z 컬럼 결측률: BETA %.3f SIZE %.3f IVOL %.3f LIQ %.3f MOM %.3f QUAL %.3f VAL %.3f D03 %.3f",
    mean(is.na(E$X_BETA)), mean(is.na(E$X_SIZE)), mean(is.na(E$X_IVOL)), mean(is.na(E$X_LIQ)),
    mean(is.na(E$X_MOM)), mean(is.na(E$X_QUAL)), mean(is.na(E$X_VAL)), mean(is.na(E$X_D03)))

# style 간 pooled 상관 (RF-R5 재료)
sc <- c("X_BETA","X_SIZE","X_IVOL","X_LIQ","X_MOM","X_QUAL","X_VAL","X_D03")
CM <- cor(as.matrix(E[, ..sc]), use = "pairwise.complete.obs")
say("style 상관 (pooled):"); print(round(CM, 3))

write_parquet(E, file.path(OUT, "exposure_panel.parquet"))
saveRDS(list(style_cor = CM, n = nrow(E), n_months = uniqueN(E$Date)),
        file.path(OUT, "r1_meta.rds"))
say("저장: %s/exposure_panel.parquet", OUT)
