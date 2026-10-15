## P3R02 평가 — M5 2칸 vs 같은 배치 기준 RX0 2칸 → 사전등록 규칙(stage_artifacts prereg.json rules)을 기계 적용(R2 — 규칙 정본은 사전등록)
##   수치는 전부 R 계약 산출(rk_eval_cell · dp_build · rk_S — 손계산 없음 · AX-008). 이 파일이 더하는 것은 규칙 적용 · 공통 창 사본 · 기록 파싱뿐.
## 실행: Rscript evaluate.R [--cells-only]      (측정 = measure.sh · 밤 파이프라인 끝 뒤)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## ── 순수 도우미(픽스처 검사 대상 · 계약 호출 없음) ─────────────────────────────
## 패킷 JSON(simplifyVector = FALSE)의 표 = 행 객체 배열 → 행마다 한 줄(null 은 NA) · data.frame 이면 그대로
.p3_rows_dt <- function(x) if (is.data.frame(x)) as.data.table(x) else if (!length(x)) data.table() else
  rbindlist(lapply(x, function(r) as.data.table(lapply(r, function(v) if (is.null(v) || !length(v)) NA else v[[1]]))), fill = TRUE)
## 공통 창 사본(rules.common_window): 02 · 03 · 05 는 start 이후 행만 · 04 는 start 에 들고 있던 보유(start 이하 마지막 리밸)부터 ·
##   NAV 는 start 1 로 재기준하고 drawdown_net · cum_cost 를 다시 계산(시작 이전 고점이 낙폭에 섞이지 않게) · 벤치 NAV 도 재기준 · 나머지 파일은 그대로 복사
p3_trim_artifacts <- function(src_dir, out_dir, start) {
  start <- as.Date(start)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(src_dir, full.names = TRUE)) if (!dir.exists(f) && !grepl("^0[2-5]_.*[.]csv$", basename(f))) file.copy(f, out_dir, overwrite = TRUE)
  rd <- function(n, tick = FALSE) { p <- file.path(src_dir, n)
                                    x <- if (tick) fread(p, colClasses = list(character = "ticker")) else fread(p)
                                    x[, date := as.Date(date)]; x }
  pr <- rd("03_period_returns.csv")[date >= start]
  br <- rd("05_benchmark_returns.csv")[date >= start]
  nv <- rd("02_nav.csv")[date >= start]
  H  <- rd("04_holdings.csv", tick = TRUE)
  h0 <- suppressWarnings(max(H$date[H$date <= start]))
  H  <- H[date >= (if (is.finite(h0)) h0 else start)]
  if (!nrow(pr) || !nrow(nv) || !nrow(br)) stop("[p3_trim] start ", format(start), " 이후 행이 없다: ", src_dir)
  setorder(nv, date); setorder(br, date)
  if ("nav_net" %in% names(nv)) {
    g0 <- if ("nav_gross" %in% names(nv)) nv$nav_gross[1] else NA_real_; n0 <- nv$nav_net[1]
    nv[, nav_net := nav_net / n0]
    if ("nav_gross" %in% names(nv)) nv[, nav_gross := nav_gross / g0]
    if ("cum_cost" %in% names(nv) && "nav_gross" %in% names(nv)) nv[, cum_cost := nav_gross - nav_net]
    if ("drawdown_net" %in% names(nv)) nv[, drawdown_net := nav_net / cummax(nav_net) - 1]
  }
  if ("benchmark_nav" %in% names(br) && "benchmark_ret" %in% names(br)) br[, benchmark_nav := cumprod(1 + benchmark_ret)]
  for (z in list(list(pr, "03_period_returns.csv"), list(br, "05_benchmark_returns.csv"), list(nv, "02_nav.csv"), list(H, "04_holdings.csv")))
    fwrite(z[[1]], file.path(out_dir, z[[2]]))
  invisible(list(start = start, holdings_from = if (is.finite(h0)) h0 else start, n_pr = nrow(pr)))
}

