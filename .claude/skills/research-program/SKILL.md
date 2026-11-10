---
name: research-program
description: v10.2 1계층 리서치 운영 절차(사다리 루프 — 기준점 · 새 계보 · 상설 판 · 사슬형 처방 · 결과 원장) — 목표 역산형 3엔진(수익 · 방어 · 구성) 리서치를 프로그램 단위로 돌린다. 등록부(06_Registry/research_programs.json) 상태 확인 → 선행 조건(측정 계약 MC1~MC8) 진척 → 프로그램 라운드(사전등록 → 측정 → 행동 카드 → 판정 → 보고) → 논문 재료 · 메커니즘 지도 유지. 구 고정 격자 강화 러너(reinforce_auto_parallel)를 대체한다(2026-10-13 퇴역). 사용 시점 — /qvest 에서 1계층을 고를 때, '리서치 진행', '프로그램 라운드', '실현 가능성 지도', '방어 엔진', '처방 루프', '행동 카드'를 말할 때.
---

# 1계층 리서치 운영 (v10.01 · 2026-10-13 도훈 지시 · v10.2 사다리 루프 2026-11-10)

**설계 정본** = `04_Research/01_reports/l1_prescription_redesign_20261013/README.md`(결정 D1~D16 · 대안 설계 · 발송 규칙).
**철학**: 남들 다 깨질 때 덜 잃고(위기 하락 포착), 강세장을 충분히 따라가(상승 포착 ≥ 0.55), 그 비대칭으로 복리를 지킨다.
철학을 숫자로 쓰면 **비대칭(볼록성)이 필요조건**이다 — 정적 노출 축소만으로는 달성할 수 없다(행동 카드 검사 D 가 증명).
비대칭의 원천은 셋뿐: ① 알파 ② 시변 노출(현금) ③ 방어적 보유. 리서치는 이 셋을 엔진으로 확보하고 결합한다.

## 0. 시작할 때 (매 세션)

```bash
Rscript -e "source('02_Infrastructure/programs/program_registry.R'); writeLines(pr_status_lines())"
```
- 측정 계약 몇 개가 끝났는지, 프로그램마다 상태 · 재료 수 · 라운드 수가 나온다.
- **blocked** 프로그램은 선행 조건(MC*)이 끝나야 열린다. 선행 조건 작업도 '라운드를 여는 일'이다(인프라 작업이지만 등록부에 계상된다).

### 운영 모델 (2026-10-15 도훈 지시 — "오케스트레이터인 네가 운용하고 스스로 개선 · 나는 결정만")
- **Q 가 다음 라운드를 스스로 설계한다**: 라운드가 닫히면 결과 · 목표 격차(병목 지표 — 예: 급락기 MDD · Calmar 격차) · 증분 알파를 읽고 다음 유의미한 라운드를 설계 → 사전등록(격리 교차 점검) → 측정 → 판정 → 보고(시각 보고 + 다음 리서치 브리핑 · qvest-telegram §0.7)까지 묻지 않고 진행한다. 프로세스 결함 · 빠진 지표도 Q 가 고친다.
- **사전등록에 후보와 제외 사유를 남긴다**: 카탈로그 · 문헌 후보군 중 무엇을 왜 골랐고 무엇을 왜 뺐는지(이미 시험함 · 입력 미비 · 원리 중복 · 시행 수 예산) — 선택 근거가 '세션 판단'으로만 남지 않게.
- **도훈에게 올리는 것만**: 목표 · 고정 축 변경 · BOOK 등록 · 사양 변경 · 비용/정책 · `dohoon_decision` · 사전등록 규율 예외. 선택지 + 권고로 결정 기록부(`dr_open`)에 올리고 보고의 '결정 대기'에 적는다.
- τ_D 규율은 그대로다 — Q 는 시험 창을 본 상태이므로 선택 · 판정 규칙은 보는 창 지표로만 쓰고 그 노출을 사전등록 `exposures` 에 적는다.

### 라운드 = 세션 (2026-10-20 도훈 결정 L1-SPEED-PLAN-20261020 · 발효 = P2R05 종료 뒤 첫 라운드)
- 라운드 하나는 새 세션 하나에서 돈다.
  - 왜: 한 세션을 7일 이어 쓰면 호출마다 맥락 48만~74만 토큰을 다시 읽는다. 이것이 라운드 토큰의 가장 큰 몫이었다.
  - 라운드를 닫을 때 재개 저널(`session_resume.py`)과 다음 설계 입력(병목 지표 · 실패 지도 · 죽은 구성 · 재료 큐)을 남긴다.
  - 다음 라운드는 새 세션으로 연다. 사용자 턴이면 바로 시작하고, 자동 이벤트 턴이면 카드로 제안한다.
  - 세션을 닫을 때 판단 Superfan T3 를 실제로 돌린다.
