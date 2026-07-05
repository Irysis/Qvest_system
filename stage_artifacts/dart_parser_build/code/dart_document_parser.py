#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
DART 임원ㆍ주요주주 특정증권등 소유상황보고서 — document.xml 원문 파서
==============================================================================
목적: elestock.json API 가 rolling ~23개월만 제공하는 한계를 우회.
      document.xml(rcept_no 원문 ZIP→XML)을 직접 파싱해 2005~ 역사 백필 가능화.

핵심 설계 (form-version robust — v2.8[2005] ~ v4.1[2024] 실측):
  - DART4 XML 은 ACODE(구조화 셀 코드) + AUNIT(추출 단위) 속성으로 필드 마킹.
  - report-level 요약(elestock 파리티 대상): MDF_STK_SUM(증감 합계) / AFR_STK_SUM(변동후) 등
    → 전 form-version 에서 일관 존재(2005 v2.8 확인). 이게 net buy/sell 수량의 authoritative.
  - reporter 분류(officer vs 10% shareholder): STF_RYN(등기/비등기) 우선, 없으면 MAIN_SH.
  - 세부변동내역(다): 거래별 RPT_RSN(보고사유) → 장내매수/매도(discretionary) vs 신규선임·상여(mechanical) 분리.
  - PIT: rcept_dt(공시 접수일) 기준 — 시장은 접수 시점에 인지. MDF_DM(변동일자)은 정보용만.
  - 인코딩: 2005~2020 EUC-KR/CP949, 2024 UTF-8 — 자동 판별.

산출: parse_document(rcept_no, raw_bytes) -> dict (report-level record + detail transactions)

