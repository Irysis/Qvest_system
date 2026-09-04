#!/usr/bin/env Rscript
# =============================================================================
# build_module_performance.R — 2계층 전략 로테이션 (Track2 데이터 레이어).
# ★ FR 입력 floor(계약) + ★v10 grade floor(essence B 이상 — 도훈 2026-08-29)를 통과한
#   모듈 allowlist만 regime Category로 분할
#   → per-regime IR/Sharpe/MDD/n → 06_Registry/module_performance.json.
# v10: 등급은 더 이상 정보용이 아니다 — 풀 자격 = grade ∈ {A,B}. RCMA 는 그 위 배치 심사.
# 기본 소비원:
#   1) module_catalog.json fr_eligible=true + metric_type=backtested + contract_pass
#   2) legacy QEPM grade_a_catalog A 모듈(마이그레이션 예외)
# 광역 scan은 QVEST_FR_ALLOW_BROAD_SCAN=1일 때만 진단용으로 허용한다.
# PIT: regime t-1 lag(어제 국면 → 오늘 수익 귀속, C5). 실측-only(자체합성 無).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite); library(xts) })
.find_root <- function() {
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
            Sys.getenv("QM_ROOT", unset = ""),
            getwd(),
            "C:/Users/99922/OneDrive/Quant_Module_Moltbot",
            "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot")
  for (p in cand[nzchar(cand)]) {
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
    if (dir.exists(file.path(p, "02_Infrastructure")) &&
        dir.exists(file.path(p, "04_Research"))) return(p)
  }
  stop("[build_module_performance] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
PROJ <- .find_root(); setwd(PROJ)
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

# 2. 등급 LUT + FR allowlist.
# ★v10 (2026-08-29 도훈 지시 "1계층에서 생산된 B등급 이상의 전략들을 활용"):
#   자격 = essence grade ∈ {A, B} — 구 "등급무관 specialist 차용"(2026-06-10) 폐기.
#   RCMA 는 이 floor **위의** 국면조건부 배치 심사로 유지된다(§SKILL 3).
#   env QVEST_L2_GRADE_FLOOR: "B"(기본) / "A" / "OFF"(진단 전용 — 구 동작).
#   풀 축소는 결함이 아니라 지시의 귀결 — 제외 수를 반드시 보고한다.
.L2_FLOOR <- toupper(Sys.getenv("QVEST_L2_GRADE_FLOOR", "B"))
.floor_excluded <- 0L
.floor_ok <- function(grade) {
  if (identical(.L2_FLOOR, "OFF")) return(TRUE)
  g <- toupper(as.character(grade %||% ""))
  g %in% (if (identical(.L2_FLOOR, "A")) "A" else c("A", "B"))
}
## ── 방어형 경로 (도훈 지시 2026-09-04) ───────────────────────────────────────
##   등급 floor 를 **대체하지 않고 병렬로** 연다. 방어형 = 벤치마크가 **실제로 마이너스를
##   기록한 국면**에서 아웃퍼폼한 전략(국면엔진 라벨 비의존 — 라벨은 이 시스템의 병목이고,
##   라벨 품질이 방어형 판정의 상한을 정하면 전략이 아니라 계기를 재게 된다).
##   실측 2026-09-04(380건): 방어형 184건 중 **B 이상 0건** — 전부 C/F 였다. 하락월 초과
##   +1.81% vs 비방어형 -0.12%, 벤치 -10% 이하에서 +5.64% vs -0.43%(심도에 따라 우위가
##   커지는 볼록성 = 선형 베타가 아니라 실제 방어 기전). 단독 알파가 약한 것은 사실이고
##   값어치는 조합 안에서 나오므로, essence 등급이 아니라 **풀 자격에서만** 인정한다.
##   ⇒ 2026-08-29 "F-overall specialist 풀 부적격" 을 **방어형에 한해** 되돌린다.
.DEF_ROUTE <- !identical(toupper(Sys.getenv("QVEST_L2_DEFENSIVE_ROUTE", "ON")), "OFF")
.defensive_ok <- function(rec) {
  if (!.DEF_ROUTE) return(FALSE)
  d <- rec$defensive_score %||% NULL
  isTRUE(d$defensive)
}
.def_admitted <- 0L
grade_lut <- new.env()
eligible_lut <- new.env()
eligible_paths <- character()
.attach <- function(id, grade, role, origin) if(nzchar(id) && is.null(grade_lut[[id]]))
  assign(id, list(grade=grade %||% NA, role=role %||% NA, origin=origin %||% NA), envir=grade_lut)
.find_sim <- function(strategy_id) {
  cand <- unique(c(
    file.path(PROJ, "04_Research", "strategies", strategy_id, "sim_result.rds"),
    Sys.glob(file.path(PROJ, "04_Research", "strategies", paste0(strategy_id, "*"), "sim_result.rds"))
  ))
  cand[file.exists(cand)][1] %||% NA_character_
}
.add_eligible <- function(id, sim_path, grade, role, origin, trust_status) {
  if(!nzchar(id) || is.na(sim_path) || !file.exists(sim_path)) return(invisible(FALSE))
  meta <- list(grade=grade %||% NA, role=role %||% NA, origin=origin %||% NA,
               trust_status=trust_status %||% "unknown")
  assign(id, meta, envir=eligible_lut)
  assign(basename(dirname(sim_path)), meta, envir=eligible_lut)
  .attach(id, grade, role, origin)
  eligible_paths <<- c(eligible_paths, normalizePath(sim_path, winslash="/", mustWork=FALSE))
  invisible(TRUE)
}
.is_fr_eligible <- function(e) {
  isTRUE(e$fr_eligible) &&
    identical(e$metric_type %||% NA_character_, "backtested") &&
    isTRUE((e$contract %||% list())$contract_pass)
}
# ★ frozen 신뢰 검증 (감사 CAP-P1-2): catalog module_hash ↔ 실제 sim_result.rds md5 대조.
#   불일치 = frozen 보장 파기(자기신고 방지) → 해당 모듈 skip + quarantine 로그 append.
#   hash 부재(구세대/legacy) = 'hash_missing' WARN만, skip하지 않음 (소급 차단은 governance 사안).
#   파일 부재는 기존 .add_eligible의 file.exists 처리에 위임 (여기서 mismatch로 오판하지 않음).
HASH_QUARANTINE_LOG <- file.path(PROJ, "06_Registry/module_hash_quarantine.log")
.verify_module_hash <- function(id, sim_path, expected) {
  if (is.na(sim_path) || !file.exists(sim_path)) return(TRUE)
  expected <- as.character(expected %||% NA_character_)
  if (is.na(expected) || !nzchar(expected)) {
    cat(sprintf("[build_module_performance] WARN hash_missing: %s — module_hash 없는 구세대 엔트리 (skip 안 함)\n", id))
    return(TRUE)
  }
  actual <- unname(tools::md5sum(sim_path))
  if (identical(expected, as.character(actual))) return(TRUE)
  cat(sprintf("[build_module_performance] WARN hash_mismatch → SKIP: %s (catalog=%s actual=%s) — frozen 위반 의심, quarantine 로그 기록\n",
              id, expected, actual))
  try(cat(sprintf("%s | HASH_MISMATCH | %s | catalog=%s | actual=%s | %s\n",
                  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), id, expected, actual, sim_path),
          file = HASH_QUARANTINE_LOG, append = TRUE), silent = TRUE)
  FALSE
}
.rel_path <- function(path) {
  p <- normalizePath(path, winslash="/", mustWork=FALSE)
  root <- normalizePath(PROJ, winslash="/", mustWork=FALSE)
  sub(paste0("^", gsub("([][{}()+*^$.|?\\\\-])", "\\\\\\1", root), "/?"), "", p)
}
mc <- tryCatch(fromJSON(file.path(PROJ,"06_Registry/module_catalog.json"), simplifyVector=FALSE)$modules, error=function(e) NULL)
gac <- tryCatch(as.data.table(fromJSON(file.path(PROJ,"04_Research/grade_a_catalog.json"))$strategies), error=function(e) NULL)
if(!is.null(gac) && nrow(gac)) for(i in seq_len(nrow(gac))) {
  .attach(gac$strategy_id[i], gac$grade[i], if("role" %in% names(gac)) gac$role[i] else NA, "qepm")
  if(identical(as.character(gac$grade[i]), "A")) {
    # ★2026-08-20: module_catalog 에 행이 있는 id 는 legacy 경로로 allowlist 에 넣지 않는다 —
    #   catalog 이 권위 (register_module 2026-08-02 상호배타 계약과 동일 원칙). 실사고:
    #   dup-hash 감사가 de-FR 한 비대표 3건(160537/021015/044603)이 6월 proxy-A 라벨로
    #   여기서 재진입 — proxy 시절 등급이 backtested 판정·fr_eligible 게이트를 우회했다.
    #   legacy 예외의 존재이유는 catalog 에 **없는** 구세대 QEPM 전략의 이관이므로 그 범위로 한정.
    if(!is.null(mc) && gac$strategy_id[i] %in% names(mc)) next
    sim_path <- .find_sim(gac$strategy_id[i])
    .verify_module_hash(gac$strategy_id[i], sim_path, NULL)   # legacy = hash 계약 부재 → hash_missing WARN만
    .add_eligible(gac$strategy_id[i], sim_path, gac$grade[i],
                  if("role" %in% names(gac)) gac$role[i] else NA, "qepm",
                  "legacy_qepm_grade_a")
  }
}
if(!is.null(mc)) for(id in names(mc)) {
  .attach(id, mc[[id]]$grade, mc[[id]]$role, mc[[id]]$origin_mode)
  if(.is_fr_eligible(mc[[id]])) {
    ## ★등급 floor 미달이어도 **방어형**이면 편입한다 (도훈 2026-09-04).
    ##   경로를 산출물에 기록해 소비자가 "왜 들어왔는지" 를 구분할 수 있게 한다.
    .adm_route <- if (.floor_ok(mc[[id]]$grade)) "grade_floor"
                  else if (.defensive_ok(mc[[id]])) "defensive_specialist" else NA_character_
    if (is.na(.adm_route)) { .floor_excluded <- .floor_excluded + 1L; next }  # ★v10 B+ floor
    if (identical(.adm_route, "defensive_specialist")) .def_admitted <- .def_admitted + 1L
    sim_path <- file.path(PROJ, mc[[id]]$sim_result_path)
    if(!.verify_module_hash(id, sim_path, mc[[id]]$module_hash)) next   # ★ hash 불일치 = frozen 파기 → skip
    .add_eligible(id, sim_path, mc[[id]]$grade,
                  mc[[id]]$role, mc[[id]]$origin_mode, "contract_fr_eligible")
  }
}
if (.DEF_ROUTE)
  cat(sprintf("[build_module_performance] ★방어형 경로: 등급 floor 미달이지만 방어형으로 편입 %d건 (방어형 = 벤치가 실제로 마이너스를 기록한 국면에서 아웃퍼폼 — 국면 라벨 비의존). 해제 = QVEST_L2_DEFENSIVE_ROUTE=OFF
",
              .def_admitted))