- **독립 프로그램 라운드 동시 운영**(L1-SPEED-LEVERS-20261020): 서로의 결과에 기대지 않는 프로그램의 라운드만 별도 세션으로 겹친다.
  - 전제: 등록부 · 원장 · 저널 쓰기 잠금 배포(WP3) 뒤. GPU 는 임대 규칙을 따른다.

### 작업 연속성 — 세션 재개 저널 (2026-10-15 도훈 지시)
- 여러 단계 작업(라운드 · 측정 파이프라인 · 계약 수리)을 시작하면 `session_resume.py begin`(단계 · 먼저 읽을 것 · 다음 할 일), 단계가 바뀔 때마다 `step`, 다음 할 일이 바뀌면 `next`, 분리 실행을 띄우면 `bg`(로그 · 센티널), 도훈 결정 대기는 `decide`, 끝나면 `done`.
- **다음 할 일은 다음 세션이 그대로 실행할 수 있게** 쓴다(명령 · 파일 · 확인할 센티널). 세션이 갑자기 끊겨도 부팅 `Resume:` 줄과 `/qvest` ⓪ 재개가 여기서 이어 간다.
- 저널에 안 적은 진행 상태도 부팅이 등록부에서 '등록됐지만 끝나지 않은 라운드'로 따로 보여 준다(자동 신호).

### 판단 기록 · Superfan 감사 (2026-10-15 도훈 지시 — "Q 의 모든 판단을 모니터링해서 검증 · Q 와 논쟁 · 병목이 아니라 Q 가 제대로 기능하게")
- **판단 기록**: 자율 판단 체계가 다스리는 판단(라운드 선택 · 후보 선정과 제외 · 설계 · 판정 해석 · 상신 여부 · 중단과 계속 · 하네스 변경 · 우선순위 · 운영)마다
  `python -X utf8 02_Infrastructure/programs/q_judgment_ledger.py record --op OP-… --kind … --summary … --rationale … --ref "§…" --evidence … --alt … --expect … --confidence …` 1건.
- **Superfan 스폰(백그라운드 · 기다리지 않는다)**: T1 라운드 선택 직후 · T2 판정 해석 직후 · T3 세션 마감 전(또는 미검토 판단 10건) · T4 큰 판단 전 임의.
  `Agent(subagent_type="superfan", run_in_background=true, prompt="트리거 T? · 범위 J-… · 세션 시작 시각 …")`.
- **응답**: `challenge` 는 `respond --kind accept --change …` 또는 `--kind rebut`(근거) · `stop` 은 그 결과를 쓰기 전에 해소(수용 · 철회 · 상신) · 이견은 라운드 보고 1줄.
  부팅 `Resume:` 줄 꼬리(`Superfan: Q 응답 대기 n · Superfan 차례 m · 미검토 판단 k · 보류 요청 h`)가 할 일을 보여 준다. 규약 = `00_Lawbook/specs/superfan_protocol.md`.
- **철학 Superfan(10-16 도훈 지시 — 과제마다 투자철학 정렬)**: 라운드마다 P1(설계안이 정해진 뒤 · 등록 전) · P2(판정 직후 · 방향 판정) · 후보 확정 때 P3(전기간 의견서 — 도훈 confirm 첨부) · 라운드 3개마다 P4. `superfan-philosophy`(백그라운드). 기준 = `00_Lawbook/specs/investment_philosophy_charter.md`. 라운드 보고에 '철학: <방향 판정> · 실패 형태 <…>' 1줄.
- **구성요소 Superfan(10-16 — 1 구성요소 = 1 전담 팬)**: `Resume:` 꼬리에 `Superfan 감시: 이상 n` 이 보이면 `python -X utf8 02_Infrastructure/programs/superfan_watch.py show --open` → 실패 이상의 구성요소마다 `superfan-component`(백그라운드 · `구성요소: <id>`) → 진단 반영 · 수리 · `ack`. 라운드 파이프라인을 돌리는 동안에는 세션이 직접 지켜본다.
- 세션 시작 뒤 추가된 에이전트 정의는 그 세션 목록에 없다 — 범용 에이전트에 '정의 파일을 먼저 읽고 따르라' + opus · max 로 띄운다.

## 0-1. v10.2 사다리 루프 — 일하는 순서 (2026-11-10 도훈 지시 · 설계 `04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md`)

A 가 안 나온 이유는 검증 부족이 아니라 ① 한 계보에 갇힌 생성 ② 시행 소진 ③ 기준점 부재 ④ 정지였다(설계 §1). 검증 장치는 그대로 두고 순서를 바꾼다.

1. **기준점부터(양성 대조)** — 통과시켜 본 적 없는 관문의 '불통과'는 정보가 아니다.
   - A 경로 소방 훈련: 합성 양성 1건이 측정 → 등급 → A 자격 관문 → Judge 요청 → BOOK 후보 보고(건식)까지 통과하는지. 관문 코드가 바뀔 때마다 다시.