작성: 2026-07-05 (도훈 mandate — DART insider 역사 백필 유일 경로). 기존 파일 수정 없음(신규).
"""
import re
import io
import zipfile

# ---- RPT_RSN 코드 → discretionary(장내매매) 여부 분류 --------------------------
# 01 장내매수(+), 02 장내매도(-) = discretionary open-market (진짜 신호)
# 03 장외매수, 04 장외매도 = off-market (약한 신호)
# 나머지(신규선임/상여/증여/상속/전환/합병 등) = mechanical (노이즈, 별도 라벨)
DISCRETIONARY_MARKET = {"01", "02"}          # 장내매수/매도
OFFMARKET = {"03", "04"}                     # 장외매수/매도
# 나머지 코드는 mechanical 로 취급.

# ---- 인코딩 자동 판별 -----------------------------------------------------------
def decode_document(raw_bytes):
    """document.xml ZIP 바이트 → (rcept_no_xml_name, decoded_text, encoding)."""
    z = zipfile.ZipFile(io.BytesIO(raw_bytes))
    name = z.namelist()[0]
    data = z.read(name)
    for enc in ("utf-8", "euc-kr", "cp949"):
        try:
            return name, data.decode(enc), enc
        except UnicodeDecodeError:
            continue
    # 마지막 fallback: 손실 허용
    return name, data.decode("cp949", errors="replace"), "cp949-lossy"


# ---- 셀 값 추출 헬퍼 ------------------------------------------------------------
def _strip_tags(s):
    return re.sub(r"<[^>]+>", "", s).strip()


def _num(s):
    """'−467,230' / '2,280' / '-' → int or None."""
    if s is None:
        return None
    t = re.sub(r"[^0-9\-]", "", s)
    if t in ("", "-"):
        return None
    try:
        return int(t)
    except ValueError:
        return None


def _rate(s):
    """'0.00' / '-' → float or None."""
    if s is None:
        return None
    t = re.sub(r"[^0-9.\-]", "", s)
    if t in ("", "-", "."):
        return None
    try:
        return float(t)
    except ValueError:
        return None


def get_acode(txt, code):
    """<TE/TU/TD ... ACODE="{code}" ...>value</...> 첫 매치의 텍스트."""
    m = re.search(rf'<T[EUD][^>]*ACODE="{code}"[^>]*>(.*?)</T[EUD]>', txt, re.S)
    return _strip_tags(m.group(1)) if m else None


def get_aunit_val(txt, unit):
    """AUNIT 셀의 표시 텍스트."""
    m = re.search(rf'<T[EUD][^>]*AUNIT="{unit}"[^>]*>(.*?)</T[EUD]>', txt, re.S)
    return _strip_tags(m.group(1)) if m else None


def get_aunit_code(txt, unit):
    """AUNIT 셀의 AUNITVALUE(코드)."""
    m = re.search(rf'AUNIT="{unit}"[^>]*AUNITVALUE="([^"]*)"', txt)
    return m.group(1) if m else None


# ---- reporter 분류 --------------------------------------------------------------
def classify_reporter(txt):
    """
    return dict: reporter_type ∈ {officer, shareholder_10pct, controlling, other},
                 officer_registered(bool|None), officer_position, main_sh_label, ifr_type.
    officer 우선(STF_RYN 존재) → 없으면 MAIN_SH 로 10%주주/지배주주 판정.
    """
    stf_ryn_val = get_aunit_val(txt, "STF_RYN")     # 등기임원/비등기임원
    stf_ryn_code = get_aunit_code(txt, "STF_RYN")   # Y/N
    stf_psm = get_acode(txt, "STF_PSM")             # 직위(상무 등)
    main_sh_val = get_aunit_val(txt, "MAIN_SH")     # 10%이상주주/사실상지배주주/-
    ifr_tp = get_aunit_val(txt, "IFR_TP")           # 개인(국내)/법인 등

    officer_registered = None
    if stf_ryn_code in ("Y", "N"):
        officer_registered = (stf_ryn_code == "Y")

    # 판정 우선순위
    is_officer = bool(stf_ryn_val and stf_ryn_val not in ("-", "")) or bool(stf_psm and stf_psm not in ("-", ""))
    main_sh = main_sh_val if main_sh_val not in (None, "-", "") else None

    if is_officer:
        rtype = "officer"
    elif main_sh and "지배" in main_sh:
        rtype = "controlling"
    elif main_sh and "10%" in main_sh:
        rtype = "shareholder_10pct"
    elif main_sh:
        rtype = "shareholder_other"
    else:
        rtype = "other"

    return {
        "reporter_type": rtype,
        "officer_registered": officer_registered,
        "officer_position": stf_psm if stf_psm not in (None, "-", "") else None,
        "main_sh_label": main_sh,
        "ifr_type": ifr_tp if ifr_tp not in (None, "-", "") else None,
    }


# ---- 세부변동내역(다) 파싱 → 거래별 RPT_RSN 분류 -------------------------------
def parse_detail_transactions(txt):
    """
    세부변동내역 테이블의 거래별 행 → RPT_RSN 코드/라벨 + 증감 수량.
    각 거래 행은 AUNIT="RPT_RSN"(보고사유) + AUNIT="MDF_DM"(변동일자) + ACODE="CPT_CNT"/증감.
    반환: list of {rpt_rsn_code, rpt_rsn_label, mdf_date, change_qty, is_discretionary, is_offmarket}.
    robust: 셀 정렬 대신 RPT_RSN 앵커별로 인접 MDF_DM/수량 추출.
    """
    txns = []
    # 각 거래는 <TU AUNIT="RPT_RSN" ...> 로 시작. 그 뒤 같은 TR 내 MDF_DM 과 증감(CPT_CNT/MDF_UN_CNT).
    # 앵커: RPT_RSN 위치별로 이후 400자 window 에서 MDF_DM 코드, 증감수량 탐색.
    for m in re.finditer(r'AUNIT="RPT_RSN"[^>]*AUNITVALUE="([^"]*)"[^>]*>(.*?)</T[EUD]>', txt, re.S):
        code = m.group(1)
        label = _strip_tags(m.group(2))
        win = txt[m.end(): m.end() + 800]
        dm = re.search(r'AUNIT="MDF_DM"[^>]*AUNITVALUE="([0-9]{8})"', win)
        mdf_date = dm.group(1) if dm else None
        # 증감 수량: 우선 CPT_CNT(취득/처분 수), 없으면 detail 행의 MDF 계열
        qm = re.search(r'ACODE="CPT_CNT"[^>]*>(.*?)</T[EUD]>', win, re.S)
        qty = _num(_strip_tags(qm.group(1))) if qm else None
        txns.append({
            "rpt_rsn_code": code,
            "rpt_rsn_label": label,
            "mdf_date": mdf_date,
            "change_qty": qty,
            "is_discretionary": code in DISCRETIONARY_MARKET,
            "is_offmarket": code in OFFMARKET,
        })
    return txns


# ---- 메인 파서 -----------------------------------------------------------------
def parse_document(rcept_no, raw_bytes, rcept_dt=None, corp_code=None):
    """
    document.xml ZIP 바이트 → report-level insider record.

    return dict (None if not an insider ownership report / parse failed):
      rcept_no, rcept_dt, corp_code, stock_code, corp_name,
      reporter_name, reporter_type, officer_registered, officer_position, main_sh_label, ifr_type,
      net_change_qty (MDF_STK_SUM, 특정증권등 증감 합계 — SIGNED, authoritative net buy/sell),
      after_qty (AFR_STK_SUM), before_qty (BFR_STK_SUM),
      after_rate, change_rate,
      n_txns, n_discretionary, n_offmarket, n_mechanical,
      disc_change_qty (장내매매만 합산한 증감 — 신호정제용),
      formula_version, encoding, parse_flags(list)
    """
    flags = []
    try:
        name, txt, enc = decode_document(raw_bytes)
    except Exception as e:
        return {"rcept_no": rcept_no, "parse_flags": [f"decode_fail:{type(e).__name__}"], "ok": False}

    # 문서 유형 확인 — 임원ㆍ주요주주 소유상황보고서인지 (form-version robust)
    #   신규(2007+): "임원ㆍ주요주주 특정증권등 소유상황보고서"  (특정증권)
    #   구(2005~06): "임원ㆍ주요주주소유주식보고서"              (소유주식, 특정증권 용어 이전)
    #   둘 다 동일 ACODE(MDF_STK_SUM 등) 구조 사용 → 용어만 다름.
    docname = ""
    dm = re.search(r"<DOCUMENT-NAME[^>]*>(.*?)</DOCUMENT-NAME>", txt, re.S)
    if dm:
        docname = _strip_tags(dm.group(1))
    head = docname + txt[:2000]
    is_insider_doc = ("특정증권" in head) or ("소유주식" in head) or \
                     ("소유상황" in head and "임원" in head) or \
                     ('ACODE="00634"' in txt) or ('ACODE="MDF_STK_SUM"' in txt)
    if not is_insider_doc:
        return {"rcept_no": rcept_no, "parse_flags": ["not_insider_ownership_report"], "ok": False}
    if "특정증권" not in head and "소유주식" in head:
        flags.append("old_form_owned_stock_terminology")

    fv = re.search(r"<FORMULA-VERSION[^>]*>([^<]+)</FORMULA-VERSION>", txt)
    formula_version = fv.group(1).strip() if fv else None

    stock_code = get_acode(txt, "CRP_CD")           # 종목코드 6자리
    corp_name = get_acode(txt, "CRP_NM")
    reporter_name = get_acode(txt, "IFR_NM")

    rep = classify_reporter(txt)

    # report-level 요약 (authoritative net) — MDF_STK_SUM 우선, 없으면 MDF_UN_CNT
    net_change = _num(get_acode(txt, "MDF_STK_SUM"))
    if net_change is None:
        net_change = _num(get_acode(txt, "MDF_UN_CNT"))
    after_qty = _num(get_acode(txt, "AFR_STK_SUM"))
    if after_qty is None:
        after_qty = _num(get_acode(txt, "AFR_UN_CNT"))
    before_qty = _num(get_acode(txt, "BFR_STK_SUM"))
    if before_qty is None:
        before_qty = _num(get_acode(txt, "BFR_UN_CNT"))
    after_rate = _rate(get_acode(txt, "AFR_UN_RT"))
    change_rate = _rate(get_acode(txt, "MDF_UN_RT"))

    if net_change is None:
        flags.append("no_net_change_summary")

    # 세부변동내역 → discretionary 분리
    txns = parse_detail_transactions(txt)
    n_disc = sum(1 for t in txns if t["is_discretionary"])
    n_off = sum(1 for t in txns if t["is_offmarket"])
    n_mech = len(txns) - n_disc - n_off
    # 장내매매(01/02)만의 순증감: 02(매도-)는 음, 01(매수+)는 양. change_qty 부호가 신뢰 어려우면
    #   RPT_RSN 코드로 부호 강제(01→+, 02→-). CPT_CNT 는 절대값 취득/처분 수로 보고됨.
    disc_change = 0
    disc_seen = False
    for t in txns:
        if t["rpt_rsn_code"] in DISCRETIONARY_MARKET and t["change_qty"] is not None:
            sign = 1 if t["rpt_rsn_code"] == "01" else -1
            disc_change += sign * abs(t["change_qty"])
            disc_seen = True
    disc_change_qty = disc_change if disc_seen else None

    if formula_version and formula_version.startswith("2"):
        flags.append("old_formula_v2_reporter_fields_may_be_sparse")

    return {
        "ok": True,
        "rcept_no": str(rcept_no),
        "rcept_dt": rcept_dt,
        "corp_code": corp_code,
        "stock_code": stock_code,
        "corp_name": corp_name,
        "reporter_name": reporter_name,
        "reporter_type": rep["reporter_type"],
        "officer_registered": rep["officer_registered"],
        "officer_position": rep["officer_position"],
        "main_sh_label": rep["main_sh_label"],
        "ifr_type": rep["ifr_type"],
        "net_change_qty": net_change,
        "after_qty": after_qty,
        "before_qty": before_qty,
        "after_rate": after_rate,
        "change_rate": change_rate,
        "n_txns": len(txns),
        "n_discretionary": n_disc,
        "n_offmarket": n_off,
        "n_mechanical": n_mech,
        "disc_change_qty": disc_change_qty,
        "formula_version": formula_version,
        "encoding": enc,
        "parse_flags": flags,
    }


if __name__ == "__main__":
    # 단위 테스트: probe 폴더의 5개 샘플
    import os, json
    OUTD = os.path.join(os.environ.get("TEMP", r"C:\Users\99922\AppData\Local\Temp"), "dart_probe")
    samples = {
        "20241220000101": "2024-12-20",
        "20050131000139": "2005-01-31",
        "20100630000401": "2010-06-30",
        "20150331004513": "2015-03-31",
        "20200429001361": "2020-04-29",
    }
    for rc, dt in samples.items():
        p = os.path.join(OUTD, rc + ".xml")
        if not os.path.exists(p):
            print(rc, "no local xml (run probe first)")
            continue
        txt = open(p, encoding="utf-8").read()
        # 로컬 xml 은 이미 decode 됨 → parse_document 는 zip bytes 를 기대하므로 내부 함수 직접 사용
        import types
        # 로컬 테스트용: decode 우회
        fv = re.search(r"<FORMULA-VERSION[^>]*>([^<]+)</FORMULA-VERSION>", txt)
        rep = classify_reporter(txt)
        net = _num(get_acode(txt, "MDF_STK_SUM")) or _num(get_acode(txt, "MDF_UN_CNT"))
        txns = parse_detail_transactions(txt)
        print(f"{rc} ({dt}) v{fv.group(1) if fv else '?'}: "
              f"code={get_acode(txt,'CRP_CD')} name={get_acode(txt,'CRP_NM')} "
              f"reporter={get_acode(txt,'IFR_NM')} type={rep['reporter_type']} "
              f"net_change={net} n_txns={len(txns)} "
              f"disc={sum(1 for t in txns if t['is_discretionary'])}")
