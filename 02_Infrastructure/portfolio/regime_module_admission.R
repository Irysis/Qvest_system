#!/usr/bin/env Rscript
# =============================================================================
# regime_module_admission.R — Factor Rotation Mode: RCMA (국면조건부 모듈 admission).
# ★ overall 등급이 아니라 *국면조건부 성과*로 (module × regime) 셀 admission 판정.
#   양방향 대칭: 방어형(CRISIS specialist) + 공격형(RISK_ON/확장 specialist) 모두 차용.
#   F-overall이어도 특정 국면서 강하면 그 국면 sleeve로 — 약점 국면은 dispatcher가 ~0 처리.
#
# ★★ WALK-FORWARD RCMA (도훈 a안, 2026-06-05 fix #2):
#   admission = point-in-time. `compute_rcma(asof_date)`는 Date ≤ asof_date 데이터만으로 판정.
#   run_wf_ensemble가 연 1회 asof=직전 기간말로 재호출 → 멤버십이 시간가변(미래정보 無).
#   c3(IS·OOS 부호)는 고정 2012 cut 폐기 → asof 창 *내부* 65/35 분할로 대체(이제 전체가 WF라 자연 OOS).
#   정적 06_Registry/module_regime_admission.json은 *진단용*(asof=max date)으로 남김 — 실측 권위는 WF 함수.
#
# 6기준 (m,L): ① regime_IR≥0.5 OR regime-L 상위⅓  ② n_months≥12 floor  ③ asof창 IS·OOS sign+(둘 다 +)
#             ④ |t|=|IR·√(n_m/12)|≥2  ⑤ 경제논리(role/regime 휴리스틱+보류)  ⑥ 한계기여(>median, advisory)
# admitted = ①∧②∧③∧④ (hard). ⑤ 플래그, ⑥ advisory.
# ★ C2 (2026-06-10 도훈 mandate, rare_mode flag — 기본 OFF, A/B 통과 후 활성):
#   희소국면(base rate<10%: CRISIS·RISK_OFF) 셀 한정 ②n≥6·④t≥1.5 완화 OR stress-pool 합산 t≥2 대체경로.
#   두 경로 모두 ⑤ strict(review_pending 불가) 의무. dispatcher shrink n/(n+36)+w_cap이 사이징 방어.
# PIT: regime t-1 lag. 실측-only. 모듈 frozen(소비).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
if (!exists("PROJ")) PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
if (!exists("%||%")) `%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
ANN <- 252
ir_ann <- function(a, annf=ANN){ a<-a[is.finite(a)]; if(length(a) < (if(annf<=12) 8L else 20L) || sd(a)==0) return(NA_real_); mean(a)/sd(a)*sqrt(annf) }

# ── thresholds (합격선) ──
# MIN_MONTHS = 12 floor (희소 국면 CRISIS/CAUTION는 36월-in-regime이 비현실 — 방어형 specialist 차단).
# 표본-significance는 ④ t = IR·√(n_m/12) ≥ 2 가 담당(소표본일수록 더 높은 IR 요구). n≥36 = high_conf 플래그.
IR_FLOOR <- 0.5; MIN_MONTHS <- 12; T_MIN <- 2.0; HIGH_CONF_MONTHS <- 36
# ── C2 소표본 셀 완화 경로 v2.1 (2026-06-10 — calibration 백로그 C2, A/B 1차 진단 반영 재설계) ──
# 긴장: ②n≥12 × ④t≥2 곱 → n=12 셀에 IR≥2.0 요구 = 소표본 specialist 셀 수학적 차단.
# ★ v2.0(기각)의 두 결함 — 1차 A/B(2026-06-10, FR_001_c2ab) 실측 진단:
#   ① rare를 *국면 base rate*(<10%)로 정의 → CRISIS(실측 16.7%)가 비껴감. 차단의 실변수는
#      국면 희소성이 아니라 **셀-레벨 n_months**(모듈 이력 × 국면 겹침 — 예: valearn CRISIS n=7).
#   ② rationale-strict를 legacy-통과 셀에 소급 적용 → 무고한 강셀 제거(STR_1622 CAUTION n=33m
#      IR 1.27 t 2.12 — 전 asof 유일 diff = ensemble SR −0.043/PORT_t −0.375 전손 원인).
# v2.1 = **순수 완화**: legacy 판정 불변(소급 조임 금지). rare 셀 = 위기군 국면(STRESS_POOL) ∧ n<12.
#   신규 입장 경로만 추가: 직접(n≥6·t≥1.5) OR stress-pool 합산 t≥2 — 두 경로 모두 ⑤ strict 의무.
# ★ 활성화 게이트: rare_mode 기본 OFF — run_wf_ensemble A/B(전후 ensemble OOS 비악화) 통과 후 ON (도훈 confirm).
RARE_MIN_MONTHS <- 6; RARE_T_MIN <- 1.5
STRESS_POOL <- c("CRISIS", "RISK_OFF", "CAUTION")

# ── 모듈 per-regime active 일간 시계열 로드 (한 번만; asof는 함수에서 슬라이스) ──────
# AL[[sid]] = data.table(Date, a=active daily, regime=t-1 lag). 무겁지 않게 캐시.
.rcma_load <- function(proj = PROJ) {
  MP <- fromJSON(file.path(proj,"06_Registry/module_performance.json"), simplifyVector=FALSE)
  mod_ids <- names(MP$modules)
  RG <- as.data.table(read_parquet(file.path(proj,".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]
  setorder(RG,Date); RG[, regime:=shift(Category,1L)]; RG <- RG[!is.na(regime), .(Date,regime)]
  AL <- list(); FREQ <- list()
  for(sid in mod_ids){
    p <- file.path(proj, MP$modules[[sid]]$sim_result_path)
    s <- tryCatch(readRDS(p), error=function(e) NULL); if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
    fq <- MP$modules[[sid]]$freq %||% s$freq %||% "daily"      # ★ freq-aware (월간 DPL 등 비-일간)
    d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
    bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
    if(!is.null(bm)) d<-merge(d,bm,by="Date",all.x=TRUE) else d[,bm:=0]
    d[, a := r - fifelse(is.finite(bm),bm,0)]
    if(identical(fq,"monthly")){ setkey(RG,Date); dd<-d[,.(Date,a)]; setkey(dd,Date); d <- RG[dd, roll=TRUE][!is.na(regime)]
    } else d <- merge(d[,.(Date,a)], RG, by="Date")
    if(nrow(d) >= (if(identical(fq,"monthly")) 60L else 250L)){ AL[[sid]] <- d; FREQ[[sid]] <- fq }
  }
  regimes <- unlist(MP$regimes) %||% c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
  # C2: 국면 base rate (일수 비중) — rare 판정용 (rare = share < RARE_SHARE)
  sh <- RG[, .N, by = regime]; regime_share <- setNames(sh$N / sum(sh$N), sh$regime)
  list(MP = MP, AL = AL, FREQ = FREQ, mod_ids = names(AL), regimes = regimes, regime_share = regime_share)
}

# ── ★ compute_rcma(asof_date): point-in-time admission (Date ≤ asof_date 만 사용) ─────
#   반환: list(CELL=data.table(셀 진단+판정), admitted_by_regime=list(L->module ids),
#              admitted_modules, pool_oos_rho, asof=asof_date, n_modules)
#   c3(IS·OOS sign): asof 창 *내부* 시간순 65/35 분할(고정 2012 cut 폐기).
compute_rcma <- function(asof_date, ctx = NULL, proj = PROJ,
                         rare_mode = isTRUE(as.logical(Sys.getenv("RCMA_RARE_MODE", "FALSE")))) {
  if (is.null(ctx)) ctx <- .rcma_load(proj)
  AL <- ctx$AL; mod_ids <- ctx$mod_ids; regimes <- ctx$regimes; MP <- ctx$MP; FREQ <- ctx$FREQ %||% list()
  asof_date <- as.Date(asof_date)

  cells <- list(); pool_t_vec <- c()
  for(sid in mod_ids){
    d <- AL[[sid]][Date <= asof_date]                       # ★ PIT: asof 이하만
    fq <- FREQ[[sid]] %||% "daily"; annf <- if(identical(fq,"monthly")) 12 else 252
    mdiv <- if(identical(fq,"monthly")) 1L else 21L; split_min <- if(identical(fq,"monthly")) 16L else 40L
    if(nrow(d) < (if(identical(fq,"monthly")) 60L else 250L)) next   # cold-start: 데이터 부족 모듈 skip
    # C2 stress-pool 합산 증거 (모듈 단위, asof-sliced): CRISIS∪RISK_OFF∪CAUTION 합산 t
    ps <- d[regime %in% STRESS_POOL]
    pool_ir <- ir_ann(ps$a, annf); pool_nm <- nrow(ps)/mdiv
    pool_t_vec[sid] <- if (is.finite(pool_ir)) pool_ir * sqrt(pool_nm/12) else NA_real_
    for(L in regimes){ sub <- d[regime==L]; nm <- nrow(sub)/mdiv
      full_ir <- ir_ann(sub$a, annf)
      # asof 창 내부 65/35 시간순 분할 (자연 OOS — 고정 2012 cut 폐기)
      if(nrow(sub) >= split_min){
        setorder(sub, Date); kk <- floor(nrow(sub)*0.65)
        is_ir  <- ir_ann(sub$a[1:kk], annf); oos_ir <- ir_ann(sub$a[(kk+1):nrow(sub)], annf)
      } else { is_ir <- NA_real_; oos_ir <- NA_real_ }
      tstat <- if(is.finite(full_ir)) full_ir*sqrt(nm/12) else NA_real_
      cells[[paste(sid,L)]] <- data.table(module=sid, regime=L, n_months=round(nm,1),
        regime_ir=round(full_ir,3), is_ir=round(is_ir,3), oos_ir=round(oos_ir,3), t_stat=round(tstat,2))
    } }
  if(length(cells)==0) return(list(CELL=data.table(), admitted_by_regime=setNames(vector("list",length(regimes)),regimes),
                                   admitted_modules=character(0), pool_oos_rho=NA_real_, asof=asof_date, n_modules=0L))
  CELL <- rbindlist(cells)
  CELL[, grade := vapply(module, function(s) as.character(MP$modules[[s]]$grade %||% "ungraded"), character(1))]

  # pool 진단: 전체 셀 IS vs OOS Spearman (국면조건부 스킬이 OOS에 남는가)
  ok <- is.finite(CELL$is_ir)&is.finite(CELL$oos_ir)
  pool_rho <- if(sum(ok)<4) NA_real_ else suppressWarnings(cor(CELL$is_ir[ok], CELL$oos_ir[ok], method="spearman"))

  # criterion 1 relative: regime-L 상위 ⅓
  CELL[, ir_rank_in_regime := frank(-regime_ir, na.last="keep"), by=regime]
  CELL[, n_in_regime := sum(is.finite(regime_ir)), by=regime]
  CELL[, top_tercile := is.finite(regime_ir) & ir_rank_in_regime <= ceiling(n_in_regime/3)]
  CELL[, median_ir_L := median(regime_ir, na.rm=TRUE), by=regime]

  # economic rationale 휴리스틱 (⑤ 반자동 + 보류 플래그)
  .rat <- function(sid,L,ir){ rl <- MP$modules[[sid]]$role %||% NA
    if(!is.na(rl) && grepl("defens",rl,ignore.case=TRUE) && L %in% c("CRISIS","CAUTION")) return("defensive crisis_alpha (AX-001)")
    if(L %in% c("RISK_ON","NEUTRAL") && is.finite(ir) && ir>=0.8) return("offensive expansion specialist")
    if(L=="CRISIS" && is.finite(ir) && ir>=0.5) return("crisis specialist (mechanism review)")
    if(L %in% c("RISK_ON","NEUTRAL") && is.finite(ir) && ir>=0.5) return("expansion contributor (review)")
    "review_pending" }
  CELL[, rationale := mapply(.rat, module, regime, regime_ir)]

  # RCMA 판정 — legacy 4기준은 rare_mode와 무관하게 항상 동일 산출 (v2.1: 소급 조임 금지)
  CELL[, pool_t := pool_t_vec[module]]
  CELL[, c1_perf  := is.finite(regime_ir) & (regime_ir>=IR_FLOOR | top_tercile)]
  CELL[, c2_n     := is.finite(n_months) & n_months>=MIN_MONTHS]
  CELL[, high_conf := is.finite(n_months) & n_months>=HIGH_CONF_MONTHS]
  CELL[, c3_oos   := is.finite(is_ir) & is.finite(oos_ir) & is_ir>0 & oos_ir>0]   # asof창 IS·OOS 둘 다 + (지속)
  CELL[, c4_sig   := is.finite(t_stat) & abs(t_stat)>=T_MIN]
  CELL[, c6_adv   := is.finite(regime_ir) & regime_ir>median_ir_L]
  CELL[, legacy_adm := c1_perf & c2_n & c3_oos & c4_sig]
  # C2 v2.1 rare 셀 = 위기군 국면 ∧ 셀 n<12 (국면 base rate 정의 폐기 — 1차 A/B 진단 ①)
  CELL[, rare := regime %in% STRESS_POOL & is.finite(n_months) & n_months < MIN_MONTHS]
  if (isTRUE(rare_mode)) {
    # 순수 완화: legacy 판정 불변 + rare 셀 신규 입장 경로 2개 (둘 다 ⑤ strict 의무)
    CELL[, rationale_strict := rationale != "review_pending"]
    CELL[, rare_direct := rare & c1_perf & c3_oos & rationale_strict &
                          is.finite(n_months) & n_months >= RARE_MIN_MONTHS &
                          is.finite(t_stat) & abs(t_stat) >= RARE_T_MIN]
    CELL[, rare_alt := rare & c1_perf & c3_oos & rationale_strict &
                       is.finite(pool_t) & abs(pool_t) >= T_MIN]
    CELL[, admitted := legacy_adm | rare_direct | rare_alt]
  } else {
    CELL[, rare_direct := FALSE]; CELL[, rare_alt := FALSE]
    CELL[, admitted := legacy_adm]
  }

  admitted_by_regime <- setNames(lapply(regimes, function(L) sort(CELL[admitted==TRUE & regime==L]$module)), regimes)
  admitted_modules <- sort(unique(CELL[admitted==TRUE]$module))
  list(CELL=CELL, admitted_by_regime=admitted_by_regime, admitted_modules=admitted_modules,
       pool_oos_rho=pool_rho, asof=asof_date, n_modules=length(mod_ids),
       rare_mode=isTRUE(rare_mode), rare_def="cell-level: regime in STRESS_POOL & n_months<12 (v2.1)")
}

# ── 정적 진단 JSON 산출 (asof = max date). run_wf_ensemble는 함수를 직접 호출. ─────────
.rcma_write_diagnostic <- function(proj = PROJ) {
  ctx <- .rcma_load(proj)
  asof <- max(unlist(lapply(ctx$AL, function(x) max(x$Date))))
  res <- compute_rcma(asof, ctx, proj)
  CELL <- res$CELL; mod_ids <- ctx$mod_ids; regimes <- ctx$regimes; MP <- ctx$MP

  adm <- list()
  for(sid in mod_ids){ rl<-list()
    for(L in regimes){ r <- CELL[module==sid & regime==L]
      if(nrow(r)==0){ rl[[L]] <- list(admitted=FALSE, regime_ir=NA, n_months=0); next }
      rl[[L]] <- list(admitted=as.logical(r$admitted), regime_ir=r$regime_ir, n_months=r$n_months,
        is_ir=r$is_ir, oos_ir=r$oos_ir, oos_sign_ok=as.logical(r$c3_oos), t_stat=r$t_stat,
        top_tercile=as.logical(r$top_tercile), high_confidence=as.logical(r$high_conf),
        marginal_above_median=as.logical(r$c6_adv), rationale=r$rationale) }
    adm[[sid]] <- list(grade=as.character(MP$modules[[sid]]$grade %||% "ungraded"),
                       role=MP$modules[[sid]]$role %||% NA, by_regime=rl) }
  out <- list(schema_version="v2.0", generated=as.character(Sys.Date()),
    method="RCMA 국면조건부 모듈 admission (★WALK-FORWARD: compute_rcma(asof) point-in-time). 본 JSON은 asof=max date 진단용. 실측 권위 = run_wf_ensemble의 WF 함수 호출. 6기준(IR≥0.5|top⅓ / n≥12m / asof창 IS·OOS sign+ / |t|≥2 / 경제논리 / 한계기여). overall 등급 게이트 폐지(도훈 2026-06-05).",
    pit_note="lookahead 차단: 멤버십이 asof 시점 데이터로만 산정(고정 2012 cut 폐기). 본 정적 JSON은 진단용이며 walk-forward 실측이 권위.",
    thresholds=list(ir_floor=IR_FLOOR, min_months=MIN_MONTHS, t_min=T_MIN),
    diagnostic_asof=as.character(res$asof), pool_oos_rho=round(res$pool_oos_rho,3),
    n_modules=length(mod_ids), n_admitted_cells=CELL[admitted==TRUE,.N], n_admitted_modules=length(res$admitted_modules),
    admitted_modules=res$admitted_modules, admission=adm)
  write_json(out, file.path(proj,"06_Registry/module_regime_admission.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)

  cat(sprintf("\nRCMA[진단 asof=%s]: %d/%d 모듈 · %d (module×regime) 셀 admitted | pool OOS ρ=%.3f\n",
    as.character(res$asof), length(res$admitted_modules), length(mod_ids), CELL[admitted==TRUE,.N], res$pool_oos_rho))
  for(L in regimes){ a<-CELL[admitted==TRUE & regime==L][order(-regime_ir)]
    cat(sprintf("  [%-8s] admitted %2d  top: %s\n", L, nrow(a),
      paste(sprintf("%s(IR%.2f,%s)", head(a$module,3), head(a$regime_ir,3), head(a$grade,3)), collapse=" "))) }
  lowA <- CELL[admitted==TRUE & grade!="A"]
  de <- lowA[regime=="CRISIS"][order(-regime_ir)][1]; of <- lowA[regime %in% c("RISK_ON","NEUTRAL")][order(-regime_ir)][1]
  cat(sprintf("\n★ 양방향 실증 (저등급=non-A): 방어형 CRISIS = %s (IR %s, grade %s) | 공격형 확장 = %s @%s (IR %s, grade %s)\n",
    de$module %||% "없음", as.character(de$regime_ir %||% NA), de$grade %||% NA,
    of$module %||% "없음", of$regime %||% NA, as.character(of$regime_ir %||% NA), of$grade %||% NA))
  invisible(out)
}

# 정적 진단 JSON 갱신 트리거:
#   - 직접 Rscript 실행(sys.nframe()==0) → 진단 JSON 작성.
#   - 다른 스크립트가 source 시: 호출측이 .RCMA_FUNC_ONLY=TRUE 설정 시 함수만 정의(JSON 미작성),
#     미설정 시(run_factor_rotation의 rebuild step 등) 진단 JSON 작성.
.rcma_func_only <- exists(".RCMA_FUNC_ONLY", inherits = TRUE) && isTRUE(get(".RCMA_FUNC_ONLY", inherits = TRUE))
if (!.rcma_func_only) {
  setwd(PROJ); .rcma_write_diagnostic(PROJ)
}
cat("[regime_module_admission] Loaded. compute_rcma(asof_date) (walk-forward PIT RCMA).\n")
