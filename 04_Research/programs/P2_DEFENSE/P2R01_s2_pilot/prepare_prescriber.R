## P2R01 S2 파일럿 — ② 처방 담당 레인 준비 (분석가 산출 → 처방 담당 재료)
## 실행: Rscript prepare_prescriber.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
P <- rx_paths("P2_DEFENSE", "P2R01_s2_pilot", ROOT)
LA <- P$lane("analyst"); LP <- P$lane("prescriber")

## 분석가 산출 확인 — 실행 성공 · json 요약 · 처방 입력 금지 정보(τ_D 뒤 날짜 · 등급 표기) 없음
rl <- readLines(file.path(LA, "run.log"), warn = FALSE)
if (!any(grepl("^rc=0$", rl))) stop("[prepare_prescriber] 분석가 레인 실패: ", paste(rl, collapse = " | "))
ao <- readLines(file.path(LA, "out.md"), warn = FALSE, encoding = "UTF-8")
aj <- rx_parse_json(ao)
need <- c("edge_sources", "regimes", "strengths_to_preserve", "weakness_hypotheses", "priorities")
miss <- setdiff(need, names(aj)); if (length(miss)) stop("[prepare_prescriber] 분석가 요약 키 누락: ", paste(miss, collapse = ","))
.rx_assert_clean(paste(ao, collapse = "\n"), ROOT, "analyst_report")
wids <- vapply(aj$weakness_hypotheses, function(z) as.character(z$id), character(1))
cat("분석가 약점 가설:", paste(wids, collapse = ", "), "\n")

FIELDS <- c("performance.strategy.cagr", "performance.strategy.mdd", "performance.strategy.calmar", "performance.strategy.sharpe",
            "performance.strategy.port_t", "behavior.summary.crisis_dd_capture_median", "behavior.summary.crisis_dd_capture_worst",
            "behavior.summary.bull_up_capture_median", "behavior.summary.share_crisis_strong", "behavior.summary.share_crisis_weak",
            "behavior.summary.mdd_vs_bench", "behavior.summary.asymmetry", "behavior.stats.beta", "behavior.stats.beta_down",
            "behavior.stats.beta_up", "behavior.stats.cdar", "behavior.rolling.pass_life", "controls.attribution.share_beats_size_exposure",
            "controls.attribution.share_beats_exposure", "controls.attribution.median_placebo_p", "controls.exposure_profile.mean",
            "profile.turnover_annual", "profile.cost_drag_annual", "profile.eff_n_mean")
writeLines(FIELDS, file.path(P$round_dir, "falsification_fields.txt"))

