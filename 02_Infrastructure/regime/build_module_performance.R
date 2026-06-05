#!/usr/bin/env Rscript
# =============================================================================
# build_module_performance.R — Factor Rotation Mode (Track2 데이터 레이어).
# ★ 광역 모듈 유니버스(04_Research/strategies/*/sim_result.rds 전수, 등급 게이트 없음)를
#   regime Category로 분할 → per-regime IR/Sharpe/MDD/n → 06_Registry/module_performance.json.
# 등급은 정보용 attach만(grade_a_catalog ∪ module_catalog ∪ best-effort). 사용여부는
#   국면조건부 admission(RCMA: regime_module_admission.R)이 판단 — overall 등급 게이트 폐지
#   (도훈 mandate 2026-06-05: Grade-A만 쓰지 말 것. 하위등급도 국면 specialist면 차용).
# PIT: regime t-1 lag(어제 국면 → 오늘 수익 귀속, C5). 실측-only(자체합성 無).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
ANN <- 252
# freq-aware Sharpe/IR: annf=252(daily)/12(monthly). 월간 DPL 등 비-일간 모듈 정합(도훈 2026-06-05).
sr  <- function(r, annf=ANN){ r<-r[is.finite(r)]; if(length(r) < (if(annf<=12) 8L else 20L) || sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(annf) }
mdd <- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(NA_real_); n<-cumprod(1+r); as.numeric(1-min(n/cummax(n))) }

# 1. regime Category (t-1 lag for PIT)
RG <- as.data.table(read_parquet(file.path(PROJ,".cache/unified_regime_signal_daily.parquet")))
RG <- RG[!is.na(Category), .(Date=as.Date(Date), Category)]
setorder(RG, Date); RG[, regime_lag := shift(Category, 1L)]
RG <- RG[!is.na(regime_lag), .(Date, regime=regime_lag)]

# 2. 등급 LUT (정보용 attach — ★ 게이트 아님). grade_a_catalog(QEPM A) ∪ module_catalog(register_module)
grade_lut <- new.env()
.attach <- function(id, grade, role, origin) if(nzchar(id) && is.null(grade_lut[[id]]))
  assign(id, list(grade=grade %||% NA, role=role %||% NA, origin=origin %||% NA), envir=grade_lut)
gac <- tryCatch(as.data.table(fromJSON(file.path(PROJ,"04_Research/grade_a_catalog.json"))$strategies), error=function(e) NULL)
if(!is.null(gac) && nrow(gac)) for(i in seq_len(nrow(gac)))
  .attach(gac$strategy_id[i], gac$grade[i], if("role" %in% names(gac)) gac$role[i] else NA, "qepm")
mc <- tryCatch(fromJSON(file.path(PROJ,"06_Registry/module_catalog.json"), simplifyVector=FALSE)$modules, error=function(e) NULL)
if(!is.null(mc)) for(id in names(mc)) .attach(id, mc[[id]]$grade, mc[[id]]$role, mc[[id]]$origin_mode)
lookup_meta <- function(dirn){
  if(!is.null(grade_lut[[dirn]])) return(grade_lut[[dirn]])
  ids <- ls(grade_lut); hit <- ids[vapply(ids, function(x) startsWith(dirn, x), logical(1))]  # STR_944 ⊂ STR_944_oc_sue
  if(length(hit)) return(grade_lut[[hit[which.max(nchar(hit))]]])
  list(grade="ungraded", role=NA, origin="qepm")
}

