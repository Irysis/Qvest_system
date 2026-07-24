# AST 리프 맵 v0 — Qvest 가용 전 데이터 자산 전수 (2026-07-25)

**의뢰**: 도훈 — "DB 팩터에 한정하지 말고 현재 Qvest 가용 가능한 모든 데이터에 대해 AST 맵"
**정본**: `06_Registry/ast_field_map_v0.json` (58 리프 그룹 × 6 도메인 — 전 수치 pyarrow footer 실측 + 로더 코드 파일:라인 인용. 워크플로우 wf_85fe98c6-538)
**전제 판정**: AST v1.1 편입 판정(`ast_layer_adoption_review_20260725.md`)의 M1(escape 리프)·M2(registry 포인터) 원칙 적용.

---

## 1. 총괄

| 클래스 | 수 | 의미 |
|---|---|---|
| FIELD (원천) | 22 | AST 리프 직접 자격 — RAWDATA·벤치/지수·멤버십·수급·재무·컨센서스·DART 이벤트·FRED/ECOS |
| FIELD_REGISTRY_PTR | 11 | factor_registry 373엔트리의 그룹 포인터 (개별 스펙은 registry SOT — 3중화 방지) |
| STORED_SCORE (파생) | 15 | IC 패널·국면 패널·스타일 트래커·insider 패널 등 — **provenance 3필드 의무 후** 리프 자격 |
| LLM_SCORE | 2 | 사업보고서 텍스트(8,229 filings 인벤토리 + LLM 파일럿 45문서) |
| EXTERNAL | 5 | 미확보(공매도/대차·KRX파생·NPS)·외부 MCP 조회형(PIT 불가) — 인입 시 재분류 |
| NOT_LEAF | 3 | 운용 산출(book NAV)·observability 메타 — 단 cache_registry/pin_cache는 availability/vintage 필드의 1차 소스로 재사용 |

**핵심 원천 커버리지 (실측)**: RAWDATA 1990-01-05~2026-07-23 (1,403만행, 상폐 포함 survivorship-free) · 벤치 1990~T-1 · 멤버십 8패널 1990~**2026-03-31** · 종목수급 2000~2026-07-01 (3,186만행) · 재무 merged 2000~ (543만행, XLSX+DART 혼합) · 컨센서스 12 metric 2000~ (**일별 as-of — vintage 구조 보유**) · DART insider 역사 2005~2026-06 (258/258개월, 31.6만행) · FRED 24계열 + ECOS 2000~.

## 2. 설계안 §3 표의 실측 답 (원안이 "확인 필요"로 남긴 칸)

| 필드군 | 원안 | **실측** |
|---|---|---|
| 가격·거래량 | 0 (T 장마감) | Naver T+0 patch가 PRIMARY(당일 종가 즉시), cron 00:03 — 실효 T-1. 단 **수정주가 원장 = 전기간 재작성**이라 restatement_prone=**true** (원안 false와 반대) — pin_cache가 vintage 대응 |
| 투자자별 수급 | 0~1일 (확인 필요) | KRX 원공표는 T+0이나 Qvest 인입은 QuantiWise 수동 export — **실효 지연 ~22일(비정기)**. 강제점 compute_investor.R:100 strict t-1뿐 |
| 분기 재무 | 분기말+규제기한 | 3-way 불일치 실측: xlsx 일률 +45d(Q4≈익년 2/14) vs DART 분기 고정일(5/15·8/15·11/15·3/31) vs pit.md 선언 "연간 5월" — **Step 0 결정 대상이 2-way가 아니라 3-way** |
| 재무 restatement/vintage | 확인 필요 | **true / false 확정** — xlsx 스냅샷 + rank==1 dedupe가 정정 전 원본 물리 소거. DART 재수집으로 부분 구제 가능성만 존재 |
| 컨센서스 | 제공 시각·확인 필요 | 일별 as-of 시계열(gap 최빈 1일) = **컨센서스-레벨 vintage 구조 보유**(eps_chg_1m/3m이 수정치 자체). per-analyst 상세는 없음 |
| 공시 이벤트 | 공시 시각 | rcept_dt(접수일) = 가용시점 권위 확립. 이벤트→월간 신호 규약 = "신호월 m = 접수월, forward = m+1" (build_insider_factor_panel.R:20-21, C5 정합) |

## 3. ★ 채록 중 적발된 운영 이슈 (맵의 부산물 — 조치 필요)

