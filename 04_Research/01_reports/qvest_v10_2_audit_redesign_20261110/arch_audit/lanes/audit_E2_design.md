# 감사 레인 E2 — 강화 사슬 처방 설계 품질(채택 규칙 · 생성기 · 도구 상자) · 2026-11-10

## 1. 배선 지도
- 사슬 = `round_core/v1/p4.R`(E1): 기저 풀(상설 자격 ∨ 권위 등급 A/B · 구현 의심 · 감사 판정 · 롱 다리 · 팩터 DB 판) → 사슬 판(채택 규칙 threshold · 필수 dS_vis · uc_vis · d_dd_capture_median_vis) → 기준 칸 측정 → 걸음 열기(가설 · 블록 하나 · 칸 하나 · md5 · 예산) → 측정(rf_cell_worker) → 판정(`rc_p4_visible_metrics` = 등급 계약 보는 창 + 행동 카드 visible: 강세 상승 포착 중앙값 · 위기 하락 포착 중앙값) → 닫기(마지막 채택 · selection_regrade · 후보 관문).
- 생성기 = `P4_ASSEMBLY/_generator/g1/step.md`(50줄) · 입력 = design_input · 헌장 · toolbox(`rx_toolbox_md`) · 부모 칸. 판 등록부 `rx_generator.json`(g1 만 · evidence 0) · 개정 `rxg_revise`(철학 영수증).
- 도구 상자 = 셀 엔진 `rf_cell_engine.R`(팩터 적재 `.load_factor` · 결합 rank-Z · B7 슬리브 · 비중 catalog 가지) · `rf_sleeve.R` · 처방 검증 `rx_round.R::rx_validate`.
- 사슬 원장은 아직 0개(P4_ASSEMBLY 아래 chain_steps.jsonl 없음) — 아래 판단은 코드 · 등록부 기준이다.

## 2. 채택 규칙 대 헌장 (기계 조건으로 실렸나)
| 헌장 항목 | 기계 조건? | 사슬에서 실제 계산되나 | 새 숫자 없이 넣을 수 있는 조건(패치 제안 · p4.R) |
|---|---|---|---|
| §4 현금 기계 · 빈칸 24 | 일부 | uc_vis(강세 상승 포착 **중앙값**) ≥ uc_floor 만 · 기저 풀에는 상승 포착 조건 없음 | 걸음 규칙 N1(구간별 강세 참여 · 아래) + 기저 풀 제외 사유 `cash_machine`(보는 창 uc < uc_floor) |
| §4 한 번의 행운 · 빈칸 2 · 23 | 아니오 | 위기 포착 중앙값만 — 위기별 과반 · 깊은 위기 과반 없음 | N2 `deep_crisis_nonworse_share_vis` = 깊은 위기(시장 낙폭 ≥ 중앙 · 빈칸 2) 중 걸음 포착 ≤ 부모 포착인 비율 > majority_share(behavior_card.json) |
| §4 추첨 행운 · 빈칸 21 | 아니오 | 시드 띠 없음 | 학습 처치 블록(ML 게이트 · 분포 표적)에 한해 재시드 2회 칸을 같은 걸음에 묶어 '띠 안 승리 = 시드 미결 = 기각'(값 = 측정 띠 · 새 숫자 없음) |
| §4 지표 게이밍 · 빈칸 5 · 18 | 아니오 | CDaR · 회복 거래일 미계산(카드 stats$cdar 은 있음 · 사슬이 안 읽음) | N3 `d_cdar_vis ≤ 0`(낙폭 경로 비악화 · 빈칸 13 의 Δ 엄격 규칙을 비악화로) · 회복 지연 비율은 기록만(빈칸 5 = 꼬리표) |
| §4 크기 방어 착시 · 빈칸 14 | 아니오 | MC8 짝 · 크기 × β 동시 짝 미계산 | 방어 블록(regime_exposure · tail_overlay · defense_sleeve) 채택에 `mc8_label ∈ {selection}` 요구 — 귀속 라벨은 계약 산출(`matched_controls.R`) |
| §4 집중 · 빈칸 1 | 아니오 | 깊은 위기 한 종목 기여 미계산 | N4 `worst_name_contrib_deep_vis > −0.10`(빈칸 1 값 그대로) |
| 빈칸 3 · 8 β 비대칭 · β 짝 | 아니오 | 카드 stats beta_up/down 있음 · 사슬 미사용 | N5 노출 블록: `beta_down_vis < beta_up_vis`(빈칸 3) |
| 빈칸 4 엔진 강점 | 아니오(0.55 절대 하한만) | — | N1 `uc_seg_ok_share_vis` = 강세 구간 중 걸음 상승 포착 ≥ 기준 칸의 (기준 − 0.2·|기준|) 인 비율 > majority_share(빈칸 4 · 7 · 13 값) · 알파 비열등(t > −2)은 계약 산출 필요 |
| 빈칸 6 · 10 빠른 급락 | 아니오 | 위기 성격 분류 없음 | 문헌 정의 사전 고정 전엔 기록만 |
| 빈칸 11 lag-1 | 아니오 | — | 오버레이 블록에만 lag-1 사본 측정(같은 걸음 · 시행 회계 +1) |
| 빈칸 15 방어 방향 | **이번에 엔진 지원** | `factors[].direction = defensive_only` · B7 슬리브 direction defensive | — |
| 빈칸 16 엔진 대비 · 시장 대비 | 일부 | d_dd(엔진 대비)만 · 시장 대비 결론 조건 없음 | 닫기 결론 문장에 dd_capture_median_vis ≤ 1 여부 함께 기록(판정 아님) |
| 빈칸 17 독립 엔진 | 아니오 | 풀에 기저 계열 표기 없음 | 풀 열 `base_family`(논문 엔진 신호 계열 · 등록부 기록) — blend 의 '두 엔진' 셈 |
| 빈칸 19 보유 겹침 | 아니오 | — | 걸음 기록에 부모 대비 보유 겹침(rf_sl_turnover_overlap 과 같은 식) |
| 빈칸 20 위기 성격 · 22 비학습 대리 | 아니오 | — | 기록 · 생성기 지침(g2 4단계) |
- 지금 사슬이 기계로 막는 것은 **S 개선 · 상승 포착 중앙값 하한 · 위기 포착 중앙값 비악화** 셋뿐이다. 헌장 실패 형태 8개 중 '현금 기계'만 부분적으로 실렸다.
- 구현 위치(제안): `rc_p4_visible_metrics` 가 이미 τ_D 로 자른 카드(`card$crises` · `card$bull_phases` · `card$stats`)를 받는다 — 거기서 위기 · 강세 표를 걸음 지표로 남기고, `rc_p4_step_decide` 가 부모 산출 지표(`.rcp4_artifacts_of(parent)`)와 위기 id 로 짝지어 N1 · N2 · N3 을 계산 · `RC_P4_METRICS` 에 열 추가 · 필수 지표에 N1 · N2 추가(현금 기계 · 한 번의 행운). 시험: 합성 카드 2개(강세 구간 하나를 통째로 놓친 칸 → N1 기각 · 깊은 위기만 악화된 칸 → N2 기각 · 돌연변이 = 비율 판정 부등호 뒤집기).

