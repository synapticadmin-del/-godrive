/**
 * Client-side mirror of the API's RBAC matrix (apps/api/src/lib/staff.ts).
 *
 * The server is the enforcement point — requireStaff re-reads the role from
 * D1 on every request. Everything here is presentation: which nav items and
 * pages a role gets to see. If this file drifts from the API matrix the
 * worst outcome is a hidden page that is still callable, or a visible page
 * whose every request answers 403 — never an actual privilege.
 */

export const STAFF_ROLES = ['owner', 'admin', 'assistant', 'support', 'finance'] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export type StaffPermission =
  | 'stats:view'
  | 'analytics:view'
  | 'captains:view'
  | 'captains:manage'
  | 'documents:view'
  | 'documents:review'
  | 'trips:view'
  | 'users:view'
  | 'safety:view'
  | 'audit:view'
  | 'pricing:manage'
  | 'config:manage'
  | 'payouts:manage'
  | 'staff:manage';

const ALL_PERMISSIONS: readonly StaffPermission[] = [
  'stats:view',
  'analytics:view',
  'captains:view',
  'captains:manage',
  'documents:view',
  'documents:review',
  'trips:view',
  'users:view',
  'safety:view',
  'audit:view',
  'pricing:manage',
  'config:manage',
  'payouts:manage',
  'staff:manage',
];

const GRANTS: Record<Exclude<StaffRole, 'owner'>, readonly StaffPermission[]> = {
  admin: [
    'stats:view',
    'analytics:view',
    'captains:view',
    'captains:manage',
    'documents:view',
    'documents:review',
    'trips:view',
    'users:view',
    'safety:view',
    'audit:view',
  ],
  assistant: ['stats:view', 'captains:view', 'documents:view', 'documents:review', 'trips:view', 'users:view'],
  support: ['stats:view', 'trips:view', 'users:view', 'safety:view'],
  finance: ['stats:view', 'analytics:view', 'payouts:manage'],
};

export function isStaffRole(value: string | null | undefined): value is StaffRole {
  return typeof value === 'string' && (STAFF_ROLES as readonly string[]).includes(value);
}

export function permissionsFor(role: StaffRole | null | undefined): readonly StaffPermission[] {
  if (!role) return [];
  if (role === 'owner') return ALL_PERMISSIONS;
  return GRANTS[role];
}

export function hasPermission(role: StaffRole | null | undefined, permission: StaffPermission): boolean {
  return permissionsFor(role).includes(permission);
}

/** Arabic labels for the role badges and the staff-management dropdown. */
export const ROLE_LABELS_AR: Record<StaffRole, string> = {
  owner: 'المالك',
  admin: 'مدير',
  assistant: 'مساعد',
  support: 'دعم فني',
  finance: 'محاسب',
};

/** One-line Arabic description per role, shown in the staff page. */
export const ROLE_DESCRIPTIONS_AR: Record<StaffRole, string> = {
  owner: 'صلاحيات كاملة، بما فيها إدارة الموظفين والأدوار والتسعير',
  admin: 'العمليات: الرحلات والكباتن والتوثيق والاستغاثات — بدون المالية والتسعير',
  assistant: 'متابعة لوحة العمليات ومراجعة الوثائق فقط',
  support: 'البحث عن المستخدمين والرحلات ومتابعة الاستغاثات',
  finance: 'طلبات السحب والتحليلات المالية فقط',
};

/**
 * Page → permission map. App.tsx uses it to gate routes; the Sidebar uses it
 * to hide items. A page that needs several endpoints lists the permission
 * that gates its primary feed.
 */
export const PAGE_PERMISSIONS: Record<string, StaffPermission> = {
  '/': 'stats:view',
  '/live': 'stats:view',
  '/captains': 'captains:view',
  '/verification': 'documents:view',
  '/safety': 'safety:view',
  '/trips': 'trips:view',
  '/users': 'users:view',
  '/analytics': 'analytics:view',
  '/pricing': 'pricing:manage',
  '/payouts': 'payouts:manage',
  '/audit': 'audit:view',
  '/settings': 'config:manage',
  '/staff': 'staff:manage',
};

/** First route a role may open — used to redirect forbidden paths. */
export function firstAllowedPath(role: StaffRole | null | undefined): string {
  for (const [path, permission] of Object.entries(PAGE_PERMISSIONS)) {
    if (hasPermission(role, permission)) return path;
  }
  return '/';
}

export function canAccess(role: StaffRole | null | undefined, path: string): boolean {
  const permission = PAGE_PERMISSIONS[path];
  if (!permission) return true; // unknown path — the router's catch-all handles it
  return hasPermission(role, permission);
}
