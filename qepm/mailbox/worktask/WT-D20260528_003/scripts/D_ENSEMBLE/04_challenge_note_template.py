#!/usr/bin/env python
"""
WT-D20260528_003 / Track 3 D_ENSEMBLE
Step 4: Build challenge_note_D_ENSEMBLE.md after codex critic response received.

Charter §8 No Silent Override:
- Per-concern classification: ACCEPT_FIXED / PARTIAL / REBUTTAL
- REBUTTAL: 학술 1+ + L-code 1+ + 정량 data (3축)
- Self-rationalization grep: "미미", "관행적", "보수적이면 OK", "대부분 결과 동일", "실무적"
- HIGH ≥ 5 or AX hard FAIL ≥ 3 or PIT C1 위반 → Q-Lead escalate

Outputs:
  qepm/mailbox/worktask/WT-D20260528_003/challenge_note_D_ENSEMBLE.md
"""

import json
from pathlib import Path
from datetime import datetime

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
MAILBOX = PROJ / 'qepm' / 'mailbox' / 'worktask' / WT_ID
OUT_DIR = PROJ / 'stage_artifacts' / f'WT_D20260528_003_D_ENSEMBLE'

draft_path = MAILBOX / 'alpha_package_draft_D_ENSEMBLE.json'
codex_path = MAILBOX / 'codex_critic_response_alpha_D_ENSEMBLE.json'
note_path = MAILBOX / 'challenge_note_D_ENSEMBLE.md'

with open(draft_path) as f:
    draft = json.load(f)

if not codex_path.exists():
    print(f"[ERROR] codex response not found: {codex_path}")
    print("        Run 03_codex_round.sh first.")
    exit(1)

with open(codex_path) as f:
    codex = json.load(f)

concerns = codex.get('critical_concerns', [])
stance = codex.get('stance', codex.get('codex_stance', 'UNKNOWN'))
rationale = codex.get('rationale', codex.get('codex_rationale', ''))
weakest = codex.get('weakest_assumption', '')

# Self-rationalization grep terms (Charter §15 + answer-principles)
SELF_RATIO_TERMS = ["미미", "관행적", "보수적이면 OK", "대부분 결과 동일", "실무적", "관행적 허용", "영향 미미"]

# Classification heuristics (manual review must override these defaults)
def classify_concern(concern):
    """Default classification: REBUTTAL/PARTIAL/ACCEPT_FIXED. Manual review required."""
    cid = concern.get('id', '').upper()
    desc = concern.get('description', '').lower()
    sev = concern.get('severity', 'MEDIUM').upper()

    # Hard PASS gates already binding to forge stage (PARTIAL)
    forge_binding = ['DSR', 'TURNOVER', '5-SPEC', 'AX-008', 'AX-001 V2 HARD', 'BACKTEST', 'COST-AWARE']
    if any(k in desc.upper() or k in cid for k in forge_binding):
        return 'PARTIAL', 'Forge stage binding (downstream WT cycle)'

    # PIT carve-out already documented
    if 'C13' in cid or 'C15' in cid or 'CARVE' in cid:
        return 'PARTIAL', 'Carve-out per .claude/rules/factor-db.md (ML + daily parquet exception)'

    # Ensemble specific concerns
    if 'ENSEMBLE' in cid or 'STACK' in desc or 'CORRELATION' in desc:
        return 'REBUTTAL', 'Ensemble premium reported in draft; correlation diagnostics in feature_importance shared'

    # Default
    return 'REBUTTAL', 'Requires academic + L-code + quantitative justification'

note_lines = [
    f"# Challenge Note — D_ENSEMBLE (Track 3) — {WT_ID}",
    f"",
    f"**Generated**: {datetime.now().isoformat()}",
    f"**Draft**: `{draft_path.name}`",
    f"**Codex response**: `{codex_path.name}`",
    f"**Codex stance**: `{stance}`",
    f"",
    f"## 0. Summary",
    f"",
    f"- Codex critical concerns: {len(concerns)} (HIGH={sum(1 for c in concerns if c.get('severity', '').upper() == 'HIGH')})",
    f"- Weakest assumption: {weakest[:300]}",
    f"",
    f"## 1. Charter §8 Required Response (per-concern)",
    f"",
]

high_count = 0
ax_hard_fail = 0
pit_c1_breach = False

