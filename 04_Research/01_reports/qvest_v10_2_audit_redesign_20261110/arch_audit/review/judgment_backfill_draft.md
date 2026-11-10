# 판단 원장 따라잡기 초안 — 2026-11-06 12:47 뒤 미기록 판단 (검토용 · 원장 미기록)

- 작성: 2026-11-10 · Superfan v10.2 개정 작업(구현 담당) · **원장에 쓰지 않았다** — Q(도훈 검토 뒤)가 아래 명령을 골라 실행한다.
- 출처: `06_Registry/decision_register.json`(opened/decided ≥ 11-06) · `02_Infrastructure/docs/CHANGELOG_constitution.md`(v10.2 · 보강 절) · `git log --since=2026-11-06T12:47`(88건) · 설계 `04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md` §6 · §6-1.
- 원장 마지막 기록: 판단 `J-20261106-005`(11-06 12:47 · GPU 순서) · 응답 11-06 14:55. 그 뒤 기록 0.
- 정보 경계: 이 초안에는 2023-01 이후 성과 수치를 싣지 않았다(등급 v3.3 · OOS 관문 결정의 근거란에 있는 시험 창 · 롤링 통과율 수치는 옮기지 않았다).
- 체계 조항 = `00_Lawbook/specs/q_autonomy_decision_framework.md` 절 번호.

## writer 형식과 한계

```bash
PY=.venv_qvest_ml/Scripts/python.exe
L="$PY -X utf8 02_Infrastructure/programs/q_judgment_ledger.py"
$L record --op <OP-…> --kind <round_selection|candidate_selection|design|verdict|escalation|no_escalation|stop_continue|harness_change|priority|ops|other> \
   --summary "…" --rationale "…" [--ref "…" …] [--evidence 경로 …] [--alt "…" …] [--expect "…"] [--confidence 0.x] [--supersedes J-…]
```

- writer 에는 **`--at` 이 없다** — id · 시각은 기록하는 순간(11-10 이후)으로 찍힌다. 그래서 요지 첫머리에 `[소급 MM-DD HH:MM]` 을 붙였다(원 시각 = 결정 기록부 decided_at 또는 커밋 시각). 순서를 보존하려면 아래 순서대로 실행한다.
- `--op` 를 모르는 항목은 비웠다(세션 재개 저널 `06_Registry/session_resume.json` 에 해당 OP 가 있으면 채운다).
- 도훈 결정 항목은 'Q 의 판단' 쪽(상신 여부 · 권고 · 집행)을 기록한다 — 결정 자체는 결정 기록부가 정본이다.
- ★표 = 소급 T4 대상(등급 · 판정 규칙 변경 — 규약 §13-1 '수혜 기록을 미리 보지 않았는가').

## 요약 (24건)