1. **[최우선·도훈 수동] K200/KQ150 멤버십 종점 2026-03-31** — universe_support 8패널이 4개월 스테일로 **2026-06 정기변경 미반영**. 헌법 Universe 제약(K200∪KQ150)의 원천이라 최근월 백테·라이브 종목선정에 직접 영향. A2(KRX 층)도 carry-forward라 보정 불가 — **QuantiWise Universe_Support.xlsx 재export가 유일 해소 경로**.
2. **benchmark.parquet Date dtype = timestamp[ns] 실측** — date32 통일 수리(memory: branch)가 main에 미병합 상태 확정. RAWDATA(date32)와 `by="Date"` 조인 시 silent all-NA 실사고 전력(β 54팩터 전멸) — 병합 필요.
3. **신선도 스테일 4건**: SJM BearProb 2026-06-04(~7주, 리프레시 미배선) · conditional_ic_matrix 2026-06-08(~7주) · regime_daily_v2 4영업일 지연 · factor_db_202607이 07-03 단일 intra-month 스냅샷(소비자에 침묵 전달) + factor_ic_monthly 2개월 lag.
   - **[조치 2026-07-25 Q — 앞 3건 수리 완료 (commit ebba3c08 main 병합)]**: ① SJM = daily_refresh [4] 일간 배선(refit_jm_daily, 실측 2.0분) + registry daily/3d 등재, 수동 리프레시로 종점 2026-07-24 현행화 ② conditional_ic_matrix = daily_refresh [6c] 주간(월) 배선 + registry weekly/10d 등재 + `sg_compute_conditional_ic` base fallback 수리(STR_1375 holdings 소실 → STR_1469_cons4f_5sleeve, 근본원인 = monthly_distill task 미등록 + base 소실 이중 결함), 종점 07-25 현행화(328팩터) ③ regime_daily_v2 = daily_refresh [4] FRED 직후 이중 배선(morning-only 갭 봉합), 종점 2026-07-24(=macro_fred)로 lag 0. 구 vintage는 `.cache/pins/prewire_regimecache_20260725` pin 보존. audit 검증 OK=45/WARN 0/CRITICAL 0. **잔여**: factor_db_202607 intra-month 스냅샷 + factor_ic_monthly 2개월 lag은 미조치(별도 트랙) · Qvest_MonthlyDistill 스케줄러 task 미등록은 도훈 결정 대기.
4. **선언-실측 불일치 2건**: "value/BM 2002-08~"(CLAUDE.md KR 한계)의 실측 onset = 2000-07 (2002-08은 336팩터 full-set 시점으로 재해석 필요) · C4 3-way(위 §2).
5. **고아/부재 3건**: fundamental_dart_quarterly(소비자 0) · valuation.parquet(빌더가 참조하나 파일 부재) · investor_market(2026-03-13 수집 정지 + cache_registry 미등재).

## 4. 공백 목록 — FQ가 원하는데 미확보 (게이트별)

- **도훈 로그인/export**: 공매도잔고·대차잔고(FQ-003 — 최고-EV 비-return lane, KRX API 부재 실조사 완료→QW export만) · 신용잔고 crowding(FQ-005). **저장소 전수 grep 실보유 0건 확정 = 전량 계획 상태.**
- **도훈 활용신청/무료키**: NPS 사업장 가입자수(FQ-064 — crosswalk 474행 준비 완료, 활용신청만 남음) · 산단 가동률(FQ-070) · KIPRIS 특허(FQ-071) · 관세청 HS 수출(FQ-073).
- **파서 비용 결정**: DART 계약금액 magnitude(FQ-002) · 담보 역사 2005~2023 ~29k 문서(FQ-004 2단).
- **기타**: FM 가중치+venv 패키지(FQ-061, capacity-gated) · TRASS(FQ-072 — alt-data 경계 위반 소지, 비권고) · KRX 파생(컬렉터 코드만, 캐시 0파일).

## 5. AST 리프 계약 권고 (v1.1 Step 1 입력)

1. **availability lag 유형에 "수동 export(비정기)" 1급 신설** — 자동배치(T-1)와 달리 코드 강제점(Date<sig_d)이 미래참조는 막지만 스테일은 못 막는 구조 (A3/A6/A8 실증). 리프 메타에 `refresh_mode: auto|manual` + cache_registry `max_lag_days` 연동.
2. **dtype 불변식 리프 계약** — Date 컬럼 dtype(date32)·심볼 sanity(벤치 IKS200)·조인 키 규약을 리프 레벨 불변식으로 (사고 이력 최다 리프 = 벤치마크).
3. **STORED_SCORE provenance 3필드 의무** — {기반 store build_hash, 생성 코드 경로, 생성 시각}. 현행 파생 3종(월간 IC·일간 IC 패널·flow_smartmoney) 전부 부재 실측 — 재빌드 후 정합 추적 불가 상태.
4. **C5 적용 컷오프를 리프 속성으로 내장** — 국면/오버레이 도메인은 신호 파일이 clean해도 소비 타이밍이 오염 지점(BearProb 실사고). 리프에 `apply_cutoff: first_day_of_holding_month` 명시.
5. **DART 이벤트 도메인 공통 라벨** — IC→PORT_t 전이 벽 반복 실측 도메인이므로 rank-IC advisory·canonical PORT_t 권위를 그룹 공통 강제. corp_code≠stock_code 함정(파서 산출의 corp_code가 실은 6자리 stock_code) 조인 가드.
6. **fdb_daily 접근자 신설** — 일간 팩터 439파일에 전용 관문 부재(C15 carve-out). AST 컴파일러가 일간 리프를 쓰려면 최우선 배관.

## 6. next_probe

1. **도훈 액션 2건**: ① Universe_Support.xlsx 재export(§3-1 — 최우선) ② Step 0 결정이 3-way로 확장됨(§2 재무 행): 연간 availability를 [3/31 | 5월 | +45d 일률] 중 확정.
2. **선행 수리 2건**(AST와 독립 가치): benchmark date32 병합 · SJM/steering 캐시 리프레시 배선.
3. **맵 소비**: v1.1 Step 1(registry 기계가독 승격)의 field_dictionary 원천으로 본 맵 사용 + Phase 3 커버리지 지도의 행/열 = 본 맵 FIELD·PTR 그룹. 공백 4건(§4 도훈-게이트)은 FQ 큐와 이미 정합 — 신규 등재 불요.
