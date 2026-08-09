# =============================================================================
# run_fu_close.R — 결함 고지문 해소 기록 + FQ-122 서브라운드 상태 갱신
#   원장 기록은 정본 writer(02_Infrastructure/ops/frontier_queue_io.R) 경유 — 직접 toJSON 금지.
# =============================================================================
suppressPackageStartupMessages({library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
say <- function(f,...) cat(sprintf(paste0("[close] ",f,"\n"),...))
T13 <- readRDS(file.path(FU,"fu_task13_results.rds")); T2 <- readRDS(file.path(FU,"fu_task2_results.rds"))
T3S <- readRDS(file.path(FU,"fu_task3_supp.rds")); T4 <- readRDS(file.path(FU,"fu_task4_results.rds"))
Q5 <- readRDS(file.path(FU,"fu_d03_quintile.rds"))
f3d <- T13$task1_raw_gap$D03_EWMA; f3q <- T13$task1_raw_gap$Q01_EB
s3d <- T13$task3_sector_gap$D03_EWMA__Sector; s3q <- T13$task3_sector_gap$Q01_EB__Sector
ret_d <- sapply(T3S[grep("^D03",names(T3S))],function(x)x$retention)
ret_q <- sapply(T3S[grep("^Q01",names(T3S))],function(x)x$retention)

# ── 1. 결함 고지문 해소 기록 ─────────────────────────────────────────────────
NF <- file.path(OUT,"alpha_scores_PANEL_DEFECT_NOTICE.json")
n <- fromJSON(NF, simplifyVector=FALSE)
n$resolution_20260809 <- list(
  status = "RESOLVED",
  resolved_by = "alpha-research · verification_followup_20260809 (run_fu_task4_emit_repair.R)",
  rows_before = T4$rows_old, rows_after = T4$rows_new, rows_removed = T4$rows_old - T4$rows_new,
  emitted_basis = T4$universe_basis,
  verification = sprintf("재발행판 자A 미달 %d · 자B(고지문 절차) 미달 %d · 결측 0 → CLEAN. 위반 주입(필터 제거판) → 자A %d · 자B %d 미달로 VIOLATION 발화 = 검사 실효 확인.",
    T4$check_new$n_fail_contract, T4$check_new$n_fail_raw20,
    T4$check_injected$n_fail_contract, T4$check_injected$n_fail_raw20),
  superseded_panel = "stage_artifacts/WT_D20260808_001/alpha_scores_superseded_20260809.parquet",
  advisory_battery = "재산출 완료 — alpha_package.json::diagnostics (구 값은 diagnostics.superseded_20260808_pre_liquidity_repair 보존)",
  alpha_vector = "최신월 25종 불변 — 본 고지문의 'NOT_contaminated: 벡터는 청정' 주장 확인",
  correction_to_this_notice = paste0("본 고지문의 note_on_differing_figure(3.31% vs 5.03% 를 '측정 패널과의 차분 vs 직접 적용' 으로 설명)는 ",
    "**부정확하다**. 실측 결과 둘은 서로 다른 **유동성 자**의 산물이다: 자B(rawdata 20일 평균) 미달 2,875행 · ",
    "자A(계약 liq_dt = Vol0*Close0 월말 1일치) 미달 4,376행. 4,376 은 86,942 − 82,566(eligible_set 차분)과도 ",
    "정확히 일치하는데 eligible_set 이 곧 자A 필터이기 때문이며, 두 설명은 모순이 아니라 같은 수를 다르게 부른 것이다."),
  newly_found = paste0("★파생 발견: 판정 유니버스(eligible_set 82,566행) 자체도 Production Constraints 정의(20일 평균)로 재면 ",
    "395행(0.478%)이 미달이고, **실제 선별된 top-25 중 224~225 종-월(3.04%)이 20일-ADV 2e8 미만**이다(92~96개월에 분포, ",
    "미달 종목 adv20 중앙 1.14e8, 최다 월 2003-03 16종). 즉 결함은 발행 패널에 국한되지 않고 판정 arm 의 유동성 축에도 ",
    "닿아 있다. 이는 계약 함수의 라벨↔구현 불일치에서 오며 본 WT 가 단독 수리할 수 없다 — 인프라 상신 대상."))
write(toJSON(n, auto_unbox=TRUE, pretty=TRUE, null="null", digits=NA), NF)
say("결함 고지문 해소 기록 완료")

# ── 2. FQ-122 서브라운드 상태 ────────────────────────────────────────────────
source("02_Infrastructure/ops/frontier_queue_io.R")
say("원장 형식 정본 여부(무수정 왕복 바이트 동일): %s", frontier_queue_format_ok())
Q <- read_frontier_queue()
i <- which(sapply(Q$entries, function(x) identical(x$id, "FQ-122")))[1]
stopifnot(!is.na(i))
say("FQ-122 인덱스 %d", i)
e <- Q$entries[[i]]
vf <- e$verification_followup_20260809
vf$status <- "completed"
vf$completed_at <- "2026-08-09"
vf$outcome <- list(
  task1_f3_hac = sprintf("교정 완료. gap 계열 ACF r1 %.3f/%.3f 에서 lag-3 은 무효 추론량 — t %.2f/%.2f → **NW lag-60 %.2f/%.2f** (lag-59 %.2f/%.2f · Andrews %.2f/%.2f · MBB(L=60) %.2f/%.2f). 관측(F3)은 SUPPORTED 유지, 유의성 크기 2.5~3배 축소. 적대검증 기대치(-5.07/-6.67 · MBB -4.76/-6.28)와 일치하나 Andrews 는 불일치(기대 -7.46/-11.63) — 조정하지 않고 병기.",
    f3d$acf_r1, f3q$acf_r1, f3d$nw_lag3$t, f3q$nw_lag3$t, f3d$nw_lag60$t, f3q$nw_lag60$t,
    f3d$nw_lag59$t, f3q$nw_lag59$t, f3d$andrews_qs$t, f3q$andrews_qs$t, f3d$mbb_L60$t, f3q$mbb_L60$t),
  task2_f2 = sprintf("**D03 반증 확정 · Q01 강화 유지**. 회전율(log 거래대금/시총) 통제 시 D03 t %.2f → %.2f, 순위변환+전통제에서 부호 역전 %+.2f. 표본축소(결측 0.018%%)·공선성(VIF 2.05) 아티팩트 아니며 교락 실재(회전율→개인 순매수 t +7.61, D03 z↔회전율 cor -0.559). Q01 은 회전율과 직교(cor -0.001)라 전 9사양 잔존(%.2f → %.2f). ⇒ verdict.b_D03 기전 서술을 **미확립**으로 강등(NOT_CONSUMABLE 불변).",
    T2$f2$D03_EWMA$M0_raw$t_nw_lag3, T2$f2$D03_EWMA$M4_wins_size_turn$t_nw_lag3,
    T2$f2$D03_EWMA$M8_rank_all$t_nw_lag3, T2$f2$Q01_EB$M0_raw$t_nw_lag3, T2$f2$Q01_EB$M4_wins_size_turn$t_nw_lag3),
  task3_sector = sprintf("**크기 불재현 · 방향 재현**. 섹터 정의 3종 x 통계 2종 12셀 전수에서 잔존율 D03 [%.3f, %.3f] · Q01 [%.3f, %.3f] — 렌즈4 의 0.46/0.24 는 두 구간 밖. 실측 섹터 귀속률 = Q01 63~67%% · D03 36~45%%. 주장 A 는 크기 축소하나 존폐는 유지: 섹터-중립 잔차 gap 도 교정 SE 에서 유의(D03 t %.2f · Q01 t %.2f). WT-009 sector_panel 은 RAWDATA Sector 와 동일 결과(독립 정의 아님).",
    min(ret_d), max(ret_d), min(ret_q), max(ret_q), s3d$nw_lag60$t, s3q$nw_lag60$t),
  task4_panel = sprintf("발행 패널 수리 완료 %d → %d행(제거 %d · 5.50%%). 위반 주입 테스트 PASS. 최신월 25종 불변. advisory 배터리 재산출(rank_ic %.6f · Harvey-t %.4f). ★파생 발견: 유동성 축이 **두 양**(계약 adv = Vol0*Close0 1일치 vs Production 20일 평균, 상관 0.929 · 판정 불일치 2.61%%)이고 **판정 arm 의 선별 top-25 중 3.04%%(224종-월)가 20일-ADV 2e8 미만**이다 — 인프라 상신.",
    T4$rows_old, T4$rows_new, T4$rows_old-T4$rows_new, T4$battery_emitted$rank_ic, T4$battery_emitted$harvey_t),
  task5_false_statement = sprintf("조정자 지목 거짓 서술 정정 — 'D03 5분위 단조 감소'는 실측과 어긋난다(**Q2 정점 역U**, Q1→Q2 %+.2f%%p 상승). Q5−Q1 평균 스프레드 연 %+.2f%% (NW t %+.2f) = **비유의**. 확립 사실은 '순위 양(+) ∧ 평균 비유의'. 전파 7지점 동시 정정(구 문구 superseded 보존). 별건 '관측 0.79/0.81%%' 는 사전 기대치(prior_effect_from_F1) 오라벨 — 실제 관측 D03 -3.14%%(부호 반대) · Q01 +1.36%% 병기.",
    Q5$superseded$q1_to_q2_pp, Q5$superseded$spread_q5_q1_ann_pct, Q5$superseded$spread_t_nw),
  capital_claim = "없음 — 판정량 변경 없음. graduation HARD 3종 판정 아님.",
  artifacts = "stage_artifacts/WT_D20260808_001/verification_followup/ (스크립트 8 + rds 5) · 갱신 정본 = alpha_package.json · alpha_validation.json · alpha_scores.parquet",
  challenge_note = "stage_artifacts/WT_D20260808_001/verification_followup/challenge_note_followup.md")
vf$next_probe <- list(
  "NP-F1: 유동성 축 basis 통일 — 계약 build_monthly_forward_returns() 의 adv 를 실제 20일 평균으로 고칠 때 하류 판정이 얼마나 움직이는가(선별 top-25 3.04% 교체 영향). 인프라 소관이나 알파 판정에 직접 닿음.",
  "NP-F2: F2 회전율 통제의 **매개 vs 교락** 구별 — 회전율이 lottery 수요의 결과(매개)라면 통제는 과잉이다. 순위변환+통제에서 부호가 0 을 지나 역전(+2.49)한 것은 단순 매개로 설명되지 않으므로 구조적 검정(예: 회전율 잔차화 대신 계층화, 또는 개인 매수/매도 분해)이 필요.",
  "NP-F3: 섹터-중립 잔차 gap 이 살아남았으므로 **사이즈·유동성까지 동시 중립화**한 β gap 을 재산출 — 남는 성분이 진짜 종목 저β 인지 특성 노출인지 분리.",
  "NP-F4: seeds_24 플라시보 재산출(측정 객체 발행) — 현재 8값은 콘솔 전사이며 재인용 불가.",
  "NP-F5: 검정력 바의 외부 기준 sd 확보 — implied_t_threshold 2.21~2.59 로 현행 바는 t 검정의 재진술이라 INCONCLUSIVE 라벨이 정보를 담지 못한다.")
vf$revival_condition <- "본 서브라운드는 통계 처리 교정이며 FQ-122 본 판정(b_Q01 NOT_ESTABLISHED_BUT_LIVE · b_D03 NOT_CONSUMABLE)을 바꾸지 않는다. 부활 신호 = NP-F1 수리 후 유동성 축이 통일됐을 때, 또는 NP-F3 이 종목-수준 β 성분을 분리해냈을 때 재판정."
e$verification_followup_20260809 <- vf
Q$entries[[i]] <- e
write_frontier_queue(Q)
say("=== FQ-122 서브라운드 상태 갱신 완료 ===")
