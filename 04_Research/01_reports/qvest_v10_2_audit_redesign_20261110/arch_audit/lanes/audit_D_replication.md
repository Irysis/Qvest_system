# 레인 D — 논문 충실구현(심층) 감사 · 2026-11-10

범위: 큐 논문 → 구현(에이전트 engine.R) → 측정 전 사전검사(rf_preaudit.py) · 6축 충실도 감사(rf_fidelity_fanout.sh → merge) · 재구현 1회 →
측정(run_paper_replication.R — 변형 전부 · 15bps · 측정 축 주입 · 다리 결합 · 레인 표준 구성) → 권위 등급(essence v3.4) → 행동 카드 →
A 자격 관문(§11) → judge_request.eligible/held → 재료 등록(L1 · 프로그램 재료 큐) → 보고.
근거 표기: [확인] = 코드 · 로그 · 산출물로 직접 확인 · [실측] = 이 감사가 재도출 · [미확인] = 확인 못 함.

## 1. 배선 지도 [확인]

```
예약 작업 Qvest_ReinforceAutoLoop(이 PC: Disabled · 한 번도 안 돎 267011 · 동작 = jobs\off\…cmd)
 └ reinforce_auto_tick.sh(증류 양보 · 리프레시 배리어) → rf_replication_auto.sh
    ├ 디스패처(RP_SLOT 없음): rf_replication_slots.py tick — claim 회수(owner_alive = pid + 시작 시각) · 논문 잠금 · GPU 인계함 · 발행(next_replication.R)
    │   → 슬롯 작업자 nohup 분리(cpu1 · cpu2 · gpu1) · 요약 06_Registry/replication_slots/_status.json(부팅 '틱' 줄이 읽음)
    └ 작업자: 재시도(PYRETRY) → 스킵 · 백오프 관문 → 청정 모드(rf_clean_lane.py) → 원문 축자본(rf_paper_text.py) → 에이전트(claude -p · engine.R + FIDELITY.json)
        → 사전검사(rf_preaudit.py · 기각 = 같은 논문 pending · 연쇄) → rp_verify → rf_replication_verify.R
            → 6축 감사(측정 앞) → reimplement(engine.rejected<N>.R · audit_retries+1) | audit_conflict(보류) | proceed | proceed_suspect
            → run_paper_replication(대표 변형 = chain/1) → variants/(sweep · n = 변형 수) → holdings_check · behavior_card
            → §11 A 관문(rf_a_eligibility) → judge_request.eligible.json | held.json
            → L1 소비 기록 · 프로그램 재료 큐(research_programs.json kind=engine) · 텔레그램(.v1001_report) → next_replication.R
 소비자: round_core standing.R(P1 상설 자격 — 미등록) · p4.R 기저 풀(rc_p4_base_pool) · factor_db_vintage.R(fdv_stale) · A 관문
```
문서와 코드의 차이: 지시서 · 일부 문서의 `02_Infrastructure/reinforcement/run_paper_replication.R` 는 없다 — 정본은 `02_Infrastructure/alpha_search/run_paper_replication.R`.
SKILL · 에이전트 문서의 현행 epoch 가 `all_hyg_2000_v1`(10-17 이전 값)이었다 → 수리.

## 2. 심층 질문

### Q1. 1차 통과율 [실측 · census_D.py]
대상 = 청정 레인 작업 디렉터리 21개(10-05 ~ 11-07 · `RP_AUTO_CLEAN_*`). 1회차 감사 원본 = `.clean_audit_src/r1/fidelity_audit.json`.

| 결과 | 편 | 비율 |
|---|---:|---:|
| 첫 제출 무기각(사전검사 · 감사 둘 다) | 0 | 0% |
| 사전검사 보정 1회 뒤 감사 1차 통과 | 2 (1908.01112 · 2412.12350) | 10% |
| 감사 재구현 1회 뒤 통과(adapted) | 9 | 43% |
| 최종 미통과(proceed_suspect 9 · 감사 상충 보류 1) | 10 | 48% |

