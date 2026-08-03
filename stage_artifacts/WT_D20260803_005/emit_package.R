# =============================================================================
# emit_package.R — WT-D20260803_005 (FQ-131) Step G: alpha_package + alpha_validation
#   ★ 순서 계약 (L-194): alpha_package.json write → record_package_lineage
#   ★ 경계: 자본 주장 없음 / gate_eligible = FALSE / Σ·weights 없음 / alpha_discovery_count = 0
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_005/emit_package.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt005G] ", fmt, "\n"), ...))
n3 <- function(x) if (is.null(x) || !length(x) || !is.finite(x)) NULL else round(as.numeric(x), 4)

P1R <- readRDS(file.path(OUT, "persistence_results.rds"))
P2R <- readRDS(file.path(OUT, "persistence_results2.rds"))
DBR <- readRDS(file.path(OUT, "dualbasis_results.rds"))
FB  <- readRDS(file.path(OUT, "finalize_bits.rds"))
RIC <- readRDS(file.path(OUT, "rankic_results.rds"))
CP  <- readRDS(file.path(OUT, "canonical_pool.rds"))
META<- readRDS(file.path(OUT, "pool_meta.rds"))
LAB <- readRDS(file.path(OUT, "registry_labels.rds"))
REG <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
POOL <- P1R$pool
SUMM <- CP$summary; COND <- P1R$cond

prim_bin <- P2R$bin_ci[grid == "primary"]
GSp <- P2R$gate_sim$primary
nullm <- vapply(P1R$nulls, function(x) mean(x[is.finite(x)]), numeric(1))
nulllo <- vapply(P1R$nulls, function(x) as.numeric(quantile(x[is.finite(x)], .025)), numeric(1))
nullhi <- vapply(P1R$nulls, function(x) as.numeric(quantile(x[is.finite(x)], .975)), numeric(1))

# ── factors[] : 285 pool member = REGISTRY 리프 (AST v1.1, 정직한 전량 열거) ──
avail_rule <- function(f) {
  e <- REG[[f]]; a <- e$availability
  if (is.null(a)) return("unknown")
  paste0(a$type %||% "unknown", ": ", a$rule %||% "unknown")
}
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
restate <- function(f) isTRUE(REG[[f]]$restatement_prone)
FACTORS <- lapply(POOL, function(f) list(
  factor_id = f,
  ast = list(leaf = "REGISTRY", factor = f),
  role = "pool_member_measured",
  restatement_exposure = as.integer(restate(f))
))
say("factors[] = %d (registry 리프 전량 열거) | restatement-prone %d",
    length(FACTORS), sum(vapply(POOL, restate, logical(1))))

# ── factor_specs[] : 풀 census + 실측 (스펙 + 창별 판정 요약) ────────────────
PERF <- merge(SUMM[Factor_Name %in% POOL], COND[, .(Factor_Name, family, turnover_profile,
              capacity, corr_group, hold_size_pct, to_tercile, cap_tercile)],
              by = "Factor_Name", all.x = TRUE)
PP <- P1R$PR$primary[, .(n_pairs = .N, p_persist = mean(sign(t_k) == sign(t_next)),
                         mean_abs_t = mean(abs(t_k))), by = Factor_Name]
PERF <- merge(PERF, PP, by = "Factor_Name", all.x = TRUE)
PERF <- merge(PERF, RIC$ic_summary[, .(Factor_Name, mean_ic, icir)], by = "Factor_Name", all.x = TRUE)
setorder(PERF, -port_t_full)
FSPEC <- lapply(seq_len(nrow(PERF)), function(i) {
  r <- PERF[i]
  list(factor_family = r$family %||% "unknown", proxy = r$Factor_Name,
       formula = "factor_db Z_Score_Aligned (load_month_factors, C15 · C13 부호변형 없음)",
       lag_rule = avail_rule(r$Factor_Name), winsorization = "factor DB 빌드 단계",
       neutralization = "none (raw z)",
       economic_rationale = paste0("registry family=", r$family %||% "unknown",
         "; 본 라운드에서 alpha 후보가 아니라 *판정 지속성 측정 대상*으로 소비됨"),
       weight_theta = 0,
       measured = list(canonical_port_t_full = n3(r$port_t_full), net_sr = n3(r$net_sr),
         turnover_annual = n3(r$turnover_annual), mean_rank_ic = n3(r$mean_ic),
         icir = n3(r$icir), hold_size_pct_median = n3(r$hold_size_pct),
         window_sign_persistence_primary = n3(r$p_persist)),
       references = list("Harvey-Liu-Zhu 2016", "McLean-Pontiff 2016"))
})

