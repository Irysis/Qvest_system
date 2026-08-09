## =============================================================================
## FQ-223 (B)(C)(D) — 하류 전파 실측 + 오염 규모 + 수리 범위
##
## [1] 매칭 양성 대조: **같은 63일 차분 공식**을 target_price(롤오버 lift 1.008 = 비해당)에
##     가한다. M26 의 4/5월 이상이 '공식 아티팩트' 라면 target_price 에서도 나와야 하고,
##     '롤오버' 라면 나오지 않아야 한다. 같은 실행·같은 창·같은 통계.
## [2] 63일 차분 지문 — revenue_fy1(M26) / op_profit_fy1(M28) / eps_1y(SE02 후보창) /
##     bps_1y / dps_1y / target_price(대조)
## [3] 벤더 계산 필드 지문 — eps_chg_1m(C02·★현행 PG2 book 소비) / esbr(C04·★book) /
##     sue(C01·★book) / escr / eps_chg_3m. 벤더가 자체 차분을 롤오버 위로 했는지.
## [4] M28 오염 census (M26 과 동일 절차)
##
## 읽기 전용. factor_db 재빌드 없음. metric_type: canonical_screen_diag.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
SRC  <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
CD   <- file.path(ROOT, ".cache/consensus")
say <- function(fmt, ...) { cat(sprintf(paste0("[c1] ", fmt, "\n"), ...)); flush.console() }
TOL <- 1e-12; LAG <- 63L

## ---------------------------------------------------------------- [0] 입력
say("================ [0] 입력 ================")
D4 <- as.data.table(read_parquet(file.path(SRC,"alpha_scores.parquet"))); D4[, Date := as.Date(Date)]
sigs <- sort(unique(D4$Date)); K <- length(sigs)
PANEL <- unique(D4[, .(Date, Ticker)])       # 판정 패널의 (월×종목) 격자
say("판정 격자 %d (월 %d · 종목 %d)", nrow(PANEL), K, uniqueN(PANEL$Ticker))

read_metric <- function(m) {
  f <- file.path(CD, paste0(m, ".parquet"))
  if (!file.exists(f)) return(NULL)
  h <- as.data.table(read_parquet(f)); h[, Date := as.Date(Date)]
  h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker","Date")); h[]
}

## 63일 차분 + 롤오버 지문 (한 계열)
fingerprint63 <- function(m) {
  E <- read_metric(m); if (is.null(E) || !nrow(E)) return(NULL)
  ## 롤오버 지문 (b6 재현): 4월 첫 영업일 동시변경 비율 / 그 외
  E2 <- copy(E)[, prev_v := shift(value), by = Ticker][, chg := !is.na(prev_v) & abs(value-prev_v) > TOL]
  lv <- E2[, .(n_live=.N), by=Date]; cg <- E2[chg==TRUE, .(n_chg=.N), by=Date]
  bdd <- merge(lv,cg,by="Date",all.x=TRUE)[is.na(n_chg), n_chg:=0L][, frac := n_chg/n_live][n_live>=50L]
  bdd[, yr := format(Date,"%Y")]
  apr1 <- bdd[format(Date,"%m")=="04"][order(Date), .SD[1L], by=yr]      # 각 연도 4월 첫 영업일
  lift <- median(apr1$frac, na.rm=TRUE) / median(bdd[!(Date %in% apr1$Date), frac], na.rm=TRUE)
  ## 63일 차분
  E[, obs_date := Date]; setkeyv(E, c("Ticker","Date")); TKm <- unique(E$Ticker)
  mkQ <- function(d) { q <- CJ(Ticker=TKm, k=seq_len(K), sorted=FALSE); q[, Date := d[k]]
    setkeyv(q,c("Ticker","Date")); q[] }
  pb <- function(d) { r <- E[mkQ(d), roll=TRUE, on=.(Ticker,Date)]; r[!is.na(value), .(Ticker,k,v=value,dd=obs_date)] }
  N <- pb(sigs); setnames(N, c("v","dd"), c("v_now","d_now"))
  L <- pb(sigs-LAG); setnames(L, c("v","dd"), c("v_lag","d_lag"))
  J <- merge(N, L, by=c("Ticker","k"))[abs(v_lag) > 1e-6]
  J[, raw := (v_now - v_lag)/abs(v_lag)]
  J <- merge(data.table(k=seq_len(K), Date=sigs), J[is.finite(raw)], by="k")
  J <- merge(PANEL, J, by=c("Date","Ticker"))                        # 판정 격자로 축소
  if (!nrow(J)) return(NULL)
  J[, grp := fifelse(format(Date,"%m")=="04","04", fifelse(format(Date,"%m")=="05","05","other"))]
  s <- J[, .(n=.N, frac_zero=mean(abs(raw)<1e-9),
             med_nz=median(abs(raw)[abs(raw)>=1e-9]), q90=quantile(abs(raw),.90),
             frac_pos=mean(raw>1e-9), sd=sd(raw)), by=grp]
  o <- s[grp=="other"]
  s[, `:=`(metric=m, rollover_lift=lift,
           mag_ratio_vs_other = med_nz/o$med_nz, pos_ratio_vs_other = frac_pos/o$frac_pos)]
  s[]
}

