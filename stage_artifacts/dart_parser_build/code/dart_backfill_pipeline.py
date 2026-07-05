#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
DART Insider 역사 백필 파이프라인 (document.xml 원문파서 경로)
==============================================================================
elestock.json(rolling ~23m) 우회 → document.xml 직접 파싱으로 2005~2024 역사 백필.

흐름:
  1. K200∪KQ150 corp_code 로드 (.cache/dart/universe_corpcodes.csv, 348종)
  2. 월별 list.json(pblntf_ty="D") 페이지네이션 → 임원·주요주주 특정증권 소유상황보고서 필터
  3. 유니버스 corp_code 교집합 → 각 rcept_no document.xml fetch → parse_document
  4. report-level record → 월별 parquet 체크포인트(resumable)
  5. PIT: rcept_dt(접수일) 기준 signal date

규율:
  - resumable: 완료 월 parquet 존재 시 skip. 부분 실패 월은 체크포인트 미기록(다음 run redo).
  - budget-guard: DART 일 10,000 call. 기본 예산/run = 7,000(daily_refresh 여유).
  - rate-limit: 0.75s 간격. status "020" (rate limit) 감지 시 즉시 halt.
  - PIT: signal date = rcept_dt (시장 인지 시점). MDF_DM 은 정보용만.
  - 기존 파일 수정 없음 — 산출 전부 stage_artifacts/dart_parser_build/ 격리.

Usage:
  BF_START=2005-01 BF_END=2024-02 DART_DAILY_BUDGET=7000 MODE=backfill \
    python dart_backfill_pipeline.py
  MODE=parity BF_START=2024-03 BF_END=2026-03  → 파리티 검증용 재파싱(elestock 대조)