## 3. 생성기 감사 · 성적표
- g1 결함: ① 헌장 §4 · §5 를 판정 기준으로 쓰라는 지시 없음(한 줄 정렬만) ② 되풀이 금지 장치 = "같은 블록에서 기각이 이어졌으면 다른 기전 고려" 한 줄 — 같은 (블록 · 축) 재제출을 막는 기계 · 지침 없음 ③ 과거 negative 조회 입력 없음 ④ 방향 필드(defensive · defensive_only) · 학습 처치의 시드 띠 · 비학습 대리 지침 없음 ⑤ 탐색 균형(미사용 블록) 지침 없음. 한 걸음 = 가설 하나 · 블록 하나는 지킨다(원장이 기계로도 막음).
- 성적표 `02_Infrastructure/programs/rx_generator_scorecard.R`(순수 함수 · 보는 창 열만 · 시험 창 열이 보이면 멈춤): 판마다 사슬 · 걸음 · 판정 · 채택률 · dS 평균/중앙 · **걸음당 개선(주 척도 = Σ 채택 dS_vis / 판정 걸음)** · 사슬 단위 표준오차 · 누적 dS · 누적 상승 포착 차 · 누적 위기 포착 차 · 새 블록 비율 · 되풀이 기각 · 최장 잡음 연속 · 기각 사유 빈도 · 블록별 표 · 비교 `rxg_scorecard_compare`(판정 문턱 없음 — 승격 규칙은 개정 사유 · 사전등록이 정한다).
- g2 초안 `<SCR>/generator_g2_draft/step.md` 변경 사유표:
| 변경 | 사유 |
|---|---|
| 진단 단계(§4 실패 형태 하나) | 채택 규칙이 못 보는 실패 형태를 처방 단계에서 막는다 |
| repeat_check 필드 | 같은 (블록 · 축) 재제출 = 잡음 연속의 주된 원인 |
| negative_lookup.md · negative_diff | 과거 negative 조회(사실 기록) 입력 |
| 헌장 정렬 6문항(빈칸 1 · 2 · 3 · 4 · 6 · 7 · 8 · 15 · 21 · 22 · 24) | 노출(β) 방어 귀속 0/14 · 0/8(P2R03 · P2R04)의 재발 방지 |
| scorecard.md · 미사용 블록 우선 | 탐색 균형 |
| allow_cash 안내 | 구성 층 현금(P-2) 이 생긴 뒤의 어휘 |
- 등록 절차(총괄): `rxg_revise(new_dir = 04_Research/programs/P4_ASSEMBLY/_generator/g2, reason, evidence = 결과 원장 round_id ≥ 1, philosophy_review = P4_generator_g2 리뷰 id)` — **결과 원장에 P4 근거 round 가 아직 없어 evidence 를 채울 수 없다**(첫 사슬 닫기 뒤 가능).

