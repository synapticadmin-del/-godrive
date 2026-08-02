/**
 * Lets the harness import the API's own `.ts` modules unmodified.
 *
 * The source uses extensionless relative specifiers (`./utils`), which Node's
 * ESM resolver does not complete on its own. Node >= 22.6 strips the types; this
 * hook only supplies the extension.
 */
import { registerHooks } from "node:module";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith(".") && !/\.(ts|mjs|js|json)$/.test(specifier)) {
      try {
        const base = new URL(specifier, context.parentURL);
        for (const ext of [".ts", "/index.ts"]) {
          const candidate = new URL(base.href + ext);
          if (existsSync(fileURLToPath(candidate))) {
            return { url: candidate.href, shortCircuit: true };
          }
        }
      } catch {
        /* fall through to the default resolver */
      }
    }
    return nextResolve(specifier, context);
  },
});
