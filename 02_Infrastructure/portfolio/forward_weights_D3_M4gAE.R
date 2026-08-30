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
N_TARGET<-20L; MIN_NAMES<-15L; LAMBDA<-1.5; TOPHI<-3.0; UB<-0.20; UB_CRISIS<-0.10; LIQ<-2e8
cat(sprintf("=== D3 (M4∩AE 게이트) forward AS_OF=%s ===\n", AS_OF))
## ★가중 규약 = admit 정본 (2026-08-08 도훈 승인 "정본으로 정렬해").
##   구판은 인라인 z-선형 `.tilt`(tophi 미적용 · CRISIS ub 분기 없음 · 선별순서 상이)를 써서
##   북 기록 체계(linear_tilt_to_penalty_qd)와 갈려 있었다 — 실측 월 괴리 24~42%,
##   overlay 결합 MDD 29.02%(제약 위반) vs 정본 23.28%(충족). 근거: chip task_fea61227.
##   ★정본 함수는 **재구현하지 않고 계약 모듈을 source** 한다(재구현 표류가 이 결함의 기전이었다).
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))

## --- 1. base sleeve (정본 엔진: top-N by score_eff → 유동성 교집합 → rank-tilt + tophi + CRISIS cap) ---
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),col_select=c("Date","Ticker","Name","Sector","Close","Vol")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]

## 정본 선별·가중 1개월 (run_all.R 285-405 / extract_book_carrier.R 57-99 동일 로직)
.canon_month <- function(sig, w_prev) {
  p <- ap[Date==sig & !is.na(score_eff)]
  if (!nrow(p)) stop(sprintf("[base] alpha_scores 에 sig_date %s 없음", sig))
  rg <- p$regime_state[1]
  setorder(p, -score_eff)
  n_el <- nrow(p); n_tg <- min(N_TARGET, n_el)
  if (n_tg < MIN_NAMES && n_el >= MIN_NAMES) n_tg <- MIN_NAMES
  pk <- p[seq_len(n_tg)]                                  ## ★정본 순서: 먼저 top-N, 그 다음 유동성 교집합
  sd_ <- min(raw[Date >= sig]$Date)
  liq <- raw[Date >= sd_-30L & Date < sd_, .(ATV=mean(TV,na.rm=TRUE)), by=Ticker][ATV>=LIQ, Ticker]
  tk <- intersect(pk$Ticker, liq); if (length(tk) < 5L) tk <- pk$Ticker
  pk <- pk[Ticker %in% tk]
  a <- setNames(pk$score_eff, pk$Ticker)
  ub_use <- if (identical(rg, "CRISIS")) min(UB, UB_CRISIS) else UB
  w <- linear_tilt_to_penalty_qd(a, lambda=LAMBDA, w_prev=w_prev, phi=TOPHI, lb=0, ub=ub_use)
  names(w) <- names(a)
  list(w = normalize_long_only(w, lb=0, ub=ub_use, target_sum=1), regime = rg, ub = ub_use, picks = pk)
}

