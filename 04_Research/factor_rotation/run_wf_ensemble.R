#!/usr/bin/env Rscript
# =============================================================================
# run_wf_ensemble.R — Factor Rotation Mode 핵심: anchored walk-forward 앙상블 백테 → FR.
# 모듈 NAV(sim_result) → 국면 조건부 배분(module_dispatcher) → 합성 → build_bt_result(실측)
#   → essence_score(DSR HARD) → FR_XXXX 등재 → OOS retention + placebo 게이트.
#
# ★ FIX #1 (도훈 수용, 2026-06-05): 포트 수익률 자체합성 폐기 → PerformanceAnalytics::Return.portfolio.
#   모듈=asset, 월별 regime weights=월초 적용·월중 frozen(=monthly rebalance), 일간 모듈수익=R.
#   prod(1+r)/cumprod/손Σ 전부 제거. 월 집계는 apply.monthly/Return.cumulative(계약 표준).
#   15bps 국면전환 turnover 비용은 Return.portfolio weight 전이로 산정 후 리밸 시점 차감(정직).
#
# ★ FIX #2 (도훈 a안, 2026-06-05): RCMA를 walk-forward로. compute_rcma(asof)를 연 1회(직전 기간말)
#   재호출 → 그 시점 admitted_by_regime로 풀/국면 후보 제한. 멤버십 시간가변(미래정보 無).
#   정적 module_regime_admission.json은 진단용 — 실측 권위는 본 스크립트의 WF compute_rcma 호출.
#
# PIT: 가중은 IS(t 이전)로만, regime t-1 lag, 모듈 frozen. 실측-only(자체합성 없음, 계약 경유).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
CD <- file.path(PROJ, "02_Infrastructure/contracts")
source(file.path(PROJ, "02_Infrastructure/portfolio/module_dispatcher.R"))
.RCMA_FUNC_ONLY <- TRUE                                   # ★ admission 스크립트 = 함수만(정적 JSON 재작성 안 함)
source(file.path(PROJ, "02_Infrastructure/portfolio/regime_module_admission.R"))
source(file.path(CD, "backtest_result_contract.R")); source(file.path(CD, "audit_bt_result.R")); source(file.path(CD, "essence_score.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
sr <- function(r){ r<-r[is.finite(r)]; if(sd(r)==0) return(NA); mean(r)/sd(r)*sqrt(12) }
MIN_IS_MONTHS <- 60L; MIN_MODULES <- 3L; RCMA_REFIT_MONTHS <- 12L   # RCMA 멤버십 연 1회 재호출
# ★ FIX (breadth sanity, 2026-06-05): OOS 시작점은 임의(2016 절단)도 무근거(1995)도 아닌,
#   모듈 breadth(그 달 가용 모듈 수)가 충분치 이상인 첫 달로 근거 있게 잡는다.
#   1990~2001 KR 구간은 backfill 모듈 4~7개뿐(thin) → 앙상블 비대표적(MDD·oos_retention 폭주 원인).
#   진단(2026-06-05): breadth≥10 첫 달 = 200203, ≥15 = 200307, full ~78모듈 = 2005-06+.
MIN_BREADTH_OOS <- 10L   # OOS 평가 시작 = 그 달 가용 모듈 ≥ 이 값인 첫 달 (근거: avail_by_m 진단)

# ── ★2026-09-12 (2계층 FR_003 라운드) 최소 파라미터화 — 기본값은 전부 구동작 보존 ───────────
#   왜: 러너가 fr_id 를 "FR_001" 로 못박고 있어 새 리서치 1단위를 돌리면 이전 등재를 덮는다.
#       또 대조군(arm_C)·PIT 스트레스(arm_S)를 같은 러너로 돌리려면 등재를 꺼야 한다.
#   원칙: 하나도 기본값을 바꾸지 않는다(FR_RUN_ID 미설정 = FR_001, 등재 ON, 추가지연 0).
FR_RUN_ID   <- Sys.getenv("FR_RUN_ID", "FR_001")                      # 등재/산출 파일 식별자
FR_REGISTER <- !identical(Sys.getenv("FR_REGISTER", "1"), "0")        # 0 = 레지스트리 등재 생략(대조·스트레스 arm)
FR_ARM_TAG  <- Sys.getenv("FR_ARM_TAG", "")                            # 진단 산출물 라벨
# 국면신호 추가 지연(개월). 0 = 기본(전월말 Category). 1 = lag-1 스트레스(전전월말) — C5 동월누출 판별.
FR_EXTRA_REGIME_LAG <- suppressWarnings(as.integer(Sys.getenv("FR_EXTRA_REGIME_LAG", "0"))); if (is.na(FR_EXTRA_REGIME_LAG)) FR_EXTRA_REGIME_LAG <- 0L
FR_DIAG_DIR <- Sys.getenv("FR_DIAG_DIR", "")                           # 비면 진단 덤프 생략

# 1. 모듈 풀 + 일간 수익 매트릭스 -----------------------------------------------
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
mod_ids <- names(MP$modules)
# RCMA context (active 일간 시계열 1회 로드 — compute_rcma(asof)가 슬라이스). WF 멤버십 = PIT.
RCMA_CTX <- tryCatch(.rcma_load(PROJ), error=function(e){ cat("[RCMA] load 실패:", conditionMessage(e), "\n"); NULL })
rets <- list(); bmref <- NULL; bmref_src <- NA_character_; bmref_n <- 0L
for(sid in mod_ids){
  p <- file.path(PROJ, MP$modules[[sid]]$sim_result_path)
  s <- tryCatch(readRDS(p), error=function(e) NULL); if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  rets[[sid]] <- d
  # ★ FIX (benchmark 절단 방지, 2026-06-05): 모든 모듈의 bm_xts = 동일 KOSPI200 지수(span만 상이).
  #   "첫 모듈" 휴리스틱은 단기 bm(2016~)을 잡아 FR 평가를 60개월로 silent 절단 → *가장 긴* bm_xts 채택.
  if(!is.null(s$bm_xts) && nrow(s$bm_xts) > bmref_n){
    bmref <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
    bmref_n <- nrow(s$bm_xts); bmref_src <- sid }
}
mod_ids <- names(rets)
if(!is.null(bmref)) cat(sprintf("[bm] benchmark source=%s (longest bm_xts) span %s..%s n=%d\n",
  bmref_src, as.character(min(bmref$Date)), as.character(max(bmref$Date)), bmref_n))
# wide daily matrix
RM <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE), lapply(names(rets), function(s){ x<-copy(rets[[s]]); setnames(x,"r",s); x }))
setorder(RM, Date)
# 공통 기간: 월별 ≥MIN_MODULES 모듈 가용
RM[, ym := format(Date,"%Y%m")]
avail_by_m <- RM[, .(navail = sum(sapply(.SD, function(c) any(is.finite(c))))), by=ym, .SDcols=mod_ids]
setorder(avail_by_m, ym)
good_ym <- avail_by_m[navail >= MIN_MODULES, ym]
RM <- RM[ym %in% good_ym]
# ★ breadth gate: OOS 평가는 breadth ≥ MIN_BREADTH_OOS 인 첫 달부터 (근거 있는 시작점). thin 초기구간 배제.
breadth_ok_ym <- avail_by_m[navail >= MIN_BREADTH_OOS, ym]
OOS_START_YM  <- if(length(breadth_ok_ym)) min(breadth_ok_ym) else min(good_ym)
OOS_START_BREADTH <- avail_by_m[ym==OOS_START_YM, navail]
cat(sprintf("[1] modules=%d  daily rows=%d  months=%d (%s..%s)\n", length(mod_ids), nrow(RM), uniqueN(RM$ym), min(RM$ym), max(RM$ym)))
cat(sprintf("[1b] breadth gate: OOS 시작 = %s (그 달 모듈 %d개 ≥ MIN_BREADTH_OOS=%d) — thin 초기구간(4~7모듈) 배제\n", OOS_START_YM, OOS_START_BREADTH, MIN_BREADTH_OOS))

