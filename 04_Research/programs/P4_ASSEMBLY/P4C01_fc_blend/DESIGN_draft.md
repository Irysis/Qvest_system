# P4C01_fc_blend 설계 초안 — 블렌딩 사슬 1호(자체 사양 동일가중 카테고리 엔진 · 서로 다른 수익 원천 결합)

작성 2026-11-13 19:1x · **미등록 초안**(chain_spec.json 없음 — 사슬 틱 · 풀 판독이 이 폴더를 읽지 않는다). 상위 = P1R03 결론 범위 '원천 3개 이상 → 코어 v4 자체 사양 입구 → 상설 판 → 기저 풀 → P4 블렌딩 사슬'. 재개 저널 OP-20261113-P1R04 S6.

## 0. 등록 전제(모두 — 하나라도 없으면 등록하지 않는다)
1. 코어 v4 출시(RELEASES.json v4 항목 — 사슬 판 core_version v4 · 채택 규칙 판 p4_rules_v3).
2. 등급 v3.5 핀 교체 끝(도훈 GRADE-CR-NOTCH-BETA-SELECTION-20261113) — 사슬 핀이 새 등급 계약을 묶는다 · 닫기 재채점이 v3.5.
3. P1S03(자체 사양 상설 판) 시드 대조 · 통과 판정 + 철학 P2 판독 → 기저 풀 자격(`round.sh - p4-pool` · v4 관문: philosophy_unread · philosophy_hold · lowrisk_confirm_pending · own_spec_unresolved).
4. 원천 라운드 영수증: P1R03(원 세션 · LOWBETA release_decision) · P1R04(이 세션 · T1 저위험 엔진 hold).
5. P1R04 30칸 산출(원천 시행 — 코어 v4 는 원천 칸 산출이 하나라도 없거나 낡았는데 갈음이 없으면 사슬 등록을 거부한다 · D1 판 표식 뒤 재측정분).

## 1. 질문 · 가설
- 질문: 서로 다른 수익 원천의 P1 자격 엔진(밸류 · 성장 · 컨센서스 · 저β 묶음)을 한 포트폴리오로 섞으면, IS 종합점수 S(Calmar 6 : PORT_t 4)와 강세 참여 · 위기 하락노출이 단일 기저보다 나아지는가.
- 가설: 원천이 다른 엔진의 초과수익은 상관이 낮다 → 결합하면 같은 β 에서 선택 알파의 t 가 오르고(PORT_t), 원천별 낙폭 시점이 어긋나 낙폭이 얕아진다(Calmar). 반증: 채택 걸음 0(모든 blend 가 dS_vis < 0 또는 필수 지표 미달) · 또는 채택 걸음이 저β 상대를 섞어 β 만 낮춘 경우(N5 β 비대칭 · same_lineage_blend 표식)뿐.

## 2. 기저 규칙(기계 · 등록 전 고정 · IS 만 — 판단 T4 C-20261113-040)
- 후보 = 기저 풀 자격 행 중 원천 라운드 P1R03 의 동일가중(T0) 엔진(family_root FC:<카테고리> · FC:total — origin own_spec).
- 선택 = 격차 표(`rc_p4_gap` — IS 지표만 · 등급 계약 gv3_S)의 S_vis 최대 · 동률이면 port_t_vis 큰 쪽. Q 는 고르지 않는다(P1R03 IS 판정 파일의 test_hold 열람 고지 — 규칙이 그 열을 읽지 않는다).

## 3. 부품 · 블록
- 부품 = 같은 풀의 P1R03 자격 T0 엔진(P1S03 통과 · v4 관문 통과분 — 최대 8: 컨센서스 · 쏠림 · 방어 · 성장 · 유동성 · 위험 · 밸류 · 토탈). 저β 5(방어 · 위험 · 유동성 · 쏠림 · 토탈) = '저β 수익 엔진' 표기 · 방어 주장 없음(도훈 LOWBETA-ENGINES-BASE-USE-20261113 · CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113).
- T1(IC 가중) 엔진 = 사슬 2호부터(P1R04 결론 범위 · 판단 C-20261113-004).
- 걸음 = 가설 하나 · 블록 하나 · 칸 하나 — 사슬 목적(purpose)에 '블렌딩 사슬: blend 블록(기저 + 부품 1개 추가)부터'를 적어 생성기(g1 · 무인 틱 chain_tick)의 설계 입력으로 준다. 같은 계보 · 토탈 ⊃ 카테고리 블렌드 = 꼬리표 same_lineage_blend(거부 아님 · 닫기 결론에 '한 원천의 결합 가중').

