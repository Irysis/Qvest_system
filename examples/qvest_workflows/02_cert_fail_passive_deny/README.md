# 02 Cert Fail Passive Deny — `WT-D99990102_001`

**시나리오**: alpha cert NOT_ISSUED지만 RISK/OPT/FORGE/JUDGE 진행 가능. Governor admission 단계에서 passive deny.

## 핵심 학습 포인트 (Charter v1.7 §10 정합)

1. **alpha_package** harvey_t_specs_pass_count=**1** (< 3 threshold) → `alpha_discovery_certificate` **NOT_ISSUED**
2. **그래도 lifecycle 진행** — RISK / OPT / FORGE / JUDGE는 alpha cert 무관하게 작성 가능
3. **Judge** 본 시나리오에서 APPROVE_CONDITIONAL (cert 부재가 hard FAIL은 아님)
4. **Governor admission** — `wt_check_graduation()` 단계에서 alpha_discovery cert 부재 감지 → **GOVERNOR_REJECTED** + scenario="alpha_cert_insufficient"
5. **book_state.admitted_ids** 변동 없음 (admit 안 됨)

## 왜 이 패턴인가 (Codex revised #4 옵션 B 채택)

- 연구는 끝까지 돌려 실패 사유를 축적 — admission에서 막는 구조가 학습 가치 큼
- WT_003 BHEQ 사례 정확히 이 패턴 (alpha cert 미발급이지만 risk-research 진행 + Q-Lead 보류)
- v6.4 코드 정합 (cert 부재 시 wt_check_graduation passive deny)

## File 구성 (15 file)

| File | 차이 (vs 01 happy) |
|---|---|
| alpha_package.json | **harvey_t_specs_pass_count=1** (< 3) — cert FAIL 트리거 |
| alpha_discovery_certificate.json | **issued=false**, non_issuance_reason="harvey_t_count 1 < 3" |
| risk/opt/forge_package.json | 동일 (lifecycle 진행) |
| sr_provenance_certificate.json | issued=true (forge_package 충족 — alpha cert 무관) |
| forge_package_validated_certificate.json | issued=true |
| judge_verdict.json | verdict=APPROVE_CONDITIONAL |
| governor_admission.json | **verdict=GOVERNOR_REJECTED**, scenario="alpha_cert_insufficient" |
| status.json | current_phase=GOVERNOR_REJECTED |

## 다음 단계 reference

이 example을 reading하면:
- alpha cert NOT_ISSUED 메커니즘 (4 AND 중 1개 fail)
- lifecycle 진행 정책 (Charter §10 cert 부재 ≠ block)
- Governor passive deny 트리거 패턴
- book_state 무손상 검증 흐름