prompt <- paste0(
"# 역할: 처방 루프 v0 — ② 처방 담당 (청정 레인 · 읽기 전용)

당신은 **처방 담당**이다. 분석가의 「전략 이해서」(analyst_report.md)와 진단 패킷을 읽고,
이 전략의 **위기 방어를 고치는 처방전 1~3건**을 쓴다. 처방은 이 전략의 강점(알파)을 지키면서 위기 하락 포착을 낮추고
강세 참여(상승 포착 ≥ 0.55)를 유지하는 것을 겨냥한다 — charter.md 의 투자철학과 등급 산식이 목표다.

## 재료 — 아래 작업 디렉터리 안의 파일만 읽는다
작업 디렉터리: ", LP, "
- analyst_report.md — 분석가의 「전략 이해서」(약점 가설 W1… 포함)
- diagnosis_packet.md / .json — 기저 진단(보는 창 2005-02 ~ 2022-12 만 · R 계약 산출). 1절 '축'이 기저의 현재 셀 사양이다.
- charter.md — 투자철학 · 등급 산식 · 정보 경계 · 리서치 규칙
- toolbox.md — 처방 구현에 쓸 수 있는 축 어휘(이것 밖은 구현 불가)
- paper.pdf · paper_engine.R — 논문과 신호 구현

## 처방 규칙
1. 구현은 toolbox.md 의 축(factors · weighting · universe · rebalance · overlay · defense_sleeve · cap_core)의 값으로만 쓴다.
   기저 셀 사양에서 **바꿀 축만** 적는다(나머지는 기저 그대로). 고정 축은 바꿀 수 없다.
   factors 를 적으면 그 목록이 기저의 결합 팩터 목록을 **대체**한다(빈 목록 = 논문 신호만).
2. 처방끼리 **서로 다른 기전**이어야 한다. 같은 기전의 파라미터만 바꾼 변형을 여러 건 내지 마라(측정한 변형 수는 시행 회계 → 등급 DSR).
3. 각 처방은 분석가의 약점 가설(W id) 하나 이상을 겨냥하고, 지켜야 할 강점과 그 확인 방법을 명시한다.
4. 기대 방향은 행동 카드 지표로 적는다(위기 하락 포착 · 상승 포착 · Calmar · PORT_t · 크기·노출 짝 귀속). 크기는 대략의 범위로 —
   **수치를 새로 계산하지 말고** 패킷 수치를 기준점으로 인용하라.
5. **반증 조건은 기계 판정 형식**으로 쓴다(측정 후 R 이 처방 변형의 보는 창 패킷으로 판정한다 — 하나라도 참이면 그 처방은 기각).
   형식: {\"field\": \"<아래 필드 경로>\", \"op\": \"<\"|\"<=\"|\">\"|\">=\", \"value\": <숫자>} 또는
   {\"field\": \"<필드>\", \"op\": \"...\", \"ref\": \"base\", \"delta\": <숫자>}  (= 처방 값 op (기저 값 + delta) 이면 기각)
   쓸 수 있는 필드: ", paste(FIELDS, collapse = " · "), "
6. **최종 후보 선택 규칙**: 측정 후 반증을 통과한 처방 중 최대 1개를 고르는 규칙 — 보는 창 정보만. 원시 최댓값 하나만 보지 말고
   개선이 여러 위기에 걸쳐 있는지(지속성) · 강점 보존을 함께 보라.
7. 2023년 이후 정보 · 사전학습으로 아는 사건은 근거로 쓰지 마라. 이 저장소의 다른 실험 결과를 추측하지 마라.

## 산출 — 처방전(한국어 · 마크다운)
처방마다: id · 이름 · 겨냥 약점(W id) · 기전(왜 고쳐지나 — 논문 · 패킷 근거) · 구현(delta) · 기대 방향 · 보존할 강점과 확인 지표 · 반증 조건 · 위험.

응답 맨 끝에 반드시 ```json 블록 하나(키 이름 그대로):
```json
{\"prescriptions\": [{\"id\": \"RX1\", \"name\": \"...\", \"targets\": [\"W1\"], \"mechanism\": \"...\",
   \"implementation\": {\"overlay\": {\"kind\": \"...\", \"arm_id\": \"...\"}},
   \"expected\": {\"crisis_dd_capture\": \"...\", \"bull_up_capture\": \"...\", \"calmar\": \"...\", \"port_t\": \"...\", \"mc8\": \"...\"},
   \"preserve\": [{\"what\": \"...\", \"check\": \"<필드>\"}],
   \"falsification\": [{\"field\": \"behavior.summary.bull_up_capture_median\", \"op\": \"<\", \"value\": 0.55}],
   \"risks\": [\"...\"]}],
 \"final_selection_rule\": \"...\",
 \"notes\": \"...\"}
```
")
writeLines(ao, file.path(P$round_dir, "analyst_report.md"), useBytes = TRUE)
rx_prepare_lane(LP, files = list(`analyst_report.md` = file.path(LA, "out.md"),
                                 `diagnosis_packet.md` = file.path(LA, "diagnosis_packet.md"),
                                 `diagnosis_packet.json` = file.path(LA, "diagnosis_packet.json"),
                                 `charter.md` = file.path(LA, "charter.md"), `toolbox.md` = file.path(LA, "toolbox.md"),
                                 `paper.pdf` = file.path(LA, "paper.pdf"), `paper_engine.R` = file.path(LA, "paper_engine.R")),
                prompt = prompt, root = ROOT)
cat("lane:", LP, "\n"); print(list.files(LP))