2. **새 계보를 만든다** — 기저는 충실구현 레인이 찾는다(도훈 11-10): 레인 엔진 → 상설 판(P1 자격 · 표준 롱온리 구성으로 지금의 팩터 DB 위에서 새로 잰다) → 기저 풀 → 강화 사슬(P4).
   기저 풀 자격 = 상설 통과 또는 권위 등급 B 이상 · 팩터 DB 수리 뒤 측정분(`round.sh - p4-pool` 이 자격과 제외 사유를 낸다). 자체 엔진 레인(팩터 가족 단위)은 설계만 있고 코드는 없다.
   새 엔진 없이 한 엔진 위에 방어 장치 라운드를 더 붙이지 않는다(P2R03 14/14 · P2R04 8/8 반증 — 시행만 태운다).
3. **시행은 예산이다** — 스윕형 라운드(여러 칸 중 고르는 라운드)는 등록 전에 변형 수 상한의 근거를 계산해 사전등록에 싣는다:
   ```bash
   Rscript 02_Infrastructure/programs/trial_budget.R rc <rho> [<기대 t>]   # ★등급 v3.4 관문(선택 현실 점검) 기준 — 닮은 변형의 상관 rho(입력) × 변형 수별 요구 t · 최대 변형 수
   #   과거 시행 집합이 있으면 tb_rc_from_trials(dirs, 후보) = 계약 그대로 환산 독립 시행 수 · 요구 t
   Rscript 02_Infrastructure/programs/trial_budget.R 300        # (진단) 관측 개월 수 → 시행 수별 DSR 최소 활성 SR · 근사 t — v3.4 에서 DSR 은 관문이 아니다
   ```
   **강화 사슬(P4 · round_core `p4_chain`)** — 사슬 판을 한 번 등록하고(기저 · 보는 창 채택 규칙 · 예산 · 생성기 판) 걸음을 흘린다. 한 걸음 = 가설 하나 → 칸 하나 → 블록 유형 하나:
   ```bash
   R=04_Research/programs/_lib/round_core/round.sh
   bash $R - p4-pool                          # 기저 풀(자격 · 제외 사유) — 자격 0 이면 상설 판 측정이 먼저다
   bash $R <사슬 폴더> p4-check · p4-register --p1 <철학 P1 id> --t1 <판단 T1 id>   # 사슬 판 검사(시험 창 지표 · 출처 없는 숫자 · 낡은 생성기 · 채택 규칙 판 v2 필수 지표 N1 · N2) → 등록(영수증 없으면 거부)
   bash $R <사슬 폴더> p4-base-measure          # 기준 칸(k = 0) — 걸음 전 필수 · 배리어 · 데이터 신선도(낡음 = 종료 6) · 판 표식 · 점유(다른 측정 중 = 종료 7)
   bash $R <사슬 폴더> p4-workdir --out <사슬 밖 빈 폴더>   # 생성기 작업 디렉터리(네 파일만) — 처방 에이전트는 사슬 폴더가 아니라 여기서 일한다
   bash $R <사슬 폴더> p4-step-open --k 1 --hypothesis "…" --mechanism "…" --block <유형> --cell <칸 사양> --parent 0 --generator g1 [--probe-ref <round_id>#<n>]
   bash $R <사슬 폴더> p4-step-measure --k 1    # 정본 셀 워커(스윕 회계 · 등재 · L-code 끔) — 종료 0 측정 · 4 배리어 · 6 데이터 낡음 · 7 점유 · 1 실패
   bash $R <사슬 폴더> p4-step-decide --k 1     # 측정 기록의 산출 → 보는 창 지표 → 등록된 규칙 → 채택 | 기각(--artifacts 는 측정 기록과 같은지 대조할 때만)
   bash $R <사슬 폴더> p4-step-abandon --k 1 --reason "…"   # 측정 실패 2회 이상인 걸음만 — 기각(산출 없음)으로 닫아 사슬이 멈추지 않게
   bash $R <사슬 폴더> p4-close --note "…" --probe "…" --probe "…" --regrade-write --p2 <철학 P2 id> --t2 <판단 T2 id>   # 닫기는 한 번뿐 — --regrade-write(운영) | --regrade-dry-run(시험) 필수
   #   결과 원장 + 최종 후보 선택 현실 점검 재채점(등급 v3.4) → A 면 후보 관문 · 아니면 앞선 요청 거두기 · 결론에 엔진 대비 · 시장 대비(빈칸 16)
   #   원장 손상 = 멈춘다 → 사람이 확인 뒤 격리: bash $R <사슬 폴더> p4-quarantine --line <n> --reason "…" · bash $R - outcomes-quarantine --line <n> --reason "…"
   bash $R - p4-generator-review              # 블록 유형별 채택률 · 개선 폭 · 기각 사유 → 생성기 새 판의 재료(rxg_revise)
   ```
   사슬도 '사슬이라 면제'에 기대지 않는다 — 끝나면 기저와 모든 걸음 칸을 시행 집합으로 최종 후보를 다시 채점한다. 스윕형 라운드의 최종 후보도 같다(`programs/selection_regrade.R`).
   **무인 틱(11-10 CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110)** — `02_Infrastructure/ops/chain_tick.sh`(예약 작업 Qvest_StandingBoard 매시 37분 · 상설 판 다음)가 **이미 등록된 열린 사슬**을 사람 없이 잇는다: 기준 칸 측정 → 열린 걸음 측정 → 측정된 걸음 판정(등록된 규칙) → 다음 걸음 설계(생성기 LLM 1회 = `ops/chain_gen_run.sh` · 청정 레인 · 읽기 3도구 · LLM 전 읽기 가드 탐침) → 산출 검사(`programs/chain_tick.R compile` — τ_D · rx_validate · 한 블록 차이) → `p4-step-open`. 다음 행동은 계획기(`chain_tick.R plan`)가 원장을 매 행동 뒤 다시 읽어 정한다 · 틱당 측정 1 · 생성 1 · 측정 못 할 때(배리어 · 데이터 낡음)는 새 걸음을 열지 않는다. **감독 아래 남는 것**(틱이 부르지 않는다 — 허용 목록 밖): 사슬 판 등록 · 닫기(`p4-close` — 닫을 때가 되면 '닫기 대기' prep_send 1통) · 생성기 새 판 · 격리. 생성 연속 실패 2회(`RC_STANDING_MAX_FAILS`) = 그 사슬 생성 차단(풀기 `bash 02_Infrastructure/ops/chain_tick.sh --reset <chain_id>`) · 사용 한도 = 다음 날까지 생성만 멈춤. ★손으로 걸음을 돌리는 동안 `<사슬>/tick_hold` 를 둔다(틱이 그 사슬을 건너뛴다 — 없으면 틱이 같은 k 를 먼저 열 수 있다). 끄기 = `06_Registry/chain_tick.json` `"enabled": false` · 한 번만 = `QVEST_CHAIN_TICK=off` · 보기 = `bash 02_Infrastructure/ops/chain_tick.sh --dry-run`. 로그 `.cache/scheduler_logs/chain_tick_*.log` · 생성기 `chain_gen_*.log` · 장부 `.cache/chain_tick/` · 작업 폴더 `04_Research/programs/P4_ASSEMBLY/_lanes/<chain_id>/`.
