## run_ramp_r15_emit.R — R15 L-code 적립 (mode=ramp, backtested, construction_type=composite, selection_type=chain)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/ramp/ramp_loop.R")
RUNTAG <- "20260713"
TAB <- as.data.table(read_parquet(sprintf("outputs/ramp/r15_fill_gates_%s.parquet", RUNTAG)))
PAIRED <- as.data.table(read_parquet(sprintf("outputs/ramp/r15_fill_paired_%s.parquet", RUNTAG)))
RES <- fromJSON(sprintf("outputs/ramp/r15_fill_summary_%s.json", RUNTAG))
g <- function(m,c) TAB[model==m, get(c)]
pf <- function(m) PAIRED[model==m, paired_t_full]
CH <- RES$challenge

lesson <- paste0(
 "RAMP R15 충원(fill) 규율 축(FQ-028, R14 next_probe 1순위 소비): 퇴출 트리거를 챔피언 F-1(순위-단독)에 고정하고 ",
 "빈 슬롯 충원 규율만 변주(수준-fill/신선-fill/무-fill 축소/일관성-fill). R14 ④(ctrl_D2 fill 선택만으로 cap-w 2.406↔2.503 이동)이 ",
 "노출한 퇴출-직교 다이얼. entry(반기 top-K20 level36)·exit(F-1 rank-only 분기) 전 arm 고정 — 차이는 순수히 fill에 귀속. ",
 "weighted_screen_bt 계약경로(cap-w authoritative nwt act_bm). parity: R6 anchor Δ=1.4e-5·",
 sprintf("base_F1(level36-fill) cap-w=%.4f == R14 ctrl_F1 2.937(Δ=2.4e-5, 3-소수 정확 재현 Δ=0.000). ", g("base_F1_level36fill","port_t_capwt")),
 sprintf("결과: base F-1 cap-w=%.3f oos=%.3f. L-1(신선-recent18-fill) cap-w=%.3f oos=%.3f paired=%.2f. ",
   g("base_F1_level36fill","port_t_capwt"), g("base_F1_level36fill","oos_retention"),
   g("armL1_fresh_fill","port_t_capwt"), g("armL1_fresh_fill","oos_retention"), pf("armL1_fresh_fill")),
 sprintf("L-2(무-fill 축소) cap-w=%.3f oos=%.3f paired=%.2f. L-3(일관성-12m×3-min-fill) cap-w=%.3f(최근접)·oos=%.3f(최고)·EW-uni oos %.3f·paired=%.2f. ",
   g("armL2_nofill_shrink","port_t_capwt"), g("armL2_nofill_shrink","oos_retention"), pf("armL2_nofill_shrink"),
   g("armL3_consist_fill","port_t_capwt"), g("armL3_consist_fill","oos_retention"), g("armL3_consist_fill","oos_ew"), pf("armL3_consist_fill")),
 sprintf("판정 config_scoped_negative(충원 규율 config 한정): 어떤 fill 규율도 level36-fill(챔피언 F-1 기본값 %.3f)의 cap-w를 넘지 못함 — best cap-w arm=L-3 2.890(<F-1)·best oos arm=L-3 +0.079(base +0.048, Δ+0.030 nominal). HARD 3종 0/5(전 model cap-w<2.95·oos<0.7·calmar<0.64)·max full paired %.3f(<2.0). ",
   g("base_F1_level36fill","port_t_capwt"), max(pf("armL1_fresh_fill"),pf("armL2_nofill_shrink"),pf("armL3_consist_fill"))),
 "확립 지식: ",
 sprintf("(1) [challenge①] L-2 무-fill은 K 축소 sweep과 수렴 안 함 — 유효 K(pool 평균) %.2f(K20 근접, min 11은 반기 진입 직전 일시적, 진입서 완전 재충전)·R6 K10 cap-w 1.905와 다른 지대. 오히려 L-2 cap-w 2.652 ≈ R6 no-exit 2.612 → F-1의 cap-w 우위(2.612→2.937)는 '퇴출 자체'가 아니라 '퇴출 슬롯을 level36-top으로 재충원'에서 나온다는 직접 증거. ",
   CH$pool_size$L2$mean),
 sprintf("(2) [challenge②] L-1 신선-fill은 FM 수렴 안 함 — fill-only recent18은 pool FM화 실패(Jaccard L-1↔FMpure %.3f vs base↔FMpure %.3f=Δ+0.024만·L-1↔base %.3f, fresh_frac 0.78로 다른 팩터 뽑으나 분기당 ~2슬롯이라 pool 골격 불변). R13 D-1 전면선별 FM수렴(0.713)과 대조. fill-only가 FM 오염 구조적 억제. 단 신선-fill은 cap-w 악화(모멘텀-hot·level-weak 재유입 희석). ",
   CH$jaccard$L1_FM, CH$jaccard$base_FM, CH$jaccard$L1_base),
 sprintf("(3) [challenge③] fill=저빈도 다이얼(검정력 한계 정직) — exit-only anchor 37개(교대구조 반기당 1회)·anchor당 배출 slots 평균 1.95·arm간 pool 94~96%% 겹침. negative는 '저개입 내 무검출'이지 강한 기각 아님. 단 방향 명확(소폭 이동조차 전부 F-1 이하). "),
 "(4) [null 확증] 이건 발견이 아니라 '기본값(level36-fill) 최적'을 확증하는 null — 챔피언 F-1이 이미 최적 fill 사용. 확립: F-1 챔피언 {반기 level36 진입 + rank 퇴출 + level36 재충원}이 return-derived construction 최적점. L-3(consist-fill)는 '가장 덜 해로운 대안'(oos·EW-uni 소폭 friendly)이나 자본 후보 아님. ",
 "메타: 선별(R6~R8)·퇴출(R12~R14)·충원(R15) = construction 3대 축 전부 동일 천장(cap-w~2.94·oos~+0.12) 수렴 확정. cap-tier×cap-w 벽 불변(EW-uni oos 高나 cap-w oos 붕괴, FQ-015). ",
 "잔존 frontier: 검증된 F-1 construction(진입·퇴출·level36-fill 최적 확정)을 비-수익 substrate(DART insider, FQ-001/FQ-019 armed 하네스)에 이식 — return-derived 위 construction 미세조정은 저EV. ",
 sprintf("적대검증 7약점(challenge_note ①~⑦: ①REBUTTAL L-2≠K10·②REBUTTAL L-1≠FM·③ACCEPT 저빈도검정력·④PARTIAL IS승자잡음·⑤ACCEPT L-3<F-1·⑥ACCEPT 기본값-최적null·⑦ACCEPT return천장). "),
 sprintf("vintage: r6_session_20260711 SUB=_ramp_r13_sub 재사용. n_trials 계보 누적=30(R14 27+R15 3). selection_type=chain·construction=composite. config_hash 7f5855e1dc0ce7e4."))

