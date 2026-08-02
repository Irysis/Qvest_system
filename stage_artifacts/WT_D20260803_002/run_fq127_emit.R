# =============================================================================
# run_fq127_emit.R — WT-D20260803_002 산출물 발행 (측정 재실행 없음 — rds 소비)
#   charts → alpha_scores.parquet → alpha_package.json → lineage → alpha_validation.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(ggplot2); library(scales)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_002")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260803_002")
say <- function(fmt, ...) cat(sprintf(paste0("[fq127e] ", fmt, "\n"), ...))

EV  <- readRDS(file.path(OUT, "fq127_eval_results.rds"))
ADV <- readRDS(file.path(OUT, "fq127_adversarial_regime_ub.rds"))
RES <- EV$RES

g <- function(tn, cn, f) RES[[tn]]$by_config[[cn]][[f]]

# ── 차트 1: 재판정 전후 대조 (4 B-주장) ──────────────────────────────────────
CH <- data.table(
  claim = factor(rep(c("CL-4 MAX5배제\n(WT-014)", "CL-5 MAX5배제+overlay\n(WT-016)",
                       "CL-3 PATHQ교체\n(WT-009)", "CL-8 POS2조합\n(WT-021)"), each = 2),
                 levels = c("CL-4 MAX5배제\n(WT-014)", "CL-5 MAX5배제+overlay\n(WT-016)",
                            "CL-3 PATHQ교체\n(WT-009)", "CL-8 POS2조합\n(WT-021)")),
  frame = factor(rep(c("원 주장 frame", "production rank-tilt"), 4),
                 levels = c("원 주장 frame", "production rank-tilt")),
  delta_ir = c(0.1692, -0.1131,   # CL-4: cap_norm → tilt20 (WT-022 실측 승계)
               0.1284, -0.1489,   # CL-5: cap_norm×overlay → full-path (WT-022 승계)
               g("T1", "ew25", "delta_ir"), g("T1", "tilt20_tophi", "delta_ir"),
               g("T2", "ew25", "delta_ir"), g("T2", "tilt20_tophi", "delta_ir")))
CH[, flipped := rep(c(TRUE, TRUE, FALSE, FALSE), each = 2)]
p1 <- ggplot(CH, aes(claim, delta_ir, fill = frame)) +
  geom_col(position = position_dodge(0.7), width = 0.62) +
  geom_hline(yintercept = 0, linewidth = 0.4) +
  geom_text(aes(label = sprintf("%+.3f", delta_ir),
                vjust = ifelse(delta_ir >= 0, -0.4, 1.3)),
            position = position_dodge(0.7), size = 3.1) +
  scale_fill_manual(values = c("원 주장 frame" = "#8aa8c8", "production rank-tilt" = "#c85a54")) +
  labs(title = "FQ-127 base-의존성 재판정 — 08-02 개선 주장 4건 전후 대조",
       subtitle = "배제-필터 주장(CL-4/5)만 부호 반전 · 점수-교체 주장(CL-3/8)은 부호 유지 — 부분 계통",
       x = NULL, y = "ΔIR (paired, net 15bps)", fill = NULL,
       caption = "CL-4/5 = WT-022 실측 승계(cap_norm→rank-tilt) · CL-3/8 = 본 라운드 재실측(EW-25→tilt20+TOphi, n=295)") +
  theme_minimal(base_size = 11) + theme(legend.position = "top")
ggsave(file.path(OUT, "chart_fq127_before_after.png"), p1, width = 9.6, height = 5.6, dpi = 130)

# ── 차트 2: T1/T2 config 격자 — 부호 안정성 ──────────────────────────────────
CFG <- rbindlist(lapply(c("T1", "T2"), function(tn) rbindlist(lapply(
  c("ew25", "tilt20_tophi", "tilt25_tophi", "capnorm25"), function(cn)
    data.table(test = ifelse(tn == "T1", "T1: PATHQ vs M01 (WT-009)", "T2: POS2 vs PATHQ (WT-021)"),
               config = cn, delta_ir = g(tn, cn, "delta_ir"),
               paired_t = g(tn, cn, "paired_t_nw"))))))
CFG <- rbind(CFG,
  data.table(test = "T1: PATHQ vs M01 (WT-009)", config = "tilt20+CRISISub",
             delta_ir = ADV$T1_regime_ub$delta_ir, paired_t = ADV$T1_regime_ub$paired_t_nw),
  data.table(test = "T2: POS2 vs PATHQ (WT-021)", config = "tilt20+CRISISub",
             delta_ir = ADV$T2_regime_ub$delta_ir, paired_t = ADV$T2_regime_ub$paired_t_nw))
CFG[, config := factor(config, levels = c("ew25", "tilt20_tophi", "tilt20+CRISISub",
                                          "tilt25_tophi", "capnorm25"))]
