#!/usr/bin/env Rscript
# Governor Pilot 11 PG0~PG3 Admission Brief (tg_agent_brief v3)
# WT-D20260424_009 — CONDITIONAL_ADMIT_DIVERSIFIER_PROBE

suppressPackageStartupMessages({
  source("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")
})

result <- tg_agent_brief(
  agent = "Governor",
  title = "WT-D20260424_009 Pilot 11 Governor — CONDITIONAL_ADMIT_DIVERSIFIER_PROBE",
  as_of = "2026-04-24",
  sections = list(

    list(
      heading = "PG0 Gap 현황 + Pilot 11 기여 추정",
      type = "text",
      body = paste(
        "현 PG2: STR_1631 80% + STR_1656 20% → SR 1.193 / CAGR 16.14% / MDD -21.27%",
        "Gap: SR 0.807 (OPEN 최우선) / CAGR -0.14pp (CLOSED) / MDD 3.73pp (CLOSED)",
        "",
        "Pilot 11 sleeve 15% 편입 시 proxy 기여:",
        "  • book SR → 1.22~1.28 (+0.03~+0.09)",
        "  • book CAGR → 16.6~18.1% (+0.5~+2.0pp)",
        "  • book MDD → -22.8~-20.3% (소폭 악화 가능)",
        "  • SR gap 0.807 → 0.73 (단독으로 SR 2.0 달성 불가)",
        sep = "\n"
      )
    ),

    list(
      heading = "TDC vs STR_1631 — Factor Family 100% Overlap",
      type = "text",
      body = paste(
        "<b>STR_1631 4F</b>: C01_SUE + C04_ESBR + C02_EPS_Chg_1m + C06_TP_Gap (consensus)",
        "<b>Pilot 11 4F</b>: C04_ESBR + C19_Composite_Earn + C01_SUE + C09_Earn_Surprise_Sq",
        "",
        "공통 2F (SUE+ESBR) = factor overlap 50%",
        "factor family overlap = 100% (동일 consensus_earnings)",
        "",
        "Proxy TDC: <b>0.65</b> (range 0.55~0.75, 0.4~0.7 CONDITIONAL 구간)",
        "규범 TDC: CRISIS 0.80 / RISK_ON 0.70 / NEUTRAL 0.60 / CAUTION 0.50",
        "",
        "Empirical TDC 측정 <b>미실시</b> — daily NAV export 후 compute_tdc() 필수",
        "판정: <b>FAMILY_COUSIN</b>, not independent diversifier",
        sep = "\n"
      )
    ),

    list(
      heading = "3-Sleeve Scenario Comparison",
      type = "table",
      df = data.frame(
        Scenario = c("S1 15%", "S2 25%", "S3 30%", "S4 60% Core"),
        Book_SR = c("1.22~1.28", "1.24~1.32", "1.24~1.34", "REJECT"),
        Book_CAGR = c("16.6~18.1", "16.9~19.3", "17.1~20.0", "-"),
        Book_MDD = c("-22.8~-20.3", "-23.8~-19.3", "-24.3~-18.3", "-"),
        Verdict = c("✅ RECO", "Phase3", "NO", "❌")
      ),
      notes = c(
        "S1 = Phase 2 target (4 trigger 해결 후)",
        "S4 REJECT — Harvey t 상실 + family 내 idio swap + MDD hard fail 잔존"
      )
    ),

    list(
      heading = "Red Flag 4건 + Mitigation",
      type = "bullet",
      items = c(
        "[CRITICAL] Full MDD -57.47% (hard fail) — 2008 GFC 포함. Mitigation: regime overlay + MDD stop-out 30% + stress test recalc",
        "[HIGH] RISK_ON Active IR -2.20 — 강세장 drag. Mitigation: RISK_ON weight 0.5x rule + cash sleeve + multi-sleeve AX-007",
        "[HIGH] Harvey t 미확정 — STR_1631 3.09 anchor 필수. Mitigation: Judge returns-based t-stat + DSR 계산 요청",
        "[LOW-MED] Methodology novelty audit — HRP+Score가 primary driver면 STR_1631도 upgrade로 동일 효과 가능 (L-202)"
      )
    ),

    list(
      heading = "Admission Verdict + Routing",
      type = "text",
      body = paste(
        "<b>VERDICT: CONDITIONAL_ADMIT_DIVERSIFIER_PROBE</b>",
        "Immediate action: <b>HOLD_PHASE_1</b> (즉시 편입 없음)",
        "Phase 2 target: S1 sleeve 15% (STR_1631 70% + STR_1656 15% + Pilot11 15%)",
        "",
        "<b>Phase 2 Trigger 4건 (모두 선결)</b>:",
        "  1. empirical TDC vs STR_1631 &lt; 0.55 (Forge daily NAV + Governor compute_tdc)",
        "  2. RISK_ON weight 0.5x rule 구현 (Forge + Risk Mgr)",
        "  3. returns-based Harvey t ≥ 3.0 (Judge)",
        "  4. cross-family diversifier 1건 동시 편입 or consensus &lt; 50% (Pilot 12)",
        "",
        "REJECT paths: ADMIT_CORE_REPLACE (family 내 idio swap 무의미), REJECT_PG1 (breakthrough 확인됨)",
        sep = "\n"
      )
    ),

    list(
      heading = "Strategy Registry 제안",
      type = "text",
      body = paste(
        "제안 ID: <code>STR_1690_CRAPC_HRP_N20</code>",
        "전체 명: Consensus RAPC v2 HRP+Score Hybrid N=20 Dynamic Monthly",
        "등록 타이밍: Phase 2 admission 확정 시",
        "역할: diversifier_probe_within_consensus_family",
        "concentration policy: max_w 7% / HHI 0.08",
        "regime policy: NEUTRAL+CRISIS 1.0x / CAUTION+RISK_ON 0.5x",
        "",
        "<b>PG2 status</b>: UNCHANGED (STR_1631 80 + STR_1656 20 유지)",
        "<b>MEGA Sprint</b>: MEGA_02 Risk PRIORITY_UP + Pilot 12 cross-family 발주 필수",
        sep = "\n"
      )
    )
  ),
  footer = paste(
    "<i>Artifacts</i>:",
    "  • pilot11_pg_admission.json (main verdict)",
    "  • pg0_gap_vector_updated.json v1.1.0",
    "  • pilot11_tdc_analysis.json (proxy TDC)",
    "  • status.json (PILOT11_ADMISSION_ISSUED)",
    "",
    "<b>사용자 확인 필요</b>: CONDITIONAL_ADMIT verdict + Phase 2 trigger plan + Pilot 12 발주 방향",
    sep = "\n"
  )
)

stopifnot(isTRUE(result$ok))
cat("[Governor] Telegram brief 발송 완료\n")
print(result)
