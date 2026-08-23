# v8 프롬프트 아카이브 (2026-08-23, v9 Lean Loop 컷오버)

여기 있는 두 파일은 **현역이 아니다**. v9 Lean Loop §3.4(e) 로 축소되기 직전의
원본이며, 축소가 무엇을 덜어냈는지 대조하려고 남긴다(삭제 아님).

| 아카이브 | 현역 | 축소 |
|---|---|---|
| `paper_router_prompt_v2_20260823.md` (16.4KB) | `../paper_router_prompt.md` | STEP 1-b(optimizer/risk 2축) → `../mode_queue_research_prompt.md` 이관 · **STEP 3 autorun 삭제**(라우터는 백테를 돌리지 않는다) |
| `alpha_search_queue_prompt_v8_20260823.md` (6.3KB) | `../alpha_search_queue_prompt.md` | L1~L3 수동 verdict 수집 삭제 · **L4 `claude -p` 충실성 검증자 삭제**(31건 중 판정 기여 0) · L5 게이트는 프롬프트가 아니라 래퍼(`alpha_search_queue_run.sh`)가 런 종료 후 산출물 전수에 적용 |

★왜 덜어냈나 (실측):
- 라우터가 STEP 3 에서 직접 백테를 돌려 런이 50분 상한에 걸렸고, 소비자 래퍼와
  **이중 실행**이 났다. 라우터의 일은 배분이지 측정이 아니다.
- L4 검증자는 `claude -p` 를 한 번 더 스폰하면서 31건 처리 동안 판정을 바꾼 적이 없다.
- L1~L3 을 프롬프트가 손으로 모으게 하면 값이 산문에서 만들어진다 — 래퍼가
  `hurdle_result.json` / `strategy_manifest.json` 산출물에서 기계로 뽑는 것이 정직하다.