4. **의식은 규칙에, 속도는 후보에** — 규칙은 프로그램에 한 번 등록(상설 판 — round_core README '상설 판')하고 후보를 흘린다. P1 상설 자격(P1S01)부터 출시한다.
5. **막지 않는다** — 환경 핀(운영 파일 · 패키지)은 측정을 시작할 때 건다. 등록만 되고 측정을 못 시작한 라운드가 다른 프로그램 · 코어 출시 · 결함 수리를 묶고 있으면, 등록본을 보존한 채 그 라운드를 뒤로 미루고 묶인 것부터 푼다(재개 때 재핀 — 사전등록 내용은 바꾸지 않는다).
6. **닫으면 남긴다** — 종료는 다음 탐침 2개 이상(없으면 사유) · 교훈 · 목표 축 판독을 결과 원장(`06_Registry/round_outcomes.jsonl` — 2026-11-10 현재 미생성 · 첫 `round.sh close` 가 만든다)에 쓴다. 글에 정보 경계 뒤 날짜가 있으면 닫히지 않는다.
   ```bash
   bash 04_Research/programs/_lib/round_core/round.sh <round_dir> close --note "<해석>" --probe "<다음 탐침 1>" --probe "<다음 탐침 2>" [--lesson "<교훈>"] [--r7 noise|signal] --p2 <id> --t2 <id>
   Rscript -e 'source("04_Research/programs/_lib/round_core/v1/load.R"); writeLines(rc_outcomes_md(rc_outcomes_path(), "<프로그램 id>"))'   # 다음 설계의 출발점
   ```
   다음 라운드 설계는 이 출력(열린 탐침 · 교훈 · 연속 '잡음 이내' 횟수)에서 출발하고, 이어받는 탐침은 `rc_probe_consume("<round_id>#<번호>", "<새 round_id>", rc_outcomes_path())` 로 표시한다.

7. **판 표식** — 팩터 DB 수리 전에 잰 측정은 재측정 전 A 자격 · 기저 자격이 없다(`contracts/factor_db_vintage.R` · 원장 `06_Registry/factor_db_vintage.json`). 팩터 DB 를 수리하면 그 원장에 한 줄 더한다.
   팩터를 쓸 때는 방향을 고른다 — 칸 사양 `factors[].direction` = `ic_asof`(기본) · `registry`(고정 방향 · 시점 간 학습) · `defensive`(방어 틸트) · 결합 · ML 입력은 결합용 뷰 `fc_load_month`.