## w_prev 체인 — tophi(φ=3)는 전월 비중과 블렌드하므로 시작점이 필요하다.
## 정본 엔진 산출인 book_carrier 를 이어받고, 캐리어 종점~AS_OF 사이 공백월은 같은 엔진으로 replay 한다.
## ★캐리어 부재/추월 시 fail-closed — w_prev=NULL 로 조용히 낙하하면 다른 비중이 나온다.
car_path <- file.path(ROOT, "06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet")
if (!file.exists(car_path)) stop("[base] book_carrier 부재 — extract_book_carrier.R 선행 필요(w_prev 체인 시작점)")
car <- as.data.table(read_parquet(car_path)); car[, decision_date := as.Date(decision_date)]
last_dd <- max(car$decision_date)
if (last_dd >= AS_OF) stop(sprintf("[base] 캐리어 종점(%s)이 AS_OF(%s) 이상 — 체인 방향 이상, 중단", last_dd, AS_OF))
w_prev <- { x <- car[decision_date==last_dd]; setNames(x$weight_strategy, x$Ticker) }
## ★2026-08-13 수리 (도훈 승인): n_gap=0 일 때 seq(Date, by="month", length.out=0) 가 에러
##   (`zero-length component [[5]] in non-empty "POSIXlt"`). 발화 조건 = 캐리어 종점이 AS_OF
##   직전월 = **공백월 없는 정상 운용 상태**. 08-08 수용검증은 그날 캐리어가 2개월 이전이라
##   n_gap=1 로 우회돼 통과했고, 08-09 캐리어 연장으로 n_gap=0 경로가 도달 가능해졌다.
##   로직 동등 — 0 케이스만 빈 벡터로 방어한다.
.n_gap <- max(0L, 12L*(as.integer(format(AS_OF,"%Y"))-as.integer(format(last_dd,"%Y"))) +
                  (as.integer(format(AS_OF,"%m"))-as.integer(format(last_dd,"%m"))) - 1L)
gap <- if (.n_gap > 0L) {
  seq(seq(last_dd, by="month", length.out=2)[2], by="month", length.out=.n_gap)
} else as.Date(character(0))
gap <- gap[gap < AS_OF]
for (g in as.list(gap)) { w_prev <- .canon_month(as.Date(g), w_prev)$w
  cat(sprintf("[chain] %s 경유 (n=%d)\n", as.Date(g), length(w_prev))) }
.cm <- .canon_month(AS_OF, w_prev)
w_base <- .cm$w; REGIME <- .cm$regime; picks <- .cm$picks
cat(sprintf("[base] regime=%s ub=%.2f | n=%d | max_w=%.4f | Sum=%.4f | tophi 체인 %s→%s\n",
            REGIME, .cm$ub, length(w_base), max(w_base), sum(w_base), last_dd, AS_OF))

## --- 2. m4_scalar (동일 로드) ---
m4 <- as.data.table(read_parquet(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))); m4[, Date:=as.Date(Date)]
m4r <- m4[Date<=AS_OF][which.max(Date)]; m4_scalar <- if(nrow(m4r)) m4r$weight_str1715[1] else 1.0
cat(sprintf("[m4] @%s weight=%.4f\n", as.character(m4r$Date), m4_scalar))

