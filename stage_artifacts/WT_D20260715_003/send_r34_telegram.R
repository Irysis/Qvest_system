## R34 텔레그램 v7 판정 보고 (원칙 9 — 차트 첨부 의무)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_003"
r  <- fromJSON(file.path(OUT,"r34_results.json"))
dp <- r$derisk_primary; dr <- r$derisk_restricted; dl <- r$derisk_lag1_stress
wb <- r$wiring_current_book; cov <- r$held_coverage

## 차트 1 — de-risk 신호력 (per-holding basis) gap NW-t
c1 <- tg_chart_sweep(
  labels = c("수익 gap NW-t (전체 보유)", "수익 gap NW-t (insider-커버)", "lag1 스트레스 gap NW-t"),
  values = c(dp$gap_ret_t, dr$gap_ret_t, dl$gap_ret_t),
  out_dir = OUT, title = "순매수 flag 보유 = 익월 수익차 유의 (per-holding, lag1 robust)",
  value_label = "forward NW-t", hline = 2.0, hline_label = "유의",
  filename = "chart_A_derisk_signal.png")

## 차트 2 — forward 위험 개선 (flag vs 비-flag, per-holding %)
c2 <- tg_chart_sweep(
  labels = c("익월수익 flag %", "익월수익 비-flag %", "하방 flag %", "하방 비-flag %",
             "급락<-15% flag %", "급락<-15% 비-flag %"),
  values = c(dp$mean_fwd_flag*100, dp$mean_fwd_nonflag*100, dp$downside_flag*100, dp$downside_nonflag*100,
             dp$tail_hit_flag*100, dp$tail_hit_nonflag*100),
  out_dir = OUT, title = "순매수 flag 보유 = 고수익·하방완화·급락회피 (per-holding)",
  value_label = "%", highlight = c("익월수익 flag %","하방 flag %","급락<-15% flag %"),
  filename = "chart_B_risk_improve.png")

## 차트 3 — 현 북 14 보유 통합 tripwire 판정 (현재 스냅샷)
c3 <- tg_chart_sweep(
  labels = c("NET_BUY_SAFE (안전)", "NEUTRAL", "NO_INSIDER_DATA", "net-sell advisory (경보아님)"),
  values = c(wb$n_net_buy_safe, wb$n_neutral, wb$n_no_insider_data, wb$n_net_sell_advisory),
  out_dir = OUT, title = "현 북 14보유 순매수 tripwire (홀딩월 202607 · armed·inactive)",
  value_label = "종목수", highlight = "NET_BUY_SAFE (안전)",
  filename = "chart_C_current_book.png")

sections <- list(
  list(type="summary", emoji="📌",
    body="임원 순매수 클러스터 안전신호를 북 보유에서 확증하고 tripwire를 부실경보 창구에 배선 완료 — per-holding 유지-안전(자본 아님)."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "임원이 최근 6개월 꾸준히 사 모은 종목 = '상대적 안전' 신호.",
      "R33: 시장 전체서 확인. R34: 우리 북 보유 종목서도 같은지 검증.",
      "결과: 북 보유 중 신호 켜진 종목은 다음달 수익 높고 급락 빈도 절반.",
      "그 종목들 전부 대형·중형(살 수 있는 크기) = 소형주 착시 아님.",
      "★단 '계속 들고 있어도 안전' 라벨이지 '더 사라'가 아님(소수집중=변동성↑).",
      "그래서 비중이 아니라 월간 감시신호로만 배선(부실경보 창구 반대편).",
      "현 북 14종목 중 안전신호 켜진 것 0개(신호기 켜두고 대기).")),
  list(type="kv", emoji="📊", heading=sprintf("핵심 수치 (북 보유 %d종목-월 · §7b clean T-1 기준)", cov$held_name_months),
    kv=list(
      "순매수 신호 표본"=sprintf("%d건 (%.1f%%·월평균 %.1f종·%d개월)", cov$flagged_held, cov$flagged_held_pct, dp$avg_flag_per_month, dp$n_months),
      "익월 수익차 (신호−무신호)"=sprintf("연 %+.1f%% · 다중검정t %.2f (커버내 %.2f)", dp$gap_ret_ann*100, dp$gap_ret_t, dr$gap_ret_t),
      "하방수익 (신호/무신호)"=sprintf("%.1f%% / %.1f%% (완화)", dp$downside_flag*100, dp$downside_nonflag*100),
      "급락(-15%미만) 빈도"=sprintf("%.1f%% / %.1f%% (절반)", dp$tail_hit_flag*100, dp$tail_hit_nonflag*100),
      "신호종목 시총등급"="대형173 · 중형104 · 소형0 (전량 배포권)",
      "직전월 밀기 스트레스"=sprintf("수익차t %.2f (붕괴 아님 = 동월누출 아님)", dl$gap_ret_t),
      "★바스켓 경로위험 (자본축·교란)"=sprintf("신호 최대낙폭 %.1f%% vs 무신호 %.1f%% — 악화=분산손실(%.1f vs %.1f종)", dp$cohort_mdd_flag*100, dp$cohort_mdd_nonflag*100, dp$avg_flag_per_month, dp$avg_nonflag_per_month),
      "현 북 감시판정 (202607)"=sprintf("안전 %d · 중립 %d · 데이터無 %d (대기)", wb$n_net_buy_safe, wb$n_neutral, wb$n_no_insider_data))),
  list(type="bullet", emoji="🚩", heading="판정 · 주의 (평문)",
    items=c(
      "판정: 능력확립(capability_established) — 감시신호 배선·북레벨 확증.",
      "★자본 아님: 종목별 유지-안전(고수익+급락회피)이지 비중확대 아님.",
      "바스켓 경로위험은 신호가 오히려 악화 — 소수집중 분산손실, 비중배선 금지.",
      "순매도는 R33 무정보 → 참고용만, 경보 아님(경보=지각·감사).",
      "기준 패널=운영코드 정합(§7b) 재사용·외부조회 없음·북 무변경.",
      "배선처: 부실경보 감시파일 C절 + 감시 프롬프트(월간·보고만).")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe)",
    items=c(
      "감시신호 커버리지 확장(지표결합/임계완화) — 현 신호 희소, 대형 표본↑",
      "실제 안전신호 발화 시 실효 표본외 추적 — 익월 실현위험 누적(현 0건 대기)",
      "청산시점 대칭 검정 — 신호 소멸 시 위험 재상승 여부(추가 미래참조 점검)"))
)

tg_agent_brief(
  agent = "Monitoring",
  title = "WT-D20260715_003 R34 insider net-buy de-risk tripwire — 배선 완료 · 북-레벨 capability (자본 아님)",
  sections = sections,
  charts = c(c1, c2, c3),
  as_of = "2026-07-15")
cat("[telegram] sent with 3 charts\n")
