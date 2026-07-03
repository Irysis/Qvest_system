# 05_Production Promote Flag — Layer4 제거 (WT-D20260702_002)

**상태: ✅ COMPLETED (2026-07-02) — 슬롯 2-3 정식 materialize 완료.**
**작성**: governor. book_state v2.5 + 05_Production 슬롯 2-3 생성 완료 (도훈 FINAL 승인 + coordinator promote 지시 2026-07-02).
**잔여 수동**: 실계좌 주문(2버튼 중 실주문)만 도훈 수동.

## ✅ 완료 요약 (promote materialize)
- 슬롯 `2-3.STR_1715_on_M4_R05_noLayer4_PG2` 생성 (제안 A 채택 — 아래 원안).
- 01_reproducible_code (generator+파이프라인+README) / 02_holdings_universe (당월 홀딩) / 03_admit_artifacts (decision+judge+challenge+book_state v2.5 snapshot) / 04_backtest_results (10-component+rds, 클린 annualization=12) / 05_lineage_chain (inherit_pointer) 전부 완비.
- 04_backtest_results: audit PASS=13 FAIL=0 WARN=3(panel-lineage 필연) · validate valid=TRUE · judge 정합 PASS(SR_geo 1.898·CAGR 0.4526·MDD 0.2329·Calmar 1.943·PORT_t 6.214) · annualization=12(252버그 회피).
- 2-1/2-2 기존 파일 **무변경** (filesystem 확인). 2-2에 `_SUPERSEDED_by_2-3_noLayer4.md` 마커 신규 1건만 추가(비파괴).

---

## [이력·원안] 왜 자동 promote_to_production()를 쓰지 않았나 (정직 보고)
`02_Infrastructure/portfolio/promote_to_production.R::promote_to_production()`는 **04_Research/strategies/{id}에 Grade-A hurdle_result.json이 있는 standalone 전략을 새 05_Production 슬롯으로 복사**하는 함수다. 본 건은 그 시나리오가 아님:
- noLayer4 book은 04_Research standalone 전략이 아니라 **기존 05_Production 슬롯 2-2의 오버레이 층(Layer4) 제거**다.
- `promote_to_production("STR_1715_on_M4_R05_noLayer4_PG2")` 실행 시 line 39 "not found in 04_Research/strategies/"에서 stop — 부적합 경로.
- 올바른 반영 = 새 슬롯 `2-3.STR_1715_on_M4_R05_noLayer4_PG2` 생성 또는 슬롯 2-2 오버레이 in-place 변경 = **production 코드 작성/수정** → 규율상 governor 직접 수정 금지(도훈 수동).

## 정확히 무엇을 promote해야 하는가
현 배포 슬롯 상태:
- `2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2` = 현 active (Layer4=β_faith 포함) — **제거 대상**
- `2-1.STR_1715_AR_on_M4_R05_overlay_PG2` = rollback 보존 (Layer4=β_AR)

### 제안 A (권장): 새 슬롯 2-3 생성
1. `05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/` 생성.
2. `01_reproducible_code/`: `forward_weights_R05_noLayer4.R` (본 WT 산출, 검증 완료) 복사 + `run_pg2_forward.sh`에서 combine step을 noLayer4 generator로 배선(β_faith/β_AR 미적용). run_all.R / m4 / R05 배선은 2-2 미러.
3. `04_backtest_results/`: Step3 clean bt_result(annualization=12) 기반 10-component 산출. ⚠ **RDS 06_metrics 연율화 버그(252)** 회피 — factor=12로 재산출(별도 chip task_b2ebfb2f 근본수리 후 정합 재확인 권장).
4. `02_holdings_universe/`: 본 WT 산출 `20260701_noLayer4_weights_cap_0p20.csv` (현금 75.22% · 20종목 24.78%) 복사.
5. active slot 지정 = 2-3. 2-2(faith)는 rollback 보존(2-1 AR과 동일 패턴).

### 제안 B: 슬롯 2-2 in-place 오버레이 변경
- run_layer5_faith_overlay.R에서 β_faith 곱을 제거 (β_faith=1.0). 슬롯명은 유지되나 book_state id와 불일치 발생 → 비권장(감사 추적성 저하).

## 스테이징된 검증 산출물 (WT-D20260702_002/output + WT dir)
| 파일 | 내용 |
|---|---|
| `output/20260701_noLayer4_weights_cap_0p20.csv` | 라이브(2026-07) 종목레벨 배포 비중 (현금 75.22% · 주식 24.78% · 20종목) |
| `output/20260701_noLayer4_manifest.json` | 오버레이 분해 (m4 0.826 × β_R05 0.30, β_faith REMOVED) |
| `output/bt_result_C_noL4_CLEAN_ann12.rds` | clean bt_result (monthly annualization=12, judge 정합 PASS) |
| `output/06_metrics_noL4_clean_ann12.csv` | 정확 연율화 metrics |
| `output/07_benchmark_compare_noL4_clean_ann12.csv` | PORT_t 6.214 등 |
| `output/step3_clean_recompute_meta.json` | judge 정합 대조 결과 |
| `forward_weights_R05_noLayer4.R` | forward generator (05_Production forward_weights_R05_FAITH.R 미러, β_faith 제거) |
| `recompute_bt_noLayer4_clean.R` | clean 재계산 스크립트 |

## 실투 2버튼 (수동 유지)
1. **book confirm** — book_state v2.5 (완료, 도훈 FINAL) → 05_Production 슬롯 확정.
2. **실주문** — noLayer4 홀딩(현금 75.22%·20종목 24.78%)으로 리밸런싱 주문 실행 (execution agent 경유, 도훈 수동 트리거).

## 무결성
- book_state.json = v2.5 갱신 완료 + backup `book_state_backup_pre_layer4_removal_20260702.json` 보존.
- 05_Production 파일 **0건 수정** (규율 준수 — 참조만).
- 재계산값 judge 정합 PASS (SR_geo 1.898 · CAGR 0.4526 · MDD 0.2329 · Calmar 1.943 · PORT_t 6.214).