for i, c in enumerate(concerns, 1):
    cid = c.get('id', f'C{i}')
    sev = c.get('severity', 'MEDIUM').upper()
    desc = c.get('description', '')
    rec = c.get('recommendation', c.get('action_required', ''))

    if sev == 'HIGH':
        high_count += 1
    if 'AX-' in cid.upper() and ('HARD' in desc.upper() or 'FAIL' in desc.upper()):
        ax_hard_fail += 1
    if 'C1' == cid.upper() or 'PIT-C1' in cid.upper() or 'LOCKBOX' in desc.upper():
        pit_c1_breach = True

    classification, default_rebuttal = classify_concern(c)

    note_lines.extend([
        f"### Concern {i}: {cid} ({sev})",
        f"",
        f"**Description**: {desc}",
        f"",
        f"**Codex recommendation**: {rec}",
        f"",
        f"**Classification**: `{classification}`",
        f"",
        f"**Response**: {default_rebuttal}",
        f"",
        f"**3-axis citation (REBUTTAL/PARTIAL only)**:",
        f"- Academic: [TBD — fill in for REBUTTAL]",
        f"- L-code: [TBD — methodology_active.md reference]",
        f"- Quantitative: [TBD — draft diagnostics value]",
        f"",
    ])

# Escalation triggers
escalate_triggers = []
if high_count >= 5:
    escalate_triggers.append(f"HIGH severity concerns = {high_count} ≥ 5")
if ax_hard_fail >= 3:
    escalate_triggers.append(f"AX axiom hard FAIL = {ax_hard_fail} ≥ 3")
if pit_c1_breach:
    escalate_triggers.append("PIT C1 (lockbox / lookahead) breach detected")

note_lines.extend([
    f"## 2. Self-rationalization auto-check",
    f"",
    f"Searched for: {SELF_RATIO_TERMS}",
    f"",
    f"Result (after manual edit): [TBD — agent verify no rationalization terms in REBUTTALs]",
    f"",
    f"## 3. Escalation triggers",
    f"",
])

if escalate_triggers:
    note_lines.append("**⚠ ESCALATE to Q-Lead** — triggers:")
    for t in escalate_triggers:
        note_lines.append(f"- {t}")
else:
    note_lines.append("No escalation triggers fired. Auto-resolve OK.")

# Diversification premium summary
ens_compare = draft.get('ensemble_comparison', {})
note_lines.extend([
    f"",
    f"## 4. Diversification benefit (Track 3 핵심 질문)",
    f"",
    f"- Max individual model IC: {ens_compare.get('max_individual_ic', 'n/a')}",
    f"- Best ensemble IC: {ens_compare.get('best_ensemble_ic', 'n/a')}",
    f"- Diversification premium: {ens_compare.get('diversification_premium', 'n/a')}",
    f"",
    f"Per-method scoreboard:",
    f"",
])

# Scoreboard
all_methods = ens_compare.get('all_methods', {})
note_lines.append("| Method | Rank IC | ICIR | Harvey-t HAC | DSR | Subperiod Stab | AX-001 v2 ratio |")
note_lines.append("|--------|---------|------|--------------|-----|----------------|------------------|")
for m, d in all_methods.items():
    if d is None:
        continue
    note_lines.append(
        f"| {m} | {d.get('rank_ic_mean', 'n/a'):.4f} | {d.get('icir', 'n/a'):.3f} | "
        f"{d.get('t_hac_newey_west', 'n/a'):.2f} | {d.get('dsr_simplified', 'n/a'):.3f} | "
        f"{d.get('subperiod_stability_fraction', 'n/a'):.2f} | {d.get('ax001_v2_bad_normal_ratio', 'n/a'):.3f} |"
    )

# vs D ML
note_lines.extend([
    f"",
    f"## 5. vs D ML baseline",
    f"",
])

vs_dml = draft.get('vs_d_ml_baseline', {})
for k, v in vs_dml.items():
    if isinstance(v, float):
        note_lines.append(f"- {k}: {v:+.4f}")
    else:
        note_lines.append(f"- {k}: {v}")

note_lines.extend([
    f"",
    f"## 6. Final stance",
    f"",
    f"**discovery_eligible**: {draft.get('final_stance', {}).get('discovery_eligible')}",
    f"**deployment_eligible**: {draft.get('final_stance', {}).get('deployment_eligible')}",
    f"**rationale**: {draft.get('final_stance', {}).get('rationale')}",
    f"",
])

with open(note_path, 'w', encoding='utf-8') as f:
    f.write("\n".join(note_lines))

print(f"Challenge note (template) saved: {note_path}")
print(f"  HIGH severity: {high_count}")
print(f"  AX hard FAIL: {ax_hard_fail}")
print(f"  PIT C1 breach: {pit_c1_breach}")
print(f"  Escalate triggers fired: {len(escalate_triggers)}")