## 4. 수리 · 시험
- B7 부호 기준 불일치 수리(rf_sleeve.R · rf_cell_engine.R): 선정 IC × 등록부 방어 부호 · 처치 = direction defensive · select + ic_asof 거부 · 비 db 원천 + direction 거부 · 등록부 부재 = 멈춤. 운영 자료 판독(읽기 전용 · `<SCR>/b7_realdata_diag.R`): as-of 2005 · 2010 · 2015 · 2022-12 네 시점 모두 구판 1~3위 = 신판 1~3위(D42 · D35 · D36 · 방어 부호 +1) · 그 세 팩터의 as-of 정렬 부호는 2005-01~2022-12 216개월 내내 방어 부호와 같다 ⇒ **기존 B7 칸의 실제 처치는 뒤집히지 않았다(잠재 결함)**. 단 후보 78종 전체에서 as-of 정렬 부호 ≠ 방어 부호인 팩터-월 = 평균 25.9%(14.3~46.8%) — 방어 틸트를 기본(ic_asof)으로 얹으면 그만큼의 달에 공격 틸트가 된다 → 빈칸 15 모드가 필요한 실증.
- 빈칸 15 `defensive_only`(rf_cell_engine.R): 달마다 ic_asof · defensive 두 정렬 부호 비교 · 다르면 rank-Z 뒤 그 열 0 · 접근자 어휘 불변.
- E3 연결 P-1~P-3(rf_cell_engine.R catalog 가지 · rx_round.R): §6 참조.
- 시험(전부 통과 · 한 번에 하나씩): test_rf_cell_factor_direction 19/19 · test_rf_sleeve 59/59 · test_rf_selection_asof 71/71(+1 skip) · test_rx_round 43/43 · test_rx_generator_scorecard 21/21(신규) · test_scn_rx_construct_link 15/15(신규) · 회귀: test_rf_capcore 63/63 · test_rf_cell_engine_smoke 37/37 · test_sleeve_delivery 34/34 · test_rf_spec_axes 35/35.

## 5. 빠진 레버(우선순위 · 근거)
1. **낙폭 목적 구성 + 구성 층 현금** — E3 가 CDaR 구성(`rf_cdar_construct.R`)을 만들었고 셀 엔진 catalog 가지가 Σw ≤ 1 을 받게 됐지만 카탈로그 정규형(`method_registry.R` wrap_adapter target_sum = 1)이 현금을 지운다 → 패치 P-2b 가 열려야 걸을 수 있다. 근거: 헌장 빈칸 18(꾸준함 = 낙폭 경로) · 과거 방어 전부 노출 귀속(0/14 · 0/8) · lookup cdar 3건(실측 0).
2. **요인 위험모형 Σ** — P-1 로 걸을 수 있게 됨(Σ 를 쓰는 arm 한정 · ERC 등). lookup beta 30건(MARGINAL 8) — 정적 β 축소는 현금 기계로 대체(빈칸 8) → Σ 개선은 β 축소가 아니라 위기 상관 구조(dd_state 변형)를 겨냥해야 한다.
3. **as-of 국면 게이트 팔(조립 단위 장치 선택)** — 빈칸 23: 위기 유형 분류기가 보는 창 앞 위기로 반증 검사를 통과하기 전에는 금지 → 분류기 라운드(2계층 또는 P2)가 선행. lookup regime 30건(FAIL 2 · DISTILLED_NEG 1). ★`hypothesis_index.R lookup regime` 이 부가 출력에서 R 파싱 오류(`unexpected input in "LED_NEG %d · PASS %d ·"`)를 낸다 — 소유 밖 · 사실만.
4. **종목 β 꼬리 오버레이(노출이 아니라 보유 단위)** — 도구 상자에 없음. lookup cap 30건(DISTILLED_NEG 20 — 대부분 cap-tier 조건부). 빈칸 3 비대칭(하락 β < 상승 β)을 직접 겨냥하는 유일한 보유 단위 장치.
5. **종목별 상한** — 고정 축 '비중 상한 없음'(도훈 10-15) → 레버로 제시 금지(INV-7). 대신 빈칸 1 판정(한 종목 기여 < −10%)을 채택 규칙(N4)으로.
- 연결점(E3 중복 없음): Σ 공급자 = `weighting.sigma_provider` · 현금 = `weighting.allow_cash` · lean 창 = `weighting.lean_n_days` — 셀 서명은 weighting 전체를 직렬화하므로(`rf_spec_sig.R:99`) 새 키가 자동으로 다른 칸이 된다(패치 불요).