- 감사 1회차 misdeclared 축 판정(20편): undeclared 13 · signal 13 · universe 5 · portfolio 5 · timing 3 · cost 1.
- 1회차 지적 115건 축 분포: signal 46 · undeclared 38 · portfolio 12 · timing 9 · universe 8 · cost 2.
- 10-17 근본 원인 보고(`first_pass_rejection_rootcause_20261017`) 뒤 배포된 레버(원문 축자본 · 6축 자가 감사 · 상수 원문 대조 P-검사 · 종목 수 키 n_long(10-20) ·
  등록부 방향 안내(11-10))의 효과는 **아직 측정되지 않았다** — 10-20 이후 새 첫 제출 6편(1109.3488 · 1309.7119 · 2106.06164 · 2601.04602 · 1603.00751 · 2604.16773 재발행)이
  전부 1회차 감사 기각이지만, 그중 방향 안내(11-10)는 6편 모두보다 늦다.

반복 사유 상위 5(1회차 원문 재독 · 근본 원인 보고와 교차):
1. **보충 · 방어 코드 미신고/오신고**(캐시 키 누락 상수 · NA 경로 · 그룹원 가드 · dropout · log 변환 · 음 고유값 절단) — undeclared 축 최다.
   레버: 사전검사가 이미 clip · NA · seed · fallback · 하한 · 최상위 상수를 기계로 본다. 남는 것은 **함수 안 리터럴 · 변환(log · clamp)** —
   사전검사 범주에 `transform_literal`(np.log · torch.clamp · eigvalsh(...).clamp 등 code_regex + changed 신고 어휘) 추가를 제안(등록부 `06_Registry/rf_preaudit.json` 은 총괄 소유).
2. **팩터 DB 대리 지표의 정의 · 방향 차이**(ic_sign 정렬이 학습/예측 패널마다 바뀜 · GR02 분모 |.| · dedup 군집 중복) — signal 축.
   11-10 등록부 방향 인자 안내로 방향 쪽은 수리됨. 정의 차이는 사전검사 `factor_ref` 가 등록부 정의를 FIDELITY.factor_mapping 에 요구 — 유지.
3. **하네스 · 축 사실 오해**(top_n 키 미판독 → 실현 = 신호 폭 10% · 일간→주간 접기 · 유니버스 신고) — portfolio · timing · universe. 10-20 수리(n_long · H10 공시).
4. **논문 방법 · 유니버스 누락 미신고**(HSI 48종 유니버스 · A.4 ML 필터 변형 · ρ 격자 · Variant II) — 모든 방법론 규칙(10-17) 이후에도 1309.7119 · 2601.04602 에서 재발.
   레버(정보 동등): 감사 축 지시의 '변형 열거' 기준을 구현자 프롬프트의 variants 절에 **같은 문장으로** 싣기(지금은 구현자 = focus 요약 · 감사자 = 축 프롬프트 전문).
5. **신고서 내부 모순**(self_audit '미명시 생략 0건' ↔ paper_steps note '미명시라 생략') — 결정론으로 잡힌다: paper_steps 중 status=omitted 이면서 note 에
   미명시 어휘가 있는데 omitted 목록 J-코드가 아닌 항목 = fail. 사전검사 P-검사 신설 제안(등록부 소유 밖 · 코드 rf_preaudit.py 는 패치 제안).
감사 기준을 낮추는 제안은 없다.

