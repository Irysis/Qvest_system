## P3R01 평가 — 구성 변형 10칸(round_kit 칸 평가) vs 같은 엔진 EW 기준(P0R01 C0 평가) → 사전등록 규칙 기계 적용
## 실행: Rscript evaluate.R [--cells-only]
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
CELLS_ONLY <- "--cells-only" %in% commandArgs(trailingOnly = TRUE)
RD <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map")
PR <- file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R01_construction_map/prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P3R01_construction_map"), pr_get(reg, "P3_CONSTRUCTION")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P3R01 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P3R01 평가] 행동 카드 설정 사본 변경")
TAU <- as.Date(pre$tau_d)
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL
EVS <- lapply(pre$cells, function(cl) rk_eval_cell(ROOT, RD, cl, env, TAU)); names(EVS) <- vapply(pre$cells, function(z) z$code, character(1))
n_done <- sum(vapply(EVS, function(e) e$status %in% c("evaluated", "axis_violation"), logical(1)))
cat(sprintf("[P3R01 평가] 칸 평가 %d/%d\n", n_done, length(EVS)))
if (CELLS_ONLY) quit(status = 0)
P0R <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")
REF <- lapply(pre$reference_cells, function(r) fromJSON(file.path(P0R, r$code, "eval.json"), simplifyVector = FALSE))
FS <- pre$final_selection_rule
row <- function(e, eng, k) data.table(engine = eng, variant = k, code = e$code, status = e$status,
  cdar = as.numeric(e$visible$cdar %||% NA), calmar = as.numeric(e$visible$calmar %||% NA), port_t = as.numeric(e$visible$port_t %||% NA),
  cagr = as.numeric(e$visible$cagr %||% NA), mdd = as.numeric(e$visible$mdd %||% NA), turnover = as.numeric(e$visible$turnover_annual %||% NA),
  test_calmar = as.numeric(e$test$perf$calmar %||% NA), full_cdar = as.numeric(e$full$cdar %||% NA), grade = as.character(e$full$grade %||% NA))
T <- rbindlist(c(lapply(names(REF), function(eng) row(REF[[eng]], eng, "K0")),
                 lapply(EVS, function(e) row(e, e$engine, e$component))), fill = TRUE)
T[, S_vis := rk_S(calmar, port_t, FS)]
B <- T[variant == "K0", .(engine, cdar0 = cdar, S0 = S_vis, test_calmar0 = test_calmar)]
T <- merge(T, B, by = "engine")
T[variant != "K0", improve := status == "evaluated" & is.finite(cdar) & is.finite(cdar0) & cdar < cdar0 & S_vis >= S0]
both <- T[variant != "K0", .(n_eng = .N, n_improve = sum(improve %in% TRUE), mean_S = mean(S_vis), mean_cdar = mean(cdar)), by = variant][n_improve == n_eng]
sel <- if (nrow(both)) { setorder(both, -mean_S); top <- both[mean_S >= both$mean_S[1] - FS$tie_eps]; setorder(top, mean_cdar); top[1] } else NULL
res <- list(schema = "p3r01_evaluation_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
            table = T, both_improve = both, verdict = if (nrow(both)) "construction_lever" else "no_lever_over_ew",
            selected = if (is.null(sel)) NULL else as.list(sel),
            test_window_selected = if (is.null(sel)) NULL else T[variant == sel$variant, .(engine, test_calmar, test_calmar0)])
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "results", "evaluation.json"))
print(T[, .(engine, variant, cdar = round(cdar, 3), cdar0 = round(cdar0, 3), S_vis = round(S_vis, 3), S0 = round(S0, 3), improve, turnover = round(turnover, 2))])
cat(sprintf("[P3R01 평가] 판정 %s · 선택 %s\n", res$verdict, if (is.null(sel)) "없음(EW 유지)" else sel$variant))