## --- 2b. ★AE fire_seq (walk-forward, last_feat < AS_OF) ---
ae_path <- file.path(ROOT,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")
## ★생산자 정본 = 02_Infrastructure/regime/ae_regime_monthly.py (월간 배관, 러너 [1a2]).
##   구 문구는 ae_regime_extend.py 를 가리켰는데 그건 동결된 실험 확장기다 —
##   EXTRA_DECISIONS 하드코딩이라 그대로 부르면 같은 223행을 재생산하는 침묵 no-op 이다.
if(!file.exists(ae_path)) stop("[AE] ae_regime_signal_ext.parquet 부재 — ae_regime_monthly.py 선행 필요(러너 [1a2] 월간 배관)")
ae <- as.data.table(read_parquet(ae_path)); ae[, decision_date:=as.Date(decision_date)]
## ── ★AE 신선도 하드 검사 (2026-08-30 신설, 도훈 지시) ─────────────────────────
##   구판: `ae[decision_date<=AS_OF][which.max(decision_date)]` — AS_OF 행이 없으면
##   **직전 달 행을 조용히 재사용**했다. 이것은 폴백이 아니라 **침묵 절단**이다:
##     · 아래 PIT 가드(`last_feat < AS_OF`)는 낡음을 구조적으로 못 잡는다 —
##       신호가 오래될수록 last_feat 이 AS_OF 에서 더 멀어져 **더 잘 통과한다**.
##     · 실측 2026-08-01~30: 생산자에 호출자가 없어 신호가 한 달 정지했는데
##       배포는 매달 초록이었다. 2026-09 는 m4 미발화(gate=1.00 고정)라 무해했을 뿐,
##       m4 발화월(실측 37개월 중 36, 97.3%)에는 **30% de-risk 오판**이 된다.
##   ⇒ 당월 결정행을 **요구**한다. 없으면 낡은 값으로 비중을 내지 않고 멈춘다.
##   관련: feedback-freshness-must-be-measured-at-the-consumption-panel
aer <- ae[decision_date == AS_OF]
if (nrow(aer) != 1L) {
  .amax <- if (nrow(ae)) as.character(max(ae$decision_date)) else "(빈 패널)"
  stop(sprintf(paste0("[AE] ★신선도 FAIL — 결정일 %s 행이 %d건(1건이어야). 패널 최대 decision_date=%s.\n",
                      "     낡은 AE 로 D3 게이트를 계산하지 않는다(직전 달 조용한 재사용 = 침묵 절단).\n",
                      "     조치: python 02_Infrastructure/regime/ae_regime_monthly.py --as-of %s --advance-pin"),
               as.character(AS_OF), nrow(aer), .amax, as.character(AS_OF)))
}
ae_fire <- as.integer(aer$fire_seq[1])
ae_lfd  <- as.character(aer$last_feat_date[1])
## PIT: last_feat < AS_OF. ★구판은 `is.na(ae_lfd) || ...` 라 **NA 가 통과**했다 —
##   미측정을 합격으로 접는 형태(이 저장소의 '빈 결과 = 합격' 계통). NA 도 막는다.
if (is.na(ae_lfd)) stop(sprintf("[AE] last_feat_date 결측 — PIT 판정 불가(결정일 %s)", as.character(AS_OF)))
stopifnot(as.Date(ae_lfd) < AS_OF)
cat(sprintf("[AE] decision@%s fire_seq=%d (last_feat %s, PIT OK · 신선도 OK: AS_OF 당월행)\n",
            as.character(aer$decision_date[1]), ae_fire, ae_lfd))

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
## q20 소스 교체 (2026-08-02 정리 2단계): 2-1 정적 사본(2026-06 동결) → WT-H rerun 정본(매월 재생성).
## 실측: Δq20 = -0.0005 · 8월 zlt 판정 동일(TRUE) — 판정 뒤집힘 없음 확인 후 교체.
prl <- fread(file.path(ROOT,"qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"))
q20_past <- as.numeric(quantile(prl$R05_z_avg[!is.na(prl$R05_z_avg)],0.20,na.rm=TRUE)); zlt <- !is.na(R05_z_avg)&&R05_z_avg<q20_past
beta_R05 <- fcase(REGIME=="CRISIS"&zlt,0.30, REGIME=="CRISIS",0.50, REGIME=="CAUTION"&zlt,0.50, REGIME=="CAUTION",0.70, REGIME%in%c("BULL","NORMAL")&zlt,0.85, default=1.0)
cat(sprintf("[β_R05] regime=%s z=%.3f → %.2f\n", REGIME, R05_z_avg, beta_R05))
## ── FQ-119 라벨 자격 관문 (2026-08-08 배선) — ★경고 전용, 배포 무개입 ─────────────
##   위 fcase 는 REGIME 라벨을 실자본 노출(β)로 바꾼다. 그 라벨이 자격이 있는지를 **기록**한다.
##   ★차단하지 않는다: 라이브 리밸을 관문이 멈추는 것은 도훈 confirm 사안이고, 비중 산출은
##     이 블록 이전에 이미 끝나 있다(아래 tryCatch 는 어떤 경우에도 w_fin 을 건드리지 않는다).
##   ★basis = alpha_scores_regime_state — 배포가 읽는 바로 그 라벨(어휘가 unified 계열과 다르다).
LABEL_GATE <- tryCatch({
  .rlg_f <- c("02_Infrastructure/contracts/regime_label_gate.R",
              file.path(ROOT, "02_Infrastructure/contracts/regime_label_gate.R"))
  .rlg_f <- .rlg_f[file.exists(.rlg_f)]
  if (!length(.rlg_f)) stop("regime_label_gate.R 부재")
  source(.rlg_f[1])
  g <- regime_label_gate(asof = AS_OF, label_basis = "alpha_scores_regime_state", proj = ROOT)
  rlg_enforce(g, site = "forward_weights_D3_M4gAE/beta_R05", mode = "warn")   # ★mode 고정 — env 로 block 승격 불가
  cat(sprintf("[FQ-119 라벨 자격] %s | lift %.2fx p %.5f (n=%d월) | lag1 보존율 %.2f\n",
              g$verdict, g$lift, g$fisher_p, g$n, g$diag_lag1$retention))
  rlg_summary(g)
}, error = function(e) list(verdict = "GATE_ERROR", reason = conditionMessage(e),
                            note = "관문 실패는 배포에 영향 없음(경고 전용) — 판정 부재로 기록"))

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
  formula="w_str1715(rank-tilt λ=1.5 + tophi φ=3 + CRISIS ub 0.10) × [M4∩AE gate] × β_R05_V5(regime,R05_z)  [Layer4 없음]",
  d3_swapin=TRUE, d3_decision="WT-D20260719_001 D3 swap-in (도훈 승인 2026-07-19)",
  tilt_convention=list(
    engine="02_Infrastructure/portfolio/strategy_tilt_weights.R::linear_tilt_to_penalty_qd (run_all.R:161-187 verbatim)",
    lambda=LAMBDA, tophi=TOPHI, ub=UB, ub_crisis=UB_CRISIS,
    selection_order="top-N by score_eff → liquidity intersect (run_all.R 정본 순서)",
    w_prev_chain=sprintf("book_carrier(%s) + replay %d gap months", as.character(last_dd), length(gap)),
    aligned_on="2026-08-08 (도훈 승인 '정본으로 정렬해', chip task_fea61227)",
    supersedes="인라인 z-선형 .tilt — tophi 미적용·CRISIS ub 분기 없음·선별순서 상이(3세대 재구현 표류)"),
  overlays=list(m4_scalar=m4_scalar, ae_fire_seq=ae_fire, m4_ae_gate=gate,
    gate_rule="0.70 if (m4<0.999 AND ae_fire==1) else 1.00",
    beta_faith=list(value=1.0, status="REMOVED_Layer4"),
    beta_R05_V5=list(value=beta_R05,regime=REGIME,R05_z_avg=R05_z_avg,
      # FQ-119: β 를 정한 라벨의 자격 판정을 manifest 에 동반 기록(경고 전용 — 배포 미개입).
      label_gate=LABEL_GATE)),
  invested=invested, cash_pct=cash, n_equity=sum(out$Ticker!="CASH"),
  inert_note=sprintf("2026-07 m4=%.4f(미발화)→gate=1.0 → noLayer4와 동일(swap 실효 0). D3 첫 실효=M4 발화 첫 달", m4_scalar),
  pit=list(no_future_reference=TRUE, ae_last_feat=ae_lfd, ae_pit_ok=(is.na(ae_lfd)||as.Date(ae_lfd)<AS_OF)),
  governance=list(book_state="D3 swap-in (2026-07-19, 도훈 승인)", production_staging=TRUE, source_readonly="05_Production forward_weights_R05_noLayer4.R mirror + AE gate"))
write_json(man, file.path(OUT, sprintf("%s_M4gAE_manifest.json",dt)), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n저장: %s_M4gAE_weights_cap_0p20.csv (Sum_w=%.4f, 주식 %.1f%% / 현금 %.1f%%)\n", dt, sum(out$Weight), invested*100, cash*100))
