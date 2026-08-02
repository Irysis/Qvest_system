# =============================================================================
# run_wt014_telegram.R — WT-D20260802_014 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_014/run_wt014_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_014")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt014_eval_results.rds"))
f <- R$filtered
pr <- as.data.frame(f$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-014 복권형 제외-필터 적용판 (MAX5 상위 10% 배제)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · ΔIR %+.3f (무필터 대비)",
                         f$portfolio_alpha_t_nw_lag3, f$net_sr, R$paired$delta_ir))

lab <- c("무필터 기준", "필터 X=10% (사전등록)", "필터 X=5% (진단)", "필터 X=20% (진단)", "신호 1개월 지연")
vals <- c(R$base$information_ratio,
          R$filtered$information_ratio,
          R$base$information_ratio + R$xdiag$X05$delta_ir,
          R$base$information_ratio + R$xdiag$X20$delta_ir,
          R$base$information_ratio + R$lag1$delta_ir)
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-014 정보비율 비교 — 무필터 vs 제외-필터 (선별 계층)",
  value_label = "정보비율 (연환산, 순비용)", hline = R$base$information_ratio,
  hline_label = "무필터 기준선", highlight = "필터 X=10% (사전등록)")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_014 ALPHA_DONE — 복권형 제외-필터: 사전등록 기준 충족 (특성화 positive)",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "복권형 배제 필터가 선별 정보비율 +0.169 개선 — 사전등록 기준 충족 (t 1.57, 자본 주장 없음)"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (256개월, 사전등록 단일시험)",
         kv = list(
           "기준선 재현" = "무필터 판 알파 t값 3.0583 — 검증 기록과 정확 일치 (하네스 무결)",
           "ΔIR (판별 기준)" = "+0.169 (기준 +0.05 충족) — 선별 계층 정보비율 0.643 → 0.812",
           "짝비교 t값" = "+1.57 — 통계 확증 보통 수준 (점추정 충족, 유의성 병기)",
           "발동 실효" = "95.7% 월에서 상위 25종 구성 실변화 — 월평균 3.3종 복권형이 실제로 편입되고 있었음",
           "최대낙폭" = "-55.9% → -44.4% (11.4%p 개선)",
           "유동성 긴장" = "배제 후 후보 25종 미달 월 0",
           "위기월 역효과" = "위기 국면 월평균 -0.33%p (t -1.78) — 사전등록 병기 가설(위기에 더 유효) 반증",
           "기전 검정" = "배제군을 개인이 보유월에 더 순매수 (t +3.90) — 복권수요 실재 지지",
           "지연 스트레스" = "신호 1개월 지연 시 편익 소멸 — 신속 리밸런싱 필수 (동월 누출은 구조상 부재)")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "직전 3개월 사이 하루 급등이 유난히 컸던 '복권 같은' 종목 상위 10%를 매수 후보에서 미리 빼는 필터입니다",
           "이런 종목은 개인투자자가 복권 사듯 몰려 비싸져 있어 다음 달 성과가 나쁘다는 가설입니다",
           "현재 운용 전략의 종목 선별에 이 필터를 끼우면 성과 대비 변동 비율이 개선되고 최대 손실 폭도 줄었습니다",
           "다만 통계적으로 우연을 완전히 배제할 수준은 아니고, 위기 국면에서는 오히려 손해였습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 유의점",
         items = list(
           "판정: 소비면 특성화 positive — 사전등록 판별 기준(ΔIR +0.05) 충족, 발동 실효 확인",
           "제한 1: 짝비교 t 1.57 — 자본 편입 근거로는 불충분 (본 라운드는 특성화, 편입 판정 아님)",
           "제한 2: 2015~19 부기간 음수 — 편익이 전 기간 균질하지 않음",
           "제한 3: 오버레이 미반영 선별 계층 측정 — 운용 북 전체 기준 수치는 별도 확인 필요",
           "무결성: 위기월 역효과·부기간 음수 모두 사전등록 틀 안에서 정직 병기 (Self-Adversarial 6건 기록)")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위: 오버레이 포함 판 짝비교 — 위기월 역효과가 노출 축소와 상쇄되는지 실측",
           "2순위: 국면 조건부 필터(위기월 해제)는 사후 선택이라 이번 라운드 미채택 — 별도 사전등록 라운드로",
           "3순위: 판정·소비 경로는 Q-Lead 수집 — FQ-103 상태 전이 + 소비면 체크리스트 순회"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