## 4. 채택 규칙(p4_rules_v3 · IS 만 · 숫자 = 정본 참조)
- dS_vis ≥ `04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps`(0.02 — 파일럿 P4C90 와 같은 규칙 · 잡음 수준 개선은 채택하지 않는다 · 11-14 정정: 초안의 '≥ 0' 은 근거 문서가 없었다) · uc_vis ≥ `06_Registry/behavior_card.json::uc_floor` · d_dd_capture_median_vis ≤ 0 · uc_seg_ok_share_vis > `behavior_card.json::majority_share` · deep_crisis_nonworse_share_vis > majority_share · beta_asym_ok_vis ≥ 1(N5 — blend · 노출 층 걸음 · 판단 C-20261113-011 · 격리 R6).

## 5. 예산(근거 문구 = 사슬 판 budget.*_source)
- max_steps 20: `programs/trial_budget.R rc 0.8` — K 50 → 요구 t 2.52 · K 100 → 2.62. 시행 집합 = 원천 45(P1R03 15 + P1R04 30 — 코어 v4 원천 시행 · 판단 C-038) + 기저 1 + 걸음 ≤ 20 ≈ 66 → 요구 t ≈ 2.55. 걸음을 늘려도 요구 t 증가가 완만해 시행이 아니라 생성 비용 · 시간이 상한을 정한다.
- noise_k 2: 연속 2 걸음 '잡음 이내'면 닫기 — P2 R7 선례(lean-loop 예산 · 목표 축 판독).

## 6. 닫기
- 최종 후보 = 마지막 채택 걸음(final_rule last_accepted) · 원천 시행 포함 선택 현실 점검 재채점(등급 v3.5 · --regrade-write) · A 면 후보 관문.
- 결론: 엔진 대비 · 시장 대비(빈칸 16) · 원천 셈 두 판(이름 5 · 측정 4) · same_lineage 여부 · 채택 걸음이 노출 방어로 수렴했는지(철학 P2).

## 7. 결론 범위에 승계할 줄(P1R03 · P1R04 · P1S03)
- 소형주 착시(유동성 구간 귀속) · 시가총액 짝 선택 알파 미측정 · 희소 구성원 쏠림(P2 가 유효 구성원 수 대조).
- 강세 구간별 참여 기록(대형주 주도 강세 구간 포함 — 판정은 중앙값 · 도훈 CHARTER-GAP-BULL-PARTICIPATION-UNIT = 현행 유지).
- 위기 하락노출 = 시장 대비 귀속 전 원값 — 방어 근거 아님 · '방어' 표기는 시가총액 × β 무작위 대조 포트폴리오 통과 ∧ 최대낙폭 뚜렷이 작을 때만.
- 팩터 방향 불일치 구성원(V23 · C08 · CR05)이 든 카테고리 = 등록부 방향 결과 · 등록부 수정 뒤 새 엔진.

## 8. 감독 · 등록
- 사슬 판 초안 = `tools/init_p4c01.R`(기저 선택 기록 base_selection.json 포함 · `--dry-run` = 후보 표만). 11-14: 후보 0(P1S03 미등록)이라 중단 확인.
- 철학 P1 + 판단 T1(사슬 판 초안 뒤 동시) → `round.sh <사슬> p4-check` → `p4-register --p1 <id> --t1 <id>` → `p4-base-measure` → 무인 틱(걸음 측정 · 판정 · 다음 걸음) · 닫기는 감독 아래.
- 순서(11-14 원 세션 · 도훈 D2 채택 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114): D2 판 표식 → P1R04 측정 → P1S03 등록 · 측정(시드 대조 → 통과) → 영수증(P1R04 · P1S03) → 이 사슬 판 초안 · 감독 · 등록.