**재귀 개선의 경계**: 루프가 고쳐 쓰는 것은 생성기(처방 프롬프트 = `06_Registry/rx_generator.json` 의 판 · 도구 상자 · 탐색 순서)뿐이다. 판정 규칙을 고칠 일이 생기면 새 판으로 다시 등록한다 — 루프가 자기 채점 기준을 고치지 않는다.
**철학 · 초과달성**: 최종 후보 선택 규칙에 헌장의 실패 형태(현금 기계 · 노출 방어 · 집중 · 추첨 행운)를 기계 조건으로 싣고(값은 정본 설정 참조), 순위는 점 추정이 아니라 여유(시드 띠 아래 끝 · 판정 여유)로 매긴다.

## 1. 프로그램 (정본 = 등록부)

| id | 이름 | 단계 | 하는 일 |
|---|---|---|---|
| P0_FRONTIER | 실현 가능성 지도 | 1 | 문헌 표준의 단순 부품 × 기존 수익 엔진으로 목표 영역에 닿는지 먼저 잰다. 닿지 않으면 탐색을 늘리지 않고 도훈 안건 |
| P1_RETURN | 수익 엔진 | 2 | 알파 · 상승 포착 |
| P2_DEFENSE | 방어 엔진 | 2 | 위기 하락 포착 축소 — **여러 수익 엔진에 걸쳐** 검증(위기 수 × 엔진 수) |
| P3_CONSTRUCTION | 구성 | 2 | 낙폭 제약 아래 복리 극대화(비중 · 집중 · 회전 · 용량) |
| P4_ASSEMBLY | 조립 · 처방 루프 | 3 | P0 골격의 빈칸을 처방 루프가 채운다 |

상태 어휘: blocked · idle · ready · active · paused · done · killed. 쓰기는 `program_registry.R` 함수만(직접 편집 금지 — 검사 · 원자적 교체).

## 2. 라운드 한 번 (모든 프로그램 공통)

### 2-0. 공통 판정 코어 round_core v1 (2026-10-20 · L1-SPEED-PLAN-20261020 · 발효 = P2R05 종료 뒤 첫 라운드)

라운드는 더 이상 register.R · evaluate.R · precheck.R · measure.sh · notify.R · close_round.R 을 새로 쓰지 않는다. 라운드가 쓰는 것은 셋뿐이다.
- `round_spec.json`: 칸 · 엔진 · 규칙 선언 · 선택 · 노출 · 결론 범위.
- `DESIGN.md`: 사고 기록 — 템플릿 `_lib/round_core/templates/`.
- 필요할 때만 `round_ext.R`: 같은 선언 형식의 고유 규칙 + 그 픽스처.

정본 · 사용법 = `04_Research/programs/_lib/round_core/README.md`.

- **규칙 단일 출처**
  - 규칙 선언 하나에서 사전등록 문장 · 판정 실행 · DESIGN 표를 생성한다. 문구 표류(P2R04 · P2R05 필수 지적 11/17)가 구조적으로 사라진다.
  - 수치 문턱은 `basis` 나 정본 `value_ref` 가 없으면 거부한다.
  - 미측정은 `na = fail | untested` 이고 통과로 접지 않는다.
  - 판정 규칙의 내용 · 수 · 설계 재량은 현행대로다(도훈 10-20).
- **실행기** `bash 04_Research/programs/_lib/round_core/round.sh <round_dir> <단계>`
  - 단계: check · draft · reviewed · register · measure · evaluate · report · close.
  - 핀은 한 함수로 대조한다.
  - 점검본 사본 대신 drafts.json 을 쓴다.
  - 칸 평가는 내용 주소 캐시를 쓴다(재측정 뒤 옛 평가 금지).
  - 측정 → 평가는 자동으로 이어진다.
  - 판정은 `results/verdict.json` 한 곳에 쓰고, 종료 기록과 보고를 여기서 생성한다.
- **점검 동시 실행**
  - 사양 초안(`round.sh draft` 가 만드는 `prereg_draft.md`)이 나오면 철학 P1 · 판단 T1 · 격리 교차 점검을 **동시에** 띄운다.
  - 점검자에게는 라운드 패키지(사양 · ext · 초안 md · 코어 판)만 준다. 코어 자체는 출시할 때 한 번 점검한다.
  - 점검 횟수는 §12 기본(전체 1회 + 변경분 1회)이다. 등록 조건은 P1 수령 ∧ 점검 ok 다.
- **P1 라운드**: `rc_init_p1` 이 표준 구성 칸 사양(P0R01 C0 선례 · 고정 축 정본 대조)과 골격을 만든다.
- **속도 규칙**: `_lib/round_core/PERFORMANCE.md` 를 따른다. 결과 동일 실증과 전후 시간 기록이 없는 최적화는 쓰지 않는다.
- **P2 · P3 판정 틀은 v1 에 붙었다**(10-20 WP1-b · main 6c37495f4).
  - 모듈: `v1/pair.R`(짝 평가 골격 · 위기 · β 짝 · 과반 · 샤딩) · `p2.R`(장치 × 엔진) · `p3.R`(구성 변형) · `rules_p2.R`(P2 규칙 종류).
  - P2R04 · P2R03 · P3R03 을 코어로 다시 판정한 결과가 저장본과 같다(`rejudge/RESULTS.json`). 쓰는 법 = round_core README.
  - ★예외 = P2R05: 등록 전에 라운드 전용 코드로 짜였고, 핀 51개 파일 무접촉 결정(L1-SPEED-PLAN)대로 현행 방식으로 끝낸다. 코어는 P2R05 다음 라운드부터 쓴다.
