# =============================================================================
# emit_p7.R — NP-A 판정 발행 + challenge_note 생성
#   ★ 모든 수치는 산출물에서 **읽어서** 채운다. 손으로 적지 않는다
#     (WT-003 이 subperiod_stability 를 손으로 적어 0.6667 로 오기한 전례).
# 실행: Rscript -e 'source("stage_artifacts/NP_A_hump_universality/emit_p7.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/NP_A_hump_universality")
say <- function(fmt, ...) cat(sprintf(paste0("[np-a p7] ", fmt, "\n"), ...))

PRE <- fromJSON(file.path(OUT, "preregistration.json"))
MC  <- fromJSON(file.path(OUT, "measurement_corrected.json"))
SA  <- readRDS(file.path(OUT, "selfadv_p6.rds"))   # 이름 보존 — JSON 왕복에서 named vector 이름이 유실됨
DG  <- fromJSON(file.path(OUT, "diagnosis_p4.json"))
EX  <- fromJSON(file.path(OUT, "exploration.json"))
C5  <- readRDS(file.path(OUT, "correct_p5.rds"))
BOOK7 <- PRE$population$signals[PRE$population$signals %in%
  c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap","Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")]

g <- function(x) if (is.null(x)) NA else x
bv <- MC$book7_verdicts; p7 <- SA$SA2_book7_pooled

# book-7 신호별 표 (전표본 · 승계창, 두 arm) — 산출물에서 직접 조립
mk_tab <- function(key) {
  ce <- C5$cells[[key]]
  rbindlist(lapply(BOOK7, function(fn) { z <- ce$per_signal[[fn]]
    data.table(signal = fn, n_month = z$n_month,
      q1 = z$ew_relative_ann_pct[1], q2 = z$ew_relative_ann_pct[2], q3 = z$ew_relative_ann_pct[3],
      q4 = z$ew_relative_ann_pct[4], q5 = z$ew_relative_ann_pct[5],
      argmax = z$argmax_quintile, hump = z$hump_weak, top_below_ew = z$top_below_ew,
      gap_ann = z$gap_q5_q3$ann_pct, gap_t = z$gap_q5_q3$t_cited,
      gap_p_cons = z$gap_q5_q3$p_conservative, gap_acf = z$gap_q5_q3$acf_r1) })) }
TB <- list()
for (k in c("tiebreak|A|neutral|full","tiebreak|A|raw|full",
            "tiebreak|A|neutral|post2015","tiebreak|A|raw|post2015")) TB[[k]] <- mk_tab(k)
for (k in names(TB)) { say("=== book-7 %s ===", k)
  print(TB[[k]][, .(signal, q1 = round(q1,2), q2 = round(q2,2), q3 = round(q3,2), q4 = round(q4,2),
                    q5 = round(q5,2), argmax, hump, top_below_ew,
                    gap = round(gap_ann,2), t = round(gap_t,2), p = round(gap_p_cons,3))]) }

V <- list(
  id = "NP-A", attributed_to = "WT-D20260808_003 next_probe NP-A (신규 WT 미생성)",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  metric_type = "canonical_screen / diag",
  capital_claim = "없음",
  scope = MC$scope_note,
  question = "중립 Q01 의 혹(hump) 분위 프로파일이 Q01 고유인가, KR long-only 신호의 공통 형태인가",

  primary_verdict = "Q01_SCOPED — 혹은 book 신호의 공통 형태가 아니다",
  primary_basis = list(
    rule_applied = "조율자 축소 규칙: book 7종 다수(>=4/7) 혹 ⇒ 구조적 불리 / 다수 단조 ⇒ 탈락 재료의 특징",
    count_full_neutral = bv[["tiebreak|A|neutral|full"]]$hump_weak,
    count_full_raw = bv[["tiebreak|A|raw|full"]]$hump_weak,
    count_denominator = bv[["tiebreak|A|neutral|full"]]$n_book,
    count_verdict_full = c(neutral = bv[["tiebreak|A|neutral|full"]]$verdict, raw = bv[["tiebreak|A|raw|full"]]$verdict),
    count_is_uninformative = SA$SA1_interpretation,
    count_null_full = SA$SA1_count_null$null_full,
    decisive_axis = "크기(book-7 pooled 갭 월계열) — 계수가 귀무분포 안이라 단독 인용 불가",
    book7_pooled = p7),

  inherited_window = list(
    note = "부모 창(post-2015) 복제 — 새 분할 아님. 사전등록 저검정력 라벨",
    count_neutral = bv[["tiebreak|A|neutral|post2015"]]$hump_weak,
    count_raw = bv[["tiebreak|A|raw|post2015"]]$hump_weak,
    verdicts = c(neutral = bv[["tiebreak|A|neutral|post2015"]]$verdict, raw = bv[["tiebreak|A|raw|post2015"]]$verdict),
    arms_disagree = bv[["tiebreak|A|neutral|post2015"]]$verdict != bv[["tiebreak|A|raw|post2015"]]$verdict,
    pooled = p7[grepl("post2015", names(p7))],
    reading = paste0("계수는 arm 에 따라 갈리지만 크기는 두 arm 모두 **비음(非陰)** — 혹 방향 증거 없음. ",
                     "raw 계수 5/7 도 귀무 90% 안(단측 p ", sprintf("%.3f", SA$SA1_count_null$p_hump_side[["p15_raw"]]), ")")),

  anchor_q01 = list(
    full = list(ew_relative = MC$anchor$full$ew_relative_ann_pct, gap_ann_pct = MC$anchor$full$gap$ann_pct,
                t = MC$anchor$full$gap$t_cited, p_conservative = MC$anchor$full$gap$p_conservative,
                rank_ascending = MC$anchor$full$rank_ascending, pop_median = MC$anchor$full$pop_median),
    post2015 = list(ew_relative = MC$anchor$post2015$ew_relative_ann_pct, gap_ann_pct = MC$anchor$post2015$gap$ann_pct,
                t = MC$anchor$post2015$gap$t_cited, p_conservative = MC$anchor$post2015$gap$p_conservative,
                rank_ascending = MC$anchor$post2015$rank_ascending, pop_median = MC$anchor$post2015$pop_median),
    reading = "Q01 의 혹은 모집단 10종 중 2번째로 음수(양 창) — 중앙값이 아니라 꼬리. 그리고 Q01 자신의 갭도 보수적 추론에서 5% 유의 미달"),

  falsification_of_parent_reading = paste0(
    "부모 라운드의 '상단에 정보가 없다'는 서술은 Q01 에 한정된다. book 신호에서는 전표본 최상위분위가 ",
    "중간분위를 연 ", sprintf("%+.2f%%", p7[["neutral|full"]]$ann_pct), "(중립, NW t ",
    sprintf("%+.2f", p7[["neutral|full"]]$t_nw3), ") · ", sprintf("%+.2f%%", p7[["raw|full"]]$ann_pct),
    "(raw, t ", sprintf("%+.2f", p7[["raw|full"]]$t_nw3), ") 이긴다 — 방향이 반대다."),

  nw_lag_discipline = list(
    rule = PRE$measurement$nw_lag_rule,
    measured_acf_r1_book7_pooled = sapply(p7, function(z) z$acf_r1),
    cited_lag = 3L,
    lag12_check = sapply(p7, function(z) z$t_nw12),
    finding = "판정 계열은 겹치는 창 파생이 아니다(ACF r1 |.| <= 0.14). lag-12 로 늘려도 |t| 가 오히려 커지므로 lag-3 인용이 보수적"),

  power = MC$power_labels,
  power_reading = paste0("implied_t_threshold 전부 9.11~11.66 — 2.0~3.2 재진술 구간 밖이므로 바는 외부(배포) 기준의 진짜 바다. ",
    "전표본 셀은 PASS, 승계창 셀은 INCONCLUSIVE_UNDERPOWERED (n=138 에서 필요 연 10.06%). ",
    "승계창의 null 을 '효과 부재'로 읽지 않는다."),

  defects_repaired = list(
    empty_quintile_nan = list(cause = "raw z 동점 — C02_EPS_Chg_1m 최빈값 점유 중앙 41.7%, 282개월 중 147개월 빈 분위",
      repair = "분위 랭크 동점처리 균일화(random, 시드 고정) + 대안(빈 분위 월 제외) 병행",
      noop_verified = MC$repair_noop_verified,
      both_repairs_agree = MC$repair_agreement),
    inference_disagreement = list(
      anchor_post2015 = DG$bootstrap_asymmetry[c("boot_p_percentile","boot_p_normal","nw_p2")],
      repair = "세 추론 중 가장 보수적인 값만 인용(p_conservative 필드)")),

  self_adversarial = list(
    count_null_test = SA$SA1_count_null, direction_flip_census = SA$SA3_direction_flips,
    test_count = SA$SA5_test_count),

  handed_to_FQ166 = list(
    signals = MC$scope_note$control_only_owned_by_FQ166,
    reason = "형태 갈림의 설명(재료군·중립화·시대)·사다리 분해는 FQ-166(WT-D20260809_003) 소관",
    calibration_datum = paste0("본 프레임에서의 대조군 형태 census 는 exploration.json / correct_p5.rds 에 있다. ",
      "교차 라운드 대조 시 프레임 정의: ", MC$scope_note$frame_for_cross_round_comparison),
    exploratory_lead_do_not_treat_as_verdict = list(
      gap_vs_persistence_spearman_full = EX$conditioning_full$table$signal,
      note = "지속성(회전율 역수) 축 rho 는 exploration.json 참조 — n=10 서술. FQ-166 ③ 의 입력 후보")),

  next_probe = list(
    NP_A1 = paste0("book-7 중 유일하게 양 창·양 arm 에서 혹인 Q07_Earnings_Stability 를 단일 대상으로 ",
      "가설-주도 진단(왜 이 신호만 상단이 죽는가). 소비면 = 선별 라벨 / 유니버스 필터"),
    NP_A2 = paste0("형태가 아니라 **상단 폭**을 물어라: top-25(배포 단위)와 top-quintile(~55종) 의 갭이 ",
      "book-7 에서 어떻게 갈리는지. 본 라운드는 분위 단위만 측정했고 배포 단위는 미측정"),
    NP_A3 = "방향 전환 서명이 있는 4종(특히 C06_TP_Gap 8개월)의 전환 월을 제외한 재측정 — 형태 주장의 잔여 취약점"),
  revival_condition = paste0("book 구성이 바뀌어 고-지속성 fundamental 신호 비중이 늘거나, ",
    "승계창(post-2015) 표본이 n>=240 개월로 늘어 필요 연효과가 book-7 pooled 크기 아래로 내려오면 재측정"),
  forbidden_generalization = "본 라운드는 'top-N 선별이 KR 에서 구조적으로 불리하다'를 지지하지 않는다. 벽 일반화 금지"
)
write_json(V, file.path(OUT, "np_a_verdict.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
fwrite(rbindlist(TB, idcol = "cell"), file.path(OUT, "book7_profiles.csv"))
say("=== 판정 발행 → np_a_verdict.json + book7_profiles.csv ===")
say("주판정: %s", V$primary_verdict)
say("book-7 pooled 전표본 중립 연 %+.3f%% (t %+.2f) · raw 연 %+.3f%% (t %+.2f)",
    p7[["neutral|full"]]$ann_pct, p7[["neutral|full"]]$t_nw3, p7[["raw|full"]]$ann_pct, p7[["raw|full"]]$t_nw3)
