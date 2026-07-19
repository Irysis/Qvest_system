# =============================================================================
# FQ-063 run_04: 텔레그램 v7 브리핑 (tg_agent_brief 단일 진입점)
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
OUT_DIR<-file.path(ROOT,"stage_artifacts/method_frontier")
m<-fromJSON(file.path(OUT_DIR,"fq063_metrics.json"), simplifyVector=FALSE)
gp<-function(c) m$cells[[c]]$port_t_capw
pv<-m$paired_best_vs_baseline$A_LinearTilt

charts<-c(file.path(OUT_DIR,"fq063_chart_sweep_port_t.png"),
          file.path(OUT_DIR,"fq063_chart_modeB_sigma.png"))
charts<-charts[file.exists(charts)]

sections<-list(
  list(type="bullet", emoji="\U0001F4DA", heading="연구 컨텍스트",
    items=c(
      "질문(도훈): lw_nls 공분산 기반으로 비중결정 방법을 고르면 유의한가",
      "NP4는 MVO 한 방법만 측정(NULL). 본 라운드=8-방법 스윕 + 위험선택 전방법 실측",
      "알파 base=production STR_1715 score_eff(파리티), K200+KQ150, 27셀 x 198개월")),
  list(type="bullet", emoji="\U0001F4D6", heading="쉬운 설명",
    items=c(
      "같은 종목 점수 위에서 '비중 나누는 법' 27개를 16년 나란히 운용",
      "기준선=알파비례(LinearTilt, 현 방식). 도전자=MVO/HRP/ERC/MaxDiv/GMV/CVaR",
      "결과: 어떤 똑똑한 방법도 '점수 높은 종목에 비례'를 못 이김",
      "lw_nls가 위험모델 제대로 돌려도 저변동만 골라 수익이 오히려 뒤짐")),
  list(type="bullet", emoji="\U0001F52C", heading="실측 (canonical PORT_t, cap-w)",
    items=c(
      sprintf("기준선 LinearTilt %.2f · 현운용 prodLT20 %.2f(전셀최고) · EW %.2f", gp("A_LinearTilt"), gp("A_prodLT20"), gp("A_EW")),
      sprintf("best-of-sweep CVaR %.2f(미달) · MVO %.2f · GMV %.2f · HRP %.2f", gp("A_CVaR"), gp("A_MVO"), gp("A_GMV"), gp("A_HRP")),
      sprintf("best vs LinearTilt paired NW-t %.2f (연 %.1f%%p, 초과 아님)", pv$nw_t_lag3, pv$ann_diff*100),
      sprintf("Mode B lw_nls GMV/MaxDiv 순수 %.2f/%.2f — 퇴화교정 작동하나 더 음수", gp("B_GMV_lwnls_pure"), gp("B_MaxDiv_lwnls_pure")),
      sprintf("DSR %.2f<0.5 FAIL · graduation HARD 0/27", m$dsr$dsr_best))),
  list(type="bullet", emoji="\U0001F9E0", heading="기전 진단",
    items=c(
      "알파비례가 전 최적화/위험방법 지배(single-cluster 북서 위험배분=알파희석)",
      "위험선택=알파선택 대체 — 진짜 min-var일수록 알파서 멀어져 PORT_t 더 음수",
      "최대 레버=비중방법 아닌 종목수(top-20 vs 25 +0.33)=Grinold breadth",
      "상대순위 cap-w + EW-uni 양 basis 강건 — 알파비례 지배는 벤치 무관")),
  list(type="bullet", emoji="\U0001F6A9", heading="판정 + 다음",
    items=c(
      "판정: config-scoped negative — 방법선택 성과-축 부가가치 없음(NP4 강화)",
      "lw_nls 가치는 위험-축(risk_package 대형 공분산) 유지, 성과-축은 미달",
      "병목 지도 5행: MVO-only -> 전방법 소진 확정. 갭 귀속(1 재료) 불변",
      "부활(INV-7): 위험배분=multi-sleeve 시만 · TC-aware MVO 재측정")))

r<-tg_agent_brief(agent="Optimizer",
  title="FQ-063 METHOD-SELECT — lw_nls 방법선택 canonical PORT_t A/B (판정 config-scoped negative)",
  sections=sections, charts=charts, relaxed=TRUE)
cat("[telegram] sent:", isTRUE(r$ok) || !is.null(r), "\n")
cat("[done] run_04\n")
