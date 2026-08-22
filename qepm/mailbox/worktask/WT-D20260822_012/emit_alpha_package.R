# alpha_package.json 발행 — res 객체에서 직접 (전사 오류 방지)
suppressWarnings(suppressMessages({library(jsonlite)}))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT <- file.path(root, "qepm/mailbox/worktask/WT-D20260822_012")
res <- readRDS(file.path(WT, "_measure_res.rds"))
now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

e1 <- res$E1_primary
rg <- res$regime_summary
rnd <- function(x, d=4) if (is.null(x)||!is.finite(x)) NULL else round(x, d)

ast <- list(
  ast_id = "FQ-245-v1",
  ast_version = "ast_v1.1",
  spec = "ast_v1.1_stage1to4",
  primary_leaves = list(list(
    leaf_type = "STORED_SCORE",
    source_path = ".cache/macro_beta_scores.parquet",
    score_column = "Score", ticker_column = "Ticker", date_column = "Date",
    provenance = list(
      generated_by = "STR_AS_20260822_143237_8580",
      strategy_id = "STR_AS_20260822_143237_8580",
      generation_date = "2026-08-22",
      production_parity_verified = FALSE,
      note = paste0("alpha-search 런 산출물(무조건부 macro-beta momentum). STORED_SCORE 소비 계약 provenance 3필드. ",
                    "본 라운드 권위 = canonical_screen_bt 실측(정렬월 부분집합). 유니버스 선-제한: score 3462종 → ",
                    "returns_dt(K200∪KQ150 멤버십) 교집합 inner-join(WT-009 CF-03 오염 차단, 커버리지 ~348종/월).")
    )
  )),
  conditioning_layer = list(
    type = "REGIME_GATE",
    source = "fred_macro.parquet daily delta20 sign-alignment (Term_Spread·VIX·KRW_USD)",
    condition = "3/3 dynamic sign aligned (min_aligned=3, tie=not_aligned). delta20 = shift(1)-shift(21)",
    mixed_handling = "mixed 월 = 무포지션(부분집합서 제외 — E1 은 정렬월만 canonical). 전기간 MDD 진단에만 mixed=벤치 배정"
  ),
  selection_rule = "top_25_ew",
  universe = "KOSPI200_union_KOSDAQ150",
  rebalance = "monthly",
  cost_model = "15bps_one_way (v2.4_kr_retail_15bps)",
  liq_ruler = "adv20_t1 (2e8 KRW floor, injected_daily)"
)

