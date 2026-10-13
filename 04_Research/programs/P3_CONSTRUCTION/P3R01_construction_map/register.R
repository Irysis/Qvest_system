## P3R01 구성 지도 — 같은 엔진에서 구성(비중 · 회전)만 바꿔 CDaR · 종합점수 · 시험 창 유지가 나아지는가
##   등록부 P3_CONSTRUCTION thesis/decisive_test · 기준 칸(EW) = P0R01 의 E1_C0 · E2_C0 측정 재사용(같은 축 · 같은 판본)
##   ★등록 시점 = P0R01 측정 진행 중 · P0R01 평가 미생성 — 결과를 보지 않고 쓴다(파일 존재로 확인)
## 실행: Rscript register.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
PROGRAM <- "P3_CONSTRUCTION"; ROUND <- "P3R01_construction_map"
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
PR <- file.path(P$prereg_dir, "prereg.json")
if (file.exists(PR)) stop("[P3R01] 사전등록이 이미 있다(R2)")
if (file.exists(file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results/evaluation.json")))
  stop("[P3R01] P0R01 평가가 이미 있다 — 결과를 본 뒤의 사전등록이 된다 · 등록하지 않는다")
EP <- ma_epoch(root = ROOT)
P0PR <- file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/prereg.json"); p0 <- fromJSON(P0PR, simplifyVector = FALSE)
P0SP <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs")
ENGINES <- list(E1 = list(ref = "P0R01_E1_C0", n_prior = p0$selection_accounting$E1),
                E2 = list(ref = "P0R01_E2_C0", n_prior = p0$selection_accounting$E2))
VAR <- list(
  K1 = list(name = "역변동성 비중", delta = list(weighting = list(kind = "catalog", catalog_id = "lean:ivol", label = "ivol")),
            basis = "Kirby & Ostdiek (2012) It's All in the Timing, JFQA 47(2) doi:10.1017/S0022109012000117"),
  K2 = list(name = "최소분산 비중", delta = list(weighting = list(kind = "catalog", catalog_id = "lean:minvar", label = "minvar")),
            basis = "Clarke, de Silva & Thorley (2006) Minimum-Variance Portfolios in the U.S. Equity Market, JPM 33(1) doi:10.3905/jpm.2006.661366"),
  K3 = list(name = "낙폭 제약(CDaR LP) 비중", delta = list(weighting = list(kind = "catalog", catalog_id = "qepm:CDaR_LP", label = "CDaR_LP")),
            basis = "Chekhlov, Uryasev & Zabarankin (2005) Drawdown Measure in Portfolio Optimization, IJTAF 8(1) doi:10.1142/S0219024905002767"),
  K4 = list(name = "켈리(성장 최적) 비중", delta = list(weighting = list(kind = "catalog", catalog_id = "lean:kelly", label = "kelly")),
            basis = "Busseti, Ryu & Boyd (2016) Risk-Constrained Kelly Gambling, J. Investing 25(3) arXiv:1603.06183"),
  K5 = list(name = "순위 버퍼 2배(회전 통제)", delta = list(rebalance = list(kind = "rank_buffer", mult = 2)),
            basis = "Novy-Marx & Velikov (2016) A Taxonomy of Anomalies and Their Trading Costs, RFS 29(1) doi:10.1093/rfs/hhv063"))
N_ROUND <- length(ENGINES) * length(VAR)
cells <- list(); bad <- character(0)
for (eid in names(ENGINES)) {
  e <- ENGINES[[eid]]
  b <- fromJSON(file.path(P0SP, paste0(e$ref, ".json")), simplifyVector = FALSE)   # P0R01 기준 칸 사양(측정 축 표식 포함)
  nf <- as.integer(e$n_prior + N_ROUND)
  SA <- list(selection_type = "sweep", family_root = b$selection_accounting$family_root,
             lineage = c(paste0("RX_", ROUND), unlist(b$selection_accounting$lineage)),
             n_family_at_registration = nf,
             n_trials_basis = sprintf("P3R01: P0R01 회계 %d + 이 라운드 %d(엔진 %d × 구성 %d)", as.integer(e$n_prior), N_ROUND, length(ENGINES), length(VAR)))
  for (k in names(VAR)) {
    d <- VAR[[k]]$delta; code <- sprintf("P3R01_%s_%s", eid, k)
    v <- rx_validate(d, ROOT); if (!isTRUE(v$ok)) { bad <- c(bad, sprintf("%s: %s", code, paste(v$errors, collapse = " | "))); next }
    sp <- rx_compile_spec(b, d, code = code, label = sprintf("%s × %s", eid, VAR[[k]]$name),
                          idea = sprintf("[P3R01 구성 지도 · %s × %s] %s", eid, k, VAR[[k]]$basis), selection_accounting = SA, epoch = EP, root = ROOT)
    f <- file.path(P$specs_dir, paste0(code, ".json"))
    cells[[code]] <- list(code = code, engine = eid, component = k, path = sub(paste0("^", ROOT, "/"), "", f),
                          md5 = rc <- { dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
                                        writeLines(toJSON(sp, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE); rk_md5(f) },
                          n_family = nf)
  }
}
if (length(bad)) stop("[P3R01] 검증 실패:\n", paste(bad, collapse = "\n"))
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json"); file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = TRUE)
TD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
GV <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = "구성(비중 · 회전)만 바꿨을 때 낙폭 제약 아래 복리가 나아지는가 — 등록부 P3_CONSTRUCTION",
  measurement_axis = list(epoch = EP$id), tau_d = "2022-12-31",
  reference_cells = list(E1 = list(code = "P0R01_E1_C0", round = "P0R01_feasibility_map"), E2 = list(code = "P0R01_E2_C0", round = "P0R01_feasibility_map")),
  variants = lapply(VAR, function(v) list(name = v$name, delta = v$delta, basis = v$basis)),
  cells = unname(cells),
  rules = list(
    improve = "칸이 같은 엔진 기준(EW · P0R01 C0)보다 보는 창 CDaR(behavior.stats.cdar) 낮음 ∧ 보는 창 S_vis ≥ 기준 S_vis",
    program_verdict = "두 엔진 모두에서 improve 인 구성 변형이 하나라도 있으면 '구성 레버 있음' · 없으면 '이 엔진들에선 EW 를 넘는 구성 없음'",
    selection = "두 엔진 모두 improve 인 변형 중 두 엔진 평균 S_vis 최대(동률 < tie_eps → 평균 CDaR 낮은 쪽) · 없으면 EW 유지(선택 없음)",
    test_window = "선택 변형만: 시험 창 Calmar(gv3_window) · 전기간 카드 CDaR 를 기준과 비교(사람 쪽 보고 · 선택 규칙 입력 아님)"),
  expectations = list(K1 = "CDaR ↓ · CAGR ≈", K2 = "CDaR ↓ · CAGR ↓", K3 = "CDaR ↓(직접 표적)", K4 = "CAGR ↑ · CDaR ↑(성장 최적은 낙폭을 키울 수 있다)", K5 = "회전 · 비용 ↓ · S_vis ↑"),
  final_selection_rule = list(calmar_norm = TD$min_calmar, port_t_norm = TD$min_portfolio_alpha_t_nw, w_calmar = GV$weights$calmar, w_port_t = GV$weights$port_t, tie_eps = 0.02),
  axis_audit = "측정 뒤 04_holdings 실보유가 롱온리 · ≤ max_names · Σw ≤ 1 — 위반 칸 = 측정 무효",
  behavior_card_cfg = list(path = sub(paste0("^", ROOT, "/"), "", BCP), md5 = rk_md5(BCP)),
  budget = list(variants = N_ROUND, rounds = 1L))
dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
file.copy(PR, file.path(RD, "prereg.json"), overwrite = TRUE)
pr_set_status(PROGRAM, "active", reason = sprintf("라운드 %s 사전등록(%d칸 · 기준 = P0R01 EW 칸)", ROUND, length(cells)), root = ROOT)
pr_record_round(PROGRAM, list(round_id = ROUND, prereg = sub(paste0("^", ROOT, "/"), "", PR), prereg_md5 = rk_md5(PR), status = "registered",
                              n_variants = length(cells), variants = unname(vapply(cells, function(z) z$code, character(1)))), root = ROOT)
cat(sprintf("[P3R01] 사전등록 %s (md5 %s) · 칸 %d\n", PR, rk_md5(PR), length(cells)))