| # | 원 시각 | 종류 | 요지 | 근거(결정 · 커밋) |
|---|---|---|---|---|
| 1 | 11-06 14:31 | escalation | KQ150 출범 전 소급 명부 — BOOK_0001 재측정 여부 상신 | KQ150-PRELAUNCH-NO-BOOK0001-REMEASURE-20261106 · 4b32772c3 |
| 2 | 11-08 16:56 | harness_change | 환경 최신화 R 4.6.2 · Py 3.15.2 + P2R05 환경 핀만 재고정 | 40232a68f · 3f6d3d50f |
| 3 | 11-08 23:49 | harness_change | PerformanceAnalytics 2.1.0 → 2.0.8 고정(측정 정의 변경 회피) · P2R05 재핀 | 1d2abf6bd |
| 4 | 11-09 07:34 | escalation | 재무 v2 전환 전 등급 처리 — '기록 후 인용 시 재측정' 상신 | FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109 · 9d8de7b2b |
| 5 | 11-09 11:40 | ops | 재무 원천 v2 전환 실행 · 팩터 DB 전체 재빌드 착수 | FUND-V2-SWITCH-EXECUTED-20261109 · 5ce28d308 |
| 6 | 11-09 12:32 | design | 충실구현 롱숏 다리 결합 = 논문식(bhr) 선택지 | REPLICATION-LS-PAPER-BHR-20261109 · 6c990e7f9 |
| 7 | 11-09 15:08 | harness_change ★ | 등급 v3.3 팩터 조정 알파 노치(구현 · 비활성) | GRADE-V33-FACTOR-ALPHA-NOTCH-20261109 · b6e800c5b |
| 8 | 11-09 15:52 | harness_change ★ | A 의 OOS 관문 교체(시험 창 Calmar vs 같은 창 KOSPI200) | GRADE-V33-OOS-TEST-WINDOW-CALMAR-20261109 · d2984e7e6 |
| 9 | 11-09 16:16 | harness_change | 결합용 팩터 뷰 + 접근자 direction 인자(C13 해석 확장) | FACTOR-COMBINABLE-VIEW-20261109 · 7cd973003 |
| 10 | 11-09 17:49 | harness_change | 팩터 방향 · 저장 규약 수리(등록부 저장값 기준 · 일간 as-of · XF) | FACTOR-DIRECTION-STORAGE-REPAIR-20261109 · 6ec99a015 · ae82871fe · 37b586749 |
| 11 | 11-09 21:00 | design | 등록부 방향 두 필드(C안 — 기대수익 + 방어) | FACTOR-DIRECTION-TWO-VIEWS-20261109 · 357cedcc4 |
| 12 | 11-10 05:10 | ops ★ | 등급 v3.3 발효 · 저장 등급 재채점 | 63a4433b3 |
| 13 | 11-10 08:00 | stop_continue | 재무 v2 재측정(현 축 A 3칸) 착수 → 중지(DNN 메모리 실패 · 도훈 "DNN은 스탑해") · 재개 = 총부채 수리 뒤 | 177697060 |
| 14 | 11-10 10:13 | harness_change | v10.2 사다리 루프 채택 · 1계층 일하는 순서 개정 | 98ddbcbf1 · OP-20261110-V102-LADDER |
| 15 | 11-10 10:13 | priority | P2R05 를 등록본 보존 채 뒤로 미룸(측정 시작 때 재핀) · 코어 출시 · P1 상설 자격 먼저 | 설계 README §6(결정 아님 · Q 진행) |
| 16 | 11-10 10:11 | escalation | DSR 관문 형태 상신 — (나) 권고 | DSR-GATE-FORM-20261110 |
| 17 | 11-10 10:11 | escalation | 등급 v3.3 노치 as-of · 규칙 변경 절차 상신(열림) | GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110 |
| 18 | 11-10 11:00 | other | 기준 사다리 상정 철회 — 요구 오독 정정 | LADDER-REFERENCE-ASSEMBLY-20261110 |
| 19 | 11-10 11:36 | harness_change ★ | 등급 v3.4 — 스윕 선정 A 관문 = 선택 현실 점검 · DSR · PBO 진단 | 5b42d80f4 |
| 20 | 11-10 11:40 | harness_change | 팩터 DB 총부채(TotalDebt) 0 수리 · 27팩터 전 기간 재계산 | 201ccc26d · FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110(결정 기록부에 항목 없음 — 판 표식 원장에만) |
| 21 | 11-10 11:51 | harness_change | 팩터 DB 판 표식 원장 + A 자격 상시 보류 factor_db_stale | e96f334ba |
| 22 | 11-10 12:10 | design | P4 골격 = B 방향(엔진 우선) · 강화 사슬 p4_chain 구축 | P4-SKELETON-REVIEW-20261018 · 838f7147a |
| 23 | 11-10 12:18 · 12:21 | escalation | 선택 현실 점검 보정값(PBO 역할 · 유의수준) 상신 — 기본값 근거 첨부 | SELECTION-RC-CALIBRATION-20261110 · SELECTION-RC-ALPHA-20261110 |
| 24 | 11-10 11:00 | escalation | 비밀 값 교체 시점 상신 → 추후 교체 | SECRETS-ROTATION-DEFER-20261110 |

