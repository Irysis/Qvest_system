## ============================================================================
## STR_1715_on_M4_R05_noLayer4 — FORWARD 배포 비중 생성기 (Layer4 제거 이행)
## WT-D20260702_002 Step 2. 도훈 FINAL 승인 2026-07-02 (REMOVE_LAYER4).
##
## 근거: forward_weights_R05_FAITH.R (현 배포 코드)의 정확 미러 —
##   유일한 차이: β_faith(Layer4) 제거 = β_faith := 1.0 (미적용).
##   w_final(i) = w_str1715(i) × m4_scalar × β_R05_V5(regime, R05_z)   [β_faith 없음]
##   invested   = m4_scalar × β_R05                                    [β_faith 곱 제거]
##
## ★05_Production 파일 수정 금지 — 참조만. 산출은 본 WT output dir로.
## PIT: β_R05는 factor_db(prev month) + regime(alpha_scores AS_OF)만. 미래참조 0.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
AS_OF <- as.Date(Sys.getenv("PG2_AS_OF", "2026-07-01"))
OUT <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output")
N_TARGET<-20; LAMBDA<-1.5; UB<-0.20; LIQ<-2e8
cat(sprintf("=== noLayer4 forward (Layer4 제거) AS_OF=%s ===\n", AS_OF))
.norm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt <- function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}

## --- 1. base sleeve (FAITH/AR forward와 동일) ---
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date:=as.Date(Date)]
panel <- ap[Date==AS_OF & !is.na(score_eff)]; stopifnot(nrow(panel)>0); REGIME <- panel$regime_state[1]
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),col_select=c("Date","Ticker","Name","Sector","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]
liquid <- raw[Date>=AS_OF-30L & Date<AS_OF, .(ATV=mean(TV,na.rm=TRUE)), by=Ticker][ATV>=LIQ, Ticker]
panel <- panel[Ticker %in% liquid]; setorder(panel,-score_eff); picks <- panel[seq_len(min(N_TARGET,nrow(panel)))]
w_base <- .tilt(setNames(picks$score_eff, picks$Ticker)); names(w_base)<-picks$Ticker
cat(sprintf("[base] regime=%s | top-%d liq | Sum=%.4f\n", REGIME, length(w_base), sum(w_base)))

## --- 2. m4_scalar (동일) ---
m4 <- as.data.table(read_parquet(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))); m4[, Date:=as.Date(Date)]
m4r <- m4[Date<=AS_OF][which.max(Date)]; m4_scalar <- if(nrow(m4r)) m4r$weight_str1715[1] else 1.0
cat(sprintf("[m4] @%s weight=%.4f\n", as.character(m4r$Date), m4_scalar))

## --- 3. β_faith 제거 (Layer4 removal) ---
beta_faith <- 1.0  ## ★ Layer4 제거: β_faith 미적용 (도훈 FINAL 2026-07-02)
cat("[β_faith] REMOVED (Layer4 제거) → 1.00 (미적용)\n")

## --- 4. β_R05_V5 (FAITH forward와 동일) ---
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

## --- 5. 결합 (β_faith 제거) + 저장 ---
invested <- m4_scalar*beta_R05; cash <- 1-invested; w_fin <- w_base*invested   ## ★ β_faith 곱 제거
nm <- raw[!is.na(Name)&Ticker%in%names(w_fin), .SD[which.max(Date)], by=Ticker, .SDcols=c("Name","Sector")]
out <- merge(data.table(Ticker=names(w_fin),Weight=as.numeric(w_fin)), nm, by="Ticker", all.x=TRUE); setorder(out,-Weight)
out <- rbindlist(list(data.table(Ticker="CASH",Weight=cash,Name="CASH (단기예금/MMF)",Sector="Cash"), out), use.names=TRUE); out[, rank:=.I-1L]
cat(sprintf("\n[overlay noL4] m4=%.4f × β_R05=%.2f = invested %.4f → CASH %.2f%%\n", m4_scalar,beta_R05,invested,cash*100))
print(out[, .(rank,Ticker,Name,Weight=round(Weight,4))])
dt <- format(AS_OF,"%Y%m%d")
fwrite(out[,.(rank,Ticker,Name,Sector,Weight)], file.path(OUT, sprintf("%s_noLayer4_weights_cap_0p20.csv",dt)))
man <- list(strategy="STR_1715_on_M4_R05_noLayer4_PG2", as_of=as.character(AS_OF),
  formula="w_str1715 × m4 × β_R05_V5(regime,R05_z)  [Layer4(β_faith) 제거]",
  layer4_removed=TRUE, layer4_removal_decision="WT-D20260702_002 REMOVE_LAYER4 (도훈 2026-07-02)",
  overlays=list(m4_scalar=m4_scalar, beta_faith=list(value=1.0, status="REMOVED_Layer4"),
    beta_R05_V5=list(value=beta_R05,regime=REGIME,R05_z_avg=R05_z_avg)),
  invested=invested, cash_pct=cash, n_equity=sum(out$Ticker!="CASH"),
  pit=list(no_future_reference=TRUE, beta_faith="removed"),
  governance=list(book_state="Layer4 removal (2026-07-02, 도훈 FINAL)", production_staging=TRUE, source_readonly="05_Production forward_weights_R05_FAITH.R mirror"))
write_json(man, file.path(OUT, sprintf("%s_noLayer4_manifest.json",dt)), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n저장: %s_noLayer4_weights_cap_0p20.csv (Sum_w=%.4f, 주식 %.1f%% / 현금 %.1f%%)\n", dt, sum(out$Weight), invested*100, cash*100))
