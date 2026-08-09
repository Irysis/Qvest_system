## 적대검증 종합 반영 — 큐의 거짓 서술 정정 + 라벨 규칙 제안 철회 (2026-08-09)
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
say <- function(fmt,...) cat(sprintf(paste0("[fix] ",fmt,"\n"),...))

CORR <- paste(
  "★2026-08-09 적대검증(렌즈 4종 + 완전성 비판 + 종합) 반영 — 본 항목이 인용한 서술 2건이 거짓으로 판정됐다.",
  "",
  "① 거짓: 'D03 5분위 평균수익이 Q1 +13.1% -> Q5 +8.0% 로 **단조 감소**'.",
  "   실측 계열 = [13.07, 15.33, 14.63, 11.07, 7.96] = **Q2 정점 역U형**(Q1->Q2 는 +2.2%p 상승).",
  "   같은 문장의 monotonicity 0.25 가 이미 비단조를 뜻하므로 **수치와 서술이 자기모순**이었다.",
  "   정정 서술 = '**Q2 정점 역U + 상위 3분위 하락**'.",
  "",
  "② 표제 대비에 불확실성이 없다: Q5-Q1 **평균** 스프레드 = 연 -5.10%, NW t **-1.07** (0과 구별 불가).",
  "   같은 라운드가 |t| 1.4 셀을 전부 INCONCLUSIVE 로 처분하면서 |t| 1.07 기울기를 '확립'으로 승격 = **증거기준 비대칭**.",
  "",
  "③ 반대 방향 증거가 같은 패널에 있었다: Q5-Q1 **중앙값** 스프레드 = 연 **+12.01%, t +2.57 (유의)**.",
  "   확립된 사실은 '역전'이 아니라 **'순위/중앙값 양(+) ∧ 평균 비유의'** 다. 이것이 양의 rank-IC 와 정합한다.",
  "",
  "④ 왜도 기전은 미확립: 평균-중앙 괴리의 지배항은 3차(왜도 1.4x)가 아니라 **2차 모멘트(SD 2.0x)**.",
  "   기하 보정 시 Q1 우위가 소멸한다. WT 는 왜도를 한 번도 측정하지 않고 귀속했다.",
  "",
  "⑤ 이 서술이 본 항목을 포함해 **8곳에 전파**됐고, 그중 큐 2건이 WT-D20260808_003 사전확률 상향 근거로 쓰였다.",
  "   ⇒ 그 사전확률 근거는 철회한다. (WT-003 자체 결과는 독립적으로 유효 — B2/B3 착지는 이 서술에 의존하지 않는다.)",
  "",
  "원문: stage_artifacts/WT_D20260808_001/ 적대검증 종합 §2. 판정 자체(b_D03 = NOT_CONSUMABLE)는 불변.")

WITHDRAW <- paste(
  "★2026-08-09 **제안 철회**. 적대검증 결론: 현 상태로 등재 불가. 사유 4종 —",
  "① n=1 팩터(D03) 위에서 만든 규칙 ② 근거 통계의 |t| = 1.07 (비유의)",
  "③ basis 취약: 중앙값 basis 로 재면 D03 의 monotonicity 가 0.50 이라 **규칙이 발화조차 안 한다**",
  "④ **정의 미상**: WT 정의(5분위 4스텝 증가비율 in {0,.25,.5,.75,1}) vs 플랫폼 정본",
  "   (02_Infrastructure/ml_pipeline/quality_metrics.py:77-98 = 10분위 Spearman in [-1,1]).",
  "   alpha_research_init.md:304 의 예시 0.87 · :366 의 '<0.5 붕괴' 는 WT 정의로 **도달 불가능한 값**이다.",
  "⇒ 재제안 조건 = ①정의 통일 선행 ②다수 독립 재료에서 형태 재현 ③배선 전 효용 검정(라벨이 판정을 실제로 가르는가).",
  "   FQ-166 이 5재료 3형태를 확립했으므로 ②의 재료는 생겼다 — 단 ①이 여전히 미해소.")

n_corr <- 0L
for (i in seq_along(E)) {
  b <- paste(unlist(E[[i]]), collapse=" ")
  if (grepl("13.1%", b, fixed=TRUE) || grepl("13.07", b, fixed=TRUE) || grepl("monotonicity 0.25", b, fixed=TRUE)) {
    E[[i]]$adversarial_verification_20260809 <- CORR
    n_corr <- n_corr + 1L
    say("정정 부착: %s", if (is.null(E[[i]]$id)) "?" else E[[i]]$id)
  }
  if (grepl("transfer_negative_component", b, fixed=TRUE)) {
    E[[i]]$label_rule_proposal_status <- "WITHDRAWN_20260809"
    E[[i]]$label_rule_withdrawal_reason <- WITHDRAW
    say("라벨 규칙 철회 표기: %s", if (is.null(E[[i]]$id)) "?" else E[[i]]$id)
  }
}
say("정정 부착 항목 수: %d", n_corr)
if (n_corr == 0L) say("★0건 — 스캐너 의심. 결과로 쓰지 말 것.")
q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
say("완료")
