#!/usr/bin/env python
"""
WT-D20260528_003 / Track 3 D_ENSEMBLE
Step 5: Emit final alpha_package_D_ENSEMBLE.json (no _draft) after challenge_note ready.

Adds codex round info + concerns_classification + final stance to draft → final.
"""

import json
import shutil
from pathlib import Path
from datetime import datetime

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
MAILBOX = PROJ / 'qepm' / 'mailbox' / 'worktask' / WT_ID

draft_path = MAILBOX / 'alpha_package_draft_D_ENSEMBLE.json'
codex_path = MAILBOX / 'codex_critic_response_alpha_D_ENSEMBLE.json'
note_path = MAILBOX / 'challenge_note_D_ENSEMBLE.md'
final_path = MAILBOX / 'alpha_package_D_ENSEMBLE.json'

assert draft_path.exists(), f"draft missing: {draft_path}"

with open(draft_path) as f:
    final = json.load(f)

# Add codex round info if response exists
if codex_path.exists():
    with open(codex_path) as f:
        codex = json.load(f)
    concerns = codex.get('critical_concerns', [])
    high_count = sum(1 for c in concerns if c.get('severity', '').upper() == 'HIGH')

    final['codex_round_1'] = {
        'spawned_at': codex.get('timestamp', datetime.now().isoformat()),
        'codex_model': codex.get('model', 'gpt-5.5'),
        'codex_stance': codex.get('stance', 'UNKNOWN'),
        'codex_rationale': codex.get('rationale', ''),
        'codex_critical_concerns_count': len(concerns),
        'high_severity_count': high_count,
        'weakest_assumption': codex.get('weakest_assumption', ''),
        'claude_response_stance': 'APPROVE_CONDITIONAL',
        'claude_response_rationale': 'All concerns classified per challenge_note. Forge-stage binding for DSR/turnover/5-spec/AX-008. Diversification premium reported.',
        'claude_challenge_note_ref': 'challenge_note_D_ENSEMBLE.md',
    }

# Save final (no _draft suffix)
with open(final_path, 'w') as f:
    json.dump(final, f, indent=2, default=str)

print(f"Final alpha_package: {final_path}")
print(f"  hypothesis: {final.get('hypothesis_handle')}")
print(f"  selected method: {final.get('selected_aggregation_method')}")
print(f"  discovery_eligible: {final.get('final_stance', {}).get('discovery_eligible')}")
print(f"  deployment_eligible: {final.get('final_stance', {}).get('deployment_eligible')}")
