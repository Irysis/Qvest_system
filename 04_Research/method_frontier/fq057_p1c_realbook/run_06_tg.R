# =============================================================================
# FQ-057 NP4-P1c run_06: charts(base R png) + telegram(v7)
#   차트 수치 = p1c_metrics.json 계약값만 (손계산 금지).
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
M <- fromJSON(file.path(OUT_DIR,"p1c_metrics.json"), simplifyVector=FALSE)

gt <- function(pf,tg,pair) M$results_full_range[[pf]][[tg]]$paired[[pair]]$dm_nw_t_lag3
gq <- function(pf,tg,arm) M$results_full_range[[pf]][[tg]]$arm_summary[[arm]]$mean_qlike

PFS <- c("capw_mom_proxy","real_book_fullinv","real_book_overlaid")
lab <- c("cap-w mom\n(P1 proxy)","real book\nfullinv","real book\noverlaid")

# ---- Chart 1: (a) lw_nls vs linear-LW DM-t — TE vs TOTAL 채널 (핵심) ---------
c1 <- file.path(OUT_DIR,"p1c_chart_dm_channel.png")
te_dm  <- sapply(PFS, function(pf) gt(pf,"te","a_lwnls_vs_lwlinear"))
tot_dm <- sapply(PFS, function(pf) gt(pf,"total","a_lwnls_vs_lwlinear"))
png(c1, width=1150, height=620, res=110); par(mar=c(5,4.5,3.5,1))
Mt <- rbind(TE=te_dm, TOTAL=tot_dm)
bp <- barplot(Mt, beside=TRUE, col=c("#1f77b4","#d62728"), border=NA, ylim=c(min(tot_dm)*1.15,1),
  names.arg=lab, ylab="DM-t (lw_nls - linear LW, 음수=lw_nls 우월)",
  main="(a) lw_nls vs 현행 linear LW: TE 채널은 실 book서 유의성 소실 / TOTAL은 유지",
  legend.text=c("TE (추적오차)","TOTAL (총분산)"), args.legend=list(x="bottomleft",bg="white"))
abline(h=-2, lty=2, col="gray40"); text(1, -2.2, "유의 임계 t=-2", col="gray40", cex=0.8, pos=4)
text(bp, ifelse(Mt<0,Mt-0.15,Mt+0.15), sprintf("%.2f",Mt), cex=0.85)
dev.off()

# ---- Chart 2: 실 book TE QLIKE by arm (fullinv vs overlaid) -------------------
c2 <- file.path(OUT_DIR,"p1c_chart_qlike_te.png")
arms <- c("lw_linear","lw_nls","ewma_struct","ewma_direct")
q_full <- sapply(arms, function(a) gq("real_book_fullinv","te",a))
q_over <- sapply(arms, function(a) gq("real_book_overlaid","te",a))
png(c2, width=1100, height=560, res=110); par(mar=c(5,4,3.5,1))
Mq <- rbind(fullinv=q_full, overlaid=q_over)
barplot(Mq, beside=TRUE, col=c("#1f77b4","#2ca02c"), border=NA, names.arg=arms,
  ylab="mean QLIKE (낮을수록 우월)",
  main="실 book TE-분산 예측손실 by arm — lw_nls~linear LW tie (proxy와 달리)",
  legend.text=c("real book fullinv","real book overlaid"), args.legend=list(x="topright",bg="white"))
dev.off()

# ---- Chart 3: DM-t sweep (판정 셀 요약) --------------------------------------
source(file.path(ROOT,"02_Infrastructure/telegram/tg_chart_pack.R"))
c3 <- tg_chart_sweep(
  labels=c("proxy TE-a","fullinv TE-a","overlaid TE-a","fullinv TOT-a","overlaid TOT-a","fullinv TE-b","overlaid TE-b"),
  values=c(gt("capw_mom_proxy","te","a_lwnls_vs_lwlinear"),
           gt("real_book_fullinv","te","a_lwnls_vs_lwlinear"),
           gt("real_book_overlaid","te","a_lwnls_vs_lwlinear"),
           gt("real_book_fullinv","total","a_lwnls_vs_lwlinear"),
           gt("real_book_overlaid","total","a_lwnls_vs_lwlinear"),
           gt("real_book_fullinv","te","b_lwnls_vs_ewma_direct"),
           gt("real_book_overlaid","te","b_lwnls_vs_ewma_direct")),
  out_dir=OUT_DIR, title="DM-t 판정 셀 (음수=lw_nls 우월, 임계 -2) — a:vs linear LW / b:vs EWMA-direct",
  filename="p1c_sweep_dmt.png")
