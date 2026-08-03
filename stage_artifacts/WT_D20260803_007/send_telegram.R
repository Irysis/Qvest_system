# send_telegram.R — WT-D20260803_007 (FQ-135) 결과 보고
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

AR <- readRDS(file.path(OUT, "arm_results.rds")); PH <- readRDS(file.path(OUT, "posthoc_results.rds"))
XP <- readRDS(file.path(OUT, "adversarial_probes.rds"))
SUM <- AR$summary; gv <- function(a, c) SUM[arm == a, get(c)]

# 표준 3종 (primary arm 실측) + 비교 막대
pr <- as.data.table(AR$res_period_returns[["A_REL_TOP"]])
pk <- tryCatch(tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-007 A_REL_TOP (era-robust 상위 20 EW composite) OOS 167개월",
  metrics_note = sprintf("PORT_t %.3f (cap-w) / %.3f (EW-유니버스) · IR %.3f · 회전율 %.2f/yr",
    gv("A_REL_TOP","port_t"), gv("A_REL_TOP","ew_port_t"), gv("A_REL_TOP","ir"),
    gv("A_REL_TOP","turnover_annual"))), error = function(e) { message(e$message); character(0) })

charts <- c(file.path(OUT, "charts/discriminants.png"),
            file.path(OUT, "charts/arm_cum_active.png"),
            file.path(OUT, "charts/random_null.png"), pk)
charts <- charts[file.exists(charts)]

sections <- list(
  list(type = "text", emoji = "📌",
       body = sprintf("era-robust 성분 선별 판정 — 사전등록 관문 2개 모두 미달. (a) 상위-하위 t=%+.2f · (b) 상위-단일최강 t=%+.2f (문턱 +2.0). 판정 FAIL — 이 방식에는 실제 자본을 배정하지 않습니다.",
                      AR$disc$a_t, AR$disc$b_t)),
  list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
       items = c(
         "시도: '언제 통하는지'를 못 맞히니 '언제든 덜 무너지는' 재료 20개를 골랐습니다",
         "방법: 285개 팩터를 과거만 보고 고른 뒤 이후 167개월을 실제 운용하듯 측정",
         "결과: 반대로 고른 집합도, 가장 센 단일 재료도 이기지 못했습니다",
         "원인: 우위처럼 보인 것은 '과거 성적 좋음'의 재선택이었습니다",
         "성적 요소를 걷어내니 오히려 손해(PORT_t -1.07)였습니다",
         "의미: 자본 배정 없음. 새로 측정한 벤치마크 왜곡을 다음 라운드로 넘깁니다")),
  list(type = "table", emoji = "📊", heading = "arm 별 PORT_t (cap-w / EW기준), OOS 167개월",
       df = data.frame(
         arm = c("A_REL_TOP (robust 상위20)", "A_REL_BOT (하위20)", "SINGLE_BEST (단일최강)",
                 "A_PERP_TOP (성적제거)", "POOL_EW (무선별 285)", "LEVEL_TOP_K20 (사후)",
                 "무작위 200회 평균"),
         PORT_t = c(sprintf("%+.2f / %+.2f", c(gv("A_REL_TOP","port_t"), gv("A_REL_BOT","port_t"),
                 gv("SINGLE_BEST","port_t"), gv("A_PERP_TOP","port_t"), gv("POOL_EW","port_t"), PH$port_t),
                 c(gv("A_REL_TOP","ew_port_t"), gv("A_REL_BOT","ew_port_t"), gv("SINGLE_BEST","ew_port_t"),
                 gv("A_PERP_TOP","ew_port_t"), gv("POOL_EW","ew_port_t"), PH$ew_port_t)),
                 sprintf("%+.2f / -", mean(AR$rand$port_t, na.rm = TRUE))),
         check.names = FALSE, stringsAsFactors = FALSE)),
  list(type = "kv", emoji = "🔬", heading = "기전 귀속",
       kv = list(
         `시대강건성 순증분` = sprintf("t=%+.3f (음수)", PH$pairs[pair == "A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3]),
         `성적요소 제거 시` = sprintf("PORT_t %+.3f — inert 팩터 선택기로 퇴화", gv("A_PERP_TOP","port_t")),
         `무작위 대비` = "상위 99.0 백분위 / 하위 68.0 — 상위만 분리",
         `위반 주입` = sprintf("발화 — t 1.212 → %.2f → %.2f", AR$pairs[pair == "LEAK_FULLSAMPLE - A_REL_BOT", t_nw_lag3], AR$pairs[pair == "LEAK_ORACLE_OOS - A_REL_BOT", t_nw_lag3]),
         `격자 민감도` = sprintf("11변형 전부 미달 (최대 %.3f)", max(XP$ap1[grepl("BOT", pair), t_nw_lag3], na.rm = TRUE)))),
  list(type = "bullet", emoji = "🚩", heading = "정직 한계 · 유보",
       items = c(
         sprintf("부트스트랩상 (a)/(b) 문턱 도달 확률 %.0f%%/%.0f%% — 효과 부재 증명 아님", 100*XP$ap4$p_reach_2[1], 100*XP$ap4$p_reach_2[2]),
         sprintf("확정된 것은 순증분 부재 쪽 (도달 확률 %.1f%%)", 100*XP$ap4$p_reach_2[3]),
         sprintf("★새 사실: 이 판의 기준선은 0이 아니라 %.2f (무작위 20팩터 평균)", mean(AR$rand$port_t, na.rm = TRUE)),
         sprintf("동일가중 기준으로 바꾸면 LEVEL_TOP_K20이 %+.2f로 부호 반전", PH$ew_port_t),
         "판별식은 arm 간 차라 벤치마크가 정확히 상쇄 — 판정은 뒤집히지 않음",
         sprintf("회전율 %.2f/년 > 상한 11.0 — 구현 규율 별도 관문", gv("A_REL_TOP","turnover_annual")),
         "판정 범위는 era-robust 축 한정 — 구성 방식 일반 판결 아님")),
  list(type = "bullet", emoji = "➡️", heading = "다음 탐침 (next_probe)",
       items = c(
         "NP-1 시총 중립 composite — 동일가중 2.86을 시총가중으로 옮길 수 있는가",
         "NP-2 중형주(11~30위) 국소화 — 2017년 이후 음수가 초대형주 artifact인가",
         "NP-3 지표를 선택기 아닌 배제기로 — inert 팩터 제거는 미측정",
         "NP-4 era 변동성을 risk 레인 불안정성 입력으로 이관")))

tg_agent_brief(agent = "Alpha",
  title = "WT-D20260803_007 ALPHA_DONE — era-robust 성분 선별 (a)/(b) 모두 미달, 순증분 0",
  sections = sections, charts = charts)
cat("[wt007T] telegram 발송 완료 (charts", length(charts), ")\n")
