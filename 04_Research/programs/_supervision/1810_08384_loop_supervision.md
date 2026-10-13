# 감독 기록 — 1810.08384 「Portfolio Construction Matters」 충실구현 → 1계층 처방 루프 (2026-10-14 · v10.01)

> 감독 = Q(오케스트레이션). 각 에이전트 · 계약이 설계(설계 정본 `l1_prescription_redesign_20261013` §3.3 · §10.4 · lean-loop)대로 제 역할만 하는지 확인한다.
> 감독은 **과정**을 본다 — 결과를 원하는 쪽으로 몰지 않는다(R2 사전등록 · AX-008 계약 수치만 · τ_D 경계).

## 단계와 역할 (설계 기준)

| # | 단계 | 담당 | 설계상 역할 | 감독 확인 항목 |
|---|---|---|---|---|
| 1 | 요청 | `next_replication.R` | 큐 순서 그대로 1편 발행(고르지 않음) | 큐 상단 = 1810.08384 · dohoon_decision 아님 |
| 2 | 재구현 | 청정 레인 에이전트(opus/max) | 논문만 읽고 engine.R + FIDELITY.json 만 산출 · 성과 열람 차단 | 프롬프트 축 문구 정합 · 출처 기록 · 산출물 2개뿐 · 축(유니버스 = 계약 주입 · 시작일 리터럴 없음) |
| 3 | 사전검사 | `rf_preaudit.py`(기계) | 신고 구조(paper_steps · windows · constants · 공시 블록) 확인 | 지적 → 보정 1회 · 통과 |
| 4 | 측정 | `run_paper_replication`(계약) | 등급 v3.1 · 측정 축 epoch 기록 · 실효 시작 | 권위 기록만 인용 · epoch = all_hyg_2000_v1 |
| 5 | 충실도 감사 | 감사 레인(opus/xhigh) | 논문 ↔ 코드 대조 · 근거 재도출 | 판정(faithful/adapted/misdeclared) · 근거 실재 |
| 6 | 검증기 | `rf_replication_verify.R` | 행동 카드 · 재료 큐 · 보고 1통 | 재료가 어느 프로그램 큐로 갔나 |
| 7 | 처방 루프 | 분석가 → 처방 담당 → (사전등록) → 측정 → 리뷰어 | §3.3 · 보는 창(≤ 2022-12-31)만 | 레인 입력에 τ_D 뒤 수치 없음 · 반증 기계 판정 · 선택 규칙 사전등록 |

## 기록

### 1. 요청 — 정상
- 07:32 `next_replication.R` → `replication_request.json` pending(1810.08384 · 큐 상단 · 재정렬 없음).

### 2. 재구현 1차 — 중단 · 하네스 결함 1건 수리
- **이탈(하네스 쪽)**: 프롬프트의 하네스 공시 블록이 구 측정 축을 공시(H2 'KQ150 2010~' · H3 '2005~' · H8 '무필터') — 같은 프롬프트의 '축' 절(전 종목 + 위생 · 2000~)과 모순.
  구현자는 블록을 FIDELITY 에 그대로 옮기고 감사는 하네스 사실로 읽는다 → 신고 기록 오염 · 감사 오판 위험.
  원인 = 10-13 축 전환 때 이 문구가 코드가 아니라 설정(`06_Registry/rf_preaudit.json`)에 있어 빠졌다.
- **수리**: `rf_preaudit.py::harness_block` 이 활성 epoch 문장을 고르게 함(검사 H4~H7 · 54/0 · 돌연변이 검출 확인) — CHANGELOG 10-14 절.
- **1차 에이전트**: 수리 전에 이미 산출 없이 rc=1(시작 2.5분 · 전사가 07:36:14 도구 결과 뒤 끊김 · 원인 미상). 연구 실패 아님 → 요청 세션 처리(pending · 재시도 예산 미소모).
- **2차 실행**: 07:44 재시작 — 프롬프트 공시 블록 = `epoch=all_hyg_2000_v1` 확인.
  - 07:56 전사 점검: 읽기 = 허용 목록 안(factor-db-access.md · backtest_harness.R · run_paper_replication.R · replication_harness.R) · 가드 차단 0 · 성과 파일 열람 0.
    논문은 arXiv 원문 전문(read_paper)으로 읽었다 · 하네스 규약(다리 부호 · 신호일 · 유니버스 결합)을 코드에서 확인한 뒤 엔진 작성에 들어감(07:50~).

### (관련 결정) P0 = A안 — 사전등록 유지
- 도훈 'P0는 A안으로 가자'(10-14) → decision_register `P0R01-PREREG-KEEP-A`(resolved). Q 고지 기록: P3R01 E1 등급 기록 줄이 측정 로그(module_register)에서 Q 에게 노출 — 사전등록 개정이 없으므로 R2 영향 없음.
- 감독 규칙(이 루프 동안): 측정 로그 원문(`reinforce_auto_log.jsonl`)은 module_register 줄을 걸러서 본다(진행 중 라운드 칸의 등급 노출 차단).
