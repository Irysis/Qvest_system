## ============================================================================
## STR_1715_AR_on_M4_R05 — FORWARD 비중 생성기 (self-contained, 오버레이 항상 신선)
## 도훈 mandate 2026-06-17: 그 코드만 실행하면 전체 PG2 비중(오버레이 포함)이 나오게.
##   "오버레이까지가 PG2" — M4 × β_AR × β_R05 전부 적용. 하드코딩 없이 스케줄/factor_db 직접 read.
##
## w_final(i) = w_str1715(i) × m4_scalar × β_AR × β_R05_V5(regime, R05_z)
##   - w_str1715 : Iter5 alpha(score_eff) top-N × Iter31 linear-tilt(λ=1.5,φ=3,cap0.20)
##   - m4_scalar : M4 BOCPD schedule weight_str1715 @ AS_OF   (factor_engine.R 산출)
##   - β_AR      : beta_t_mapping beta_threshold @ AS_OF      (build_absorption_ratio→optimizer)
##   - β_R05_V5  : 생산 admit variant. CRISIS&z<q20→0.3/CRISIS→0.5/CAUTION&z<q20→0.5/
##                 CAUTION→0.7/BULL·NORMAL&z<q20→0.85/else→1.0   (regime + R05_z_avg)
##
## ★ 전제: 오버레이 엔진들이 AS_OF까지 연장돼 있어야 함 (run_pg2_forward.sh가 보장).
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
STRAT <- file.path(ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

AS_OF <- as.Date(Sys.getenv("PG2_AS_OF", "2026-06-01"))   # 운용월 sig_date
N_TARGET <- 20; LAMBDA <- 1.5; TOPHI <- 3; UB <- 0.20; LIQ <- 2e8
cat(sprintf("=== PG2 forward (오버레이 신선) AS_OF=%s ===\n", AS_OF))

## --- Iter31 tilt 함수 (forward_weights.R 거울) ---
.norm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt <- function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}

