## 05_contradictions_vintage_alt.R — (a) 같은 개념 스타일 간 판독 모순 (b) 판 사이 수정으로 바뀐 판독 (c) 저변동성 위기월 점검
##   (d) 대안 판독(유의 문턱 · 등록부 t 2.0) 을 같은 as-of 재현으로 비교. 입력 = 스크래치 사본 · 04 산출 replay_daily.rds.
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE); SNAP <- a[1]; OUT <- a[2]; QM <- a[3]
T_SIG <- as.numeric(fromJSON(file.path(QM, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_graduation[["grade_b_min_portfolio_alpha_t"]])
TR <- as.data.table(read_parquet(file.path(SNAP, "ff5_kr_monthly.parquet")))
SB <- as.data.table(read_parquet(file.path(SNAP, "smartbeta_kr_monthly.parquet")))
CA <- as.data.table(read_parquet(file.path(SNAP, "kr_factor_returns_v2.parquet")))
CA[, ym := sprintf("%s-%s", substr(ym, 1, 4), substr(ym, 5, 6))]
r12 <- function(x) frollmean(x, 12)

## (a) 모순: 완결 12개월 평균 부호가 같은 개념끼리 어긋난 달의 비율
m <- merge(TR[, .(ym, SMB, HML, RMW, MKT)], SB[, .(ym, SIZE, VAL, QUAL, LOWVOL, DIV, MOM)], by = "ym")
m <- merge(m, CA[, .(ym, SMB_ca = SMB, HML_ca = HML, RMW_ca = RMW, WML_ca = WML)], by = "ym", all.x = TRUE)
pairs <- list(c("SMB", "SIZE"), c("HML", "VAL"), c("RMW", "QUAL"), c("HML_ca", "VAL"), c("SMB_ca", "SIZE"), c("RMW_ca", "QUAL"), c("WML_ca", "MOM"))
CT <- rbindlist(lapply(pairs, function(p) { x <- r12(m[[p[1]]]); y <- r12(m[[p[2]]]); ok <- is.finite(x) & is.finite(y)
  data.table(pair = paste(p, collapse = " vs "), n = sum(ok), disagree_share = round(mean(sign(x[ok]) != sign(y[ok])), 3),
             disagree_2016plus = round(mean(sign(x[ok & m$ym >= "2016-01"]) != sign(y[ok & m$ym >= "2016-01"])), 3),
             cor_r12 = round(cor(x[ok], y[ok]), 3)) }))
cat("[a] 같은 개념 스타일의 12개월 평균 부호 모순 비율\n"); print(CT)
## 부활 워치 발화 달(트래커 완결 12개월) 중 스마트베타 소형주 · 가치가 음인 비율
fire <- r12(m$SMB) > 0 & r12(m$HML) > 0
cat(sprintf("트래커 완결 12개월 부활 발화 %d개월 · 그중 스마트베타 소형주 12개월 음 %.0f%% · 가치포워드 음 %.0f%%\n",
            sum(fire, na.rm = TRUE), 100 * mean(r12(m$SIZE)[which(fire)] < 0), 100 * mean(r12(m$VAL)[which(fire)] < 0)))

## (b) 판 사이 수정: 날짜별 사본(그날 발행된 월간 표)으로 낸 '그날의 완결 12개월 판독' 대 오늘 판으로 같은 창을 다시 낸 판독
vs <- sort(Sys.glob(file.path(SNAP, "vint", "ff5_kr_monthly_*.csv")))
VB <- rbindlist(lapply(vs, function(p) { v <- fread(p); setorder(v, ym); w <- tail(v, 12)
  now <- TR[ym %in% w$ym]
  if (nrow(now) != 12) return(NULL)
  lab <- function(d) c(SMB = sign(mean(d$SMB)), HML = sign(mean(d$HML)), RMW = sign(mean(d$RMW)))
  lv <- lab(w); ln <- lab(now)
  data.table(vintage = sub(".*_(\\d{8})\\.csv$", "\\1", p), window_end = max(w$ym),
             SMB_then = sprintf("%+.2f", mean(w$SMB) * 100), SMB_now = sprintf("%+.2f", mean(now$SMB) * 100),
             HML_then = sprintf("%+.2f", mean(w$HML) * 100), HML_now = sprintf("%+.2f", mean(now$HML) * 100),
             RMW_then = sprintf("%+.2f", mean(w$RMW) * 100), RMW_now = sprintf("%+.2f", mean(now$RMW) * 100),
             labels_changed = sum(lv != ln)) }))
VB <- unique(VB, by = c("window_end", "SMB_then", "HML_then", "RMW_then"))
cat("\n[b] 판 사이 수정 — 발행 당시 완결 12개월 평균(%) 대 오늘 판(같은 창)\n"); print(VB)

## (c) 저변동성 위기월: 시장 초과(MKT) 가 가장 나빴던 달들의 스타일 초과수익(%)
mm <- merge(SB, TR[, .(ym, MKT)], by = "ym")
cr <- mm[order(MKT)][1:12, .(ym, MKT = round(MKT * 100, 1), LOWVOL = round(LOWVOL * 100, 1), DIV = round(DIV * 100, 1),
                              VAL = round(VAL * 100, 1), SIZE = round(SIZE * 100, 1), MOM = round(MOM * 100, 1))]
cat("\n[c] 시장 최악 12개월의 스타일 초과수익(%) — 진짜 저변동성이면 대개 양(+)\n"); print(cr)
cat(sprintf("최악 12개월 중 '저변동성' 초과수익 음(−) 비율 = %.0f%% · 고배당 음 = %.0f%%\n",
            100 * mean(cr$LOWVOL < 0), 100 * mean(cr$DIV < 0)))

## (d) 대안 판독 — 같은 창(완결 11 + MTD) 평균의 t 가 등록부 문턱 이상일 때만 강세/약세, 아니면 '뚜렷하지 않음'
D <- readRDS(file.path(OUT, "replay_daily.rds"))
fwd <- function(r, h) { n <- length(r); cs <- c(0, cumsum(log1p(r))); o <- rep(NA_real_, n); i <- seq_len(n - h)
  o[i] <- exp(cs[i + h + 1] - cs[i + 1]) - 1; o }
AL <- rbindlist(lapply(c("SMB", "HML", "RMW"), function(f) {
  t <- D[[paste0("t_", f)]]; L <- ifelse(abs(t) >= T_SIG, sign(t), 0); L[!is.finite(t)] <- NA
  ok <- !is.na(L); Ld <- L[ok]
  ## 뚜렷한 판독 사이 뒤집힘(중립 지나 반대 부호로 가는 것 포함) — 중립 아닌 날만 이어 붙여 센다
  dec <- Ld[Ld != 0]; flips <- sum(dec[-1] != dec[-length(dec)])
  yrs <- as.numeric(diff(range(D$Date[ok]))) / 365.25
  r <- rle(Ld)
  rbindlist(lapply(c(21, 63, 126), function(h) { y <- fwd(D[[f]], h)[ok]; k <- is.finite(y) & Ld != 0
    data.table(factor = f, h_days = h, decisive_share = round(mean(Ld != 0), 3),
               flips_per_year_decisive = round(flips / yrs, 2),
               median_run_decisive_days = median(r$lengths[r$values != 0]),
               hit_when_decisive = round(mean(sign(y[k]) == Ld[k]), 3), n_decisive = sum(k)) }))
}))
cat(sprintf("\n[d] 대안 — |t| ≥ %.1f(등록부) 일 때만 강세/약세 판독\n", T_SIG)); print(AL)
fwrite(CT, file.path(OUT, "diag_contradictions.csv")); fwrite(VB, file.path(OUT, "diag_vintage_labels.csv"))
fwrite(cr, file.path(OUT, "diag_lowvol_crisis_months.csv")); fwrite(AL, file.path(OUT, "diag_alt_sig_label.csv"))
