"""Regenerate the fictional invoice fixtures used by the Swift invoice-import tests.

Run from this directory on macOS: python3 make_fixtures.py
Needs only the standard library and the built-in `sips` tool. Writes:

- invoice_text.pdf      a text PDF (Nordlicht Software GmbH, 119,00 EUR incl. 19% MwSt)
- invoice_scanned.pdf   an image-only PDF of a second invoice (Druckerei Beispiel GmbH, 59,50 EUR)
- invoice_photo.png     that second invoice as a PNG
- invoice_photo.heic    the same as HEIC
- invoice_photo_rotated.jpg  the same as JPEG, pixels stored rotated 90 degrees clockwise with
                        EXIF orientation 8, so it displays upright only once the orientation is applied

Every invoice has a dark header bar across the top, which the orientation test looks for. All names,
addresses and numbers are made up.
"""

import os
import struct
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
A4 = (595, 842)


def pdf_string(text):
    """A PDF literal string in WinAnsi encoding."""
    raw = text.encode("cp1252")
    return b"(" + raw.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)") + b")"


def write_pdf(objects):
    """A PDF 1.4 file from object bodies numbered 1...n; object 1 must be the catalog."""
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for offset in offsets:
        out += b"%010d 00000 n \n" % offset
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    return bytes(out)


def stream(dictionary, data):
    return b"<< " + dictionary + b" /Length %d >>\nstream\n" % len(data) + data + b"\nendstream"


def text_page_pdf(lines, scale=1):
    """One A4 page (scaled by `scale`) with a dark header bar and lines of (x, y, size, text) in Helvetica."""
    ops = [b"%d 0 0 %d 0 0 cm" % (scale, scale), b"0.15 0.2 0.3 rg 0 792 595 50 re f"]
    for x, y, size, text, white in lines:
        colour = b"1 1 1 rg" if white else b"0 0 0 rg"
        ops.append(colour + b" BT /F1 %d Tf %d %d Td " % (size, x, y) + pdf_string(text) + b" Tj ET")
    content = b"\n".join(ops)
    width, height = A4[0] * scale, A4[1] * scale
    return write_pdf([
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << /Font << /F1 4 0 R >> >> "
        b"/Contents 5 0 R >>" % (width, height),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        stream(b"", content),
    ])


def invoice_lines(supplier, address, number, date, items, net, vat_rate, vat, gross):
    lines = [(40, 808, 20, supplier, True)]
    y = 760
    for text in address:
        lines.append((40, y, 10, text, False))
        y -= 14
    lines += [
        (40, 680, 10, "Alex Beispiel, Beispielweg 5, 10117 Berlin", False),
        (40, 620, 18, "Rechnung", False),
        (40, 596, 10, "Rechnungsnummer: %s" % number, False),
        (40, 582, 10, "Rechnungsdatum: %s" % date, False),
        (40, 540, 10, "Leistung", False),
        (440, 540, 10, "Betrag", False),
    ]
    y = 520
    for text, amount in items:
        lines += [(40, y, 10, text, False), (440, y, 10, amount + " EUR", False)]
        y -= 16
    lines += [
        (300, 440, 10, "Netto", False), (440, 440, 10, net + " EUR", False),
        (300, 424, 10, "MwSt %d%%" % vat_rate, False), (440, 424, 10, vat + " EUR", False),
        (300, 404, 12, "Gesamtbetrag (Brutto)", False), (440, 404, 12, gross + " EUR", False),
        (40, 300, 9, "Zahlbar innerhalb von 14 Tagen ohne Abzug.", False),
    ]
    return lines


TEXT_INVOICE = invoice_lines(
    "Nordlicht Software GmbH", ["Musterstraße 1", "20095 Hamburg", "USt-IdNr. DE000000000"],
    "NS-2026-0042", "01.10.2026", [("Cloud Hosting Oktober 2026", "100,00")], "100,00", 19, "19,00", "119,00")

PHOTO_INVOICE = invoice_lines(
    "Druckerei Beispiel GmbH", ["Beispielallee 12", "80331 München", "USt-IdNr. DE111111111"],
    "DB-7781", "15.09.2026", [("Visitenkarten, 500 Stück", "35,00"), ("Briefpapier, 250 Blatt", "15,00")],
    "50,00", 19, "9,50", "59,50")


def sips(*args):
    subprocess.run(["sips", *args], check=True, stdout=subprocess.DEVNULL)


def jpeg_size(data):
    """(width, height) from a JPEG's SOF marker."""
    i = 2
    while i < len(data):
        marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            height, width = struct.unpack(">HH", data[i + 5:i + 9])
            return width, height
        i += 2 + length
    raise ValueError("no SOF marker")


def with_orientation(jpeg, orientation):
    """The JPEG with any APP1 segments replaced by a minimal EXIF block holding only `orientation`."""
    ifd = struct.pack(">HHHIHH", 1, 0x0112, 3, 1, orientation, 0) + struct.pack(">I", 0)
    exif = b"Exif\0\0" + b"MM\0*" + struct.pack(">I", 8) + ifd
    app1 = b"\xff\xe1" + struct.pack(">H", len(exif) + 2) + exif
    body, i = bytearray(), 2
    while jpeg[i] == 0xFF and jpeg[i + 1] != 0xDA:
        length = struct.unpack(">H", jpeg[i + 2:i + 4])[0]
        if jpeg[i + 1] != 0xE1:
            body += jpeg[i:i + 2 + length]
        i += 2 + length
    return jpeg[:2] + app1 + bytes(body) + jpeg[i:]


def scanned_pdf(jpeg):
    """An image-only A4 page showing the JPEG, like a scanner would produce."""
    width, height = jpeg_size(jpeg)
    content = b"q 595 0 0 842 0 0 cm /Im0 Do Q"
    return write_pdf([
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Im0 4 0 R >> >> "
        b"/Contents 5 0 R >>",
        stream(b"/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB "
               b"/BitsPerComponent 8 /Filter /DCTDecode" % (width, height), jpeg),
        stream(b"", content),
    ])


def main():
    def out(name):
        return os.path.join(HERE, name)

    with open(out("invoice_text.pdf"), "wb") as f:
        f.write(text_page_pdf(TEXT_INVOICE))

    with tempfile.TemporaryDirectory() as tmp:
        # sips rasterizes PDFs at 72 dpi, so draw the page at 2x to get a 1190 x 1684 px image.
        source = os.path.join(tmp, "photo.pdf")
        with open(source, "wb") as f:
            f.write(text_page_pdf(PHOTO_INVOICE, scale=2))
        sips("-s", "format", "png", source, "--out", out("invoice_photo.png"))
        sips("-s", "format", "heic", "-s", "formatOptions", "40", out("invoice_photo.png"),
             "--out", out("invoice_photo.heic"))

        upright = os.path.join(tmp, "upright.jpg")
        sips("-s", "format", "jpeg", "-s", "formatOptions", "50", out("invoice_photo.png"), "--out", upright)
        with open(upright, "rb") as f:
            upright_jpeg = f.read()
        with open(out("invoice_scanned.pdf"), "wb") as f:
            f.write(scanned_pdf(upright_jpeg))

        rotated = os.path.join(tmp, "rotated.jpg")
        sips("-r", "90", upright, "--out", rotated)
        with open(rotated, "rb") as f:
            rotated_jpeg = f.read()
        # Stored turned 90 degrees clockwise; orientation 8 tells viewers to turn it back counterclockwise.
        with open(out("invoice_photo_rotated.jpg"), "wb") as f:
            f.write(with_orientation(rotated_jpeg, 8))


if __name__ == "__main__":
    main()