# 2. 월간 regime (t-1 lag) + 월말 인덱스 ---------------------------------------
RG <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]
me <- RM[, .(me_date=max(Date)), by=ym]; setorder(me, me_date)
mreg <- merge(me, RG, by.x="me_date", by.y="Date", all.x=TRUE)
setorder(mreg, me_date)
mreg[, regime_lag := shift(Category, 1L + FR_EXTRA_REGIME_LAG)]       # 어제(전월말) 국면 → 이번달 적용 (+추가지연 = lag 스트레스)
mreg[, sig_cutoff := shift(me_date, 1L + FR_EXTRA_REGIME_LAG)]        # ★C5: 이 배분이 실제로 본 마지막 날짜
mreg[is.na(regime_lag), regime_lag := "NEUTRAL"]
# ── ★C5 오버레이 신호 타이밍 HARD 검사 (pit.md §오버레이 신호 타이밍) ────────────────
#   컷오프(신호가 본 마지막 날) < 홀딩월 첫 거래일 이어야 한다. 홀딩월 = 수익이 벌리는 달 = ym.
local({
  src <- file.path(PROJ, "02_Infrastructure/validation/overlay_pit_guard.R")
  if (!file.exists(src)) stop("[C5] overlay_pit_guard.R 부재 — 관문 없이 국면 오버레이를 돌릴 수 없음")
  source(src, local = TRUE)
  ok <- !is.na(mreg$sig_cutoff)
  ## ym 은 "YYYYMM" — overlay_signal_cutoff 는 "YYYY-MM" 을 기대한다(paste0(ym,"-01")).
  hold_start <- overlay_signal_cutoff(sub("^(\\d{4})(\\d{2})$", "\\1-\\2", mreg$ym[ok]))   # 홀딩월 1일
  if (any(is.na(hold_start))) stop("[C5] 홀딩월 시작일 파싱 실패 — ym 포맷 확인")
  assert_overlay_pit(as.Date(mreg$sig_cutoff[ok]), hold_start, label = "FR regime dispatch")
  cat(sprintf("[C5] assert_overlay_pit PASS — n=%d 월, extra_lag=%d, 최대 컷오프-홀딩월시작 간격 %d일\n",
              sum(ok), FR_EXTRA_REGIME_LAG,
              as.integer(max(hold_start - as.Date(mreg$sig_cutoff[ok])))))
})
# ★ Track1-B proactive dispatch (env FR_REGIME_SOURCE=forecast): contemporaneous regime_lag 대신
#   regime_forecaster의 *다음국면 예측*을 dispatch에 사용(reactive→proactive). 예측 NA 월은 regime_lag fallback.
#   forecaster beats_baseline=TRUE 일 때만 의미(아니면 과적합). baseline(category)은 default — FR_001 불변.
REGIME_SOURCE <- Sys.getenv("FR_REGIME_SOURCE", "category")
mreg[, regime_dispatch := regime_lag]                                # default = contemporaneous (baseline)
if(REGIME_SOURCE == "forecast"){
  fcp <- file.path(PROJ,".cache/regime_forecast_series.parquet")
  if(!file.exists(fcp)) stop("FR_REGIME_SOURCE=forecast 인데 regime_forecast_series.parquet 부재 — regime_forecaster.R 먼저 실행")
  FS <- as.data.table(read_parquet(fcp))
  mreg <- merge(mreg, FS, by="ym", all.x=TRUE)
  mreg[!is.na(forecast_regime), regime_dispatch := forecast_regime]  # 예측 가용 월만 override
  setorder(mreg, me_date)                                            # ★ merge 후 순서 복원 (months 인덱스 정합)
  cat(sprintf("[regime] ★ proactive dispatch: forecast %d/%d 월 override (나머지 category fallback)\n",
              mreg[!is.na(forecast_regime), .N], nrow(mreg)))
} else cat("[regime] dispatch source = category (contemporaneous, baseline)\n")

