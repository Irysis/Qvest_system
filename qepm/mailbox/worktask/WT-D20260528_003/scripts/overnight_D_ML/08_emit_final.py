#!/usr/bin/env python
"""
WT-D20260528_003 Hypothesis D — Final alpha_package_D_ML.json
Codex Round 1 fixes 반영 + 5단계 Step (Charter §8 No Silent Override)
"""

import json
import time
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML'
WT_DIR = PROJ / 'qepm' / 'mailbox' / 'worktask' / WT_ID

print(f"[{datetime.now().strftime('%H:%M:%S')}] Step 8 — Final alpha_package_D_ML.json", flush=True)

# Load draft
with open(WT_DIR / 'alpha_package_draft_D_ML.json') as f:
    draft = json.load(f)

# Load codex critic
with open(WT_DIR / 'codex_critic_response_alpha_D_ML.json') as f:
    codex = json.load(f)

# Load step 7 fixes
with open(OUT_DIR / 'codex_round1_fixes.json') as f:
    fixes = json.load(f)

# Build final = draft + codex_response_summary + fixes_applied
final = draft.copy()

# Add codex round 1 metadata
final['codex_round_1'] = {
    "spawned_at": codex['timestamp'],
    "codex_model": codex['model'],
    "codex_stance": codex['stance'],
    "codex_rationale": codex['stance_rationale'],
    "codex_critical_concerns_count": len(codex['critical_concerns']),
    "high_severity_count": sum(1 for c in codex['critical_concerns'] if c['severity'] == 'HIGH'),
    "weakest_assumption": codex['weakest_assumption'],
    "claude_response_stance": "APPROVE_CONDITIONAL",
    "claude_response_rationale": "9 concerns 모두 분류 + 3축 인용 REBUTTAL/PARTIAL/ACCEPT_FIXED. 4 immediate fixes applied (C3/C4/C5/Σw schedule). 5 deferred to forge stage binding (C1 DSR / C6 turnover / C7 5-spec / C8 AX-008 / C9 AX-001 hard). discovery graduation 6/7 PASS but deployment-ineligible (DSR + turnover gates).",
    "claude_challenge_note_ref": "challenge_note_D_ML.md",
    "concerns_classification": {
        "ACCEPT_FIXED": ["C3 PIT-C10 liquidity", "C4 label quarantine", "C5 AX-007 sizing mechanism"],
        "PARTIAL": ["C1 DSR_FAIL (BLP simplified, forge binding)", "C2 PIT-C13/C15 (carve-out factor-db.md + future binding L-code)", "C6 turnover 16.37 (forge bandbuffer+cooldown binding)", "C7 5-spec (forge binding)", "C8 AX-008 triangulation (2/3 source, forge resolve)", "C9 AX-001 v2 hard (forge crisis test binding)"],
    }
}

# Step 7 artifacts added
final['codex_round_1_fixes'] = fixes

# Update challenge_flags with Codex-derived ones
existing_ids = [cf['id'] for cf in final['challenge_flags']]

new_flags = [
    {
        "id": "CODEX_C2_PIT_CARVE_OUT",
        "severity": "MEDIUM",
        "detail": "PIT-C13 (FLIP_SIGN -D02_Beta_zxs) + PIT-C15 (direct daily parquet load) carve-out. .claude/rules/factor-db.md 명시 ML 예외 정합. -D02_Beta는 registry direction='lower_better' aligned.",
        "action_required": "Future iteration: Z_Score_Aligned 통합 산출 (registry direction auto-align). Binding L-code 등재 권고."
    },
    {
        "id": "CODEX_C6_TURNOVER_EXCESSIVE",
        "severity": "HIGH",
        "detail": f"Weights schedule 2-way annualized turnover {fixes['c5_c6_weights_schedule']['turnover']['annualized_2way']:.2f} >> 6.0/yr cap. 15bps × 16.37 = 245bps/yr cost potential. ML signal fast-decay 정합 (Gu-Kelly-Xiu 2020 Table 7).",
        "action_required": "Forge stage: bandbuffer (keep_n=30, entry_n=20) + cooldown 2m overlay + Net-of-cost ML loss (Kelly-Pedersen 2022) 적용 후 turnover 재측정."
    },
    {
        "id": "CODEX_C7_ROBUSTNESS_MATRIX",
        "severity": "MEDIUM",
        "detail": "5-spec CAPM/Carhart/FF5/FF6 regression 부재. Sector-neutral retention IC drop 측정 없음. discovery 단계는 t-HAC (Newey-West)로 multi-testing partial coverage.",
        "action_required": "Forge stage: PerformanceAnalytics::Return.portfolio + 5-spec alphaTest, post-OLS sector neutralize IC retention."
    },
    {
        "id": "CODEX_C8_AX008_TRIANGULATION",
        "severity": "MEDIUM",
        "detail": "AX-008 Triangulation 2/3 source current (Claude + Codex). Forge backtest source 3 진입 시 resolve.",
        "action_required": "Forge stage: PerformanceAnalytics-based monthly returns + 5-spec + cost-aware net SR. 3-source agreement target."
    },
]

