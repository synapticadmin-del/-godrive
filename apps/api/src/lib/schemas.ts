import { z } from "zod";

export const requestOtpSchema = z
  .object({
    email: z.string().max(255).optional(),
    phone: z
      .string()
      .max(30)
      .optional()
      .transform((s) => (s ? s.replace(/[\s-]/g, "") : s)),
    // Admin accounts are provisioned manually in D1 by the team; the public
    // OTP flow must never be able to mint or enumerate an admin role.
    role: z.enum(["rider", "captain"]).default("rider"),
    name: z.string().max(120).optional(),
    turnstileToken: z.string().max(2048).optional(),
  })
  .refine((d) => Boolean(d.email || d.phone), {
    message: "email or phone required",
  });

export const verifyOtpSchema = z
  .object({
    email: z.string().max(255).optional(),
    phone: z
      .string()
      .max(30)
      .optional()
      .transform((s) => (s ? s.replace(/[\s-]/g, "") : s)),
    code: z.string().length(6).regex(/^\d{6}$/),
  })
  .refine((d) => Boolean(d.email || d.phone), {
    message: "email or phone required",
  });

export const refreshSchema = z.object({
  refreshToken: z.string().min(20).max(1024),
});

export const estimateTripSchema = z
  .object({
    pickupLat: z.number().min(-90).max(90),
    pickupLng: z.number().min(-180).max(180),
    dropoffLat: z.number().min(-90).max(90),
    dropoffLng: z.number().min(-180).max(180),
    city: z.string().max(60).optional(),
  })
  .refine((d) => d.pickupLat !== d.dropoffLat || d.pickupLng !== d.dropoffLng, {
    message: "pickup and dropoff must differ",
  });

export const createTripSchema = z.object({
  pickupLat: z.number().min(-90).max(90),
  pickupLng: z.number().min(-180).max(180),
  dropoffLat: z.number().min(-90).max(90),
  dropoffLng: z.number().min(-180).max(180),
  pickupAddress: z.string().max(300).optional(),
  dropoffAddress: z.string().max(300).optional(),
  city: z.string().max(60).optional(),
  offeredPrice: z.number().min(1).max(10000).optional(),
  paymentMethod: z.enum(["cash", "card", "wallet"]).default("cash"),
  promoCode: z.string().max(40).optional(),
  vehicleTypeId: z.string().max(40).optional(),
  scheduledFor: z.string().datetime().optional(),
  waypoints: z
    .array(
      z.object({
        lat: z.number().min(-90).max(90),
        lng: z.number().min(-180).max(180),
        address: z.string().max(300).optional(),
      }),
    )
    .max(5)
    .optional(),
});

export const createBidSchema = z.object({
  counterPrice: z.number().min(1).max(10000),
});

export const acceptBidSchema = z.object({
  bidId: z.string().min(1),
});

export const deviceTokenSchema = z.object({
  token: z.string().min(20).max(2048),
  platform: z.enum(["android", "ios", "web"]).default("android"),
  appRole: z.enum(["rider", "captain"]).optional(),
});

export const sosSchema = z.object({
  tripId: z.string().max(60).optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  reason: z.string().max(300).optional(),
});

export const tripShareSchema = z.object({
  tripId: z.string().min(1),
  ttlMinutes: z.number().int().min(5).max(10080).default(1440),
});

export const intercityRouteSchema = z.object({
  originCity: z.string().min(1).max(80),
  destinationCity: z.string().min(1).max(80),
  distanceKm: z.number().min(1).max(2000).optional(),
  basePrice: z.number().min(1).max(5000),
  vehicleTypeId: z.string().optional(),
  durationMinutes: z.number().int().min(1).max(1440).optional(),
});

export const intercityScheduleSchema = z.object({
  routeId: z.string().min(1),
  departAt: z.string().datetime(),
  seatsTotal: z.number().int().min(1).max(50).default(4),
});

export const intercityBookingSchema = z.object({
  scheduleId: z.string().min(1),
  seats: z.number().int().min(1).max(10).default(1),
  pickupStation: z.string().max(120).optional(),
  dropoffStation: z.string().max(120).optional(),
  paymentMethod: z.enum(["cash", "wallet", "card"]).default("cash"),
});