p2 <- ggplot(CFG, aes(config, delta_ir, fill = paired_t)) +
  geom_col(width = 0.62) +
  geom_hline(yintercept = 0, linewidth = 0.4) +
  geom_text(aes(label = sprintf("ΔIR %+.3f\nt %+.2f", delta_ir, paired_t), vjust = -0.15), size = 2.9) +
  facet_wrap(~test) +
  scale_fill_gradient2(low = "#c85a54", mid = "#e8e2d4", high = "#5a8a5a", midpoint = 0) +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.28))) +
  labs(title = "재판정 세부 — 가중 규칙 5종 전부에서 부호 유지 (본 라운드 신규 2건)",
       subtitle = "WT-022의 배제-필터 반전과 대조: 점수-교체/조합 주장은 base 가중 규칙에 강건",
       x = "portfolio 가중 config", y = "ΔIR", fill = "paired t") +
  theme_minimal(base_size = 11) + theme(legend.position = "right")
ggsave(file.path(OUT, "chart_fq127_config_grid.png"), p2, width = 10.4, height = 5.2, dpi = 130)
say("charts 저장 완료")

# ── alpha_scores.parquet (기록용 — T1 cand arm 최종 신호월 대조 점수) ─────────
TP <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TP[, Date := as.Date(Date)]
last_d <- max(TP$Date)
LV <- TP[Factor_Name == "M01_PATHQ" & Date == last_d & is.finite(score)]
LV[, z := (score - mean(score)) / sd(score)]
write_parquet(LV[, .(Date, Ticker, pathq_z = round(z, 4))],
              file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet: %d행 (%s) — 기록용", nrow(LV), format(last_d))

# ── alpha_package.json ───────────────────────────────────────────────────────
alpha_vec <- as.list(setNames(round(LV$z, 4), LV$Ticker))
conf_vec  <- as.list(setNames(rep(0.1, nrow(LV)), LV$Ticker))
pkg <- list(
  task_id = "WT-D20260803_002",
  as_of_date = "2026-08-03",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "08-02 세션의 ΔIR/paired 개선 주장은 base 가중 규칙에 조건부인 국소량이며, production rank-tilt base로 옮기면 계통적으로 부호가 반전된다 (FQ-127 감사 가설).",
    mechanism = list(
      agent = "측정 프레임을 고르는 리서처 — 개입(배제/교체)이 건드리는 종목의 '무게'가 base 가중 규칙마다 다르다",
      friction = "cap_norm(Size) base에서 배제 대상 소형주는 무게≈0 → 개입이 분모(변동성)만 줄여 ΔIR 낙관 편의. rank-tilt base에서 같은 대상이 최상위 비중(승자 컷)",
      path = "비-parity base에서 검증된 '개선'이 production 이식 시 반전 — WT-022 실측(+0.158 → −0.113)"
    ),
    falsification = "재판정에서 부호 반전이 배제-필터(cap_norm) 계열 밖 — EW-base 점수-교체 주장(STORED_SCORE 리프 M01/PATHQ 계열) — 에서도 관찰되면 '필터-국소 기전'은 기각되고 전면 계통으로 격상. 본 라운드 실측: 관찰되지 않음(T1/T2 부호 유지) → 필터-국소 기전 유지",
    regime_scope = list(
      holds_in = list("ALL — 측정-방법론 명제(국면 무관)"),
      weakens_or_reverses_in = list("해당 없음 — 성과 가설이 아니라 측정 프레임 감사 명제"),
      boundary_rationale = "감사 라운드: 국면 경계는 개별 원 주장(WT-014/016/009/021)의 소관 — 본 라운드는 base 축만 격리"
    )
  ),
  factors = list(list(
    factor_id = "F1_audit_contrast_pathq",
    ast = list(op = "CS_ZSCORE",
               ast_note = "감사 대조용 기록 — T1 cand arm(M01_PATHQ) 최종 신호월 z. 신규 설계 아님(WT-009 STORED_SCORE 재소비)",
               args = list(list(leaf = "STORED_SCORE:WT_D20260802_009/tuned_panel.M01_PATHQ"))),
    role = "audit_record_only",
    restatement_exposure = 0,
    escape_contract = list(
      type = "STORED_SCORE",
      provenance = list(
        source_path = "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
        build_wt = "WT-D20260802_009",
        vintage = "2026-08-02"),
      production_parity_verified = FALSE,
      parity_note = "WT-021이 WT-015 저장값 대비 max|diff|=0 재현 확인 — 단 production 코드 산출물 아님(§7b base 권위 비해당, 감사 기록용이라 소비 무해)")
  )),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "STORED_SCORE:tuned_panel.M01_PATHQ", availability_rule = "fixed: 신호월말 가격-파생 — WT-009 C1~C15 검증 승계", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:base_panel.M01_Mom_12_1", availability_rule = "fixed: 동일", restatement_prone = FALSE)),
    verdict = "clean"
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  alpha_vector_note = "감사 라운드 기록용(T1 cand arm 최종 신호월 z) — 채택 후보 아님, 소비 금지. confidence 0.10 flat",
  alpha_discovery_count = 0,
  discovery_of = NULL,
  signal_matrix_ref = "stage_artifacts/WT_D20260803_002/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "audit_methodology",
    proxy = "base-weighting counterfactual re-adjudication",
    formula = "동일 점수쌍을 ew25/tilt20+TOphi/tilt25/capnorm25 가중으로 재구성 → paired ΔIR·NW t 대조",
    lag_rule = "신호월말 → 차기 신호월말 (start_d, end_d] — WT-022 하네스 동일",
    winsorization = "none (저장 점수 재소비)",
    neutralization = "none",
    economic_rationale = "measurement_integrity — ΔIR은 base 가중 규칙에 조건부인 국소량(WT-022 실증)의 일반화 범위 확정",
    weight_theta = 0,
    references = list("WT-D20260802_022 mechanism_decomposition", "FQ-127")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL,
    canonical_port_t_note = "감사 라운드 — canonical_screen_bt 신규 알파 스크리닝 비수행. 판정 수치는 alpha_validation.json 재판정 표 참조 (metric_type=realcode_recon_diag/weighted_screen 라벨 병기)",
    t1_tilt20_delta_ir = g("T1", "tilt20_tophi", "delta_ir"),
    t1_tilt20_paired_t = g("T1", "tilt20_tophi", "paired_t_nw"),
    t2_tilt20_delta_ir = g("T2", "tilt20_tophi", "delta_ir"),
    t2_tilt20_paired_t = g("T2", "tilt20_tophi", "paired_t_nw"),
    n_months = g("T1", "tilt20_tophi", "n")
  ),
  selection_objective = "canonical_port_t",
  n_trials = 1,
  selection_type = "preregistered_audit_no_selection",
  method_shopping_log = list(alpha_agent = list(candidates_tried = 1, method_log = list(
    list(name = "FQ127_base_dependency_audit", selected = TRUE,
         note = "사전등록 감사 — T1/T2 재판정 + CL-4/5 승계. 어느 arm도 채택 후보 아님")))),
  challenge_flags = list(
    "계통 판정: 부분 계통 — 부호 반전은 배제-필터×cap_norm 계열(CL-4/5)에 국소, 점수-교체/조합(CL-3/8)은 5개 가중 config 전부 부호 유지",
    "CL-3 부호 유지가 PATHQ 교체를 부활시키지 않음 — FQ-109 멤버십 jitter 철회는 독립 사유로 존치 (tilt20 paired t +1.556 < 2.0)",
    "parity gate: T1 ew25 재현 +1.516 vs 원 +2.028 (동부호, |Δ|=0.512 ≤ 0.7 사전등록 허용) — 근사 하네스 관습차(수익 윈도우·liq 결측 처리) 병기",
    "CL-1(WT-003 paired +2.569)은 base arm 점수 패널 미저장으로 재판정 불가(C) — base cap-w PORT_t 0.59의 약한 base 위 주장이라 경고 라벨 최상급",
    "CRISIS ub 0.10 감응도: T1 +0.144/t 1.49, T2 +0.173/t 0.87 — 부호 불변 (C3 정량 반박)"
  ),
  verdict_summary = "재판정+승계 4건 중 부호 반전 2건(CL-4 +0.169→−0.113, CL-5 +0.128→−0.149 — 전부 배제-필터×cap_norm) / 부호 유지 2건(CL-3 +0.126→+0.150, CL-8 +0.140→+0.182 — 점수-교체·조합×EW). 사전등록 규칙상 '부분 계통': base-의존 반전은 '개입 대상의 무게 비대칭'이 있는 필터 계열에 국소, 전역 재순위 개입은 가중 규칙에 강건."
)
if (!dir.exists(MB)) dir.create(MB, recursive = TRUE)
write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 6)
say("alpha_package.json 발행")

# ── lineage (package write 이후 — L-194 순서) ────────────────────────────────
lin_ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260803_002",
    package_type = "alpha_package",
    method_selected = "FQ-127 base-dependency audit (T1/T2 rank-tilt 재판정 + WT-022 승계)",
    input_file_paths = c(
      "stage_artifacts/WT_D20260802_009/base_panel.parquet",
      "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
      "stage_artifacts/WT_D20260802_009/size_panel.parquet",
      ".cache/rawdata.parquet", ".cache/benchmark.parquet",
      ".cache/unified_regime_signal.parquet"))
  TRUE
}, error = function(e) { say("lineage 실패: %s", conditionMessage(e)); FALSE })
say("lineage: %s", ifelse(lin_ok, "기록", "실패 — 수동 후속"))