선택(작은 하네스 변경 — 기록 여부는 Q 판단): 11-07 bare bash → `qv_bash()`(3d9bf3ad1) · 11-07 무인 레인 CLI 자동 업데이트(054cb2e85 · 도훈 지시) · 11-09 PSOCK 포트 예약 회피(6f0e260e3) · 11-09 한국 FF 팩터 수익 빌더(81dadf604 — 7번의 입력) · 11-10 전수점검 수리 ①②③(5c05969b8 · 72bae6a27 · 3b4651760) · 11-10 셀 엔진 팩터 방향 선택(98b679826).
경계 확인 필요: RL-STRATEGY-RESEARCH-20261106(12:38 결정 — 원장 마지막 기록 12:47 보다 앞이나 원장에 대응 판단이 있는지 `show` 로 확인) · SHARPE-STANDARD-RF-CD91-20261106(09:16).

## 명령 초안

```bash
# 1
$L record --kind escalation --summary "[소급 11-06 14:31] KQ150 출범(2015-07) 전 멤버십 = 출범 명부 소급 투영(C6) — BOOK_0001 이력 재측정 여부를 도훈에게 올림 → 재측정 안 함" \
  --rationale "BOOK 등록 전략의 사양 · 이력 변경은 상신 대상(체계 §5 BOOK 등록 · 등록 전략 사양 변경). 사실 진단(소급 투영)은 기록하고 재상정하지 않는다" \
  --ref "§5 BOOK 등록 · 사양 변경" --evidence 06_Registry/decision_register.json#KQ150-PRELAUNCH-NO-BOOK0001-REMEASURE-20261106 \
  --alt "Q 단독으로 BOOK_0001 재측정(§5 위반)" --expect "구 축 소비자(k200kq150_2005_v1 산출물 · smartbeta 추적) 재측정 지시 없음이 유지된다" --confidence 0.8

# 2
$L record --kind harness_change --summary "[소급 11-08 16:56] 환경 최신화(R 4.6.2 · Python 3.15.2 · 패키지 최신) 실행 + 진행 중 라운드 P2R05 는 결과 전에 환경 핀만 새 판으로 재고정(R2 supersede · 설계 불변)" \
  --rationale "구 판 유지 비용(보안 · 호환) 대비 회귀 0 실증(전체 회귀 3차) · 재고정은 결과 전이라 R2 위반 아님" \
  --ref "§6 하네스 변경(결과 동일성 검사와 함께)" --evidence 04_Research/01_reports/env_upgrade_20261109/PLAN.md --evidence 40232a68f --evidence 3f6d3d50f \
  --alt "P2R05 종료 뒤 최신화" --expect "P2R05 측정이 새 환경 핀으로 재현된다 · 회귀 시험 빨강 0" --confidence 0.7

# 3
$L record --kind harness_change --summary "[소급 11-08 23:49] PerformanceAnalytics 2.1.0 → 2.0.8 고정 — 2.1.0 이 Return.portfolio 날짜 · Sharpe/UpDownRatios 기본값을 바꿔 측정 정의가 조용히 달라짐" \
  --rationale "측정 신뢰 결함은 최우선(체계 §2-1) · 판 올림 전 옛/새 값 대조에서 차이 확인" \
  --ref "§2-1 측정 신뢰 결함" --evidence 1d2abf6bd --evidence 06_Registry/infra_holds.json \
  --alt "2.1.0 수용 + 등급 재채점" --expect "infra_currency 가 2.0.8 고정을 존중 · 저장 등급 재현 불변" --confidence 0.85

# 4
$L record --kind escalation --summary "[소급 11-09 07:34] 재무 원천 v2 전환 전 팩터 DB 위 등급의 처리 — '기록 후 인용 시 재측정'(자동 재채점 · 일괄 재측정 · epoch 상향 없음)으로 상신 · 도훈 A" \
  --rationale "측정 축 판(epoch)을 올릴지는 축 결정(§5) · 일괄 재측정은 비용 정책(§5) — Q 가 권고안을 붙여 올림" \
  --ref "§5 목표 · 고정 축" --ref "§5 비용 · 정책" --evidence 06_Registry/decision_register.json#FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109 \
  --alt "epoch 상향 + 전 등급 재측정" --alt "처리 없이 전환" --expect "재무 결함 위 등급이 인용될 때마다 v2 재측정 값만 쓰인다(인용 기록에 재측정 경로)" --confidence 0.75

# 5
$L record --kind ops --summary "[소급 11-09 11:40] 재무 원천 v2 전환 실행(fundamental_source.json active = v2) · 11:41 팩터 DB 전체 재빌드 착수 · 영향 목록 첨부" \
  --rationale "도훈 '보충 끝나면 전체 재빌드해줘' · 시작 조건(DART 보충 complete · 측정 중 라운드 없음 · 배리어 free · 날짜 순서 겹침 0) 확인 뒤 실행" \
  --ref "§6 측정 신뢰 결함 수리" --evidence 06_Registry/decision_register.json#FUND-V2-SWITCH-EXECUTED-20261109 --evidence 5ce28d308 --evidence 06_Registry/factor_db_vintage.json#FUND-V2-FULL-REBUILD-20261109 \
  --alt "측정 중 라운드 끝까지 대기" --expect "재빌드 '성공' · 판 표식 원장에 완료 시각 기록(23:31)" --confidence 0.8

# 6
$L record --kind design --summary "[소급 11-09 12:32] 충실구현 롱숏 다리 결합 선택지 ls_combination(daily | bhr) — 보유 기간 매수 후 보유 차를 보고하는 논문은 논문식(bhr)" \
  --rationale "충실구현 = 논문 그대로(CLAUDE.md 축) · 하네스 매일 결합이 숏 1종목 창에서 논문식과 크게 갈림을 F-Score 분석에서 실증 · 기본 daily 로 구판 비트 동일" \
  --ref "§3 충실도(원문 정식화)" --evidence 06_Registry/decision_register.json#REPLICATION-LS-PAPER-BHR-20261109 --evidence 6c990e7f9 \
  --alt "매일 결합 유지" --expect "bhr 논문의 재현 성과가 논문 보고값 쪽으로 이동 · daily 경로 결과 불변" --confidence 0.7

# 7 ★소급 T4
$L record --kind harness_change --summary "[소급 11-09 15:08] 등급 v3.3 팩터 조정 알파 노치(FF3 · Carhart4 · FF5 · FF6 NW-t 최솟값 · C→B 2.0 · B→A 2.95 · CR 약함 제외) 구현(비활성 → 11-10 발효)" \
  --rationale "도훈 '통계적 유의성이 확인되면 높은 등급을 부여할 수 있게 등급체계 수정' · 숫자는 기존 tier_graduation 정본 재사용(새 숫자 없음)" \
  --ref "§5 목표 · 고정 축(등급 체계 = 도훈 결정)" --evidence 06_Registry/decision_register.json#GRADE-V33-FACTOR-ALPHA-NOTCH-20261109 --evidence b6e800c5b --evidence 06_Registry/grade_v3.json \
  --alt "파마-맥베스 진단만(등급 무관)" --expect "FF 요인 구성이 as-of 임이 재검으로 확인된다(열린 결정 GRADE-V33-NOTCH-ASOF…)" --confidence 0.6

# 8 ★소급 T4 — 근거란의 수혜 기록 노출이 열린 결정의 대상
$L record --kind harness_change --summary "[소급 11-09 15:52] A 의 OOS 관문 교체 — 롤링 36개월 통과율 → '시험 창 위기 방어 약함 아님 ∧ 시험 창 Calmar ≥ 같은 창 KOSPI200 Calmar' · 롤링은 진단" \
  --rationale "도훈 '롤링 36개월 통과율 기준은 너무 빡센 기준인가?' → 롤링 창 대부분이 τ_D 이전 달을 담아 시험 창을 재지 못함을 실측 → 대안 교체(도훈 결정)" \
  --ref "§5 목표 · 고정 축" --evidence 06_Registry/decision_register.json#GRADE-V33-OOS-TEST-WINDOW-CALMAR-20261109 --evidence d2984e7e6 \
  --alt "롤링 통과율 유지" --alt "롤링 창을 시험 창 안으로만" --expect "규칙 변경 절차 결정(GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110)에서 이 결정의 근거란이 수혜 기록을 미리 본 사례로 판정된다 — 절차 명문화 뒤 재검" --confidence 0.5

# 9
$L record --kind harness_change --summary "[소급 11-09 16:16] 결합용 팩터 뷰(월간 저장형 · 증분 자동 갱신) + 접근자 direction = ic_asof | registry(C13 해석 확장 — 등록부 선언 방향 정렬 허용 · 수동 반전 금지 유지)" \
  --rationale "도훈 '모두 선형/비선형 결합 가능한 형태로 적재되는가' → 실측(별칭 · 고상관 쌍 · 왜도) → 도훈 만들기 결정" \
  --ref "§6 검사 보강 · 하네스 변경" --evidence 06_Registry/decision_register.json#FACTOR-COMBINABLE-VIEW-20261109 --evidence 7cd973003 \
  --alt "호출자마다 즉석 정렬" --expect "결합용 뷰 직접 읽기는 상설 입구가 탐지한다(e96f334ba)" --confidence 0.7

# 10
$L record --kind harness_change --summary "[소급 11-09 17:49] 팩터 방향 · 저장 규약 수리 — 등록부 방향 = 저장값 기준(71개 변경) · 일간 접근자 날마다 as-of 부호 · XF 채움 변환 · XF 계열 정의 + 영향 13팩터 전 기간 재계산" \
  --rationale "방향 불일치 조사 중 측정 신뢰 결함 발견(체계 §2-1) — 코드 감사 표 · 상설 검사와 함께 수리" \
  --ref "§2-1 측정 신뢰 결함" --evidence 06_Registry/decision_register.json#FACTOR-DIRECTION-STORAGE-REPAIR-20261109 --evidence 06_Registry/factor_direction_audit.json --evidence 6ec99a015 --evidence ae82871fe \
  --alt "등록부만 고치고 재계산 없음" --expect "영향 칸 재측정 전 인용 0(판 표식 원장 FACTOR-DIRECTION-STORAGE-REPAIR-20261109 범위 = 전체)" --confidence 0.75

# 11
$L record --kind design --summary "[소급 11-09 21:00] 등록부 방향 두 필드(C안) — direction = 기대수익 방향(문헌) + direction_defensive(위험 · 유동성 계열 · 위기 하락 노출↓ 쪽 높게)" \
  --rationale "등록부 이론 방향 30개가 문헌 · 정의 문구와 어긋남(Q 감사) · 수익 방향과 방어 방향이 다른 팩터를 한 필드로 못 담음 — 도훈 C안" \
  --ref "§3 충실도" --evidence 06_Registry/decision_register.json#FACTOR-DIRECTION-TWO-VIEWS-20261109 --evidence 357cedcc4 \
  --alt "A안(기대수익 방향만)" --alt "B안(방어 방향만)" --expect "셀 엔진 factors[].direction = defensive 가 방어 방향이 있는 팩터에서만 받아진다(rx_validate)" --confidence 0.7

# 12 ★소급 T4
$L record --kind ops --summary "[소급 11-10 05:10] 등급 v3.3 발효(알파 노치 + A 의 OOS 관문 교체) · 저장 등급 3,148기록 재채점" \
  --rationale "도훈 결정 2건(7 · 8) 집행 · 저장분은 판 표식으로 재채점" \
  --ref "§6 결정 집행" --evidence 63a4433b3 --evidence 06_Registry/grade_v3.json \
  --alt "다음 측정부터만 적용(재채점 없음)" --expect "재채점 결과 A 가 된 기록은 재무 v1 위 측정이면 인용 보류(FUND-V2-PRIOR-GRADES ③)" --confidence 0.6

# 13
$L record --kind stop_continue --summary "[소급 11-10 08:00] 재무 v2 재측정(등급 v3.3 현 축 A 3칸) 착수 → 중지 — DNN 메모리 실패 · 도훈 'DNN은 스탑해' · 재개 = 팩터 DB 총부채 수리 뒤" \
  --rationale "총부채 0 결함이 남은 팩터 DB 위 재측정은 다시 낡음(측정 신뢰 결함 우선 · §2-1)" \
  --ref "§2-1" --evidence 177697060 \
  --alt "메모리 상한 조정 후 즉시 재측정" --expect "총부채 수리(11-10 11:26) 뒤 재측정이 열린다 · 그때까지 그 3칸 인용 보류" --confidence 0.7

# 14
$L record --op OP-20261110-V102-LADDER --kind harness_change --summary "[소급 11-10 10:13] Qvest v10.2 사다리 루프 채택 — 기준점부터 · 새 계보 · 시행은 예산 · 상설 판 · 막지 않는다 · 닫으면 남긴다(결과 원장) · 루프가 고치는 것은 생성기뿐" \
  --rationale "전수점검: A 부재 원인 = 한 계보에 갇힌 생성 · 시행 소진 · 기준점 부재 · 정지(23일 0라운드) — 검증을 더하지 않고 순서를 바꾼다(도훈 '한계없이 고민하고 결론')" \
  --ref "§2 선택 순서" --ref "§6 하네스 변경" --evidence 04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md --evidence 98ddbcbf1 --evidence 322d05514 \
  --alt "v10.01 루프 유지 + 검증 보강" --expect "4주 안 닫힌 라운드 · 사슬이 결과 원장에 쌓인다(정지 재발 없음)" --confidence 0.6

# 15
$L record --op OP-20261110-V102-LADDER --kind priority --summary "[소급 11-10 10:13] P2R05 를 등록본 보존 채 뒤로 미룸(측정 시작 때 재핀) — 코어 v1 출시 · P1 상설 자격을 먼저 연다" \
  --rationale "등록만 된 P2R05 가 코어 출시 · P1 상설 자격 · RL 탐침 · P4 판단 · 파일 50개 수리를 '종료 뒤'로 묶었다(설계 README §1 · 원칙 '막지 않는다') — 결정이 아니라 Q 진행(§6)" \
  --ref "§2-2 막힌 선행 조건" --ref "§6" --evidence 04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md#6 \
  --alt "P2R05 종료까지 대기" --alt "P2R05 철회" --expect "P1S01 등록 · 측정이 P2R05 종료 전에 시작된다 · P2R05 재개 때 재핀만으로 측정 가능" --supersedes J-20261106-005 --confidence 0.7
#   (--supersedes 는 GPU 순서 'P2R05 먼저' 판단을 대체한다고 볼 때만 — 검토 필요)

# 16
$L record --kind escalation --summary "[소급 11-10 10:11] DSR 관문 형태 상신 — (가) 유지 (나) 진단으로 내리고 후보 역할 제한 + 재표집 검정 (다) 논문 정의로 교정 · Q 권고 (나) · 앞으로만 적용 → 도훈 (나)" \
  --rationale "현행 DSR 이 계보 누적 칸 수를 독립 시행으로 세고 분산을 가정값으로 두어 관문이 부적합 · 등급 관문 변경 = 도훈 권한(§5)" \
  --ref "§5 목표 · 고정 축" --evidence 06_Registry/decision_register.json#DSR-GATE-FORM-20261110 --evidence 04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md#8 \
  --alt "(가)" --alt "(다)" --expect "소급 승격 0 · 앞으로 등록되는 계보부터 선택 현실 점검 적용" --confidence 0.7

# 17
$L record --kind escalation --summary "[소급 11-10 10:11] 등급 v3.3 — FF 요인 구성 as-of 여부 · 규칙 변경 때 수혜 기록을 미리 보지 않는 절차를 상신(열림) · 결정 전 기본값 = 현 축 A 3기록 인용 보류" \
  --rationale "전수점검 PIT 레인: 요인 구성 미래참조 의심 · 11-09 OOS 관문 결정 근거란에 수혜 기록 이름이 있었다(G1 · L2) — 등급 규칙 · PIT 판단은 §5" \
  --ref "§5" --evidence 06_Registry/decision_register.json#GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110 \
  --alt "노치 즉시 비활성" --expect "요인 as-of 재검 결과와 변경 절차 명문화가 결정된다 · 그 전 A 3기록 인용 0" --confidence 0.7

# 18
$L record --kind other --summary "[소급 11-10 11:00] 기준 사다리(BOOK_0001 조리법을 현 축 부품으로 재측정) 상정 철회 — 도훈 요구의 오독 정정: 요구 = 레인이 찾은 알파 기저에서 강화 프로세스가 스스로 BOOK_0001급을 찾게" \
  --rationale "도훈 11-10 정정 발언 · 첫 판 §3 은 11-06 'BOOK_0001 재측정은 하지마'와도 가까웠다" \
  --ref "§1 판단의 원천(도훈 지시)" --evidence 06_Registry/decision_register.json#LADDER-REFERENCE-ASSEMBLY-20261110 \
  --alt "기준 사다리 유지 + 사슬 병행" --expect "설계 §3 이 '레인 기저 → 강화 사슬'로 바뀌고 기준 사다리 측정 0" --confidence 0.85
#   교훈 후보: 요구 해석이 갈릴 때 '조리법 재현'과 '능력 구축'을 구분해 되묻는다

# 19 ★소급 T4
$L record --kind harness_change --summary "[소급 11-10 11:36] 등급 v3.4 구현 — 스윕형 선정의 A 관문 = 선택 현실 점검(실제 시행 집합 재표집 다중 검정 · 통계량 = PORT_t) · 미제출 스윕 = 종전 DSR(경과) · DSR · PBO 진단 · 채점식 v3.3 그대로" \
  --rationale "DSR-GATE-FORM (나) 집행 · 수치는 grade_v3.json::selection_bias(근거 *_source)" \
  --ref "§6 결정 집행" --evidence 5b42d80f4 --evidence 02_Infrastructure/contracts/selection_reality_check.R --evidence 02_Infrastructure/programs/selection_regrade.R \
  --alt "DSR 식만 교정" --expect "소급 승격 0 · 재채점은 수혜 기록 표식과 함께" --confidence 0.65

# 20
$L record --kind harness_change --summary "[소급 11-10 11:40] 팩터 DB 총부채(TotalDebt) 0 수리 — 사채 포함 차입금 · 둘 다 결측 = NA · 27팩터 전 기간 재계산('성공' 11:15 · 이번 달 11:26)" \
  --rationale "2015~ 총부채 0 행이 DART 값을 덮어 부채 · EV 계열이 죽어 있었다(측정 신뢰 결함 §2-1)" \
  --ref "§2-1" --evidence 201ccc26d --evidence .cache/scheduler_logs/factor_subset_repair_20261110_090109.json --evidence 06_Registry/factor_db_vintage.json#FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110 \
  --alt "결함 팩터 사용 금지 목록만" --expect "판 표식 원장 범위 팩터의 수리 전 측정은 '낡음'으로 A 관문 · 기저 풀에서 빠진다" --confidence 0.8
#   참고: 이 결정 id 는 결정 기록부에 항목이 없다(판 표식 원장 · 요약 파일에만) — 결정 기록부에 둘지 Q 판단

# 21
$L record --kind harness_change --summary "[소급 11-10 11:51] 팩터 DB 판 표식 — 수리 원장 06_Registry/factor_db_vintage.json + 계약 factor_db_vintage.R · A 자격 상시 보류 factor_db_stale · 기저 풀 · 상설 입구 표식" \
  --rationale "수리 전 측정이 표식 없이 소비되는 경로 차단(체계 §2-1) · 원장은 추가 전용" \
  --ref "§2-1" --evidence e96f334ba --evidence 02_Infrastructure/contracts/factor_db_vintage.R \
  --alt "수리마다 영향 칸 수동 목록" --expect "수리 뒤 원장 한 줄 누락은 구성요소 감시 factor_db_vintage 가 잡는다(11-10 감시 확장)" --confidence 0.75

# 22
$L record --kind design --summary "[소급 11-10 12:10] P4 조립 골격 = B 방향(엔진 우선) — 골격을 P0 지도 한 칸에 고정하지 않고, 레인 엔진 풀의 기저 위에 강화 사슬(p4_chain)이 한 걸음씩 얹는다 · 생성기 판 관리" \
  --rationale "10-15 골격의 근거 셋이 바뀜(철학 P4 C-20261018-072 · 판단 T1 C-20261018-056) · 도훈 B 결정 · 사슬형(가설 하나 · 칸 하나 · 블록 하나)" \
  --ref "§2-3" --ref "§3" --evidence 06_Registry/decision_register.json#P4-SKELETON-REVIEW-20261018 --evidence 838f7147a --evidence 04_Research/programs/_lib/round_core/README.md \
  --alt "E2 DNN × C4 저변동 골격 유지" --expect "기저 풀 자격 엔진 ≥ 1 이 생기면 사슬 1호 등록(설계 §4 순서 3)" --confidence 0.65

# 23
$L record --kind escalation --summary "[소급 11-10 11:35~12:21] 선택 현실 점검 보정값 상신 — PBO 역할 · 유의수준 · Q 가 근거를 붙여 기본값을 넣고 확정은 도훈에게 → PBO = 진단 유지 · alpha = 0.05" \
  --rationale "등급 문턱 재보정 = 도훈 권한(CLAUDE.md 등급 절 · §5) · 0.5 는 닮은 변형 집합에서 관문이 서지 않음" \
  --ref "§5" --evidence 06_Registry/decision_register.json#SELECTION-RC-CALIBRATION-20261110 --evidence 06_Registry/decision_register.json#SELECTION-RC-ALPHA-20261110 \
  --alt "alpha 0.5(종전 DSR 수준)" --alt "PBO 관문화" --expect "grade_v3.json::selection_bias 값 불변" --confidence 0.8

# 24
$L record --kind escalation --summary "[소급 11-10 11:00] 비밀 값 교체 시점 상신(평문 백업 1 · git 추적 설정 키 1 · 점검 중 출력 3) → 추후 교체 · 교체 전 그 값을 출력 · 커밋 · 전송에 싣지 않음" \
  --rationale "외부 서비스 자격 = 비용 · 정책(§5)" --ref "§5 비용 · 정책" --evidence 06_Registry/decision_register.json#SECRETS-ROTATION-DEFER-20261110 \
  --alt "즉시 교체" --expect "교체 결정 전 새 노출 0" --confidence 0.8
```

## 기록 뒤 할 일(제안)

- 7 · 8 · 12 · 19(★)를 범위로 판단 Superfan **T4**(규약 §13-1 — 수혜 기록을 미리 보지 않았는가)를 한 번 띄운다. 결정 `GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110` 의 재료가 된다.
- 나머지는 다음 T3 범위(미검토 판단 10건마다 규칙에 걸린다).
