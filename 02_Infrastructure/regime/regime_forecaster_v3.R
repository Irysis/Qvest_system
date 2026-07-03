#!/usr/bin/env Rscript
# =============================================================================
# regime_forecaster_v3.R — 국면엔진 강화: 외부 KR-native 매크로(ECOS) 추가
# -----------------------------------------------------------------------------
# v1(전이+nudge)은 최고지만 feature가 전부 US 중심(VIX/HY/TS/BBB/Claims=FRED).
#   v2(US feature 다항로짓)·v1+US-VIX = v1 못 이김(과적합/중복). → 외부소스 강화의
#   진짜 갭 = **KR-native 매크로**(ECOS 한국은행). 본 v3:
#   v1 nudge + KR-native stress 2항:
#     ① KR term spread 역전 (KR_Gov10Y − KR_Call1D 낮을수록 침체 → 방어)
#     ② KR credit spread 확대 (KR_CorpAA − KR_Gov3Y 높을수록 스트레스 → 방어)
#   둘 다 **일간 시장금리**(발표시차 無, PIT 안전; t-1 월말값 + expanding z).
# ★ 허용 외부소스(CLAUDE.md: FRED/ECOS/DART). 크로스마켓/alt-data 아님. 실측 ECOS 캐시(무fabrication).
# ★ 게이트: v3가 v1을 hit-rate AND Brier 둘 다 우위 시에만 채택(과적합 회피). 동일윈도우.
# ★ coef는 기존 US 유사항과 동일 스케일 고정(TS 0.10/credit 0.10) — 사후 튜닝 p-hacking 회피.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
.qvest_root <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[regime_forecaster_v3] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
PROJ <- .qvest_root(); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
MIN_IS <- 100L
regimes <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
KRTS_COEF <- as.numeric(Sys.getenv("FC_KRTS_COEF","0.10"))   # KR term-spread 역전 nudge
KRCS_COEF <- as.numeric(Sys.getenv("FC_KRCS_COEF","0.10"))   # KR credit-spread 확대 nudge

# ---- 1. 월말 패널 (Category + CrisisP + 기존 US stress + ★KR-native) --------
UN <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[, Date:=as.Date(Date)]
RD <- as.data.table(read_parquet(file.path(PROJ,".cache/regime_daily_v2.parquet")))[, Date:=as.Date(Date)]
BR <- as.data.table(read_parquet(file.path(PROJ,".cache/ecos_bond_rates.parquet")))[, Date:=as.Date(Date)]
# KR 금리 wide
BRw <- dcast(BR[Series %in% c("KR_Gov10Y","KR_Gov3Y","KR_Call1D","KR_CorpAA")], Date ~ Series, value.var="Value")
setorder(BRw, Date)
BRw[, KR_TS := KR_Gov10Y - KR_Call1D]              # term spread (역전=침체)
BRw[, KR_CS := KR_CorpAA  - KR_Gov3Y]              # credit spread (확대=스트레스)
# 일간 결측 forward-fill (시장금리 휴장 carry) — PIT 안전(과거값)
BRw[, KR_TS := nafill(KR_TS, "locf")]; BRw[, KR_CS := nafill(KR_CS, "locf")]

setorder(UN, Date); UN[, ym := format(Date,"%Y%m")]
me <- UN[!is.na(Category), .(d=max(Date)), by=ym]
M <- merge(me, UN[, .(Date, Category, CrisisP=MSM_Crisis_Prob)], by.x="d", by.y="Date")
M <- merge(M, RD[, .(Date, Claims=Claims_z_smooth, TS=TS_z_smooth)], by.x="d", by.y="Date", all.x=TRUE)
# KR 월말값: 해당 월말 이전 최근 금리 (asof backward) → t-1 PIT
M <- BRw[, .(Date, KR_TS, KR_CS)][M, on=.(Date=d), roll=TRUE]   # rolling join: 각 월말 d 이전 최근 금리
setnames(M, "Date", "d")
setorder(M, d); M[, CrisisP_chg := CrisisP - shift(CrisisP)]
M <- M[Category %in% regimes]
M[, next_regime := shift(Category, 1L, type="lead")]
# expanding z (PIT): 직전까지 분포로 표준화
exp_z <- function(x){ n<-length(x); z<-rep(NA_real_,n)
  for(i in seq_len(n)){ if(i<24||!is.finite(x[i])) next; h<-x[1:(i-1)]; h<-h[is.finite(h)]
    if(length(h)<24||sd(h)==0) next; z[i]<-(x[i]-mean(h))/sd(h) }; z }
M[, KR_TS_z := exp_z(KR_TS)]; M[, KR_CS_z := exp_z(KR_CS)]
M <- M[d >= as.Date("2003-01-01")]      # KR term/credit + expanding z 안정 구간
n <- nrow(M)
cat(sprintf("[fc_v3] 월말 패널 n=%d (%s..%s) | KR-native term/credit z\n", n, as.character(min(M$d)), as.character(max(M$d))))

brier <- function(p, ai){ y<-rep(0,length(p)); y[ai]<-1; sum((p-y)^2) }
apply_nudge <- function(p, s){ s<-min(s,0.5); if(s>0){ defn<-regimes %in% c("CAUTION","CRISIS","RISK_OFF")
  p[defn]<-p[defn]*(1+s); p[!defn]<-p[!defn]*(1-s/2); p<-p/sum(p) }; p }