export const companySchema = z.object({
  name: z.string().min(1).max(120),
  legalName: z.string().max(200).optional(),
  taxId: z.string().max(60).optional(),
  contactEmail: z.string().email().max(200).optional(),
  contactPhone: z.string().max(30).optional(),
  creditLimit: z.number().min(0).max(10_000_000).default(0),
  monthlyInvoiceDay: z.number().int().min(1).max(28).default(1),
});

export const companyEmployeeSchema = z.object({
  companyId: z.string().min(1),
  userId: z.string().min(1),
  costCenter: z.string().max(120).optional(),
  spendLimitMonth: z.number().min(0).max(100_000).default(0),
  allowedVehicleTypes: z.array(z.string()).optional(),
  allowedHours: z.object({ from: z.string(), to: z.string() }).optional(),
});

export const cancelTripSchema = z.object({
  reason: z.string().max(200).optional(),
});

export const rateTripSchema = z.object({
  score: z.number().int().min(1).max(5),
  comment: z.string().max(500).optional(),
});

export const captainProfileSchema = z.object({
  vehicleMake: z.string().max(60).optional(),
  vehicleModel: z.string().max(60).optional(),
  vehiclePlate: z.string().max(20).optional(),
  vehicleColor: z.string().max(30).optional(),
  licenseNumber: z.string().max(60).optional(),
  name: z.string().max(120).optional(),
  phone: z.string().max(30).optional(),
  // Four-step onboarding (migration 0014): Arabic four-part name, birth date,
  // national ID number, licence expiry and vehicle year. All optional so the
  // flow can save partial progress one step at a time.
  firstName: z.string().max(60).optional(),
  fatherName: z.string().max(60).optional(),
  grandfatherName: z.string().max(60).optional(),
  familyName: z.string().max(60).optional(),
  birthDate: z.string().max(20).optional(),
  nationalIdNumber: z.string().max(20).optional(),
  licenseExpiry: z.string().max(20).optional(),
  vehicleYear: z.number().int().min(1980).max(2100).optional(),
});

export const captainOnlineSchema = z.object({
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
  online: z.boolean().default(true),
  city: z.string().max(60).optional(),
});

export const captainLocationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  heading: z.number().min(0).max(360).optional(),
  tripId: z.string().max(60).optional(),
  city: z.string().max(60).optional(),
});

// Captain document registration: the optional identity fields the captain
// fills in at upload time. All are optional so a captain can still upload a
// bare photo the way the flow worked before, and so document types without
// the data (a criminal-record certificate carries no expiry) stay valid.
export const documentRegisterSchema = z.object({
  // Document type id from the admin-managed `document_types` catalog. This is
  // deliberately a slug rather than a fixed enum: the catalog is data-driven,
  // so a type added from the dashboard (e.g. vehicle_photo, profile_photo)
  // must register without shipping a new API build. POST /captain/documents
  // validates the id against the catalog and refuses deactivated types.
  type: z.string().min(1).max(60).regex(/^[a-z0-9_]+$/),
  r2Key: z.string().min(1).max(500),
  // Four-part legal name as printed on the national ID card.
  holderFullName: z.string().max(200).optional(),
  // National ID number (14 digits in Egypt; kept loose for other markets).
  nationalIdNumber: z.string().max(30).optional(),
  // Document expiry, as YYYY-MM-DD from a date picker or a full ISO stamp.
  expiresAt: z
    .union([
      z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      z.string().datetime(),
      z.null(),
    ])
    .optional(),
});

export const pricingUpdateSchema = z.object({
  currency: z.string().max(3).optional(),
  baseFare: z.number().min(0).max(1000).optional(),
  perKm: z.number().min(0).max(100).optional(),
  perMin: z.number().min(0).max(100).optional(),
  bookingFee: z.number().min(0).max(1000).optional(),
  minFare: z.number().min(0).max(1000).optional(),
  commissionRate: z.number().min(0).max(1).optional(),
});

