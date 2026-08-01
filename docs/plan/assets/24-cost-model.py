# Synaptic Go cost model — all rates from Cloudflare Workers Paid plan, Aug 2026
R = dict(
 wk_req=(10e6,0.30), cpu=(30e6,0.02),
 d1_r=(25e9,0.001), d1_w=(50e6,1.00), d1_stor=(5,0.75),
 do_req=(1e6,0.15), do_dur=(400e3,12.50), do_w=(50e6,1.00), do_stor=(5,0.20),
 kv_r=(10e6,0.50), kv_w=(1e6,5.00),
 q=(1e6,0.40), r2_stor=(10,0.015), r2_a=(1e6,4.50))
def bill(k,units):
    inc,rate=R[k]; return max(0.0,units-inc)*rate/(1e6 if k not in('d1_stor','do_stor','r2_stor') else 1)

# ── Per-trip assumptions (A1..A8) ────────────────────────────────────
TRIP_MIN=20; SPEED_TRIP=20; SPEED_IDLE=20   # km/h
DF_TRIP=10; DF_IDLE=50                      # metres (captain_state.dart:621,625)
RATE_CAP=30                                 # /min  (captain.ts:194)
IDLE_RATIO=1.0                              # 1 idle min per trip min (50% utilisation)
fixes_trip=min(RATE_CAP*TRIP_MIN, (SPEED_TRIP*1000/60*TRIP_MIN)/DF_TRIP)
idle_min=TRIP_MIN*IDLE_RATIO
fixes_idle=min(RATE_CAP*idle_min, (SPEED_IDLE*1000/60*idle_min)/DF_IDLE)
pings=fixes_trip+fixes_idle
path_pts=TRIP_MIN*60/30                     # 30s gate (captain.ts:245)
LIFECYCLE_W=36; LIFECYCLE_R=20; LIFECYCLE_REQ=30; OFFERED=10

# ── Per completed trip ───────────────────────────────────────────────
d1_w  = fixes_trip*2 + fixes_idle*1 + path_pts + LIFECYCLE_W
d1_r  = fixes_trip*2 + LIFECYCLE_R
do_req= fixes_trip*2 + fixes_idle*1 + 9 + 1 + OFFERED + 21
do_w  = pings*1 + 7
kv_w  = pings + LIFECYCLE_REQ               # rateLimit.ts:50 — 1 PUT per limited req
kv_r  = kv_w                                # rateLimit.ts:29 — 1 GET per limited req
wk_req= pings + LIFECYCLE_REQ + 40 + 30
q_ops = (OFFERED + 8) * 3                   # 3 ops/message (write+read+delete)

print(f"{'PER-TRIP UNIT MODEL':<44}{'value':>12}   formula")
rows=[("captain fixes on-trip",fixes_trip,f"min({RATE_CAP}/min×{TRIP_MIN}min, {SPEED_TRIP}km/h÷{DF_TRIP}m)"),
 ("captain fixes idle",fixes_idle,f"{SPEED_IDLE}km/h×{idle_min:.0f}min÷{DF_IDLE}m"),
 ("path points",path_pts,"20min ÷ 30s gate"),
 ("D1 rows written",d1_w,"trip×2 + idle×1 + path + 36 lifecycle"),
 ("D1 rows read",d1_r,"trip×2 + 20"),
 ("DO requests",do_req,"trip×2 + idle×1 + 9 nearby + 1 sched + 10 inbox + 21"),
 ("DO storage writes",do_w,"1 GeoCell put/ping + 7 room state"),
 ("KV writes",kv_w,"1 PUT per rate-limited request"),
 ("KV reads",kv_r,"1 GET per rate-limited request"),
 ("Worker requests",wk_req,"pings + lifecycle + polls"),
 ("Queue operations",q_ops,"18 msgs × 3 ops")]
for n,v,f in rows: print(f"{n:<44}{v:>12,.0f}   {f}")