# 3. ★ 광역 scan (04_Research/strategies/*/sim_result.rds 전수) + per-regime 실측
sim_files <- Sys.glob(file.path(PROJ, "04_Research/strategies", "*", "sim_result.rds"))
# 메모리 가드(E3): FR_MAX_MODULES>0 시 최근 수정순 상한 (대규모 유니버스 OOM 회피). 0=무제한.
.maxmod <- suppressWarnings(as.integer(Sys.getenv("FR_MAX_MODULES", "0")))
if (!is.na(.maxmod) && .maxmod > 0L && length(sim_files) > .maxmod) {
  sim_files <- sim_files[order(file.info(sim_files)$mtime, decreasing = TRUE)][seq_len(.maxmod)]
  cat(sprintf("[build_module_performance] FR_MAX_MODULES=%d → 최근 %d개로 제한\n", .maxmod, .maxmod))
}
regimes <- c("RISK_ON","NEUTRAL","CAUTION","CRISIS","RISK_OFF")
out <- list(); kept <- 0
for(f in sim_files){
  dirn <- basename(dirname(f))
  s <- tryCatch(readRDS(f), error=function(e) NULL); if(is.null(s)||is.null(s$DAILY_NAV_DT)) next
  d <- as.data.table(s$DAILY_NAV_DT); if(!all(c("Date","Strategy_Ret")%in%names(d))) next
  d[, Date:=as.Date(Date)]
  # ★ freq 감지 (월간 DPL 등 비-일간 모듈 정합). s$freq 우선, 없으면 날짜간격 중앙값.
  freq <- s$freq %||% (if(nrow(d)>5 && stats::median(as.numeric(diff(sort(unique(d$Date)))))>=20) "monthly" else "daily")
  annf <- if(identical(freq,"monthly")) 12 else 252; mdiv <- if(identical(freq,"monthly")) 1L else 21L
  bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
  dm <- d[, .(Date, ret=Strategy_Ret)]
  # 월간 모듈: 월말 날짜가 RG(거래일) 미일치 가능 → roll-join으로 직전 거래일 regime 귀속(PIT t-1 정합)
  if(identical(freq,"monthly")){ setkey(RG,Date); setkey(dm,Date); d <- RG[dm, roll=TRUE]
  } else d <- merge(dm, RG, by="Date")
  if(!is.null(bm)) d <- merge(d, bm, by="Date", all.x=TRUE) else d[, bm:=NA_real_]
  d <- d[!is.na(regime)]
  d[, active := ret - fifelse(is.finite(bm), bm, 0)]
  if(nrow(d) < (if(identical(freq,"monthly")) 24L else 100L)) next
  # validity 필터 (★데이터-깨짐만 — blown-up/NAV→~0. 등급·overall성과로 거르지 않음:
  #   91% MDD grade-F도 국면 specialist일 수 있어 풀 진입 허용, 사용여부는 RCMA가 국면조건부 판단. 도훈 #4)
  full_mdd <- mdd(d$ret)
  if(!is.finite(full_mdd) || full_mdd >= 0.99) next           # MDD≥99%(NAV→~1%) = 데이터깨짐/완전blown-up만
  if(max(abs(d$ret), na.rm=TRUE) > 0.5) next                  # 일간 |ret|>50% = 데이터 오류
  meta <- lookup_meta(dirn)
  per <- list()
  for(rg in regimes){ sub <- d[regime==rg]
    per[[rg]] <- list(n_days=nrow(sub), n_months=round(nrow(sub)/mdiv,1),
      sharpe=round(sr(sub$ret,annf),3), ir=round(sr(sub$active,annf),3),
      mdd=round(mdd(sub$ret),3), mean_ann=round(mean(sub$ret,na.rm=TRUE)*annf,4)) }
  out[[dirn]] <- list(
    source_strategy_id = dirn, grade = meta$grade %||% "ungraded", role = meta$role %||% NA,
    origin_mode = meta$origin %||% "qepm", freq = freq,
    sim_result_path = sub("^.*Quant_Module_Moltbot/","",f),
    full_sharpe = round(sr(d$ret,annf),3), full_ir = round(sr(d$active,annf),3),
    n_days = nrow(d), date_range = c(as.character(min(d$Date)), as.character(max(d$Date))),
    per_regime = per)
  kept <- kept + 1
}
res <- list(schema_version="v2.0", generated=as.character(Sys.Date()),
            generated_by="Factor Rotation Mode (build_module_performance.R — 광역·등급무관)",
            regime_source="unified_regime_signal_daily.parquet Category (t-1 lag PIT)",
            regimes=regimes, metric_type="backtested_realized (sim_result NAV, 실측-only)",
            note="광역 유니버스(04_Research/strategies/* 전수). grade=정보용 attach. 사용여부=RCMA(regime_module_admission). overall 등급 게이트 폐지(도훈 2026-06-05).",
            n_modules=kept, modules=out)
dir.create(file.path(PROJ,"06_Registry"), showWarnings=FALSE)
write_json(res, file.path(PROJ,"06_Registry/module_performance.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat(sprintf("module_performance.json written: %d modules (광역, 등급 게이트 없음)\n", kept))
gtab <- sort(table(vapply(out, function(x) as.character(x$grade %||% "ungraded"), character(1))), decreasing=TRUE)
cat("grade 분포:", paste(names(gtab), gtab, sep="=", collapse=" "), "\n")
