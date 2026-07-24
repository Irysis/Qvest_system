# FQ-064/065 firm-level 신호 PIT 계획 (point-in-time 스냅샷 보존 규약)

**대상**: FQ-064 국민연금 사업장 헤드카운트 모멘텀 · FQ-065 나라장터 정부조달 수주 magnitude
**적용**: `.claude/rules/pit.md` C1~C15 + measurement-graduation §7(vintage pinning)
**상태**: data.go.kr 키 랜딩 前 규약 사전확정. crosswalk는 firm-identity(시점-불변)라 지금 구축 완료.

---

## §1 usable_date (관측 가능 시점) — 두 원천의 발표시차 상이

| 신호 | data_ym 기준 | usable_date (관측가능) | lag 근거 | PIT 체크 |
|---|---|---|---|---|
| FQ-064 헤드카운트 | 기준월 말 | **M+1월 15일** | 국민연금 자격취득 신고 = 익월 15일까지. 마감 후에야 완전 관측 | C4-유사(재무lag) |
| FQ-065 정부조달 | 최초 낙찰일 | **낙찰일 ≈ 즉시(시차 0)** | 나라장터 낙찰 공표 실시간 | C10/C14 usable≤sig |

**신호→sig_date 매핑 규약(보수적)**:
- FQ-064: `data_ym` 신호는 usable_date(M+1 15일) **이후 첫 month-end**에 배정 → 그 월말 스코어로 다음달 수익 측정. 러너 STEP 3의 `build_pit_map()`(랜딩 시 교체)이 담당. 절대 `data_ym` 당월말로 배정 금지(자격취득 마감 전 = look-ahead).
- FQ-065: 낙찰월 month-end에 배정(시차 0이나 월간 cadence 정합). same-month 수익 스케일 금지(C2).

## §2 vintage 고정 (개정·계약변경 소급 금지)

- **FQ-064**: 국민연금 가입자수는 **후속 개정 가능**(정정신고). pull 시점 vintage를 그대로 스냅샷 저장하고, 이후 개정판으로 과거월 값을 **덮어쓰지 않는다**(first-release 보존). measurement-graduation §7 pin_cache tag를 산출물에 기록.
- **FQ-065**: 계약변경(증액/감액/해지)은 **최초 낙찰일 스냅샷으로 고정**. 변경금액을 최초 낙찰일로 **소급 반영 금지**(사후 정보 누출). 변경분은 변경 공표일 별도 이벤트로만 인식. `award_date=최초 낙찰일`이 vintage anchor.
- 두 신호 공통: HARD 게이트 판정·다중라운드 A/B는 pinned 스냅샷 기준(§7), pin tag 산출물 기록.

## §3 crosswalk 조인 무결성 (실측 근거)

`crosswalk_coverage.json` 실측(474 상장사, 2023+ univ 합집합):
- **full bizr_no(10자리) = firm-unique** (중복 0) → **정본 조인키**.
- **bizr_no6(앞 6자리) = 충돌 121건 / 190행 관여** (앞 6자리 = 관할세무서+개인/법인 구분코드, firm-unique 아님. 예: `101811`=종로세무서에 롯데관광개발·현대모비스·현대건설 동시).
- ★**국민연금 공표가 6자리 마스킹이면 bizr_no6 단독조인 금지** — 사업장명(corp_name) + 소재지(adres) fuzzy disambiguation 병용 의무. 랜딩 시 마스킹 여부 실측 후 조인전략 확정(추측 금지).
- FQ-065 계열귀속: 비상장 자회사 낙찰 → 상장모기업 귀속은 별도 `group_map` 필요(현 러너는 직접 상장사 낙찰만=보수적 하한).

## §4 잔여 PIT 리스크 (랜딩 시 실측 검증 항목)

1. **커버리지 편향**: 국민연금/조달 데이터의 상장사 커버리지% + 결측 firm의 비랜덤성(대형주 편중?) — 랜딩 시 census.
2. **정규직 편향(FQ-064)**: 국민연금 가입=정규직 위주 → 노동집약/고용형태 편향. sector·size-residualize 정규화.
3. **backfill depth**: 두 원천의 이력 시작월 확인(FQ-065 백필 범위 미측정) → 측정 기간이 canonical n_months·oos 분할에 영향.
4. **survivorship**: crosswalk는 현재+2023이후 univ 기준 → 과거 상장폐지 firm 결측 가능. 장기 백테 시 delisted corp_code 보강 필요(corpCode.xml 전체는 상폐 포함 3,978건이라 확장 가능).