작성: 2026-07-05 (도훈 mandate). 신규 파일.
"""
import os
import re
import io
import sys
import time
import json
import zipfile
import requests
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dart_document_parser import parse_document

ROOT = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
BUILD = os.path.join(ROOT, "stage_artifacts", "dart_parser_build")
CKDIR = os.path.join(BUILD, "cache", "monthly")
os.makedirs(CKDIR, exist_ok=True)

DELAY = 0.75
DAILY_BUDGET = int(os.environ.get("DART_DAILY_BUDGET", "7000"))
START = os.environ.get("BF_START", "2005-01")
END = os.environ.get("BF_END", "2024-02")
MODE = os.environ.get("MODE", "backfill")

LIST_URL = "https://opendart.fss.or.kr/api/list.json"
DOC_URL = "https://opendart.fss.or.kr/api/document.xml"

INSIDER_RE = re.compile(r"임원.{0,2}주요주주.{0,4}특정증권")


def load_key():
    env = open(os.path.join(ROOT, ".env"), encoding="utf-8").read()
    return re.search(r"DART_API_KEY=([^\r\n]+)", env).group(1).strip()


def load_universe():
    df = pd.read_csv(os.path.join(ROOT, ".cache", "dart", "universe_corpcodes.csv"), dtype=str)
    # corp_code -> stock_code map
    cc2sc = dict(zip(df["corp_code"], df["stock_code"]))
    return set(df["corp_code"]), cc2sc


class Budget:
    def __init__(self, cap):
        self.cap = cap
        self.calls = 0
        self.halted = False

    def get(self, url, params):
        self.calls += 1
        try:
            r = requests.get(url, params=params, timeout=40)
        except Exception:
            r = None
        time.sleep(DELAY)
        return r

    def left(self):
        return self.calls < self.cap


def month_range(start, end):
    s = pd.Period(start, "M")
    e = pd.Period(end, "M")
    out = []
    p = s
    while p <= e:
        out.append(p.strftime("%Y%m"))
        p += 1
    return out


def fetch_month_list(bud, key, ym, uni_cc):
    """월별 지분공시 list → 유니버스 insider 보고서 rows (rcept_no, rcept_dt, corp_code, report_nm)."""
    yr, mo = ym[:4], ym[4:6]
    bgn = ym + "01"
    last = pd.Period(f"{yr}-{mo}", "M").days_in_month
    end = ym + f"{last:02d}"
    page = 1
    rows = []
    ok = True
    while True:
        if not bud.left():
            ok = False
            break
        p = bud.get(LIST_URL, {"crtfc_key": key, "bgn_de": bgn, "end_de": end,
                               "pblntf_ty": "D", "page_no": page, "page_count": 100})
        if p is None:
            ok = False
            break
        try:
            j = p.json()
        except Exception:
            ok = False
            break
        st = j.get("status")
        if st == "020":
            bud.halted = True
            ok = False
            break
        if st != "000" or not j.get("list"):
            break
        for d in j["list"]:
            if d.get("corp_code") in uni_cc and INSIDER_RE.search(d.get("report_nm", "")):
                rows.append({"rcept_no": d["rcept_no"], "rcept_dt": d["rcept_dt"],
                             "corp_code": d["corp_code"], "report_nm": d["report_nm"]})
        tp = int(j.get("total_page", page))
        if page >= tp:
            break
        page += 1
    return rows, ok


def fetch_document(bud, key, rcept_no):
    r = bud.get(DOC_URL, {"crtfc_key": key, "rcept_no": rcept_no})
    if r is None:
        return None, "no_response"
    # rate-limit JSON error masquerading as document
    ct = r.headers.get("content-type", "")
    if "json" in ct or r.content[:2] != b"PK":
        try:
            j = r.json()
            if j.get("status") == "020":
                bud.halted = True
                return None, "rate_limit_020"
            return None, "status_" + str(j.get("status"))
        except Exception:
            return None, "not_zip"
    return r.content, "ok"


def process_month(bud, key, ym, uni_cc, cc2sc):
    """한 달 처리 → records list. budget/halt 시 partial=True."""
    listrows, list_ok = fetch_month_list(bud, key, ym, uni_cc)
    if not list_ok:
        return None, True  # partial — redo next run
    records = []
    partial = False
    for lr in listrows:
        if not bud.left():
            partial = True
            break
        raw, status = fetch_document(bud, key, lr["rcept_no"])
        if bud.halted:
            partial = True
            break
        if raw is None:
            records.append({"rcept_no": lr["rcept_no"], "rcept_dt": lr["rcept_dt"],
                            "corp_code": lr["corp_code"], "ok": False,
                            "parse_flags": json.dumps([f"fetch_{status}"], ensure_ascii=False)})
            continue
        rec = parse_document(lr["rcept_no"], raw, rcept_dt=lr["rcept_dt"], corp_code=lr["corp_code"])
        if rec.get("ok"):
            rec["stock_code"] = rec.get("stock_code") or cc2sc.get(lr["corp_code"])
        # parse_flags 항상 json 문자열로 통일 (ok=str / 실패=list 혼재 → pyarrow ArrowTypeError 방지)
        pf = rec.get("parse_flags", [])
        rec["parse_flags"] = pf if isinstance(pf, str) else json.dumps(pf, ensure_ascii=False)
        records.append(rec)
    return records, partial


def run():
    key = load_key()
    uni_cc, cc2sc = load_universe()
    months = month_range(START, END)
    bud = Budget(DAILY_BUDGET)
    print(f"[bf] mode={MODE} universe={len(uni_cc)} months={START}..{END} ({len(months)}) budget={DAILY_BUDGET}/run")

    done_this_run = 0
    for ym in months:
        ck = os.path.join(CKDIR, ym + ".parquet")
        if os.path.exists(ck):
            continue
        if not bud.left():
            print(f"[bf] budget reached before {ym} — stop (resume next run)")
            break
        records, partial = process_month(bud, key, ym, uni_cc, cc2sc)
        if partial or records is None:
            print(f"[bf] {ym} partial (budget/halt, calls={bud.calls}) — no checkpoint, redo next run")
            break
        if len(records) == 0:
            df = pd.DataFrame([{"ym": ym, "note": "no_universe_insider"}])
        else:
            df = pd.DataFrame(records)
        df.to_parquet(ck, index=False)
        ok_n = int(df["ok"].sum()) if "ok" in df.columns else 0
        print(f"[bf] {ym} done: {len(records)} reports, {ok_n} parsed ok (calls={bud.calls})")
        done_this_run += 1

    total_done = sum(os.path.exists(os.path.join(CKDIR, m + ".parquet")) for m in months)
    print(f"[bf] RUN END. calls={bud.calls} halted={bud.halted} "
          f"months_done={total_done}/{len(months)} (this_run={done_this_run})")


if __name__ == "__main__":
    run()
