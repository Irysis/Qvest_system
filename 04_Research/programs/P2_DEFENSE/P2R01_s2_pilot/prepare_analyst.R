## P2R01 S2 파일럿 — ① 분석가 레인 준비 (2026-10-13 · 처방 루프 v0 · 도훈 결정 GRADE-V3-PROMOTE ③ 출발점 = 2002.06975 계보)
## 기저 = 2002.06975 계보 B6_36(close_t1 재측정 · C1 표식 없음 · ⚠ automem 노출 표식 'possible' → 이 계보 A 는 보류 정책)
## 실행: Rscript prepare_analyst.R   (저장소 루트 무관 — 절대경로)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/programs/rx_round.R")

P <- rx_paths("P2_DEFENSE", "P2R01_s2_pilot", ROOT)
BASE_DIR  <- file.path(ROOT, "stage_artifacts/replication/20260923_205641_8212")
BASE_SPEC <- file.path(ROOT, ".cache/rf_parallel/spec_B6_36__RP_20260913_084807_skipped_base_promo1.json")
PAPER_PDF <- file.path(ROOT, "01_Literature/Alpha_Search_Recharge/20260830/mcp_arxiv/MCP_2002_06975.pdf")
PAPER_ENG <- file.path(ROOT, "04_Research/strategies/RP_AUTO_2002_06975/engine.R")

## 기저 진단 패킷(보는 창만) — 라운드 정본 사본 + 레인 사본
pk <- dp_build(BASE_DIR, root = ROOT, cell_spec = BASE_SPEC)
dp_write(pk, file.path(P$round_dir, "base"))
LANE <- P$lane("analyst")
dp_write(pk, LANE)
file.copy(BASE_SPEC, file.path(P$round_dir, "base", "base_cell_spec.json"), overwrite = TRUE)

toolbox <- rx_toolbox_md(ROOT); charter <- rx_charter_md(pk, ROOT)
writeLines(enc2utf8(toolbox), file.path(P$round_dir, "toolbox.md"), useBytes = TRUE)
writeLines(enc2utf8(charter), file.path(P$round_dir, "charter.md"), useBytes = TRUE)

prompt <- paste0(
"# 역할: 처방 루프 v0 — ① 전략 분석가 (청정 레인 · 읽기 전용)

당신은 한국 주식 롱온리 전략의 **전략 분석가**다. 목표는 다음 단계의 처방 담당이 이 전략의 위기 방어를 고칠 수 있도록
**전략을 이해하는 문서(「전략 이해서」)**를 쓰는 것이다. 처방(무엇을 바꿀지)은 고르지 않는다 — 그것은 다음 단계다.

## 재료 — 아래 작업 디렉터리 안의 파일만 읽는다(그 밖은 읽기 가드가 막는다)
작업 디렉터리: ", LANE, "
- paper.pdf — 원논문(arXiv 2002.06975 · 딥러닝 횡단면 주가 예측 · 실제 운용 관점)
- paper_engine.R — 이 저장소의 논문 신호 구현(충실구현 엔진 · 성과 수치 없음 · 특성 정의 · 모델 · 학습 창)
- diagnosis_packet.md (읽기용) · diagnosis_packet.json (같은 내용 전체) — 이 전략(기저 칸)의 진단.
  **보는 창 ", pk$window[1], " ~ ", pk$window[2], " 만** 담았고, 모든 수치는 R 계약이 계산했다.
- charter.md — 투자철학 · 등급 산식 · 정보 경계 · 리서치 규칙(반드시 먼저 읽어라)
- toolbox.md — 처방이 바꿀 수 있는 축 어휘(참고용)

## 절대 규칙
1. **수치를 새로 계산 · 추정하지 마라.** 패킷의 수치만 인용하고 출처(패킷의 절 · 표 · 필드)를 밝혀라. 필요한 수치가 없으면 \"측정 필요: <무엇>\" 이라고 적어라.
2. **2023년 이후의 시장 사건 · 성과는 사전학습으로 알더라도 근거로 쓰지 마라.** 위기 분석은 패킷의 위기들로만 한다.
3. 이 저장소의 다른 실험 · 다른 전략의 결과를 추측하지 마라(당신은 볼 수 없고, 보아서도 안 된다).
4. 파일을 쓰지 마라(쓰기 도구가 없다). 산출은 최종 응답 하나다.

## 산출 — 「전략 이해서」(한국어 · 마크다운)
1. **엣지의 원천** — 논문 기전(무엇을 예측하나 · 입력 특성 · 학습 방식) + 이 칸의 구성(결합 팩터 · 비중 · 리밸)
   + 패킷의 노출 분해(선택 · 크기 · 시장 성분의 몫)로 본 실제 초과수익 원천.
2. **작동/실패 국면** — 위기마다: 무엇이 낙폭을 냈나(성분 합 · 손실 상위 종목의 업종 · 크기 분위 · 업종 손실) · 하락 포착률과 크기·노출 짝 대비 위치.
   강세장 참여(상승 포착) · 연도별 수익에서 보이는 정체 구간.
3. **지켜야 할 강점** — 처방이 훼손하면 안 되는 것과 그것을 확인할 지표(패킷 필드로).
4. **약점 가설 2~4개** — 각각 {주장 · 근거(패킷 수치 인용) · 반증 조건(어떤 측정 결과가 나오면 이 가설이 틀렸다고 볼 것인가)}.
   크기 방어 · 노출 방어 착시와 실제 방어를 구분하라(패킷의 MC8 귀속 · 무작위 크기 짝 분위 참고).
5. **처방 담당에게** — 고칠 곳의 우선순위와 이유, 피해야 할 함정(예: 정적 노출 축소는 상승 포착을 같이 깎는다 · 노출을 줄였을 뿐인 방어는 '노출 방어'로 기록된다).

응답 맨 끝에 반드시 ```json 블록 하나로 구조화 요약을 붙여라(키 이름 그대로):
```json
{\"edge_sources\": [\"...\"],
 \"regimes\": {\"works\": [\"...\"], \"fails\": [\"...\"]},
 \"strengths_to_preserve\": [{\"what\": \"...\", \"check\": \"패킷 필드/지표\"}],
 \"weakness_hypotheses\": [{\"id\": \"W1\", \"claim\": \"...\", \"evidence\": [\"패킷 인용\"], \"falsifiable_by\": \"...\"}],
 \"priorities\": [\"W?\", \"...\"]}
```
")
rx_prepare_lane(LANE, files = list(`paper.pdf` = PAPER_PDF, `paper_engine.R` = PAPER_ENG,
                                   `toolbox.md` = I(toolbox), `charter.md` = I(charter)), prompt = prompt)
cat("lane:", LANE, "\n"); print(list.files(LANE))
cat("τ_D 초과 날짜(패킷):", length(dp_scan_dates(pk[setdiff(names(pk), c("created_at", "tau_d"))], pk$tau_d)), "\n")