## ---------------------------------------------------------------- [1] 63일 차분 지문
say("================ [1] 63일 차분 지문 (target_price = 매칭 양성 대조) ================")
mets <- c("revenue_fy1","op_profit_fy1","eps_1y","bps_1y","dps_1y","target_price")
FP <- rbindlist(lapply(mets, function(m) { r <- fingerprint63(m)
  if (is.null(r)) say("  %s: 산출 0 — ★0은 정지 신호(파일/커버리지 확인)", m); r }), fill=TRUE)
if (!nrow(FP)) stop("[c1] 63일 지문 전건 0 — 계측 사망. 중단")
setorder(FP, metric, grp)
for (i in seq_len(nrow(FP))) with(FP[i], say(
  "  %-14s %-5s n=%6d · 영값 %.3f · 비영중앙|.| %.5f · 양비율 %.3f · 대(對)평월 배수 %.2f · 양비율배수 %.2f",
  metric, grp, n, frac_zero, med_nz, frac_pos, mag_ratio_vs_other, pos_ratio_vs_other))
say("--- 요약: 4월 이상 배수 vs 롤오버 지문 lift ---")
sm <- FP[grp=="04", .(metric, rollover_lift, mag_x = mag_ratio_vs_other, pos_x = pos_ratio_vs_other)]
for (i in seq_len(nrow(sm))) with(sm[i], say("  %-14s 롤오버 lift %6.2f · 4월 크기배수 %5.2f · 4월 양비율배수 %5.2f",
  metric, rollover_lift, mag_x, pos_x))
say("★대조 판정: target_price(lift %.2f) 의 4월 크기배수 %.2f — 1 근방이면 공식 아티팩트 아님(= 롤오버 귀속 성립)",
    sm[metric=="target_price", rollover_lift], sm[metric=="target_price", mag_x])
fwrite(FP, file.path(OUT, "c1_diff63_fingerprint.csv"))

## ---------------------------------------------------------------- [2] 벤더 계산 필드 지문
say("================ [2] 벤더 계산 필드 지문 (현행 PG2 book 소비분 포함) ================")
vend <- c("eps_chg_1m","eps_chg_3m","esbr","escr","sue")
VF <- rbindlist(lapply(vend, function(m) {
  E <- read_metric(m); if (is.null(E) || !nrow(E)) { say("  %s 부재", m); return(NULL) }
  E[, obs_date := Date]; setkeyv(E, c("Ticker","Date")); TKm <- unique(E$Ticker)
  q <- CJ(Ticker=TKm, k=seq_len(K), sorted=FALSE); q[, Date := sigs[k]]
  setkeyv(q, c("Ticker","Date"))
  r <- E[q, roll=TRUE, on=.(Ticker,Date)][!is.na(value), .(Ticker, Date=sigs[k], v=value)]
  r <- merge(PANEL, r, by=c("Date","Ticker"))
  if (!nrow(r)) return(NULL)
  r[, grp := fifelse(format(Date,"%m")=="04","04", fifelse(format(Date,"%m")=="05","05","other"))]
  s <- r[, .(n=.N, frac_zero=mean(abs(v)<1e-9), med_nz=median(abs(v)[abs(v)>=1e-9]),
             frac_pos=mean(v>1e-9), sd=sd(v)), by=grp]
  o <- s[grp=="other"]
  s[, `:=`(metric=m, mag_ratio_vs_other=med_nz/o$med_nz, pos_ratio_vs_other=frac_pos/o$frac_pos)]
  s[]
}), fill=TRUE)
if (!nrow(VF)) stop("[c1] 벤더 필드 지문 0 — 계측 사망. 중단")
setorder(VF, metric, grp)
for (i in seq_len(nrow(VF))) with(VF[i], say(
  "  %-12s %-5s n=%6d · 영값 %.3f · 비영중앙|.| %.5f · 양비율 %.3f · 크기배수 %.2f · 양비율배수 %.2f",
  metric, grp, n, frac_zero, med_nz, frac_pos, mag_ratio_vs_other, pos_ratio_vs_other))
