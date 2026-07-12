#==============================================================================
# N2 / FQ-021 delta_ext — Step 30: charts (tg_chart_pack + config sweep) + telegram v7
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
DEXT <- file.path(ROOT, "stage_artifacts/WT_D20260711_002/delta_ext")
CH   <- file.path(DEXT, "charts"); if(!dir.exists(CH)) dir.create(CH, recursive=TRUE)
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

r <- readRDS(file.path(DEXT,"delta_results.rds"))

# ---- standard 3 (primary c1 full period_returns) ----
pr <- as.data.frame(r$results$c1$canon_full$period_returns)  # date, ret_net, benchmark_ret
paths_std <- tg_chart_pack(pr, out_dir=CH,
  title="FQ-021 Δm1 변화축 (기본 c1: raw Δ 12m)",
  metrics_note="cap-w PORT_t 0.77 · netSR 0.22 · IS 1.58→OOS -0.83 (canonical_screen)",
  prefix="c1_")

# ---- config sweep bar: cap-w PORT_t for c1..c4 + reference ----
f_sweep <- file.path(CH, "config_portt_sweep.png")
grDevices::png(f_sweep, width=1000, height=560, res=110)
graphics::par(mar=c(5,4.4,3.2,1))
pt <- c(r$results$c1$full$port_t, r$results$c2$full$port_t,
        r$results$c3$full$port_t, r$results$c4$full$port_t)
labs <- c("c1 raw·12m\n(기본)","c2 잔차·12m","c3 raw·6m","c4 잔차·6m")
cols <- ifelse(pt>=2.95, "#2ca02c", "#d62728")
bp <- graphics::barplot(pt, names.arg=labs, col=cols, border=NA, ylim=c(-1,3.2),
  ylab="cap-w PORT_t (canonical)", main="FQ-021 Δm1 4개 config — cap-w PORT_t vs 2.95 게이트")
graphics::abline(h=2.95, lty=2, lwd=2, col="#333333")
graphics::abline(h=0, lwd=1, col="#999999")
graphics::text(bp, pt+0.15*sign(pt+0.01), sprintf("%.2f", pt), cex=0.95)
graphics::text(par("usr")[1]+0.3, 2.95+0.12, "HARD 게이트 2.95", pos=4, cex=0.8, col="#333333")
graphics::mtext("Phase A 레벨 m1 = 2.35 (screen-tier) · 변화축 4/4 미달", side=3, line=0.2, cex=0.78, col="#555555")
grDevices::dev.off()

charts <- c(paths_std, f_sweep)
cat("[30] charts:\n"); print(charts)

# ---- telegram v7 (5 sections + 비전공자 3장치) ----
tg_agent_brief(
  agent = "Alpha",
  title = "FQ-021 (N2) Δm1 변화축 — 판정: NULL / 텍스트 아크 최종 종결",
  sections = list(
    list(type="summary", emoji="📌",
         body="공시 가독성 '악화(Δm1)'로 저수익 예측 시도 — 4개 config 전부 자본 게이트 미달, 변화축 신호 없음(NULL)."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
         items=c("시도: 작년보다 공시가 갑자기 읽기 어려워진 회사의 주가가 나쁜지 검증했습니다",
                 "방법: 기존 4,432건 재사용, 회사별 연도 문장길이 차이(Δ)로 top-25 모의운용+무작위 대조",
                 "결과: 4개 구성 모두 게이트 2.95에 크게 미달, 방향도 가설과 반대, 0과 구분 안 됨",
                 "의미: '변화' 축은 자본급 신호 아님 — 텍스트 가독성 연구를 종결합니다")),
    list(type="table", emoji="📊", heading="config별 판정 (PORT_t·정보t·IS→OOS, 게이트 2.95)",
         df=data.frame(
           구성 = c("c1 raw·12m(기본)","c2 잔차·12m","c3 raw·6m","c4 잔차·6m"),
           `PORT_t·정보t·IS→OOS` = c("0.77·1.85·1.58→-0.83","0.64·2.26·1.20→-0.50",
                                     "-0.20·0.07·0.51→-0.80","-0.38·1.10·0.12→-0.64"))),
    list(type="bullet", emoji="🚩", heading="적대검증",
         items=c("방향 역전: 정보계수 +0.008(양수) — 가설(악화→저수익, 음수)과 반대이며 무의미",
                 "placebo p=0.085 (≥0.05 비유의) · 시총통제 편상관 거의 불변(size proxy 아님이나 신호 자체가 null)",
                 "EW-유니버스 기준도 약함/음수 → cap-w 벤치 아티팩트 아님 (dual-basis 확인)",
                 "잔차 Δ(레벨 통제)가 raw보다 정보계수 소폭↑ = 변화는 레벨의 위장 아닌 '독립이나 null' 차원",
                 "보유 92% 소형주 = Phase A와 동일 cap-tier 국소화 벽")),
    list(type="bullet", emoji="➡️", heading="다음",
         items=c("FQ-021 → settle_negative (변화축 소진)",
                 "텍스트 가독성 아크 최종 종결: 레벨 m1 = OVERLAY_CANDIDATE feature 보존, 변화축 = 부정 적립",
                 "누적 n_trials 11 (chain) · null max Harvey-t 2.26 < Phase A 2.80 · 자본급 후보 부재",
                 "잔여 프론티어 = 비-수익 데이터 원천(공시 임원거래 등)")),
    list(type="kv", emoji="🔬", heading="근거 수치",
         kv=list("Δm1 연도쌍"=3657, "종목수"=585, "신호월(12개월유지)"=157,
                 "기본 초과수익t"="0.77 (게이트 2.95)", "무작위대조 p값"=0.085,
                 "사전등록 해시"="4bdda5f8"))
  ),
  charts = charts,
  footer = "canonical_screen (alpha-stage 실측, forge-authoritative 아님) · text_cache 재사용(DART/쿼터 0) · prereg 동결 4bdda5f8"
)
cat("[30] telegram sent.\n")
