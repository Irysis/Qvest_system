# G3 재료 — 캐리+m4 정정 세트 반영 시 incumbent_book_ir 이동 (도훈 confirm 사안)

생성: 2026-07-11 16:42 · pin: `spec1_carry_20260711_163733` · book_state 변경 없음(본 문서는 재료).

## 수치 (계약 실측 — build_benchmark_compare, ann=12, pinned IKS200, 269m)

| 항목 | IR (net_active_recon_v1) |
|---|---|
| 현행 incumbent_book_ir 기록 (book_state.json, 07-02 vintage) | **1.4160** |
| 본 세션 계약 재현 — 07-02 vintage 시계열 (방법 검증) | 1.4160 |
| V0 base — 현행 vintage (원천 패널 2026-06 수정 반영) | 1.4055 |
| 캐리만 반영 (V1 — 채택 금지, 진단용) | 1.4194 |
| m4 정정만 반영 (V2 — 진단용) | 1.4052 |
| **세트 (V3 = 캐리 + m4 정정) — 채택 후보** | **1.4191** |

분해: 기록 1.4160 → 현행 vintage 1.4055 (**vintage 효과 -0.0105** — 원천 패널 2026-06 1개월 수정, 규약 무관·`spec1_vintage_diff.csv`) → 세트 1.4191 (**규약 효과 +0.0135** = 캐리 +0.0139 + m4 정정 -0.0003, vintage-내부 비교라 오염 없음). 기록 대비 순변화 +0.0031.

## 게이트 분모 영향 (1문단)

세트 규약 채택 시 incumbent_book_ir는 현행 vintage 기준 **1.4191**가 된다(기록 1.4160 대비 +0.0031 — 이 중 규약 효과는 +0.0135이고 나머지는 데이터 vintage 이동분). book-marginal admission 게이트(measurement-graduation §4, ΔIR = new_book_ir − incumbent_book_ir ≥ 0.05)의 분모(incumbent 기준선)가 이만큼 이동하므로 향후 신규 후보의 실질 admit 문턱도 동일 폭 이동한다 — 상승이면 보수화, 하락이면 완화. 공정성 조건 두 가지: ① 후보 북 recon에도 **동일 캐리+과금 규약을 대칭 적용**해야 비교가 성립(비대칭 적용 = 게이트 왜곡), ② **캐리만 반영은 금지**(낙관 편향 규약) — m4 무과금 정정(연 1.14bps 추가 비용, ΔSR -0.00058)과 반드시 세트로만 채택한다. 세트의 MDD는 23.08%로 25% 제약 내(여유 1.92%p), PORT_t 6.23로 HARD 2.95 상회 유지. ir_convention 라벨(net_active_recon_v1)은 불변 — SR basis rf=0 유지, 캐리는 ret_net 내 현금수익 반영이지 벤치·active 정의 변경이 아님. 반영 실행(book_state.json incumbent_book_ir 갱신 + ir_convention_note에 캐리 규약 추가)은 도훈 confirm 후 별도 커밋.

## 근거

- `spec1_set_metrics.json` (checks: judge 정합(07-02 vintage) PASS · 캐리 ΔSR 재현 PASS · MDD<25 PASS · audit critical FAIL 0 PASS)
- bt_result: `spec1_bt_v0_base.rds` / `spec1_bt_v3_set.rds` (10-component, audit 포함)
- 기준: `qepm/mailbox/worktask/WT-D20260702_002/output/07_benchmark_compare_noL4_clean_ann12.csv` (IR 1.41602608097397)

