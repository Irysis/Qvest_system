## ============================================================================
## [STAGED — 05_Production 반영 전 검증판, chip task_fea61227 ④ 수리안]
## STR_1715_on_M4gAE_R05_noLayer4 — D3 FORWARD 배포 비중 생성기 v2 (정본 가중규약 정렬)
##
## 현행 2-4 forward_weights_R05_noLayer4_M4gAE.R 대비 변경 = base sleeve 가중 블록만:
##   ① 인라인 z-선형 .tilt 제거 → 02_Infrastructure/portfolio/strategy_tilt_weights.R
##      source (admit 정본 run_all.R:161-187 verbatim 추출본. 재구현 금지)
##   ② tophi φ=3 w_prev 체인 복원: w_prev = 캐리어(06_Registry/book_carrier) 마지막
##      결정월 비중에서 AS_OF 직전월까지 동일 엔진 replay로 연장 (결정적·자기완결)
##   ③ CRISIS ub=0.10 분기 복원 (run_all.R:332)
##   ④ 선별 순서 정본 정렬: top-N by score_eff → 유동성 교집합 (구: 유동성→top-N)
## 오버레이(M4∩AE gate × β_R05_V5)·저장 포맷 = 현행과 동일 (결함 아님, 불변).
##
## 근거 실측 (2026-08-08, scratchpad/tilt_parity_audit.R):
##   실배포 z-선형 vs 정본 rank+tophi: 06월 42.0% / 07월 39.0% / 08월 24.5% 턴오버 등가
##   괴리, CRISIS cap 0.10 위반 5/4종목, 7월 실현 NAV -1.60%pt.
## PIT: 입력·컷오프 현행과 동일 (score_eff@AS_OF, 유동성 t-30..t-1, factor_db prev). 미래참조 0.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/config.R"))   # CACHE_DIR 선정의 — connector의 self-dir 상대 resolve(호출 스크립트 위치 오해석) 우회
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))   # ★정본 가중 함수 (verbatim)
AS_OF <- as.Date(Sys.getenv("PG2_AS_OF", "2026-08-01"))
OUT <- Sys.getenv("PG2_OUT_DIR", file.path(ROOT, "stage_artifacts/tilt_realign_20260808/output"))
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
N_TARGET<-20L; MIN_NAMES<-15L; UB<-0.20; UB_CRISIS<-0.10; LIQ<-2e8; LAMBDA<-1.5; TOPHI<-3.0
cat(sprintf("=== D3 forward v2 (정본 rank+tophi+CRISIS0.10) AS_OF=%s ===\n", AS_OF))

