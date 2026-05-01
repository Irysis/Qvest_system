# 01 Discovery Happy Path — `WT-D99990101_001`

**시나리오**: 신규 Discovery WT가 alpha → risk → optimizer → forge → judge → governor 전체 lifecycle을 통과하고 admit되는 reference case.

## 핵심 학습 포인트

1. **alpha_package** harvey_t=4 + cor=0.10 + factor_specs 2개 → `alpha_discovery_certificate` ISSUED
2. **forge_package** 8 mandatory field 충족 + measurement_basis_primary="forge_realized_share_based" → `sr_provenance_certificate` + `forge_package_validated_certificate` ISSUED
3. **optimization_package** schedule_density=1.0 → `schedule_fidelity_certificate` ISSUED
4. **judge_verdict** verdict=APPROVE
5. **governor_admission** GOVERNOR_ADMITTED + str_id=WT-D99990101_001 + allocation=0.05

## File 구성

| File | 역할 |
|---|---|
| `request.json` | WT 생성 spec (hypothesis_title, theme, wt_type, universe) |
| `alpha_package.json` | 4 AND condition 충족 — cor 0.10 + mech 100+ chars + factor_specs 2 + harvey_t 4 |
| `risk_package.json` | factor_covariance_ref + risk_summary + diagnostics |
| `optimization_package.json` | method=MVO, target_weights, schedule_fidelity 100% density |
| `forge_package.json` | 8 mandatory field (sr_realized_share_based 1.5, schedule_density_pass=true) |
| `judge_verdict.json` | verdict=APPROVE |
| `governor_admission.json` | GOVERNOR_ADMITTED + allocation_decided |
| `alpha_discovery_certificate.json` | ISSUED — 4 AND eligibility 충족 |
| `sr_provenance_certificate.json` | ISSUED — 4 field 충족 |
| `forge_package_validated_certificate.json` | ISSUED — 8 field 충족 |
| `governance_log.json` | events[] — PHASE_ADVANCE 6건 + cert ISSUED 3건 |
| `status.json` | current_phase=GOVERNOR_ADMITTED |

## 다음 단계 reference

이 example을 reading하면:
- 정상 cert 발급 흐름 (alpha_discovery → sr_provenance → forge_package_validated → governor_concord)
- 6 role artifact_lineage chain 이해
- governor_admission str_id ↔ book_state.admitted_ids 매핑 패턴