## 위기 짝(rules.decisive (b)): 같은 위기 = 같은 peak_date · trough_date(벤치 정의). M5 cum_capture < RX0 cum_capture − tol 인 위기의 비율
p3_crisis_majority <- function(cr_m, cr_r, tol) {
  key <- function(x) paste(as.character(x$peak_date), as.character(x$trough_date))
  cm <- .p3_rows_dt(cr_m); cr <- .p3_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr)) return(list(n_pair = 0L, n_better = 0L, share = NA_real_, unpaired = nrow(cm) + nrow(cr)))
  cm[, k := key(cm)]; cr[, k := key(cr)]
  J <- merge(cm[, .(k, m = as.numeric(cum_capture))], cr[, .(k, r = as.numeric(cum_capture))], by = "k")
  J <- J[is.finite(m) & is.finite(r)]
  nb <- sum(J$m < J$r - tol)
  list(n_pair = nrow(J), n_better = nb, share = if (nrow(J)) nb / nrow(J) else NA_real_,
       unpaired = (nrow(cm) - nrow(J)) + (nrow(cr) - nrow(J)), per_crisis = J)
}

## 셀 로그 기록(rules.record ① ②): 엔진 요약 줄(커버리지 · EW 폴백) · [ecm] 진단 줄(신호일별 n · active · capbind · infeasible)
p3_parse_cell_log <- function(lines) {
  cov <- grep("^\\[rf_cell_engine\\] catalog ", lines, value = TRUE)
  cv <- if (length(cov)) {
    s <- cov[length(cov)]
    num <- function(p) suppressWarnings(as.numeric(sub(p, "\\1", s)))
    list(diff = num(".*차별화 ([0-9]+).*"), ew_fallback = num(".*EW폴백 ([0-9]+).*"),
         n_hit = num(".*선정일 ([0-9]+)/[0-9]+.*"), n_try = num(".*선정일 [0-9]+/([0-9]+).*"))
  } else NULL
  if (!is.null(cv)) cv$carry_days <- cv$n_try - cv$n_hit
  ec <- grep("^\\[ecm\\] d=", lines, value = TRUE)
  E <- if (length(ec)) rbindlist(lapply(ec, function(s) {
    g <- function(k) sub(paste0(".* ", k, "=([^ ]+).*"), "\\1", s)   # 키 앞 공백 필수 — 'capbind=' 끝의 'd=' 를 d 로 읽지 않게(픽스처 3b 실측)
    data.table(d = as.Date(g("d")), n = as.integer(g("n")), active = suppressWarnings(as.integer(g("active"))),
               capbind = suppressWarnings(as.integer(g("capbind"))), infeasible = as.integer(g("infeasible")))
  })) else data.table(d = as.Date(character(0)), n = integer(0), active = integer(0), capbind = integer(0), infeasible = integer(0))
  fb <- grep("어댑터 실패", lines, fixed = TRUE, value = TRUE)
  list(coverage = cv, ecm = E, n_method_fallback = length(fb),
       fallback_by_reason = list(cap_infeasible = sum(grepl("상한 불능", fb, fixed = TRUE)),
                                 under_3_assets = sum(grepl("자산 3종 미만", fb, fixed = TRUE)),
                                 other = sum(!grepl("상한 불능|자산 3종 미만", fb))))
}

## 처치 전달률(rules.tested): 계획 해를 낸 신호일([ecm] infeasible=0) / 선정 신호일(엔진 커버리지 줄 n_try) — 줄이 없으면 NA(미시험)
p3_delivery <- function(pl) {
  if (is.null(pl$coverage) || !is.finite(pl$coverage$n_try) || pl$coverage$n_try <= 0) return(NA_real_)
  sum(pl$ecm$infeasible == 0L, na.rm = TRUE) / pl$coverage$n_try
}

## 위기 중 보유를 낸 집행일 — 위기마다 {고점 이하 마지막 집행일} ∪ (고점, 저점] 안의 집행일
p3_crisis_execs <- function(exec_dates, crises) {
  ex <- sort(unique(as.Date(exec_dates))); cr <- .p3_rows_dt(crises)
  if (!length(ex) || !nrow(cr)) return(as.Date(character(0)))
  out <- unlist(lapply(seq_len(nrow(cr)), function(i) {
    p0 <- as.Date(as.character(cr$peak_date[i])); t0 <- as.Date(as.character(cr$trough_date[i]))
    c(suppressWarnings(max(ex[ex <= p0])), ex[ex > p0 & ex <= t0])
  }))
  out <- as.Date(out, origin = "1970-01-01"); sort(unique(out[is.finite(out)]))
}

