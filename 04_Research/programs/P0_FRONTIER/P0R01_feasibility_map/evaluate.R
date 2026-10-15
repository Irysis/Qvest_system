## P0R01 — 측정 뒤 평가: 칸별 축 감사 · 보는 창 패킷(사전등록 행동 카드 설정 · 위생 raw) · 전기간 카드 · 시험 창 지표 →
##   목표 영역 판정(사전등록 규칙 그대로) · 기대 방향 집계 · 기계 선택 규칙 · 결과 파일. 칸 평가는 results/<code>/eval.json 으로 남겨 재실행 시 건너뛴다.
## 실행: Rscript evaluate.R [--cells-only]   (--cells-only = 칸 평가만 · 종합 판정 생략 — 측정이 덜 끝났을 때)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/programs/program_registry.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ARGS <- commandArgs(trailingOnly = TRUE); CELLS_ONLY <- "--cells-only" %in% ARGS
RD <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
RES <- file.path(RD, "results")
md5 <- function(f) unname(as.character(tools::md5sum(f)))
PR <- file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/prereg.json")

## ── 사전등록 불변(R2) ──
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P0R01_feasibility_map"), pr_get(reg, "P0_FRONTIER")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, md5(PR))) stop("[P0R01 평가] 사전등록 md5 불일치 — 결과 뒤 변경 의심(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
if (!identical(md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P0R01 평가] 사전등록 당시 행동 카드 설정 사본이 바뀌었다")
TAU <- as.Date(pre$tau_d)
TR <- pre$decisive_test$target_region
UC_FLOOR <- as.numeric(TR[[1]]$value); CAGR_MIN <- as.numeric(TR[[3]]$value)
getf <- function(x, path) { for (k in strsplit(path, ".", fixed = TRUE)[[1]]) { if (is.null(x)) return(NA_real_); x <- x[[k]] }
                            v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }

## ── 축 감사(04_holdings 실보유) ──
CD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
MAXN <- as.integer(CD$tier_soft_deployment$max_names)
axis_audit <- function(dir) {
  H <- fread(file.path(dir, "04_holdings.csv"))
  wc <- intersect(c("target_weight", "actual_weight"), names(H))[1]
  H[, w := as.numeric(get(wc))]
  per <- H[is.finite(w) & w != 0, .(n = .N, s = sum(w), mn = min(w)), by = date]
  list(max_names = MAXN, n_max_realized = max(per$n), w_min = min(per$mn), sigma_w_max = max(per$s),
       ok = max(per$n) <= MAXN && min(per$mn) >= -1e-9 && max(per$s) <= 1 + 1e-6)
}

## ── 시험 창 성과(등급 v3 의 같은 창 함수 · 2023-01~) ──
E <- .dp_deps(ROOT)
BCFG_L <- E$bc_cfg(ROOT, path = BCFG)     # 사전등록 사본을 목록으로(dp_build · mc_card 공통 — mc_card 는 경로를 받지 않는다)
test_perf <- function(dir) {
  rd <- .dp_read(E, dir)
  prt <- rd$pr[date > TAU][order(date)]; brt <- rd$br[date > TAU][order(date)]; nvt <- rd$nv[date > TAU][order(date)]
  if (nrow(prt) < 20L) return(list(status = "insufficient"))
  emptyM <- data.table(metric_name = character(0), metric_value = numeric(0)); emptyC <- data.table(metric_name = character(0), active_value = numeric(0))
  X <- E$.gv3_prep(prt, brt, nvt, emptyM, emptyC)
  p <- E$gv3_window(X$pr, X$br, X$nv, root = ROOT)
  c(list(status = "ok", window = c(format(min(prt$date)), format(max(prt$date)))), p[intersect(names(p), c("cagr", "mdd", "calmar", "sharpe", "port_t"))])
}

## ── 칸 평가 ──
raw <- NULL
eval_cell <- function(cell) {
  out_dir <- file.path(RES, cell$code); ej <- file.path(out_dir, "eval.json")
  if (file.exists(ej)) return(fromJSON(ej, simplifyVector = FALSE))
  rj <- file.path(RES, paste0(cell$code, ".json"))
  if (!file.exists(rj)) return(list(code = cell$code, status = "not_measured"))
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) return(list(code = cell$code, status = "measure_failed", err = r$err %||% NA))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(raw)) raw <<- mc_load_raw(ROOT, from = "1999-11-01", hygiene = TRUE)
  t0 <- Sys.time()
  ax <- axis_audit(r$artifacts)
  vis <- dp_build(r$artifacts, root = ROOT, cell_spec = file.path(ROOT, cell$path), raw = raw, bcfg = BCFG_L)
  dp_write(vis, file.path(out_dir, "visible"))
  card <- mc_card(r$artifacts, root = ROOT, raw = raw, bcfg = BCFG_L)
  mc_write(card, file.path(out_dir, "full"), root = ROOT)
  tp <- tryCatch(test_perf(r$artifacts), error = function(e) list(status = paste("error:", conditionMessage(e))))
  ar <- fromJSON(file.path(r$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  uc <- getf(vis, "behavior.summary.bull_up_capture_median"); dc <- getf(vis, "behavior.summary.crisis_cum_capture_median")
  dcs <- getf(vis, "behavior.dc_strong_max"); cg <- getf(vis, "performance.strategy.cagr")
  ev <- list(code = cell$code, engine = cell$engine, component = cell$component, status = "evaluated", artifacts = r$artifacts,
             axis = ax,
             visible = list(window = vis$window, uc = uc, dc = dc, dc_strong = dcs, cagr = cg,
                            calmar = getf(vis, "performance.strategy.calmar"), port_t = getf(vis, "performance.strategy.port_t"),
                            mdd = getf(vis, "performance.strategy.mdd"), sharpe = getf(vis, "performance.strategy.sharpe"),
                            dd_capture_median = getf(vis, "behavior.summary.crisis_dd_capture_median"),
                            dd_capture_worst = getf(vis, "behavior.summary.crisis_dd_capture_worst"),
                            n_crisis = getf(vis, "behavior.summary.n_crisis"), n_bull = getf(vis, "behavior.summary.n_bull"),
                            verdict = vis$behavior$verdict, attribution = vis$controls$attribution$label %||% NA,
                            exposure_mean = getf(vis, "controls.exposure_profile.mean")),
             target = list(uc_ok = is.finite(uc) && uc >= UC_FLOOR, dc_ok = is.finite(dc) && is.finite(dcs) && dc <= dcs,
                           cagr_ok = is.finite(cg) && cg >= CAGR_MIN),
             test = list(uc = card$test$bull_up_capture_median %||% NA, dc = card$test$crisis_cum_capture_median %||% NA,
                         n_bull = card$test$n_bull %||% NA, n_crisis = card$test$n_crisis %||% NA, verdict = card$test$verdict %||% NA,
                         dc_strong = card$dc_strong_max %||% NA, perf = tp),
             full = list(grade = ar$essence_grade, S = ar$grade_v3$S %||% NA, cr = card$overall$verdict, attribution = card$controls$attribution$label %||% NA,
                         effective_start = ar$measurement_axis$effective_start$date %||% NA),
             eval_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  ev$target$in_region <- isTRUE(ev$target$uc_ok) && isTRUE(ev$target$dc_ok) && isTRUE(ev$target$cagr_ok)
  if (!isTRUE(ax$ok)) { ev$status <- "axis_violation"; ev$target$in_region <- FALSE }
  writeLines(toJSON(ev, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ej)
  cat(sprintf("[평가] %s — UC %.3f · DC %.3f(문턱 %.3f) · CAGR %.3f · 영역 %s · 축 %s · %.0f초\n", cell$code, uc, dc, dcs, cg,
              ev$target$in_region, ax$ok, ev$eval_seconds))
  ev
}
## 병렬 칸 평가(2026-10-15) — --cells-only 에 --shard=i/K 가 있으면 그 몫만(_lib/eval_parallel.sh 가 K 개를 띄운다) · 종합 판정은 전부
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
CELLS <- if (CELLS_ONLY) rk_shard(pre$cells, ARGS) else pre$cells
EVS <- lapply(CELLS, eval_cell)
names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
n_done <- sum(vapply(EVS, function(e) identical(e$status, "evaluated") || identical(e$status, "axis_violation"), logical(1)))
cat(sprintf("[P0R01 평가] 칸 평가 %d/%d\n", n_done, length(EVS)))
if (CELLS_ONLY) quit(status = 0)
if (n_done < length(EVS)) cat("[P0R01 평가] ⚠ 측정 · 평가 안 된 칸이 있다 — 종합 판정은 평가된 칸으로만(표식)\n")

## ── 종합: 목표 영역 · 기대 방향 · 선택 ──
row_of <- function(e) data.table(code = e$code, engine = e$engine %||% NA, component = e$component %||% NA, status = e$status,
                                 uc = e$visible$uc %||% NA_real_, dc = e$visible$dc %||% NA_real_, dc_strong = e$visible$dc_strong %||% NA_real_,
                                 cagr = e$visible$cagr %||% NA_real_, calmar = e$visible$calmar %||% NA_real_, port_t = e$visible$port_t %||% NA_real_,
                                 mdd = e$visible$mdd %||% NA_real_, verdict = e$visible$verdict %||% NA_character_,
                                 attribution = as.character(e$visible$attribution %||% NA_character_),
                                 in_region = isTRUE(e$target$in_region), uc_ok = isTRUE(e$target$uc_ok), dc_ok = isTRUE(e$target$dc_ok),
                                 cagr_ok = isTRUE(e$target$cagr_ok), grade = as.character(e$full$grade %||% NA_character_),
                                 S_full = suppressWarnings(as.numeric(e$full$S %||% NA)))
T <- rbindlist(lapply(EVS, row_of), fill = TRUE)
FS <- pre$final_selection_rule
T[, S_vis := ifelse(is.finite(calmar) & is.finite(port_t) & calmar > 0 & port_t > 0,
                    (calmar / FS$calmar_norm)^FS$w_calmar * (port_t / FS$port_t_norm)^FS$w_port_t, 0)]
T[, short_uc := pmax(0, UC_FLOOR - uc)][, short_dc := pmax(0, dc - dc_strong)][, short_cagr := pmax(0, CAGR_MIN - cagr)]
T[, n_comp := fifelse(component == "C0", 0L, fifelse(component == "C6", 2L, 1L))]
## 기대 방향 — 같은 엔진의 참조 칸 대비(R 기계 집계)
EXP <- list()
for (cid in names(pre$expectations)) for (q in pre$expectations[[cid]]) for (eid in unique(T$engine)) {
  a <- T[engine == eid & component == cid]; b <- T[engine == eid & component == q$ref]
  if (!nrow(a) || !nrow(b)) next
  fld <- sub("^.*\\.", "", q$field); col <- c(bull_up_capture_median = "uc", crisis_cum_capture_median = "dc")[[fld]]
  va <- a[[col]]; vb <- b[[col]]
  hit <- if (!is.finite(va) || !is.finite(vb)) NA else switch(q$op, "<" = va < vb, "<=" = va <= vb, ">" = va > vb, ">=" = va >= vb)
  EXP[[length(EXP) + 1L]] <- data.table(engine = eid, component = cid, field = fld, op = q$op, ref = q$ref, value = va, ref_value = vb, hit = hit)
}
EXPT <- rbindlist(EXP)
## 선택(사전등록 규칙 그대로 · 보는 창 필드만)
H <- T[in_region == TRUE]
sel <- NULL
if (nrow(H)) {
  setorder(H, -S_vis)
  top <- H[S_vis >= H$S_vis[1] - FS$tie_eps]
  setorder(top, dc, n_comp)
  sel <- top[1]
}
verdict <- if (nrow(H)) "reached" else "not_reached"
## 시험 창 — 목표 영역 칸만(사람 쪽 판정)
test_rows <- if (nrow(H)) rbindlist(lapply(H$code, function(cd) { e <- EVS[[cd]]; tp <- e$test$perf
  data.table(code = cd, test_uc = e$test$uc %||% NA_real_, test_dc = e$test$dc %||% NA_real_, test_dc_strong = e$test$dc_strong %||% NA_real_,
             test_cagr = suppressWarnings(as.numeric(tp$cagr %||% NA)), test_n_bull = e$test$n_bull %||% NA, test_n_crisis = e$test$n_crisis %||% NA) }), fill = TRUE) else data.table()
if (nrow(test_rows)) {
  test_rows[, uc_hold := fifelse(is.finite(test_uc), test_uc >= UC_FLOOR, NA)]
  test_rows[, dc_hold := fifelse(is.finite(test_dc) & is.finite(test_dc_strong), test_dc <= test_dc_strong, NA)]
  test_rows[, cagr_hold := fifelse(is.finite(test_cagr), test_cagr >= CAGR_MIN, NA)]
}
res <- list(schema = "p0r01_evaluation_v1", round_id = "P0R01_feasibility_map", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            prereg_md5 = md5(PR), n_cells = length(EVS), n_evaluated = n_done,
            thresholds = list(uc_floor = UC_FLOOR, cagr_min = CAGR_MIN, dc_strong = unique(na.omit(T$dc_strong))),
            decisive = list(verdict = verdict, n_in_region = nrow(H), in_region = H$code,
                            binding = list(uc = sum(!T$uc_ok, na.rm = TRUE), dc = sum(!T$dc_ok, na.rm = TRUE), cagr = sum(!T$cagr_ok, na.rm = TRUE)),
                            selected = if (is.null(sel)) NULL else as.list(sel), test_window = if (nrow(test_rows)) test_rows else NULL),
            table = T, expectations = EXPT,
            expectation_hit_rate = if (nrow(EXPT)) mean(EXPT$hit, na.rm = TRUE) else NA_real_,
            axis_violations = T[status == "axis_violation"]$code)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation.json"))
fwrite(T, file.path(RES, "evaluation_table.csv"))
cat(sprintf("[P0R01 평가] 판정 %s · 목표 영역 %d칸 · 구속(미달 칸 수) UC %d · DC %d · CAGR %d · 기대 방향 적중 %.0f%%\n",
            verdict, nrow(H), res$decisive$binding$uc, res$decisive$binding$dc, res$decisive$binding$cagr, 100 * res$expectation_hit_rate))
if (!is.null(sel)) cat(sprintf("[P0R01 평가] 선택 = %s (S_vis %.3f)\n", sel$code, sel$S_vis))