pkg <- list(
  wt_id = "WT-D20260822_012",
  fq_id = "FQ-245",
  alpha_research_version = "1",
  produced_by = "alpha-research",
  produced_at = now,
  hypothesis_inherited_from = "alpha_hypothesis.json",
  hypothesis_inheritance_note = "mechanism/falsification/regime_scope 승계(재작성 없음). 에피소드 동기 서술 1건(EuDebt 2011H2)은 프레리그 §7 대로 철회(라벨 규칙 정본, 가설 불변) — challenge_note_alpha.md 약점6.",
  prereg_frozen = "prereg_frozen_fq245.md (sha1 38b4a814f06e79a08a226fdc585e727707bc3b7a)",
  selection_type = "single_prereg (config argmax 없음 → DSR 게이트 비발동)",
  ast = ast,
  measurement = list(
    metric_type = "canonical_screen",
    tier = "screen_diagnostic",
    measurement_path = "02_Infrastructure/contracts/canonical_screen_bt.R (build_benchmark_compare 경유, NW lag-3)",
    E1_primary = list(
      definition = "정렬국면(min_aligned=3, 양방향 pooled) top-25 EW score 선별 월별 활성수익(vs Size-weighted K200∪KQ150 proxy, 15bps), NW lag-3 t",
      n_aligned = rg$aligned_n,
      port_t_nw3 = rnd(e1$port_t_nw3),
      information_ratio = rnd(e1$information_ratio),
      alpha_annualized = rnd(e1$alpha_annualized),
      active_return_mean_annual = rnd(e1$active_return_mean_annual),
      active_vol_monthly = rnd(e1$active_vol_monthly, 5),
      diag_ew_universe_port_t = rnd(e1$diag_ew_port_t),
      diag_ew_universe_note = "dual-basis 진단(비바인딩). EW-유니버스 벤치 대비도 음(-) — cap-w 아티팩트로 인한 오기각 아님.",
      verdict_with_power_arm_sd = e1$verdict_with_power,
      verdict_with_power_external_sd = e1$verdict_with_power_external_sd,
      verdict_note_external_sd = e1$verdict_note_external_sd,
      required_annual_t2 = rnd(e1$required_annual_t2),
      implied_t_threshold = rnd(e1$verdict_implied_t, 3),
      reachable_ceiling_port_t = rnd(e1$reachable_ceiling_port_t, 2),
      reachable_ceiling_note = "완전예지 top-25(실현수익 상위) PORT_t = 17.15 → 이 창(74월)은 원리적 도달 가능. '창이 짧아 미결'이 아니다.",
      point_estimate_direction = "NEGATIVE (가설 방향 = 양+ 회복. 관측 = 음-)",
      final_label = "NULL_WITH_NEGATIVE_POINT_ESTIMATE",
      final_label_rationale = paste0("verdict_with_power(외부 sd) = INCONCLUSIVE_UNDERPOWERED (|효과|<필요치). ",
        "그러나 부호가 음(-)이고 3 arm(E1/S1/r1) 전부 음(-) + 완전예지 상한 +17.15 로 창 도달 가능 ",
        "⇒ '창이 짧아 미결'이 아니라 가설 방향(양+) 성립 아님. 단 |t|=1.14 로 유의 음(-)도 아님 = 확립적 반증은 아님.")
    ),
    S1_up_only = list(n = res$S1_up_only$n, port_t_nw3 = rnd(res$S1_up_only$port_t_nw3),
                      information_ratio = rnd(res$S1_up_only$information_ratio),
                      active_return_mean_annual = rnd(res$S1_up_only$active_return_mean_annual),
                      note = "에피소드 근거 직접 대응 arm. MDE80 연 37% 로 확증력 없음(보고 전용). 음(-) 확인."),
    S2_concordance = list(n = res$s2_concordance$n, slope = rnd(res$s2_concordance$slope, 5),
                          t = rnd(res$s2_concordance$t, 3), sign = res$s2_concordance$sign,
                          note = res$s2_concordance$note,
                          interpretation = "정합강도(Ct)↑ 시 활성수익 미상승(slope 음·t −0.75 비유의) — 기전 단조성 미지지. ★aligned regime Ct≡1 상수라 aligned-only 회귀 불능 → 전표본 회귀로 진단(challenge_note 약점5)."),
    flow_falsification = list(
      F_flow_nw_t = rnd(res$flow_falsification$nw_t, 3),
      mean_spread = rnd(res$flow_falsification$mean_spread, 6),
      n = res$flow_falsification$n,
      rule_verdict = "확인 (NW-t +0.80 > 0)",
      binding_verdict = "MOOT_UNDER_NEGATIVE_E1",
      note = paste0("반증규칙(NW-t≤0→기각)은 수익 양(+) 문맥의 기전 확인용. E1 활성수익 음(-) 상태서 flow 양(+) = ",
                    "'외국인이 사도 가격 미상승 = flow→price 전달 단절'. 기전 지지 근거로 인용 불가(challenge_note 약점4 REBUTTAL).")
    ),
    robustness = list(
      r1_clean_window = list(window = "2016-01~", n = res$r1_clean$n,
                             port_t_nw3 = rnd(res$r1_clean$port_t_nw3),
                             active_return_mean_annual = rnd(res$r1_clean$active_return_mean_annual),
                             note = "KQ150 백필 통제 청정창 — 음(-) 재현(−1.27). 백필 아티팩트 아님."),
      lag1_stress = list(port_t_nw3 = rnd(res$lag1_stress$port_t_nw3, 3),
                         base_e1_t = rnd(res$lag1_stress$base_e1_t),
                         collapse = res$lag1_stress$collapse,
                         note = "shift(1) 판 −0.11(음→음, 붕괴 아님) — 동월 누출 없음."),
      strict_pit_ab = list(inflation = rnd(res$strict_pit_ab$inflation, 4),
                           lookahead_suspected = res$strict_pit_ab$lookahead_suspected,
                           note = "인플레 0.0% — 신호=월말·집행=익월 구조상 current==strict. clean.")
    ),
    gate0_sd_recheck = list(
      aligned_sd_monthly = rnd(res$gate0_sd_recheck$aligned_sd_monthly, 5),
      full_sd_monthly = rnd(res$gate0_sd_recheck$full_sd_monthly, 5),
      threshold_1_3x = 0.08011,
      recheck_triggered = res$gate0_sd_recheck$recheck_triggered,
      gate0_status_after_recheck = res$gate0_sd_recheck$gate0_status_after_recheck,
      note = "정렬월 sd 0.0695 < 1.3x 문턱 0.0801 → 재산출 불요, Gate 0 PASS 유지."
    ),
    episode_classification_check = list(
      covid_2020h1_aligned_n = res$episode_check$covid_2020h1_aligned_n,
      eudebt_2011h2_aligned_n = res$episode_check$eudebt_2011h2_aligned_n,
      motivation_narrative_retained = res$episode_check$motivation_narrative_retained,
      note = "EuDebt 2011H2 정렬월 0 → 동기 서술 철회(프레리그 §7, 가설 불변)."
    ),
    mdd_conditional = list(
      value = rnd(res$mdd_conditional, 4),
      prediction_threshold = 0.45,
      prediction_met = (abs(res$mdd_conditional) <= 0.45),
      note = "F-MDD 사전예측(≤45%) 위반(−59.5%). 정렬국면 소비가 악화국면 방어 실패 — 기전 부수예측 실패, E1 음(-)과 정합."
    )
  ),
  regime_labels_summary = list(
    total_months = rg$total_months, aligned_n = rg$aligned_n,
    aligned_up_n = rg$aligned_up_n, aligned_down_n = rg$aligned_down_n,
    mixed_n = rg$mixed_n, zero_delta_months = rg$zero_delta_months,
    gate0_expected_74_match = rg$gate0_expected_74_match,
    note = "gate0 실측(74=32up+42down) 편차 0 — 라벨 규칙 정확 복제."
  ),
  verdict = "설계·측정 완료(screen_diagnostic tier) — E1 NULL_WITH_NEGATIVE_POINT_ESTIMATE",
  screen_route = "NONE (E1 음-·MDD 예측 위반으로 OVERLAY_CANDIDATE 라우팅 전제(E1 성립) 불충족)",
  graduation_hard_gates_status = "NOT_EVALUATED — alpha 단계. forge-authoritative 수치 없이 PORT_t 2.95/oos/calmar 판정 불가. 본 라운드는 canonical_screen 실측(screen tier)만.",
  capital_path_claim = "금지 준수 — 자본 경로 주장 없음. proxy 손계산 없음(canonical_screen_bt 경유).",
  pit_status = list(
    assert_overlay_pit = "PASS",
    lag1_stress = "붕괴 아님(−0.11)",
    strict_pit_ab_inflation = 0.0,
    macro_frequency_d_enforced = TRUE,
    macro_regime_parquet_consumed = FALSE,
    delta20_shift1 = TRUE,
    c15_note = "macro_beta_scores 직접 소비(적용 제외) + RAWDATA build_monthly_forward_returns 경유(factor-parquet 직접 load 아님)."
  ),
  next_steps = "verdict = 가설 방향 성립 아님(음- 점추정). risk/optimizer/forge 이관 실익 없음(screen tier NULL). next_probe = alpha_hypothesis candidates C4(bear_prob 조건화, FQ-246 인접) 별도 사전등록.",
  next_probe = list(
    "C4 — 조건변수 교체(bear_prob, FQ-246 소관 축) 별도 가설 사전등록 (자유도 분리: 조건변수만 교체)",
    "정렬국면 내 신호가 음(-)인 기전 진단: aligned_down(42월)서 score 상위=하락수혜인데 활성 음(-) = 방향 내장 소비의 역전 — score 구성(Σβ·δ)의 β 추정창(60d) vs 소비창(1M) 불일치 점검"
  ),
  challenge_note_path = "challenge_note_alpha.md",
  transition_gates = list(
    decision = "NO_TRANSITION",
    conditions_checked = list(
      "E1 PORT_t ≥ +2.0 (screening) : FAIL (−1.14, 부호 반대)",
      "F-flow NW-t > 0 (기전) : rule PASS but MOOT (E1 음-)",
      "F-MDD ≤ 45% (그릇 예측) : FAIL (−59.5%)",
      "S2 정합강도 단조 : 미지지 (slope 음·비유의)"
    ),
    rationale = "E1 가설 방향 성립 아님 + MDD 예측 위반 + 기전 단조성 미지지 → risk-research 이관 실익 없음. screen_diagnostic NULL 로 종결, next_probe 로 이관."
  )
)

writeLines(toJSON(pkg, auto_unbox = TRUE, pretty = TRUE, null = "null"),
           file.path(WT, "alpha_package.json"))
cat("EMIT_DONE\n")
