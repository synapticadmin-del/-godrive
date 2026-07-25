# Synaptic Go — Operating Cost

## Target budgets

| Stage | Daily trips | Monthly tech cost |
|-------|-------------|-------------------|
| Dev / demo | < 50 | $0–20 |
| Soft launch | 100–250 | $30–70 |
| Growth | 500–1000 | $100–200 |
| Scale | 2000+ | $300–800+ |

Recommended launch budget: **$50–100 / month**.

## Cost drivers

1. SMS OTP (avoid early)
2. Google Maps (avoid early)
3. Unthrottled GPS writes
4. Online payment fees (% of GMV)

## Guardrails baked into product

- Location every 4–5s on trip only
- Path samples to D1 every 30–60s
- OSM / MapLibre first
- Email OTP first
- Cash payments first
