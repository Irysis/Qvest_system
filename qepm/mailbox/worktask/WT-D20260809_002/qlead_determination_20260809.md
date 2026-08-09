# Q-Lead 판정 — WT-D20260809_002 (2026-08-09)

`request.json::provenance_note` 가 요구한 "Q-Lead 는 이 파일을 정본으로 승인하거나 교체할 것" 에 대한 응답이다.
**request.json 을 덮어쓰지 않는다** — 라운드가 진행 중이라 입력을 바꾸면 그때까지의 측정이 무엇에 대한 것이었는지 흐려진다.
대신 판정을 별도 파일로 남기고, 인용 시 이 파일을 병기하도록 한다.

## 1. 정본 승인 — 조건부 승인

`request.json` 을 **본 라운드의 정본으로 승인**한다. alpha-research 가 브리핑에서 재구성했으나 내용이
브리핑 원문에 근거하고 새 요구사항을 창작하지 않았음을 확인했다(hypothesis_description·boundaries·mandated_gates 대조).

**단 아래 2·3 을 함께 적용한다.**

## 2. ★base 라벨 의무 — `legacy-base scoped`

`incumbent_base` 가 `05_Production/2.Factor_Model/**2-2**.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/.../period_returns_layer5_faith.csv`
이고 산식이 `ret_noL4 = beta_R05 × m4 × ret_orig − |Δbeta_R05| × 15bps` 다.

**2026-08-09 β_R05 권위 판정 실측**(같은 날, Q-Lead):
- `beta_R05 × m4` 는 **재계산 경로**의 노출이다 — `live_book_series::invested_eff` 와 271/271 동일하고
  `ret_recompute_panel` 재현 cor **1.00000**.
- 그러나 권위는 `ret_net` 이다(§2b 계약 rds 앵커). **rds 앵커월 162/271 에서 재계산 노출은 ret_net 을 재현하지 못한다**
  — cor **0.575**, 100개월이 0.02 초과 이탈. 생성기가 `beta_matches_ret_net` 로 이미 신고하고 있었다.
- 현 admitted 는 **2-4** `STR_1715_on_M4gAE_R05_noLayer4_PG2` 이고, 2-2 는 퇴역 슬롯이다.

⇒ **본 라운드의 모든 수치는 `legacy-base scoped` 로 라벨한다.**
- 인용 시 base 병기 의무: "2-2 FaithTrend base · β×m4 재계산 산식".
- **현 admitted(2-4) base 위에서 잰 결과와 나란히 놓지 말 것.** 같은 축을 다른 프레임에서 재면
  두 판정이 갈리는데 그 갈림이 신호 차이로 읽힌다(중복 측정보다 위험한 실패 모드).
- 자본 상신 근거로 사용 금지(§7b — incumbent base 권위는 현 production 코드 경로).

## 3. ★FQ 발번 정정

`request.json::id_namespace_warning` 이 지적한 대로:
- 브리핑 인용 **`FQ-143` 은 오기**다. 실제 `FQ-143` = CV_Vol (`config_scoped_negative_20260804`) 이며 본 라운드와 무관하다.
- **본 라운드의 계보 앵커 = `FQ-119` + 2026-08-08 라벨 자격 실측**(월<0% 무자격 / <−10% 3.19x 통과).
- 신규 FQ 발번은 라운드 **판정 수집 시점**에 한다(미리 발번하면 미측정 항목이 큐에 쌓인다).
  발번 시 `FQ-184`(게이트 ΔIR 단독 문제)와 `FQ-183`(깊이 축) 을 `related` 로 연결할 것.

## 4. 동시 라운드 충돌 고지

**같은 날 Q-Lead 가 같은 축을 측정했다** — regime chain step 4 "노출 깊이" 반응면
(`stage_artifacts/paper_recharge/depth_response_surface_20260809.json`, 271개월, **2-4 base**).
본 라운드 제목의 "심도-표적 노출 축소" 와 같은 질문이다.

두 결과의 관계:
- **프레임이 다르다**(base 2-2 vs 2-4, 산식 재계산 vs ret_net 앵커, 창 vs 271개월).
- 따라서 **서로 검증이 아니다**. 일치해도 재현이 아니고 불일치해도 반박이 아니다.
- 재측정 없이 비교하려면 최소한 base·창·산식 3축을 병기해야 한다.

`FQ-183::concurrent_round_conflict` 에 같은 내용을 등재했다.

## 5. 자본 게이트

본 판정은 측정·기록 판정이다. `book_state` 미변경, 실주문 없음, governor 정지 유지.