pkg <- list(
  task_id = "WT-D20260803_005",
  as_of_date = "2026-08-03",
  forecast_horizon = "1M",
  pit = list(sig_date = "2026-06-30", decision_ts = "2026-08-04",
    decision_ts_rationale = paste0("마지막 창의 마지막 신호월(2026-06-30)이 풀 285 리프 중 **가장 보수적인 지연**",
      "(C11_publication_lag = FRED release 35d 상한, 해당 factor 5종: D32_Beta_VIX·MA01~MA04)까지 반영되어 ",
      "실행 가능해지는 최초 시점 = 2026-06-30 + 35d = 2026-08-04. ",
      "본 라운드는 자본 결정을 내리지 않으므로(gate_eligible FALSE, alpha_vector 빈 객체) ",
      "이 날짜는 '실행 가능 시점의 정직한 선언'이지 그 시점에 무언가를 결정했다는 주장이 아니다. ",
      "★ 이 값을 보고일(2026-08-03)로 두면 ast_spec_gate PIT 정적검증이 FAIL_LOOKAHEAD 로 차단한다 — ",
      "게이트가 옳고, 그 차단이 이 선언을 만들었다(CF-09).")),
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = paste0("KR long-only top-25 팩터 포트의 '성분 자격 판정'(창별 canonical PORT_t 부호)은 ",
      "시간에 따라 유지되지 않는다. 유지 실패의 지배 기전은 (i) cap-w 벤치 구성이 만드는 era 공통성분과 ",
      "(ii) 창 추정잡음이며, factor 고유 성분은 그 아래에 묻힌다 — 따라서 |t| 문턱 기반 정적 자격 게이트는 ",
      "원리적으로 작동할 수 없다."),
    mechanism = list(
      agent = paste0("자격을 판정하는 주체 = 리서치 파이프라인 자신(과거 창의 PORT_t로 성분/교체를 정하는 ",
        "registry·조합·게이트 절차). 시장 측 주체는 KOSPI200 cap-w 벤치를 구성하는 초대형주 ",
        "패시브·지수 수급(2021~2026 반도체 초대형주 편중)."),
      friction = paste0("KR 공매도 제약으로 long-only 슬리브는 β≈0.92의 시장성분을 제거할 수 없고, ",
        "top-25 EW는 구조적으로 cap-w 벤치의 초대형주 편중을 언더웨이트한다. 이 스타일 갭은 차익거래로 ",
        "지워지는 미가격 오류가 아니라 벤치 정의가 만든 상시 노출이므로, 국면이 바뀌면 285개 factor가 ",
        "동시에 같은 방향으로 벤치 대비 이기거나 진다."),
      path = paste0("창 k의 PORT_t 부호 → 자격 판정 → 성분 편입/교체. 그런데 그 부호는 대부분 창 k의 ",
        "era 라벨(전 factor 공통)이라 창 k+1의 factor 고유 성과로 전이되지 않는다. 강한 |t|일수록 ",
        "era 성분을 더 많이 담아 오히려 다음 창 반전 위험이 커진다.")
    ),
    falsification = list(
      list(field = "A4_benchmark_kospi200",
           observation = paste0("기전이 참이면 벤치를 cap-w에서 EW-유니버스로 바꿀 때 창별 양수비율의 era 진폭이 ",
             "소멸해야 한다. 소멸하지 않으면 '벤치 구성 아티팩트' 기전 기각."),
           measured = "cap-w 0.75/0.91/0.22/0.02 → EW 0.37/0.50/0.42/0.48 (era 일치율 0.856 → 0.558)",
           result = "CONFIRMED"),
      list(field = "S01_Size",
           observation = paste0("era 성분이 초대형주 편중에서 온다면, 보유 종목 시총 백분위가 높은 factor일수록 ",
             "판정 지속성이 낮아야 한다."),
           measured = "CAP_large 0.514 < CAP_mid 0.604 < CAP_small 0.614 (primary)",
           result = "CONFIRMED_directional"),
      list(field = "FDB-B7_ic_history_monthly",
           observation = paste0("부호 전환이 IC-direction 정렬(시변 절차)의 아티팩트라면, 정렬 방향 전환이 0회인 ",
             "factor는 판정 부호 지속성이 유의하게 높아야 한다."),
           measured = "방향 전환 0회 67 factor 0.548 vs >=1회 28 factor 0.536 (Δ +0.012)",
           result = "REJECTED — 정렬 아티팩트 아님(기전 후보 제거)")
    ),
    regime_scope = list(
      holds_in = list("mega_cap_led", "style_rotation", "post2017_kr"),
      weakens_or_reverses_in = list("ew_universe_benchmark_basis", "mid_cap_led"),
      boundary_rationale = paste0("기전의 축은 벤치 구성(cap-w 초대형주 편중)이므로, EW-유니버스 벤치나 ",
        "mid-cap 주도 국면에서는 era 진폭이 사라진다(실측 EW 0.37~0.50). ",
        "단 ★기전이 약해져도 판정 지속성 자체는 개선되지 않았다(EW 0.607 vs cap-w 0.578) — ",
        "era는 판정의 *수준*을 지배하고, *지속성*은 추정잡음이 지배한다.")
    )
  ),
  verdict = "blocked_by_capability",
  blocker = paste0("본 라운드가 평가하려던 구성물 = '창별 PORT_t로 성분 멤버십을 시변 결정하는 자격 게이트'. ",
    "PORT_t는 종목-단면 리프 연산이 아니라 포트폴리오·시계열 집계 통계이므로 𝒪(CS_*/TS_*/산술/조건/AS_OF/VINTAGE) ",
    "로 표현 불가하다. 스코어 수준 근사로 우회 구현하지 않았다(SOT §2 우회 금지). ",
    "factors[]에 열거한 285 REGISTRY 리프는 *측정 대상*이지 제안 alpha가 아니다."),
  unblock_requirement = paste0("① 포트폴리오-수준 집계 통계를 신호 문법에 들이려면 𝒪 확장이 필요하나 ",
    "**본 라운드는 확장을 요청하지 않는다**(operator_backlog_requested = false): 실측이 그 연산으로 얻을 ",
    "예측력이 현 재료에 없음을 보였다 — primary 최상위 |t|>=2 bin 부호 지속 0.500 [0.366, 0.655], ",
    "tau=2 선발의 다음 창 PORT_t 평균 −0.112 [−0.453, +0.300]. ",
    "② 부활 조건: 비-return 원천 factor가 창별 부호 지속 >= 0.70을 보이거나, era 공통성분을 사전 관측가능하게 ",
    "추정 가능해져 era-조건부 자격이 가능해질 때(next_probe NP-1)."),
  operator_backlog_requested = FALSE,
  factors = FACTORS,
  factors_note = paste0("★ 제안 alpha 아님. 본 라운드가 창별 판정 지속성을 *측정한 대상* 285종을 ",
    "REGISTRY 리프로 전량 열거한 것이다(하나만 대표로 올리면 나머지는 무검증이 되므로 전량). ",
    "verdict=blocked_by_capability — 이 리프들을 시변 자격으로 선별하는 규칙이 𝒪 밖이다."),
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "REGISTRY(285 pool member)", availability_rule = "load_month_factors(sig_date) 경유 — align_factor_direction PIT-safe(Usable_Date <= sig_date, C14), 재무 리프는 quarterly+45d / annual 3-31(C4)", restatement_prone = TRUE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily", availability_rule = "fixed: T-1 (forward 수익·유동성 ADV)", restatement_prone = FALSE),
      list(leaf = "A4_benchmark_kospi200", availability_rule = "fixed: 유니버스 시총가중 forward return (build_monthly_forward_returns)", restatement_prone = FALSE)
    ),
    verdict = "clean",
    note = paste0("창별 자격 판정은 그 창 이하의 active 수익만 사용한다(비중첩 격자). ",
      "예측 회귀는 인접 *비중첩* 창만 사용 — 중첩 창을 쓰면 자기 자신을 예측하는 구조가 된다(위반 주입 LEAK_OVERLAP로 실증).")
  ),
  combination_rule = "single_factor",
  alpha_vector = structure(list(), names = character(0)),
  alpha_vector_note = paste0("★ 비어 있음이 정직한 값. 본 라운드는 전략을 만들지 않고 '판정의 성질'을 측정했다. ",
    "판별 (a)(b) 모두 FAIL — 어떤 종목에도 기대초과수익을 부여하지 않는다. Optimizer/Risk 소비 대상 아님."),
  confidence_vector = structure(list(), names = character(0)),
  signal_matrix_ref = "stage_artifacts/WT_D20260803_005/alpha_scores.parquet (verdict panel: grid x window x factor x PORT_t[cap-w, EW])",
  factor_specs = FSPEC,
  alpha_discovery_count = 0L,
  selection_objective = "canonical_port_t",
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL,
    canonical_port_t_note = paste0("단일 후보 alpha가 없어 단일 값 부여 불가(schema null 허용). ",
      "풀 census 실측: 285 factor 전기간 canonical PORT_t 중앙값 ",
      sprintf("%.3f", median(SUMM[Factor_Name %in% POOL, port_t_full])),
      " / >=2.95 통과 ", SUMM[Factor_Name %in% POOL & port_t_full >= 2.95, .N], "건 / >0 ",
      SUMM[Factor_Name %in% POOL & port_t_full > 0, .N], "건 (metric_type=canonical_screen)"),
    canonical_n_months = as.integer(median(SUMM[Factor_Name %in% POOL, n_months])),
    rank_ic = round(RIC$pool_rank_ic_median, 5),
    rank_ic_note = paste0("풀 285 factor의 factor별 전기간 평균 Spearman rank IC 의 **중앙값**. ",
      "월별 전체 단면 재순회(load_month_factors, C15)로 실측 — top-80 저장 패널을 쓰지 않았다. advisory."),
    icir = round(RIC$pool_icir_median, 4),
    turnover_proxy = round(median(SUMM[Factor_Name %in% POOL, turnover_annual]), 3),
    alpha_inheritance_cor = 0,
    alpha_inheritance_note = paste0("parent alpha 부재(discovery_of=null) + alpha_discovery_count=0 → ",
      "상속 상관 정의 불가. schema가 number[0,1]을 요구해 0(=완전 신규) 기입하되, ",
      "'신규 alpha를 산출했다'는 뜻이 아님을 명시한다. challenge_flags CF-05 참조."),
    subperiod_stability = round(P1R$pp$primary[["p"]], 4),
    subperiod_stability_note = "본 라운드에서는 '창별 판정 부호 지속률'로 정의(primary W=60m, 비중첩 3전이, 850쌍).",
    deflated_sharpe_ratio = NULL,
    dsr_note = "selection_type=chain (argmax/threshold-pick 없음, n_iterations=1) → DSR 게이트 부적용(measurement-graduation §3).",
    persistence = list(
      p_persist_primary = round(P1R$pp$primary[["p"]], 4),
      p_persist_ci_factor_clustered = c(round(P1R$pp$primary[["lo"]], 4), round(P1R$pp$primary[["hi"]], 4)),
      p_persist_ci_corr_cluster_k39 = c(round(DBR$clboot2[grid == "primary", lo], 4), round(DBR$clboot2[grid == "primary", hi], 4)),
      p_persist_ci_time_clustered = c(round(DBR$time_boot[grid == "primary", lo], 4), round(DBR$time_boot[grid == "primary", hi], 4)),
      constant_alpha_null_mean = round(nullm[["primary"]], 4),
      constant_alpha_null_ci = c(round(nulllo[["primary"]], 4), round(nullhi[["primary"]], 4)),
      top_bin_persistence = round(prim_bin[bin == "[2,inf)", p], 4),
      top_bin_ci = c(round(P2R$bin_ci[grid=="primary" & bin=="[2,inf)", lo], 4),
                     round(P2R$bin_ci[grid=="primary" & bin=="[2,inf)", hi], 4)),
      gate_tau2_mean_next_port_t = round(GSp[tau == 2, mean_t_next], 4),
      era_agreement_capw = round(mean(DBR$era_share$agree_cap), 4),
      era_agreement_ew = round(mean(DBR$era_share$agree_ew), 4),
      persistence_when_era_sign_persists = 0.9592,
      persistence_when_era_sign_flips = 0.3043,
      persistence_era_split_note = paste0("primary 최상위 |t|>=2 bin 164쌍 분해: era 부호가 유지된 전이 49쌍 0.959 / ",
        "era 부호가 뒤집힌 전이 115쌍 0.304. ★ 자격 판정이 유지되는 유일한 조건은 era 유지이며, ",
        "era 유지 여부는 자격 판정 자신이 알려주지 않는다."),
      rank_ic_sign_persistence = c(primary = 0.5798, rob36 = 0.6248, rob24 = 0.6667),
      ic_sign_predicts_next_port_sign = 0.472
    )
  ),
  metric_type = "canonical_screen",
  gate_eligible = FALSE,
  gate_eligible_reason = "판정의 성질을 재는 메타 측정 라운드 — 자본 후보 아님. graduation/admission 심사 대상 아님.",
  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH", flag = paste0("사전등록 위반주입 판정식이 발화하지 않았다: ",
      "LEAK_OVERLAP Δp_persist +0.016 / LEAK_FULL −0.001 < 기준 +0.02. ",
      "그러나 (b)가 실제로 쓰는 지표에서는 누출 지문이 뚜렷하다 — 기울기 b 0.277→0.557(2.0배), ",
      "AUC 0.640→0.701, 최상위 bin 지속 0.500→0.791. 즉 비중첩 규율은 실구속이고, ",
      "**둔감한 것은 내가 사전등록한 집계 통계 p_persist 쪽**이다. 사후 판정식 교체는 하지 않았다.")),
    list(id = "CF-02", severity = "HIGH", flag = paste0("factor-clustered CI는 유효표본을 과대평가한다. ",
      "285 factor의 active 상관행렬 PC 90% = 39개(PC1 = 분산 56%). 클러스터 bootstrap CI 폭은 factor CI의 4.0배. ",
      "★ time-clustered(전이 3개) CI는 [0.251, 0.784] — primary 격자에서 P_persist는 0.5를 배제하지 못한다.")),
    list(id = "CF-03", severity = "MEDIUM", flag = paste0("관측 P_persist(0.578)는 상수-알파 잡음 귀무 ",
      "(block bootstrap, 시간순서 파괴) 평균 0.548의 60.2 백분위 — 귀무분포 안이다. ",
      "즉 '자격이 시간에 따라 무너진다'는 서술보다 '자격 판정이 애초에 그만큼 정밀하지 않았다'가 더 정확하다. ",
      "부호 유지 길이가 창 길이와 무관하게 항상 ~2.2~2.4 창(60m/36m/24m 격자 공통)이라는 사실이 같은 결론을 가리킨다 ",
      "— 달력 시간의 반감기가 존재하지 않는다.")),
    list(id = "CF-04", severity = "MEDIUM", flag = paste0("family/cap/turnover 조건 분해의 클러스터 CI는 ",
      "소분류에서 클러스터 수 1~4로 붕괴한다(growth 1, quality 1, value 2). 방향(순서)만 보고하고 ",
      "유의성 주장은 클러스터 >= 10 축(TO_high 14, CAP_mid 10, CAP_large 12)에 한정한다.")),
    list(id = "CF-05", severity = "LOW", flag = paste0("schema 필수 필드 alpha_inheritance_cor(number[0,1])에 0을 넣었으나 ",
      "parent alpha가 없어 정의 불가한 값이다. rank_ic도 advisory 진단이며 단일 alpha 값이 아니라 풀 중앙값이다. ",
      "두 필드를 자격 판정에 사용 금지.")),
    list(id = "CF-06", severity = "MEDIUM", flag = paste0("registry labels.turnover_profile 이 실측 회전율과 반대 방향을 가리킨다: ",
      "라벨 low 0.637 > high 0.563 vs 실측 tercile TO_high 0.613 > TO_low 0.558. ",
      "registry 회전율 라벨을 선별 축으로 쓰면 안 된다(위생 항목 — 별도 태스크).")),
    list(id = "CF-07", severity = "MEDIUM", flag = paste0("harness 결함: ast_spec_gate.sh 는 spec_version=ast_v1.1 패키지에 ",
      "verdict 무관하게 ast 노드 존재를 요구한다(라인 ~223 'ast 노드 부재' block). ",
      "SOT가 규정한 blocked_by_capability 탈출로(=AST 없음)가 게이트를 통과할 수 없다. ",
      "본 패키지는 측정 대상 285 REGISTRY 리프를 factors[]에 실제로 열거해 우회 없이 통과시켰으나, ",
      "AST가 진짜 없는 blocked 패키지는 여전히 발행 불가.")),
    list(id = "CF-09", severity = "MEDIUM", flag = paste0("★ ast_spec_gate PIT 정적검증이 처음 실행에서 ",
      "REGISTRY[D32_Beta_VIX] FAIL_LOOKAHEAD 를 발행했다(avail 2026-08-04 > decision_ts 2026-08-03). ",
      "게이트가 옳다 — C11_publication_lag 리프 5종(D32_Beta_VIX·MA01~MA04)은 보수 35d 지연이라 ",
      "2026-06-30 신호가 2026-08-04 이전에는 실행 불가다. 처리: ① decision_ts 를 실행가능 최초시점으로 정정 ",
      "② 측정 영향 정량화(AP-4) — 5종 제외 시 P_persist Δ ≤ 0.0014, 최상위 bin Δ ≤ 0.009, 창-부호 lag1 20/20 유지 ",
      "→ 판정 불변. 은폐 없이 기록.")),
    list(id = "CF-10", severity = "MEDIUM", flag = paste0("자기적대검증 AP-2가 내 최초 parity 검사의 사각을 잡았다: ",
      "top-80 절단 parity를 주류 factor 3종으로만 봐서 정확 0 이 나왔으나, 사이즈 틸트 factor에서는 절단이 문다 ",
      "(L26_Log_MktCap 전기간 PORT_t 0.7618 → 0.7438). 위험 factor 18종 x 3격자 = 392 창 셀 재측정 결과 ",
      "부호 불일치 0건, P_persist 0.5776 불변. 결함은 실재하고 판정은 불변 — 둘 다 기록.")),
    list(id = "CF-08", severity = "LOW", flag = paste0("lag1 스트레스 12개 중 C02_EPS_Chg_1m 만 붕괴(2.487→0.628). ",
      "1개월 horizon 신호라 1개월 지연이 신호를 소멸시키는 것이 정상 — 누출 지문으로 읽지 말 것. ",
      "나머지 11/12는 부호·크기 유지(|Δt| 중앙 0.103)."))
  ),
  verdict_summary = paste0(
    "(a) 운용가능 지속성 FAIL — 비절단 sign-run 중앙값 1창(60m), P_persist 0.578이나 ",
    "time-clustered CI [0.251, 0.784]로 0.5 미배제, 상수-알파 잡음 귀무(0.548) 안. ",
    "(b) 게이트 원리적 가능성 FAIL — 기울기는 유의(+0.277)하나 최상위 |t|>=2 bin 지속 0.500 [0.366, 0.655], ",
    "tau=2 선발의 다음 창 PORT_t 평균 −0.112. 문턱을 올릴수록 나빠진다(primary). ",
    "★ 지배 발견 = 자격 판정이 유지되는 유일한 조건은 era(스타일 국면) 유지다 — 최상위 bin을 분해하면 ",
    "era 부호 유지 전이 0.959 vs era 전환 전이 0.304. 판정 부호는 factor 라벨이 아니라 era 라벨이며 ",
    "(cap-w 일치율 0.856 → EW 0.558), era를 EW 벤치로 제거해도 지속성은 개선되지 않는다(0.607 vs 0.578) ",
    "— 수준은 벤치 구성이, 지속성은 추정잡음이 지배. 그리고 era 유지 여부는 자격 판정 자신이 알려주지 않는다. ",
    "⇒ 현 재료에서 정적 자격 게이트는 작동 불가. 문제는 'era를 예측할 수 있는가'로 이동한다(NP-1). ",
    "next_probe 4건 + 소비면 7종 + 부활 조건 3건 = alpha_validation.json")
)

dir.create(MBX, recursive = TRUE, showWarnings = FALSE)
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE,
           null = "null", na = "null")
say("alpha_package.json write 완료 (%.1f KB)", file.info(file.path(MBX, "alpha_package.json"))$size/1024)

# ── lineage (L-194: write 이후) ─────────────────────────────────────────────
ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id = "WT-D20260803_005", package_type = "alpha_package",
    method_selected = "eligibility persistence census (285 registry factors x non-overlapping canonical PORT_t windows)",
    input_file_paths = c(".cache/RAWDATA.parquet",
      "02_Infrastructure/factor_db/factor_registry.json",
      file.path(OUT, "pool_panel.parquet"), file.path(OUT, "canonical_pool.rds"),
      file.path(OUT, "preregistration.json")))
  TRUE }, error = function(e) { say("lineage 실패: %s", conditionMessage(e)); FALSE })
say("lineage 기록: %s", ok)
