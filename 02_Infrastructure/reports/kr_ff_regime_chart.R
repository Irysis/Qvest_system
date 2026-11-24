##=============================================================================
## kr_ff_regime_chart.R — 스타일 국면 브리핑 v4 차트: 한국 FF 요인 정본의 12개월+MTD t · 3개월 t (diagnostic_monitoring)
##   2026-11-24 도훈 "스타일 국면 브리핑 국면판독 부분 개선" · 검토 04_Research/01_reports/style_regime_brief_review_20261124/
##   재료 = .cache/kr_factor_returns_daily.parquet + kr_factor_returns_v2.parquet (build_kr_factor_returns.R · 밤 갱신 [5c]).
##   t(d) = (완결 n−1개월 정본 월간 합 + d 까지 진행월 일간 복리) / (d 까지 252거래일 일간 표준편차 × √창 거래일 수)
##     — style_brief_lib.R::sw_kf_prepare 와 같은 식(마지막 날 값 일치를 실행 중에 확인 · 어긋나면 멈춘다).
##   띠 = ±t_sig(등록부 tier_graduation::grade_b_min_portfolio_alpha_t) — 띠 안은 '판정하지 않음'.
##   PIT: 각 날의 t 는 그날까지의 값만 쓴다(후행 창 · 후행 표준편차). 보이는 기간 = 최근 3년(756거래일 · 달력 관례).
##   경로 덮어쓰기(검사용): KR_FACTOR_DIR(기본 .cache) · FF5_KR_OUT_DIR(기본 outputs/ff5_kr). 쓰기 = 차트 PNG 1장뿐.
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
## 루트 = CLAUDE_PROJECT_DIR → QM_ROOT (build_kr_factor_returns.R::krf_root 와 같은 순서 — ~/.Renviron 의 QM_ROOT 는 export 로 못 덮는다)
.kc_root <- Sys.getenv("CLAUDE_PROJECT_DIR", ""); if (!nzchar(.kc_root)) .kc_root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(.kc_root)) stop("[kr_ff_regime_chart] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
setwd(gsub("\\\\", "/", .kc_root))
source("02_Infrastructure/reports/style_brief_lib.R")
KF_DIR <- Sys.getenv("KR_FACTOR_DIR", ".cache")
OUT_DIR <- Sys.getenv("FF5_KR_OUT_DIR", "outputs/ff5_kr")
dir.create(file.path(OUT_DIR, "charts"), recursive = TRUE, showWarnings = FALSE)
T_SIG <- as.numeric(fromJSON("02_Infrastructure/worktask/constraint_defaults.json")$tier_graduation[["grade_b_min_portfolio_alpha_t"]])
stopifnot(length(T_SIG) == 1L, is.finite(T_SIG))
SHOW_DAYS <- 3L * .SW_KF_SD_DAYS                                   # 최근 3년

D <- as.data.table(read_parquet(file.path(KF_DIR, "kr_factor_returns_daily.parquet"), col_select = c("Date", "MKT_TOTAL", .SW_KF_ALL)))
M <- as.data.table(read_parquet(file.path(KF_DIR, "kr_factor_returns_v2.parquet"), col_select = c("ym", .SW_KF_ALL)))
D[, Date := as.Date(Date)]; setorder(D, Date)
a <- sw_kf_asof(D$Date, Sys.time())
D <- D[Date <= a][complete.cases(D[Date <= a])]
M[, ym := sprintf("%s-%s", substr(as.character(ym), 1, 4), substr(as.character(ym), 5, 6))]; setorder(M, ym)
D[, ym := format(Date, "%Y-%m")]
yms <- sort(unique(c(M$ym, D$ym)))
D[, k := match(ym, yms)]
## 창 합: 완결 (n−1)개월 = 정본 월간(없는 달은 일간 복리로 채우지 않는다 — NA) + 진행월 = 그날까지 일간 복리
tcalc <- function(f, n) {
  mv <- M[[f]][match(yms, M$ym)]                                 # yms 순서의 월간 값(진행월 · 결측월 = NA)
  rs <- frollsum(mv, n - 1L, align = "right")                    # rs[j] = 월 j−(n−2) .. j 합(결측 있으면 NA)
  j <- pmax(D$k - 1L, 1L)
  prev_sum <- ifelse(D$k > n - 1L, rs[j], NA_real_)              # 월 k−(n−1) .. k−1
  mtd <- D[, cumprod(1 + get(f)) - 1, by = ym]$V1
  dcount <- D[, .N, by = ym]; dcount[, k := match(ym, yms)]
  nd_month <- dcount$N[match(seq_along(yms), dcount$k)]; nd_month[is.na(nd_month)] <- 0L
  ndm <- frollsum(as.numeric(nd_month), n - 1L, align = "right")
  nd_prev <- ifelse(D$k > n - 1L, ndm[j], NA_real_)
  nd_mtd <- D[, seq_len(.N), by = ym]$V1
  sdv <- frollapply(D[[f]], .SW_KF_SD_DAYS, sd, align = "right")
  (prev_sum + mtd) / (sdv * sqrt(nd_prev + nd_mtd))
}
for (f in .SW_KF) { D[, (paste0("t12_", f)) := tcalc(f, 12L)]; D[, (paste0("t3_", f)) := tcalc(f, 3L)] }

## 마지막 날 값 = 브리핑(sw_kf_prepare)과 같은가 — 같은 식 두 구현의 대조(어긋나면 차트를 그리지 않는다)
K <- sw_kf_prepare(list(daily = D[, c("Date", "MKT_TOTAL", .SW_KF_ALL), with = FALSE], monthly = M), now = Sys.time())
if (isTRUE(K$ok) && identical(K$mode, "mtd")) {
  dif <- max(abs(unlist(D[.N, paste0("t12_", .SW_KF), with = FALSE]) - K$w12$t[.SW_KF]))
  if (!is.finite(dif) || dif > 1e-8) stop(sprintf("[kr_ff_regime_chart] 차트 t 와 브리핑 t 불일치 %.3g — 그리지 않는다", dif))
}

S <- tail(D, SHOW_DAYS)
cols <- c(SMB = "firebrick", HML = "steelblue", RMW = "darkgreen", CMA = "purple", WML = "darkorange")
lab <- sprintf("%s(%s)", names(.SW_KF_NAME), .SW_KF_NAME)
## v4.1 스타일 동조화(흡수 비율 · style_brief_lib.R::sw_kf_absorption 과 같은 정의) — 보이는 기간의 날마다 그날까지의 500일 · 3개월 창
X5 <- as.matrix(D[, .SW_KF, with = FALSE]); nD <- nrow(D)
ar_at <- function(e, w) { if (e < w) return(NA_real_); ev <- eigen(cov(X5[(e - w + 1L):e, , drop = FALSE]), symmetric = TRUE, only.values = TRUE)$values; ev[1] / sum(ev) }
sidx <- (nD - nrow(S) + 1L):nD
AR500 <- vapply(sidx, ar_at, numeric(1), w = .SW_KF_AR_DAYS); AR63 <- vapply(sidx, ar_at, numeric(1), w = 3L * .SW_KF_MONTH_DAYS)
png(file.path(OUT_DIR, "charts", "kr_ff_regime_t.png"), width = 1250, height = 1000)
par(mfrow = c(3, 1), mar = c(3, 5, 3, 15), cex.main = 1.4, cex.axis = 1.15, cex.lab = 1.2)   # 우측 = 범례(최신 t)
for (w in c("t12", "t3")) {
  Y <- as.matrix(S[, paste0(w, "_", .SW_KF), with = FALSE])
  yl <- range(c(Y, -T_SIG * 1.5, T_SIG * 1.5), na.rm = TRUE)
  plot(S$Date, Y[, 1], type = "n", ylim = yl, xlab = "", ylab = "t",
       main = sprintf("한국 FF 요인 정본 — %s t (~%s · |t|≥%.1f 만 판정 · 띠 안 = 판정 안 함)",
                      if (w == "t12") "12개월+MTD" else "3개월(2완결+MTD)", format(a), T_SIG))
  rect(min(S$Date), -T_SIG, max(S$Date), T_SIG, col = "gray92", border = NA)
  abline(h = c(-T_SIG, 0, T_SIG), lty = c(2, 3, 2), col = "gray40")
  for (j in seq_along(.SW_KF)) lines(S$Date, Y[, j], col = cols[.SW_KF[j]], lwd = 2.2)
  last <- Y[nrow(Y), ]
  legend(x = par("usr")[2] + diff(par("usr")[1:2]) * 0.01, y = par("usr")[4],
         legend = sprintf("%s %+.1f", lab, last), col = cols, lwd = 2.6, bty = "n", cex = 1.1, xpd = TRUE)
}
plot(S$Date, AR500 * 100, type = "l", lwd = 2.4, col = "black", ylim = range(c(AR500, AR63) * 100, na.rm = TRUE),
     xlab = "", ylab = "제1 공통 성분 비중 %",
     main = "스타일 동조화(흡수 비율 · 5요인 공분산 제1 고유값 비중) — 높을수록 여러 스타일이 한 베팅")
lines(S$Date, AR63 * 100, lwd = 1.8, col = "gray45")
legend(x = par("usr")[2] + diff(par("usr")[1:2]) * 0.01, y = par("usr")[4], bty = "n", cex = 1.1, xpd = TRUE,
       legend = c(sprintf("500일 %.0f%%", 100 * tail(AR500, 1)), sprintf("3개월 %.0f%%", 100 * tail(AR63, 1))),
       col = c("black", "gray45"), lwd = c(2.6, 2))
dev.off()
cat(sprintf("[kr_ff_regime_chart] kr_ff_regime_t.png ~%s · 12개월 t: %s\n", format(a),
            paste(sprintf("%s %+.1f", .SW_KF, unlist(D[.N, paste0("t12_", .SW_KF), with = FALSE])), collapse = " ")))