export const validatePromoSchema = z.object({
  code: z.string().min(3).max(40),
  tripEstimate: z.number().min(0).max(10000).optional(),
});

// Accepts either camelCase or the snake_case the admin UI actually sends, and
// tolerates explicit nulls for "no limit" / "no expiry".
const optionalPositiveInt = z
  .union([z.number().int().min(1).max(1_000_000), z.null()])
  .optional();

// The admin uses <input type="date">, which yields "2026-08-01". Accept that
// as well as a full ISO timestamp, and normalise to an ISO string so the
// stored value is comparable with the runtime's new Date(...) checks.
const optionalExpiry = z
  .union([
    z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD")
      // End of the chosen day, so a code is valid for the whole date picked.
      .transform((s) => new Date(`${s}T23:59:59.999Z`).toISOString()),
    z.string().datetime(),
    z.null(),
  ])
  .optional();

export const createPromoSchema = z
  .object({
    code: z
      .string()
      .min(3)
      .max(40)
      .transform((s) => s.toUpperCase()),
    type: z.enum(["percent", "fixed"]).default("percent"),
    value: z.number().min(0).max(1_000_000),
    maxUses: optionalPositiveInt,
    max_uses: optionalPositiveInt,
    expiresAt: optionalExpiry,
    expires_at: optionalExpiry,
  })
  // A percentage discount above 100% would make the fare negative; a fixed
  // discount has no such ceiling, which is why the cap is per-type.
  .refine((d) => d.type !== "percent" || d.value <= 100, {
    message: "percent discount cannot exceed 100",
    path: ["value"],
  })
  // Collapse the two accepted spellings into the canonical camelCase fields.
  .transform((d) => ({
    code: d.code,
    type: d.type,
    value: d.value,
    maxUses: d.maxUses ?? d.max_uses ?? null,
    expiresAt: d.expiresAt ?? d.expires_at ?? null,
  }));

export const savedPlaceSchema = z.object({
  label: z.string().min(1).max(60),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  address: z.string().max(300).optional(),
});

// PUT /admin/system-config — every field optional so the admin form can send a
// partial patch. Bounds mirror the min/max already enforced by the number
// inputs in SettingsPage, so a value that passes client validation also passes
// here; anything outside the range is a hand-crafted request and is rejected.
//
// Commission is expressed as a whole percentage here (the admin types "20")
// while pricing_rules.commission_rate stores a 0-1 fraction. Keeping the admin
// unit as a percentage avoids a confusing 0.2 in the UI; the API converts when
// seeding a new city.
export const systemConfigUpdateSchema = z.object({
  defaultCommissionPct: z.number().min(0).max(100).optional(),
  searchRadiusKm: z.number().min(1).max(30).optional(),
  freeCancelMin: z.number().int().min(0).max(120).optional(),
  cancelFeeEgp: z.number().min(0).max(1000).optional(),
  // Egyptian numbers arrive as "+201xxxxxxxxx"; allow the common local forms
  // rather than pinning a single country to keep support numbers editable.
  supportPhone: z
    .string()
    .max(30)
    .regex(/^\+?[\d\s-]{6,}$/, "expected a phone number")
    .transform((s) => s.replace(/[\s-]/g, ""))
    .optional(),
  supportWhatsapp: z
    .string()
    .max(30)
    .regex(/^\+?[\d\s-]{6,}$/, "expected a phone number")
    .transform((s) => s.replace(/[\s-]/g, ""))
    .optional(),
  autoAssign: z.boolean().optional(),
});

export type RequestOtpInput = z.infer<typeof requestOtpSchema>;
export type VerifyOtpInput = z.infer<typeof verifyOtpSchema>;
export type CreateTripInput = z.infer<typeof createTripSchema>;
export type CaptainProfileInput = z.infer<typeof captainProfileSchema>;
export type CaptainLocationInput = z.infer<typeof captainLocationSchema>;
export type PricingUpdateInput = z.infer<typeof pricingUpdateSchema>;
export type SystemConfigUpdateInput = z.infer<typeof systemConfigUpdateSchema>;