## β 대조 귀속(rules.selection — 재점검 권고 ③): 같은 위기(패킷 exposure.crises · peak · trough 짝)에서 M5 selection_sum − RX0 selection_sum > 0 인 비율
##   MC8 짝은 크기 · 비중 · 총노출만 맞추고 β 는 맞추지 않는다 — 저β 구성은 selection_defense 라벨만으로는 기전 방어가 아니다
p3_selection_vs_ref <- function(ex_m, ex_r) {
  m <- .p3_rows_dt(ex_m); r <- .p3_rows_dt(ex_r)
  need <- c("peak_date", "trough_date", "selection_sum")
  if (!nrow(m) || !nrow(r) || !all(need %in% names(m)) || !all(need %in% names(r))) return(list(n_pair = 0L, share = NA_real_))
  if (!"market_beta_sum" %in% names(m)) m[, market_beta_sum := NA_real_]   # list() 안의 data.table 은 := 가 사본에 갈 수 있어 하나씩
  if (!"market_beta_sum" %in% names(r)) r[, market_beta_sum := NA_real_]
  m[, k := paste(as.character(peak_date), as.character(trough_date))]; r[, k := paste(as.character(peak_date), as.character(trough_date))]
  J <- merge(m[, .(k, sm = as.numeric(selection_sum), bm = as.numeric(market_beta_sum))],
             r[, .(k, sr = as.numeric(selection_sum), br = as.numeric(market_beta_sum))], by = "k")[is.finite(sm) & is.finite(sr)]
  list(n_pair = nrow(J), n_better = sum(J$sm - J$sr > 0), share = if (nrow(J)) mean(J$sm - J$sr > 0) else NA_real_, per_crisis = J)
}

## 이력 불완전 탈락(rules.record ③): 신호일 d 의 RX0 선정 수(EW 보유 수 — d 다음 첫 집행일 보유) − [ecm] n · 그 몫(탈락 / 선정)
p3_history_drops <- function(E, H_rx0) {
  if (!nrow(E) || !nrow(H_rx0)) return(data.table())
  sel <- H_rx0[is.finite(w) & w > 0, .(n_sel = uniqueN(ticker)), by = date][order(date)]
  out <- E[, {
    ex <- sel[date > d][1]
    list(exec = ex$date, n_sel = ex$n_sel, n = n)
  }, by = d]
  out[, drops := pmax(n_sel - n, 0L)][, drop_share := drops / n_sel]
  out[]
}

if (sys.nframe() == 0L) {   # ── 본 실행(스크립트로 불렸을 때만 — 픽스처 검사는 위 도우미만 적재) ──
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
CELLS_ONLY <- "--cells-only" %in% commandArgs(trailingOnly = TRUE)
RD <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz")
PR <- file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P3R02_eigen_markowitz"), pr_get(reg, "P3_CONSTRUCTION")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P3R02 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P3R02 평가] 행동 카드 설정 사본 변경")
## 판정 구현 자기 대조 — 이 파일 · 픽스처가 사전등록 고정값과 같아야 판정한다(결과 뒤 구현 수정 차단 · 재점검 권고 ①)
for (f in pre$evaluation$files %||% list()) if (!identical(rk_md5(file.path(ROOT, f$path)), f$md5)) stop("[P3R02 평가] 평가 경로 md5 ≠ 사전등록: ", f$path)
pc <- file.path(RD, "results", "precheck.json")
if (!file.exists(pc) || !isTRUE(fromJSON(pc)$ok)) stop("[P3R02 평가] precheck 통과 기록이 없다 — 측정 조건 미확인")
TAU <- as.Date(pre$tau_d); FS <- pre$final_selection_rule
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL
CELLS <- if (CELLS_ONLY) rk_shard(pre$cells) else pre$cells   # 병렬 칸 평가(2026-10-15 · _lib/eval_parallel.sh) — 종합 판정은 전부
EVS <- lapply(CELLS, function(cl) rk_eval_cell(ROOT, RD, cl, env, TAU)); names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
cat(sprintf("[P3R02 평가] 칸 평가 %d/%d\n", sum(vapply(EVS, function(e) e$status %in% c("evaluated", "axis_violation"), logical(1))), length(EVS)))
if (CELLS_ONLY) quit(status = 0)

