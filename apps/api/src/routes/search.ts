import { Hono } from 'hono';
import { authMiddleware, type AppEnv } from '../middleware/auth';

export const searchRoutes = new Hono<AppEnv>();

searchRoutes.use('*', authMiddleware);

searchRoutes.get('/admin/search', async (c) => {
  const user = c.get('user');
  if (user.role !== 'admin') {
    return c.json({ error: 'صلاحيات أدمن مطلوبة' }, 403);
  }

  const q = (c.req.query('q') || '').trim().toLowerCase();
  if (!q) {
    return c.json({ results: { captains: [], riders: [], trips: [] } });
  }

  const term = `%${q}%`;

  // 1. Search Users (Captains & Riders)
  const usersRes = await c.env.DB.prepare(`
    SELECT u.id, u.email, u.name, u.phone, u.role, c.approval_status, c.vehicle_plate
    FROM users u
    LEFT JOIN captains c ON u.id = c.user_id
    WHERE LOWER(u.name) LIKE ? OR LOWER(u.email) LIKE ? OR u.phone LIKE ? OR LOWER(c.vehicle_plate) LIKE ? OR u.id LIKE ?
    LIMIT 10
  `).bind(term, term, term, term, term).all();

  const captains = (usersRes.results || []).filter((u: any) => u.role === 'captain');
  const riders = (usersRes.results || []).filter((u: any) => u.role === 'rider');

  // 2. Search Trips
  const tripsRes = await c.env.DB.prepare(`
    SELECT id, status, city, pickup_address, dropoff_address, estimated_fare, created_at
    FROM trips
    WHERE LOWER(id) LIKE ? OR LOWER(pickup_address) LIKE ? OR LOWER(dropoff_address) LIKE ? OR LOWER(city) LIKE ?
    LIMIT 10
  `).bind(term, term, term, term).all();

  return c.json({
    results: {
      captains,
      riders,
      trips: tripsRes.results || [],
    },
  });
});