# 3. anchored walk-forward: 월별 가중(IS-only) → 다음달 적용 -------------------
#    weights는 월초(첫 거래일)에 적용·월중 frozen → Return.portfolio가 monthly rebalance로 합성.
months <- mreg$ym
W_rows <- list(); wlog <- list()           # W_rows: rebalance-date별 모듈 weight (Return.portfolio 입력)
diaglog <- list(); admlog <- list()        # ★MC1/MC2 진단 로그
## 방어형 경로로 편입된 모듈 id (module_performance.json 의 admission_route 라벨 — 자체 판정 아님)
DEFENSIVE_IDS <- names(Filter(function(x) identical(as.character(x$admission_route %||% ""),
                                                    "defensive_specialist"), MP$modules))
cat(sprintf("[pool] 풀 %d · 방어형 경로 편입 %d · grade_floor %d · legacy %d\n",
            length(MP$modules), length(DEFENSIVE_IDS),
            sum(vapply(MP$modules, function(x) identical(as.character(x$admission_route %||% ""), "grade_floor"), logical(1))),
            length(MP$modules) - length(DEFENSIVE_IDS) -
              sum(vapply(MP$modules, function(x) identical(as.character(x$admission_route %||% ""), "grade_floor"), logical(1)))))
adm_cache <- NULL; adm_cache_asof <- NULL   # WF RCMA 멤버십 캐시(연 1회 갱신)
months_used <- character(0)
for(i in seq_along(months)){
  if(i <= MIN_IS_MONTHS) next
  m <- months[i]; reg_now <- mreg$regime_dispatch[i]
  if(m < OOS_START_YM) next                                      # ★ breadth gate: 대표성 충분한 첫 달 전 구간은 OOS 미평가
  is_end <- mreg$me_date[i-1]                                    # IS = 이전월말까지
  IS <- RM[Date <= is_end]
  # ── ★ FIX #2: WF RCMA — asof=직전 월말, 연 1회 재호출 → admitted_by_regime(시간가변) ──
  refit_now <- is.null(adm_cache) || is.null(adm_cache_asof) ||
               as.integer((as.Date(is_end)-as.Date(adm_cache_asof))) >= (RCMA_REFIT_MONTHS*30L)
  if(!is.null(RCMA_CTX) && refit_now){
    adm_cache <- tryCatch(compute_rcma(is_end, RCMA_CTX, PROJ), error=function(e){ cat("[RCMA wf] asof",as.character(is_end),"실패:",conditionMessage(e),"\n"); NULL })
    adm_cache_asof <- is_end
  }
  admitted_by_regime <- if(!is.null(adm_cache)) adm_cache$admitted_by_regime else NULL
  admitted_union <- if(!is.null(adm_cache)) adm_cache$admitted_modules else character(0)

  # IS에서 국면조건부 IR + vol (실측, expanding)
  ISr <- merge(IS, RG, by="Date", all.x=TRUE); setorder(ISr, Date); ISr[, reg_lag := shift(Category,1L)]
  avail <- mod_ids[sapply(mod_ids, function(s) sum(is.finite(ISr[[s]])) >= 250)]   # 최소 1년
  # ★ FIX #2: admitted union으로 풀 제한(≥MIN_MODULES일 때만 — cold-start 정직: 부족 시 broad pool)
  if(length(admitted_union) >= MIN_MODULES){ pool_u <- intersect(avail, admitted_union); if(length(pool_u) >= MIN_MODULES) avail <- pool_u }
  # 이 국면 admitted 모듈로 추가 제한 (≥MIN_MODULES일 때만; 아니면 specialist 부재 → broad pool fallback)
  adm_L <- if(!is.null(admitted_by_regime)) admitted_by_regime[[reg_now]] else NULL
  if(!is.null(adm_L)){ pool_L <- intersect(avail, adm_L); if(length(pool_L) >= MIN_MODULES) avail <- pool_L }
  if(length(avail) < MIN_MODULES) next
  regime_ir <- setNames(sapply(avail, function(s){ x<-ISr[reg_lag==reg_now][[s]]; x<-x[is.finite(x)]; if(length(x)<20||sd(x)==0) 0 else mean(x)/sd(x)*sqrt(252) }), avail)
  n_reg     <- setNames(sapply(avail, function(s) sum(is.finite(ISr[reg_lag==reg_now][[s]]))/21), avail)
  vols      <- setNames(sapply(avail, function(s){ x<-ISr[[s]]; x<-x[is.finite(x)]; sd(tail(x,252)) }), avail)
  w <- suppressWarnings(compute_regime_module_weights(regime_ir, vols, n_reg))
  wlog[[m]] <- data.table(ym=m, regime=reg_now, t(w))
  ## ★MC1/MC2 조작 확인 로그(2026-09-12): 처치가 어느 채널로 전달됐는지 사후에 재도출 가능하게.
  ##   R54 교훈 — 헤드라인만 보고 '국면층 기각' 이라 쓸 뻔했으나 그 셀엔 처치가 전달된 적이 없었다.
  .fd <- fr_weight_expressiveness(w)
  diaglog[[m]] <- data.table(ym = m, regime = reg_now,
    n_avail = length(avail), n_adm_union = length(admitted_union),
    n_adm_regime = if (is.null(adm_L)) NA_integer_ else length(adm_L),
    retention = .fd$retention %||% NA_real_, intended_dev = .fd$intended_dev %||% NA_real_,
    actual_dev = .fd$actual_dev %||% NA_real_, dev_from_ew = .fd$dev_from_ew %||% NA_real_,
    w_max = max(w), w_defensive = sum(w[intersect(names(w), DEFENSIVE_IDS)]),
    n_defensive_avail = length(intersect(avail, DEFENSIVE_IDS)))
  admlog[[m]] <- list(ym = m, regime = reg_now, admitted = as.character(avail))
  months_used <- c(months_used, m)
  # rebalance 행: 이번달 첫 거래일에 weight 적용 (월중 frozen은 Return.portfolio가 처리)
  rb_date <- RM[ym==m, min(Date)]
  W_rows[[m]] <- data.table(Date=rb_date, t(w))
}
if(length(W_rows) < 12) stop("walk-forward 월 부족 — RCMA/데이터 점검")

