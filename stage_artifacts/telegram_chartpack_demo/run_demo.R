# run_demo.R — 텔레그램 실측 시각화 v7.1 데모 (도훈 mandate 2026-07-11)
# 실데이터 2원천: ① SPEC-1 V0 base bt_result(현 운용 북 269개월 계약 산출)
#                ② SPEC-2 timing-luck verdict.json (집행지연 시나리오 샤프 실측)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(jsonlite) })
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))

OUT <- file.path(ROOT, "stage_artifacts/telegram_chartpack_demo")

# ── ① 표준 3종: 현 운용 북(V0 base) 계약 산출 소비 ─────────────────────────
bt <- readRDS(file.path(ROOT, "04_Research/pg2_carry_convention/spec1_bt_v0_base.rds"))
m <- as.data.frame(bt$metrics)
gv <- function(nm) {
  v <- m$metric_value[m$metric_name == nm]
  if (length(v) >= 1) as.numeric(v[1]) else NA_real_
}
sr  <- gv("Sharpe")
mdd <- gv("MDD")
note <- sprintf("샤프 %.2f · 최대낙폭 %.1f (계약 산출, recon 재구성 시계열)",
                sr, abs(mdd) * 100)
p3 <- tg_chart_pack_from_bt(bt, out_dir = OUT,
                            title = "현 운용 북 (재구성 시계열)",
                            metrics_note = note)
cat("[demo] standard pack:", length(p3), "charts\n")

# ── ② sweep 비교: SPEC-2 집행지연 실측 (디스크 verdict 값 그대로) ───────────
v <- fromJSON(file.path(ROOT, "stage_artifacts/spec2_timing_luck_repaired/verdict.json"))
sk <- unlist(v$sr_by_offset)
labs <- c(sprintf("지연 %s일%s", gsub("k", "", names(sk)),
                  ifelse(names(sk) == "k0", " (현행)", "")),
          "분할집행 (tranche)")
vals <- c(as.numeric(sk), as.numeric(v$tranche$SR))
ps <- tg_chart_sweep(labs, vals, out_dir = OUT,
                     title = "리밸런스 집행 지연별 샤프지수 (SPEC-2 실측)",
                     value_label = "샤프지수 (net 15bps)",
                     highlight = "지연 0일 (현행)")
cat("[demo] sweep chart ok\n")

# ── ③ v7 브리핑 + 차트 4장 발송 ─────────────────────────────────────────────
res <- tg_agent_brief(
  agent = "Q-Lead",
  title = "보고 개편: 오늘부터 실측 리서치는 그래프와 함께 도착합니다",
  sections = list(
    list(type = "bullet", emoji = "🎯", heading = "연구 컨텍스트 (한글)",
         items = c(
           "목적: 실측 수치가 나오는 모든 리서치 보고에 측정 그래프를 항상 첨부 (도훈 지시)",
           "검토: 기존 사진 전송 배관 재사용 + 표준 차트 생성기 신설 + 스킬 규칙 의무화",
           "결론: 지금 이 메시지에 첨부된 4장이 앞으로의 표준 양식입니다")),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 글자만 오던 결과 보고를 그림과 함께 오도록 바꿨습니다",
           "방법: 모든 연구가 같은 규격의 그래프 3종을 자동으로 그려 붙입니다",
           "결과: 누적수익 곡선, 연도별 수익 막대, 낙폭 골짜기를 한눈에 봅니다",
           "의미: 숫자를 못 읽어도 선의 모양만 보면 전략의 성격이 보입니다")),
    list(type = "kv", emoji = "📊", heading = "표준 그래프 구성",
         kv = list(
           "기본 3종" = "누적수익(로그) · 연간수익률 막대 · 낙폭 수중곡선 — 모두 벤치마크와 겹쳐 그림",
           "비교 1종" = "여러 안을 겨룰 때 가로막대 서열표 + 합격 기준선 표시",
           "적용 시점" = "지금부터 — 진행 중인 두 연구(공시 난독화 · 보루타 로테이션)의 결과 보고부터 적용")),
    list(type = "bullet", emoji = "🖼️", heading = "첨부 데모 (전부 실측 데이터)",
         items = c(
           "1~3번: 현재 운용 중인 북의 재구성 시계열 269개월 (계약 산출값 소비)",
           "4번: 리밸런스 집행을 하루씩 늦출 때 샤프지수가 단조 감소하는 실측 — 어제 보고를 그림 1장으로"))
  ),
  charts = c(p3, ps),
  force = TRUE
)
cat("[demo] send ok =", isTRUE(res$ok), "\n")
