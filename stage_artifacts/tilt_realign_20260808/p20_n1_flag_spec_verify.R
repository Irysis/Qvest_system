# p20_n1_flag_spec_verify.R — N1: flag 스펙 확정 + 재현 검증
# 발견: 문턱 정의는 산출물엔 없지만 `02_Infrastructure/portfolio/run_layer5_rerun_extended.R` 에 있다.
#   정본 스펙 (같은 파일 175~233):
#     z 원천 = stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet 의 R05_Tail_Risk_Z  ★동결 패널
#     선별   = score_eff 상위 20 (Date 별), **유동성 필터 없음**
#     z      = 그 20종목의 R05_Tail_Risk_Z 평균
#     문턱   = expanding past-only q20, 과거 관측 **≥12개**일 때만 산출(그 전은 NA→무발화)
#     매핑   = V5: CRISIS&z<q20 0.3 / CRISIS 0.5 / CAUTION&z<q20 0.5 / CAUTION 0.7 /
#              BULL·NORMAL&z<q20 0.85 / else 1.0
# 내 재계산이 갈린 이유 3가지 가설: ①z 원천(동결패널 vs load_month_factors+align) ②유동성 필터
#   ③min_periods(12 vs 36). 이 스크립트로 정본 스펙 재현 → 원장 beta_R05 와 대조.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

zsrc <- "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"
cat(sprintf("[z 원천] %s — 존재: %s\n", zsrc, file.exists(zsrc)))
stopifnot(file.exists(zsrc))
r05 <- as.data.table(read_parquet(zsrc)); r05[, Date := as.Date(Date)]
stopifnot("R05_Tail_Risk_Z" %in% names(r05))
cat(sprintf("[z 원천] %s행 | %s ~ %s | ★동결 여부 확인: 최신 %s\n",
    format(nrow(r05), big.mark=","), min(r05$Date), max(r05$Date), max(r05$Date)))

asp <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); asp[, Date := as.Date(Date)]
m <- merge(asp[, .(Date, Ticker, score_eff, regime_state)], r05[, .(Date, Ticker, R05_Tail_Risk_Z)],
           by=c("Date","Ticker"), all.x=TRUE)
mv <- m[!is.na(score_eff)]; setorder(mv, Date, -score_eff)
top20 <- mv[, head(.SD, 20), by=Date]
P <- top20[, .(z = mean(R05_Tail_Risk_Z, na.rm=TRUE), n_valid = sum(!is.na(R05_Tail_Risk_Z)),
               regime = regime_state[1]), by=Date]
setorder(P, Date)
cat(sprintf("[패널] %d 신호일 | z 전결측(n_valid==0) %d일 (최근: %s)\n", nrow(P), sum(P$n_valid==0),
    paste(tail(as.character(P[n_valid==0]$Date), 3), collapse=", ")))

expq_spec <- function(x, dates, q=0.20, minp=12L) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= minp) out[i] <- as.numeric(quantile(past, q, na.rm=TRUE)) }
  out
}
P[, q20 := expq_spec(z, Date)]
P[, beta_spec := fcase(is.na(q20), 1.0,
  regime=="CRISIS" & z < q20, 0.30, regime=="CRISIS", 0.50,
  regime=="CAUTION" & z < q20, 0.50, regime=="CAUTION", 0.70,
  regime %in% c("BULL","NORMAL") & z < q20, 0.85, default=1.00)]
P[, key := format(Date + 32, "%Y-%m")]
P[, key := format(as.Date(paste0(format(Date, "%Y-%m"), "-01")) + 32, "%Y-%m")]

L <- fread("06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
L[, key := as.character(realized_ym)]
C <- merge(P[, .(key, Date, regime, z, q20, beta_spec)], L[, .(key, beta_R05, regime_lb=regime)], by="key")
cat(sprintf("\n[재현 검증] n=%d | 일치 %.1f%% | max|Δ| %.3f | cor %.4f\n", nrow(C),
    100*mean(abs(C$beta_spec - C$beta_R05) < 1e-9), max(abs(C$beta_spec - C$beta_R05)),
    suppressWarnings(cor(C$beta_spec, C$beta_R05))))
cat(sprintf("[국면 라벨 정합] 패널 regime vs 원장 regime 일치 %.1f%%\n", 100*mean(C$regime == C$regime_lb)))
bad <- C[abs(beta_spec - beta_R05) > 1e-9]
if (nrow(bad)) {
  cat(sprintf("[불일치 %d건 상위]\n", nrow(bad)))
  print(bad[order(-abs(beta_spec-beta_R05))][1:min(8,nrow(bad)),
    .(key, regime, z=round(z,3), q20=round(q20,3), spec=beta_spec, 원장=beta_R05)])
}
cat(sprintf("\n[판정] 정본 스펙 재현 %s — %s\n",
  ifelse(mean(abs(C$beta_spec-C$beta_R05)<1e-9) >= 0.99, "성공(≥99%)", "부분"),
  ifelse(mean(abs(C$beta_spec-C$beta_R05)<1e-9) >= 0.99,
         "flag 은 완전 재현 가능 — pin 문서화만 하면 N1 종결",
         "잔여 원인 추가 특정 필요")))
fwrite(P[, .(Date, key, regime, z, q20, beta_spec, n_valid)],
       "stage_artifacts/tilt_realign_20260808/p20_flag_spec_panel.csv")