say("★현행 PG2 book 소비 필드(sue=C01 · eps_chg_1m=C02 · esbr=C04) 4월 배수:")
for (m in c("sue","eps_chg_1m","esbr")) {
  r <- VF[metric==m & grp=="04"]
  if (nrow(r)) say("   %-12s 크기배수 %.3f · 양비율배수 %.3f ⇒ %s", m, r$mag_ratio_vs_other, r$pos_ratio_vs_other,
      if (r$mag_ratio_vs_other >= 2 || r$pos_ratio_vs_other >= 1.5) "★롤오버 지문 의심" else "지문 없음")
}
fwrite(VF, file.path(OUT, "c1_vendor_field_fingerprint.csv"))

## ---------------------------------------------------------------- [3] M28 오염 census
say("================ [3] M28(op_profit_fy1) 오염 census ================")
E <- read_metric("op_profit_fy1")
E2 <- copy(E)[, prev_v := shift(value), by=Ticker][, chg := !is.na(prev_v) & abs(value-prev_v)>TOL]
lv <- E2[, .(n_live=.N), by=Date]; cg <- E2[chg==TRUE, .(n_chg=.N), by=Date]
bd <- merge(lv,cg,by="Date",all.x=TRUE)[is.na(n_chg), n_chg:=0L][, frac := n_chg/n_live]
ROLL <- sort(bd[frac>=0.50 & n_live>=50L, Date]); ROLL <- ROLL[format(ROLL,"%m")=="04"]
if (!length(ROLL)) stop("[c1] op_profit_fy1 4월 동시변경일 0건 — 정지 신호")
say("op_profit_fy1 4월 동시변경일 %d개", length(ROLL))
E[, obs_date := Date]; setkeyv(E, c("Ticker","Date")); TKm <- unique(E$Ticker)
mkQ <- function(d) { q <- CJ(Ticker=TKm, k=seq_len(K), sorted=FALSE); q[, Date := d[k]]
  setkeyv(q,c("Ticker","Date")); q[] }
pb <- function(d) { r <- E[mkQ(d), roll=TRUE, on=.(Ticker,Date)]; r[!is.na(value), .(Ticker,k,v=value,dd=obs_date)] }
N <- pb(sigs); setnames(N,c("v","dd"),c("v_now","d_now"))
L <- pb(sigs-LAG); setnames(L,c("v","dd"),c("v_lag","d_lag"))
J <- merge(data.table(k=seq_len(K), Date=sigs), merge(N,L,by=c("Ticker","k")), by="k")
J <- merge(PANEL, J, by=c("Date","Ticker"))
bas <- as.Date(vapply(sigs, function(s){ kk <- ROLL[ROLL<=s]; if(!length(kk)) NA_real_ else as.numeric(max(kk))},0),
               origin="1970-01-01")
J[, b := bas[k]][, contam := !is.na(b) & d_now >= b & d_lag < b][, mon := format(Date,"%m")]
m28 <- J[, .(n=.N, contam=sum(contam), frac=mean(contam)), by=mon][order(mon)]
for (i in seq_len(nrow(m28))) with(m28[i], say("  %s월 n=%6d · 오염 %6d (%.4f)", mon, n, contam, frac))
say("★M28 전체 오염 비중 %.4f (%d/%d) · 04·05 집중도 %.3f",
    mean(J$contam), sum(J$contam), nrow(J), J[mon %in% c("04","05"), sum(contam)]/max(1L,sum(J$contam)))
fwrite(m28, file.path(OUT, "c1_m28_contamination.csv"))

## ---------------------------------------------------------------- [4] 저장
saveRDS(list(FP=FP, VF=VF, m28=m28, m28_frac=mean(J$contam)), file.path(OUT, "c1_results.rds"))
say("저장 완료 → %s", OUT)
