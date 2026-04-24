#!/usr/bin/env Rscript
# Judge Pilot 11 Telegram brief via tg_agent_brief() SOT

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

OUT <- file.path(ROOT, "stage_artifacts/WT_D20260424_009")

# ── Performance comparison table ──
perf_df <- data.frame(
  Period  = c("Full", "Train", "Val", "Lockbox"),
  SR      = c("1.070", "0.988", "1.299", "1.759"),
  CAGR    = c("26.87%", "24.30%", "26.45%", "48.88%"),
  MDD     = c("-57.5%", "-57.5%", "-11.0%", "-21.5%"),
  stringsAsFactors = FALSE
)

# ── Forge vs Judge (AX-008 triangulation) ──
tri_df <- data.frame(
  Metric  = c("Full SR", "Val SR", "MDD"),
  Forge   = c("1.064", "1.354", "-57.5%"),
  Judge   = c("1.070", "1.299", "-57.5%"),
  Match   = c("YES", "YES", "YES"),
  stringsAsFactors = FALSE
)

# ── Pilot 9 vs Pilot 11 composition ──
comp_df <- data.frame(
  Metric      = c("n_names", "HHI", "max_w", "top3_w", "method"),
  Pilot9      = c("16", "0.091", "15.1%", "38.7%", "ERC"),
  Pilot11     = c("20", "0.051", "6.74%", "19.1%", "HRP+Sc"),
  Delta       = c("+4", "-43%", "-55%", "-51%", "--"),
  stringsAsFactors = FALSE
)

# ── Lockbox regime decomp ──
reg_df <- data.frame(
  Regime    = c("NEUTRAL", "CRISIS", "CAUTION", "RISK_ON"),
  Days      = c("162", "61", "172", "92"),
  Port_SR   = c("2.32", "1.85", "1.37", "2.29"),
  Active_IR = c("+1.45", "+1.83", "-0.18", "-2.20"),
  stringsAsFactors = FALSE
)