# 4. ★ Return.portfolio 합성 (자체합성 폐기) -----------------------------------
#    asset = 모듈, R = 일간 모듈수익(OOS 구간), weights = rebalance행(월초). 월중 drift+monthly rebalance.
oos_ym <- months_used
RM_oos <- RM[ym %in% oos_ym]; setorder(RM_oos, Date)
# weights wide (모든 사용 모듈 union 컬럼). 미보유 모듈은 0.
all_used_mods <- sort(unique(unlist(lapply(W_rows, function(d) setdiff(names(d),"Date")))))
Wdt <- rbindlist(lapply(W_rows, function(d){ x<-copy(d); miss<-setdiff(all_used_mods, names(x)); for(c in miss) x[, (c):=0]; x[, c("Date", all_used_mods), with=FALSE] }), use.names=TRUE)
setorder(Wdt, Date)
# R 매트릭스: 동일 모듈 컬럼, OOS 일자. NA(모듈 미존재 시점)는 0 — 해당 시점 weight도 0이라 영향 없음.
Rdt <- RM_oos[, c("Date", all_used_mods), with=FALSE]
for(c in all_used_mods) Rdt[!is.finite(get(c)), (c):=0]
R_xts <- xts(as.matrix(Rdt[, ..all_used_mods]), order.by=Rdt$Date)
W_xts <- xts(as.matrix(Wdt[, ..all_used_mods]), order.by=Wdt$Date)
# Return.portfolio: weights 각 행=rebalance, 다음 rebalance까지 drift 후 재설정(=monthly rebalance, 월중 frozen).
rp <- Return.portfolio(R = R_xts, weights = W_xts, rebalance_on = NA, verbose = TRUE)
port_gross <- rp$returns                                  # 일간 gross 앙상블 수익 (표준함수 합성)

