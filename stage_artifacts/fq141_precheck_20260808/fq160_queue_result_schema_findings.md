# FQ-160 재정의 — 프론티어 큐의 **결과 계층에 스키마가 없다** (2026-08-08)

**성격**: read-only 원장 감사. **판정: 원안(창 메타를 `wall_check` 에 추가) 전제 어긋남 → 재정의.**

---

## 1. 원안이 어긋난 지점

NP-157c 는 창 길이별 핸디캡 지도를 만들고 "기각 건에 결합하려면 `wall_check` 에 창 메타가 필요"로 넘겼다.
실측하니 `wall_check` 는 **측정 결과를 담는 자리가 아니었다**.

- `wall_check` 실질 보유 157/164, 그중 창 정보(n=·개월·연-월) 보유 = **2건 (1.3%)**
- 내용 표본: `FQ-001` "…전이 벽은 미검증 — canonical PORT_t가 최종 관문" / `FQ-002` "…IC→PORT_t 전이는 미검증"
  ⇒ **가설 시점의 예상 서술**(이 항목이 어떤 벽에 걸릴 것 같은가)이지 사후 측정 기록이 아니다.

## 2. 실제 결함 — 결과 필드명이 109종

| 축 | 값 |
|---|---|
| entries | 164 |
| 코어 11 필드(`id/lane/title/hypothesis/ev_rationale/wall_check/data_gate/owner/status/next_action/source_refs`) 외 필드 **종류** | **109종** |
| 임시 결과 필드를 하나 이상 가진 entry | **139 / 164 (84.8%)** |

출현 빈도 상위(코어 외): `registered` 62 · `result_ref` 31 · `result` 24 · `precheck_measured` 22 ·
`verdict` 20 · `revival_conditions` 20 · `next_probe` 11 · `result_lcode` 7 · `verdict_date` 6 ·
`result_artifacts` 5 · `precheck_20260808` 5 · `measured_verdict` 3 · `precheck_result` 3 …

동의어 군집이 그대로 보인다:
- 결과: `result` / `result_ref` / `result_lcode` / `result_artifacts` / `result_20260725` / `alpha_round_result` /
  `direction_a_result` / `ev_check_result` / `build_result_20260725` / `acquisition_result` / `key_finding`
- 판정: `verdict` / `verdict_date` / `verdict_artifact` / `measured_verdict`
- 사전확인: `precheck_measured` / `precheck_result` / `precheck_20260808`
- 부활: `revival_conditions` / `revival_signal` / `revival_trigger`
- 소비면: `consumer_surfaces` / `consumer_surfaces_checked` / `consumer_surfaces_untested` /
  `consumption_surfaces_checked` / `consumption_path`

## 3. 왜 이게 알파 차단인가 (위생이 아니라)

CLAUDE.md 는 인프라 즉시 수리를 ①알파 라운드를 실제로 막는 결함 ②측정 신뢰 훼손 2기준으로 한정한다.
이건 ①에 해당한다:

- **소비자가 기계적으로 읽을 수 없다.** "이 FQ 는 무엇으로 측정됐고 언제 창에서 쟀나"를 물으려면
  109개 이름을 알아야 한다. 소비 코드를 쓸 수 없으므로 **측정 지식이 라운드 간에 전달되지 않는다**.
- 실제로 이번 세션에서 그 비용을 지불했다 — NP-157c 산출물(창 길이별 핸디캡 지도)을 기존 기각 164건에
  **결합할 방법이 없어** 소비가 멈췄다.
- 계통 = 메모리 `[[project-wiring-map-standards-unconsumed-20260808]]`("표준은 있는데 소비자 0")과 동형이나
  방향이 반대다. 여기는 **표준 자체가 없어** 소비자가 생길 수 없다.

## 4. ★ 자기 기여 (정직)

이번 세션에서 필자가 **3개 신규 필드명을 보탰다**: `np_a_result`(FQ-141) · `np_157c`(FQ-157) ·
`precheck_20260808`(FQ-141/156). 스키마가 없으니 매 세션이 자기 이름을 짓는 것이 국소적으로 합리적이고,
그래서 109종이 됐다. **개별 세션의 부주의가 아니라 스키마 부재가 원인**이다.

## 5. 제안 (실행은 도훈 판단 — 원장 전면 수정이므로)

최소 스키마 `measurement` 객체 1개로 동의어 군집을 흡수:

```json
"measurement": {
  "verdict": "<enum: measured_positive | config_scoped_negative | precheck_refuted | capability_established | ...>",
  "window_months": 167, "window_end": "2026-06",
  "metric_type": "canonical_screen | backtested | canonical_screen_diag | proxy",
  "port_t": 2.198, "basis": "cap_w",
  "measured_at": "2026-08-08",
  "artifacts": ["..."], "l_code": "...",
  "revival": "...", "next_probes": ["...", "..."]
}
```
- **소급 이관은 자동 불가**: 109종의 값 형식이 제각각(문자열/객체/리스트 혼재)이라 기계 변환은 손실적이다.
  현실적 경로 = ①신규부터 `measurement` 강제 ②기존은 **읽기 어댑터**(동의어 → 정본 매핑 테이블)로 흡수
  ③미기재분은 `UNKNOWN` 명시(**빈칸을 합격으로 읽지 않기** — 이 저장소 반복 계통).
- 강제 지점 = 큐 쓰기 경로에 스키마 검증 + 위반 주입 테스트.

## next_probe

- **NP-160a** — 읽기 어댑터 먼저(원장 무수정): 109종 → 정본 키 매핑 테이블을 만들고,
  "이 FQ 의 측정 창은?" 질의가 몇 % 응답 가능한지 실측. **이게 낮으면 스키마를 새로 강제해도
  기존 지식은 여전히 소비 불가** — 즉 어댑터 커버리지가 스키마 도입 EV 의 상한이다.
- **NP-160b** — 창 메타 회수 가능성: `source_refs` / `result_artifacts` 가 가리키는 산출물에서
  측정 창을 **역추출**할 수 있는 비율. 큐 본문에 없어도 아티팩트에는 있을 수 있다(NP-157c 소비의 실제 관문).
- **NP-160c** — 신규 쓰기 강제만 선도입했을 때의 분기 비용 추정: 어댑터 없이 강제하면
  "신규는 정본 · 기존은 109종" 이원화가 고착된다. 도입 순서(어댑터 선행 vs 강제 선행)를 실측으로 결정.

## 부활 조건 (INV-7)

원안(창 메타를 `wall_check` 에 추가)은 `wall_check` 의 의미가 "예상 서술"에서 "측정 기록"으로
재정의되는 경우에만 부활. 현 의미로는 잘못된 자리다.
