## P2R02 방어 장치 교차 엔진 검증 — ★사전등록(R2) · P0R01 측정 칸을 공유한다(새 측정 없음)
##   등록 시점: P0R01 측정 진행 중 · P0R01 결과(평가 파일) 미생성 · 미열람 — 이 사전등록은 결과를 보지 않고 쓴다.
##   등록부 P2_DEFENSE decisive_test: "여러 수익 엔진에 붙였을 때 크기 짝 · 노출 짝 대조보다 위기 낙폭 포착이 낮은 비율이 과반 · 급락형/완만형 위기를 나눠 본다"
## 실행: Rscript register.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
md5 <- function(f) unname(as.character(tools::md5sum(f)))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R02_device_cross_engine"
P <- rx_paths(PROGRAM, ROUND, ROOT)
PR <- file.path(P$prereg_dir, "prereg.json")
if (file.exists(PR)) stop("[P2R02] 사전등록이 이미 있다 — 결과 뒤 재작성 금지(R2)")
P0PR <- file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/prereg.json")
P0EV <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results/evaluation.json")
if (file.exists(P0EV)) stop("[P2R02] P0R01 평가 파일이 이미 있다 — 결과를 본 뒤의 사전등록이 된다(R2 위반 위험) · 등록하지 않는다")
p0 <- fromJSON(P0PR, simplifyVector = FALSE)
BCJ <- fromJSON(file.path(ROOT, p0$behavior_card_cfg$path), simplifyVector = FALSE)
MCJ <- fromJSON(file.path(ROOT, "06_Registry/matched_controls.json"), simplifyVector = FALSE)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = "방어 장치(시변 노출 · 방어적 보유)를 여러 수익 엔진에 걸쳐 검증 — 위기 수 × 엔진 수(등록부 P2_DEFENSE thesis)",
  data = list(source_round = "P0R01_feasibility_map", source_prereg_md5 = md5(P0PR), shared_measurement = TRUE,
              note = "새 측정 없음 · 칸 = P0R01 의 21칸(엔진 E1·E2·E3 × 부품 C0~C6) · 평가 재료 = P0R01 평가가 쓴 보는 창 진단 패킷(results/<칸>/visible)",
              p0_evaluation_seen_at_registration = FALSE),
  tau_d = "2022-12-31", window = "visible(≤ τ_D) — 판정 · 선택 · 교훈은 보는 창만",
  devices = list(C1 = "추세 현금(시변 노출)", C2 = "변동성 타기팅(시변 노출)", C3 = "낙폭 제어(시변 노출)", C4 = "저변동 틸트(방어적 보유)",
                 C5 = "퀄리티 틸트(방어적 보유)", C6 = "추세 현금 + 저변동(결합)"),
  reference = "같은 엔진의 C0(장치 없음)",
  unit = "(엔진, 보는 창 위기) 쌍 — 위기 = 사전등록 행동 카드 설정(LT 20/20 첫 통과 · P0R01 사본)의 보는 창 위기",
  rules = list(
    V1_device_effect = list(text = "장치 칸의 위기 낙폭 포착(dd_capture) < 같은 엔진 C0 의 같은 위기 dd_capture − tol 인 쌍의 비율 > majority_share",
                            tol_source = "matched_controls.json(.MC_TOL 과 같은 값 — 짝 대조 판정 허용오차)", majority_share = BCJ$majority_share),
    V2_beyond_controls = list(text = "장치 칸이 그 위기에서 크기 + 평균 노출 짝 플라시보를 이긴(controls.per_crisis.beats) 쌍의 비율 > majority_share",
                              placebo = list(n = MCJ$placebo$n %||% MCJ$placebo_n %||% NA, alpha = MCJ$placebo$alpha %||% MCJ$placebo_alpha %||% NA)),
    V3_participation = list(text = "장치 칸의 보는 창 상승 포착(bull_up_capture_median) ≥ uc_floor 인 엔진 수 ≥ 엔진 과반(3 중 2)", uc_floor = BCJ$uc_floor),
    verdict = "V1 ∧ V2 ∧ V3 = validated · 아니면 rejected(실패 규칙 코드 기록)",
    crisis_type_split = paste("위기 유형 = 벤치(KOSPI200) 고점→저점 거래일 수가 보는 창 위기들의 중앙값 이하면 급락형 · 초과면 완만형",
                              "(중앙값 = 보는 창 위기만으로 · 새 상수 없음) — V1 · V2 비율을 유형별로도 낸다(판정 아닌 보고 · '전천후' 표식 = 두 유형 모두 과반)")),
  expectations = list(
    C1 = "완만형 위기에서 V1 비율 > 급락형(추세 신호는 시간이 걸린다)",
    C2 = "급락형 위기에서 V1 비율 > 완만형(변동성 급등이 먼저 온다)",
    C3 = "완만형 위기에서 V1 비율 > 급락형(낙폭이 쌓여야 걸린다)",
    C4 = "급락형 위기에서 V1 비율 > 완만형(저베타 보유가 충격을 덜 받는다)",
    C5 = "V1 비율 > 0.5(퀄리티 비행이 위기에 나타난다)",
    C6 = "V1 비율 ≥ max(C1, C4)(두 원천의 결합)"),
  selection = "선택 없음 — 검증된 장치 목록이 P4 조립의 방어 후보가 된다(P4 에서 고를 때 이 라운드 6장치를 시행 수로 센다)",
  budget = list(rounds = 1L, new_measurements = 0L))
dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
dir.create(P$round_dir, recursive = TRUE, showWarnings = FALSE)
file.copy(PR, file.path(P$round_dir, "prereg.json"), overwrite = TRUE)
pr_set_status(PROGRAM, "active", reason = sprintf("라운드 %s 사전등록(P0R01 측정 공유 · 장치 6 × 엔진 3)", ROUND), root = ROOT)
pr_record_round(PROGRAM, list(round_id = ROUND, prereg = sub(paste0("^", ROOT, "/"), "", PR), prereg_md5 = md5(PR), status = "registered",
                              n_variants = 6L, variants = c("C1", "C2", "C3", "C4", "C5", "C6"), shared_with = "P0R01_feasibility_map"), root = ROOT)
cat(sprintf("[P2R02] 사전등록 %s (md5 %s)\n", PR, md5(PR)))