RES <- file.path(RD, "results")
pk_read <- function(code, sub = "visible") { p <- file.path(RES, code, sub, "diagnosis_packet.json"); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL }
pk_build <- function(cell, art, out_sub) {           # 공통 창 사본에 같은 계약 적용(사전등록 설정 사본 · 위생 raw)
  if (is.null(env$raw)) env$raw <- mc_load_raw(ROOT, from = "1999-11-01", hygiene = TRUE)
  v <- dp_build(art, root = ROOT, cell_spec = file.path(ROOT, cell$path), raw = env$raw, bcfg = env$BCFG_L)
  dp_write(v, file.path(RES, cell$code, out_sub)); v
}
g <- function(x, p) rk_getf(x, p)
cells_by <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), pre$cells)[[1]]
## 측정 연기(워커 ok=FALSE · deferred) = 측정이 없는 것 — 판정 전 같은 사양으로 재측정(결과를 보고 고르는 것이 아니다 · 재점검 권고 ①)
dfr <- Filter(function(cl) { j <- file.path(RES, paste0(cl$code, ".json")); if (!file.exists(j)) return(FALSE)
                             r <- fromJSON(j, simplifyVector = FALSE); !isTRUE(r$ok) && !is.null(r$deferred) }, pre$cells)
if (length(dfr)) stop("[P3R02 평가] 측정 연기 칸 — 재측정(measure.sh) 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
## 쌍 판본(rules.vintage_pair — 재점검 권고 ④): 같은 엔진의 M5 · RX0 측정 시작 · 종료 데이터 지문이 모두 같아야 한다 — 다르면 그 쌍 재측정
fp_of <- function(code, tag) { f <- file.path(RES, sprintf("%s.fp_%s", code, tag)); if (file.exists(f)) paste(readLines(f, warn = FALSE), collapse = "|") else NA_character_ }
ENG <- list()
for (eng in c("E1", "E2")) {
  cm <- cells_by(eng, "M5"); cr <- cells_by(eng, "RX0"); em <- EVS[[cm$code]]; er <- EVS[[cr$code]]
  out <- list(engine = eng, m5 = cm$code, rx0 = cr$code, status_m5 = em$status, status_rx0 = er$status)
  fps <- c(fp_of(cm$code, "start"), fp_of(cm$code, "end"), fp_of(cr$code, "start"), fp_of(cr$code, "end"))
  out$vintage <- list(fingerprints = fps, same = !anyNA(fps) && length(unique(fps)) == 1L)
  if (!isTRUE(out$vintage$same)) stop(sprintf("[P3R02 평가] %s 쌍 데이터 지문 불일치 또는 부재 — 그 쌍을 재측정한 뒤 평가(rules.vintage_pair)", eng))
  untested <- function(why) { out$tested <<- FALSE; out$verdict <<- "untested"; out$why <<- why; ENG[[eng]] <<- out }
  out$tested <- identical(em$status, "evaluated") && identical(er$status, "evaluated")
  if (!isTRUE(out$tested)) { untested(sprintf("평가 상태 %s · %s", em$status, er$status)); next }
  ## 처치 전달률 — 계획 해를 낸 신호일 / 선정 신호일 < delivery_min 이면 M5 시험이 아니라 혼합(EW 폴백 · 이월) 시험이다
  lg <- file.path(RES, paste0(cm$code, ".log")); L <- if (file.exists(lg)) readLines(lg, warn = FALSE, encoding = "UTF-8") else character(0)
  pl <- p3_parse_cell_log(L); dlv <- p3_delivery(pl); out$delivery <- dlv
  if (!is.finite(dlv) || dlv < as.numeric(FS$delivery_min)) { untested(sprintf("처치 전달률 %s < %s", format(dlv), FS$delivery_min)); next }
  arf <- function(e) fromJSON(file.path(env$E$ta_resolve_artifact(e$artifacts)$dir, "authoritative_remeasure.json"), simplifyVector = FALSE)$measurement_axis$effective_start
  esm <- arf(em); esr <- arf(er)
  out$effective_start <- list(m5 = esm[c("status", "date")], rx0 = esr[c("status", "date")])
  if (!identical(esm$status, "ok") || !identical(esr$status, "ok")) { untested(sprintf("실효 시작 상태 %s · %s", esm$status %||% "NA", esr$status %||% "NA")); next }
  if (identical(esm$date, esr$date)) {
    out$window <- "original"; PM <- pk_read(cm$code); PRX <- pk_read(cr$code)
  } else {
    ## 공통 창 — 절단일 = 늦게 시작한 칸의 첫 기간수익일(두 칸을 같은 날에 맞춘다 · 재점검 권고 ②) · 보유는 그 날 들고 있던 집행일부터
    late <- if (as.Date(esm$date) > as.Date(esr$date)) em else er
    cs <- min(as.Date(fread(file.path(env$E$ta_resolve_artifact(late$artifacts)$dir, "03_period_returns.csv"))$date))
    out$window <- paste0("common_from_", format(cs)); sub <- paste0("common_", format(cs, "%Y%m%d"))
    tm <- file.path(RES, cm$code, sub, "artifacts"); tr <- file.path(RES, cr$code, sub, "artifacts")
    out$trim <- list(m5 = p3_trim_artifacts(env$E$ta_resolve_artifact(em$artifacts)$dir, tm, cs),
                     rx0 = p3_trim_artifacts(env$E$ta_resolve_artifact(er$artifacts)$dir, tr, cs))
    PM <- pk_build(cm, tm, file.path(sub, "visible")); PRX <- pk_build(cr, tr, file.path(sub, "visible"))
  }
  if (is.null(PM) || is.null(PRX)) { untested("보는 창 패킷 없음"); next }
  dcm <- g(PM, "behavior.summary.crisis_cum_capture_median"); dcr <- g(PRX, "behavior.summary.crisis_cum_capture_median")
  ucm <- g(PM, "behavior.summary.bull_up_capture_median")
  maj <- p3_crisis_majority(PM$behavior$crises %||% list(), PRX$behavior$crises %||% list(), as.numeric(FS$crisis_tol))
  ## 판정 입력이 하나라도 NA(위기 · 강세 국면 없음 · 짝 위기 0) = 미시험 — 반증으로 접지 않는다(재점검 권고 ①)
  if (!is.finite(dcm) || !is.finite(dcr) || !is.finite(ucm) || !is.finite(maj$share)) {
    out$inputs <- list(dc_m5 = dcm, dc_rx0 = dcr, uc_m5 = ucm, n_pair = maj$n_pair); untested("판정 입력 NA"); next }
  a <- dcm < dcr
  b <- maj$share > as.numeric(FS$majority_share)
  cc <- ucm >= as.numeric(FS$uc_floor)
  Sm <- rk_S(g(PM, "performance.strategy.calmar"), g(PM, "performance.strategy.port_t"), FS)
  Sr <- rk_S(g(PRX, "performance.strategy.calmar"), g(PRX, "performance.strategy.port_t"), FS)
  cmv <- g(PM, "performance.strategy.calmar"); crv <- g(PRX, "performance.strategy.calmar")
  ni <- if (is.finite(Sr) && Sr > 0) is.finite(Sm) && Sm >= Sr - as.numeric(FS$tie_eps) else is.finite(cmv) && is.finite(crv) && cmv >= crv
  out$decisive <- list(a_median = list(m5 = dcm, rx0 = dcr, ok = a), b_majority = c(maj[setdiff(names(maj), "per_crisis")], list(ok = b)),
                       c_participation = list(m5 = ucm, floor = FS$uc_floor, ok = cc), ok = a && b && cc)
  out$non_inferiority <- list(S_m5 = Sm, S_rx0 = Sr, calmar_m5 = cmv, calmar_rx0 = crv,
                              basis = if (is.finite(Sr) && Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(ni))
  ## 귀속 — 패킷 라벨(MC8) + β 대조(exposure.crises selection_sum 짝 과반) · β 는 두 칸 병기
  sv <- p3_selection_vs_ref(PM$exposure$crises %||% list(), PRX$exposure$crises %||% list())
  out$attribution <- list(label = as.character(PM$controls$attribution$label %||% NA)[1],
                          selection_vs_rx0 = sv[setdiff(names(sv), "per_crisis")],
                          beta = list(m5 = g(PM, "behavior.stats.beta"), rx0 = g(PRX, "behavior.stats.beta")))
  out$attribution$mechanism <- identical(out$attribution$label, "selection_defense") && is.finite(sv$share) && sv$share > as.numeric(FS$majority_share)
  out$per_crisis <- maj$per_crisis
  out$cdar <- list(m5 = g(PM, "behavior.stats.cdar"), rx0 = g(PRX, "behavior.stats.cdar"))
  out$verdict <- if (isTRUE(out$decisive$ok)) "decisive" else "not_decisive"
  ## 기록 — 이력 불완전 탈락(위기 보유 집행일의 평균 탈락 EW 비중 > drop_tag_share 면 결론에 '선택 교락' 꼬리표)
  Hr <- tryCatch({ x <- fread(file.path(env$E$ta_resolve_artifact(er$artifacts)$dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
                   x[, date := as.Date(date)]; x[, w := as.numeric(get(intersect(c("target_weight", "actual_weight"), names(x))[1]))]; x },
                 error = function(e) data.table())
  hd <- p3_history_drops(pl$ecm, Hr)
  cx <- if (nrow(hd)) p3_crisis_execs(hd$exec, PRX$behavior$crises %||% data.table()) else as.Date(character(0))
  hd_cr <- if (nrow(hd)) hd[exec %in% cx] else hd
  out$history_drop_tag <- nrow(hd_cr) > 0L && mean(hd_cr$drop_share, na.rm = TRUE) > as.numeric(FS$drop_tag_share)
  out$record <- list(coverage = pl$coverage, method_fallback_lines = pl$n_method_fallback, fallback_by_reason = pl$fallback_by_reason,
                     ecm = list(n_days = nrow(pl$ecm), infeasible = sum(pl$ecm$infeasible), capbind_days = sum(pl$ecm$capbind > 0, na.rm = TRUE),
                                active_min = suppressWarnings(min(pl$ecm$active, na.rm = TRUE)), active_median = stats::median(pl$ecm$active, na.rm = TRUE)),
                     history_drops = if (nrow(hd)) list(mean = mean(hd$drops), max = max(hd$drops), mean_share = mean(hd$drop_share, na.rm = TRUE),
                                                        crisis_mean_share = if (nrow(hd_cr)) mean(hd_cr$drop_share, na.rm = TRUE) else NA_real_) else NULL,
                     turnover_annual = list(m5 = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")))
  ENG[[eng]] <- out
}
tested <- vapply(ENG, function(x) isTRUE(x$tested), logical(1))
dec <- vapply(ENG, function(x) isTRUE(x$decisive$ok), logical(1))
nio <- vapply(ENG, function(x) isTRUE(x$non_inferiority$ok), logical(1))
verdict <- if (!any(tested)) "untested" else if (any(tested & !dec)) "falsified" else if (all(tested)) "decisive_both" else "decisive_partial"
sel <- NULL
if (all(tested) && all(dec) && all(nio)) {
  ## 꼬리표 없는 '구성 부품 후보' = 두 엔진 모두 기전 방어(MC8 selection_defense ∧ β 대조 selection_sum 짝 과반) — 그 밖(insufficient · NA · 불일치 포함)은 노출(β) 레버 꼬리표
  mech <- vapply(ENG, function(x) isTRUE(x$attribution$mechanism), logical(1))
  tags <- c(if (!all(mech)) "노출(β) 레버 — 기전 방어 아님", if (any(vapply(ENG, function(x) isTRUE(x$history_drop_tag), logical(1)))) "선택 교락(이력 탈락)")
  sel <- list(variant = "M5", tag = if (length(tags)) paste0("구성 부품 후보(", paste(tags, collapse = " · "), ")") else "구성 부품 후보",
              attribution = lapply(ENG, function(x) x$attribution[c("label", "mechanism")]))
}
## 기록 ⑤ M5 대 P3R01 K2 · ⑥ RX0 대 P0R01 C0(판정 입력 아님 · 있는 것만)
side <- function(path) if (file.exists(path)) fromJSON(path, simplifyVector = FALSE)$visible else NULL
cmp <- lapply(c("E1", "E2"), function(eng) list(
  k2 = side(file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map/results", sprintf("P3R01_%s_K2", eng), "eval.json")),
  p0r01_c0 = side(file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results", sprintf("P0R01_%s_C0", eng), "eval.json")),
  m5 = EVS[[sprintf("P3R02_%s_M5", eng)]]$visible, rx0 = EVS[[sprintf("P3R02_%s_RX0", eng)]]$visible)); names(cmp) <- c("E1", "E2")
res <- list(schema = "p3r02_evaluation_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
            evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")), engines = ENG, verdict = verdict, selected = sel,
            record_comparisons = cmp, precheck = fromJSON(pc, simplifyVector = FALSE))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation.json"), useBytes = TRUE)
for (eng in names(ENG)) { x <- ENG[[eng]]
  cat(sprintf("[P3R02 평가] %s — %s · 창 %s · (a) %s (b) %s (c) %s · 비열등 %s · 귀속 %s\n", eng, x$verdict, x$window %||% "-",
              isTRUE(x$decisive$a_median$ok), isTRUE(x$decisive$b_majority$ok), isTRUE(x$decisive$c_participation$ok),
              isTRUE(x$non_inferiority$ok), as.character(x$attribution %||% "-"))) }
cat(sprintf("[P3R02 평가] 판정 %s · 선택 %s\n", verdict, if (is.null(sel)) "없음(EW 유지)" else sel$tag))
}