### Q2. 측정 재도출 [실측 · rederive_D*.R · 재측정 없음]
| 점검 | 롱숏 2412.12350(B · 11-06) | ML 1603.00751(B · RF · 11-06) | 롱온리 1908.01112(F · DL · 10-17) |
|---|---|---|---|
| 비용 15bps × Σ|Δw| | 비용일 322 = 리밸 다음 첫 보유일 322 · 함의 회전율/목표 비중 회전율 중앙 1.000 | 1.004 | 1.003 |
| 리밸 · 빈 달 | 월 322회 · 빈 달 0 | 107회 · 63거래일 간격(분기 보유) | 110회 · 분기 |
| 신호 → 집행 → 수익 | 신호 = 월말 · 집행 = 익월 첫 거래일 종가(close_t1) · 첫 수익일 = 다음 날(C2 · C5 통과) | 같음 | 같음 |
| 동전주 바닥 · 유동성(신호일 t−1) | 위반 0 / 25,760행 | 위반 0 | px<1,000 18행 · adv<2e8 26행 / 1,532행 (구 epoch all_hyg_2000_v1 — 바닥 없음 · adv 위반은 미해명) |
| 실효 시작(MC3 B) | 2000-01-31 = 창 기준 | 2000-03-31 | 2000-01-04 |
| 순수익 경로 CAGR · MDD | 0.1486/0.333 vs 권위 0.149/0.333 | 0.1945/0.588 vs 0.196/0.588 | 0.1175/0.7725 vs 0.116/0.772 |
| 변형 | 3/3 ok · 대표 = 권위 run · FIDELITY sha = 출처 기록 | 16/16 ok · 대표 고정 | 변형 없음 |
| 다리 결합 | daily(월 리밸 · bhr 대상 아님) | — | — |

조용한 실패 후보:
- **먼지 보유**: 1908.01112 보유 행 384/1,532(25%)가 |w| < 1e-10(최적화 잔차 1e-17) — 종목 수 진단(n 5~30 · 중앙 13)과 보유 대조가 부풀려진다. 수익 · 비용 영향은 0 수준.
  패치 제안(replication_harness.R — 측정 규약 변경이라 총괄 결정): 보유 기록 · 종목 수 진단에서 |w| < 1e-12 제외(수익 경로 불변).
- **turnover · n_holdings 열 NA**: 03_period_returns.csv 의 turnover 는 리밸일 외 NA · n_holdings 는 전부 NA(세 건 모두). 계약 CSV 소비자가 이 열을 읽으면 빈다. [미확인: 소비자 존재]
- **rebalance 표기**: 분기 보유 엔진도 auth.replication.rebalance.mode = monthly(하네스 실현 주기) — 보유 기간 신고와 어긋나 보일 수 있다(판정 영향 없음).
- 1908.01112 의 adv 위반 26행: 엔진 신호일이 집행 직전 거래일이 아닐 수 있음 · 또는 멤버십 미적용 — 구 epoch 이라 재측정 대상이므로 재측정 판에서 같은 대조를 다시 볼 것.

### Q3. 변형 회계 · 선택 현실 점검 배선
- 지금: 대표 = FIDELITY.headline_variant(측정 전 · 출처 기록 sha 로 고정 확인) → chain/1 권위. 나머지 = sweep · n = 변형 수 · 종전 DSR(v3.4 '점검 미제출 스윕 = 종전 DSR').
  비대표 A 는 §11 관문이 회계 요건(chain)으로 보류 — 발행 0.
- 빈 곳: 비대표 변형을 소비자(P1 상설 · P4 기저 · 2계층)가 '골라' 쓰면 그것이 선정인데 시행 집합(같은 논문의 변형 전부)이 어디에도 묶여 있지 않다.
- 제안(코드 = 레인 · 계약은 총괄 소유 그대로 호출):
  ① `rf_replication_verify.R::.v1001_measure_variants` 끝에서 `selection_regrade.R::sr_regrade(candidate = 각 비대표 ok 변형, trial_dirs = 대표 + 모든 ok 변형, write = FALSE)`
     를 진단으로 돌려 `<대표>/variants_selection_check.json` 에 후보별 조정 p · 관문 결과만 남긴다(권위 기록 무수정 · 등급 불변).
  ② 비대표를 소비하는 쪽(p4.R 기저 풀 · standing.R)은 그 파일이 있으면 `sr_regrade(write = TRUE)` 로 재채점한 뒤에만 받는다 — 시행 집합 = 위 파일의 trial_dirs.
  ③ 대표는 선정이 아니므로 점검 대상이 아니다(chain/1) — 단, 측정 뒤 대표를 바꾸는 경로는 지금 없다(바꾸면 그 판은 sweep).
  관문 계약(`selection_reality_check.R` · `grade_v3.R`)은 손대지 않는다.

