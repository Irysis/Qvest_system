## _r13_telegram.R — RAMP R13 판정 텔레그램 v7 (원칙 8 비전공자 3장치 + 원칙 9 실측 차트)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a

r13 <- fromJSON("outputs/ramp/r13_decay_summary_20260713.json")
CHART_DIR <- "stage_artifacts/ramp/R13_decay"
if(!dir.exists(CHART_DIR)) dir.create(CHART_DIR, recursive=TRUE)

## ── 차트 1: arm 서열 — 1차 endpoint oos_retention (자본문턱 0.7) ──
res <- as.data.table(r13$results)
labs <- c("base","D1 감쇠선별","D2 감쇠퇴출","D3 부분창일관","FM 대조군")
mp <- c(base="base", armD1_decay_penalty="D1 감쇠선별", armD2_decay_exit="D2 감쇠퇴출",
        armD3_subwin_consistency="D3 부분창일관", ctrl_factormom="FM 대조군")
res[, lab := mp[model]]
p_oos <- tg_chart_sweep(labels=res$lab, values=res$oos_retention, out_dir=CHART_DIR,
  title="R13 arm별 표본외 유지율(oos) — 1차 지표",
  value_label="oos_retention (cap-w)", hline=0.7, hline_label="자본문턱 0.7",
  highlight="D2 감쇠퇴출", filename="sweep_oos.png")
## ── 차트 2: arm 서열 — 2차 cap-w PORT_t (자본문턱 2.95) ──
p_pt <- tg_chart_sweep(labels=res$lab, values=res$port_t_capwt, out_dir=CHART_DIR,
  title="R13 arm별 다중검정 t값(cap-w) — 2차 지표",
  value_label="PORT_t (cap-w)", hline=2.95, hline_label="자본문턱 2.95",
  highlight="D2 감쇠퇴출", filename="sweep_capwt.png")
## ── 차트 3~5: 최선안(D-2) 표준 3종 ──
bp <- readRDS(".cache/_ramp_r13_bestpr_20260713.rds")
p_std <- tg_chart_pack(period_returns=bp$period_returns, out_dir=CHART_DIR,
  title="R13 최선안 D2(감쇠퇴출)", bm_label="KOSPI200",
  metrics_note="cap-w PORT_t 2.503 · oos +0.045 (계약 실측)", prefix="best_D2_")
charts <- c(p_oos, p_pt, p_std)
cat("charts:", length(charts), "\n"); print(charts)

## ── 텔레그램 v7 판정 보고 ──
tg_agent_brief(
  agent = "Q-Lead",
  title = "RAMP R13 감쇠속도 실험 — 팩터 갈아치우기 속도로 성과 유지력을 높이려 했으나 미달",
  sections = list(
    list(type="summary", emoji="📌",
         body="팩터 힘빠짐 속도를 반영했습니다. 갈아치우는 재료로 쓰면 유행추종으로 변질돼 나빠졌고, 내보내는 기준으로만 쓰면 살짝 나아졌으나 합격선엔 크게 미달했습니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
         items=c("시도: 팩터가 최근 힘 빠지는 '감쇠 속도'를 3가지 방식으로 종목 선별에 반영",
                 "방법: 2005~2026 21년 데이터로 백테스팅하고 '유행 추종'과 같아지는지 검증",
                 "결과: 선별 재료로 쓰면(D1) 유행추종 붕괴, 내보내는 기준으로만 쓰면(D2) 유지율 −0.08→+0.05",
                 "의미: 방향은 맞으나 합격선(0.7)의 1/6 — 자본 미배정, 재료를 바꾸는 다음 실험으로")),
    list(type="kv", emoji="📊", heading="arm별 성과 (유지율 / t값, 클수록 좋음)",
         kv=list("기준 base"="유지율 -0.08 · t값 2.61",
                 "D2 감쇠퇴출"="유지율 +0.05 · t값 2.50 (최선)",
                 "D1 감쇠선별"="유지율 -0.45 · t값 1.56 (붕괴)",
                 "FM 대조군"="유지율 -0.45 · t값 1.32")),
    list(type="bullet", emoji="🚩", heading="주의·핵심 발견",
         items=c("감쇠속도를 '팩터 선별 재료'로 쓴 D1은 유행 추종(팩터 모멘텀)과 71% 겹쳐 함께 붕괴",
                 "D2 개선폭(+0.12)이 직전 라운드 최선과 정확히 같음 — 유지율 천장이 퇴출 방식과 무관하게 ~+0.12로 굳음",
                 "소형주 기준 유지율은 D2 0.75·D3 0.97로 높으나 대형주 가중 기준으론 붕괴 = 규모-편중 함정 재확인")),
    list(type="bullet", emoji="➡️", heading="판정·다음",
         items=c("판정: config-scoped negative — 이 아이디어에는 실제 자본을 배정하지 않습니다(참고 기록만 보관)",
                 "다음: 시간-함수형 튜닝은 성과·유지율 양쪽서 소진지대 → 재료 축(DART 임원 매수 등 비-수익 데이터)으로 전환",
                 "L-RAMP-20260713_102944 적립 · governor 정지(자본 무변경)"))
  ),
  charts = charts
)
cat("TG_DONE\n")
