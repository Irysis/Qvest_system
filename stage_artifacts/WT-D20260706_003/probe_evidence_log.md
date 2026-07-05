# Phase 0 Feasibility Probe — Evidence Log (WT-D20260706_003)

as_of: 2026-07-06 | agent: alpha-research | verdict: NO_GO

## Path A — KRX Open API (data-dbg.krx.co.kr /svc/apis), AUTH_KEY valid
| endpoint | HTTP | note |
|---|---|---|
| /sto/ksq_bydd_trd (KOSDAQ OHLCV, control) | 200 | real data (BAS_DD/ISU_CD/ISU_NM...) — auth+host OK |
| /srt/sslt_bydd_trd (공매도 거래) | 404 | "API referenced by the path does not exist" |
| /srt/ssts_bydd_trd | 404 | 동일 |
| /srt/sbst_bydd_trd (공매도 잔고) | 404 | 동일 |
→ short-selling service group not in subscription catalog.

## Path B — KRX MDC portal (data.krx.co.kr getJsonData.cmd), no auth
| request | HTTP | body |
|---|---|---|
| MDCSTAT30501 (공매도 잔고) | 400 | LOGOUT |
| MDCSTAT30101 (공매도 거래) | 400 | LOGOUT |
| MDCSTAT01501 (전종목시세, KNOWN-WORKING control) | 400 | LOGOUT ← ★bld/param 아닌 세션 문제 격리 |
| GenerateOTP.cmd (CSV download path) | 200 | "에러페이지 - 한국거래소" (error page) |
| loader GET menuId=MDC0201020101 (quote) | 200 | alert('로그인 또는 회원가입이 필요합니다') + MDCCOMS001 redirect; login_wall=TRUE |
| loader GET menuId=MDC0201020506 (short) | 200 | login_wall=TRUE |
→ MDC portal universally login-walled (2024-2025 KRX policy). Historic no-auth scrape path dead.

## Path C — local caches
- factor_db: no short/lending factor (공매도 문자열 = axiom/firewall text only)
- investor_wide.parquet cols: Date, Ticker, Foreign, Individual, Institutional, OtherCorp (no short)
- krx_data_collector.R: header comment mentions 공매도 but functions = OHLCV/index/info only

## Path D — QuantiWise
- requires 도훈 login = out of autonomous scope (NO-GO reason only)

## Dedup
- lookup_hypothesis(공매도/short interest/대차잔고/short balance/lending) = 0 prior matches (virgin)

## Conclusion
3 independent portal paths (getJsonData / loader GET / GenerateOTP) converge on login-wall; Open API tier lacks /srt/*; no local asset. Autonomous acquisition structurally impossible → NO_GO. Requires 도훈 authenticated resource (data.go.kr API approval [existence unverified] / QuantiWise / KRX Open API short-group subscription).