## 6. E3 연결 P-1 · P-2 · P-3 결과
| 건 | 구현 | 기본 결과 불변 | 새 선택지 시험 | 돌연변이 | 남은 것 |
|---|---|---|---|---|---|
| P-1 `sigma_provider` | sample(기본) · factor:ts:base/downside/dd_state → rfc_sigma_ctx(R 행 날짜 · 요인 수익 Date < d) · 가드: 요인 표 없음 = 멈춤 · pca 폴백 과반 = 멈춤 · 탐침 3신호일 Σ 표본판과 비중 같으면 = 처치 미전달 멈춤 | HEAD 엔진과 PORTFOLIO 비트 동일(lean:ivol · paper:ERCMRT2010 · 기본값 명시) | B1 ERC 요인 Σ 완주 · 비중 다름 / B2 lean:ivol(Σ 안 씀) 멈춤 / C1 PIT 결정일 뒤 요인 교란 → Σ 불변(dd_state) | E2 탐침 가드 삭제 → 조용히 완주 | lean 20종은 Σ 를 안 쓴다 → 요인 Σ 를 걸 수 있는 arm = paper:* · qepm:* · gen:* 중 ctx$Sigma 소비분 |
| P-2 `allow_cash` | 마무리 함수 `.rf_wt_finalize`(기본 = w / sum(w) 그대로) · opt-in 이면 Σw ≤ 1 유지 · > 1 멈춤 · 현금 든 신호일 0 이면 멈춤 | 동일 | D1 · D2(카탈로그 arm 은 정규형 Σw=1 → 멈춤) · D3 | E1 재정규화 삭제 → D1 깨짐 | **패치 P-2b(소유 밖)**: `method_registry.R:79` wrap_adapter 에 `target_sum` 인자(기본 1) 또는 `wrap_adapter_le`(같은 단언 · `sum(out) <= 1 + 1e-6`) · `weight_catalog.R` 이 arm 메타 `budget = "le"` 일 때 그 판으로 감싼다 · CDaR 어댑터는 `budget = if (isTRUE(ctx$allow_cash)) "le" else "eq"` · 엔진은 opt-in 칸에서 `ctx$allow_cash = TRUE` 를 싣는다(한 줄 추가 예정 · 지금은 넣지 않음 — 받는 쪽이 없으면 무의미) |
| P-3 `lean_n_days` | native(기본) · cell → ctx$n_days = 창 행 수 · 캐리어가 ctx$n_days 를 안 읽으면 멈춤 | 동일 | D4 멈춤 | E3 확인 삭제 → 조용히 완주 + **포트폴리오 native 와 비트 동일**(= 캐리어가 n_days 를 무시한다는 실증) | **패치 P-3b(소유 밖)**: `weight_catalog.R:245` `mx <- c(mx, if (!is.null(ctx$n_days) && "n_days" %in% names(formals(fn))) list(n_days = as.integer(ctx$n_days)))` — 기본 ctx 에 n_days 가 없으므로 기존 arm 불변 |
- 등록에 필요한 줄(총괄): `reinforce_program.json` B2 블록 어휘에 세 키 서술 · `weight_catalog.json` 변경 없음 · 시험 `08_Tests/scenarios/test_scn_rx_construct_link.R` · `08_Tests/programs/test_rx_generator_scorecard.R` 를 SUITES 에.

## 7. 그 밖 사실(범위 밖)
- `cluster_power` F3 실패(등록부 16 ↔ 상수 15): 16번째 범주 = `custom`(2건 · 측정된 전략 신호 자동 등록 · 경제 계열 아님). 패치: `contracts/cluster_power.R` 의 범주 셈에서 `custom` 제외(rx_round.R .rx_factor_vocab 와 같은 규칙) — 상수 15 유지.
- `rf_weight_arms_explore` E1 실패: shrinkage 계열이 이미 측정돼(원장 L1 essence 3 arm) 설계상 탐색 슬롯이 꺼진 것 — 코드 결함 아님 · 대상 코드 호출처 0(dead 목록).
- 시험 하나(`test_rx_round.R:11`)가 base R 경로 정규화 함수를 쓴다(기존 · 미수정).

## 8. 미확인
- 실제 사슬 원장 0개 — 성적표 · 채택 규칙 효과는 합성 원장으로만 시험.
- 요인 Σ 칸(B1)의 실제 진단 수치(요인 Σ 신호일 · pca 폴백 수)는 로그 판독만 했고 기록하지 않았다.
- P-2b · P-3b 적용 뒤 결과(소유 밖).