- **GPU 확보 = 임대**(10-20 WP3 배포 · `02_Infrastructure/ops/qv_lock.{R,py,sh}` 의 `gpu_lease_acquire` / `gpu_lease_release` · 상한 12h).
  - lane_hold · lane_pause · 외부 감시는 퇴역이다. 충실구현 레인은 슬롯(CPU 2 + GPU 1)이다.
  - 요청 상태는 `rf_replication_slots.py status` 로 본다.

**처방 루프 라운드 도구(v0 · 2026-10-13 S2 파일럿 · D7 별도 모듈)** — 에이전트(분석가 · 처방 담당 · 리뷰어)가 있는 라운드는 이 경로로:
- 진단 패킷 `contracts/diagnosis_packet.R::dp_build(dir)` — **보는 창(≤ τ_D)만으로 계산**(적재 단계 절단 · 검사 = τ_D 뒤 세계를 바꿔도 바이트 동일).
  행동 카드 · MC8 귀속 · 노출 분해(tilt_attribution 기계) · 위기별 종목/업종/크기 귀속 · 구성 프로필. 종목명은 싣지 않는다.
- 라운드 도구 `programs/rx_round.R` — 도구 상자(`rx_toolbox_md` · 수치 가림 · custom 팩터 제외) · 헌장(`rx_charter_md`) · 레인 준비(`rx_prepare_lane` —
  처방 입력 문서에 τ_D 뒤 날짜 · 등급 표기가 있으면 멈춤) · 처방 검증(`rx_validate` — **엔진 파서**로) · 사양 컴파일(`rx_compile_spec`).
- 에이전트 실행 `programs/rx_lane.sh <lane_dir>` — 무인 단일 진입(자동 기억 차단) + 청정 표식(R6 읽기 가드 · 작업 디렉터리 = `04_Research/programs/<프로그램>/<round>/lane_<역할>`) ·
  읽기 전용 · 산출 = 최종 응답. ★세션 서브에이전트는 쓰지 않는다(세션 기억 · 가드 밖 = τ_D 누출). 세션에서 띄울 때 인증 = 사용자 환경변수 토큰(기억 카드 참조).
- 반증 조건은 **기계 판정 형식**(패킷 필드 · 부등호 · 절대값 또는 기저 대비)으로 받아 R 이 판정한다. **최종 후보 선택 규칙도 R 이 기계 적용**하고(사전등록 문구에서 옮긴 상수는 문구 대조로 묶는다) 리뷰어는 확인 · 이견 기록만 한다. 첫 사례 = `04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/`(`evaluate.R`).
- 레인 재료는 **md 만** 넣는다 — 성과 키(calmar · cagr · mdd …)가 2종 이상 든 json/csv 는 청정 레인 내용 가드(R1_content)가 읽기를 막는다(사전등록도 md 안 json 블록으로). PDF 는 레인에서 못 읽는다 → `pdftotext` 로 만든 txt.
- 같은 판본 기저 대조(RX0): 데이터 판본이 기저 측정 뒤 바뀌었으면 기저를 같은 사양으로 다시 재 반증 · 선택의 기준으로 쓴다(처방 효과와 데이터 갱신 효과를 섞지 않는다 · 시행 수 무가산).
- **축 감사(측정 뒤 · 의무)**: 처방 칸의 실제 보유(04_holdings)가 롱온리 · ≤ `constraint_defaults.json::tier_soft_deployment.max_names` 인지 확인한다 — 파서 통과 ≠ 축 준수.
  위반 칸 = 측정 무효(미시험) · 등급 인용 금지(등급 파일은 손대지 않는다). 첫 사례 = P2R01 RX2 `turnover_cap`(최대 120종 · 검증기가 이제 거부).
- **반증 필드 설계**: 위기가 적으면(4개) '위기 중앙값'은 가운데 두 위기로만 정해진다 — 양 끝 위기만 바꾸는 처방은 못 본다. 위기별 개선 수 · 최악값 · CDaR 를 함께 등록한다(P2R01 교훈).
- **결합 규칙**(2026-10-18 · 철학 P4 C-20261018-073 보류 · 판단 T2 C-20261017-003): 장치마다 이긴 위기가 다르면(P2R03 D5 · D7 = 2008 · 2020 / P2R04 H2 · W2 = 2011 · 2021) 합치면 깊은 위기 과반이 기계적으로 나온다 — **위기별 승패 지도의 합집합으로 결합 · 선택 규칙을 짜지 않는다**. 결합은 위기 유형을 시작 시점 이전 정보(as-of)로 가르는 기전 · 새 사전등록 · 결합 칸 자체 판정 · 시행 수로만 하고, 결합 칸을 P4 · A · BOOK 로 올리기 전에 도훈 확인을 받는다.
- 알려진 경계: 헤드리스 레인은 CLAUDE.md · 자동 로드 규칙을 주입받는다(규칙에 시험 창 사건 언급이 있다) — 전략 수치는 아니며 사전학습 서사 지식과 같은 성격 → 시험 창 판정은 MC8 크기 짝과 함께 읽는다.

