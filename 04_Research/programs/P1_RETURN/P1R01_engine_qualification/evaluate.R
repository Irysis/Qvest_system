## P1R01 평가 — 엔진 3종(P0R01 C0 칸)의 β-통제 알파(보는 창 · 시험 창) · 상승 포착 → 사전등록 자격 규칙 기계 적용
## 실행: Rscript evaluate.R   (P0R01 evaluate.R --cells-only 이후)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
md5 <- function(f) unname(as.character(tools::md5sum(f)))
RD <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R01_engine_qualification")
PR <- file.path(ROOT, "stage_artifacts/programs/P1_RETURN/P1R01_engine_qualification/prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P1R01_engine_qualification"), pr_get(reg, "P1_RETURN")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, md5(PR))) stop("[P1R01 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
TAU <- as.Date(pre$tau_d); TMIN <- as.numeric(pre$rules$qualify$t_alpha_min); UCF <- as.numeric(pre$rules$qualify$uc_floor)
E <- .dp_deps(ROOT)
P0R <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")
mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")    # 행동 카드 계약의 월 집계(복리)
rows <- list()
for (e in names(pre$data$cells)) {
  code <- pre$data$cells[[e]]
  ev <- tryCatch(fromJSON(file.path(P0R, code, "eval.json"), simplifyVector = FALSE), error = function(z) NULL)
  if (is.null(ev) || !identical(ev$status, "evaluated")) { rows[[e]] <- data.table(engine = e, code = code, status = ev$status %||% "not_evaluated"); next }
  rd <- .dp_read(E, ev$artifacts)
  S <- mon(rd$pr[, .(date, ret_net)], "ret_net"); K <- mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")
  M <- merge(S[, .(ym, s = r)], K[, .(ym, k = r)], by = "ym")[order(ym)]
  tym <- format(TAU, "%Y-%m")
  bv <- beta_controlled_alpha(M[ym <= tym]$s, M[ym <= tym]$k, periods_per_year = 12, nw_lag = 3L)
  bt <- tryCatch(beta_controlled_alpha(M[ym > tym]$s, M[ym > tym]$k, periods_per_year = 12, nw_lag = 3L), error = function(z) NULL)
  rows[[e]] <- data.table(engine = e, code = code, status = "evaluated",
                          t_alpha_vis = bv$t_alpha, alpha_ann_vis = bv$alpha_ann, beta_vis = bv$beta, port_t_vis = bv$port_t, n_vis = bv$n,
                          uc_vis = suppressWarnings(as.numeric(ev$visible$uc)), cagr_vis = suppressWarnings(as.numeric(ev$visible$cagr)),
                          t_alpha_test = bt$t_alpha %||% NA_real_, alpha_ann_test = bt$alpha_ann %||% NA_real_, n_test = bt$n %||% NA_integer_,
                          uc_test = suppressWarnings(as.numeric(ev$test$uc %||% NA)))
}
T <- rbindlist(rows, fill = TRUE)
T[status == "evaluated", qualify := is.finite(t_alpha_vis) & t_alpha_vis >= TMIN & is.finite(uc_vis) & uc_vis >= UCF]
T[status == "evaluated", test_hold := fifelse(qualify & is.finite(alpha_ann_test), alpha_ann_test > 0, NA)]
res <- list(schema = "p1r01_evaluation_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = md5(PR),
            t_alpha_min = TMIN, uc_floor = UCF, table = T, qualified = T[qualify %in% TRUE]$engine)
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "results", "evaluation.json"))
print(T[, .(engine, t_alpha_vis = round(t_alpha_vis, 2), beta_vis = round(beta_vis, 2), uc_vis = round(uc_vis, 3), qualify,
            t_alpha_test = round(t_alpha_test, 2), alpha_ann_test = round(alpha_ann_test, 3), test_hold)])
cat(sprintf("[P1R01 평가] 자격 엔진: %s\n", if (length(res$qualified)) paste(res$qualified, collapse = ",") else "없음"))
