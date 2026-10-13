## P4R01 조립 · 처방 루프 1라운드 — ① 분석가 레인 준비
##   골격 = P0R01 선택 칸(사전등록 선택 규칙 · 보는 창 S_vis 최대) · 재료 = 보는 창 진단 패킷(md) · 헌장 · 도구 상자 · 엔진 설명 ·
##   프로그램 메모(P2R02 검증 장치 · P3R01 구성 — 보는 창 수치만 · 등급 표기 없음)
## 실행: Rscript prepare_analyst.R   (P0 미도달이면 멈춘다 — 등록부 P4 blocked_by P0)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/programs/rx_round.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
P <- rx_paths("P4_ASSEMBLY", "P4R01_skeleton_rx", ROOT)
P0D <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
ev <- fromJSON(file.path(P0D, "results/evaluation.json"), simplifyVector = FALSE)
if (!identical(ev$decisive$verdict, "reached")) stop("[P4R01] P0 미도달 — P4 차단(등록부 blocked_by P0_FRONTIER)")
SEL <- ev$decisive$selected$code; ENG <- ev$decisive$selected$engine; CMP <- ev$decisive$selected$component
BASE_RES <- file.path(P0D, "results", SEL)
dir.create(file.path(P$round_dir, "base"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(P0D, "specs", paste0(SEL, ".json")), file.path(P$round_dir, "base", "base_cell_spec.json"), overwrite = TRUE)
for (f in c("diagnosis_packet.md", "diagnosis_packet.json")) file.copy(file.path(BASE_RES, "visible", f), file.path(P$round_dir, "base", f), overwrite = TRUE)
pk <- fromJSON(file.path(BASE_RES, "visible", "diagnosis_packet.json"), simplifyVector = FALSE)
toolbox <- rx_toolbox_md(ROOT); charter <- rx_charter_md(pk, ROOT)
writeLines(enc2utf8(toolbox), file.path(P$round_dir, "toolbox.md"), useBytes = TRUE)
writeLines(enc2utf8(charter), file.path(P$round_dir, "charter.md"), useBytes = TRUE)

## 엔진 설명(성과 수치 없음)
eng_note <- switch(ENG,
  E1 = paste("# 엔진 — 모멘텀 12-1(문헌 표준)", "",
             "- 신호 = 종목별 (21거래일 전 종가 / 252거래일 전 종가 − 1) — 최근 1개월을 건너뛴 12개월 수익률(Jegadeesh & Titman 1993 · JF 48(1)).",
             "- 셀 엔진 내장 신호(rf_cell_engine.R · shift 21/252 — 신호일 당일 값 미사용).", "- 상위 25종(유동성 하한 · 측정 유니버스 안) 동일가중 · 월말 신호 · 다음 거래일 종가 체결.", sep = "\n"),
  paste("# 엔진 — 2002.06975 DNN(Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment Management)", "",
        "- 논문 엔진 = 04_Research/strategies/RP_AUTO_2002_06975/engine.R(paper_engine.R 사본) — 31개 특성 · DNN5 · 5거래일 갱신 · 최근 1,000 실현 세트 학습.",
        "- 엔진은 그날 적격 종목 전부의 DNN 예측 점수(순위 척도)와 롱숏 분위 비중을 함께 낸다 — 셀 엔진은 예측 점수를 기저 신호로 쓴다(상위 25 = 예측 점수 상위).",
        if (identical(ENG, "E3")) "- 이 칸(B6_36)은 기저 신호에 팩터 3개(12-1 모멘텀 · FCF 수익률 · 잔차 모멘텀)를 rank-z 결합(기저 가중 0.5) · 엔트로피 비중 · 순위 버퍼 2배." else "",
        sep = "\n"))
cmp_note <- c(C0 = "부품 없음", C1 = "추세 현금 규칙(시장 12개월 수익 부호 < 0 → 현금 · 오버레이 ts_mom_sign)", C2 = "변동성 타기팅(오버레이 vol_median)",
              C3 = "낙폭 제어(오버레이 dd_brake_q)", C4 = "저변동 틸트(팩터 D03_RealVol 결합)", C5 = "퀄리티 틸트(팩터 Q08_Composite_Quality 결합)",
              C6 = "추세 현금 + 저변동 틸트(오버레이 ts_mom_sign · 팩터 D03_RealVol)")[[CMP]]

## 프로그램 메모 — P2R02 · P3R01(보는 창 수치만 · 등급 · 시험 창 없음)
pm <- c("# 프로그램 메모 — 같은 측정 축의 다른 라운드 결과(보는 창만)", "")
p2 <- tryCatch(fromJSON(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R02_device_cross_engine/results/evaluation.json"), simplifyVector = TRUE), error = function(e) NULL)
if (!is.null(p2)) {
  V <- as.data.table(p2$devices)
  pm <- c(pm, "## 방어 장치 교차 엔진 검증(엔진 3종 × 보는 창 위기)", "",
          "| 장치 | 엔진 단독보다 덜 빠진 (엔진×위기) 비율 | 크기+노출 짝 플라시보를 넘은 비율 | 상승 포착 하한 유지 엔진 | 급락형 / 완만형 |", "|---|---|---|---|---|",
          vapply(seq_len(nrow(V)), function(i) with(V[i], sprintf("| %s | %.2f | %.2f | %d/%d | %.2f / %.2f |", device, v1_share, v2_share, n_uc_ok, n_eng, v1_crash, v1_grind)), character(1)),
          "", "- 장치 기호: C1 추세 현금 · C2 변동성 타기팅 · C3 낙폭 제어 · C4 저변동 틸트 · C5 퀄리티 틸트 · C6 추세+저변동")
}
p3 <- tryCatch(fromJSON(file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map/results/evaluation.json"), simplifyVector = TRUE), error = function(e) NULL)
if (!is.null(p3)) {
  T3 <- as.data.table(p3$table)
  pm <- c(pm, "", "## 구성(비중 · 회전) 지도 — 같은 엔진 동일가중 대비(보는 창 CDaR · 종합점수 S)", "",
          "| 엔진 | 구성 | CDaR | 기준 CDaR | S | 기준 S |", "|---|---|---|---|---|---|",
          vapply(seq_len(nrow(T3)), function(i) with(T3[i], sprintf("| %s | %s | %.3f | %.3f | %.3f | %.3f |", engine, variant, cdar, cdar0, S_vis, S0)), character(1)),
          "", "- 구성 기호: K0 동일가중 · K1 역변동성 · K2 최소분산 · K3 낙폭 제약(CDaR LP) · K4 켈리 · K5 순위 버퍼 2배")
}
pm_txt <- paste(pm, collapse = "\n")

LANE <- P$lane("analyst")
files <- list(`diagnosis_packet.md` = file.path(BASE_RES, "visible", "diagnosis_packet.md"),
              `toolbox.md` = I(toolbox), `charter.md` = I(charter), `engine_note.md` = I(eng_note), `program_notes.md` = I(pm_txt))
if (ENG %in% c("E2", "E3")) {
  files[["paper.txt"]] <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/paper_2002_06975.txt")
  files[["paper_engine.R"]] <- file.path(ROOT, "04_Research/strategies/RP_AUTO_2002_06975/engine.R")
}
prompt <- paste0(
"# 역할: 조립 · 처방 루프 1라운드 — ① 전략 분석가 (청정 레인 · 읽기 전용)

당신은 한국 주식 롱온리 전략의 **전략 분석가**다. 이 칸은 '실현 가능성 지도'(문헌 표준 부품 × 수익 엔진 21칸)에서
보는 창 목표 영역(강세 상승 포착 ≥ 0.55 · 위기 누적 포착 ≤ 강함 문턱 · CAGR ≥ 16%)에 닿은 칸 중 종합점수가 가장 높아 **골격**으로 고정됐다.
골격 = 엔진(engine_note.md) × 부품(", cmp_note, ").
다음 단계의 처방 담당이 이 골격의 빈칸(방어 파라미터 · 구성 · 수익 엔진 보강)을 채워 **종합점수 S ≥ 1 과 하한(charter.md 2절)** 에 다가가도록,
이 칸을 이해하는 문서(「전략 이해서」)를 쓴다. 처방은 고르지 않는다 — 그것은 다음 단계다.

## 재료 — 아래 작업 디렉터리 안의 파일만 읽는다(그 밖은 읽기 가드가 막는다)
작업 디렉터리: ", LANE, "
- diagnosis_packet.md — 이 칸의 진단. **보는 창 ", pk$window[[1]], " ~ ", pk$window[[2]], " 만** 담았고 모든 수치는 R 계약이 계산했다.
- charter.md — 투자철학 · 등급 산식 · 정보 경계 · 리서치 규칙(반드시 먼저 읽어라). 2절에 S ≥ 1 에 필요한 Calmar 산술이 있다.
- engine_note.md — 엔진 설명(성과 수치 없음)", if (ENG %in% c("E2", "E3")) " · paper.txt(원논문 텍스트) · paper_engine.R(논문 엔진 구현)" else "", "
- program_notes.md — 같은 측정 축의 다른 라운드 결과(방어 장치 교차 엔진 검증 · 구성 지도 — 보는 창 수치만)
- toolbox.md — 처방이 바꿀 수 있는 축 어휘(참고용)

## 절대 규칙
1. **수치를 새로 계산 · 추정하지 마라.** 재료의 수치만 인용하고 출처(파일 · 절 · 필드)를 밝혀라. 필요한 수치가 없으면 \"측정 필요: <무엇>\" 이라고 적어라.
2. **2023년 이후의 시장 사건 · 성과는 사전학습으로 알더라도 근거로 쓰지 마라.** 위기 분석은 패킷의 위기들로만 한다.
3. 이 저장소의 다른 실험 · 다른 전략의 결과를 추측하지 마라(program_notes.md 에 있는 것만 쓴다).
4. 파일을 쓰지 마라. 산출은 최종 응답 하나다.

## 산출 — 「전략 이해서」(한국어 · 마크다운)
1. **엣지의 원천** — 엔진 기전 + 부품 기전 + 패킷의 노출 분해(선택 · 크기 · 시장 성분의 몫)로 본 실제 초과수익 원천.
2. **작동/실패 국면** — 위기마다: 무엇이 낙폭을 냈나 · 하락 포착률과 크기·노출 짝 대비 위치 · 부품이 켜졌는지(노출 프로필).
   강세장 참여(상승 포착) · 연도별 수익에서 보이는 정체 구간.
3. **A 까지의 거리** — charter.md 2절 산술로: 보는 창 PORT_t · Calmar 가 S ≥ 1 에 얼마나 모자라나, 어느 축(낙폭 · 알파)이 구속인가.
4. **지켜야 할 강점** — 처방이 훼손하면 안 되는 것과 확인 지표(패킷 필드).
5. **약점 가설 2~4개** — 각각 {주장 · 근거(패킷 수치 인용) · 반증 조건}. 크기 방어 · 노출 방어 착시와 실제 방어를 구분하라.
6. **처방 담당에게** — 고칠 곳의 우선순위와 이유 · program_notes.md 의 검증된 장치 · 구성 중 이 골격에 맞는 것 · 피해야 할 함정.

응답 맨 끝에 반드시 ```json 블록 하나로 구조화 요약을 붙여라(키 이름 그대로):
```json
{\"edge_sources\": [\"...\"],
 \"regimes\": {\"works\": [\"...\"], \"fails\": [\"...\"]},
 \"distance_to_a\": {\"binding\": \"calmar|port_t|both\", \"note\": \"...\"},
 \"strengths_to_preserve\": [{\"what\": \"...\", \"check\": \"패킷 필드/지표\"}],
 \"weakness_hypotheses\": [{\"id\": \"W1\", \"claim\": \"...\", \"evidence\": [\"패킷 인용\"], \"falsifiable_by\": \"...\"}],
 \"priorities\": [\"W?\", \"...\"]}
```
")
unlink(LANE, recursive = TRUE)
rx_prepare_lane(LANE, files = files, prompt = prompt, root = ROOT)
writeLines(c(sprintf("skeleton=%s", SEL), sprintf("engine=%s", ENG), sprintf("component=%s", CMP)), file.path(P$round_dir, "skeleton.txt"))
cat("lane:", LANE, "\n"); print(list.files(LANE))
cat("τ_D 초과 날짜(패킷):", length(dp_scan_dates(pk[setdiff(names(pk), c("created_at", "tau_d"))], pk$tau_d)), "\n")
