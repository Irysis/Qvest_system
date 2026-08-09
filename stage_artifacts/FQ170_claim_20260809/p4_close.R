#!/usr/bin/env Rscript
# p4_close.R — FQ-170 NP-1 결과 등재 + 텔레그램
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/FQ170_claim_20260809")

source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170"); stopifnot(length(i) == 1)
Q$entries[[i]]$np1_result_20260809 <- paste0(
  "NP-1 배포 프레임 전이 실측 완료(p3_np1_capw, weighted_screen_bt 계약·15bps·25종 재선별·282개월): ",
  "**양 basis 전이 CONFIRMED** — 'D8~D9 밴드 내 상위 25' vs 'top-25' paired NW3: ",
  "EW basis +5.99%p/yr t +2.568 (PORT_t A -0.598 → B +0.974) · cap-w basis +8.88%p/yr t +2.449 ",
  "(PORT_t A -2.068 → B +0.473). ★cap-w 에서 개선폭이 더 큰 이유 = top-25 가 cap-w 에서 최악",
  "(-2.068, mega-cap 상단이 가장 아픔 — cap-w 벽 실측과 정합). ",
  "형태-조건부 소비 규칙이 gross 진단→배포 프레임까지 생존. ",
  "⚠자본 한정: B 절대 PORT_t 0.974(EW)/0.473(capw) < HARD 2.95 — Q01 단독은 자격 미달 유지. ",
  "확립된 것은 **차등 규칙**(HUMP 재료를 소비할 땐 상단이 아니라 밴드) — 소비처는 composite 성분화·",
  "타 HUMP 재료 적용·스크린 라벨이지 standalone 자본이 아님."
)
Q$entries[[i]]$next_action <- paste0(
  "[NP-2 잔존] HUMP 계열 일반화 — Q01_neutral 포함 타 HUMP 재료 동일 A/B (1건 일반화 금지 규약). ",
  "[NP-3 잔존] INVERTED(D03) 형태 대응 미측정 셀. ",
  "[신규 NP-4] 밴드 선별 Q01 을 book composite 의 성분으로 — 기존 컨센서스 3종과 |cor|<0.30 이면 ",
  "book-marginal ΔIR 측정 자격 (M26 소비면 FQ-165 와 동일 절차, 그쪽 세션과 소관 중복 없음 확인 후)."
)
res <- write_frontier_queue(Q)
cat("[fq170-np1] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(OUT, "charts")
p1 <- tg_chart_sweep(
  labels = c("상위25 (시총가중)", "상위25 (동일가중)", "밴드 재선별 (시총가중)", "밴드 재선별 (동일가중)"),
  values = c(-2.068, -0.598, 0.473, 0.974),
  out_dir = CH, title = "배포 프레임 전이 — 밴드 선별이 음수를 양수로 (비용·25종 반영)",
  value_label = "다중검정 t값 (벤치마크 대비 순초과)", hline = 0,
  highlight = "밴드 재선별 (동일가중)", filename = "fq170_np1_deploy.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "형태 맞춤 선별, 실전 조건에서도 생존 — 비용과 25종 제약을 넣어도 뒤집힘 유지",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "혹형 신호의 밴드 선별이 거래비용·25종 제약·시총가중까지 넣어도 관행 대비 유의하게 낫습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "직전 확인은 이상적 조건이라 실전 조건(비용 15bps·25종 한도)으로 다시 쟀습니다",
           "동일가중: 관행 t값 -0.60 → 밴드 선별 +0.97 (개선 연 +6.0%p, t 2.57)",
           "시총가중: 관행 -2.07 → 밴드 +0.47 (개선 연 +8.9%p, t 2.45)",
           "시총가중에서 개선이 더 큽니다 — 대형주 꼭대기가 가장 아프기 때문입니다",
           "의미: 규칙은 확립, 단 이 신호 단독으론 여전히 자본 기준(2.95) 미달입니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "동일가중" = "차이 +5.99%p/yr · t값 2.568 (282개월)",
           "시총가중" = "차이 +8.88%p/yr · t값 2.449",
           "절대수준" = "밴드 선별 t값 0.97(동일)·0.47(시총) — 기준 2.95 미달",
           "쓰임새"   = "단독 자본 아님 — 복합 신호의 성분·선별 규칙 지식",
           "계보"     = "어제 형태 분류 → 오늘 소비 규칙 확립 → 실전 조건 생존")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "다른 혹형 신호들로 일반화 검증이 남아 있습니다",
           "복합 신호 성분으로 편입 가능한지 상관 검사부터 진행합니다",
           "판정: 자본 배정 없음 — 선별 규칙으로 원장 적립 완료"))
  ),
  charts = p1,
  footer = "📚 FQ-170 NP-1 · p3_np1_capw.json · metric_type=backtested_screen",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
