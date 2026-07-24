from fq073_customs_probe import *
BASES = {
 "nitemtrade_http" : "http://apis.data.go.kr/1220000/nitemtrade/getNitemtradeList",
 "nitemtrade_https": "https://apis.data.go.kr/1220000/nitemtrade/getNitemtradeList",
 "Itemtrade_https" : "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList",
}
P = {"strtYymm":"202401","endYymm":"202401","cntyCd":"US","hsSgn":"8542"}
for tag, b in BASES.items():
    for kf in ("enc","dec"):
        show(tag, b, P, kf, n=600)
