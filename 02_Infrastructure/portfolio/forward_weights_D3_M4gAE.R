## ============================================================================
## STR_1715_on_M4gAE_R05_noLayer4 — D3 FORWARD 배포 비중 생성기 (M4∩AE 게이트 swap-in)
## WT-D20260719_001. 도훈 승인 2026-07-19 (D3 swap-in).
##
## 근거: forward_weights_R05_noLayer4.R(현 배포 2-3)의 정확 미러 —
##   유일한 차이: m4_scalar(연속 BOCPD 스케줄) → M4∩AE 게이트로 교체.
##   gate = 0.70  if (m4 발화[m4<0.999] AND AE 발화[fire_seq==1])
##        = 1.00  else            (M4 단독 발화 시 de-risk 제거 = AE 미확인이면 full 투자)
##   w_final(i) = w_str1715(i) × gate × β_R05_V5(regime, R05_z)   [Layer4 없음, m4 대신 gate]
##   invested   = gate × β_R05
##
## ★근거(WT-D20260718_007 R2/R3): D3 교집합 = 인컴번트 오버레이 파레토 지배(calmar 2.089→2.341·
##   MDD −22.1→−19.8%·수익 중립, noLayer4 정본 재측정). 비지도 AE가 지도학습 OOD 실패를 구조해결
##   (2008 GFC 9/9 방어). AE=8개월+ 연속 발화(EXTREME). D3 첫 실효=M4 발화 첫 달(AE는 이미 발화).
## ★2026-07 inert: m4=1.0(미발화)→gate=1.0 → noLayer4와 동일 book(swap 실효 0, 검증됨).
##
## ★05_Production 파일 수정 금지 — 참조만. PIT: β_R05 factor_db(prev)+regime AS_OF, AE fire_seq
##   = last_feat_date < AS_OF(walk-forward, PIT self-check 0). 미래참조 0.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
## AS_OF 기본값은 하드코딩하지 않는다 (도훈 mandate 2026-08-01) — 미지정 시 **당월 1일**.
## 구판 기본값 "2026-07-01" 은 8월 리밸에서 env 를 빼먹으면 조용히 7월 비중을 재산출했다.
AS_OF <- as.Date(Sys.getenv("PG2_AS_OF", format(Sys.Date(), "%Y-%m-01")))
OUT <- Sys.getenv("PG2_OUT_DIR", file.path(ROOT, "qepm/mailbox/worktask/WT-D20260719_001/output"))   ## PG2_OUT_DIR로 production 배치 override
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
N_TARGET<-20; LAMBDA<-1.5; UB<-0.20; LIQ<-2e8
cat(sprintf("=== D3 (M4∩AE 게이트) forward AS_OF=%s ===\n", AS_OF))
.norm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt <- function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}

## --- 1. base sleeve (noLayer4/FAITH/AR forward와 동일 — SELECTION 불변) ---
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date:=as.Date(Date)]
panel <- ap[Date==AS_OF & !is.na(score_eff)]; stopifnot(nrow(panel)>0); REGIME <- panel$regime_state[1]
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),col_select=c("Date","Ticker","Name","Sector","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]
liquid <- raw[Date>=AS_OF-30L & Date<AS_OF, .(ATV=mean(TV,na.rm=TRUE)), by=Ticker][ATV>=LIQ, Ticker]
panel <- panel[Ticker %in% liquid]; setorder(panel,-score_eff); picks <- panel[seq_len(min(N_TARGET,nrow(panel)))]
w_base <- .tilt(setNames(picks$score_eff, picks$Ticker)); names(w_base)<-picks$Ticker
cat(sprintf("[base] regime=%s | top-%d liq | Sum=%.4f\n", REGIME, length(w_base), sum(w_base)))

## --- 2. m4_scalar (동일 로드) ---
m4 <- as.data.table(read_parquet(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))); m4[, Date:=as.Date(Date)]
m4r <- m4[Date<=AS_OF][which.max(Date)]; m4_scalar <- if(nrow(m4r)) m4r$weight_str1715[1] else 1.0
cat(sprintf("[m4] @%s weight=%.4f\n", as.character(m4r$Date), m4_scalar))

