import { DurableObject } from "cloudflare:workers";

type Session = {
  ws: WebSocket;
  userId: string;
};

/**
 * One DO per online captain for push offers.
 * Captains connect via /ws/captain/offers?token=
 * API pushes trip.offer events here by userId.
 */
export class CaptainInbox extends DurableObject<Env> {
  sessions: Map<WebSocket, Session> = new Map();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/push" && request.method === "POST") {
      const body = await request.json<Record<string, unknown>>();
      this.broadcast(body);
      return Response.json({ ok: true, clients: this.sessions.size });
    }

    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      this.ctx.acceptWebSocket(server);

      const userId = url.searchParams.get("userId") || "unknown";
      this.sessions.set(server, { ws: server, userId });

      server.send(
        JSON.stringify({
          type: "connected",
          channel: "captain.inbox",
          userId,
        }),
      );

      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response("CaptainInbox: WebSocket or POST /push", { status: 400 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    if (typeof message !== "string") return;
    try {
      const data = JSON.parse(message) as { type?: string };
      if (data.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", t: Date.now() }));
      }
    } catch {
      ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
    }
  }

  async webSocketClose(ws: WebSocket) {
    this.sessions.delete(ws);
  }

  async webSocketError(ws: WebSocket) {
    this.sessions.delete(ws);
  }

  private broadcast(payload: unknown) {
    const raw = JSON.stringify(payload);
    for (const [socket] of this.sessions) {
      try {
        socket.send(raw);
      } catch {
        this.sessions.delete(socket);
      }
    }
    for (const ws of this.ctx.getWebSockets()) {
      if (this.sessions.has(ws)) continue;
      try {
        ws.send(raw);
      } catch {
        /* ignore */
      }
    }
  }
}