res <- ramp_document(
  strategy_id = "RAMP_R15_fill_20260713",
  grade = "F",
  lesson_text = lesson,
  construction_type = "composite",
  selection_type = "chain",
  mechanism_hypothesis = paste0(
    "퇴출을 챔피언 F-1(rank)에 고정하고 빈 슬롯 충원 규율(level36/recent18/none/consist-min)만 변주하면 cap-w 또는 oos가 천장 밖으로 움직이는가 = FALSE. ",
    "어떤 fill 규율도 level36-fill(F-1 기본값 cap-w 2.937)을 개선 못 함(best L-3 2.890·oos +0.079이나 paired −0.377 무의미). ",
    "무-fill=F-1 재충원 이득만 제거(≈no-exit 2.652), 신선-fill=cap-w 희석(2.732), 일관성-fill=가장 덜 해로움(2.890). ",
    "확립: F-1의 cap-w 우위 원천=level36 재충원. fill 다이얼은 저빈도(분기 ~2슬롯)·기본값 최적 확증 null. 벽=return-derived construction 천장."),
  core_reference = "L-RAMP-20260713_110343(R14 exitcomb)·L-RAMP-20260713_102944(R13 decay)·L-RAMP-20260713_100638(R12 asym)·FQ-028·FQ-027 challenge④·project-selection-discipline-arc-r4r5r6·project-captier-alpha-localization·measurement-graduation §6·challenge_note_r15_fill_20260713.md",
  portfolio_alpha_t = round(g("armL3_consist_fill","port_t_capwt"),4),
  oos_retention = round(g("armL3_consist_fill","oos_retention"),4),
  falsification_attempts = "challenge_note_r15 ①~⑦ (7 weaknesses: ①REBUTTAL L-2≠K10-sweep(유효K 19.0)·②REBUTTAL L-1≠FM(fill-only Jaccard Δ+0.024)·③ACCEPT 저빈도 검정력한계·④PARTIAL IS승자(L-2)잡음·⑤ACCEPT L-3<base F-1·⑥ACCEPT 기본값-최적 null·⑦ACCEPT return-substrate 천장)",
  metrics = list(
    round="R15", fq="FQ-028",
    calmar=round(g("armL3_consist_fill","calmar"),4),
    max_paired_full=round(max(pf("armL1_fresh_fill"),pf("armL2_nofill_shrink"),pf("armL3_consist_fill")),4),
    record_type="performance",
    base_F1_capwt=round(g("base_F1_level36fill","port_t_capwt"),4), base_F1_oos=round(g("base_F1_level36fill","oos_retention"),4),
    L1_fresh_capwt=round(g("armL1_fresh_fill","port_t_capwt"),4), L1_fresh_oos=round(g("armL1_fresh_fill","oos_retention"),4), L1_paired=round(pf("armL1_fresh_fill"),4),
    L2_nofill_capwt=round(g("armL2_nofill_shrink","port_t_capwt"),4), L2_nofill_oos=round(g("armL2_nofill_shrink","oos_retention"),4), L2_paired=round(pf("armL2_nofill_shrink"),4), L2_pool_mean=round(CH$pool_size$L2$mean,3),
    L3_consist_capwt=round(g("armL3_consist_fill","port_t_capwt"),4), L3_consist_oos=round(g("armL3_consist_fill","oos_retention"),4), L3_consist_ewuni=round(g("armL3_consist_fill","oos_ew"),4), L3_paired=round(pf("armL3_consist_fill"),4),
    r6_anchor_parity_delta=RES$parity$r6_delta, base_F1_parity_delta=RES$parity$f1_delta,
    jaccard_L1_FM=round(CH$jaccard$L1_FM,4), jaccard_base_FM=round(CH$jaccard$base_FM,4), jaccard_L2_base=round(CH$jaccard$L2_base,4),
    r6_k10_capwt=1.9055, r6_k10_oos=-0.3753,
    kill_config_scoped_negative=TRUE, any_graduation=FALSE, hard_pass_count=0L,
    winner_is_only=RES$winner_1st, n_trials_lineage=30L,
    config_hash="7f5855e1dc0ce7e4", vintage_pin="r6_session_20260711"))
cat("L-code emitted:\n"); str(res, max.level=1)
cat(sprintf("\nR15_EMIT_DONE l_code=%s\n", tryCatch(res$l_code, error=function(e) tryCatch(res$lcode, error=function(e2) "(see above)"))))
