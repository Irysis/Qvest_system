# FQ-018 텔레그램 v7 보고 — A급 18건 재베이스 감사 (차트 의무: tg_chart_sweep 전/후 PORT_t)
suppressMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

out_dir <- file.path(ROOT, "stage_artifacts/fq018_agrade_rebase")

# ── sweep 차트: 재측정 수치 있는 3건의 재베이스 전/후 PORT_t ──────────────────
chart <- tg_chart_sweep(
  labels = c("AS 멀티팩터 0612 [전]", "AS 멀티팩터 0612 [후]",
             "AS 5슬리브 0612 [전]",  "AS 5슬리브 0612 [후]",
             "AS RD/M 0709 [전]",     "AS RD/M 0709 [후=동일]"),
  values = c(2.523, 1.943, 1.938, 1.369, 2.584, 2.584),
  out_dir = out_dir,
  title = "FQ-018 A급 재베이스: 전/후 PORT_t (교정벤치 IKS200)",
  value_label = "PORT_t (NW lag-3, 실측)",
  hline = 2.95, hline_label = "graduation HARD",
  highlight = c("AS 멀티팩터 0612 [후]", "AS 5슬리브 0612 [후]", "AS RD/M 0709 [후=동일]"),
  filename = "fq018_rebase_sweep.png")

res <- tg_agent_brief(
  agent = "Q-Lead",
  title = "FQ-018 A급 원장 18건 재베이스 감사 완료",
  as_of = "2026-07-12",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "A급 18건 전수 재판정 — 자본급 생존자 0건, 절차기록 7건만 A 유지"),
    list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
         items = c(
           "무엇을: 벤치마크 버그 수리(7/2) 이전에 'A등급'을 받은 기록 18건을 전부 다시 채점했습니다",
           "어떻게: 보존된 수익 시계열을 고친 벤치마크에 다시 대조(재베이스) — 재던 자와 같은 공식 함수만 사용",
           "결과: 재측정 가능 3건 모두 합격선(2.95) 미달, 나머지는 기존 판정 인용·시계열 소실·절차기록으로 분류",
           "의미: 예전 A 중 '진짜 돈 되는 전략'은 없었고, 옛 벤치 버그가 성적을 부풀렸음이 수치로 확정됐습니다")),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 수치 (실측)",
         kv = list(
           "재베이스1"  = "PORT_t 2.52→1.94 (멀티팩터 0612)",
           "재베이스2"  = "PORT_t 1.94→1.37 (5슬리브 0612)",
           "보조검증"   = "RD/M 0709 = 2.58 불변 (벤치 동일)",
           "벤치버그"   = "구벤치 누적 7.43 vs 교정 9.29 (과소)",
           "판정합계"   = "유지A 7 / 강등 8 / 소실 3 / 생존 0")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "리스크·주의",
         items = c(
           "RAMP_03C(06-20)는 명목 HARD 3/3 통과 유일 기록이나 원 시계열 소실 — 재실행 없인 판별 불가 (도훈 결정 회부)",
           "06-12 AS 2건은 batch_434 오염 창 — 라벨-신호 불일치 가능성 별도 유의",
           "원 L-code JSON은 무수정(원장 불변) — 강등 반영은 파생 뷰에서 Cleaner confirm 후")),
    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "판정 평문: 이번 18건에서 자본 투입 후보로 올라가는 전략은 0건 — 운용 북·실제 돈은 그대로, 바뀌는 건 지식 원장의 등급 라벨뿐입니다",
           "RAMP_03C 재실행(frontier 큐 dohoon_decision 등재) 여부 도훈 결정 대기",
           "보고서: 04_Research/01_reports/agrade_rebase_audit_20260712.md"))),
  charts = c(chart),
  footer = "FQ-018 종료 — 원장 정화 권고안 포함")

cat("[tg] ok=", res$ok, " error=", if (is.null(res$error)) "none" else res$error, "\n", sep = "")