1. **사전등록**(R2) — 측정 **전에** 파일로: 가설 · 기대 방향(행동 카드 지표로) · 반증 조건 · 변형 목록(수 상한) · 최종 후보 선택 규칙(보는 창 정보만).
   `stage_artifacts/programs/<프로그램>/<round_id>/prereg.json`. 그리고 `pr_record_round(id, list(round_id=, prereg=<경로>))`.
   **등록 → 커밋 → 측정 기동** 순서다 — 등록본(두 사본) · 등록부 항목 · 등록 시점 핀 점검을 서술형 커밋으로 남긴 **뒤에** 측정을 띄운다
   ('결과 전 등록'을 git 이 증명한다 · 세션 중 자동 커밋이 결과와 한 묶음으로 쓸어 담지 않게 — 2026-10-17 판단 Superfan T3 C-20261017-003 · P3R03 c7166d2ca).
2. **측정** — 정본 계약만(`run_paper_replication` → essence). 손계산 · 재구성 금지(AX-008).
3. **행동 카드** — 측정 산출물마다(카드 + MC8 크기·노출 짝 대조 · 롱온리 처방 정의 · 디렉터리당 약 16초):
   ```r
   source("02_Infrastructure/contracts/matched_controls.R")
   raw  <- mc_load_raw(root, from = "<첫 집행일 − 1개월>")     # 디렉터리가 여럿이면 한 번만 읽는다
   card <- mc_card("<산출물 디렉터리>", root = root, raw = raw)
   mc_write(card, "<산출물 디렉터리>")                           # behavior_card.json(대조가 붙은 상위 판)
   ```
   방어 주장은 귀속 라벨(`card$controls$attribution` — 선택 방어 / 크기 방어 / 노출 방어)과 함께만 한다. 크기 방어 · 노출 방어를 '실력'으로 쓰지 않는다.
   판정은 같은 크기 분포 · 평균 노출로 무작위로 고른 포트폴리오 200개의 분위다(평균 비교는 운을 실력으로 센다 — 보고서 `l1_prescription_redesign_20261013/mc8_matched_controls/README.md`).
   처방 에이전트에게는 `attribution$visible` · `crises[window == "visible"]` 만 준다(τ_D). 롱숏 · 유니버스 미상 = 정의 밖(닫힘).
4. **판정** — 사전등록한 반증 조건으로. 결과를 본 뒤 기대를 고쳐 쓰지 않는다. `pr_record_round` 로 같은 round_id 에 결과를 덮어 쓴다(사전등록 경로는 바꿀 수 없다 — writer 가 거부).
5. **보고** — 리서치 1단위 = 텔레그램 1통:
   ```r
   source("02_Infrastructure/programs/program_report.R")
   prep_send(program = "방어 엔진", target = "<사람이 읽는 이름>",
             status = list(stage = "...", position = "...", previous = "..."),
             card = card, next_step = "...", artifact = "<산출물 디렉터리>", push = <판정 변화·실패·종료면 TRUE>)
   ```
6. **닫기 · 교훈** — `round.sh close`(§0-1 ⑥): 다음 탐침 ≥ 2 · 교훈 · 목표 축 판독을 결과 원장에 남긴다. 기전이 특정되는 실패만 L-code. 교훈에는 **τ_D(2022-12-31) 이전 수치만** 싣는다.

## 3. 정보 경계 (R4 · D6 — 절대)

- 분석가 · 처방 담당 · 팩터 정의자 · **리뷰어**는 **2022-12-31 까지**의 성과 · 위기만 본다. 최종 후보 선택 규칙 · 교훈 카드도 같다.
- 2023-01 이후(시험 창 — 2024~25 · 2026 두 번의 급락)는 등급 · 철학 감독관 · Judge · BOOK(사람 쪽 판정)에만 쓴다.
- 2026-06~07 KOSPI200 −40.9% 급락은 **실제 사건이다**(도훈 확인 — 데이터 의심 재상정 금지). 초대형주 주도라 방어 판정은 크기 짝 대조로(MC8 시운전: S1 · 2002.06975 B6_36 의 이 급락 방어는 무작위 크기 짝 분포 안 — 크기 효과).

## 4. 고정 축 (v10.01)