v1_hit<-rep(NA,n); v3_hit<-rep(NA,n); base_hit<-rep(NA,n)
v1_br<-rep(NA_real_,n); v3_br<-rep(NA_real_,n); base_br<-rep(NA_real_,n); fc3<-character(n)
for(t in seq_len(n-1)){
  if(t < MIN_IS) next
  cur <- M$Category[t]; actual <- M$next_regime[t]; if(is.na(actual)) next
  ai <- match(actual, regimes)
  hist <- M[1:t]
  trans <- table(factor(hist$Category, regimes), factor(shift(hist$Category,1L,type="lead"), regimes))
  row <- trans[cur, ]; p0 <- (row + 0.5)/sum(row + 0.5)
  s <- 0
  if(is.finite(M$CrisisP_chg[t])) s <- s + max(0, M$CrisisP_chg[t])*1.5
  if(is.finite(M$Claims[t]))      s <- s + max(0, M$Claims[t])*0.15
  if(is.finite(M$TS[t]))          s <- s + max(0, -M$TS[t])*0.10
  # v1
  p1 <- apply_nudge(p0, s); pred1 <- regimes[which.max(p1)]
  v1_hit[t+1]<-as.integer(pred1==actual); v1_br[t+1]<-brier(p1,ai)
  # v3 = v1 + KR-native
  s3 <- s
  if(is.finite(M$KR_TS_z[t])) s3 <- s3 + max(0, -M$KR_TS_z[t])*KRTS_COEF   # 역전(낮은 TS)=방어
  if(is.finite(M$KR_CS_z[t])) s3 <- s3 + max(0,  M$KR_CS_z[t])*KRCS_COEF   # 확대(높은 CS)=방어
  p3 <- apply_nudge(p0, s3); pred3 <- regimes[which.max(p3)]; fc3[t+1]<-pred3
  v3_hit[t+1]<-as.integer(pred3==actual); v3_br[t+1]<-brier(p3,ai)
  # persistence
  base_hit[t+1]<-as.integer(cur==actual); bp<-rep(0.02,length(regimes)); bp[match(cur,regimes)]<-0.92; bp<-bp/sum(bp)
  base_br[t+1]<-brier(bp,ai)
}
ev <- which(!is.na(v1_hit) & !is.na(v3_hit))
v1h<-mean(v1_hit[ev]); v3h<-mean(v3_hit[ev]); bh<-mean(base_hit[ev])
v1b<-mean(v1_br[ev]);  v3b<-mean(v3_br[ev]);  bb<-mean(base_br[ev])
beats_v1 <- (v3h > v1h) && (v3b < v1b); no_worse <- (v3h >= v1h) && (v3b <= v1b)
n_diff <- sum(v1_hit[ev] != v3_hit[ev], na.rm=TRUE)   # 예측이 달라진 월 수 (KR 신호 발화)

fc_series <- data.table(ym=M$ym, forecast_regime=ifelse(nzchar(fc3), fc3, NA_character_))
arrow::write_parquet(fc_series, file.path(PROJ,".cache/regime_forecast_series_v3.parquet"))
res <- list(schema_version="v3", generated=as.character(Sys.Date()),
  method=sprintf("v1 + KR-native ECOS stress(term-spread 역전 coef=%.2f + credit-spread 확대 coef=%.2f). walk-forward 동일윈도우.", KRTS_COEF, KRCS_COEF),
  source="ECOS 한국은행 (KR_Gov10Y/Gov3Y/Call1D/CorpAA, 일간 시장금리·발표시차無)",
  n_eval=length(ev), eval_window=c(as.character(M$d[min(ev)]),as.character(M$d[max(ev)])),
  n_months_kr_changed_pred=n_diff,
  v1_hit_rate=round(v1h,3), v3_hit_rate=round(v3h,3), persistence_hit_rate=round(bh,3),
  v1_brier=round(v1b,4), v3_brier=round(v3b,4), persistence_brier=round(bb,4),
  beats_v1=beats_v1, no_worse_than_v1=no_worse,
  current_regime=M$Category[n], current_forecast=fc3[n] %||% NA,
  adopt=beats_v1, note="채택=beats_v1(hit↑ & Brier↓ 동시). KR-native가 US-feature 천장을 넘는가 테스트.")
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/regime_forecast_v3.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat("\n==== regime_forecaster v3 (외부 KR-native ECOS 강화) ====\n")
cat(sprintf("eval n=%d (%s..%s) | KR신호로 예측바뀐 월=%d\n", length(ev), res$eval_window[1], res$eval_window[2], n_diff))
cat(sprintf("hit-rate:  v3=%.3f  v1=%.3f  persistence=%.3f\n", v3h, v1h, bh))
cat(sprintf("Brier:     v3=%.4f  v1=%.4f  persistence=%.4f\n", v3b, v1b, bb))
cat(sprintf("beats_v1=%s | no_worse=%s → %s\n", beats_v1, no_worse,
  if(beats_v1) "★ KR-native 외부소스 강화 채택" else if(no_worse) "무해(동등)" else "v1 천장 — KR-native도 못 넘음(정직)"))
