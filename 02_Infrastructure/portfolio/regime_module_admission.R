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
# PIT: regime t-1 lag. 실측-only. 모듈 frozen(소비).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
if (!exists("PROJ")) PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
if (!exists("%||%")) `%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
ANN <- 252
ir_ann <- function(a){ a<-a[is.finite(a)]; if(length(a)<20||sd(a)==0) return(NA_real_); mean(a)/sd(a)*sqrt(ANN) }

# ── thresholds (합격선) ──
# MIN_MONTHS = 12 floor (희소 국면 CRISIS/CAUTION는 36월-in-regime이 비현실 — 방어형 specialist 차단).
# 표본-significance는 ④ t = IR·√(n_m/12) ≥ 2 가 담당(소표본일수록 더 높은 IR 요구). n≥36 = high_conf 플래그.
IR_FLOOR <- 0.5; MIN_MONTHS <- 12; T_MIN <- 2.0; HIGH_CONF_MONTHS <- 36

# ── 모듈 per-regime active 일간 시계열 로드 (한 번만; asof는 함수에서 슬라이스) ──────
# AL[[sid]] = data.table(Date, a=active daily, regime=t-1 lag). 무겁지 않게 캐시.
.rcma_load <- function(proj = PROJ) {
  MP <- fromJSON(file.path(proj,"06_Registry/module_performance.json"), simplifyVector=FALSE)
  mod_ids <- names(MP$modules)
  RG <- as.data.table(read_parquet(file.path(proj,".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]
  setorder(RG,Date); RG[, regime:=shift(Category,1L)]; RG <- RG[!is.na(regime), .(Date,regime)]
  AL <- list()
  for(sid in mod_ids){
    p <- file.path(proj, MP$modules[[sid]]$sim_result_path)
    s <- tryCatch(readRDS(p), error=function(e) NULL); if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
    d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
    bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
    if(!is.null(bm)) d<-merge(d,bm,by="Date",all.x=TRUE) else d[,bm:=0]
    d[, a := r - fifelse(is.finite(bm),bm,0)]
    d <- merge(d[,.(Date,a)], RG, by="Date")
    if(nrow(d) >= 250) AL[[sid]] <- d
  }
  regimes <- unlist(MP$regimes) %||% c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
  list(MP = MP, AL = AL, mod_ids = names(AL), regimes = regimes)
}

# ── ★ compute_rcma(asof_date): point-in-time admission (Date ≤ asof_date 만 사용) ─────
#   반환: list(CELL=data.table(셀 진단+판정), admitted_by_regime=list(L->module ids),
#              admitted_modules, pool_oos_rho, asof=asof_date, n_modules)
#   c3(IS·OOS sign): asof 창 *내부* 시간순 65/35 분할(고정 2012 cut 폐기).
compute_rcma <- function(asof_date, ctx = NULL, proj = PROJ) {
  if (is.null(ctx)) ctx <- .rcma_load(proj)
  AL <- ctx$AL; mod_ids <- ctx$mod_ids; regimes <- ctx$regimes; MP <- ctx$MP
  asof_date <- as.Date(asof_date)

  cells <- list()
  for(sid in mod_ids){
    d <- AL[[sid]][Date <= asof_date]                       # ★ PIT: asof 이하만
    if(nrow(d) < 250) next                                  # cold-start: 데이터 부족 모듈 skip
    for(L in regimes){ sub <- d[regime==L]; nm <- nrow(sub)/21
      full_ir <- ir_ann(sub$a)
      # asof 창 내부 65/35 시간순 분할 (자연 OOS — 고정 2012 cut 폐기)
      if(nrow(sub) >= 40){
        setorder(sub, Date); kk <- floor(nrow(sub)*0.65)
        is_ir  <- ir_ann(sub$a[1:kk]); oos_ir <- ir_ann(sub$a[(kk+1):nrow(sub)])
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

  # RCMA 판정
  CELL[, c1_perf  := is.finite(regime_ir) & (regime_ir>=IR_FLOOR | top_tercile)]
  CELL[, c2_n     := is.finite(n_months) & n_months>=MIN_MONTHS]
  CELL[, high_conf := is.finite(n_months) & n_months>=HIGH_CONF_MONTHS]
  CELL[, c3_oos   := is.finite(is_ir) & is.finite(oos_ir) & is_ir>0 & oos_ir>0]   # asof창 IS·OOS 둘 다 + (지속)
  CELL[, c4_sig   := is.finite(t_stat) & abs(t_stat)>=T_MIN]
  CELL[, c6_adv   := is.finite(regime_ir) & regime_ir>median_ir_L]
  CELL[, admitted := c1_perf & c2_n & c3_oos & c4_sig]

  admitted_by_regime <- setNames(lapply(regimes, function(L) sort(CELL[admitted==TRUE & regime==L]$module)), regimes)
  admitted_modules <- sort(unique(CELL[admitted==TRUE]$module))
  list(CELL=CELL, admitted_by_regime=admitted_by_regime, admitted_modules=admitted_modules,
       pool_oos_rho=pool_rho, asof=asof_date, n_modules=length(mod_ids))
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