long-only · ≤25종 · **Σw ≤ 1(잔여 현금)** · **전 종목 + 위생 단계**(헌장 §11 `factor_z_standard.R`) · 비용(유동성 구간별 — D10) ·
**2000-01~** · **리밸런싱 ≥ 주간** · 종목별 상한 없음 · PIT C1~C15. 측정 계약 개정(MC1~MC5 · MC7 · MC8)이 끝나기 전의 새 축 측정은 판정에 쓰지 않는다.
등급 = **등급 v3**(2026-10-13 MC7 승격 · essence_score 가 산출): S = (Calmar/0.64)^0.6 × (PORT_t/2.95)^0.4 · B 경계 = S(같은 창 벤치 Calmar, PORT_t 2.0) · A 하한 · 위기 복원력 노치 · τ_D OOS. 구 5조건 판정 = `grade_v921`(진단).
**규칙 판 v3.1(10-13 도훈)**: 위기 = Lunde-Timmermann 20/20 첫 통과 구간(고점 대비 20% 하락 = 시작 · 저점 대비 20% 반등 = 끝 · CRISIS-DEF-LT2020) · CR '강함' 상향 노치 = MC8 선택(기전) 방어 동반 시만(GRADE-V3-CR-STRONG-SELECTION). 판이 다른 저장분은 `programs/grade_v3_backfill.R` 이 판 표식(`grade_v3.rules_version`)으로 다시 채점한다.
**규칙 판 v3.2(10-18 · 헌장 빈칸 9 A′ · CHARTER-GAPS-3)**: MC8 selection_defense 를 선택(노출 경로 고정 또는 노출 경로까지 맞춘 짝을 과반에서 이김) / 타이밍(경로 짝 미통과)으로 가른다 — 타이밍 방어는 증거 기록((a) 같은 β 현금 사본을 깊은 위기 · 빠른 급락 과반에서 이김 (b) 두 엔진 (c) 느린 약세 개선이 lag-1 에서도 유지)이 있을 때만 '강함' 상향. **방어 라운드의 평가는 장치가 (a)(b)(c)를 충족하면 `grade_v3.R::gv3_timing_evidence_add` 로 증거를 기록한다**(등록부 `06_Registry/timing_defense_evidence.json` · 셈 단위 = LT 위기 수 = unit 'lt' — 도훈 10-18 GRADE-V32-TIMING-EVENT-UNIT · 상태 일화 판은 보고 기록판).
**규칙 판 v3.3(11-10 발효)**: 팩터 조정 알파 노치(FF3 · Carhart4 · FF5 · FF6 알파 NW-t 최솟값) + A 의 OOS 관문 교체(시험 창 Calmar ≥ 같은 창 KOSPI200 Calmar ∧ 위기 복원력 약함 아님). 정의 정본 = `CLAUDE.md` 등급 절 · `contracts/grade_v3.R`.
사전등록 당시 정의로 판정해야 하는 라운드는 그 판의 설정 사본을 고정해 `dp_build(…, bcfg = <사본>)` 로 잰다(R2 — 위기 정의가 바뀌어도 반증 의미 불변 · 첫 사례 P2R01).

## 5. 논문 · 문헌 (자동 · 아침 체인)

`morning_run.sh`: [0/3] 수집 → [0.5/3] 트리아지 v5(엔진 분류) → [0.51] `program_paper_sync.R`(엔진별 재료 큐) →
[0.52] `paper_atlas_run.sh`(메커니즘 지도 · `QVEST_PAPER_ATLAS_ENABLE=1`일 때만).
- 지도 = `06_Registry/mechanism_atlas.jsonl`(첫 수록 전엔 파일 없음 · append-only · R 검증 통과분만 · 원문 위치 없는 수치 거부).
- 처방 담당은 처방 전에 지도에서 해당 엔진 · 기전의 기존 증거를 읽는다(시장 · 기간 · 위기 행동).
- 예약 작업의 켜짐 · 꺼짐은 문서에 적지 않는다 — 정본은 부팅 `Queue:` 줄(레인 슬롯 · 틱 나이)과 `scheduler_task_health`. 켜고 끄는 것은 도훈(시스템 설정).

## 6. 에이전트 (D12 — 정본 = `reinforce_auto_config.json::llm.lanes`)

판단(판독 · 분석 · 처방 · 리뷰 · 감사 · 감독 · Judge) = **Opus** · 명확한 사양 실행(코딩 · 분류 · 요약) = **Sonnet** · Fable 미사용.
지시가 완전히 명확하면 모델 없이 R/Python 으로 한다. 생성과 검증의 독립성 = 맥락 격리 + R 근거 재도출 + 기계 검사.

## 7. 하지 않는 것

- 등급(A)을 직접 최적화하지 않는다 — 행동 목표로 설계하고 등급은 보고 문턱.
- 위기 하나로 방어를 주장하지 않는다(CR '매번' = 둘 이상).
- 2023년 이후 성과를 보고 처방 · 선택 · 교훈을 고치지 않는다.
- 구 고정 격자 러너 · 블록 설계 레인을 되살리지 않는다(퇴역 — 롤백 태그 `pre-v10.01-prescription-20261013`).
