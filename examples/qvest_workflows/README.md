# Qvest Workflow Examples

3개의 synthetic 표준 WT (Year 9999 prefix — production mailbox 무손상).

각 example은 도훈이 직접 읽고 이해할 수 있는 reference. 14 schema valid + qvest_search `--include-examples`로 인덱싱 가능.

| Example | WT ID | 시나리오 | 결과 |
|---|---|---|---|
| 01 | `WT-D99990101_001` | Discovery happy path (모든 phase 통과, alpha/sr/forge cert ISSUED) | GOVERNOR_ADMITTED |
| 02 | `WT-D99990102_001` | Cert fail passive deny (alpha cert NOT_ISSUED, lifecycle 진행, governor 차단) | GOVERNOR_REJECTED |
| 03 | `WT-D99990103_001` | PIT violation (lookahead pattern injection, judge FAIL) | JUDGE_FAILED |

## 학습 가치

- **01**: 정상 lifecycle reference — 6 phase 통과 + cert 발급 흐름 이해
- **02**: alpha cert NOT_ISSUED여도 RISK/OPT/FORGE/JUDGE 진행 가능 (Charter v1.7 §10 정합) → admission 단계 passive deny — 학습 가치 우선
- **03**: Judge가 lookahead pattern (lm(future_return ~ today_factor)) 감지 → JUDGE_FAILED → ABORTED

## Replay (선택)

각 example은 정적 fixture. 실행할 필요 없음. 단 timeline rebuild로 직접 확인 가능:

```bash
# fixture를 임시 mailbox로 복사 후 timeline 생성
cp -r examples/qvest_workflows/01_discovery_happy_path /tmp/replay_qvest/
CLAUDE_PROJECT_DIR=/tmp/replay_qvest bash 02_Infrastructure/observability/qvest_wt WT-D99990101_001
```

## CI 검증

`.github/workflows/qvest-kernel-ci.yml::schema_validate` job이 examples 14 schema 검증 (status / governance_log / expected_timeline 분기 whitelist).

## Synthetic ID 정책

- prefix `WT-D9999` (year 9999)
- production mailbox에 leak 시 `_e2e_cleanup_guard.sh --check` CI gate 자동 차단
- `qvest_search` default 제외 (--include-examples opt-in 필요)
- `qvest_wt --recent` default 제외 (--include-test opt-in 필요)
