# -*- coding: utf-8 -*-
"""Recover arXiv discovery candidates for TODAY when arxiv-mcp-server returned HTTP 406.

Diagnosis (2026-09-26): arXiv returns 406 to every *Python* HTTP client request from this
host (urllib with/without UA, any query shape incl. trivial all:electron) while curl gets
HTTP 200 on the byte-identical URL. That is the actual root cause of the collector outage
since 2026-09-18 -- NOT rapid-fire throttling as the 20260924 note supposed. So we keep the
query spec byte-identical to the collector and only swap the transport to curl.
Reproduces the collector candidate schema incl. paper_key = 'axv:<id>'.
"""
import json, time, re, subprocess, urllib.parse, xml.etree.ElementTree as ET

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PR = ROOT + "/stage_artifacts/paper_recharge"
TODAY = "20260926"
SPEC = json.load(open(PR + "/mcp_discovery_" + TODAY + ".json", encoding="utf-8"))

queries = SPEC["queries"]
cats = SPEC["categories"]
maxr = SPEC["max_results_per_query"]
sortby = SPEC["sort_by"]
cat_clause = " OR ".join("cat:" + c for c in cats)
NS = {"a": "http://www.w3.org/2005/Atom"}
UA = "qvest-paper-triage/1.0 (mailto:0428kdh12@gmail.com)"
VSUF = re.compile(r"v\d+$")


def fetch(q, attempt=0):
    sq = "(ti:(" + q + ") OR abs:(" + q + ")) AND (" + cat_clause + ")"
    url = "https://export.arxiv.org/api/query?" + urllib.parse.urlencode(
        {"search_query": sq, "start": 0, "max_results": maxr,
         "sortBy": sortby, "sortOrder": "descending"})
    cp = subprocess.run(["curl", "-sS", "--max-time", "60", "-A", UA,
                         "-w", "%{http_code}", "--output", "-", url],
                        capture_output=True)
    if cp.returncode != 0:
        if attempt < 2:
            time.sleep(6.0 * (attempt + 1))
            return fetch(q, attempt + 1)
        return None, "curl rc=%d: %s" % (cp.returncode, cp.stderr.decode("utf-8", "replace")[:160])
    out = cp.stdout
    code = out[-3:].decode("ascii", "replace")
    body = out[:-3]
    if code != "200":
        if attempt < 2:
            time.sleep(6.0 * (attempt + 1))
            return fetch(q, attempt + 1)
        return None, "HTTP " + code
    return body, None


def parse(xml_bytes, q):
    out = []
    root = ET.fromstring(xml_bytes)
    for e in root.findall("a:entry", NS):
        raw_id = (e.findtext("a:id", "", NS) or "").strip()
        vid = raw_id.split("/abs/")[-1] if "/abs/" in raw_id else raw_id
        # strip version suffix from the last path segment only (keeps legacy cond-mat/0410079)
        head, sep, tail = vid.rpartition("/")
        base = head + sep + VSUF.sub("", tail)
        title = " ".join((e.findtext("a:title", "", NS) or "").split())
        abstract = " ".join((e.findtext("a:summary", "", NS) or "").split())
        authors = [" ".join((a.findtext("a:name", "", NS) or "").split())
                   for a in e.findall("a:author", NS)]
        catl = [c.attrib.get("term") for c in e.findall("a:category", NS) if c.attrib.get("term")]
        pub = (e.findtext("a:published", "", NS) or "").strip()
        upd = (e.findtext("a:updated", "", NS) or "").strip()
        pdf = ""
        for l in e.findall("a:link", NS):
            if l.attrib.get("title") == "pdf":
                pdf = l.attrib.get("href", "")
        out.append({
            "query": q, "title": title, "arxiv_id": base,
            "pdf_url": pdf, "abs_url": "https://arxiv.org/abs/" + vid,
            "categories": catl, "published": pub, "abstract": abstract,
            "raw": {"id": base, "versioned_id": vid, "title": title,
                    "authors": authors, "abstract": abstract,
                    "categories": catl, "published": pub, "updated": upd},
            "paper_key": "axv:" + base,
        })
    return out


uniq, errors = {}, []
for i, q in enumerate(queries):
    body, err = fetch(q)
    if err:
        errors.append({"query": q, "error": err})
        print("[%2d/%d] FAIL %-48s :: %s" % (i + 1, len(queries), q[:48], err), flush=True)
    else:
        items = parse(body, q)
        n_new = 0
        for it in items:
            if it["paper_key"] not in uniq:
                uniq[it["paper_key"]] = it
                n_new += 1
        print("[%2d/%d] ok n=%3d new=%3d :: %s" % (i + 1, len(queries), len(items), n_new, q[:48]), flush=True)
    if i < len(queries) - 1:
        time.sleep(3.1)

out = {
    "schema_version": "paper_recharge_mcp_v1",
    "recovery_of": "mcp_discovery_" + TODAY + ".json",
    "recovery_method": "direct_arxiv_api_via_curl_spaced_3.1s",
    "recovery_reason": "arXiv returns HTTP 406 to Python HTTP clients from this host (all query shapes); curl gets 200 on identical URL",
    "date": TODAY,
    "queries": queries, "categories": cats,
    "max_results_per_query": maxr, "sort_by": sortby,
    "status": "recovered_ok" if not errors else "recovered_partial",
    "n_queries_failed": len(errors),
    "candidates": list(uniq.values()),
    "errors": errors,
}
p = PR + "/mcp_discovery_" + TODAY + "_recovered.json"
json.dump(out, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("\nRECOVERED n_unique=%d failed_queries=%d -> %s" % (len(uniq), len(errors), p))