### Q4. 기저 공급 병목 [실측 · pool_D.R — rc_p4_base_pool 읽기 전용]
| 사유 | 건 | 생기는 단계 |
|---|---:|---|
| factor_db_stale | 12/12 | 측정 시각(10-14 ~ 11-06) < 수리 완료(11-09 23:31 · 11-10 01:38 · 11:26) — 전부 재측정 대상 |
| not_qualified | 10 | 권위 등급 F(B 미만) — 측정 결과 |
| needs_long_leg | 9 | 롱숏(has_short TRUE) — 재료 등록 시 has_short · 롱 다리 변환 없음 |
| implementation_suspect · audit_not_passed | 4 · 4 | 감사 재구현 뒤에도 misdeclared(1810.08384 · 1801.01777 · 1603.00751 · 2604.16773 2판) |
| no_engine | 2 | 2412.12516 · 2411.13555 — 10-20 재발행(재구현 대기열)이 engine.R 을 engine.rejected2.R 로 옮겼고 GPU 인계함에서 대기 중 · 재료 항목은 옛 경로를 가리킨다 |
- 롱 다리 경로: P1 상설 자격(standing.R — 엔진 신호를 표준 롱온리 구성으로 다시 잼 · long_leg_window 검사)이 정본 경로다. **아직 등록 전(P1S01)** — 지금 롱숏 엔진을
  롱온리 25종으로 넘기는 실행 경로는 0.
- 재측정 목록 · 비용(로그 실측): 엔진 있는 10건 중 suspect 4건은 재측정해도 자격 0 → **실익 = 비의심 5건**(2202.10721 · 2601.10732 · 2411.08864 · 1908.01112 · 2412.12350).
  레인 검증기만 재실행은 편당 감사 재스폰(중앙 11.3분 LLM) + 측정(단일 7~15분 · 변형 3개 49분 · 16개 109분) → 5건 ≈ 2~3시간(CPU 1슬롯).
  그러나 4건이 F 이고 1건이 롱숏 B 라 레인 재측정만으로는 기저 풀 자격이 여전히 0 → **P1 상설 자격 측정(롱온리 25 · 현 팩터 DB)이 공급의 실질 경로**.

### Q5. 판 표식 — 수리
`run_paper_replication.R` 이 권위 기록에 `factor_db_vintage` 를 싣는다(measured_at = run_id · 원장 md5 · 수리 id/완료 · 진행 중 수리 · 선언 팩터 · 측정 순간 낡음 · 팩터 DB 빌드 도장).
계약 함수(fdv_ledger · fdv_stale · fdv_declared_factors)를 격리 환경에서 그대로 부른다. 실패 = status "error: …"(측정 계속 · 소비자 판정 경로 불변).
권위 기록은 원자적 쓰기(임시 파일 → 되읽기 → 이름 바꾸기)로 바꿨다 — 측정 중 크래시가 반쪽 JSON 을 남기지 않는다.

