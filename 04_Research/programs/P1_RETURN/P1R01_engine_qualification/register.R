## P1R01 수익 엔진 자격 — 새 측정 축에서 기존 엔진 3종(P0R01 C0 칸 공유)이 '수익 엔진' 자격(β-통제 알파 · 상승 포착)을 갖는가
##   등록부 P1_RETURN decisive_test: "β-통제 알파 t · 상승 포착 · 시험 창 유지 — 행동 카드 + 등급 v3"
##   재료 판단(등록 시점 · 기록): 재료 규칙 'B 이상' 에 맞는 새 엔진 없음 — L1 원장의 B 기저(1403.8125 · 2404.08129)는 지금 엔진 파일이
##     아닌 각색판이었고 현 엔진 파일(충실 재구현판)의 기저 등급은 F(원장 skipped_base_quality). 결합 기저 B 는 C1 표식 계보(S0 진단).
##   ★등록 시점 = P0R01 측정 진행 중 · P0R01 평가 미생성 — 결과를 보지 않고 쓴다.
## 실행: Rscript register.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
PROGRAM <- "P1_RETURN"; ROUND <- "P1R01_engine_qualification"
P <- rx_paths(PROGRAM, ROUND, ROOT)
PR <- file.path(P$prereg_dir, "prereg.json")
if (file.exists(PR)) stop("[P1R01] 사전등록이 이미 있다(R2)")
if (file.exists(file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results/evaluation.json")))
  stop("[P1R01] P0R01 평가가 이미 있다 — 결과를 본 뒤의 사전등록이 된다 · 등록하지 않는다")
P0PR <- file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/prereg.json"); p0 <- fromJSON(P0PR, simplifyVector = FALSE)
TD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
BCJ <- fromJSON(file.path(ROOT, p0$behavior_card_cfg$path), simplifyVector = FALSE)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = "새 측정 축(전 종목 + 위생 · 2000~)에서 기존 수익 엔진의 자격 판정 — P4 조립의 수익 엔진 후보 목록",
  data = list(source_round = "P0R01_feasibility_map", source_prereg_md5 = rk_md5(P0PR), shared_measurement = TRUE,
              cells = c(E1 = "P0R01_E1_C0", E2 = "P0R01_E2_C0", E3 = "P0R01_E3_C0"), p0_evaluation_seen_at_registration = FALSE),
  material_note = paste("재료 규칙(B 이상)에 맞는 새 엔진 없음 — 1403.8125 · 2404.08129 의 원장 B 는 각색판(현 파일 아님) · 현 파일 기저 F ·",
                        "결합 B 는 C1 표식 계보. 새 재료는 충실구현 레인(/alpha-search)으로 확보 — 이 라운드는 그 전의 기준선"),
  tau_d = "2022-12-31",
  metrics = list(t_alpha = "beta_controlled_alpha.R::beta_controlled_alpha — 월간 순수익(행동 카드 bc_monthly) vs KOSPI200 · NW lag 3 · 보는 창",
                 uc = "보는 창 진단 패킷 behavior.summary.bull_up_capture_median", test_alpha = "같은 계약 · 시험 창(2023-01~) alpha_ann"),
  rules = list(qualify = list(text = "보는 창 t(α) ≥ tier_graduation.grade_b_min_portfolio_alpha_t ∧ 보는 창 상승 포착 ≥ uc_floor → '수익 엔진 자격'",
                              t_alpha_min = TD$grade_b_min_portfolio_alpha_t, uc_floor = BCJ$uc_floor),
               test_window = "자격 엔진만: 시험 창 alpha_ann > 0 이면 '유지'(사람 쪽 보고)",
               selection = "선택 없음 — 자격 엔진 목록이 P4 수익 엔진 후보(P4 에서 고를 때 시행 수로 센다)"),
  expectations = list(E1 = "모멘텀은 한국에서 약하다(문헌 · 과거 negative) — 자격 미달 예상", E2 = "자격 경계", E3 = "자격 예상(계보 최고 셀)"),
  budget = list(rounds = 1L, new_measurements = 0L))
dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
dir.create(P$round_dir, recursive = TRUE, showWarnings = FALSE); file.copy(PR, file.path(P$round_dir, "prereg.json"), overwrite = TRUE)
pr_set_status(PROGRAM, "active", reason = sprintf("라운드 %s 사전등록(P0R01 C0 칸 공유 · 엔진 3)", ROUND), root = ROOT)
pr_record_round(PROGRAM, list(round_id = ROUND, prereg = sub(paste0("^", ROOT, "/"), "", PR), prereg_md5 = rk_md5(PR), status = "registered",
                              n_variants = 3L, variants = c("E1", "E2", "E3"), shared_with = "P0R01_feasibility_map"), root = ROOT)
cat(sprintf("[P1R01] 사전등록 %s (md5 %s)\n", PR, rk_md5(PR)))
