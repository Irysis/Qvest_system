## P4R01 — ② 처방 담당 레인 준비(분석가 산출 → 처방 담당 재료) · 최종 선택 규칙은 기계 판정 형식(JSON)으로 받는다
## 실행: Rscript prepare_prescriber.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/programs/rx_round.R")
P <- rx_paths("P4_ASSEMBLY", "P4R01_skeleton_rx", ROOT)
LA <- P$lane("analyst"); LP <- P$lane("prescriber")
rl <- readLines(file.path(LA, "run.log"), warn = FALSE)
if (!any(grepl("^rc=0$", rl))) stop("[P4R01] 분석가 레인 실패: ", paste(rl, collapse = " | "))
ao <- readLines(file.path(LA, "out.md"), warn = FALSE, encoding = "UTF-8")
aj <- rx_parse_json(ao)
miss <- setdiff(c("edge_sources", "regimes", "strengths_to_preserve", "weakness_hypotheses", "priorities"), names(aj))
if (length(miss)) stop("[P4R01] 분석가 요약 키 누락: ", paste(miss, collapse = ","))
.rx_assert_clean(paste(ao, collapse = "\n"), ROOT, "analyst_report")
writeLines(ao, file.path(P$round_dir, "analyst_report.md"), useBytes = TRUE)
FIELDS <- c("performance.strategy.cagr", "performance.strategy.mdd", "performance.strategy.calmar", "performance.strategy.sharpe",
            "performance.strategy.port_t", "behavior.summary.crisis_dd_capture_median", "behavior.summary.crisis_dd_capture_worst",
            "behavior.summary.crisis_cum_capture_median", "behavior.summary.bull_up_capture_median", "behavior.summary.share_crisis_strong",
            "behavior.summary.share_crisis_weak", "behavior.summary.mdd_vs_bench", "behavior.summary.asymmetry", "behavior.stats.beta",
            "behavior.stats.beta_down", "behavior.stats.beta_up", "behavior.stats.cdar", "behavior.rolling.pass_life",
            "controls.attribution.share_beats_size_exposure", "controls.attribution.share_beats_exposure", "controls.attribution.median_placebo_p",
            "controls.exposure_profile.mean", "profile.turnover_annual", "profile.cost_drag_annual", "profile.eff_n_mean")