if(!identical(.L2_FLOOR, "OFF"))
  cat(sprintf("[build_module_performance] ★v10 grade floor %s: 계약 통과분 중 %d건 제외 · 풀 %d건 — 축소는 도훈 지시('B등급 이상')의 귀결. legacy 무등급 재편입 = 권위 재측정 후 grade 기입.\n",
              .L2_FLOOR, .floor_excluded, length(unique(eligible_paths))))
lookup_meta <- function(dirn){
  if(!is.null(eligible_lut[[dirn]])) return(eligible_lut[[dirn]])
  if(!is.null(grade_lut[[dirn]])) return(grade_lut[[dirn]])
  ids <- ls(grade_lut); hit <- ids[vapply(ids, function(x) startsWith(dirn, x), logical(1))]  # STR_944 ⊂ STR_944_oc_sue
  if(length(hit)) return(grade_lut[[hit[which.max(nchar(hit))]]])
  list(grade="ungraded", role=NA, origin="unknown", trust_status="unlisted")
}

# 3. FR allowlist scan + per-regime 실측
if(identical(Sys.getenv("QVEST_FR_ALLOW_BROAD_SCAN", "0"), "1")) {
  sim_files <- Sys.glob(file.path(PROJ, "04_Research/strategies", "*", "sim_result.rds"))
  cat("[build_module_performance] WARN: QVEST_FR_ALLOW_BROAD_SCAN=1 — broad scan diagnostic mode\n")
} else {
  sim_files <- unique(eligible_paths)
}
if(!length(sim_files)) stop("[build_module_performance] no FR-eligible modules. Check module_catalog contracts or grade_a_catalog.")
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
    origin_mode = meta$origin %||% "unknown", trust_status = meta$trust_status %||% "unlisted",
    freq = freq,
    sim_result_path = .rel_path(f),
    full_sharpe = round(sr(d$ret,annf),3), full_ir = round(sr(d$active,annf),3),
    n_days = nrow(d), date_range = c(as.character(min(d$Date)), as.character(max(d$Date))),
    per_regime = per)
  kept <- kept + 1
}
res <- list(schema_version="v3.1", generated=as.character(Sys.Date()),
            generated_by="2계층 전략 로테이션 (build_module_performance.R — 계약 floor + v10 grade floor)",
            regime_source="unified_regime_signal_daily.parquet Category (t-1 lag PIT)",
            regimes=regimes, metric_type="backtested_realized (sim_result NAV, 실측-only)",
            grade_floor=.L2_FLOOR,                       # ★v10: 이 산출물에 실제로 쓰인 floor (검사 재도출용)
            n_floor_excluded=.floor_excluded,
            n_defensive_admitted=.def_admitted,
            defensive_route=.DEF_ROUTE,
            note="입력 2단 게이트(v10 2026-08-29 도훈): ①계약 floor = module_catalog fr_eligible=true(contract_pass+backtested+frozen+hash/build_version, legacy QEPM grade-A 이관 예외) ②grade floor = essence grade B 이상(QVEST_L2_GRADE_FLOOR, OFF=진단). module_hash는 실제 md5 대조(불일치=skip+quarantine, CAP-P1-2). 배치 심사=RCMA.",
            n_modules=kept, modules=out)
dir.create(file.path(PROJ,"06_Registry"), showWarnings=FALSE)
write_json(res, file.path(PROJ,"06_Registry/module_performance.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
## ★로그가 모드를 정직하게 말하게 한다 (2026-08-08 수정) — 구판은 실제 모드와 무관하게
##   항상 "광역"이라고 찍었다. allowlist 로 정상 실행해도 로그만 보면 **진단모드 산출물을
##   정본에 덮어쓴 것처럼 읽힌다**(실측: 08-08 FQ-056 재실행 때 그렇게 오독할 뻔했고,
##   generated_by 필드를 따로 확인하고서야 allowlist 경로였음이 밝혀졌다).
cat(sprintf("module_performance.json written: %d modules (%s · v10 grade floor 적용)\n", kept,
            if (identical(Sys.getenv("QVEST_FR_ALLOW_BROAD_SCAN", "0"), "1")) "광역 진단모드" else "FR allowlist"))
gtab <- sort(table(vapply(out, function(x) as.character(x$grade %||% "ungraded"), character(1))), decreasing=TRUE)
cat("grade 분포:", paste(names(gtab), gtab, sep="=", collapse=" "), "\n")
