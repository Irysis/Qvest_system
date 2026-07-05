# Self-Adversarial Challenge — WT-D20260706_003 (Alpha, Phase 0 NO-GO)

**v8.2 Opus 4.8 native adversarial reasoning. 외부 Codex 없음. finalize 직전 자체 적대검증.**

산출물 = infeasibility_report (NO_GO). 적대검증 대상 = "정말 자율취득 불가인가, 억지 NO-GO로 노력을 회피한 것 아닌가" + "가설 판단 자체의 취약점".

## Concern 1 (HIGH) — "충분히 probe 안 하고 NO-GO 선언(노력 회피)?"
**자기비평**: KRX MDC scrape에서 LOGOUT 하나 보고 포기한 것 아닌가? OTP 2-step, 다른 bld, 다른 referer를 더 시도했어야?
**분류: REBUTTAL (근거 有)**.
- 정량 3축: ① 세션 핸드셰이크 완비(JSESSIONID 확보 확인, cookies 출력) 후에도 400 LOGOUT ② ★결정적 — **known-working 엔드포인트(MDCSTAT01501 전종목시세)도 동일 LOGOUT** → bld/param 문제가 아니라 세션 인증 문제로 격리됨 ③ loader 페이지 GET이 직접 `alert('로그인 또는 회원가입이 필요합니다')` + MDCCOMS001(로그인) 리다이렉트를 두 menuId(quote·short) 모두 반환 = login-wall universal.
- 추가: GenerateOTP.cmd(CSV 경로)도 에러페이지. 3개 독립 경로(getJsonData·loader GET·GenerateOTP) 전부 login-wall 수렴.
- 결론: 더 시도 = login credential 없이는 구조적으로 불가. 노력 회피 아님. KRX가 2024-2025 정책으로 MDC 전면 로그인화한 것이 root cause(코드가 아님).

## Concern 2 (MEDIUM) — "Open API 404가 '영구 부재'가 아니라 내 경로명 오타?"
**자기비평**: /srt/sslt_bydd_trd가 실제 endpoint명과 다를 수 있음. 404를 '서비스 그룹 부재'로 과단정?
**분류: PARTIAL**.
- 인정: 정확한 endpoint 슬러그를 카탈로그로 확정하진 못함(3개 후보 시도).
- 그러나: ① 동일 host의 정상 서비스(/sto/ksq_bydd_trd)는 200이라 host/auth 정상 ② 404 메시지가 'API referenced by the path does not exist'로 명시 ③ KRX Open API(data-dbg) 공개 카탈로그는 지수/종목시세/기본정보 중심이며 short-selling은 전통적으로 MDC 포털 전용 데이터셋. → 슬러그 오타 가능성은 남으나, 설령 정확한 슬러그가 있어도 우리 **구독 티어에 미포함**일 개연이 높음(신청 필요). 이 불확실성을 next_action에 "KRX Open API short 서비스 그룹 추가 신청" 항목으로 명시 반영함 — 과단정 완화.

## Concern 3 (MEDIUM) — "data.go.kr을 실제로 확인 안 하고 next_action에 넣음"
**자기비평**: 최고EV로 제시한 data.go.kr 공매도 API의 실존/depth를 확인 못 함(web search payment 차단). 존재하지 않으면 도훈에게 헛수고 지시.
**분류: ACCEPT (부분)** → 보고에 반영.
- infeasibility_report next_action (1)에 "단 API 존재/depth 미확인 — 신청 전 확인 필요" 명시 캐비앗 이미 포함. 자율 web-search 자원이 차단되어 확인 불가한 것을 정직 라벨링. 도훈에게 "확인 후 신청" 프레이밍으로 전달 — 헛수고 리스크 완화.

## Concern 4 (guard) — self-rationalization auto-detection
회피표현("미미/관행적/실무적/보수적이면 OK/대부분 동일") 사용 여부 self-scan → **미사용**. NO-GO는 "괜찮다"류 합리화가 아니라 3-경로 수렴 실측(HTTP status·응답본문 인용)에 근거. PASS.

## Escalation trigger check
- HIGH severity ≥5? → NO (HIGH 1건, REBUTTAL). escalate 불요.
- 단 본 WT는 데이터 자원 게이트로 Q-Lead → 도훈 인증 자원 필요를 보고에 명시(자본 escalate 아닌 resource escalate).

## 결론
NO_GO 판정 유지. 3개 독립 경로 login-wall 수렴 + Open API 티어 미포함 + local cache 부재로 자율취득 구조적 불가. 가설은 정직/virgin/high-EV로 살아있음 — 도훈 인증 자원 투입 시 재개 milestone 큐잉. 억지 proxy 진행 금지(실데이터 아님 = 미검정).