writeLines(FIELDS, file.path(P$round_dir, "falsification_fields.txt"))
FIELD_MAP <- paste(
"| 필드 | diagnosis_packet.md 의 자리 | 단위 |", "|---|---|---|",
"| performance.strategy.cagr · .calmar · .sharpe · .port_t | 2절 성과 표(전략 열) | CAGR = 소수(0.202 = 20.2%) |",
"| performance.strategy.mdd | 2절 최대낙폭 | **양수 소수** |",
"| behavior.summary.crisis_dd_capture_median · _worst · crisis_cum_capture_median | 3절 하락 포착 · 누적 포착 | 비율 |",
"| behavior.summary.bull_up_capture_median | 3절 강세 상승 포착 중앙 | 비율 |",
"| behavior.summary.mdd_vs_bench · share_crisis_strong · share_crisis_weak · asymmetry | 3절(일부 md 에 없음 — 카드 정의) | 비율 |",
"| behavior.stats.beta · beta_down · beta_up · cdar | 3절 베타 · CDaR | — · CDaR 양수 소수 |",
"| behavior.rolling.pass_life | 3절 롤링 통과율 | 소수 |",
"| controls.attribution.share_beats_size_exposure · share_beats_exposure · median_placebo_p | 3절 크기·노출 짝 귀속 | 소수 |",
"| controls.exposure_profile.mean | 3절 평균 노출 | — |",
"| profile.turnover_annual · cost_drag_annual · eff_n_mean | 5절 | — |", sep = "\n")
prompt <- paste0(
"# 역할: 조립 · 처방 루프 1라운드 — ② 처방 담당 (청정 레인 · 읽기 전용)

당신은 **처방 담당**이다. 분석가의 「전략 이해서」(analyst_report.md)와 진단 패킷을 읽고, 이 골격의 빈칸을 채우는 **처방전 1~3건**을 쓴다.
목표: 강점(알파 · 강세 참여)을 지키며 종합점수 S ≥ 1 과 하한(charter.md 2절)에 다가간다 — 위기 하락 포착을 낮추고 상승 포착 ≥ 0.55 를 유지한다.

## 재료 — 작업 디렉터리 안의 파일만
작업 디렉터리: ", LP, "
- analyst_report.md · diagnosis_packet.md(보는 창만 · R 계약 산출 · 1절 '축' = 골격의 현재 셀 사양) · charter.md · toolbox.md(이것 밖은 구현 불가)
- program_notes.md — 같은 측정 축의 방어 장치 교차 엔진 검증 · 구성 지도(보는 창 수치만)
- engine_note.md(엔진 설명)

## 처방 규칙
1. 구현은 toolbox.md 의 축(factors · weighting · universe · rebalance · overlay · defense_sleeve · cap_core)의 값으로만 — 골격 셀 사양에서 **바꿀 축만** 적는다.
   factors 를 적으면 그 목록이 골격의 결합 팩터 목록을 **대체**한다(빈 목록 = 엔진 신호만). overlay 를 적으면 골격의 오버레이를 **대체**한다(층 목록 가능).
2. 처방끼리 **서로 다른 기전** — 같은 기전의 파라미터 변형을 여러 건 내지 마라(시행 회계 → DSR). 한 기전 = 가능한 한 한 축.
3. 각 처방은 약점 가설(W id) 하나 이상을 겨냥하고, 지킬 강점과 확인 지표를 명시한다.
4. 기대 방향은 행동 카드 지표로 · 수치를 새로 계산하지 말고 패킷 수치를 기준점으로 인용하라.
5. **반증 조건은 기계 판정 형식** — 하나라도 참이면 그 처방은 기각(측정 후 R 이 처방 변형의 보는 창 패킷으로 판정):
   {\"field\": \"<필드>\", \"op\": \"<\"|\"<=\"|\">\"|\">=\", \"value\": <숫자>} 또는 {\"field\": \"<필드>\", \"op\": \"...\", \"ref\": \"base\", \"delta\": <숫자>}
   (ref = base → 처방 값 op (골격 값 + delta) 이면 기각 · 골격 = 같은 데이터 판본으로 잰 골격 칸) · 쓸 수 있는 필드:
", FIELD_MAP, "
6. **최종 후보 선택 규칙도 기계 판정 형식**으로 — 반증을 통과한 처방 중 최대 1개(보는 창 정보만):
   {\"primary\": \"<필드>\", \"direction\": \"max\"|\"min\", \"require\": [<반증 규칙과 같은 형식 — 모두 참이어야 후보>],
    \"tie_eps\": <숫자>, \"tie_break\": \"<필드>\", \"tie_direction\": \"max\"|\"min\"}
   원시 최댓값 하나에 기대지 말고 require 에 지속성 · 강점 보존 조건을 넣어라(예: 상승 포착 하한 · 위기 강함 비율).
7. 2023년 이후 정보 · 사전학습으로 아는 사건은 근거로 쓰지 마라. 이 저장소의 다른 실험 결과를 추측하지 마라.

## 산출 — 처방전(한국어 · 마크다운) + 맨 끝 ```json 블록 하나(키 이름 그대로):
```json
{\"prescriptions\": [{\"id\": \"RX1\", \"name\": \"...\", \"targets\": [\"W1\"], \"mechanism\": \"...\",
   \"implementation\": {\"overlay\": {\"kind\": \"...\", \"arm_id\": \"...\"}},
   \"expected\": {\"crisis_dd_capture\": \"...\", \"bull_up_capture\": \"...\", \"calmar\": \"...\", \"port_t\": \"...\", \"mc8\": \"...\"},
   \"preserve\": [{\"what\": \"...\", \"check\": \"<필드>\"}],
   \"falsification\": [{\"field\": \"behavior.summary.bull_up_capture_median\", \"op\": \"<\", \"value\": 0.55}],
   \"risks\": [\"...\"]}],
 \"final_selection\": {\"primary\": \"performance.strategy.calmar\", \"direction\": \"max\", \"require\": [], \"tie_eps\": 0.02,
                       \"tie_break\": \"behavior.summary.crisis_cum_capture_median\", \"tie_direction\": \"min\"},
 \"notes\": \"...\"}
```
")
AL <- list.files(LA, full.names = TRUE)
files <- list(`analyst_report.md` = file.path(LA, "out.md"), `diagnosis_packet.md` = file.path(P$round_dir, "base", "diagnosis_packet.md"),
              `charter.md` = file.path(P$round_dir, "charter.md"), `toolbox.md` = file.path(P$round_dir, "toolbox.md"),
              `program_notes.md` = file.path(LA, "program_notes.md"), `engine_note.md` = file.path(LA, "engine_note.md"))
if (file.exists(file.path(LA, "paper.txt"))) files[["paper.txt"]] <- file.path(LA, "paper.txt")
unlink(LP, recursive = TRUE)
rx_prepare_lane(LP, files = files, prompt = prompt, root = ROOT)
cat("lane:", LP, "\n"); print(list.files(LP))