# 15bps 국면전환 turnover 비용: Return.portfolio가 산정한 BOP/EOP weight 전이로 turnover 계산 후 리밸일 차감.
#   turnover_t = Σ|target_w(BOP_t) − drifted_w(EOP_{t-1})|. BOP≠직전 EOP 인 날 = rebalance(초기배분 포함).
#   손Σ 아님 — Return.portfolio가 산정한 weight 벡터의 차이(정직). 비용은 known cost 차감.
bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
bop_m <- as.matrix(bop); eop_m <- as.matrix(eop); idx <- as.Date(index(bop))
to_by_date <- data.table(Date=idx, to=0)
prev_eop <- rep(0, ncol(bop_m))                           # 시작 = 현금(0). 첫 BOP=초기배분 → 첫 리밸 비용 정직 반영.
for(j in seq_len(nrow(bop_m))){
  tgt <- bop_m[j, ]; tgt[!is.finite(tgt)] <- 0
  diffw <- sum(abs(tgt - prev_eop), na.rm=TRUE)
  if(diffw > 1e-8) to_by_date[j, to := diffw]             # BOP≠직전 EOP → rebalance 발생
  prev_eop <- eop_m[j, ]; prev_eop[!is.finite(prev_eop)] <- 0
}
port_dt <- data.table(Date=as.Date(index(port_gross)), r_gross=as.numeric(port_gross))
port_dt <- merge(port_dt, to_by_date, by="Date", all.x=TRUE); port_dt[is.na(to), to:=0]
port_dt[, r_net := r_gross - to*(15/1e4)]                 # 비용 차감(정직) — 자체 *구성*이 아니라 known cost 차감
setorder(port_dt, Date)
cat(sprintf("[3] ensemble OOS daily=%d months=%d (%s..%s) | 총 turnover(연환산 proxy)=%.2f\n",
  nrow(port_dt), uniqueN(format(port_dt$Date,"%Y%m")), as.character(min(port_dt$Date)), as.character(max(port_dt$Date)),
  sum(port_dt$to)/(nrow(port_dt)/252)))

# 5. 계약 측정 (실측-only, 표준함수 경유) --------------------------------------
#    일간 net 시계열을 strategy_xts로 전달 → build_bt_result(frequency="monthly")가 apply.monthly로 월집계.
ED_xts  <- xts(port_dt$r_net,   order.by=port_dt$Date)
EDg_xts <- xts(port_dt$r_gross, order.by=port_dt$Date)
if(is.null(bmref)) stop("benchmark 부재")
bmref_oos <- bmref[Date %in% port_dt$Date]; setorder(bmref_oos, Date)
bm_xts <- xts(bmref_oos$bm, order.by=bmref_oos$Date)
# ★ FIX (CAGR/Calmar 정합, 2026-06-05): frequency="monthly" 선언 → DAILY_NAV_DT도 *월간* 그래뉼래리티여야 함.
#   contract build_metrics의 CAGR = (final/init)^(annualization_factor/length(nav)) − 1. 일간 NAV(7336행)에
#   월간 annualization_factor=12를 적용하면 지수가 ~21배 과소(12/7336) → CAGR 0.6%로 붕괴(실제 ~16%).
#   해결: 일간 net/gross 수익을 표준함수 apply.monthly(Return.cumulative)로 월집계 후 월간 NAV path 구성
#   (NAV는 수익률 *구성*이 아니라 net 월수익 시계열의 누적가치 — answer-principles 정합). length(nav)≈n_months.
mret_net   <- apply.monthly(ED_xts,  Return.cumulative)
mret_gross <- apply.monthly(EDg_xts, Return.cumulative)
mdates    <- as.Date(index(mret_net))
nav_net   <- as.numeric(cumprod(1 + as.numeric(mret_net)))    # 월간 NAV path (월수익 누적가치)
nav_gross <- as.numeric(cumprod(1 + as.numeric(mret_gross)))
sim_result <- list(
  DAILY_NAV_DT  = data.table(Date=mdates, NAV=nav_net, NAV_gross=nav_gross),  # ★ 월간 NAV (frequency 정합)
  strategy_xts  = ED_xts, bm_xts = bm_xts,                                    # strategy_xts/bm_xts는 일간 — contract가 apply.monthly로 집계
  HOLDINGS_LOG  = list(), PORTFOLIO_LOG = data.table(Exec_Date=as.Date(Wdt$Date)))  # ★ rb_dates 미정의 fix: rebalance 날짜 = W_rows 집계행(Wdt)의 Date
FR_ID    <- if(REGIME_SOURCE=="forecast") paste0(FR_RUN_ID, "_fc") else FR_RUN_ID
if (nzchar(FR_ARM_TAG)) FR_ID <- paste0(FR_ID, "_", FR_ARM_TAG)
OUT_JSON <- paste0(FR_ID, "_result.json"); OUT_RDS <- paste0(FR_ID, "_bt_result.rds")
spec <- list(strategy_name=paste0(FR_ID, if(REGIME_SOURCE=="forecast") "_fc_proactive_rotation" else "_regime_rotation"),
             signal="regime-conditional module rotation",
             module_pool=all_used_mods,
             regime_source=if(REGIME_SOURCE=="forecast") "regime_forecaster predicted-next-regime (proactive, PIT trailing-only)" else "unified_regime_signal_daily Category (t-1)",
             weighting="module_dispatcher rp+IR shrink (λ/τ/k0 fixed); Return.portfolio monthly rebalance",
             rebalance="monthly",
             lookahead_prevention="regime t-1 lag; module frozen; IS-only weights; walk-forward RCMA admission (compute_rcma asof=prior month-end, annual refit); Return.portfolio (no self-synthesis)")
bt <- build_bt_result(sim_result, spec, run_id=FR_ID, strategy_id=FR_ID, strategy_version="v2",
        benchmark_id="KOSPI200", benchmark_name="KOSPI 200", transaction_cost_bps=15, slippage_bps=0,
        risk_free_rate=0, frequency="monthly", annualization_factor=12, universe_id="KR_modules",
        code_version="run_wf_ensemble_v3_breadthgate_oosguard", created_by_agent="dispatch-orchestrator")
