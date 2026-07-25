# Synaptic Go — Stack

## Overview

Cloudflare-first ride-hailing stack optimized for low operating cost in Egypt.

## Backend

| Layer | Technology | Role |
|-------|------------|------|
| Compute | **Cloudflare Workers** | API gateway, auth, business logic |
| Framework | **Hono** (TypeScript) | Routing, middleware |
| SQL DB | **D1** | Users, trips, payments, ratings, pricing |
| Realtime | **Durable Objects** | TripRoom (live trip), GeoCell (matching) |
| Cache / sessions | **Workers KV** | Sessions, rate limits, geocode cache |
| Files | **R2** | Avatars, driver docs, receipts |
| Jobs | **Queues** | Notifications, settlements |
| AI (optional) | **Workers AI** | ETA hints / fraud later |

## Frontends

| App | Tech | Deploy |
|-----|------|--------|
| Rider | Flutter | APK / Play Store |
| Captain | Flutter | APK / Play Store |
| Admin | React + Vite + TypeScript | Cloudflare Pages |

## Maps & Location

| Need | Solution | Cost focus |
|------|----------|------------|
| Map UI | `flutter_map` / OSM tiles | Free/cheap |
| GPS | Device GPS | Free |
| Live location | WebSocket via Durable Objects | Throttled 4–5s |
| Routing / ETA | OSRM (Egypt extract) later | ~$5–12 VPS |
| Geocoding | Cached reverse geocode | Free tier + cache |

## Auth

- Email OTP (dev mode returns OTP in response when `DEV_OTP=true`)
- JWT access tokens
- Roles: `rider` | `captain` | `admin`

## Domains

| Service | Hostname |
|---------|----------|
| API | `api.synapticstudio.tech` |
| Admin | `admin.synapticstudio.tech` |
| Rider web (optional) | `go.synapticstudio.tech` |
| Captain web (optional) | `captain.synapticstudio.tech` |

## Payments (MVP)

- Cash to captain first
- Platform commission recorded on trip
- Online payments (Paymob/Stripe) later via webhooks

## Notifications

- Phase 1: in-app + WebSocket
- Phase 2: Firebase Cloud Messaging (FCM)

## Why this stack

1. Scale-to-zero → low idle cost
2. Durable Objects → perfect for live trip rooms
3. R2 free egress → cheap files
4. Flutter → one codebase Android/iOS
5. Pages → free admin hosting with custom domain
