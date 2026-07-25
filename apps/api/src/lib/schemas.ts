import { z } from "zod";

export const requestOtpSchema = z
  .object({
    email: z.string().max(255).optional(),
    phone: z
      .string()
      .max(30)
      .optional()
      .transform((s) => (s ? s.replace(/[\s-]/g, "") : s)),
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
  tripId: z.string().min(1).max(60),
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

export const pricingUpdateSchema = z.object({
  currency: z.string().max(3).optional(),
  baseFare: z.number().min(0).max(1000).optional(),
  perKm: z.number().min(0).max(100).optional(),
  perMin: z.number().min(0).max(100).optional(),
  bookingFee: z.number().min(0).max(100).optional(),
  minFare: z.number().min(0).max(1000).optional(),
  commissionRate: z.number().min(0).max(1).optional(),
});

export const validatePromoSchema = z.object({
  code: z.string().min(3).max(40),
  tripEstimate: z.number().min(0).max(10000).optional(),
});

export const createPromoSchema = z.object({
  code: z
    .string()
    .min(3)
    .max(40)
    .transform((s) => s.toUpperCase()),
  type: z.enum(["percent", "fixed"]).default("percent"),
  value: z.number().min(0).max(100),
  maxUses: z.number().int().min(1).max(1_000_000).optional(),
  expiresAt: z.string().datetime().optional(),
});

export const savedPlaceSchema = z.object({
  label: z.string().min(1).max(60),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  address: z.string().max(300).optional(),
});

export type RequestOtpInput = z.infer<typeof requestOtpSchema>;
export type VerifyOtpInput = z.infer<typeof verifyOtpSchema>;
export type CreateTripInput = z.infer<typeof createTripSchema>;
export type CaptainProfileInput = z.infer<typeof captainProfileSchema>;
export type CaptainLocationInput = z.infer<typeof captainLocationSchema>;
export type PricingUpdateInput = z.infer<typeof pricingUpdateSchema>;
