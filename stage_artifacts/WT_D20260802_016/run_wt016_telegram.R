# =============================================================================
# run_wt016_telegram.R — WT-D20260802_016 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_016/run_wt016_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_016")
dir.create(file.path(OUT, "charts"), showWarnings = FALSE)
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt016_eval_results.rds"))
f <- R$cells$filt_ov
pr <- as.data.frame(f$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-016 필터+overlay 결합판 (MAX5 상위 10% 배제 x 현 운용 노출)",
  metrics_note = sprintf("알파 t값 %+.2f · 절대 샤프지수 %.2f · 최대낙폭 %.1f%%",
                         f$portfolio_alpha_t_nw_lag3, f$abs_net_sr, 100 * f$abs_mdd))

lab <- c("무필터 (overlay 없음)", "필터 (overlay 없음)", "무필터 + overlay", "필터 + overlay", "필터 1개월 지연 + overlay")
vals <- c(R$cells$base_bare$information_ratio, R$cells$filt_bare$information_ratio,
          R$cells$base_ov$information_ratio, R$cells$filt_ov$information_ratio,
          R$cells$base_ov$information_ratio + R$lag1_filter_ov$delta_ir)
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-016 정보비율 2x2 — 필터 x overlay 결합 효과",
  value_label = "정보비율 (연환산, 순비용)", hline = R$cells$base_ov$information_ratio,
  hline_label = "무필터 + overlay 기준선", highlight = "필터 + overlay")

# 커스텀: 누적 필터-기여 (bare vs overlay-ON)
PD <- as.data.table(R$paired_series)
ch3 <- file.path(OUT, "charts", "wt016_cum_delta_active.png")
png(ch3, width = 1200, height = 700, res = 130)
par(mar = c(4, 4.5, 3, 1))
plot(PD$date, cumsum(PD$d_bare) * 100, type = "l", lwd = 2, col = "#888888",
     xlab = "", ylab = "누적 필터 기여 (%p, 월별 합)",
     main = "필터의 누적 초과 기여 — overlay 없음(회색) vs overlay 포함(청색)")
lines(PD$date, cumsum(PD$d_ov) * 100, lwd = 2, col = "#1f77b4")
abline(h = 0, lty = 3)
legend("topleft", c("overlay 없음 (ΔIR +0.169)", "overlay 포함 (ΔIR +0.128)"),
       col = c("#888888", "#1f77b4"), lwd = 2, bty = "n")
dev.off()

rt <- R$regime_tab
tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_016 ALPHA_DONE — 복권형 제외-필터, overlay 포함판에서도 관문 통과",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "실배치 관문 통과: overlay 포함 상태에서도 필터 기여 유지 — 짝비교 t +1.55, ΔIR +0.128 (자본 주장 없음)"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (256개월, 사전등록 단일시험)",
         kv = list(
           "기준선 재현" = "무필터 알파 t값 3.0583 — 검증 기록 정확 일치 (하네스 무결)",
           "판별 (overlay 포함)" = "짝비교 t +1.551 / ΔIR +0.128 — 소비면 닫힘 기준(t<1) 비발동",
           "무overlay 참조" = "t +1.565 / ΔIR +0.169 (직전 라운드 재현 정확)",
           "상호작용" = "overlay가 필터 기여를 유의하게 지우지 못함 (t -1.14) — 축소분은 노출 축소의 산술 결과",
           "위기월 역효과" = "크기 61% 흡수 (-0.33 → -0.13%p/월, 위기 평균 노출 0.38) — 부호는 잔존 (t -1.59)",
           "최대낙폭 분해" = "overlay 단독 15.6%p + 필터 추가 7.3%p 개선 (-40.3% → -33.0%) — 부분 독립, 중복 아님",
           "절대 샤프지수" = "0.874 → 0.962 (필터 추가 시, overlay 포함 기준)",
           "지연 스트레스" = "overlay 포함판에서도 1개월 지연 시 편익 소멸 — 신속 리밸런싱 필수",
           "무결성 검증" = "PIT 가드 통과 + 위반 주입 시 차단 발화 실증 · 누출 방향 변형이 오히려 열세 (-9%) = 미래참조 이득 부재")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "직전 라운드에서 '복권 같은 급등 종목'을 매수 후보에서 빼면 성과가 좋아짐을 확인했는데, 위기 때는 오히려 손해라는 약점이 있었습니다",
           "현재 운용 중인 전략은 위기가 오면 주식 비중 자체를 줄이는 안전장치(overlay)를 이미 갖고 있습니다",
           "이번 라운드는 그 안전장치를 켠 상태에서도 필터가 여전히 도움이 되는지를 쟀습니다 — 답은 '그렇다'입니다",
           "안전장치가 위기 때 비중을 줄여 필터의 위기 손해를 6할쯤 흡수하고, 필터의 이득은 대부분 살아남았습니다",
           "낙폭 방어도 겹치지 않았습니다: 안전장치가 15.6%p, 필터가 그 위에 7.3%p를 추가로 줄였습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 유의점",
         items = list(
           "판정: 실배치 관문 통과 — 필터는 현 운용 구성과 겹쳐도 한계기여 유지 (사전등록 기준 충족)",
           "제한 1: 짝비교 t 1.55 — 통계 확증 보통. 실배치 여부는 별도 결정 사항 (자본 결정 = 도훈 수동)",
           "제한 2: 위기월 역효과의 부호는 남음 — 노출 축소는 크기만 줄일 수 있음",
           "제한 3: 사전등록 배선 검증 기준 1회 발동 — 진단 결과 배선 무결(정렬·노출 2축 실증), 원인은 기준의 비교 대상 설정 오류로 확정·기록",
           "무결성: PIT 위반 주입 테스트 발화 확인 · 시점 누출 변형이 열세 = 미래참조 인플레 부재")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "실배치 상신: 필터+overlay 결합판 실측 완료 — 편입 여부는 governor 경로 + 도훈 결정 대기",
           "다음 검증 1: 위기월 필터 해제(국면 조건부)는 사후 선택이라 이번에 미채택 — 별도 사전등록 라운드로",
           "다음 검증 2: MAX5를 위험모델 사전지표로 쓰는 위험-축 소비 (등재 완료, 착수 대기)",
           "판정·큐 전이는 Q-Lead 수집 — FQ-111 in_flight → 수집 대기"))),
  charts = c(charts, ch2, ch3))
cat("[tg] 발송 완료\n")
