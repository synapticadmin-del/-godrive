import { describe, it, expect } from "vitest";
import {
  FILE_EXT_CONTENT_TYPE,
  isImageFileExt,
  isIsoBmffContainer,
  SNIFF_HEAD_BYTES,
  sniffFileExt,
  type StoredFileExt,
} from "./index";

/** Build a head buffer from bytes, padded to the length a caller would read. */
const head = (...bytes: number[]): Uint8Array => {
  const buf = new Uint8Array(SNIFF_HEAD_BYTES);
  buf.set(bytes.slice(0, SNIFF_HEAD_BYTES));
  return buf;
};

/** Build a head buffer from a latin-1 string, e.g. "%PDF-1.4". */
const headOf = (text: string, pad = true): Uint8Array => {
  const bytes = [...text].map((ch) => ch.charCodeAt(0));
  if (!pad) return new Uint8Array(bytes);
  return head(...bytes);
};

/** An ISO-BMFF `ftyp` box with the given 4-character brand. */
const ftyp = (brand: string): Uint8Array =>
  head(0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, ...[...brand].map((c) => c.charCodeAt(0)));

const JPEG = head(0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46);
const PNG = head(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d);
const WEBP = head(0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50);
const PDF = headOf("%PDF-1.7\n");

describe("sniffFileExt: accepts the formats the platform stores", () => {
  it("identifies JPEG from the SOI marker", () => {
    expect(sniffFileExt(JPEG)).toBe("jpg");
  });

  it("identifies PNG from the full 8-byte signature", () => {
    expect(sniffFileExt(PNG)).toBe("png");
  });

  it("identifies WebP from RIFF + the WEBP form type", () => {
    expect(sniffFileExt(WEBP)).toBe("webp");
  });

  it("identifies PDF from %PDF- at offset 0", () => {
    expect(sniffFileExt(PDF)).toBe("pdf");
  });

  it.each(["heic", "heix", "hevc", "hevx"])("maps the %s ISO-BMFF brand to heic", (brand) => {
    expect(sniffFileExt(ftyp(brand))).toBe("heic");
  });

  it.each(["mif1", "msf1", "heif"])("maps the %s ISO-BMFF brand to heif", (brand) => {
    expect(sniffFileExt(ftyp(brand))).toBe("heif");
  });
});

describe("sniffFileExt: rejects what must never be stored", () => {
  it("rejects HTML, the payload the byte check exists to stop", () => {
    expect(sniffFileExt(headOf("<html><script>x</script>"))).toBeNull();
  });

  it("rejects SVG, which is a script-capable image format", () => {
    expect(sniffFileExt(headOf("<svg xmlns='http://www.w"))).toBeNull();
  });

  it("rejects a PDF whose header is not at offset 0", () => {
    // The spec tolerates leading junk and some readers honour it, so a file that
    // opens as a PDF *and* parses as HTML would otherwise be storable.
    expect(sniffFileExt(headOf("XX%PDF-1.4"))).toBeNull();
    expect(sniffFileExt(headOf("<html>%PDF-1.4"))).toBeNull();
  });

  it("rejects RIFF containers that are not WebP (WAV, AVI)", () => {
    expect(sniffFileExt(headOf("RIFF____WAVEfmt "))).toBeNull();
    expect(sniffFileExt(headOf("RIFF____AVI LIST"))).toBeNull();
  });

  it("rejects an ISO-BMFF container whose brand is not a still image (mp4)", () => {
    expect(sniffFileExt(ftyp("mp42"))).toBeNull();
    expect(sniffFileExt(ftyp("isom"))).toBeNull();
  });

  it("rejects a truncated PNG signature", () => {
    // First four bytes match, the CRLF/EOF trap bytes do not.
    expect(sniffFileExt(head(0x89, 0x50, 0x4e, 0x47, 0x00, 0x00, 0x00, 0x00))).toBeNull();
  });
});

describe("sniffFileExt: short and empty buffers cannot throw", () => {
  it("returns null for an empty buffer", () => {
    expect(sniffFileExt(new Uint8Array(0))).toBeNull();
  });

  it.each([1, 2, 3])("returns null for a %i-byte buffer", (n) => {
    expect(sniffFileExt(new Uint8Array(n))).toBeNull();
  });

  it("returns null for a 4-byte %PDF with no trailing hyphen to read", () => {
    // Exercises the out-of-range read at head[4]: undefined, never a throw.
    expect(sniffFileExt(headOf("%PDF", false))).toBeNull();
  });

  it("does not read past a short ISO-BMFF buffer when deriving the brand", () => {
    // `ftyp` present but the 4 brand bytes are missing entirely.
    const short = new Uint8Array([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]);
    expect(() => sniffFileExt(short)).not.toThrow();
    expect(sniffFileExt(short)).toBeNull();
  });
});

describe("isIsoBmffContainer", () => {
  it("is true for any ftyp box regardless of brand", () => {
    expect(isIsoBmffContainer(ftyp("mif2"))).toBe(true);
    expect(isIsoBmffContainer(ftyp("mp42"))).toBe(true);
  });

  it("is false for formats that are not ISO-BMFF", () => {
    expect(isIsoBmffContainer(JPEG)).toBe(false);
    expect(isIsoBmffContainer(PNG)).toBe(false);
    expect(isIsoBmffContainer(PDF)).toBe(false);
    expect(isIsoBmffContainer(headOf("<html>"))).toBe(false);
  });

  it("is false for a buffer too short to hold the box type", () => {
    expect(isIsoBmffContainer(new Uint8Array([0x00, 0x00, 0x00, 0x18, 0x66]))).toBe(false);
  });

  it("is the escape hatch for an unlisted HEIC brand", () => {
    // sniffFileExt alone cannot name it, but the container is genuine — which is
    // what lets an explicit image/heic declaration be honoured safely.
    const unlisted = ftyp("mif2");
    expect(sniffFileExt(unlisted)).toBeNull();
    expect(isIsoBmffContainer(unlisted)).toBe(true);
    // HTML gets no such reprieve.
    expect(isIsoBmffContainer(headOf("<html><script>x</script>"))).toBe(false);
  });
});

describe("stored type tables", () => {
  const allExts: StoredFileExt[] = ["jpg", "png", "webp", "heic", "heif", "pdf"];

  it("gives every stored extension exactly one canonical Content-Type", () => {
    for (const ext of allExts) {
      expect(FILE_EXT_CONTENT_TYPE[ext]).toBeTruthy();
    }
    expect(Object.keys(FILE_EXT_CONTENT_TYPE).sort()).toEqual([...allExts].sort());
  });

  it("normalises jpg to image/jpeg rather than image/jpg", () => {
    expect(FILE_EXT_CONTENT_TYPE.jpg).toBe("image/jpeg");
  });

  it("classifies photographs as images and PDF as not", () => {
    for (const ext of allExts) {
      expect(isImageFileExt(ext)).toBe(ext !== "pdf");
    }
  });

  it("only ever yields a type from the canonical table", () => {
    const canonical = new Set(Object.values(FILE_EXT_CONTENT_TYPE));
    for (const bytes of [JPEG, PNG, WEBP, PDF, ftyp("heic"), ftyp("mif1")]) {
      const ext = sniffFileExt(bytes);
      expect(ext).not.toBeNull();
      expect(canonical.has(FILE_EXT_CONTENT_TYPE[ext as StoredFileExt])).toBe(true);
    }
  });

  it("reads enough bytes for the deepest check", () => {
    // The ISO-BMFF brand ends at offset 11.
    expect(SNIFF_HEAD_BYTES).toBeGreaterThanOrEqual(12);
  });
});
