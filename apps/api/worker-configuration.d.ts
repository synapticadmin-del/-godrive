interface Env {
  DB: D1Database;
  SESSIONS: KVNamespace;
  FILES: R2Bucket;
  TRIP_ROOM: DurableObjectNamespace;
  GEO_CELL: DurableObjectNamespace;
  CAPTAIN_INBOX: DurableObjectNamespace;
  // Queue producer for async notifications
  NOTIFICATIONS?: Queue<NotificationMessage>;
  APP_NAME: string;
  APP_VERSION: string;
  DEV_OTP: string;
  DEFAULT_CITY: string;
  JWT_ISSUER: string;
  JWT_SECRET: string;
  OSRM_URL?: string;
  // WhatsApp Business API (Meta Cloud or 360dialog)
  WHATSAPP_TOKEN?: string;
  WHATSAPP_PHONE_NUMBER_ID?: string;
  WHATSAPP_TEMPLATE_LANG?: string;
  // Email OTP via Resend (or Brevo-compatible)
  EMAIL_RESEND_API_KEY?: string;
  EMAIL_FROM?: string;
  // FCM HTTP v1 service-account credentials
  FCM_CLIENT_EMAIL?: string;
  FCM_PRIVATE_KEY?: string;
  FCM_PROJECT_ID?: string;
  // Paymob (Accept) credentials
  PAYMOB_API_KEY?: string;
  PAYMOB_HMAC?: string;
  PAYMOB_IFRAME_ID?: string;
  // Cloudflare Turnstile (secret only here; site key goes in [vars])
  TURNSTILE_SECRET_KEY?: string;
  TURNSTILE_SITE_KEY?: string;
  ADMIN_SETUP_SECRET?: string;
}

interface NotificationMessage {
  userId: string;
  topic: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}