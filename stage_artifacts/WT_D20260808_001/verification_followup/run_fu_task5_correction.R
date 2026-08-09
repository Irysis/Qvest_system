# =============================================================================
# run_fu_task5_correction.R — ⑤ 거짓 서술 정정 기록을 두 정본에 **동시** 반영
#   조정자 지목: "D03 5분위 평균이 Q1 +13.1% → Q5 +8.0% 단조 감소" = 거짓 서술.
#   ★전달받은 계열을 전사하지 않고 직접 재서 쓴다 (probe_d03_quintile.R).
#   0.79/0.81 오라벨(사전 기대치를 '관측'으로)도 함께 기록.
# =============================================================================
suppressPackageStartupMessages({library(jsonlite); library(data.table)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260808_001")
say <- function(f,...) cat(sprintf(paste0("[fu5] ",f,"\n"),...))
Q <- readRDS(file.path(FU,"fu_d03_quintile.rds"))
rep_ <- Q$repaired; sup_ <- Q$superseded

# 사전등록에서 0.79/0.81 의 정체를 **원 필드에서** 확인 (전사 금지)
pre <- fromJSON(file.path(OUT,"preregistration.json"), simplifyVector=FALSE)
pf <- pre$power_prereg$prior_effect_from_F1
if (is.null(pf)) { # 경로 탐색 (구조 가정 금지)
  findp <- function(x, path="") { if (!is.list(x)) return(NULL)
    if (!is.null(x$prior_effect_from_F1)) return(list(path=path, val=x$prior_effect_from_F1))
    for (n in names(x)) { r <- findp(x[[n]], paste0(path,"$",n)); if (!is.null(r)) return(r) }; NULL }
  hit <- findp(pre); pf <- hit$val
  say("prior_effect_from_F1 실제 경로 = preregistration.json%s", hit$path)
}
say("사전 기대치 원본: D03 implied_delta_ann_pct=%s · Q01=%s",
    pf$D03_EWMA$implied_delta_ann_pct, pf$Q01_EB$implied_delta_ann_pct)
stopifnot(!is.null(pf$D03_EWMA$implied_delta_ann_pct))

val0 <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
obs_d03 <- NULL; obs_q01 <- NULL
for (c_ in val0$consumption_face_b_exclusion$cells) {
  if (identical(c_$cell,"W1_recon_ew25") && identical(c_$factor,"D03_EWMA")) obs_d03 <- c_$d_ann_pct
  if (identical(c_$cell,"W1_recon_ew25") && identical(c_$factor,"Q01_EB"))   obs_q01 <- c_$d_ann_pct }
say("실제 관측(W1_recon_ew25 q20): D03 %+.3f%%/yr · Q01 %+.3f%%/yr", obs_d03, obs_q01)

CORR <- list(
  correction_id = "false_statement_correction_20260809",
  raised_by = "적대검증 종합 (행 번호 특정) → 본 라운드가 독립 재측정으로 확인",
  claim_A = list(
    false_statement = "D03 5분위 평균수익이 Q1 +13.1% → Q5 +8.0% 로 **단조 감소**",
    measured = list(
      repaired_panel_quintile_ann_pct = rep_$quintile_ann_pct,
      superseded_panel_quintile_ann_pct = sup_$quintile_ann_pct,
      argmax_quintile = sup_$argmax, q1_to_q2_pp = sup_$q1_to_q2_pp,
      monotonicity = sup_$monotonicity,
      spread_q5_minus_q1_ann_pct = list(repaired = rep_$spread_q5_q1_ann_pct,
                                        superseded = sup_$spread_q5_q1_ann_pct),
      spread_t_nw_lag3 = list(repaired = rep_$spread_t_nw, superseded = sup_$spread_t_nw),
      spread_ci_ann_pct_superseded = sup_$spread_ci,
      rank_ic_superseded = round(sup_$rank_ic,6), rank_ic_harvey_t_superseded = round(sup_$rank_ic_harvey_t,3)),
    corrected_statement = sprintf(paste0("Q2 정점 역U + 상위 3분위 하락. Q1→Q2 는 %+.2f%%p **상승**하고 ",
      "하락은 Q3→Q5 구간에 국한된다. Q5−Q1 평균 스프레드는 연 %+.2f%%(NW t %+.2f, CI [%+.2f, %+.2f]) 로 **비유의**. ",
      "확립 사실은 '역전'이 아니라 **'순위/중앙값 양(+) ∧ 평균 스프레드 비유의'**."),
      sup_$q1_to_q2_pp, sup_$spread_q5_q1_ann_pct, sup_$spread_t_nw, sup_$spread_ci[1], sup_$spread_ci[2]),
    self_contradiction = "같은 문장이 함께 보고한 monotonicity 0.25 가 이미 비단조를 뜻한다 — 수치와 서술이 자기모순이었고 아무도 검산하지 않았다.",
    downstream_impact = paste0("이 서술은 '고변동 꼬리의 양의 왜도가 평균을 끌어올린다' → 'WT-021 D03 standalone PORT_t −1.73 의 산술적 정체' → ",
      "'제거 대상이 평균 기여가 높은 종목이라 희석이 손해' 로 3단 연결됐다. 평균 스프레드가 비유의인 이상 ",
      "이 연쇄는 **약한 후보**로만 남으며 '확립'으로 인용할 수 없다."),
    propagation_sites_corrected = c(
      "qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json (challenge_flags)",
      "qepm/mailbox/worktask/WT-D20260808_001/challenge_note.md:87",
      "qepm/mailbox/worktask/WT-D20260808_001/challenge_note_contract_repair.md:80",
      "stage_artifacts/WT_D20260808_001/alpha_validation_replication_20260808.json:56(headline),:60(interpretation)",
      "stage_artifacts/WT_D20260808_001/create_wt2.R:10",
      "stage_artifacts/WT_D20260808_001/repair_package_contract.R:176",
      "stage_artifacts/WT_D20260808_001/alpha_validation.json (본 블록)"),
    preservation = "전 지점에서 구 문구를 삭제하지 않고 superseded_/취소선/주석으로 보존."),
  claim_B = list(
    false_label = "'관측 0.79%/0.81%' (create_wt2.R:9 · send_brief.R:18)",
    actual_identity = "preregistration.json::power_prereg 의 prior_effect_from_F1.implied_delta_ann_pct — F1(분위 gap)에서 유도한 **사전 기대치**이며 관측이 아니다.",
    prereg_values = list(D03_EWMA = pf$D03_EWMA$implied_delta_ann_pct, Q01_EB = pf$Q01_EB$implied_delta_ann_pct),
    actual_observation_ann_pct = list(cell = "W1_recon_ew25 q20", D03_EWMA = obs_d03, Q01_EB = obs_q01),
    corrected_statement = sprintf(paste0("사전 기대치(F1 기반 예측) +0.79%%/+0.81%% 대비 **실제 관측은 D03 %+.2f%%/yr(부호 반대) · ",
      "Q01 %+.2f%%/yr** 이다. 사전 기대치를 관측으로 표기하면 '예측이 맞았다'는 인상을 주는데 ",
      "D03 은 방향 자체가 반대였다."), obs_d03, obs_q01),
    propagation_sites_corrected = c("stage_artifacts/WT_D20260808_001/create_wt2.R:9",
      "stage_artifacts/WT_D20260808_001/send_brief.R:18")),
  lesson = paste0("두 오류의 공통 기전 = **자기 결론을 지지하는 방향의 수치를 검산 없이 승격**. ",
    "A 는 원 데이터 배열이 바로 옆에서 반증하고 있었고(quintile 배열 · monotonicity 0.25), ",
    "B 는 원 필드명(prior_effect_from_F1)이 정체를 명시하고 있었다. ",
    "둘 다 '값을 옮길 때 출처 필드를 함께 읽었으면' 막혔다 — audit_input 이 강제하려는 그 습관이다."),
  provenance = "stage_artifacts/WT_D20260808_001/verification_followup/probe_d03_quintile.R + preregistration.json 원 필드 조회")

for (f in c(file.path(MB,"alpha_package.json"), file.path(OUT,"alpha_validation.json"))) {
  j <- fromJSON(f, simplifyVector=FALSE)
  j$verification_followup_20260809$task5_false_statement_correction <- CORR
  write_json(j, f, pretty=TRUE, auto_unbox=TRUE, digits=NA, null="null")
  say("갱신: %s", basename(f))
}
p <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
v <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
a <- p$verification_followup_20260809$task5_false_statement_correction$claim_A$measured$spread_t_nw_lag3$superseded
b <- v$verification_followup_20260809$task5_false_statement_correction$claim_A$measured$spread_t_nw_lag3$superseded
say("동시 갱신 정합: package %s ↔ validation %s : %s", a, b, if (isTRUE(all.equal(a,b))) "일치" else "★불일치")
stopifnot(isTRUE(all.equal(a,b)))
say("=== ⑤ 정정 반영 완료 ===")