## --- 1. base alpha: AS_OF score_eff top-N(liq) × Iter31 tilt ---
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
ap[, Date:=as.Date(Date)]
panel <- ap[Date==AS_OF & !is.na(score_eff)]
stopifnot(nrow(panel)>0)
REGIME <- panel$regime_state[1]
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),col_select=c("Date","Ticker","Name","Sector","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]
liqw <- raw[Date>=AS_OF-30L & Date<AS_OF, .(ATV=mean(TV,na.rm=TRUE)), by=Ticker]
liquid <- liqw[ATV>=LIQ, Ticker]
panel <- panel[Ticker %in% liquid]; setorder(panel,-score_eff)
picks <- panel[seq_len(min(N_TARGET,nrow(panel)))]
w_base <- .tilt(setNames(picks$score_eff, picks$Ticker)); names(w_base)<-picks$Ticker
cat(sprintf("[base] regime=%s | top-%d liq | sum=%.4f\n", REGIME, length(w_base), sum(w_base)))

## --- 2. m4_scalar: M4 schedule @ AS_OF (신선) ---
m4 <- as.data.table(read_parquet(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")))
m4[, Date:=as.Date(Date)]
m4r <- m4[Date<=AS_OF][which.max(Date)]
m4_scalar <- if(nrow(m4r)) m4r$weight_str1715[1] else 1.0
cat(sprintf("[m4] @%s weight_str1715=%.4f (cash %.1f%%)\n", as.character(m4r$Date), m4_scalar, (1-m4_scalar)*100))

## --- 3. β_AR: beta_t_mapping @ AS_OF (신선) ---
bm <- fread(file.path(ROOT,"stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"))
bm[, Date:=as.Date(Date)]; bmr <- bm[Date<=AS_OF][which.max(Date)]
beta_AR <- if(nrow(bmr)) bmr$beta_threshold[1] else 1.0
cat(sprintf("[β_AR] @%s beta_threshold=%.2f\n", as.character(bmr$Date), beta_AR))

## --- 4. β_R05_V5: regime + R05_z_avg(top20) vs q20_past (신선) ---
ym <- format(AS_OF,"%Y%m"); fdb_m <- as.integer(ym)
# R05_Tail_Risk Z from same-month factor_db (end-prev-month data), aligned
fdb_path <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF-1,"%Y%m")))
if(!file.exists(fdb_path)) fdb_path <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", ym))
f <- as.data.table(read_parquet(fdb_path, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
r05 <- f[Factor_Name=="R05_Tail_Risk" & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]
r05[, sig_date:=AS_OF]
r05a <- align_factor_direction(r05, .load_registry(), sig_date=AS_OF, min_ic_months=12L)
if("Z_Score_Aligned" %in% names(r05a)) r05a[, Z_Score:=Z_Score_Aligned]
R05_z_avg <- mean(merge(picks[,.(Ticker)], r05a[,.(Ticker,Z_Score)], by="Ticker")$Z_Score, na.rm=TRUE)
prl <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
q20_past <- as.numeric(quantile(prl$R05_z_avg[!is.na(prl$R05_z_avg)], 0.20, na.rm=TRUE))
zlt <- !is.na(R05_z_avg) && R05_z_avg < q20_past
beta_R05 <- fcase(
  REGIME=="CRISIS" & zlt, 0.30, REGIME=="CRISIS", 0.50,
  REGIME=="CAUTION" & zlt, 0.50, REGIME=="CAUTION", 0.70,
  REGIME %in% c("BULL","NORMAL") & zlt, 0.85, default=1.0)
cat(sprintf("[β_R05_V5] regime=%s R05_z=%.4f %s q20=%.4f → %.2f\n", REGIME, R05_z_avg, if(zlt)"<" else ">=", q20_past, beta_R05))

## --- 5. 결합 ---
invested <- m4_scalar * beta_AR * beta_R05; cash <- 1 - invested
w_fin <- w_base * invested
nm <- raw[!is.na(Name) & Ticker %in% names(w_fin), .SD[which.max(Date)], by=Ticker, .SDcols=c("Name","Sector")]
out <- data.table(Ticker=names(w_fin), Weight=as.numeric(w_fin))
out <- merge(out, nm, by="Ticker", all.x=TRUE); setorder(out,-Weight)
out <- rbindlist(list(data.table(Ticker="CASH",Weight=cash,Name="CASH (단기예금/MMF)",Sector="Cash"), out), use.names=TRUE)
out[, rank:=.I-1L]
cat(sprintf("\n[overlay] m4=%.2f × β_AR=%.2f × β_R05=%.2f = invested %.4f → CASH %.2f%%\n", m4_scalar,beta_AR,beta_R05,invested,cash*100))
cat("=== 최종 비중 ===\n"); print(out[, .(rank,Ticker,Name,Weight=round(Weight,4))])
cat(sprintf("Σw=%.4f | 현금 %.2f%% + 주식 %.2f%%\n", sum(out$Weight), cash*100, invested*100))

## --- 6. 저장 ---
od <- file.path(STRAT,"production_weights"); dir.create(od,showWarnings=FALSE,recursive=TRUE)
dt <- format(AS_OF,"%Y%m%d")
fwrite(out[,.(rank,Ticker,Name,Sector,Weight)], file.path(od, sprintf("%s_R05_AR_weights_cap_0p20.csv",dt)))
man <- list(strategy="STR_1715_AR_on_M4_R05_overlay_PG2", as_of=as.character(AS_OF), recompute="2026-06-17",
  formula="w_str1715 × m4_scalar × β_AR × β_R05_V5(regime,R05_z)",
  overlays=list(m4_scalar=list(value=m4_scalar,date=as.character(m4r$Date),source="M4 BOCPD schedule (신선)"),
    beta_AR=list(value=beta_AR,date=as.character(bmr$Date),source="absorption ratio→beta_threshold (신선)"),
    beta_R05_V5=list(value=beta_R05,regime=REGIME,R05_z_avg=R05_z_avg,q20_past=q20_past,variant="V5 (생산 admit)")),
  invested=invested, cash_pct=cash, n_equity=sum(out$Ticker!="CASH"),
  pit=list(no_future_reference=TRUE, data_cutoff="prev month-end", basis="self-contained: 스케줄/factor_db 직접 read"),
  governance=list(book_state="UNCHANGED (governor 정지)", telegram="NOT sent", production_readonly=TRUE))
write_json(man, file.path(od, sprintf("%s_R05_AR_manifest.json",dt)), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("저장: %s_R05_AR_weights_cap_0p20.csv\n", dt))
