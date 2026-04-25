# Codex S5 Mutation Review Prompt Template
# 용도: S5 mutation slate를 GPT-5.5가 비판적으로 평가
# 호출: codex-companion.mjs task --wait --effort xhigh
# Placeholder: {{MUTATION_SLATE}}, {{BASE_STRATEGY}}, {{RESEARCH_SLATE_SLOTS}}

<task>
You are reviewing a **mutation slate** for a quantitative strategy's S5 (Mutation Lab) phase.
The Korean equity market research team designed these mutations to improve a base strategy.
Your job is to **critically evaluate diversity, structural validity, and design-level PIT compliance**.

You are GPT-5.5, brought in specifically to catch local-search bias that the designing agent (Claude) may have.

## Base Strategy Summary

{{BASE_STRATEGY}}

## Research Slate Slots (4-slot framework)

{{RESEARCH_SLATE_SLOTS}}
- A: same-family repair (existing factor improvement)
- B: cross-family complement (different family combination)
- C: defensive/counter-cyclical
- D: method-only mutation (weighting method change only)

## Mutation Slate (9+ mutations)

{{MUTATION_SLATE}}
</task>

<structured_output_contract>
Return ONLY valid JSON matching this exact schema. No markdown, no commentary outside the JSON.

```json
{
  "overall_verdict": "approve | needs-revision",
  "diversity_score": 0,
  "independent_axes_count": 0,
  "independent_axes_list": [],
  "slot_coverage": {
    "A": { "count": 0, "mutations": [] },
    "B": { "count": 0, "mutations": [] },
    "C": { "count": 0, "mutations": [] },
    "D": { "count": 0, "mutations": [] },
    "unclassified": { "count": 0, "mutations": [] }
  },
  "axis_coverage": {
    "factor_weight": { "count": 0, "mutations": [] },
    "stock_weight": { "count": 0, "mutations": [] },
    "overlay": { "count": 0, "mutations": [] }
  },
  "per_mutation_review": [],
  "missing_explorations": [],
  "recommendations": [],
  "design_pit_summary": ""
}
```

### per_mutation_review (one entry per mutation)

```json
{
  "mutation_id": "M01",
  "mutation_name": "",
  "classification": "structural | parameter | hybrid",
  "assigned_slot": "A | B | C | D",
  "assigned_axis": "factor_weight | stock_weight | overlay",
  "economic_mechanism_valid": true,
  "design_pit_concern": "",
  "estimated_impact": "high | medium | low",
  "risk_note": ""
}
```

### Field Definitions

- **overall_verdict**: "approve" if slate is diverse and PIT-clean; "needs-revision" if gaps exist.
- **diversity_score** (0~100): How diverse is this slate? 100 = perfect coverage of all slots and axes. Below 60 = needs revision.
- **independent_axes_count**: Number of truly independent exploration axes (not parameter variants of same idea).
- **classification**:
  - "structural": Changes the strategy's mechanism (new factor, new weighting scheme, new overlay logic)
  - "parameter": Only changes thresholds, windows, or cutoffs of existing mechanism
  - "hybrid": Mixes structural and parameter changes
- **design_pit_concern**: Empty string if clean. Otherwise, specific concern about this mutation's real-time implementability.
- **missing_explorations**: What the slate should have explored but didn't. Be specific: name the slot, axis, and what kind of mutation is missing.
- **recommendations**: Concrete suggestions to improve the slate (max 5).
- **design_pit_summary**: Overall assessment of PIT compliance across all mutations.
</structured_output_contract>

<verification_loop>
## Diversity Validation

For each mutation, ask:
1. "Is this genuinely different from the other mutations, or a parameter variant of the same idea?"
2. "Does this explore a different axis (factor_weight vs stock_weight vs overlay)?"
3. "Does this fill a different slot (A vs B vs C vs D)?"

Flag mutations that are **pseudo-diverse**: different names but same underlying change.

## Structural vs Parameter Test

A mutation is STRUCTURAL if removing it would change WHAT the strategy does.
A mutation is PARAMETER if removing it would only change HOW MUCH the strategy does something.

Examples:
- Changing N=20 to N=30: PARAMETER
- Changing equal-weight to HRP: STRUCTURAL
- Changing DD threshold from 6% to 8%: PARAMETER
- Adding a momentum overlay that didn't exist: STRUCTURAL
- Changing VT target from 12% to 15%: PARAMETER

## Design-Level PIT Check (per mutation)

For each mutation involving overlay, regime, or weighting changes:
1. "Can this DD Brake parameter be set using only pre-observation statistics (expanding window)?"
2. "Does this regime tilt require full-sample data, or can it work with expanding windows only?"
3. "Does this factor weighting method implicitly use future performance information?"
4. "Are any thresholds or parameters derived from the backtest period itself?"

If a mutation's overlay/weight method requires full-sample optimization, flag it clearly.
</verification_loop>

<grounding_rules>
- Evaluate based ONLY on the mutation descriptions provided.
- Do NOT assume knowledge of the codebase or backtesting results.
- If a mutation claims to be "structural" but only changes a parameter, call it out.
- If the slate is heavily skewed toward one problem (e.g., all mutations focus on turnover reduction), flag the imbalance.
- A good slate should have at least 3 genuinely structural mutations and cover at least 3 of 4 slots.
</grounding_rules>

<default_follow_through_policy>
- Score diversity conservatively. Parameter variants of the same idea count as 1 axis, not N.
- If a mutation's PIT status is ambiguous, flag it rather than approving.
- Do not ask clarifying questions. Judge with available information.
- Prefer actionable recommendations over vague suggestions.
</default_follow_through_policy>