# ── Extrapolation ────────────────────────────────────────────────────
ADMIN_OPS=2; ADMIN_H=8
admin_req_mo=ADMIN_OPS*(450*2+450*2)*ADMIN_H*30
# admin D1 rows scanned per dashboard+livemap tick, at 3 tiers of table size
print("\n"+"="*104)
print(f"{'MONTHLY COST':<26}"+"".join(f"{t:>26}" for t in ["1,000 trips/day","10,000 trips/day","50,000 trips/day"]))
print("="*104)
tiers=[1000,10000,50000]; totals=[]
lines={}
for td in tiers:
    m=td*30
    trips_tbl=td*365          # 1yr accumulation
    u={'wk_req':wk_req*m+admin_req_mo,'cpu':(wk_req*m)*8,
       'd1_r':d1_r*m + admin_req_mo/2*(min(trips_tbl,10e6)*3),
       'd1_w':d1_w*m,'do_req':do_req*m,'do_w':do_w*m,
       'kv_r':kv_r*m,'kv_w':kv_w*m,'q':q_ops*m,
       'do_dur':500*0.125*3600*30*0.0002,      # hibernating WS
       'd1_stor':min(trips_tbl*4.5/1e6*1024,10240)/1024, 'r2_stor':td*0.05/1000}
    c={k:bill(k,v) for k,v in u.items()}
    c['base']=5.0
    for k,v in c.items(): lines.setdefault(k,[]).append(v)
    totals.append(sum(c.values()))
label={'base':'Workers base','wk_req':'Worker requests','cpu':'Worker CPU','d1_r':'D1 rows read',
 'd1_w':'D1 rows written','d1_stor':'D1 storage','do_req':'DO requests','do_dur':'DO duration (hibernating)',
 'do_w':'DO storage writes','kv_r':'KV reads','kv_w':'KV writes','q':'Queues','r2_stor':'R2 storage'}
for k in ['base','wk_req','cpu','d1_r','d1_w','d1_stor','do_req','do_dur','do_w','kv_r','kv_w','q','r2_stor']:
    print(f"{label[k]:<26}"+"".join(f"${v:>25,.2f}" for v in lines[k]))
print("-"*104)
print(f"{'TOTAL / month':<26}"+"".join(f"${v:>25,.2f}" for v in totals))
print(f"{'Infra cost per trip':<26}"+"".join(f"${v/(t*30):>25,.4f}" for v,t in zip(totals,tiers)))
print(f"{'Commission @15% of EGP80':<26}"+"".join(f"{'$0.2400':>26}" for _ in tiers))
print(f"{'Infra as % of commission':<26}"+"".join(f"{v/(t*30)/0.24*100:>25.1f}%" for v,t in zip(totals,tiers)))

# D1 storage ceiling
print("\n── D1 10 GB CEILING ──")
for geom_kb in (2,5):
    row_kb=0.5+geom_kb
    for td in tiers:
        days=10*1024*1024/(td*(row_kb+ (40*0.12)))
        print(f"  route_geometry {geom_kb}KB → row {row_kb+4.8:.1f}KB/trip incl. path pts @ {td:>5,}/day → D1 full in {days:>6,.0f} days ({days/365:.1f} yr)")

print("\n"+"="*104)
print("OPTIMISED SCENARIO — after P0 fixes")
print("="*104)
# P0-1 KV-cache admin stats 30s + sargable dates + indexes  -> admin D1 scans ~ -99%
# P0-2 rate limiter off KV for hot paths                    -> KV writes -95%
# P0-3 drop unconditional UPDATE captains/trips per ping    -> D1 writes -85%
# P0-4 GeoCell 15s coalescing gate                          -> DO storage writes -80%
for td in tiers:
    m=td*30; trips_tbl=td*365
    base={'wk_req':wk_req*m+admin_req_mo,'cpu':(wk_req*m)*8,
      'd1_r':d1_r*m + admin_req_mo/2*(min(trips_tbl,10e6)*3)*0.01,
      'd1_w':d1_w*m*0.15,'do_req':do_req*m,'do_w':do_w*m*0.20,
      'kv_r':kv_r*m*0.05,'kv_w':kv_w*m*0.05,'q':q_ops*m,'do_dur':1350,
      'd1_stor':min(trips_tbl*0.6/1e6*1024,10240)/1024,'r2_stor':td*0.05/1000}
    tot=sum(bill(k,v) for k,v in base.items())+5.0
    i=tiers.index(td)
    print(f"  {td:>6,} trips/day:  ${totals[i]:>10,.2f}  ->  ${tot:>9,.2f}   "
          f"saving ${totals[i]-tot:>9,.2f}/mo ({(1-tot/totals[i])*100:>4.1f}%)   "
          f"per-trip ${tot/(td*30):.4f}")