### Q6. 레인 운영 — 왜 멈췄나 · 켜도 되나
- 왜: 마지막 틱 11-07 09:30(다른 기기 · 경로 C:/Users/99922). 11-07 15:54 메인 전환 때 이 PC 의 작업은 `jobs\off\` 로 Export 됐고 Enable 이 안 됐다(한 번도 안 돎 267011).
  그 뒤 11-08 · 09 · 10 운영 로그에는 **시험의 가짜 논문 줄만** 있었다(A.cpu · B.gpu · C.cpu — 디스패처 로그 누출 · 수리함).
- 남은 상태: 슬롯 3개 모두 in_progress + 고아 claim(다른 기기 pid) — cpu1 1109.3488(auto_retries 2 · replication_error), cpu2 2106.06164(감사 재구현 착수 직후),
  gpu1 2601.04602(11-06 12:18 부터 측정 중 · verify-only). GPU 인계함 4편(전부 딥러닝). claim 읽기 전용 속성 없음(attrib 확인).
- 켜기 전 필수:
  ① **RAM** — 슬롯 설정 cpu 2 + gpu 1 인데 메인 PC 32 GB(실측 31.8). 셀 워커 1개 정점 7.45 GB · DNN 한 칸 추정 25~33 GB(메모리 카드 11-03). 인계함 4편 + gpu1 이 전부 DNN →
     동시 실행 시 페이징 · OOM. 증설 전까지 `rf_replication_slots.py config enable --cpu 1 --gpu 1`(또는 cpu 2 · gpu 0) 권고(도훈 결정).
  ② **측정 중단 → 재구현 결함**(수리함) — 고아 claim 회수 뒤 in_progress 요청은 실패 표식이 없어 **에이전트 재구현**으로 갔다(감사 통과 엔진을 다시 씀 · 1차 통과 위험).
     gpu1 2601.04602 가 바로 그 경우였다. 이제 검증기 시작 표식 + 엔진 지문이 같으면 verify_interrupted → 검증기만.
  ③ 1109.3488(MOEA): 로그 실측 리밸 1회 11.8분 → 312회 ≈ 61시간 × 변형 4 ≈ 10일 CPU 1슬롯 점유(계산 시간 상한 없음 정책). 슬롯을 묶는다 — 도훈 결정.
  ④ 무인 인증: 사용자 환경변수 CLAUDE_CODE_OAUTH_TOKEN 있음(값 미출력) · claude.exe 있음. 11-06 주간 한도 소진 7회(halt_env_failure model_quota_exhausted · 32분 백오프)는 정상 동작.
- 켜는 절차: (1) 슬롯 수 결정(①) (2) `Qvest_ReinforceAutoLoop` Enable → `qvest_tasks.ps1 -Mode Export` → Apply(일반 PowerShell · 노트북 끈 채)
  (3) 첫 틱 뒤 `_status.json` at 갱신 · 저널 claim_stale_reclaim 3건 · gpu1 verify_only_retry(note=측정 도중 중단) 확인.

### Q7. 속도 [실측 · 저널 10-05 ~ 11-07]
| 단계 | n | 중앙 | p75 | 최대 |
|---|---:|---:|---:|---:|
| 구현 에이전트(start → preaudit) | 61 | 23.2분 | 34.0 | 64.4 |
| 6축 감사(fanout → merge) | 61 | 11.3분 | 14.9 | 2,756(멈춤 1건) |
| 변형 1개 측정 | 33 | 15.6분 | 43.3 | 68.9 |
| 측정 본체(대표) | — | 7~15분(단일) · 49분(변형 3) · 109분(변형 16) · 61시간(1109.3488 추정) | | |
상위 3 소모처: ① 재구현 사이클(1차 기각 90% × 에이전트 23분 + 감사 11분 + 연쇄) ② 무거운 엔진(시간 상한 없음 · 1109.3488 · 2106.06164 11시간+) ③ LLM 주간 한도(11-06 3.5시간 정지).
단축안(판정 불변): 측정 중단 시 재구현 대신 검증기만(수리함) · 검증기만 재실행에서 같은 엔진 지문의 6축 감사 재사용(README 미완 항목 — 감사 LLM 11분 절약 · 판정 동일 조건 = 엔진 md5 + 감사 프롬프트 md5 일치) ·
Rcpp 컴파일 실패 → R 폴백(11-06 로그 'C:/qm_cache/rcpp_build file io error' — 측정 속도 저하) 원인 수리(소유 밖).

### Q8. P/L 우상향 관점
- 충실구현은 '논문 그대로'(롱숏 · 종목 수 무제한)를 KOSPI200 대비로 채점 → 재료 12 중 9 가 롱숏 · 4 건 F 가 롱숏 구조 탓. 레인이 넘기는 것은 엔진 경로뿐이고
  롱 다리 · 롱온리 25종 성과는 **어디서도 측정되지 않는다**(P1 상설 미등록). 논문 기준 성과는 auth.replication.paper_basis 로 병기된다(확인).
- 따라서 이 영역이 P/L 목표를 가장 크게 막는 것은 ① 상설 판(롱 다리 측정) 미가동 ② 1차 기각 90%(재료 공급 속도) ③ 레인 정지 + RAM 한도.

## 3. 시나리오 표
| 시나리오 | 기대 | 수리 전 실제 | 조치 | 시험 |
|---|---|---|---|---|
| 격리 시험의 디스패처 로그 | 격리 폴더 | 운영 로그에 가짜 논문 줄(11-08~10) | LOG 를 상태 폴더 기준으로 | test_scn_repl_lane.sh L1(+돌연변이) |
| 큐 빔 | 발행 0 · 오류 0 | 같음 | — | L2 |
| 다른 기기 고아 claim | 회수 · 되살림 | 같음 | — | L3 |
| pid 재사용(산 프로세스) | 회수 | 같음 | — | L4 |
| 읽기 전용 claim 폴더 | 실제 삭제 | 같음 | — | L5 |
| 산 소유자 장시간 | 회수 안 함 · 경고 1회 | 같음 | — | L6 |
| 측정 중 크래시 뒤 되살림 | 검증기만 | **에이전트 재구현**(감사 통과 엔진 덮어씀) | 검증기 시작 표식 + 엔진 지문 → verify_interrupted | L7a · L7b |
| 낡은 팩터 DB 판 → A 관문 | held(factor_db_stale) | 판정은 실행 시각으로 됨 · 기록엔 판 없음 | 판 표식 · 측정 순간 낡음 기록 | test_scn_repl_measure_record.R S1~S4 |
| 측정 중 크래시 — 반쪽 권위 기록 | 없음 | write_json 직접 쓰기 | 원자적 쓰기 | S5 · S6(돌연변이) |
| 변형 일부 실패 | 그 행만 error · 대표 = 권위 | 같음 | — | S7 |
| Grade A → eligible / 보류 → held | 관문 경유 | 같음 | — | 기존 test_replication_a_gate.R 37/37 재실행 |
| 두 슬롯 같은 논문 | 착수 안 함 | 같음 | — | 기존 test_replication_slots_lane.sh W5(통과 확인) |
| 롱숏 논문 롱 다리 전달 | 상설 판이 롱온리로 잼 | 경로 미가동(P1S01 미등록) | 도훈 · 총괄 | — |

## 4. 수리 · 패치 제안
수리(소유 경로):
1. `02_Infrastructure/ops/rf_replication_auto.sh:35-38` — 디스패처 LOG = `${QVEST_RP_STATE_DIR:-$ROOT/.cache}/…` (운영 기본값 불변).
2. 같은 파일 PYRETRY(in_progress 되살림) · 상태 전이 단계 · rp_verify · 검증기만 분기 — verify_engine_md5/verify_started_at 표식 → verify_interrupted.
3. `02_Infrastructure/alpha_search/run_paper_replication.R` — `.rp_fdv_stamp` · `.rp_write_json_atomic` 신설 · §7 에서 auth$factor_db_vintage + 원자적 쓰기(끄기 QVEST_RP_FDV_STAMP=0).
4. `.claude/skills/alpha-search/SKILL.md:16` · `.claude/agents/alpha-search.md:19` — 현행 epoch · 판 표식 문구.
패치 제안(소유 밖):
- `04_Research/programs/_lib/round_core/v1/p4.R::rc_p4_base_pool` — 측정 epoch(auth.measurement_axis.epoch ≠ 활성 epoch) 제외 사유 `axis_epoch_mismatch` 추가(1908.01112 = all_hyg_2000_v1 이 현 축 재료와 같은 풀에 있다 · 지금은 전부 stale 이라 잠복).
- 같은 곳 — 재료 항목의 engine_path 가 없으면 같은 작업 디렉터리의 재발행 판(재구현 대기열 issued)을 가리키는지 사유 상세에 적기(no_engine 2건의 원인 표기).
- `02_Infrastructure/replication/replication_harness.R` — 보유 기록 |w| < 1e-12 제외(먼지 보유) · 03_period_returns turnover/n_holdings 채움.
- `06_Registry/rf_preaudit.json` + `rf_preaudit.py` — Q1 의 ①(변환 리터럴) ⑤(신고서 내부 모순) 범주.
- 감사 재사용(검증기만 재실행) — `rf_replication_verify.R` 감사 관문 앞 '같은 engine md5 + 같은 감사 프롬프트 md5 + 감사 파일 무결' 이면 재사용(README 미완 항목).

## 5. 업데이트 누락 감지
| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 |
|---|---|---|---|---|---|
| `_status.json`(슬롯 요약) | slots.py tick | 틱(8분) | 부팅 '★틱 N 전' (11-10 신설) | 부팅 · 감시기 | 경고 표시(71시간 무경고였음) |
| replication_auto_<날짜>.log | 디스패처 | 틱 | 감시기 lane_errors(패턴) | superfan_watch | 시험 줄 오염(수리) |
| authoritative_remeasure.json | run_paper_replication | 측정마다 | fdv_stale(실행 시각 · 이제 판 표식 병기) | A 관문 · 기저 풀 · 상설 | factor_db_stale 보류 |
| 프로그램 재료 큐 kind=engine | 검증기 | 측정마다 | rc_p4_base_pool 사유 | P4 · P1 | no_engine · stale 제외 |
| GPU 인계함 | 작업자 | 인계 시 | _status.json inbox 수 | gpu1 슬롯 | 10-20 부터 4편 정체(레인 정지 · GPU 임대) |

## 6. 확인 못 한 것
- 1908.01112 adv 위반 26행의 원인(엔진 신호일 vs 멤버십) · turnover/n_holdings NA 열의 소비자 · 이 PC 의 Rcpp 컴파일 상태 · 2002.06975 오늘 06:45 실행 주체(다른 세션 추정).
- 기존 test_replication_slots_lane.sh 는 590초 상한 안에 W6 까지 통과 후 W7 에서 시간 초과(시험 자체가 10분+) — 전체 완주 미확인 · 운영 로그 불변은 확인.

## 7. 돌린 시험 · 결과
| 시험 | 결과 | 비고 |
|---|---|---|
| 08_Tests/scenarios/test_scn_repl_measure_record.R (신규) | 26/26 · 4초 | 돌연변이 2종(판 표식 배선 제거 · 비원자 쓰기 복귀) 탐지 |
| 08_Tests/scenarios/test_scn_repl_lane.sh (신규) | 9/9 · 약 3~4분 | L1 돌연변이(구판 LOG 줄) 탐지 내장 · L7 돌연변이(verify_interrupted 분기 제거 사본 · SCN_REPL_LANE) = L7a FAIL(agent=1 — 수리 전 동작 재현) |
| 08_Tests/ops/test_replication_lane.sh (기존) | 87/87 | 수리 뒤 회귀 없음 |
| 08_Tests/contracts/test_replication_a_gate.R (기존) | 37/37 | 러너 수리 뒤 |
| 08_Tests/ops/test_replication_slots_lane.sh (기존) | W6 까지 OK · W7 에서 590초 상한 | 시험 자체가 10분+ · 실행 전후 운영 로그 크기 · mtime 불변(2244B · 12:08:49) |
운영 로그 `.cache/scheduler_logs/replication_auto_20261110.log` = 모든 시험 뒤에도 2244B · 12:08:49(수리 전 시험 실행분 그대로).
배터리 등록 제안(총괄): 위 신규 2종. test_scn_repl_lane.sh 는 60초 목표를 넘는다(PowerShell pid 조회 · 레인 2회) — 밤 목록 제외 후보.

## 8. 안 쓰는 것
`dead_D_replication.tsv` — alpha_search/ 144 파일 중 99(코드 참조 0 또는 alpha_search 안 죽은 후보끼리만 참조 · 전이 폐포): certain 32(참조 0 · 시험 참조 0) · probable 67(문서 · 등록부 · 시험 참조만) · 전부 '지우지 않음'.
live 로 둔 것: run_paper_replication.R · run_alpha_search.R(실투형 측정 도구 — SKILL) · factor_engine_template.R(에이전트 문서) · 참조가 살아 있는 fe_*.R.