## --- 0. 입력 로드 ---
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),col_select=c("Date","Ticker","Name","Sector","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]

## --- 1. base sleeve: 정본 엔진 (extract_book_carrier.R 57-99 = run_all.R 285-405 verbatim) ---
## 선별 = top-N by score_eff → 유동성 교집합. 가중 = linear_tilt_to_penalty_qd(λ,φ,w_prev,ub_use).
replay_base <- function(sig_label, w_prev) {
  panel_t <- ap[Date==sig_label & !is.na(score_eff)]
  stopifnot(nrow(panel_t) > 0)
  regime_i <- panel_t$regime_state[1L]
  setorder(panel_t, -score_eff)
  N_elig <- nrow(panel_t); N_tgt <- min(N_TARGET, N_elig)
  if (N_tgt < MIN_NAMES && N_elig >= MIN_NAMES) N_tgt <- MIN_NAMES
  picks <- panel_t[seq_len(N_tgt)]
  alpha_t <- setNames(picks$score_eff, picks$Ticker)
  start_d <- min(raw[Date >= sig_label]$Date)
  liq_data <- raw[Date >= (start_d - 30L) & Date < start_d, .(ADV = mean(TV, na.rm=TRUE)), by=Ticker]
  liquid <- liq_data[ADV >= LIQ, Ticker]
  tk_liq <- intersect(names(alpha_t), liquid)
  if (length(tk_liq) < 5L) tk_liq <- names(alpha_t)
  alpha_liq <- alpha_t[tk_liq]
  ub_use <- if (identical(regime_i, "CRISIS")) min(UB, UB_CRISIS) else UB
  w_raw <- linear_tilt_to_penalty_qd(alpha_liq, lambda=LAMBDA, w_prev=w_prev, phi=TOPHI, lb=0, ub=ub_use)
  names(w_raw) <- names(alpha_liq)
  w <- normalize_long_only(w_raw, lb=0, ub=ub_use, target_sum=1)
  list(w=w, regime=regime_i, ub=ub_use)
}

## --- 1b. w_prev 체인: 캐리어 마지막 결정월 → AS_OF 직전월까지 replay 연장 ---
car <- as.data.table(read_parquet(file.path(ROOT,"06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet")))
car[, decision_date:=as.Date(decision_date)]
last_dd <- max(car$decision_date)
stopifnot(last_dd < AS_OF)
w_chain <- { x <- car[decision_date==last_dd]; setNames(x$weight_strategy, x$Ticker) }
gap_months <- seq(seq(last_dd, by="month", length.out=2)[2], by="month",
                  length.out=max(0L, 12L*(as.integer(format(AS_OF,"%Y"))-as.integer(format(last_dd,"%Y"))) +
                                     (as.integer(format(AS_OF,"%m"))-as.integer(format(last_dd,"%m"))) - 1L))
gap_months <- gap_months[gap_months < AS_OF]
for (m in as.list(gap_months)) { w_chain <- replay_base(as.Date(m), w_chain)$w
  cat(sprintf("[chain] %s 경유 (n=%d, max_w=%.4f)\n", as.Date(m), length(w_chain), max(w_chain))) }
rb <- replay_base(AS_OF, w_chain)
w_base <- rb$w; REGIME <- rb$regime
picks_held <- data.table(Ticker=names(w_base))
cat(sprintf("[base v2] regime=%s ub=%.2f | n=%d | max_w=%.4f | Sum=%.4f | tophi 체인 %s→%s\n",
            REGIME, rb$ub, length(w_base), max(w_base), sum(w_base), last_dd, AS_OF))

## --- 2. m4_scalar (현행 동일) ---
m4 <- as.data.table(read_parquet(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))); m4[, Date:=as.Date(Date)]
m4r <- m4[Date<=AS_OF][which.max(Date)]; m4_scalar <- if(nrow(m4r)) m4r$weight_str1715[1] else 1.0
cat(sprintf("[m4] @%s weight=%.4f\n", as.character(m4r$Date), m4_scalar))

