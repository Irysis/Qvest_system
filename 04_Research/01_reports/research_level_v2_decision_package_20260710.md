# 리서치 레벨 v2 — 도훈 결정 패키지 (2026-07-10)

**출처**: 리서치 레벨 v2 워크플로우(wf_82c7251a — corpus 256 L-code EV지도 + 목표-갭 구조분해 + 크로스모드 지도 + 프로그램 설계). 전 수치 실측·경로 병기. 상세 = `stage_artifacts/research_ev_map/` + `06_Registry/research_ev_map.json`.

## 핵심 실측 (먼저 아셔야 할 것)

1. **목표 3개 중 2개는 이미 충족**: CAGR 45.22 (목표 16) · MDD 23.29 (목표 25, 단 여유 1.7p 얇음 — naked 40.74를 오버레이가 지탱). **binding 갭 = SR 단일**: arith 1.7042 / geo 1.898 vs 목표 2.5. (출처 `qepm/mailbox/worktask/WT-D20260702_002/output/06_metrics_noL4_clean_ann12.csv`)
2. **갭은 decay가 아니라 수준 문제**: book SR은 pre/post-2017 안정(1.68/1.72, last60m 1.93). 2.5 도달엔 동일 변동성에서 연 +19.0p 산술수익 추가 필요.
3. **비신호 구조 레버 전수 실측 = 갭의 약 2%**(+0.012~0.017 SR): "신호를 얹으면 희석"(fleet-1)의 대칭으로 "구조 레버로도 갭은 못 닫는다"가 실측 확정.
4. **유일한 즉시-실현 레버 = 라이브 유휴현금 캐리**: 현 라이브 현금 75.22 (book_state) × CD91 3.03 → **지속 가정 시 연 약 +2.3p, 결정론적·신호리스크 0**. 백테 전기간 기여는 +0.36p CAGR / +0.012 SR로 작음(과거엔 평균 현금 8.4뿐이라) — 즉 이건 백테 개선이 아니라 **실계좌 운용 개선**.
5. SR 컨벤션 발견: 계약 Sharpe가 rf=0 입력이라 사실상 raw-basis. 실제 rf 차감 시 1.583. (기준선 정합 사안 — G3)

## 결정 요청 G1~G5

| # | 사안 | 요청 | 권고 |
|---|---|---|---|
| **G2** | **라이브 MMF/RP sweep** (유휴현금 캐리) | 실계좌에서 대기 현금을 MMF/RP로 굴리는 실행 승인 (실주문 = 도훈 전권, governor 자동화 금지 불변) | **승인 권고** — 결정론적 무위험, 유일한 즉시 레버. 단 크기는 조건부(노출 회복 시 축소) |
| **G1** | FQ-009 mid-cap 국소 알파 소비 프레임 | 벤치-상대 배포성 lane 개방 vs 공식 종결 | 판단 유보 자료: 상방 근거였던 "MID t=3.02"는 미검증 회상으로 철회됨 — 잔여 근거는 V02_EP EW 4.40(그러나 ew_oos 0.52·OTHER 98.6 capacity flag)뿐. **약화된 상방 정직 고지** |
| **G3** | book_state 기준선 갱신 (SPEC-1: 캐리 + m4 무과금 정정 **세트**) | incumbent_book_ir(1.416, net_active_recon_v1) 재정의 confirm — book-marginal 게이트의 분모 | audit PASS 산출물 확인 후 승인 권고. ⚠ m4 정정은 하향 방향·크기 미측정 — 캐리(+)만 반영 금지(세트 규약) |
| **G4** | 비-return 데이터 작업 목록 (FQ-003/004/005) + FQ-010 논문라인 지출한도 | 항목별 승인/보류 | 목록 제시만 (헤드라인 아님 — mandate 준수) |
| **G5** | (조건부) 리밸 tranche 채택 시 실행 스케줄 변경 | SPEC-2 forge 측정 후 유의 시에만 | 측정 후 재회부 |

## 죽은 계급 — 예산 0 명시 (재제안 차단, 근거 `research_ev_map.json`)

D1 횡단 return-파생 신규(130건+ 포화) · D2 M4×R05 초월 오버레이 · D3 미시구조/flow/정보이론 · D4 occurrence 이벤트 · D5 ml/uncertainty sizing · D6 composite/packaging · D7 RAMP chain 신규 + 벤치앵커·R05 히스테리시스·book 위 return-구조 일반.

## Q 즉시 실행 (결정 불요, 진행 중/예정)

- ✅ SPEC-1 자산 구제: `04_Research/pg2_carry_convention/` (a2_gap_decomp.R·a2_panel_carry.csv 이관 완료)
- ✅ EV지도 registry 승격: `06_Registry/research_ev_map.json`
- 진행 중: WT-D20260710_005(공시-품질 신호)·WT-H20260710_001(마이크로튜닝)·fleet-2(overlay 16건 드레인 등)
- 예정: SPEC-1 build_bt_result 경유 재현 검증 → G3 재료 / FQ-007 revival 3건 / SPEC-2 forge 1-run / 3단 게이트 skill 명문화

## 정직 리스크 (요지)

v2는 SR 2.5 도달을 보장하지 않음 — 실측-확정 기여는 갭의 일부일 뿐, 갭 본체는 신호/구성 프론티어에 잔존(현재 측정상 소진). v2의 가치 = 낭비 차단 + 외부 게이트 해소 시 도달 확률 개선. 라이브 캐리 크기는 국면 조건부. MDD 여유 얇음 — 정정 반영 후 25 기준 재확인 필수.