## --- 2b. ★AE fire_seq (walk-forward, last_feat < AS_OF) ---
ae_path <- file.path(ROOT,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")
if(!file.exists(ae_path)) stop("[AE] ae_regime_signal_ext.parquet 부재 — ae_regime_extend.py 선행 필요(월간 배관)")
ae <- as.data.table(read_parquet(ae_path)); ae[, decision_date:=as.Date(decision_date)]
aer <- ae[decision_date<=AS_OF][which.max(decision_date)]
ae_fire <- if(nrow(aer)) as.integer(aer$fire_seq[1]) else 0L
ae_lfd <- if(nrow(aer)) as.character(aer$last_feat_date[1]) else NA
stopifnot(is.na(ae_lfd) || as.Date(ae_lfd) < AS_OF)   ## PIT: last_feat < AS_OF
cat(sprintf("[AE] decision@%s fire_seq=%d (last_feat %s, PIT %s)\n", as.character(aer$decision_date[1]), ae_fire, ae_lfd, ifelse(is.na(ae_lfd)||as.Date(ae_lfd)<AS_OF,"OK","VIOLATION")))

## --- 2c. ★M4∩AE 게이트 (m4_scalar 대체) ---
m4_fires <- as.integer(m4_scalar < 0.999)
gate <- if(m4_fires==1L && ae_fire==1L) 0.70 else 1.00
cat(sprintf("[D3 gate] m4_fires=%d ∩ ae_fire=%d → gate=%.2f  (m4 %.4f 대체)\n", m4_fires, ae_fire, gate, m4_scalar))

## --- 3. β_faith 제거 (Layer4 없음) ---
beta_faith <- 1.0
## --- 4. β_R05_V5 (동일) ---
fdb_path <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF-1,"%Y%m")))
if(!file.exists(fdb_path)) fdb_path <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF,"%Y%m")))
f <- as.data.table(read_parquet(fdb_path, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
r05 <- f[Factor_Name=="R05_Tail_Risk" & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]; r05[, sig_date:=AS_OF]
r05a <- align_factor_direction(r05, .load_registry(), sig_date=AS_OF, min_ic_months=12L)
if("Z_Score_Aligned" %in% names(r05a)) r05a[, Z_Score:=Z_Score_Aligned]
R05_z_avg <- mean(merge(picks[,.(Ticker)], r05a[,.(Ticker,Z_Score)], by="Ticker")$Z_Score, na.rm=TRUE)
prl <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
q20_past <- as.numeric(quantile(prl$R05_z_avg[!is.na(prl$R05_z_avg)],0.20,na.rm=TRUE)); zlt <- !is.na(R05_z_avg)&&R05_z_avg<q20_past
beta_R05 <- fcase(REGIME=="CRISIS"&zlt,0.30, REGIME=="CRISIS",0.50, REGIME=="CAUTION"&zlt,0.50, REGIME=="CAUTION",0.70, REGIME%in%c("BULL","NORMAL")&zlt,0.85, default=1.0)
cat(sprintf("[β_R05] regime=%s z=%.3f → %.2f\n", REGIME, R05_z_avg, beta_R05))

## --- 5. 결합 (gate × β_R05, β_faith 없음) + 저장 ---
invested <- gate*beta_R05; cash <- 1-invested; w_fin <- w_base*invested
nm <- raw[!is.na(Name)&Ticker%in%names(w_fin), .SD[which.max(Date)], by=Ticker, .SDcols=c("Name","Sector")]
out <- merge(data.table(Ticker=names(w_fin),Weight=as.numeric(w_fin)), nm, by="Ticker", all.x=TRUE); setorder(out,-Weight)
out <- rbindlist(list(data.table(Ticker="CASH",Weight=cash,Name="CASH (단기예금/MMF)",Sector="Cash"), out), use.names=TRUE); out[, rank:=.I-1L]
cat(sprintf("\n[D3 overlay] gate=%.2f × β_R05=%.2f = invested %.4f → CASH %.2f%%\n", gate,beta_R05,invested,cash*100))
print(out[, .(rank,Ticker,Name,Weight=round(Weight,4))])
dt <- format(AS_OF,"%Y%m%d")
fwrite(out[,.(rank,Ticker,Name,Sector,Weight)], file.path(OUT, sprintf("%s_M4gAE_weights_cap_0p20.csv",dt)))
man <- list(strategy="STR_1715_on_M4gAE_R05_noLayer4_PG2", as_of=as.character(AS_OF),
  formula="w_str1715 × [M4∩AE gate] × β_R05_V5(regime,R05_z)  [Layer4 없음, m4 대신 M4∩AE 게이트]",
  d3_swapin=TRUE, d3_decision="WT-D20260719_001 D3 swap-in (도훈 승인 2026-07-19)",
  overlays=list(m4_scalar=m4_scalar, ae_fire_seq=ae_fire, m4_ae_gate=gate,
    gate_rule="0.70 if (m4<0.999 AND ae_fire==1) else 1.00",
    beta_faith=list(value=1.0, status="REMOVED_Layer4"),
    beta_R05_V5=list(value=beta_R05,regime=REGIME,R05_z_avg=R05_z_avg)),
  invested=invested, cash_pct=cash, n_equity=sum(out$Ticker!="CASH"),
  inert_note=sprintf("2026-07 m4=%.4f(미발화)→gate=1.0 → noLayer4와 동일(swap 실효 0). D3 첫 실효=M4 발화 첫 달", m4_scalar),
  pit=list(no_future_reference=TRUE, ae_last_feat=ae_lfd, ae_pit_ok=(is.na(ae_lfd)||as.Date(ae_lfd)<AS_OF)),
  governance=list(book_state="D3 swap-in (2026-07-19, 도훈 승인)", production_staging=TRUE, source_readonly="05_Production forward_weights_R05_noLayer4.R mirror + AE gate"))
write_json(man, file.path(OUT, sprintf("%s_M4gAE_manifest.json",dt)), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n저장: %s_M4gAE_weights_cap_0p20.csv (Sum_w=%.4f, 주식 %.1f%% / 현금 %.1f%%)\n", dt, sum(out$Weight), invested*100, cash*100))