## --- 2b. AE fire_seq (현행 동일) ---
ae_path <- file.path(ROOT,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")
if(!file.exists(ae_path)) stop("[AE] ae_regime_signal_ext.parquet 부재 — ae_regime_extend.py 선행 필요(월간 배관)")
ae <- as.data.table(read_parquet(ae_path)); ae[, decision_date:=as.Date(decision_date)]
aer <- ae[decision_date<=AS_OF][which.max(decision_date)]
ae_fire <- if(nrow(aer)) as.integer(aer$fire_seq[1]) else 0L
ae_lfd <- if(nrow(aer)) as.character(aer$last_feat_date[1]) else NA
stopifnot(is.na(ae_lfd) || as.Date(ae_lfd) < AS_OF)
cat(sprintf("[AE] decision@%s fire_seq=%d (last_feat %s)\n", as.character(aer$decision_date[1]), ae_fire, ae_lfd))

## --- 2c. M4∩AE 게이트 (현행 동일) ---
m4_fires <- as.integer(m4_scalar < 0.999)
gate <- if(m4_fires==1L && ae_fire==1L) 0.70 else 1.00
cat(sprintf("[D3 gate] m4_fires=%d ∩ ae_fire=%d → gate=%.2f\n", m4_fires, ae_fire, gate))

## --- 4. β_R05_V5 (현행 동일 — R05_z_avg 는 보유종목 기준) ---
fdb_path <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF-1,"%Y%m")))
if(!file.exists(fdb_path)) fdb_path <- file.path(ROOT, sprintf(".cache/factor_db/factor_db_%s.parquet", format(AS_OF,"%Y%m")))
f <- as.data.table(read_parquet(fdb_path, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
r05 <- f[Factor_Name=="R05_Tail_Risk" & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]; r05[, sig_date:=AS_OF]
r05a <- align_factor_direction(r05, .load_registry(), sig_date=AS_OF, min_ic_months=12L)
if("Z_Score_Aligned" %in% names(r05a)) r05a[, Z_Score:=Z_Score_Aligned]
R05_z_avg <- mean(merge(picks_held, r05a[,.(Ticker,Z_Score)], by="Ticker")$Z_Score, na.rm=TRUE)
prl <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
q20_past <- as.numeric(quantile(prl$R05_z_avg[!is.na(prl$R05_z_avg)],0.20,na.rm=TRUE)); zlt <- !is.na(R05_z_avg)&&R05_z_avg<q20_past
beta_R05 <- fcase(REGIME=="CRISIS"&zlt,0.30, REGIME=="CRISIS",0.50, REGIME=="CAUTION"&zlt,0.50, REGIME=="CAUTION",0.70, REGIME%in%c("BULL","NORMAL")&zlt,0.85, default=1.0)
cat(sprintf("[β_R05] regime=%s z=%.3f → %.2f\n", REGIME, R05_z_avg, beta_R05))

## --- 5. 결합 + 저장 (현행 동일 포맷) ---
invested <- gate*beta_R05; cash <- 1-invested; w_fin <- w_base*invested
nm <- raw[!is.na(Name)&Ticker%in%names(w_fin), .SD[which.max(Date)], by=Ticker, .SDcols=c("Name","Sector")]
out <- merge(data.table(Ticker=names(w_fin),Weight=as.numeric(w_fin)), nm, by="Ticker", all.x=TRUE); setorder(out,-Weight)
out <- rbindlist(list(data.table(Ticker="CASH",Weight=cash,Name="CASH (단기예금/MMF)",Sector="Cash"), out), use.names=TRUE); out[, rank:=.I-1L]
cat(sprintf("\n[D3 overlay] gate=%.2f × β_R05=%.2f = invested %.4f → CASH %.2f%%\n", gate,beta_R05,invested,cash*100))
print(out[, .(rank,Ticker,Name,Weight=round(Weight,4))])
dt <- format(AS_OF,"%Y%m%d")
fwrite(out[,.(rank,Ticker,Name,Sector,Weight)], file.path(OUT, sprintf("%s_M4gAE_weights_cap_0p20_v2staged.csv",dt)))
man <- list(strategy="STR_1715_on_M4gAE_R05_noLayer4_PG2", as_of=as.character(AS_OF), staged=TRUE,
  formula="w_str1715(rank+tophi, CRISIS ub0.10) × [M4∩AE gate] × β_R05_V5(regime,R05_z)",
  tilt_convention=list(engine="strategy_tilt_weights.R::linear_tilt_to_penalty_qd (run_all.R:161-187 verbatim)",
    lambda=LAMBDA, tophi=TOPHI, ub=UB, ub_crisis=UB_CRISIS,
    w_prev_chain=sprintf("carrier(%s) + replay %d gap months", last_dd, length(gap_months)),
    selection_order="top-N by score_eff → liquidity intersect (run_all.R 정본 순서)",
    supersedes="인라인 z-선형 .tilt (Gen1~3 표류, 2026-08-08 실측 chip task_fea61227)"),
  overlays=list(m4_scalar=m4_scalar, ae_fire_seq=ae_fire, m4_ae_gate=gate,
    beta_R05_V5=list(value=beta_R05,regime=REGIME,R05_z_avg=R05_z_avg)),
  invested=invested, cash_pct=cash, n_equity=sum(out$Ticker!="CASH"),
  pit=list(no_future_reference=TRUE, ae_last_feat=ae_lfd),
  governance=list(staged_only=TRUE, promote_gate="도훈 confirm + promote_to_production() 경유", production_untouched=TRUE))
write_json(man, file.path(OUT, sprintf("%s_M4gAE_manifest_v2staged.json",dt)), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n[STAGED] 저장: %s_M4gAE_weights_cap_0p20_v2staged.csv (Σw=%.4f, 주식 %.1f%%/현금 %.1f%%)\n", dt, sum(out$Weight), invested*100, cash*100))