for nf in new_flags:
    if nf['id'] not in existing_ids:
        final['challenge_flags'].append(nf)

# Update artifact references
final['artifact_lineage'] = {
    "primary": {
        "alpha_scores_clean": str(OUT_DIR / 'alpha_scores_clean.parquet'),
        "alpha_scores_legacy": "Overwritten with clean version (no future labels)",
        "weights_schedule": str(OUT_DIR / 'weights_schedule.parquet'),
        "alpha_validation": str(OUT_DIR / 'alpha_validation.json'),
        "challenge_note": str(WT_DIR / 'challenge_note_D_ML.md'),
        "codex_critic_response": str(WT_DIR / 'codex_critic_response_alpha_D_ML.json'),
    },
    "audit": {
        "alpha_scores_with_labels": str(OUT_DIR / 'alpha_scores_audit.parquet'),
        "top20_liquidity_audit": str(OUT_DIR / 'top20_liquidity_audit.csv'),
        "decile_monotonicity": str(OUT_DIR / 'decile_monotonicity.csv'),
        "codex_round1_fixes": str(OUT_DIR / 'codex_round1_fixes.json'),
    },
    "raw_data": {
        "ml_panel": str(OUT_DIR / 'ml_panel_train.parquet'),
        "predictions_walkforward": str(OUT_DIR / 'predictions_walkforward.parquet'),
        "feature_importance": str(OUT_DIR / 'feature_importance.parquet'),
        "cv_results": str(OUT_DIR / 'cv_results.json'),
    }
}

# Final stance
final['final_stance'] = {
    "discovery_eligible": True,
    "deployment_eligible": False,
    "rationale": "Discovery 6/7 PASS (Rank IC, ICIR, subperiod, Harvey-t HAC, AX-001 v2 soft, AX-007 mechanism via weights). Deployment-ineligible (DSR FAIL + turnover 16.37x > 6.0/yr cap). Forge stage 진입 후 bandbuffer/cooldown overlay + 5-spec robustness + crisis test 후 deployment 재검토.",
    "recommendations": [
        "OPTION A: Discovery 보존 — Hypothesis D ML signal source로 retain. Forge stage 진입 위해 bandbuffer/cooldown overlay + 5-spec robustness + Hard AX-001 crisis test 추가 필요.",
        "OPTION B: Feature pruning + retry — Top 30 features (decile spearman 0.7455 유지) 기반 simplified ML 재훈련 → turnover ↓ + DSR ↑ 시도.",
        "OPTION C: Ensemble with B/C — Hypothesis D (ML) + Hypothesis B (Bali MAX) + Hypothesis C (Microstructure) ensemble로 individual turnover 분산."
    ]
}

# Save final
final_path = WT_DIR / 'alpha_package_D_ML.json'
with open(final_path, 'w', encoding='utf-8') as f:
    json.dump(final, f, indent=2, ensure_ascii=False, default=str)

print(f"  Saved: {final_path}")
print(f"  Codex stance: {codex['stance']}")
print(f"  Claude response: APPROVE_CONDITIONAL")
print(f"  Discovery eligible: True, Deployment eligible: False")
print(f"  Challenge flags: {len(final['challenge_flags'])}")
print(f"\n=== Step 8 COMPLETE ===")