bt <- audit_bt_result(bt)
# n_trials: 앙상블 = 다중검정 (모듈조합 + hyper) — 보수적 상향
N_TRIALS <- length(all_used_mods) + 5L
es <- essence_score(bt, n_trials_cumulative = N_TRIALS)

# 6. OOS retention + placebo (월간 active 시계열 = 계약 period_returns/benchmark_returns) ----
PRm <- as.data.table(bt$period_returns)[, .(date, ret_net)]
BRm <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
MM  <- merge(PRm, BRm, by="date"); setorder(MM, date)
n<-nrow(MM); k<-floor(n*0.65); shp<-function(x){x<-x[is.finite(x)];if(length(x)<2||sd(x)==0)return(NA);mean(x)/sd(x)*sqrt(12)}
act <- MM$ret_net - MM$benchmark_ret
# ★ FIX (oos_retention 폭주 가드, 2026-06-05): IS active Sharpe(분모) abs<0.1면 비율 불안정 → null/"unstable".
#   essence_score는 동일 65/35 분할 + is_ir>0.05 가드로 oos_retention 산출 → 그 값을 권위로 채택(이중소스 불일치 제거).
is_sr_active <- shp(act[1:k]); oos_sr_active <- shp(act[(k+1):n])
OOS_RET_UNSTABLE_THRESH <- 0.1
oos_local <- if(is.finite(is_sr_active) && abs(is_sr_active) >= OOS_RET_UNSTABLE_THRESH && is.finite(oos_sr_active)) oos_sr_active/is_sr_active else NA_real_
# 권위 = essence_score의 oos_retention(가드 내장). 미산출(NA) 시 local 가드값으로 보강, 둘 다 불안정이면 NA.
oos_ret <- es$essence$oos_retention %||% oos_local
oos_ret_label <- if(is.finite(oos_ret)) "ok" else "unstable"
# placebo proxy: 동일 OOS 구간 EW(equal-weight) 앙상블 SR (Return.portfolio, 월말 리밸). 손합성 아님.
ew_rb <- RM_oos[, .(Date=min(Date)), by=ym]$Date
ew_W  <- data.table(Date=ew_rb)
for(c in all_used_mods) ew_W[, (c) := 1/length(all_used_mods)]
ewW_xts <- xts(as.matrix(ew_W[, ..all_used_mods]), order.by=ew_W$Date)
ew_rp <- tryCatch(Return.portfolio(R = R_xts, weights = ewW_xts, rebalance_on = NA), error=function(e) NULL)
ew_sr <- if(is.null(ew_rp)) NA_real_ else {
  ewd <- data.table(Date=as.Date(index(ew_rp)), r=as.numeric(ew_rp)); ewd[, ym:=format(Date,"%Y%m")]
  ewm <- apply.monthly(xts(ewd$r, order.by=ewd$Date), Return.cumulative); sr(as.numeric(ewm)) }

dir.create(file.path(PROJ,"04_Research/factor_rotation/output"), showWarnings=FALSE, recursive=TRUE)
# ★ A/B 출력 게이트: forecast 변형·대조 arm 은 별도 파일·등재 생략(baseline 보존). FR_ID/OUT_* 는 위에서 확정.
fr <- list(fr_id=FR_ID, grade=es$grade, metric_type=es$metric_type, essence=es$essence,
  n_modules=length(all_used_mods), module_pool=all_used_mods, n_months=n, n_trials_cumulative=N_TRIALS,
  oos_retention=if(is.finite(oos_ret)) round(oos_ret,3) else NA_real_, oos_retention_status=oos_ret_label,
  oos_is_active_sharpe=round(is_sr_active,3), oos_oos_active_sharpe=round(oos_sr_active,3),
  ew_baseline_SR=round(ew_sr,3),
  net_sharpe=es$essence$net_sharpe, port_t=es$essence$portfolio_alpha_t_nw_lag3, dsr=es$essence$dsr,
  oos_start_ym=OOS_START_YM, oos_start_breadth=OOS_START_BREADTH, min_breadth_oos=MIN_BREADTH_OOS,
  breadth_rationale="OOS 시작점 = 가용 모듈 breadth ≥ MIN_BREADTH_OOS 인 첫 달(avail_by_m 진단). thin 초기구간(1990~2001 4~7모듈) 배제 — 임의 2016 절단·무근거 1995 시작 모두 회피.",
  code_version="run_wf_ensemble_v3_breadthgate_oosguard",
  lookahead_prevention=spec$lookahead_prevention,
  rcma_mode="walk-forward (compute_rcma asof=prior month-end, annual refit)",
  return_synthesis="PerformanceAnalytics::Return.portfolio (monthly rebalance; no prod/cumprod/Sigma-w self-synthesis)",
  date_range=c(as.character(min(MM$date)), as.character(max(MM$date))))
