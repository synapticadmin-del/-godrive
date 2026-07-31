/**
 * Byte-level file type identification for uploads.
 *
 * Both `POST /user/avatar` and `POST /captain/upload` put a file in R2 and later
 * serve it back, so the stored Content-Type has to come from the bytes — never
 * from the uploaded filename (attacker-controlled) and never from the declared
 * MIME type (just a string the client chose). Trusting either is what allowed a
 * `.html` to be stashed in the bucket and served back from the API origin.
 *
 * These helpers are deliberately pure and take a byte prefix rather than a
 * `File`/`Blob`, so the same implementation runs inside the Worker and inside a
 * Node test with no DOM. Read [SNIFF_HEAD_BYTES] from the front of the upload
 * once and pass the result to both predicates.
 *
 * Before this module the sniffer existed twice, copy-pasted between
 * `apps/api/src/routes/user.ts` and `apps/api/src/routes/captain.ts`, with no
 * tests on either copy — so the two drifted (only one of them learned about
 * PDF) and nothing would have caught a regression in security-critical byte
 * matching.
 */

/** The extensions this platform is willing to store. */
export type StoredFileExt = "jpg" | "png" | "webp" | "heic" | "heif" | "pdf";

/**
 * How many leading bytes the sniffers need. The deepest check reads the ISO-BMFF
 * brand at offsets 8..11, so 12 would be sufficient; 16 leaves headroom for a
 * new signature without having to re-slice the upload.
 */
export const SNIFF_HEAD_BYTES = 16;

/**
 * Canonical Content-Type per stored extension. The file routes replay a value
 * from this table, so it is the complete set of types they can ever serve back:
 * nothing a client sends can widen it.
 */
export const FILE_EXT_CONTENT_TYPE: Record<StoredFileExt, string> = {
  jpg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heif",
  pdf: "application/pdf",
};

/**
 * Which stored types are photographs. `POST /user/avatar` accepts only these;
 * `POST /captain/upload` accepts every type in the table above, because captains
 * legitimately hold PDF licences, insurance certificates and permits.
 *
 * A `Record` rather than a list on purpose: adding a format to [StoredFileExt]
 * fails to compile until it is classified here, so "is this an avatar-safe
 * image?" can never silently default to yes.
 */
const FILE_EXT_IS_IMAGE: Record<StoredFileExt, boolean> = {
  jpg: true,
  png: true,
  webp: true,
  heic: true,
  heif: true,
  pdf: false,
};

/** True when [ext] is a photograph rather than a document. */
export function isImageFileExt(ext: StoredFileExt): boolean {
  return FILE_EXT_IS_IMAGE[ext];
}

/**
 * True when the bytes open with an ISO base media file format box (`ftyp` at
 * offset 4) — the container HEIC, HEIF and AVIF all share.
 *
 * Brand-agnostic on purpose. The brand list in [sniffFileExt] is not exhaustive
 * (the registry is open-ended), so a caller that has an explicit `image/heic`
 * declaration may use this as a narrow escape hatch for an unusual encoder. It
 * still requires the file to *be* a container, which is what keeps it from
 * degrading into "trust the declared type".
 */
export function isIsoBmffContainer(head: Uint8Array): boolean {
  return (
    head.length >= 8 &&
    head[4] === 0x66 &&
    head[5] === 0x74 &&
    head[6] === 0x79 &&
    head[7] === 0x70
  );
}

/**
 * Identify a file from its leading bytes, or `null` when nothing matches.
 *
 * Out-of-range reads on a `Uint8Array` yield `undefined` at runtime, so every
 * comparison against a short buffer is simply false and no check can throw.
 */
export function sniffFileExt(head: Uint8Array): StoredFileExt | null {
  if (head.length < 4) return null;

  // JPEG: SOI (FF D8) followed by the start of any marker.
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return "jpg";

  // PNG: the full 8-byte signature, including the CRLF/EOF trap bytes.
  if (
    head[0] === 0x89 &&
    head[1] === 0x50 &&
    head[2] === 0x4e &&
    head[3] === 0x47 &&
    head[4] === 0x0d &&
    head[5] === 0x0a &&
    head[6] === 0x1a &&
    head[7] === 0x0a
  ) {
    return "png";
  }

  // WebP: a RIFF container whose form type is WEBP. Checking only `RIFF` would
  // also match WAV and AVI.
  if (
    head[0] === 0x52 &&
    head[1] === 0x49 &&
    head[2] === 0x46 &&
    head[3] === 0x46 &&
    head[8] === 0x57 &&
    head[9] === 0x45 &&
    head[10] === 0x42 &&
    head[11] === 0x50
  ) {
    return "webp";
  }

  // HEIC/HEIF: an ISO-BMFF container, with the brand deciding which.
  if (isIsoBmffContainer(head) && head.length >= 12) {
    const brand = String.fromCharCode(head[8], head[9], head[10], head[11]);
    if (brand === "heic" || brand === "heix" || brand === "hevc" || brand === "hevx") {
      return "heic";
    }
    if (brand === "mif1" || brand === "msf1" || brand === "heif") return "heif";
  }

  // PDF: `%PDF-` must sit at offset 0. The spec tolerates junk before the header
  // and some readers honour that, which makes a file that both opens as a PDF
  // and parses as HTML possible; refusing the offset-shifted case keeps those
  // two from ever overlapping.
  if (
    head[0] === 0x25 &&
    head[1] === 0x50 &&
    head[2] === 0x44 &&
    head[3] === 0x46 &&
    head[4] === 0x2d
  ) {
    return "pdf";
  }

  return null;
}
