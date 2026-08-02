# =============================================================================
# run_wt006_telegram.R — WT-D20260802_006 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_006/run_wt006_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_006")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt006_eval_results.rds"))
b <- R$bt$SIG_LEVY_PV_63
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-006 경로 시그니처 (Levy area)",
  metrics_note = sprintf("PORT_t %+.2f · 순 샤프지수 %.2f · 회전율 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("PRIMARY -A_pv(63d)", "레벨1 가격(모멘텀)", "레벨1 거래대금", "레벨2 t-가격",
         "레벨2 t-거래대금", "레벨3 ppv", "레벨3 pvv", "창 21d", "창 126d",
         paste0("placebo 셔플 s", 1:5))
vals <- c(b$portfolio_alpha_t_nw_lag3,
          sapply(R$bt[c("LVL1_P_63","LVL1_V_63","A_TP_63","A_TV_63",
                        "LOGSIG3_PPV_63","LOGSIG3_PVV_63","A_PV_W21","A_PV_W126")],
                 function(x) x$portfolio_alpha_t_nw_lag3),
          sapply(R$placebo, `[[`, "port_t"))
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-006 레벨 분해 + placebo (canonical PORT_t)",
  value_label = "PORT_t (NW lag-3)", hline = 2.95, hline_label = "자본 게이트 2.95",
  highlight = "PRIMARY -A_pv(63d)")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_006 ALPHA_DONE — 경로 시그니처 Levy area: 자본미달 + 기전확인",
  sections = list(
    list(type = "summary", emoji = "📌",
         text = paste0("도훈 지시 '수학적 복잡성 최대 스마트베타' — 경로 시그니처(rough path) Levy area를 사전등록 단일 primary로 실측. ",
                       "결과: 자본-tier 미달(PORT_t +1.23 < 2.95)이나 기전은 성과-독립으로 실재 확인(후속 기관+외인 매집 t=+4.08).")),
    list(type = "kv", emoji = "📊", title = "핵심 실측 (canonical, 259개월)",
         kv = list(
           "PORT_t (시총가중 벤치)" = "+1.23 (p=0.221) — 자본 게이트 2.95 미달",
           "PORT_t (동일가중 유니버스 벤치)" = "+1.93 / post-2017 -0.07 (양쪽 소멸 = 벤치 구성 문제 아님)",
           "부기간" = "pre-2015 +3.69 → 2015-19 -0.35 → 2020+ -0.85 (감쇠 패턴)",
           "회전율" = "1578%/yr — 제약 1100% 초과",
           "직교성" = "기존 5팩터(모멘텀·변동성 계열)와 |상관| 0.11 이하 — 신규 축 성립",
           "기전 반증검정" = "거래-선행 상위 종목의 익월 기관+외인 순매수 스프레드 t=+4.08 — 기전 지지",
           "구현 검증" = "11/11 (원호 파이 재현·Chen 항등식·재매개화 불변·위반 주입 검출)")),
    list(type = "bullet", emoji = "🧠", title = "쉬운 설명",
         items = list(
           "이 팩터는 '가격과 거래대금 중 무엇이 먼저 움직였나'라는 경로의 순서를 재는 기하학 값입니다. 거래가 먼저 늘고 가격이 따라오면 조용한 매집, 가격이 먼저 뛰고 거래가 따라오면 추격 매수로 읽습니다.",
           "매집 신호가 실제로 다음 달 기관·외국인 순매수로 이어지는 것은 강하게 확인됐습니다(우연이라 보기 어려운 수준). 다만 그것이 주가 초과수익으로는 2017년 이후 이어지지 않았습니다 — 다른 팩터들과 같은 벽입니다.",
           "결론: 종목 선정용으로는 편입 불가. 대신 '보유 종목의 매집→이탈 전환 경보'와 '수급 예측' 용도로 살리는 후속 라운드를 등재합니다.")),
    list(type = "bullet", emoji = "🚩", title = "Challenge (8건 중 HIGH 3)",
         items = list(
           "placebo(순서 셔플) 대비 분리 여유 얇음 — 수익 신호력 주장 확립 불가 (ACCEPT)",
           "post-2017 양 basis 소멸, 근사 OOS 유지율 0.06 — 감쇠 패턴 (ACCEPT)",
           "회전율 제약 위반 — 평활판은 사전등록 밖이라 미실측, 후속 승계 (ACCEPT)")),
    list(type = "bullet", emoji = "➡️", title = "다음 단계 (next_probe 4)",
         items = list(
           "NP-1(P1): 수급-예측 소비면 — Levy area의 기관+외인 flow 예측력(t=4.08)을 monitoring 경보 + 수급 팩터 조건부 강화로 소비",
           "NP-2(P2): 3개월 평활판 — 회전율 제약 충족 후 post-2017 생존 재측정",
           "NP-3(P2): 시간-가격 area 역방향(동일가중 t=-2.04 관측) — 부호 사전 고정 후 독립 재도전",
           "NP-4(P3): pre-2015 강세의 감쇠 시점 귀속(계단 단절 진단 프레임 재사용)"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