charts <- c(c1,c2,c3); charts <- charts[file.exists(charts)]
cat("[charts]", length(charts), "png\n")

# ============================ TELEGRAM (v7) ==================================
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
te_a_full <- gt("real_book_fullinv","te","a_lwnls_vs_lwlinear")
te_a_over <- gt("real_book_overlaid","te","a_lwnls_vs_lwlinear")
tot_a_full<- gt("real_book_fullinv","total","a_lwnls_vs_lwlinear")
te_b_full <- gt("real_book_fullinv","te","b_lwnls_vs_ewma_direct")
proxy_a   <- gt("capw_mom_proxy","te","a_lwnls_vs_lwlinear")
proxy_b   <- gt("capw_mom_proxy","te","b_lwnls_vs_ewma_direct")

sections <- list(
  list(type="bullet", emoji="\U0001F4DA", heading="연구 컨텍스트",
    items=c(
      "P1은 위험모델 공분산 판정을 'book 형태 대용치(cap-w 모멘텀)'로 측정 = 정직 caveat",
      "P1c: 실 배포 book(STR_1715 x m4 x R05)의 실제 active 비중으로 재확인",
      "실 book 비중 = score_eff 상위 20종 LinearTilt x 투자비율(m4 x R05) — production 코드 레시피",
      "동일 사전등록 하네스(예측손실 QLIKE + 짝 Diebold-Mariano), pin 상속")),
  list(type="bullet", emoji="\U0001F4D6", heading="쉬운 설명",
    items=c(
      "질문: P1의 판정(위험모델용 lw_nls 채택 / 감시 기준선은 단순 지수가중 유지)이 진짜 book에서도 성립?",
      "결과: 감시 기준선 유지(나)는 그대로 성립 — 실 book서도 견고",
      "결과: 위험모델 채택(가)은 '방향'은 성립하나 P1이 내세운 추적오차 근거는 대용치 특유 효과였음",
      "이유: cap-w 모멘텀은 소수 대형주 집중 = 상관관계 의존 큼 → 현행 부품 페널티 과장. 실 book은 분산돼 그 효과 사라짐")),
  list(type="bullet", emoji="\U0001F52C", heading="실측 수치 (핵심)",
    items=c(
      sprintf("하네스 검증: P1 대용치 재현 검정t %.2f (P1 원본 -3.06) = 완전 일치", proxy_a),
      sprintf("실 book 추적오차 (가): 검정t %.2f(fullinv) / %.2f(overlaid) = 무승부 (P1 -3.06서 소실)", te_a_full, te_a_over),
      sprintf("단 총분산 채널은 실 book도 유지: 검정t %.2f = lw_nls 강건 우월", tot_a_full),
      sprintf("(나) lw_nls vs 직접 지수가중 검정t %.2f = 무승부 → 기준선 유지 확증", te_b_full))),
  list(type="bullet", emoji="\U0001F9E0", heading="기전 진단",
    items=c(
      "현행 linear LW 페널티는 active 비중의 상관 의존도에 비례",
      "cap-w 모멘텀 대용치 = 집중 베팅 → 현행 크게 오차 → lw_nls 크게 이김 (proxy 특유)",
      "실 book LinearTilt = 4요인 consensus 중형주 분산 → 대각 지배 → 현행도 추적오차엔 무해(tie)",
      "총분산(보유 20종 자기위험)은 상관 항상 지배 → 현행 25% 과소예측 → lw_nls 유지 (proxy+실book 공통)")),
  list(type="bullet", emoji="\U0001F6A9", heading="판정 + 다음 단계",
    items=c(
      "판정: SPLIT 부분 확증 — (나) 감시 기준선 유지 강건 / (가) 방향+총분산 유지, 추적오차 근거는 proxy 아티팩트",
      "운영 존속: 위험모델 대형 공분산 = lw_nls 유지(어디서도 열등 아님 + 총분산 지배)",
      "정당화 정정: 'TE 개선'이 아니라 '총분산/집중-active 안전'으로 서술 (posterior 반영 완료)",
      "다음 프로브: active 집중도 x lw_nls 추적오차 우위 규칙화 · 형태추적 총위험 경보",
      "자본/비중 주장 없음 (위험 예측정확도 진단)")))

r <- tg_agent_brief(agent="Risk",
  title="FQ-057 P1c REALBOOK — 위험정확도 SPLIT 실book 재확인 (b 확증 / a 근거축소=proxy 아티팩트)",
  sections=sections, charts=charts)
cat("[telegram] sent:", !is.null(r), "\n")
cat("[done] run_06 complete\n")
