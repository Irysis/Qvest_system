## R40 텔레그램 v7 판정 보고 (원칙 9 — 차트 첨부 의무 · 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_009"
r <- fromJSON(file.path(OUT,"r40_results.json"))
cA <- file.path(QM, OUT, "chart_A_censoring_census.png")
cB <- file.path(QM, OUT, "chart_B_multimonth_trajectory.png")
cC <- file.path(QM, OUT, "chart_C_worstcase.png")

wc <- r$P2_worstcase; mm <- r$P1_multimonth; cen <- r$P2_census$mid$outcome

sections <- list(
  list(type="summary", emoji="📌",
    body="R38 no-hangover의 검열편향 걱정 = 정량 결과 기우(immaterial). 단 보호막은 무기한 아닌 '~1개월'로 교정 (자본 아님)."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "R38 결론: 임원 순매수 안전신호가 꺼져도(청산) 그 종목 위험이 다시 오르지 않았다.",
      "걱정(검열편향): R38은 '다음달에도 투자가능한 종목'만 봤다.",
      "신호 꺼지자마자 상폐·유동성붕괴로 사라진 나쁜 종목이 표본서 빠졌을 수 있다.",
      "검증: 사라진 종목을 census(전수)하고 -100% 상폐손실까지 대입해 결론 확인.",
      "결과①: 투자가능 유니버스서 사라진 종목 거의 없음(중형 2건·21년 진성폐지 0건).",
      "결과②: 안전신호 종목이 무신호보다 더 자주 사라지지도 않음(통계 무유의).",
      "결과③: 사라진 2건에 -100% 대입해도 청산월 급락빈도가 무신호보다 여전히 낮음.",
      "★부수: 보호막은 청산 직후 1개월만 뚜렷·2-3개월 뒤 평범 복귀(약함·무유의).",
      "★자기검증이 패널 마지막달(2026-05) 오분류를 finalize 전 검거 → 결론 반전 방지.")),
  list(type="kv", emoji="📊", heading=sprintf("핵심 수치 (MID 중형층=안전신호 서식지 · 청산 전이 %d건)", cen$EXIT_obs),
    kv=list(
      "검열 실체 (사라진 종목)"=sprintf("MID %d건(0.2%%) · 진성 상장폐지 21년간 0건", cen$CENSORED),
      "차등검열 (안전 vs 무신호 이탈률)"=sprintf("0.209%% vs 0.107%% · p=%.3f (차이 무유의)", r$differential_censoring$tests$mid_leave_p),
      "최악대입: 청산월 급락빈도"=sprintf("R38 관측 %.1f%% → 검열대입후 %.1f%% (무신호 %.1f%% 미만 유지)", wc$r38_exit_obs$tail*100, wc$scenarios$wipeout$tail*100, wc$off_baseline$tail*100),
      "상폐손실 −100%% 대입 결과"=sprintf("위험 보호막 유지=%s (검열편향 없음)", wc$scenarios$wipeout$risk_sticky),
      "청산후 급락빈도 궤적 (0→3개월)"=sprintf("%.1f%% → %.1f%% → %.1f%% → %.1f%% (무신호 %.1f%%)", mm$h0$tail*100, mm$h1$tail*100, mm$h2$tail*100, mm$h3$tail*100, wc$off_baseline$tail*100),
      "청산후 수익우위 궤적 (다중검정 t값)"=sprintf("%+.2f → %+.2f → %+.2f → %+.2f (전구간 |t|<2 비유의)", mm$h0$paired_vs_off_t, mm$h1$paired_vs_off_t, mm$h2$paired_vs_off_t, mm$h3$paired_vs_off_t),
      "청산 유형 (소관)"=sprintf("정상청산(SAFE_FADING) 98.3%% · 파국청산(부실 tripwire) 0.9%%"))),
  list(type="bullet", emoji="🚩", heading="판정 · 주의 (평문)",
    items=c(
      "판정: 능력확립(capability_established) — R38 no-hangover 검열편향 기우로 확인.",
      "★자본 아님: 종목별 '유지 안전' 특성화이지 비중·매매 신호 아님.",
      "★교정: R38 '보호막 무기한'은 과독 → '~1개월'. SAFE_FADING 1-2개월 자동해제.",
      "한계①: 결론은 투자가능(K200∪KQ150+거래대금 2억) 조건부.",
      "검열 적은 이유=투자가능 종목이 청산 동시 사라지는 일 드물어서. 소형 상폐는 부실 tripwire 소관.",
      "한계②: 다중월 2-3개월 재악화는 방향성일 뿐 통계 무유의(과대해석 금지).",
      "자기검증이 관측창 경계 오분류를 finalize 전 검거 → false-reversal 방지.")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe) · insider 라인(R9~R40) 검열 최종 진단",
    items=c(
      "SAFE_FADING 실배선: 무기한 아닌 1개월 fade→2개월 자동해제 (filing_delay_watch Part C).",
      "부실 tripwire 확장: 상폐 집중되는 소형·비투자가능 영역 census 확장 (FQ-038 결합).",
      "insider 재료(R9~R40) = monitoring 소비면 확립 완료 (자본 미검 불변)."))
)

tg_agent_brief(
  agent = "Monitoring",
  title = "WT-D20260715_009 R40 insider SAFE 청산 검열-스트레스 — R38 no-hangover 검열편향 기우로 확인(immaterial)·보호막은 ~1개월 (자본 아님)",
  sections = sections,
  charts = c(cA, cB, cC),
  as_of = "2026-07-15")
cat("[telegram] sent with 3 charts\n")
