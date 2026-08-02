// Resolve the repo's extensionless relative imports ("./money") to "./money.ts"
// so the REAL source files run unmodified. Nothing is rewritten on disk.
export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("./") || specifier.startsWith("../")) {
    try {
      return await nextResolve(specifier, context);
    } catch (e) {
      return await nextResolve(specifier + ".ts", context);
    }
  }
  return nextResolve(specifier, context);
}