write_json(fr, file.path(PROJ,"04_Research/factor_rotation/output", OUT_JSON), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
saveRDS(bt, file.path(PROJ,"04_Research/factor_rotation/output", OUT_RDS))
# FR 운용체계 레지스트리 등재 (실측-only; metric_type=backtested 아니면 거부). forecast 변형은 A/B 실험 → 등재 생략.
if(REGIME_SOURCE != "forecast" && FR_REGISTER){
  tryCatch({ source(file.path(CD, "factor_rotation_registry.R"))
    register_fr_result(fr, regime_engine_version=sprintf("unified_regime_signal_daily Category(t-%d) + walk-forward RCMA", 1L+FR_EXTRA_REGIME_LAG)) },
    error=function(e) cat("[run_wf_ensemble] FR registry 생략:", conditionMessage(e), "\n"))
} else cat("[run_wf_ensemble] 등재 생략 —", if(REGIME_SOURCE=="forecast") "forecast A/B 변형" else "FR_REGISTER=0 (대조/스트레스 arm)", "\n")

# ── ★진단 덤프 (MC1/MC2/MC3 재도출용). FR_DIAG_DIR 미설정이면 생략 ─────────────────
if (nzchar(FR_DIAG_DIR)) {
  dir.create(FR_DIAG_DIR, showWarnings=FALSE, recursive=TRUE)
  DG <- rbindlist(diaglog, fill=TRUE)
  fwrite(DG, file.path(FR_DIAG_DIR, paste0(FR_ID, "_dispatch_diag.csv")))
  saveRDS(admlog, file.path(FR_DIAG_DIR, paste0(FR_ID, "_admitted_by_month.rds")))
  ## 국면별 admitted 집합 Jaccard (MC1) — 같은 해 안에서 국면만 다른 달끼리 비교되도록 연도 통제.
  .jac <- function(a,b){ u<-length(union(a,b)); if(u==0) NA_real_ else length(intersect(a,b))/u }
  am <- rbindlist(lapply(admlog, function(x) data.table(ym=x$ym, regime=x$regime, k=paste(sort(x$admitted), collapse="|"))))
  am[, yr := substr(ym,1,4)]
  pairs <- list()
  for (y in unique(am$yr)) { s <- am[yr==y]; if (uniqueN(s$regime) < 2L) next
    rg <- unique(s$regime)
    for (i in seq_along(rg)) for (j in seq_along(rg)) if (i<j) {
      a <- strsplit(s[regime==rg[i]][1]$k, "\\|")[[1]]; b <- strsplit(s[regime==rg[j]][1]$k, "\\|")[[1]]
      pairs[[length(pairs)+1]] <- data.table(yr=y, r1=rg[i], r2=rg[j], jaccard=.jac(a,b)) } }
  JP <- if (length(pairs)) rbindlist(pairs) else data.table()
  if (nrow(JP)) fwrite(JP, file.path(FR_DIAG_DIR, paste0(FR_ID, "_regime_jaccard.csv")))
  mc <- list(fr_id=FR_ID, arm=FR_ARM_TAG, extra_regime_lag=FR_EXTRA_REGIME_LAG,
    n_pool=length(MP$modules), n_defensive_pool=length(DEFENSIVE_IDS),
    MC1_membership=list(n_pairs=nrow(JP), jaccard_median=if(nrow(JP)) round(median(JP$jaccard, na.rm=TRUE),4) else NA,
                        jaccard_min=if(nrow(JP)) round(min(JP$jaccard, na.rm=TRUE),4) else NA,
                        delivered=if(nrow(JP)) (median(JP$jaccard, na.rm=TRUE) < 0.9) else NA),
    MC2_weights=list(retention_median=round(median(DG$retention, na.rm=TRUE),4),
                     retention_p90=round(as.numeric(quantile(DG$retention, .9, na.rm=TRUE)),4),
                     n_avail_median=median(DG$n_avail, na.rm=TRUE),
                     delivered=isTRUE(median(DG$retention, na.rm=TRUE) >= 0.25)),
    MC3_defensive=as.list(DG[, .(w_def_mean=round(mean(w_defensive, na.rm=TRUE),4),
                                 n_months=.N), by=regime]))
  write_json(mc, file.path(FR_DIAG_DIR, paste0(FR_ID, "_manipulation_check.json")), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
  cat(sprintf("[MC] retention median=%.3f (n_avail median=%.0f) · Jaccard median=%s · 방어형 비중 국면별 기록 → %s\n",
              median(DG$retention, na.rm=TRUE), median(DG$n_avail, na.rm=TRUE),
              if(nrow(JP)) sprintf("%.3f", median(JP$jaccard, na.rm=TRUE)) else "NA", FR_DIAG_DIR))
}
# ── FR L-code 발행 (2026-07-04 G-mode-wiring — FR 모드 emit 1지점, 레지스트리 등재 직후) ──
#   es 객체 스코프 내 실측치만 전달(metric_type=backtested). fail-soft — emit 실패가 러너를 죽이지 않음.
#   forecast A/B 변형도 strategy_id=FR_ID로 구분 적립 (실험 교훈도 지식 — 레지스트리 미등재와 별개).
tryCatch({
  source(file.path(PROJ,"02_Infrastructure/axiom/lcode_emit.R"))
  .fr_edge_ew <- if(is.finite(es$essence$net_sharpe%||%NA) && is.finite(ew_sr)) (es$essence$net_sharpe - ew_sr) else NA_real_
  # falsification 구조체 [{test,result,effect_retained}] — 이미 산출된 반증형 검증의 전달만 (신규 계산 금지)
  .fr_fals <- list()
  if(is.finite(oos_ret))
    .fr_fals[[length(.fr_fals)+1]] <- list(test="OOS retention (essence 3-split, 과적합 반증)",
      result=if(oos_ret >= 0.5) "survived" else "falsified",   # §3 하한 0.5 (measurement-graduation — 창작 아님)
      effect_retained=round(oos_ret,3), detail=sprintf("retention %.3f (gate 0.7, 하한 0.5)", oos_ret))
  if(is.finite(.fr_edge_ew))
    .fr_fals[[length(.fr_fals)+1]] <- list(test="EW baseline 대비 edge (placebo proxy)",
      result="diagnostic", effect_retained=NA,
      detail=sprintf("net_SR %.3f vs EW %.3f (edge %+.3f) — 유의검정 아님(진단)", es$essence$net_sharpe%||%NA, ew_sr, .fr_edge_ew))
  emit_fr_lcode(
    strategy_id = FR_ID, grade = es$grade,
    lesson_text = sprintf(
      "%s regime rotation 앙상블 실측(essence %s): net_SR=%.3f PORT_t(NW lag-3)=%.2f DSR=%s Calmar=%.2f CAGR=%.1f%% MDD=%.1f%% | oos_retention=%s | admitted pool %d모듈(%s) | edge_vs_ew=%s (EW baseline SR %.3f).",
      FR_ID, es$grade, es$essence$net_sharpe%||%NA, es$essence$portfolio_alpha_t_nw_lag3%||%NA,
      as.character(round(es$essence$dsr,3)), es$essence$calmar%||%NA,
      (es$essence$cagr%||%NA)*100, (es$essence$mdd%||%NA)*100,
      if(is.finite(oos_ret)) sprintf("%.3f", oos_ret) else "unstable",
      length(all_used_mods), paste(head(all_used_mods,8), collapse=","),
      if(is.finite(.fr_edge_ew)) sprintf("%+.3f", .fr_edge_ew) else "NA", ew_sr),
    track = "factor_rotation",
    construction_type = "regime_rotation",
    mechanism_hypothesis = "국면조건부 모듈 배분(RCMA admitted union + rp/IR shrink dispatcher) — 모듈별 약점 국면 회피로 앙상블 위험조정수익 개선 가설",
    core_reference = "run_wf_ensemble.R (walk-forward RCMA + Return.portfolio)",
    # emit v2 1급 인자 (승격축)
    portfolio_alpha_t = es$essence$portfolio_alpha_t_nw_lag3%||%NA,
    oos_retention = if(is.finite(oos_ret)) round(oos_ret,3) else NULL,
    falsification_attempts = if(length(.fr_fals)) .fr_fals else NULL,
    selection_type = "chain",   # 단일 config 러너(baseline/forecast A/B) — sweep argmax-pick 아님 (§3)
    metrics = list(
      cagr_pct = round((es$essence$cagr%||%NA)*100,2), sharpe = es$essence$net_sharpe%||%NA,
      mdd_pct = round(abs(es$essence$mdd%||%NA)*100,2),
      calmar = es$essence$calmar%||%NA, dsr = es$essence$dsr%||%NA,
      ew_baseline_sr = round(ew_sr,3), edge_vs_ew = if(is.finite(.fr_edge_ew)) round(.fr_edge_ew,3) else NA_real_,
      n_modules = length(all_used_mods), n_trials = N_TRIALS))
}, error=function(e) cat("[run_wf_ensemble] FR L-code emit 생략(fail-soft):", conditionMessage(e), "\n"))

cat(sprintf("\n==== %s (regime rotation 앙상블) — 실측 [v3: Return.portfolio + WF RCMA + breadth gate + oos guard] ====\n", FR_ID))
cat(sprintf("grade=%s  net_Sharpe=%.3f  PORT_t=%.3f  DSR=%s  Calmar=%.2f  CAGR=%.1f%%  MDD=%.1f%%\n",
  es$grade, es$essence$net_sharpe%||%NA, es$essence$portfolio_alpha_t_nw_lag3%||%NA,
  as.character(round(es$essence$dsr,3)), es$essence$calmar%||%NA, (es$essence$cagr%||%NA)*100, (es$essence$mdd%||%NA)*100))
cat(sprintf("OOS_retention=%s (gate 0.7; IS active SR=%.3f)  |  EW baseline SR=%.3f  |  n_modules=%d  |  n_trials=%d\n",
  if(is.finite(oos_ret)) sprintf("%.3f", oos_ret) else paste0("unstable(", oos_ret_label, ")"), is_sr_active%||%NA, ew_sr, length(all_used_mods), N_TRIALS))
cat(sprintf("OOS window: %s start (breadth %d ≥ %d) | n_months=%d (%s..%s)\n",
  OOS_START_YM, OOS_START_BREADTH, MIN_BREADTH_OOS, n, as.character(min(MM$date)), as.character(max(MM$date))))
cat(sprintf("vs SR 2.5 target: %s\n", if(is.finite(es$essence$net_sharpe)&&es$essence$net_sharpe>=2.5) "달성" else sprintf("미달 (gap %.2f) — 정직 보고", 2.5-(es$essence$net_sharpe%||%0))))
