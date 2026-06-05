# Codex R1 Challenge Note — 3-Mode 헌법개정 (`qvest_modes_sot.md` v0.1)

**일자**: 2026-06-05 · **Codex verdict**: `MAJOR_REVISION` (tokens 9,933) · 결과 JSON: `codex_r1.json`
**원칙**: No Silent Override — 각 concern을 ACCEPT / PARTIAL / REBUTTAL + 근거로 분류. **Codex는 veto 없음 — 최종 결정 도훈.**

## 자기합리화 점검 (의무)
- 모드 구조 REBUTTAL이 "도훈이 3모드라 했으니"(authority bias)인지 자문 → 운영축(워크플로·진입점·비용·네임스페이스)에서 3개가 **실제로 구분**되는 게 1차 근거. 단 Codex의 "collapse to 2"를 **희석 없이** 도훈께 전달하고 판단 위임(권위편향 회피).
- "대부분 결과 동일/관행적" 류 회피표현 미사용 점검 완료.

## Concern별 판정

| Dim | Sev | Codex 요지 | 판정 | 근거 / 조치 |
|---|---|---|---|---|
| 1 | H | 3 peer 모드 = 거버넌스 표면 3중 중복. Alpha=rigor-tier, FR=allocation consumer. 2-lane이 옳다. | **PARTIAL** | drift 문제 ACCEPT, 구조 collapse는 REBUT. → **3 운영모드 유지 + 단일 권위 spine**(synthesis). 도훈 mandate 영역 = D1. |
| 2 | H | "essence_score 단일권위" 선언만으론 proxy 권위화 못 막음. proxy가 telegram/methodology/backlog/Grade_A 파일명/corpus/PG로 새면 이미 권위. | **ACCEPT** | proxy 산출물 `grade` 금지→`screen_status`만. registry/book/backlog/corpus/telegram 나가는 payload에 `authority_level·metric_type·source_contract_id·n_trials·mode·admissible_for_capital` 강제. |
| 3 | H | §5-A (c) 2-tier: proxy가 survivor 고르면 계약백테가 **선택편향 표본**만 평가. | **ACCEPT(정밀화)** | 정밀히는 *다중검정/DSR 인플레*(개별 전략 계약추정 자체는 불편). 조치: proxy=triage/debug ONLY, pass/fail/grade/PG 권한 0. (a) 또는 (c')만. |
| 4 | H | FR을 peer로 두면 QEPM 산출 재등급 권위처럼 보임. 실제는 blender와 동일 직무(2차 소비자). | **PARTIAL** | 운영 모드는 유지(D2), 단 출력 타입 `composite_allocator`+`eligible_for_alpha_registry=false`+alpha registry 물리분리 ACCEPT. blender와 구현 통합은 Phase 2 검토. |
| 5 | H | path-prefix mode 판정 = 파일명우연→경로우연. 복사/temp/cache/symlink/legacy서 오판. | **ACCEPT** | path 폐기 → **artifact manifest**(`qvest_mode_manifest.json`/frontmatter: mode·authority_level·contract_run_id·parent_strategy_id·generated_by_entrypoint) 권위, path는 보조신호. |
| 6 | H | 분리 자체가 cross-mode graduation 모호 + FR이 stale 풀 소비. | **ACCEPT** | **재사용-상태기계** 신설: `screen_pass→contract_pass→qe_pm_graduated→capital_admitted→fr_eligible`. FR 입력=`qe_pm_graduated`+module hash 검증만. |
| 7 | H | wall을 Phase3로 미루면 **live integrity hole**(현 Alpha proxy A/B/C/F가 registry/book로 누수). | **ACCEPT** | 최소 interim guard를 **Phase 1로 승격**: 계약 run_id 없는 Alpha 산출물의 Grade표기/PG권고/book_state/공유registry/methodology write 차단. |
| 2b | M | DSR `n_trials` 모드별 재량 누수("1논문=1trial"로 변형 포장). | **ACCEPT** | n_trials = **실행로그 산정**(동일 idea_id 하 파라미터/유니버스/기간/weighting 변형 자동 합산). 인간선언 금지. |
| 6b | M | FR_001이 essence+backtested라 QEPM 후보 오인. | **ACCEPT** | Dim4 조치(composite_allocator 타입 + registry 분리)로 커버. |

## 핵심 재구성 (Synthesis — Codex 실질 흡수 + 도훈 3모드 보존)
**3개 "운영 모드" 유지**(도훈: 워크플로·진입점·네임스페이스 분리) **+ 단일 "권위 spine"**(Codex: drift 차단).
- 'Grade A'를 **모드별 판정에서 분리** → contract run_id + manifest 기반 **재사용-상태기계**로 일원화. 모드는 *워크플로만* 다르고, 권위·자본적격·재사용권한은 **한 곳**에서 산출.
- gate 변경 시 essence_score + 상태기계 **1곳만** 갱신(현 6~10 표면 동기화 문제 제거).
→ Codex의 semantic-drift 우려를 **모드 수를 줄이지 않고** 해소.

## 도훈 결정 필요 (pivotal)
- **D1 모드 구조**: (i) **3 운영모드 + 단일 권위 spine** 〔권고〕 / (ii) Codex 2-lane(Alpha=tier, FR=blender) / (iii) R2 추가토론(제가 synthesis로 Codex에 반박 → stance 갱신 확인)
- **D2 FR**: 운영 독립 모드 유지(+composite_allocator 타입) vs blender 흡수
- **D3 §5-A**: (c) 폐기 확정 → (a) full-contract or (c') proxy=triage-only. 권고 (c').

## 방향 무관 즉시 반영(ACCEPT, D1 결과와 독립)
manifest 기반 mode 판정 · proxy sink-ban + payload 필드 · 재사용 상태기계 · **interim guard Phase 1 승격** · n_trials 로그산정 · FR composite_allocator 타입.