result <- tg_agent_brief(
  agent = "Judge",
  title = "WT-D20260424_009 Pilot 11 GRADE_A_CANDIDATE — Forge 41.9x partial artifact, Lockbox BREAKTHROUGH verified",
  lock_scope = "judge_WT-D20260424_009",
  sections = list(
    list(type = "text",
         body = "<b>Pilot 11 HRP+Score n=20</b> — AX-008 2-source verify PASS + Lockbox 첫 positive Active IR (5 pilots 누적 fail 후 처음)"),

    list(type = "bullet",
         title = "Gate A~G 판정",
         items = c(
           "A_PIT: PASS (HRP t-1 lag 확인, C1-C15 clean)",
           "B_ISO: PASS (alpha/risk/optim 역할 경계)",
           "C_NET_ALPHA: PASS_STRONG (Full 1.07, Lockbox IR +0.26)",
           "D_CROWDING: PASS (beta 1.055, market_risk 28.1%)",
           "E_CONCENTRATION: PASS_EXCELLENT (HHI 0.051, max_w 6.74%)",
           "F_DRIFT: PASS (monotonic up 0.99->1.30->1.76)",
           "G_TAIL: FAIL_FULL_BORDERLINE_LOCKBOX (Full MDD -57.5 breach, Lockbox -21.5 pass)"
         )),

    list(type = "table",
         title = "Period Decomposition (Judge recalc from daily_nav.csv)",
         df = perf_df),

    list(type = "table",
         title = "AX-008 Verification Triangulation (Forge vs Judge)",
         df = tri_df),

    list(type = "bullet",
         title = "Forge 41.9x 이론 초과 Anomaly Audit",
         items = c(
           "H1 Pilot 9 baseline static artifact: CONFIRMED",
           "  (run_judge_pilot9.R L49 static buy-and-hold single snapshot)",
           "H2 Pilot 11 weights bug: REJECTED (HRP t-1 clean)",
           "H3 Data snooping: PARTIAL_REJECTED (alpha hash identical, method-agnostic)",
           "H4 Genuine breakthrough: LIKELY_CONFIRMED",
           "Verdict: PARTIALLY_ARTIFACT_PARTIALLY_REAL",
           "True driver: concentration shift max_w 15% -> 6.7%"
         )),

    list(type = "table",
         title = "Pilot 9 vs Pilot 11 Composition (핵심 구조 변화)",
         df = comp_df),

    list(type = "bullet",
         title = "Composition Overlap 상세",
         items = c(
           "13/16 overlap = 81% of Pilot 9 carry-over",
           "P9 only: A057500, A062730, A041140 (high-beta)",
           "P11 new 7 names: A004150, A033790, A012690, A363280, A083790, A330860, A098460",
           "Real driver: HRP+Score rank-prop tilt가 bound cap 15% -> 실제 6.7%로 자연 분산"
         )),

    list(type = "table",
         title = "Lockbox 4-Regime Decomposition (487 days)",
         df = reg_df),

    list(type = "bullet",
         title = "Lockbox OOS 핵심",
         items = c(
           "Port SR 1.759 | CAGR 48.88% vs BM 44.06%",
           "Active IR +0.26 (Pilot 9 static -0.71 대비 +0.97 delta)",
           "Alpha_ann +4.11% | TE 15.78% | MDD -21.5%",
           "NEUTRAL+CRISIS strong, RISK_ON drag (bull market)",
           "5 pilots 누적 실패 후 첫 positive Active IR"
         )),

    list(type = "bullet",
         title = "L-196 재해석 (L-202)",
         items = c(
           "Old: MinVar_superior VALIDATED",
           "New: BREADTH_DEPRIVATION ARTIFACT",
           "5-method ablation: ERC 80.8 / HRP+Sc 80.0 / Score 79.9 / HRP 79.6 / MinVar 56.3",
           "MinVar 열위 = n=7 sparse (breadth 상실)",
           "Non-sparse n=20 4 methods cluster 79-81 = method-agnostic",
           "Breadth가 primary bottleneck (L-197_v2 3-way 중 dominant)"
         )),

    list(type = "bullet",
         title = "MEGA Sprint 영향",
         items = c(
           "MEGA_01 Alpha: Consensus RAPC v2 유효 (breadth 유지)",
           "MEGA_02 Risk: LW Oracle 상속",
           "MEGA_03 Optimizer: HRP+Score + breadth-priority (n≥20, max_w≤7-10%, HHI≤0.08)",
           "MEGA_04 Forge: dynamic monthly frame 표준화 (static BnH 비교 금지)",
           "MEGA_05 Judge: L-201 methodology-mismatch audit 공식화",
           "AX-007 multi-sleeve: RISK_ON downweight 후보"
         )),

    list(type = "bullet",
         title = "New Lessons L-201 ~ L-204",
         items = c(
           "L-201: static vs dynamic backtest 비교 금지",
           "L-202: Breadth bottleneck primacy (L-196 v2)",
           "L-203: Consensus RAPC regime-conditional signature",
           "L-204: HRP+Score implicit dilution (max_w 15->6.7%)"
         )),

    list(type = "bullet",
         title = "Disposition",
         items = c(
           "Verdict: GRADE_A_CANDIDATE / MEGA_SPRINT_INTEGRATION",
           "Score: 52/100 (Grade A cut 40 +12)",
           "Next: Governor PG0~PG3 admission (STR_1631 TDC 분석)",
           "Stop: PG1~PG2 승인시 Mega Sprint core 편입"
         ))
  ),
  charts = c(
    file.path(OUT, "equity_curve_full.png"),
    file.path(OUT, "equity_curve_oos.png")
  )
)

stopifnot(isTRUE(result$ok))
cat(sprintf("Judge Telegram sent: ok=%s bytes=%d\n", result$ok, result$bytes))
