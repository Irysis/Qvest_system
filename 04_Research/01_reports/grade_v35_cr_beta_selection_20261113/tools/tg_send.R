## 등급 v3.5 출시 · 재채점 보고 — 텔레그램 1통(요약 + 차트 2장) · 수치 = 계약 산출(REPORT_tables.md · data/regrade_table.csv)
## 실행: 저장소 루트에서 Rscript …/tools/tg_send.R   (미리보기 · 발송 없음) / … tg_send.R send   (발송)
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd()))); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
SEND <- "send" %in% commandArgs(trailingOnly = TRUE)
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
D <- file.path(ROOT, "04_Research/01_reports/grade_v35_cr_beta_selection_20261113")
figs <- c("① 권위 등급 분포 — v3.4 vs v3.5(재채점 범위 = 위기 방어 가점이 유지된 기록)" = file.path(D, "charts/01_grade_distribution.png"),
          "② 위기 방어 '강함' 기록 — 시가총액·노출 일치 대조 vs 시가총액·β 일치 대조를 이긴 위기 비율" = file.path(D, "charts/02_cr_strong_attribution.png"))
stopifnot(all(file.exists(figs)))
WRITE_NOTE <- Sys.getenv("V35_WRITE_NOTE", "재채점 쓰기는 RAWDATA 2026-03-30 수정주가 이음매 수리 뒤 1회 — 위 결과는 같은 입력 드라이런(v3.4 vs v3.5)")
r <- tg_agent_brief(
  agent = "Q-Lead",
  title = "[1계층·등급 규칙] v3.5 출시 — 위기 방어 가점에 시가총액·β 일치 대조 추가",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "위기 방어 가점 = 시가총액·β 일치 대조까지 이겨야 · 정적 저β 틸트 가점 결함 수리 · 재채점 7건 중 3건 B → C"),
    list(type = "bullet", heading = "무엇이 바뀌었나", emoji = "\U0001F527",
         items = c("기존: 같은 시가총액 분위에서 무작위로 고른 대조 포트폴리오(characteristic-matched random portfolios · 200개)의 위기 낙폭 5% 분위보다 덜 빠지면 '선택 방어'. β 를 맞추지 않아 분위 안 저β 종목만 담아도 통과했다.",
                   "v3.5: 각 대조 포트폴리오를 현금 혼합으로 전략 β 까지 낮춘 동일 β 대조군(월간 OLS β · 차입 없음)도 위기 과반에서 이겨야 가점. 노출을 시변 조절하는 전략은 노출 경로까지 맞춘 대조도 이겨야 '선택'.",
                   "근거: 헌장 빈칸 14(선택 방어 = 시가총액 × β 동시 일치 대조까지 넘을 때) · 도훈 결정 GRADE-CR-NOTCH-BETA-SELECTION-20261113.",
                   "종합점수 S · 하한 · 팩터 조정 알파 노치 · OOS 관문은 그대로 — 가점 조건만 추가했으므로 같은 입력이면 등급이 오르지 않는다.")),
    list(type = "bullet", heading = "검증 — 합성 자료 양성·음성 대조 · 돌연변이", emoji = "\U0001F9EA",
         items = c("음성: 분위 안 저β(0.4) 대칭 종목 → 기존 대조 100% 통과 · 동일 β 대조 0% → 가점 해제",
                   "양성: 평상 β 1.0 · 위기 β 0.3(비대칭) → 둘 다 100% → 가점 유지 / 평상 0.6 · 위기 0.2 → 유지(저β 자체를 벌하지 않는다)",
                   "저β + 위기 달 노출 축소 → 노출 경로 동일 β 대조 0% → '선택' 아님(타이밍 · 증거 없으면 가점 없음)",
                   "검사를 무력화한 돌연변이 4종 모두 검출 · 가점 경우의 수 240개에서 등급 상승 0 · 기존 검사 5종 회귀 통과")),
    list(type = "bullet", heading = "재채점(측정 전 고정한 범위)", emoji = "\U0001F4CA",
         items = c("범위: 저장 권위 기록 3,173건 중 위기 방어 가점이 유지된 7건(규칙 = 가점 유지 기록만 · 측정 전 커밋)",
                   "결과(같은 입력 v3.4 vs v3.5): B → C 3건(P1R03 쏠림 · P1R03 위험 · RF_PAR_B2_6 최소분산 — 보유 종목 β 0.39~0.54) · 그대로 4건(F 2 · B 2)",
                   "7건 모두 동일 β 대조를 위기 과반에서 못 이겼다(10~41%) — 저장 기록 중 v3.5 가점을 유지하는 기록은 0건",
                   "실데이터 음성 대조: 이미 가점이 없던 강함 22건 + 무작위 30건 → 등급 동일 52/52",
                   "전체 분포: A 5 · B 1,303 → 1,300 · C 914 → 917 · F 950 · 수혜(상향) 기록 0",
                   WRITE_NOTE)),
    list(type = "bullet", heading = "다음", emoji = "\U000027A1\UFE0F",
         items = c("상설 자격 심사: 등급 계약이 바뀌어 새로 등록(자체 사양 심사 P1S03 은 출시 뒤 등록 · P1R04 는 측정 직전 계약 고정값 갱신)",
                   "후속: 행동 카드 보고 문구(기존 '선택 방어' 표기)를 동일 β 대조 결과와 맞추기"))),
  charts = figs, relaxed = TRUE, glossary = FALSE)
cat("ok:", isTRUE(r$ok %||% TRUE), "\n")
