//! Payload kind 2, the structured document payload (SPEC.md 11.3).
//!
//! The reader runs Phase S (structure and fields), Phase L (canonical text limits) and
//! Phase Q (the directive round trip for planes whose keys contain quotes) over the
//! uncompressed payload, then materializes the `Document` in a second pass. The writer
//! emits the canonical encoding and self-checks it with the same reader.
use crate::storage::{
    self, CheckedChars, DocumentCompression, DocumentDecodeLimits, DocumentStorageError as Error,
    OperationOptions, CONTAINER_VERSION, HEADER_BYTE_COUNT, PAYLOAD_KIND_STRUCTURED_DOCUMENT,
};
use crate::{checksum, Document, Plane};
use std::borrow::Cow;
use std::cell::Cell;
use std::collections::hash_map::RandomState;
use std::collections::{BTreeMap, HashSet};
use std::hash::{BuildHasher, BuildHasherDefault, Hasher};
use unicode_normalization::{is_nfc, is_nfc_quick, IsNormalized, UnicodeNormalization};

type Result<Value> = std::result::Result<Value, Error>;

/// Bytes scanned or validated between two cancellation checks (SPEC.md 11.3.13).
const CHUNK: usize = 65_536;
/// Integer form range, `-2^27 ..= 2^27 - 1`.
const INTEGER_MIN: f64 = -134_217_728.0;
const INTEGER_MAX: f64 = 134_217_727.0;
/// The largest value a Var holds, `2^28 - 1`.
const VAR_MAX: usize = (1 << 28) - 1;
/// Every canonical number spelling is 1 to 24 bytes long (SPEC.md 11.3.7).
const NUMBER_BOUND: usize = 24;

const DETAIL_SCALAR_BREAK: &str = "Scalar fields cannot contain physical line breaks.";
const DETAIL_FINITE: &str = "Plane coordinates must be finite.";
const DETAIL_UNIQUE: &str = "Plane positions must be unique.";
const DETAIL_VERSION: &str = "The version must be nonempty.";
const DETAIL_AXIS: &str = "The axis must already be trimmed and lowercase.";
const DETAIL_METADATA_KEY: &str = "Metadata keys cannot shadow reserved fields or comments.";
const DETAIL_ATTRIBUTE_KEY: &str =
    "Attribute keys must be lowercase and cannot shadow coordinates or labels.";
const DETAIL_EQUIVALENT: &str =
    "Canonically equivalent dictionary keys cannot be represented faithfully.";
const DETAIL_PREAMBLE_PLANES: &str = "A preamble requires at least one plane.";
const DETAIL_DIRECTIVE: &str = "The plane directive would not parse back to the same plane.";
const DETAIL_EMPTY_PREAMBLE: &str = "An empty preamble cannot be represented.";
const DETAIL_TRAILING_CR: &str = "A segment cannot end with a carriage return.";
const DETAIL_CRLF: &str = "A segment cannot contain CRLF.";
const DETAIL_BLANK_EDGE: &str = "A segment cannot begin or end with a blank line.";
const DETAIL_DIRECTIVE_LINE: &str =
    "A segment line outside a fence cannot start a plane directive.";
const DETAIL_OPEN_FENCE: &str = "Only the last plane body may end inside an open fence.";

#[cold]
fn invalid(detail: &str) -> Error {
    Error::InvalidDocument(detail.to_owned())
}

#[cfg(test)]
thread_local! {
    /// Phase Q parses on this thread, for the amplification test.
    static PHASE_Q_PARSES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Keys Phase Q normalized on this thread to order a directive line.
    static PHASE_Q_FORMS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Exact form comparison passes after two key hashes met, on this thread.
    static EXACT_FORM_PASSES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

// MARK: - Byte classes

/// Scalar scan class: counts toward `esc` (`"` and `\`).
const ESCAPED: u8 = 1;
/// Scalar scan class: a quote character (`"` and `'`).
const QUOTE: u8 = 2;
/// Scalar scan class: a physical line break (LF and CR).
const LINE_BREAK: u8 = 4;
/// Scalar scan class: a byte R9 forbids in an attribute key (space, tab and `=`).
const ATTRIBUTE_SEPARATOR: u8 = 8;
/// Scalar scan class: the `:` that R3 forbids in a metadata key.
const COLON: u8 = 16;
/// Scalar scan class: an ASCII uppercase letter.
const UPPERCASE: u8 = 32;
/// Scalar scan class: a byte of a non-ASCII scalar.
const NON_ASCII: u8 = 64;

/// The classes of every byte, so that one chunked scan of a scalar answers Str4, the quote
/// test and the byte tests of R2, R3 and R9 (SPEC.md 11.3.13: no other pass over the bytes).
static SCALAR_CLASS: [u8; 256] = {
    let mut table = [0_u8; 256];
    table[b'"' as usize] = ESCAPED | QUOTE;
    table[b'\\' as usize] = ESCAPED;
    table[b'\'' as usize] = QUOTE;
    table[b'\n' as usize] = LINE_BREAK;
    table[b'\r' as usize] = LINE_BREAK;
    table[b' ' as usize] = ATTRIBUTE_SEPARATOR;
    table[b'\t' as usize] = ATTRIBUTE_SEPARATOR;
    table[b'=' as usize] = ATTRIBUTE_SEPARATOR;
    table[b':' as usize] = COLON;
    let mut byte = b'A';
    while byte <= b'Z' {
        table[byte as usize] = UPPERCASE;
        byte += 1;
    }
    let mut byte = 0x80;
    while byte <= 0xff {
        table[byte] = NON_ASCII;
        byte += 1;
    }
    table
};

/// Bytes that can begin a line the segment scan must inspect: a scalar of W, a fence
/// character or the `@` of a directive.
static LINE_START_CLASS: [bool; 256] = {
    let mut table = [false; 256];
    table[b'\t' as usize] = true;
    table[b' ' as usize] = true;
    table[0xC2] = true;
    table[0xE1] = true;
    table[0xE2] = true;
    table[0xE3] = true;
    table[b'`' as usize] = true;
    table[b'~' as usize] = true;
    table[b'@' as usize] = true;
    table
};

/// The frozen whitespace set W of SPEC.md 11.3.6.
#[inline]
fn is_w(character: char) -> bool {
    matches!(
        character,
        '\t' | ' ' | '\u{00a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200b}' | '\u{202f}' | '\u{205f}' | '\u{3000}'
    )
}

/// The byte length of the W scalar starting `bytes`, or 0 when it does not start with one.
#[inline]
fn w_length(bytes: &[u8]) -> usize {
    match bytes {
        [b'\t' | b' ', ..] => 1,
        [0xC2, 0xA0, ..] => 2,
        [0xE1, 0x9A, 0x80, ..]
        | [0xE2, 0x80, 0x80..=0x8B | 0xAF, ..]
        | [0xE2, 0x81, 0x9F, ..]
        | [0xE3, 0x80, 0x80, ..] => 3,
        _ => 0,
    }
}

/// The offset of the first byte of `line` that does not belong to a leading W scalar. Runs of
/// spaces, the common indentation, are skipped eight bytes at a time.
fn skip_w(line: &[u8], options: &OperationOptions) -> Result<usize> {
    const SPACES: u64 = 0x2020_2020_2020_2020;
    let mut index = 0;
    let mut next_check = CHUNK;
    loop {
        let limit = line.len().min(next_check);
        while index + 8 <= limit
            && u64::from_le_bytes([
                line[index],
                line[index + 1],
                line[index + 2],
                line[index + 3],
                line[index + 4],
                line[index + 5],
                line[index + 6],
                line[index + 7],
            ]) == SPACES
        {
            index += 8;
        }
        let length = match line.get(index) {
            Some(b' ' | b'\t') => 1,
            Some(0xC2 | 0xE1 | 0xE2 | 0xE3) => w_length(&line[index..]),
            _ => 0,
        };
        if length == 0 {
            return Ok(index);
        }
        index += length;
        if index >= next_check {
            options.check()?;
            next_check = index.saturating_add(CHUNK);
        }
    }
}

/// The exact positions of LF bytes in an eight-byte little-endian word, as one high bit per
/// matching byte (no false positives, unlike the borrow-based zero-byte test).
#[inline]
fn line_feed_bits(chunk: &[u8]) -> u64 {
    const LOWS: u64 = 0x7f7f_7f7f_7f7f_7f7f;
    const LINE_FEEDS: u64 = 0x0a0a_0a0a_0a0a_0a0a;
    let word = u64::from_le_bytes([
        chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
    ]) ^ LINE_FEEDS;
    !(((word & LOWS).wrapping_add(LOWS)) | word | LOWS)
}

// MARK: - Strings

/// Str3: validates one string as UTF-8 on its own. A string longer than one chunk is split
/// at scalar boundaries and validated chunk by chunk with cancellation checks; it is copied
/// into an owned string only when `keep` is set. Short strings are always borrowed.
fn utf8<'a>(bytes: &'a [u8], keep: bool, options: &OperationOptions) -> Result<Cow<'a, str>> {
    if bytes.len() <= CHUNK {
        return std::str::from_utf8(bytes)
            .map(Cow::Borrowed)
            .map_err(|_| Error::InvalidUtf8);
    }
    let mut owned = if keep {
        String::with_capacity(bytes.len())
    } else {
        String::new()
    };
    let mut start = 0;
    while start < bytes.len() {
        options.check()?;
        let mut end = start.saturating_add(CHUNK).min(bytes.len());
        if end < bytes.len() {
            let mut stepped = 0;
            while stepped < 3 && end > start && bytes[end] & 0xC0 == 0x80 {
                end -= 1;
                stepped += 1;
            }
        }
        let chunk = std::str::from_utf8(&bytes[start..end]).map_err(|_| Error::InvalidUtf8)?;
        if keep {
            owned.push_str(chunk);
        }
        start = end;
    }
    options.check()?;
    Ok(if keep {
        Cow::Owned(owned)
    } else {
        Cow::Borrowed("")
    })
}

/// Str4 for class scalar, plus the inputs of SPEC.md 11.3.7: returns `esc(s)` and the union
/// of the byte classes that occur.
fn scan_scalar(bytes: &[u8], options: &OperationOptions) -> Result<(usize, u8)> {
    let mut escapes = 0_usize;
    let mut classes = 0_u8;
    for (index, chunk) in bytes.chunks(CHUNK).enumerate() {
        if index > 0 {
            options.check()?;
        }
        for &byte in chunk {
            let class = SCALAR_CLASS[usize::from(byte)];
            escapes += usize::from(class & ESCAPED);
            classes |= class;
        }
    }
    if classes & LINE_BREAK != 0 {
        return Err(invalid(DETAIL_SCALAR_BREAK));
    }
    Ok((escapes, classes))
}

/// G5 for the line starting at `start`: applies the fence transitions, or rejects a plane
/// directive outside a fence. Only lines that begin with a W scalar, a fence character or
/// `@` can change anything, so only those are inspected. The scan stops at the line's LF
/// on its own, because LF is neither W nor a fence character.
#[inline]
fn inspect_line(
    bytes: &[u8],
    start: usize,
    fence: &mut u8,
    options: &OperationOptions,
) -> Result<()> {
    let line = &bytes[start..];
    let trimmed = &line[skip_w(line, options)?..];
    if *fence != 0 {
        if trimmed.len() >= 3 && trimmed[..3] == [*fence; 3] {
            *fence = 0;
        }
    } else if trimmed.starts_with(b"```") {
        *fence = b'`';
    } else if trimmed.starts_with(b"~~~") {
        *fence = b'~';
    } else if line.starts_with(b"@plane")
        && matches!(line.get(6), None | Some(b' ' | b'\t' | b'\n'))
    {
        return Err(invalid(DETAIL_DIRECTIVE_LINE));
    }
    Ok(())
}

/// Whether the line starting at `start` consists of W scalars only.
fn is_blank_line(bytes: &[u8], start: usize, options: &OperationOptions) -> Result<bool> {
    let end = start + skip_w(&bytes[start..], options)?;
    Ok(end == bytes.len() || bytes[end] == b'\n')
}

/// Segment rules G1 to G6 (SPEC.md 11.3.6.4) over well-formed UTF-8 bytes. Returns `LF(S)`.
///
/// One SWAR pass finds every LF sixteen bytes at a time; the line after each LF is inspected
/// only when its first byte can begin W, a fence or a directive.
fn check_segment(
    bytes: &[u8],
    preamble: bool,
    is_final: bool,
    options: &OperationOptions,
) -> Result<usize> {
    let length = bytes.len();
    // G1
    if length == 0 {
        return if preamble {
            Err(invalid(DETAIL_EMPTY_PREAMBLE))
        } else {
            Ok(0)
        };
    }
    // G2
    if bytes[length - 1] == b'\r' {
        return Err(invalid(DETAIL_TRAILING_CR));
    }
    // G4, first line
    if is_blank_line(bytes, 0, options)? {
        return Err(invalid(DETAIL_BLANK_EDGE));
    }
    let mut fence = 0_u8;
    if LINE_START_CLASS[usize::from(bytes[0])] {
        inspect_line(bytes, 0, &mut fence, options)?;
    }
    let mut line_feeds = 0_usize;
    let mut last_start = 0;
    let mut handle = |position: usize, fence: &mut u8| -> Result<()> {
        line_feeds += 1;
        // G3
        if position > 0 && bytes[position - 1] == b'\r' {
            return Err(invalid(DETAIL_CRLF));
        }
        let next = position + 1;
        last_start = next;
        if next < length && LINE_START_CLASS[usize::from(bytes[next])] {
            inspect_line(bytes, next, fence, options)?;
        }
        Ok(())
    };
    for (index, block) in bytes.chunks(CHUNK).enumerate() {
        if index > 0 {
            options.check()?;
        }
        let base = index * CHUNK;
        let (pairs, remainder) = block.as_chunks::<16>();
        let mut offset = base;
        for pair in pairs {
            let low = line_feed_bits(&pair[..8]);
            let high = line_feed_bits(&pair[8..]);
            if low | high != 0 {
                for (mut bits, start) in [(low, offset), (high, offset + 8)] {
                    while bits != 0 {
                        handle(start + (bits.trailing_zeros() / 8) as usize, &mut fence)?;
                        bits &= bits - 1;
                    }
                }
            }
            offset += 16;
        }
        for &byte in remainder {
            if byte == b'\n' {
                handle(offset, &mut fence)?;
            }
            offset += 1;
        }
    }
    // G4, last line
    if is_blank_line(bytes, last_start, options)? {
        return Err(invalid(DETAIL_BLANK_EDGE));
    }
    // G6
    if !is_final && fence != 0 {
        return Err(invalid(DETAIL_OPEN_FENCE));
    }
    Ok(line_feeds)
}

// MARK: - Representability rules

/// Whether `text` equals `text.to_lowercase()`, without building it: that holds exactly when
/// every scalar lowercases to itself alone (`Σ` lowercases to `σ` or `ς` by context, which
/// differs from `Σ` either way). A long string checks cancellation every chunk it reads.
fn is_lowercase(text: &str, options: &OperationOptions) -> Result<bool> {
    let failure = Cell::new(None);
    let unchanged = CheckedChars::new(text, CHUNK, options, &failure).all(|character| {
        let mut lower = character.to_lowercase();
        lower.next() == Some(character) && lower.next().is_none()
    });
    match failure.take() {
        Some(error) => Err(error),
        None => Ok(unchanged),
    }
}

/// R2: the axis equals the 2.0 normalization of itself (trim W, lowercase), byte for byte.
/// `classes` are the axis's byte classes from `scan_scalar`. Lowercasing never produces a W
/// scalar, so a normalized axis is one without W at either end whose scalars are lowercase.
fn axis_is_normalized(axis: &str, classes: u8, options: &OperationOptions) -> Result<bool> {
    if classes & NON_ASCII == 0 {
        let bytes = axis.as_bytes();
        Ok(classes & UPPERCASE == 0
            && !matches!(bytes.first(), Some(b' ' | b'\t'))
            && !matches!(bytes.last(), Some(b' ' | b'\t')))
    } else if axis.starts_with(is_w) || axis.ends_with(is_w) {
        Ok(false)
    } else {
        is_lowercase(axis, options)
    }
}

/// R3, the metadata key rule. The empty key is valid. `classes` are the key's byte classes
/// from `scan_scalar`.
fn metadata_key_is_valid(key: &str, classes: u8) -> bool {
    if classes & COLON != 0 {
        return false;
    }
    if let Some(first) = key.chars().next() {
        if first == '#' || is_w(first) {
            return false;
        }
    }
    if key.chars().next_back().is_some_and(is_w) {
        return false;
    }
    !(key.len() <= 5
        && (key.eq_ignore_ascii_case("3md")
            || key.eq_ignore_ascii_case("axis")
            || key.eq_ignore_ascii_case("title")))
}

/// R9, the attribute key rule for planes where no key contains a quote character. `classes`
/// are the key's byte classes from `scan_scalar`.
fn attribute_key_is_valid(key: &str, classes: u8, options: &OperationOptions) -> Result<bool> {
    if key.is_empty() || classes & ATTRIBUTE_SEPARATOR != 0 {
        return Ok(false);
    }
    if key.starts_with(is_w) || key.ends_with(is_w) {
        return Ok(false);
    }
    if classes & NON_ASCII == 0 {
        if classes & UPPERCASE != 0 {
            return Ok(false);
        }
    } else if !is_lowercase(key, options)? {
        return Ok(false);
    }
    Ok(!matches!(key, "z" | "x" | "y" | "label"))
}

/// `Q(s) = len(s) + 2 + esc(s)`, the quoted length.
#[inline]
fn quoted_length(length: usize, escapes: usize) -> usize {
    length.saturating_add(escapes).saturating_add(2)
}

/// The spelling length of an integer-form coordinate: its digits plus a leading `-`.
#[inline]
fn integer_length(value: f64) -> usize {
    let mut magnitude = value.abs() as u32;
    let mut count = if value < 0.0 { 2 } else { 1 };
    while magnitude >= 10 {
        magnitude /= 10;
        count += 1;
    }
    count
}

/// The number form a writer picks for a finite or non-finite value (SPEC.md 11.3.3).
#[inline]
fn form_of(value: f64) -> u8 {
    if value.trunc() == value && (INTEGER_MIN..=INTEGER_MAX).contains(&value) {
        1
    } else if f64::from(value as f32) == value {
        2
    } else {
        3
    }
}

// MARK: - Reader

struct Reader<'a, 'o> {
    data: &'a [u8],
    position: usize,
    record: usize,
    /// Bytes scanned since the last cancellation check.
    scanned: usize,
    options: &'o OperationOptions,
}

/// A validated scalar: its text (borrowed, or owned or empty for a long string), raw bytes,
/// `esc` count and the union of its byte classes.
struct Scalar<'a> {
    text: Cow<'a, str>,
    bytes: &'a [u8],
    escapes: usize,
    classes: u8,
}

impl Scalar<'_> {
    #[inline]
    fn quoted_length(&self) -> usize {
        quoted_length(self.bytes.len(), self.escapes)
    }
}

impl<'a> Reader<'a, '_> {
    #[inline]
    fn remaining(&self) -> usize {
        self.data.len() - self.position
    }

    /// u8. No byte remaining: `lengthMismatch`.
    #[inline]
    fn byte(&mut self) -> Result<u8> {
        let byte = *self.data.get(self.position).ok_or(Error::LengthMismatch)?;
        self.position += 1;
        Ok(byte)
    }

    /// Var, steps V1 to V3.
    #[inline]
    fn var(&mut self) -> Result<usize> {
        let first = self.byte()?;
        if first < 0x80 {
            return Ok(usize::from(first));
        }
        let mut value = usize::from(first & 0x7f);
        let mut shift = 7;
        for index in 1..4 {
            let byte = self.byte()?;
            if index == 3 && byte & 0x80 != 0 {
                return Err(Error::InvalidContainer);
            }
            value |= usize::from(byte & 0x7f) << shift;
            if byte < 0x80 {
                if byte == 0 {
                    return Err(Error::InvalidContainer);
                }
                return Ok(value);
            }
            shift += 7;
        }
        Err(Error::InvalidContainer)
    }

    /// Count(min): divides rather than multiplies, and reserves nothing.
    #[inline]
    fn count(&mut self, minimum: usize) -> Result<usize> {
        let value = self.var()?;
        if value > self.remaining() / minimum {
            return Err(Error::LengthMismatch);
        }
        Ok(value)
    }

    fn fixed<const SIZE: usize>(&mut self) -> Result<[u8; SIZE]> {
        if self.remaining() < SIZE {
            return Err(Error::LengthMismatch);
        }
        let mut bytes = [0_u8; SIZE];
        bytes.copy_from_slice(&self.data[self.position..self.position + SIZE]);
        self.position += SIZE;
        Ok(bytes)
    }

    /// Number(form) for a form from 1 to 3.
    #[inline]
    fn number(&mut self, form: u8) -> Result<f64> {
        match form {
            1 => {
                let encoded = self.var()? as u64;
                let integer = (encoded >> 1) as i64 ^ -((encoded & 1) as i64);
                Ok(integer as f64)
            }
            2 => {
                let value = f64::from(f32::from_le_bytes(self.fixed::<4>()?));
                if !value.is_finite() {
                    return Err(invalid(DETAIL_FINITE));
                }
                if value.trunc() == value && (INTEGER_MIN..=INTEGER_MAX).contains(&value) {
                    return Err(Error::InvalidContainer);
                }
                Ok(value)
            }
            _ => {
                let value = f64::from_le_bytes(self.fixed::<8>()?);
                if !value.is_finite() {
                    return Err(invalid(DETAIL_FINITE));
                }
                if (value.trunc() == value && (INTEGER_MIN..=INTEGER_MAX).contains(&value))
                    || f64::from(value as f32) == value
                {
                    return Err(Error::InvalidContainer);
                }
                Ok(value)
            }
        }
    }

    /// Str1 and Str2: the length prefix and the record limit.
    #[inline]
    fn frame(&mut self, limit: usize) -> Result<&'a [u8]> {
        let length = self.var()?;
        if length > self.remaining() {
            return Err(Error::LengthMismatch);
        }
        if length > limit {
            return Err(Error::OversizedRecord);
        }
        let bytes = &self.data[self.position..self.position + length];
        self.position += length;
        Ok(bytes)
    }

    #[inline]
    fn charge(&mut self, length: usize) -> Result<()> {
        charge(&mut self.scanned, length, self.options)
    }

    /// Str(scalar, R).
    #[inline]
    fn scalar(&mut self, keep: bool) -> Result<Scalar<'a>> {
        let bytes = self.frame(self.record)?;
        self.charge(bytes.len())?;
        let text = utf8(bytes, keep, self.options)?;
        let (escapes, classes) = scan_scalar(bytes, self.options)?;
        Ok(Scalar {
            text,
            bytes,
            escapes,
            classes,
        })
    }

    /// Str(segment, limit): returns the text (empty unless `keep`), its byte length and LF count.
    fn segment(
        &mut self,
        limit: usize,
        keep: bool,
        preamble: bool,
        is_final: bool,
    ) -> Result<(Cow<'a, str>, usize, usize)> {
        let bytes = self.frame(limit)?;
        self.charge(bytes.len())?;
        let text = utf8(bytes, keep, self.options)?;
        let line_feeds = check_segment(bytes, preamble, is_final, self.options)?;
        Ok((text, bytes.len(), line_feeds))
    }

    /// Reads a validated map region again (for Phase Q and materialization), charging both
    /// strings like Phase S does.
    fn entry(&mut self) -> Result<(Cow<'a, str>, Cow<'a, str>)> {
        let key = self.frame(usize::MAX)?;
        self.charge(key.len())?;
        let key = utf8(key, true, self.options)?;
        let value = self.frame(usize::MAX)?;
        self.charge(value.len())?;
        let value = utf8(value, true, self.options)?;
        Ok((key, value))
    }

    /// Reads the key of a validated map entry again and skips its value (for equivalence,
    /// which checks before each key).
    fn key(&mut self) -> Result<Cow<'a, str>> {
        let key = self.frame(usize::MAX)?;
        let key = utf8(key, true, self.options)?;
        self.frame(usize::MAX)?;
        Ok(key)
    }

    /// Skips a validated map entry without reading it.
    fn skip_entry(&mut self) -> Result<()> {
        self.frame(usize::MAX)?;
        self.frame(usize::MAX)?;
        Ok(())
    }
}

// MARK: - Key equivalence

/// Keeps at most one chunk of short-string scanning between two cancellation checks. Long
/// strings check inside their own scans.
#[inline]
fn charge(scanned: &mut usize, length: usize, options: &OperationOptions) -> Result<()> {
    if length > CHUNK - *scanned {
        options.check()?;
        *scanned = 0;
    }
    *scanned += length.min(CHUNK - *scanned);
    Ok(())
}

/// Whether `key` is in NFC. A key of at most one chunk takes one `is_nfc` call, and its
/// caller bounds the bytes between two checks (by charging them or by checking per key); a
/// longer key checks cancellation within its own scan.
#[inline]
fn key_is_nfc(key: &str, options: &OperationOptions) -> Result<bool> {
    if key.len() <= CHUNK {
        Ok(key.is_ascii() || is_nfc(key))
    } else {
        long_key_is_nfc(key, options)
    }
}

/// Whether the NFC quick check alone shows `key` to be NFC: the key is ASCII, or
/// `is_nfc_quick` answers Yes. A key that fails it may still be NFC. Cancellation as in
/// [`key_is_nfc`].
#[inline]
fn key_is_quick_nfc(key: &str, options: &OperationOptions) -> Result<bool> {
    if key.len() <= CHUNK {
        Ok(key.is_ascii() || is_nfc_quick(key.chars()) == IsNormalized::Yes)
    } else {
        Ok(long_key_quick_check(key, options)? == IsNormalized::Yes)
    }
}

/// `is_nfc_quick` for a key longer than one chunk: an ASCII scan chunk by chunk, then the
/// quick check over a [`CheckedChars`] input, which checks every chunk of the key it reads.
#[cold]
fn long_key_quick_check(key: &str, options: &OperationOptions) -> Result<IsNormalized> {
    let mut ascii = true;
    for chunk in key.as_bytes().chunks(CHUNK) {
        options.check()?;
        if !chunk.is_ascii() {
            ascii = false;
            break;
        }
    }
    if ascii {
        return Ok(IsNormalized::Yes);
    }
    let failure = Cell::new(None);
    let answer = is_nfc_quick(CheckedChars::new(key, CHUNK, options, &failure));
    match failure.take() {
        Some(error) => Err(error),
        None => Ok(answer),
    }
}

/// `key_is_nfc` for a key longer than one chunk: the steps of `is_nfc`, with the quick check
/// of [`long_key_quick_check`] and a full comparison over [`CheckedChars`] inputs.
#[cold]
fn long_key_is_nfc(key: &str, options: &OperationOptions) -> Result<bool> {
    match long_key_quick_check(key, options)? {
        IsNormalized::Yes => Ok(true),
        IsNormalized::No => Ok(false),
        IsNormalized::Maybe => {
            let failure = Cell::new(None);
            let scalars = |step| CheckedChars::new(key, step, options, &failure);
            // `eq` advances both sides together, so each side checks every half chunk.
            let result = scalars(CHUNK / 2).eq(scalars(CHUNK / 2).nfc());
            match failure.take() {
                Some(error) => Err(error),
                None => Ok(result),
            }
        }
    }
}

/// Hashes a key chunk by chunk with a cancellation check between chunks. Every key is
/// written the same way, so equal keys hash equally.
fn hash_key(state: &RandomState, key: &str, options: &OperationOptions) -> Result<u64> {
    let mut hasher = state.build_hasher();
    for (index, chunk) in key.as_bytes().chunks(CHUNK).enumerate() {
        if index > 0 {
            options.check()?;
        }
        hasher.write(chunk);
    }
    Ok(hasher.finish())
}

/// Passes a keyed hash from [`hash_key`] through unchanged: it is already uniform, and an
/// input cannot steer it.
#[derive(Default)]
struct PassThrough(u64);

impl Hasher for PassThrough {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.0 = self.0.rotate_left(8) ^ u64::from(byte);
        }
    }

    fn write_u64(&mut self, value: u64) {
        self.0 = value;
    }
}

/// The keys of one map in stored order, read again for each pass of [`check_equivalence`]:
/// a map region of the payload that Phase S has validated (S6b, P7a), or a caller's map (W2).
#[derive(Clone, Copy)]
enum Keys<'a> {
    Payload {
        data: &'a [u8],
        start: usize,
        count: usize,
    },
    Map(&'a BTreeMap<String, String>),
}

impl Keys<'_> {
    fn count(self) -> usize {
        match self {
            Self::Payload { count, .. } => count,
            Self::Map(map) => map.len(),
        }
    }

    /// Calls `visit` with the index and text of each key that `wanted` selects, in stored
    /// order, with a cancellation check before every key. Other keys are skipped unread.
    fn visit(
        self,
        options: &OperationOptions,
        mut wanted: impl FnMut(usize) -> bool,
        mut visit: impl FnMut(usize, &str) -> Result<()>,
    ) -> Result<()> {
        match self {
            Self::Payload { data, start, count } => {
                let mut reader = Reader {
                    data,
                    position: start,
                    record: usize::MAX,
                    scanned: 0,
                    options,
                };
                for index in 0..count {
                    options.check()?;
                    if wanted(index) {
                        let key = reader.key()?;
                        visit(index, &key)?;
                    } else {
                        reader.skip_entry()?;
                    }
                }
            }
            Self::Map(map) => {
                for (index, key) in map.keys().enumerate() {
                    options.check()?;
                    if wanted(index) {
                        visit(index, key)?;
                    }
                }
            }
        }
        Ok(())
    }
}

/// S6b, P7a and W2: rejects a map in which two keys have equal NFC forms (SPEC.md 11.3.6.1).
///
/// Distinct keys can share an NFC form only when one of them is not NFC. Pass 1 marks every
/// key that the NFC quick check does not show to be NFC (so each key that is not NFC, and
/// perhaps some that are); pass 2 hashes the NFC forms of the marked keys into a set sized for
/// exactly them; pass 3 looks up every other key, which is its own NFC form. Two keys with
/// equal forms therefore always meet, either in the set or in a lookup. Only when two hashes
/// meet does [`find_equal_form`] compare forms exactly, one at a time. No form outlives its
/// key's visit: the memory is one bit per key plus one hash slot per marked key, and each
/// marked key is normalized once.
fn check_equivalence(keys: Keys<'_>, options: &OperationOptions) -> Result<()> {
    let mut marks = vec![0_u64; keys.count().div_ceil(64)];
    let mut marked = 0_usize;
    keys.visit(
        options,
        |_| true,
        |index, key| {
            if !key_is_quick_nfc(key, options)? {
                marks[index / 64] |= 1 << (index % 64);
                marked += 1;
            }
            Ok(())
        },
    )?;
    if marked == 0 {
        return Ok(());
    }
    let is_marked = |index: usize| marks[index / 64] >> (index % 64) & 1 != 0;
    let state = RandomState::new();
    let mut hashes: HashSet<u64, BuildHasherDefault<PassThrough>> =
        HashSet::with_capacity_and_hasher(marked, BuildHasherDefault::default());
    keys.visit(options, is_marked, |index, key| {
        let form = storage::normalized_key(key, options)?;
        if hashes.insert(hash_key(&state, &form, options)?) {
            Ok(())
        } else {
            find_equal_form(keys, is_marked, index, &form, options)
        }
    })?;
    keys.visit(
        options,
        |index| !is_marked(index),
        |index, key| {
            if hashes.contains(&hash_key(&state, key, options)?) {
                find_equal_form(keys, is_marked, index, key, options)
            } else {
                Ok(())
            }
        },
    )
}

/// Two hashes met at key `probe`, whose NFC form is `form`: rejects the map when another
/// marked key has exactly that form. (An unmarked key is its own form, and keys are distinct,
/// so two unmarked keys never share a form.) Otherwise the keyed hashes of two different forms
/// collided, which an input cannot arrange; the pass is then repeated work, not an error.
#[cold]
fn find_equal_form(
    keys: Keys<'_>,
    is_marked: impl Fn(usize) -> bool,
    probe: usize,
    form: &str,
    options: &OperationOptions,
) -> Result<()> {
    #[cfg(test)]
    EXACT_FORM_PASSES.with(|count| count.set(count.get() + 1));
    keys.visit(
        options,
        |index| index != probe && is_marked(index),
        |_, key| {
            if storage::normalized_key(key, options)? == form {
                Err(invalid(DETAIL_EQUIVALENT))
            } else {
                Ok(())
            }
        },
    )
}

/// One plane after Phase S. Strings are borrowed from the payload except long ones.
struct PlaneView<'a> {
    z: f64,
    x: Option<f64>,
    y: Option<f64>,
    /// The z, x and y forms (plane flag bits 0 to 5).
    forms: u8,
    label: Option<Cow<'a, str>>,
    attributes: usize,
    attribute_count: usize,
    /// Empty unless the reader materializes.
    body: Cow<'a, str>,
    /// DirLen(p) without the spellings of its form-2 and form-3 numbers.
    directive: usize,
    /// How many of z, x and y use form 2 or 3.
    floats: usize,
    marked: bool,
}

impl PlaneView<'_> {
    /// The exact byte length of the form-2 and form-3 spellings of this plane.
    fn float_lengths(&self) -> usize {
        let mut total = 0_usize;
        for (form, value) in [
            (self.forms & 3, Some(self.z)),
            ((self.forms >> 2) & 3, self.x),
            ((self.forms >> 4) & 3, self.y),
        ] {
            if let (2 | 3, Some(value)) = (form, value) {
                total = total.saturating_add(storage::canonical_number(value).len());
            }
        }
        total
    }
}

fn read_map(
    data: &[u8],
    start: usize,
    count: usize,
    options: &OperationOptions,
) -> Result<BTreeMap<String, String>> {
    if count == 0 {
        return Ok(BTreeMap::new());
    }
    let mut cursor = Reader {
        data,
        position: start,
        record: usize::MAX,
        scanned: 0,
        options,
    };
    // Keys arrive in strictly increasing byte order, which is `String` order: small maps are
    // filled by insertion, large ones bulk-built from the sorted entries.
    if count <= 16 {
        let mut map = BTreeMap::new();
        for _ in 0..count {
            options.check()?;
            let (key, value) = cursor.entry()?;
            map.insert(key.into_owned(), value.into_owned());
        }
        return Ok(map);
    }
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        options.check()?;
        let (key, value) = cursor.entry()?;
        entries.push((key.into_owned(), value.into_owned()));
    }
    Ok(entries.into_iter().collect())
}

/// A stored key and value of a marked plane.
type Pair<'a> = (Cow<'a, str>, Cow<'a, str>);

/// The pairs of a marked plane in the ThreeMD 2.0 Rust writer's order, which
/// `storage::canonical_keys` gives: by NFC form, each key normalized once.
///
/// Stored order is raw byte order, which is NFC order while every key is NFC. A key that the
/// NFC quick check does not show to be NFC is normalized once with `normalized_key`; from the
/// first key whose form differs from it on, the pairs are sorted by their stored forms. Byte
/// order of NFC UTF-8 is the NFC scalar order, the sort is stable, and P7a has made the forms
/// distinct, so the order equals the 2.0 writer's.
fn writer_order<'p, 'a>(
    pairs: &'p [Pair<'a>],
    options: &OperationOptions,
) -> Result<Vec<&'p Pair<'a>>> {
    let mut scanned = 0_usize;
    let mut forms: Vec<(Cow<'p, str>, &'p Pair<'a>)> = Vec::new();
    for (index, pair) in pairs.iter().enumerate() {
        charge(&mut scanned, pair.0.len(), options)?;
        let form = if key_is_quick_nfc(&pair.0, options)? {
            None
        } else {
            #[cfg(test)]
            PHASE_Q_FORMS.with(|count| count.set(count.get() + 1));
            // `normalized_key` checks at least once per key.
            Some(storage::normalized_key(&pair.0, options)?).filter(|form| *form != *pair.0)
        };
        let Some(form) = form else {
            if !forms.is_empty() {
                forms.push((Cow::Borrowed(&pair.0), pair));
            }
            continue;
        };
        if forms.is_empty() {
            forms.reserve_exact(pairs.len());
            forms.extend(
                pairs[..index]
                    .iter()
                    .map(|pair| (Cow::Borrowed(&*pair.0), pair)),
            );
        }
        forms.push((Cow::Owned(form), pair));
    }
    if forms.is_empty() {
        return Ok(pairs.iter().collect());
    }
    forms.sort_by(|left, right| left.0.cmp(&right.0));
    Ok(forms.into_iter().map(|(_, pair)| pair).collect())
}

/// Phase Q for one marked plane (SPEC.md 11.3.6.6): builds the canonical directive line as
/// the 2.0 writer does and parses it with the 2.0 parser.
fn directive_round_trip(
    data: &[u8],
    view: &PlaneView<'_>,
    options: &OperationOptions,
) -> Result<()> {
    #[cfg(test)]
    PHASE_Q_PARSES.with(|count| count.set(count.get() + 1));
    let mut cursor = Reader {
        data,
        position: view.attributes,
        record: usize::MAX,
        scanned: 0,
        options,
    };
    let mut pairs = Vec::with_capacity(view.attribute_count);
    for _ in 0..view.attribute_count {
        pairs.push(cursor.entry()?);
    }
    let ordered = writer_order(&pairs, options)?;
    let quote = |output: &mut String, text: &str| {
        output.push('"');
        for character in text.chars() {
            if character == '"' || character == '\\' {
                output.push('\\');
            }
            output.push(character);
        }
        output.push('"');
    };
    let mut source = String::from("---\n3md: \"1\"\naxis: \"a\"\n---\n\n@plane z=");
    source.push_str(&storage::canonical_number(view.z));
    if let Some(label) = &view.label {
        source.push_str(" label=");
        quote(&mut source, label);
    }
    if let Some(x) = view.x {
        source.push_str(" x=");
        source.push_str(&storage::canonical_number(x));
    }
    if let Some(y) = view.y {
        source.push_str(" y=");
        source.push_str(&storage::canonical_number(y));
    }
    for (key, value) in ordered {
        source.push(' ');
        source.push_str(key);
        source.push('=');
        quote(&mut source, value);
    }
    source.push('\n');
    let parsed = crate::parse_with_options(&source, options).map_err(|error| match error {
        Error::Cancelled => Error::Cancelled,
        _ => invalid(DETAIL_DIRECTIVE),
    })?;
    let [plane] = parsed.planes.as_slice() else {
        return Err(invalid(DETAIL_DIRECTIVE));
    };
    if plane.z != view.z
        || plane.x != view.x
        || plane.y != view.y
        || plane.label.as_deref() != view.label.as_deref()
        || plane.attributes.len() != pairs.len()
        || pairs
            .iter()
            .any(|(key, value)| plane.attributes.get(&**key).map(String::as_str) != Some(&**value))
    {
        return Err(invalid(DETAIL_DIRECTIVE));
    }
    Ok(())
}

/// Phases S, L and Q over one DocumentRecord (SPEC.md 11.3.8). With `MATERIALIZE` false this
/// is the writer's self-check and returns `None`.
fn read<const MATERIALIZE: bool>(
    data: &[u8],
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Option<Document>> {
    let record = limits.maximum_record_bytes;
    let mut reader = Reader {
        data,
        position: 0,
        record,
        scanned: 0,
        options,
    };
    // S1
    let flags = reader.byte()?;
    if flags & 0xfc != 0 {
        return Err(Error::InvalidContainer);
    }
    // S2
    let version = reader.scalar(MATERIALIZE)?;
    if version.bytes.is_empty() {
        return Err(invalid(DETAIL_VERSION));
    }
    // S3
    let axis = reader.scalar(true)?;
    if !axis_is_normalized(&axis.text, axis.classes, options)? {
        return Err(invalid(DETAIL_AXIS));
    }
    // S4
    let title = if flags & 1 != 0 {
        Some(reader.scalar(MATERIALIZE)?)
    } else {
        None
    };
    let mut frontmatter = version
        .quoted_length()
        .saturating_add(5)
        .max(axis.quoted_length().saturating_add(6));
    let mut text_bytes = (4 + 6 + 7 + 4_usize)
        .saturating_add(version.quoted_length())
        .saturating_add(axis.quoted_length());
    let mut lines = 5_usize;
    if let Some(title) = &title {
        frontmatter = frontmatter.max(title.quoted_length().saturating_add(7));
        text_bytes = text_bytes.saturating_add(title.quoted_length().saturating_add(8));
        lines += 1;
    }
    // S5, S6
    let metadata_count = reader.count(2)?;
    let metadata_start = reader.position;
    lines = lines.saturating_add(metadata_count);
    let mut previous: &[u8] = &[];
    let mut needs_equivalence = false;
    for index in 0..metadata_count {
        let key = reader.scalar(true)?;
        if index > 0 && previous >= key.bytes {
            return Err(Error::InvalidContainer);
        }
        if !metadata_key_is_valid(&key.text, key.classes) {
            return Err(invalid(DETAIL_METADATA_KEY));
        }
        let value = reader.scalar(false)?;
        let entry = key.bytes.len().saturating_add(value.quoted_length());
        frontmatter = frontmatter.max(entry.saturating_add(2));
        text_bytes = text_bytes.saturating_add(entry.saturating_add(3));
        needs_equivalence =
            needs_equivalence || (key.classes & NON_ASCII != 0 && !key_is_nfc(&key.text, options)?);
        previous = key.bytes;
    }
    // S6b
    if needs_equivalence {
        check_equivalence(
            Keys::Payload {
                data,
                start: metadata_start,
                count: metadata_count,
            },
            options,
        )?;
    }
    // S7
    let preamble = if flags & 2 != 0 {
        let (text, length, line_feeds) =
            reader.segment(record.saturating_sub(1), MATERIALIZE, true, false)?;
        text_bytes = text_bytes.saturating_add(length.saturating_add(2));
        lines = lines.saturating_add(line_feeds.saturating_add(2));
        Some(text)
    } else {
        None
    };
    // S8
    let plane_count = reader.count(4)?;
    if plane_count > limits.maximum_planes {
        return Err(Error::TooManyPlanes);
    }
    if preamble.is_some() && plane_count == 0 {
        return Err(invalid(DETAIL_PREAMBLE_PLANES));
    }
    let mut views: Vec<PlaneView<'_>> = Vec::with_capacity(plane_count);
    let mut increasing = true;
    let mut previous_z = f64::NEG_INFINITY;
    // S9
    for index in 0..plane_count {
        options.check()?;
        // P1
        let plane_flags = reader.byte()?;
        let z_form = plane_flags & 3;
        if plane_flags & 0x80 != 0 || z_form == 0 {
            return Err(Error::InvalidContainer);
        }
        let mut directive = 9_usize;
        let mut floats = 0_usize;
        // P2 to P4
        let z = reader.number(z_form)?;
        if z_form == 1 {
            directive += integer_length(z);
        } else {
            floats += 1;
        }
        let mut coordinate = |form: u8, reader: &mut Reader<'_, '_>| -> Result<Option<f64>> {
            if form == 0 {
                return Ok(None);
            }
            let value = reader.number(form)?;
            directive += 3;
            if form == 1 {
                directive += integer_length(value);
            } else {
                floats += 1;
            }
            Ok(Some(value))
        };
        let x = coordinate((plane_flags >> 2) & 3, &mut reader)?;
        let y = coordinate((plane_flags >> 4) & 3, &mut reader)?;
        // P5
        let label = if plane_flags & 0x40 != 0 {
            let label = reader.scalar(true)?;
            directive = directive.saturating_add(label.quoted_length().saturating_add(7));
            Some(label.text)
        } else {
            None
        };
        // P6, P7
        let attribute_count = reader.count(3)?;
        let attributes = reader.position;
        let mut previous: &[u8] = &[];
        let mut any_quote = false;
        let mut key_rule_failed = false;
        let mut needs_equivalence = false;
        for entry in 0..attribute_count {
            let key = reader.scalar(true)?;
            if entry > 0 && previous >= key.bytes {
                return Err(Error::InvalidContainer);
            }
            let value = reader.scalar(false)?;
            directive = directive.saturating_add(
                key.bytes
                    .len()
                    .saturating_add(value.quoted_length())
                    .saturating_add(2),
            );
            any_quote |= key.classes & QUOTE != 0;
            key_rule_failed =
                key_rule_failed || !attribute_key_is_valid(&key.text, key.classes, options)?;
            needs_equivalence = needs_equivalence
                || (key.classes & NON_ASCII != 0 && !key_is_nfc(&key.text, options)?);
            previous = key.bytes;
        }
        // P7a
        if needs_equivalence {
            check_equivalence(
                Keys::Payload {
                    data,
                    start: attributes,
                    count: attribute_count,
                },
                options,
            )?;
        }
        // P7b
        if !any_quote && key_rule_failed {
            return Err(invalid(DETAIL_ATTRIBUTE_KEY));
        }
        // P8
        let is_final = index + 1 == plane_count;
        let (body, length, line_feeds) = reader.segment(record, MATERIALIZE, false, is_final)?;
        if length == 0 {
            text_bytes = text_bytes.saturating_add(2);
            lines = lines.saturating_add(2);
        } else {
            text_bytes = text_bytes.saturating_add(length.saturating_add(3));
            lines = lines.saturating_add(line_feeds.saturating_add(3));
        }
        increasing &= z > previous_z;
        previous_z = z;
        views.push(PlaneView {
            z,
            x,
            y,
            forms: plane_flags & 0x3f,
            label,
            attributes,
            attribute_count,
            body,
            directive,
            floats,
            marked: any_quote,
        });
    }
    // S10
    if reader.remaining() != 0 {
        return Err(Error::LengthMismatch);
    }
    options.check()?;
    // L0: strictly increasing positions are unique without a set.
    if !increasing {
        let mut seen = HashSet::with_capacity(views.len());
        if !views.iter().all(|view| seen.insert(view.z.to_bits())) {
            return Err(invalid(DETAIL_UNIQUE));
        }
    }
    // L1, L2
    if record < 3 || frontmatter > record {
        return Err(Error::OversizedRecord);
    }
    // L3: a number is formatted only when the bound 1 <= Nn <= 24 cannot decide.
    let mut fixed = 0_usize;
    let mut floats = 0_usize;
    for view in &views {
        let low = view.directive.saturating_add(view.floats);
        let high = view
            .directive
            .saturating_add(view.floats.saturating_mul(NUMBER_BOUND));
        if low > record
            || (high > record && view.directive.saturating_add(view.float_lengths()) > record)
        {
            return Err(Error::OversizedRecord);
        }
        fixed = fixed.saturating_add(view.directive);
        floats = floats.saturating_add(view.floats);
    }
    // L4
    let decoded = text_bytes.saturating_add(fixed);
    let maximum = limits.maximum_decoded_bytes;
    if decoded.saturating_add(floats.saturating_mul(NUMBER_BOUND)) > maximum {
        if decoded.saturating_add(floats) > maximum {
            return Err(Error::OversizedOutput);
        }
        let mut exact = decoded;
        for view in views.iter().filter(|view| view.floats > 0) {
            exact = exact.saturating_add(view.float_lengths());
        }
        if exact > maximum {
            return Err(Error::OversizedOutput);
        }
    }
    // L5
    if lines > limits.maximum_lines {
        return Err(Error::TooManyLines);
    }
    // Phase Q
    for view in views.iter().filter(|view| view.marked) {
        options.check()?;
        directive_round_trip(data, view, options)?;
        options.check()?;
    }
    if !MATERIALIZE {
        return Ok(None);
    }
    let metadata = read_map(data, metadata_start, metadata_count, options)?;
    let mut planes = Vec::with_capacity(views.len());
    for view in views {
        options.check()?;
        planes.push(Plane {
            z: view.z,
            label: view.label.map(Cow::into_owned),
            x: view.x,
            y: view.y,
            attributes: read_map(data, view.attributes, view.attribute_count, options)?,
            body: view.body.into_owned(),
        });
    }
    let document = Document {
        version: version.text.into_owned(),
        axis: axis.text.into_owned(),
        title: title.map(|title| title.text.into_owned()),
        metadata,
        preamble: preamble.map(Cow::into_owned),
        planes,
    };
    options.check()?;
    Ok(Some(document))
}

/// D14 for payload kind 2: decodes the uncompressed payload.
pub(crate) fn decode(
    payload: &[u8],
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Document> {
    read::<true>(payload, limits, options)?.ok_or(Error::InvalidContainer)
}

// MARK: - Writer

/// The W3 buffer: header space followed by a payload capped at `Emax - 40` bytes.
struct Writer {
    output: Vec<u8>,
    cap: usize,
}

impl Writer {
    #[inline]
    fn reserve(&mut self, count: usize) -> Result<()> {
        if count > self.cap - (self.output.len() - HEADER_BYTE_COUNT) {
            return Err(Error::OversizedInput);
        }
        Ok(())
    }

    #[inline]
    fn byte(&mut self, value: u8) -> Result<()> {
        self.reserve(1)?;
        self.output.push(value);
        Ok(())
    }

    #[inline]
    fn var(&mut self, value: usize) -> Result<()> {
        // A count or length above the Var range cannot fit any cap: every limit is at most 64 MiB.
        if value > VAR_MAX {
            return Err(Error::OversizedInput);
        }
        let size = match value {
            0..=0x7f => 1,
            0x80..=0x3fff => 2,
            0x4000..=0x1f_ffff => 3,
            _ => 4,
        };
        self.reserve(size)?;
        let mut value = value;
        while value >= 0x80 {
            self.output.push((value & 0x7f) as u8 | 0x80);
            value >>= 7;
        }
        self.output.push(value as u8);
        Ok(())
    }

    #[inline]
    fn number(&mut self, value: f64, form: u8) -> Result<()> {
        match form {
            1 => {
                let integer = value as i32;
                self.var(((integer << 1) ^ (integer >> 31)) as u32 as usize)
            }
            2 => {
                self.reserve(4)?;
                self.output.extend_from_slice(&(value as f32).to_le_bytes());
                Ok(())
            }
            _ => {
                self.reserve(8)?;
                self.output.extend_from_slice(&value.to_le_bytes());
                Ok(())
            }
        }
    }

    #[inline]
    fn string(&mut self, text: &str) -> Result<()> {
        self.var(text.len())?;
        self.reserve(text.len())?;
        self.output.extend_from_slice(text.as_bytes());
        Ok(())
    }

    fn map(&mut self, map: &BTreeMap<String, String>) -> Result<()> {
        self.var(map.len())?;
        for (key, value) in map {
            self.string(key)?;
            self.string(value)?;
        }
        Ok(())
    }
}

/// W2 for Rust: a map with canonically equivalent spellings has no insertion history to
/// choose from and is rejected, as in 2.0.
///
/// The map is the caller's, not yet bounded by W3, so the scan for a key that is not NFC
/// charges keys like the reader's short strings, and a long key checks inside its own scan
/// (SPEC.md 11.3.13). Only a map with such a key runs [`check_equivalence`].
fn reject_equivalent_keys(
    map: &BTreeMap<String, String>,
    options: &OperationOptions,
) -> Result<()> {
    let mut scanned = 0_usize;
    for key in map.keys() {
        charge(&mut scanned, key.len(), options)?;
        if !key_is_nfc(key, options)? {
            return check_equivalence(Keys::Map(map), options);
        }
    }
    Ok(())
}

fn estimated_payload(document: &Document) -> usize {
    let map = |map: &BTreeMap<String, String>| {
        map.iter().fold(1_usize, |total, (key, value)| {
            total.saturating_add(key.len().saturating_add(value.len()).saturating_add(8))
        })
    };
    let mut total = 16_usize
        .saturating_add(document.version.len())
        .saturating_add(document.axis.len())
        .saturating_add(document.title.as_ref().map_or(0, String::len))
        .saturating_add(document.preamble.as_ref().map_or(0, String::len))
        .saturating_add(map(&document.metadata));
    for plane in &document.planes {
        total = total
            .saturating_add(plane.body.len())
            .saturating_add(plane.label.as_ref().map_or(0, String::len))
            .saturating_add(map(&plane.attributes))
            .saturating_add(36);
    }
    total
}

/// W3: emits the fields of SPEC.md 11.3.5 in order, normalizing -0 to +0.
fn emit(document: &Document, writer: &mut Writer, options: &OperationOptions) -> Result<()> {
    writer
        .byte(u8::from(document.title.is_some()) | (u8::from(document.preamble.is_some()) << 1))?;
    writer.string(&document.version)?;
    writer.string(&document.axis)?;
    if let Some(title) = &document.title {
        writer.string(title)?;
    }
    writer.map(&document.metadata)?;
    if let Some(preamble) = &document.preamble {
        writer.string(preamble)?;
    }
    writer.var(document.planes.len())?;
    for plane in &document.planes {
        options.check()?;
        let normalize = |value: f64| if value == 0.0 { 0.0 } else { value };
        let z = normalize(plane.z);
        let x = plane.x.map(normalize);
        let y = plane.y.map(normalize);
        let z_form = form_of(z);
        let x_form = x.map_or(0, form_of);
        let y_form = y.map_or(0, form_of);
        let label = if plane.label.is_some() { 0x40 } else { 0 };
        writer.byte(z_form | (x_form << 2) | (y_form << 4) | label)?;
        writer.number(z, z_form)?;
        if let Some(x) = x {
            writer.number(x, x_form)?;
        }
        if let Some(y) = y {
            writer.number(y, y_form)?;
        }
        if let Some(label) = &plane.label {
            writer.string(label)?;
        }
        writer.map(&plane.attributes)?;
        writer.string(&plane.body)?;
    }
    Ok(())
}

/// `encode(document, .binary(compression), limits)`: steps W1 to W6 of SPEC.md 11.3.9.
pub(crate) fn encode(
    document: &Document,
    compression: DocumentCompression,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Vec<u8>> {
    // W1, W1b
    limits.validate()?;
    options.check()?;
    let Some(cap) = limits.maximum_encoded_bytes.checked_sub(HEADER_BYTE_COUNT) else {
        return Err(Error::OversizedInput);
    };
    // W2
    reject_equivalent_keys(&document.metadata, options)?;
    for plane in &document.planes {
        options.check()?;
        reject_equivalent_keys(&plane.attributes, options)?;
    }
    // W3
    let capacity = estimated_payload(document).min(cap);
    let mut writer = Writer {
        output: Vec::with_capacity(HEADER_BYTE_COUNT + capacity),
        cap,
    };
    writer.output.resize(HEADER_BYTE_COUNT, 0);
    emit(document, &mut writer, options)?;
    // W4
    read::<false>(&writer.output[HEADER_BYTE_COUNT..], limits, options)?;
    // W5
    if compression == DocumentCompression::Lzfse {
        return Err(Error::CompressionUnavailable(compression));
    }
    // W6
    let mut output = writer.output;
    let length = (output.len() - HEADER_BYTE_COUNT) as u64;
    output[..8].copy_from_slice(storage::MAGIC);
    output[8..10].copy_from_slice(&CONTAINER_VERSION.to_le_bytes());
    output[10] = PAYLOAD_KIND_STRUCTURED_DOCUMENT;
    output[11] = compression as u8;
    output[12..20].fill(0);
    output[20..28].copy_from_slice(&length.to_le_bytes());
    output[28..36].copy_from_slice(&length.to_le_bytes());
    let crc = checksum::container(&output[..36], &output[HEADER_BYTE_COUNT..], options)?;
    output[36..40].copy_from_slice(&crc.to_le_bytes());
    options.check()?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_var(bytes: &[u8]) -> Result<usize> {
        let options = OperationOptions::default();
        let mut reader = Reader {
            data: bytes,
            position: 0,
            record: usize::MAX,
            scanned: 0,
            options: &options,
        };
        reader.var()
    }

    fn write_var(value: usize) -> Vec<u8> {
        let mut writer = Writer {
            output: vec![0; HEADER_BYTE_COUNT],
            cap: 16,
        };
        writer.var(value).unwrap();
        writer.output.split_off(HEADER_BYTE_COUNT)
    }

    #[test]
    fn var_round_trips_at_every_size_boundary_and_rejects_v1_to_v3() {
        for (value, expected) in [
            (0, vec![0x00]),
            (127, vec![0x7f]),
            (128, vec![0x80, 0x01]),
            (16_383, vec![0xff, 0x7f]),
            (16_384, vec![0x80, 0x80, 0x01]),
            (2_097_151, vec![0xff, 0xff, 0x7f]),
            (2_097_152, vec![0x80, 0x80, 0x80, 0x01]),
            (VAR_MAX, vec![0xff, 0xff, 0xff, 0x7f]),
        ] {
            assert_eq!(write_var(value), expected, "{value}");
            assert_eq!(read_var(&expected), Ok(value), "{value}");
        }
        for (bytes, expected) in [
            (&[][..], Error::LengthMismatch),
            (&[0x80][..], Error::LengthMismatch),
            (&[0xff, 0xff, 0xff][..], Error::LengthMismatch),
            (&[0x80, 0x00][..], Error::InvalidContainer),
            (&[0x81, 0x00][..], Error::InvalidContainer),
            (&[0xff, 0xff, 0x80, 0x00][..], Error::InvalidContainer),
            (&[0xff, 0xff, 0xff, 0xff, 0x01][..], Error::InvalidContainer),
            (&[0xff, 0xff, 0xff, 0x80][..], Error::InvalidContainer),
        ] {
            assert_eq!(read_var(bytes), Err(expected), "{bytes:02x?}");
        }
        let mut writer = Writer {
            output: vec![0; HEADER_BYTE_COUNT],
            cap: 64,
        };
        assert_eq!(writer.var(VAR_MAX + 1), Err(Error::OversizedInput));
    }

    #[test]
    fn number_forms_follow_the_table_and_decode_bit_exactly() {
        let cases: [(f64, u8); 24] = [
            (0.0, 1),
            (1.0, 1),
            (-1.0, 1),
            (134_217_727.0, 1),
            (-134_217_728.0, 1),
            (134_217_728.0, 2),
            (-134_217_729.0, 3),
            (16_777_217.0, 1),
            (0.5, 2),
            (0.1, 3),
            (1.5, 2),
            (9_007_199_254_740_992.0, 2),
            (9_007_199_254_740_994.0, 3),
            (5e-324, 3),
            (1.401_298_464_324_817e-45, 2),
            (f64::from(f32::MAX), 2),
            (f64::MAX, 3),
            (2_f64.powi(-140), 2),
            (1e15, 3),
            (1e16, 3),
            (1e-7, 3),
            (-134_217_728.5, 3),
            (f64::INFINITY, 2),
            (f64::NAN, 3),
        ];
        let options = OperationOptions::default();
        for (value, form) in cases {
            assert_eq!(form_of(value), form, "{value:e}");
            let mut writer = Writer {
                output: vec![0; HEADER_BYTE_COUNT],
                cap: 16,
            };
            writer.number(value, form).unwrap();
            let bytes = writer.output.split_off(HEADER_BYTE_COUNT);
            let mut reader = Reader {
                data: &bytes,
                position: 0,
                record: usize::MAX,
                scanned: 0,
                options: &options,
            };
            if value.is_finite() {
                assert_eq!(
                    reader.number(form).unwrap().to_bits(),
                    value.to_bits(),
                    "{value:e}"
                );
                assert_eq!(reader.position, bytes.len());
            } else {
                assert!(matches!(
                    reader.number(form),
                    Err(Error::InvalidDocument(_))
                ));
            }
        }
        // Zigzag at the range edges, and -0 written as +0.
        assert_eq!(write_var(0), [0x00]);
        let mut writer = Writer {
            output: vec![0; HEADER_BYTE_COUNT],
            cap: 16,
        };
        writer.number(-134_217_728.0, 1).unwrap();
        writer.number(134_217_727.0, 1).unwrap();
        assert_eq!(
            &writer.output[HEADER_BYTE_COUNT..],
            [0xff, 0xff, 0xff, 0x7f, 0xfe, 0xff, 0xff, 0x7f]
        );
        assert_eq!(form_of(-0.0), 1);
    }

    #[test]
    fn line_feed_bits_mark_exactly_the_line_feeds() {
        let mut state = 0x51a7_u64;
        for _ in 0..20_000 {
            state = state
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            let mut word = state.to_le_bytes();
            for byte in &mut word {
                if *byte % 5 == 0 {
                    *byte = b'\n';
                } else if *byte % 7 == 0 {
                    *byte = 0x8a;
                } else if *byte % 11 == 0 {
                    *byte = 0x0b;
                }
            }
            let expected = word.iter().enumerate().fold(0_u64, |bits, (index, byte)| {
                bits | (u64::from(*byte == b'\n') << (index * 8 + 7))
            });
            assert_eq!(line_feed_bits(&word), expected, "{word:02x?}");
        }
    }

    fn document(planes: usize, attributes: &[(&str, &str)], label: &str) -> Document {
        Document {
            version: "1".into(),
            axis: String::new(),
            title: None,
            metadata: BTreeMap::new(),
            preamble: None,
            planes: (0..planes)
                .map(|z| Plane {
                    z: z as f64,
                    label: Some(label.into()),
                    x: None,
                    y: None,
                    attributes: attributes
                        .iter()
                        .map(|(key, value)| ((*key).into(), (*value).into()))
                        .collect(),
                    body: String::new(),
                })
                .collect(),
        }
    }

    /// The W3 emission alone, without the self-check, so invalid documents can be encoded.
    fn payload(document: &Document) -> Vec<u8> {
        let mut writer = Writer {
            output: vec![0; HEADER_BYTE_COUNT],
            cap: usize::MAX,
        };
        emit(document, &mut writer, &OperationOptions::default()).unwrap();
        writer.output.split_off(HEADER_BYTE_COUNT)
    }

    #[test]
    fn phase_q_runs_only_after_phase_l_bounds_every_directive() {
        let options = OperationOptions::default();
        let limits = DocumentDecodeLimits::default();
        let label = "l".repeat(60);
        let quoted = document(65_536, &[("a''b", "v"), ("c''d", "w")], &label);
        let bytes = payload(&quoted);
        PHASE_Q_PARSES.with(|count| count.set(0));
        let started = std::time::Instant::now();
        let lowered = DocumentDecodeLimits {
            maximum_record_bytes: 64,
            ..limits.clone()
        };
        assert_eq!(
            read::<true>(&bytes, &lowered, &options).err(),
            Some(Error::OversizedRecord)
        );
        let lowered = DocumentDecodeLimits {
            maximum_decoded_bytes: bytes.len(),
            ..limits.clone()
        };
        assert_eq!(
            read::<true>(&bytes, &lowered, &options).err(),
            Some(Error::OversizedOutput)
        );
        assert_eq!(
            read::<true>(&bytes, &limits, &options).err(),
            Some(Error::TooManyLines)
        );
        assert_eq!(PHASE_Q_PARSES.with(std::cell::Cell::get), 0);
        assert!(started.elapsed() < std::time::Duration::from_secs(10));
        let accepted = document(40_000, &[("a''b", "v"), ("c''d", "w")], &label);
        let bytes = payload(&accepted);
        assert_eq!(read::<true>(&bytes, &limits, &options), Ok(Some(accepted)));
        assert_eq!(PHASE_Q_PARSES.with(std::cell::Cell::get), 40_000);
    }

    #[test]
    fn equivalence_is_rejected_only_for_canonically_equal_distinct_keys() {
        let options = OperationOptions::default();
        let bytes = |keys: &[&str]| {
            let mut writer = Writer {
                output: vec![0; HEADER_BYTE_COUNT],
                cap: 1024,
            };
            for key in keys {
                writer.string(key).unwrap();
                writer.string("v").unwrap();
            }
            writer.output.split_off(HEADER_BYTE_COUNT)
        };
        for (keys, ok) in [
            (&["K", "\u{212a}"][..], false),
            (&["e\u{301}", "\u{e9}"][..], false),
            (&["\u{e9}", "e\u{301}"][..], false),
            (&["a", "e\u{301}", "z"][..], true),
            (&["e\u{301}", "e\u{301}\u{301}"][..], true),
            (&["\u{1e0b}\u{323}", "\u{1e0d}\u{307}"][..], false),
        ] {
            let data = bytes(keys);
            let result = check_equivalence(
                Keys::Payload {
                    data: &data,
                    start: 0,
                    count: keys.len(),
                },
                &options,
            );
            assert_eq!(result.is_ok(), ok, "{keys:?}");
        }
    }

    /// Random maps over pieces that compose, decompose and reorder, against a brute-force
    /// comparison of NFC forms, for the payload and the caller's map alike. Forms are compared
    /// exactly only when two hashes meet: never for a map without equivalent keys.
    #[test]
    fn equivalence_matches_brute_force_and_compares_forms_only_when_hashes_meet() {
        use std::collections::BTreeSet;
        // x+U+0301 and U+0341 (a singleton for U+0301) make keys that the quick check marks
        // although they are NFC, and that keys which are not NFC normalize to.
        const PIECES: &[&str] = &[
            "a", "e", "K", "x", "\u{301}", "\u{341}", "\u{316}", "\u{e9}", "\u{212a}", "\u{1e0b}",
            "\u{1e0d}", "\u{323}", "\u{307}", "\u{ac00}", "\u{11a8}", "\u{1100}", "\u{1161}",
        ];
        let options = OperationOptions::default();
        let mut state = 0x6571_7569_7661_6c65_u64;
        let mut outcomes = [0_usize; 2];
        for _ in 0..4_000 {
            state = lcg(state);
            let size = 2 + (state >> 59) as usize;
            let mut map = BTreeMap::new();
            for _ in 0..size {
                let mut key = String::new();
                state = lcg(state);
                for _ in 0..1 + (state >> 62) {
                    state = lcg(state);
                    key.push_str(PIECES[(state >> 33) as usize % PIECES.len()]);
                }
                map.insert(key, String::new());
            }
            let forms: BTreeSet<String> = map.keys().map(|key| key.nfc().collect()).collect();
            let equivalent = forms.len() < map.len();
            outcomes[usize::from(equivalent)] += 1;
            let expected = if equivalent {
                Err(invalid(DETAIL_EQUIVALENT))
            } else {
                Ok(())
            };
            let mut writer = Writer {
                output: vec![0; HEADER_BYTE_COUNT],
                cap: usize::MAX,
            };
            for key in map.keys() {
                writer.string(key).unwrap();
                writer.string("").unwrap();
            }
            let data = writer.output.split_off(HEADER_BYTE_COUNT);
            let payload = Keys::Payload {
                data: &data,
                start: 0,
                count: map.len(),
            };
            for keys in [payload, Keys::Map(&map)] {
                EXACT_FORM_PASSES.with(|count| count.set(0));
                assert_eq!(check_equivalence(keys, &options), expected, "{map:?}");
                let passes = EXACT_FORM_PASSES.with(Cell::get);
                assert_eq!(passes, usize::from(equivalent), "{map:?}");
            }
            // Phase Q's order for the same keys is the 2.0 writer's.
            if !equivalent {
                let pairs: Vec<Pair<'_>> = map
                    .keys()
                    .map(|key| (Cow::Borrowed(key.as_str()), Cow::Borrowed("")))
                    .collect();
                let ordered: Vec<&str> = writer_order(&pairs, &options)
                    .unwrap()
                    .into_iter()
                    .map(|pair| &*pair.0)
                    .collect();
                let expected: Vec<&str> = storage::canonical_keys(&map, &options)
                    .unwrap()
                    .into_iter()
                    .map(String::as_str)
                    .collect();
                assert_eq!(ordered, expected, "{map:?}");
            }
        }
        assert!(outcomes[0] > 1_000 && outcomes[1] > 300, "{outcomes:?}");
    }

    /// Phase Q orders a marked plane as `storage::canonical_keys` does, and normalizes each key
    /// that is not NFC once, not once per comparison. In these keys byte order (d, e+U+0301,
    /// f) differs from NFC order (d, f, U+00E9) at every digit after a long shared prefix.
    #[test]
    fn phase_q_normalizes_each_key_once_in_the_2_0_writer_order() {
        let options = OperationOptions::default();
        let limits = DocumentDecodeLimits::default();
        let digits = ["d", "e\u{301}", "f"];
        let prefix = "\u{e9}".repeat(256);
        let permuted: Vec<String> = (0..729_usize)
            .map(|mut index| {
                let mut key = prefix.clone();
                for _ in 0..6 {
                    key.push_str(digits[index % 3]);
                    index /= 3;
                }
                key
            })
            .collect();
        let mixed = [
            "a''b",
            "b",
            "\u{e9}",
            "e\u{301}x",
            "x\u{340}",
            "zz",
            "\u{1e0b}\u{323}",
            "\u{f900}",
        ];
        let cases: Vec<Vec<&str>> = vec![
            permuted
                .iter()
                .map(String::as_str)
                .chain(["a''b"])
                .collect(),
            mixed.to_vec(),
            vec!["a''b", "q", "\u{fb2c}"],
            vec!["e\u{301}''", "f", "\u{e8}"],
            vec!["a''b", "b", "\u{e9}"],
        ];
        for keys in cases {
            let attributes: Vec<(&str, &str)> = keys.iter().map(|key| (*key, "v")).collect();
            let document = document(1, &attributes, "l");
            let map = &document.planes[0].attributes;
            let expected: Vec<&str> = storage::canonical_keys(map, &options)
                .unwrap()
                .into_iter()
                .map(String::as_str)
                .collect();
            // Each key that the quick check does not show to be NFC, once.
            let unnormalized = map
                .keys()
                .filter(|key| !key.is_ascii() && is_nfc_quick(key.chars()) != IsNormalized::Yes)
                .count();
            assert!(unnormalized >= map.keys().filter(|key| !is_nfc(key)).count());
            let pairs: Vec<Pair<'_>> = map
                .iter()
                .map(|(key, value)| (Cow::Borrowed(key.as_str()), Cow::Borrowed(value.as_str())))
                .collect();
            PHASE_Q_FORMS.with(|count| count.set(0));
            let ordered: Vec<&str> = writer_order(&pairs, &options)
                .unwrap()
                .into_iter()
                .map(|pair| &*pair.0)
                .collect();
            assert_eq!(ordered, expected);
            assert_eq!(PHASE_Q_FORMS.with(Cell::get), unnormalized);
            // The whole decode: one Phase Q parse, and the same normalizations.
            let bytes = payload(&document);
            PHASE_Q_PARSES.with(|count| count.set(0));
            PHASE_Q_FORMS.with(|count| count.set(0));
            assert_eq!(
                read::<true>(&bytes, &limits, &options),
                Ok(Some(document.clone()))
            );
            assert_eq!(PHASE_Q_PARSES.with(Cell::get), 1);
            assert_eq!(PHASE_Q_FORMS.with(Cell::get), unnormalized);
        }
    }

    use crate::storage::cancellation_hook;

    fn container(payload: &[u8]) -> Vec<u8> {
        let mut file = storage::MAGIC.to_vec();
        file.extend_from_slice(&[1, 0, PAYLOAD_KIND_STRUCTURED_DOCUMENT, 0]);
        file.resize(HEADER_BYTE_COUNT, 0);
        let length = payload.len() as u64;
        file[20..28].copy_from_slice(&length.to_le_bytes());
        file[28..36].copy_from_slice(&length.to_le_bytes());
        let crc = checksum::container(&file[..36], payload, &OperationOptions::default()).unwrap();
        file[36..40].copy_from_slice(&crc.to_le_bytes());
        file.extend_from_slice(payload);
        file
    }

    /// Runs `operation` uncancelled to count its checks, then cancels at every check index
    /// and requires a typed cancellation with no result, then requires the original result.
    fn cancel_everywhere<Value: PartialEq + std::fmt::Debug>(
        operation: impl Fn() -> Result<Value>,
        step: usize,
    ) -> usize {
        cancellation_hook::arm(None);
        let expected = operation();
        let total = cancellation_hook::checks();
        let mut index = 0;
        while index < total {
            cancellation_hook::arm(Some(index));
            assert_eq!(
                operation(),
                Err(Error::Cancelled),
                "check {index} of {total}"
            );
            index += step;
        }
        cancellation_hook::arm(None);
        assert_eq!(operation(), expected);
        total
    }

    fn rich_document() -> Document {
        let mut quoted = document(1, &[("a''b", "v"), ("plain", "w")], "label");
        quoted.planes[0].z = 2.5;
        let long_body = format!("{}\u{1F600}{}", "a".repeat(CHUNK - 2), "b".repeat(140_000));
        let mut document = document(3, &[("k", "v")], &"l".repeat(70_000));
        document
            .metadata
            .insert("e\u{301}".into(), "decomposed".into());
        document.metadata.insert("owner".into(), "ops".into());
        document.preamble = Some("Intro".into());
        document.planes[0].body = long_body;
        document.planes[1].x = Some(0.1);
        document.planes.push(quoted.planes.remove(0));
        document
    }

    #[test]
    fn every_cancellation_check_cancels_decode_and_encode_without_a_result() {
        let limits = DocumentDecodeLimits::default();
        let document = rich_document();
        let options = OperationOptions::default();
        let file = encode(&document, DocumentCompression::None, &limits, &options).unwrap();
        let decode_checks = cancel_everywhere(
            || storage::decode(&file, &limits, &options).map(|decoded| decoded == document),
            1,
        );
        // Entry, CRC chunks, long-string chunks, every plane, Phase L, Phase Q, materialization.
        assert!(decode_checks > 20, "{decode_checks}");
        let encode_checks = cancel_everywhere(
            || encode(&document, DocumentCompression::None, &limits, &options),
            1,
        );
        assert!(encode_checks > decode_checks, "{encode_checks}");
    }

    #[test]
    fn cancellation_reaches_the_crc_of_a_64_mib_input() {
        let limits = DocumentDecodeLimits::default();
        let options = OperationOptions::default();
        let file = container(&vec![
            b'a';
            limits.maximum_encoded_bytes - HEADER_BYTE_COUNT
        ]);
        cancellation_hook::arm(None);
        assert_eq!(
            storage::decode(&file, &limits, &options),
            Err(Error::InvalidContainer)
        );
        let checks = cancellation_hook::checks();
        assert!(checks >= 1_024, "{checks}");
        for at in [1, 2, checks / 2, checks - 2] {
            cancellation_hook::arm(Some(at));
            assert_eq!(
                storage::decode(&file, &limits, &options),
                Err(Error::Cancelled)
            );
        }
        cancellation_hook::arm(None);
        assert_eq!(
            storage::decode(&file, &limits, &options),
            Err(Error::InvalidContainer)
        );
    }

    #[test]
    fn cancellation_reaches_long_scans_and_every_plane() {
        let limits = DocumentDecodeLimits::default();
        let options = OperationOptions::default();
        // An 8 MiB body: UTF-8 chunks and segment scan chunks.
        let mut large = document(1, &[], "l");
        large.planes[0].body = "\u{e9}".repeat(4 * 1024 * 1024 - 1);
        large.planes[0].label = Some("s".repeat(1024 * 1024));
        let bytes = payload(&large);
        let file = container(&bytes);
        let crc_checks = bytes.len().div_ceil(CHUNK) + 1;
        cancellation_hook::arm(None);
        assert_eq!(storage::decode(&file, &limits, &options), Ok(large.clone()));
        let checks = cancellation_hook::checks();
        // The 1 MiB label and the 8 MiB body add their own scan and validation checks.
        assert!(checks >= crc_checks + 16 + 128 + 128, "{checks}");
        for at in [crc_checks + 4, crc_checks + 40, checks - 3] {
            cancellation_hook::arm(Some(at));
            assert_eq!(
                storage::decode(&file, &limits, &options),
                Err(Error::Cancelled)
            );
        }
        // Before plane k of 65,536.
        cancellation_hook::arm(None);
        let many = document(65_536, &[], "");
        let file = container(&payload(&many));
        cancellation_hook::arm(None);
        assert_eq!(
            storage::decode(&file, &limits, &options),
            Err(Error::TooManyLines)
        );
        let checks = cancellation_hook::checks();
        assert!(checks > 65_536, "{checks}");
        cancellation_hook::arm(Some(checks - 1_000));
        assert_eq!(
            storage::decode(&file, &limits, &options),
            Err(Error::Cancelled)
        );
        cancellation_hook::arm(None);
    }

    // MARK: - Cancellation within long keys (SPEC.md 11.3.13)

    fn lcg(state: u64) -> u64 {
        state
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407)
    }

    /// Keys longer than one chunk on which `is_nfc` answers Yes, No and Maybe (NFC or not),
    /// with each risky piece placed across a chunk boundary.
    fn long_keys() -> Vec<String> {
        const PIECES: &[&str] = &[
            "\u{e9}",
            "e\u{301}",
            "x\u{301}",
            "\u{301}",
            "\u{316}",
            "\u{301}\u{316}",
            "\u{316}\u{301}",
            "\u{1e0b}\u{323}",
            "\u{1e0d}\u{307}",
            "\u{1100}\u{1161}",
            "\u{ac00}\u{11a8}",
            "\u{212a}",
            "\u{1f600}",
        ];
        let mut keys = Vec::new();
        for piece in PIECES {
            for shift in 0..4 {
                let ascii = "a".repeat(CHUNK - shift);
                keys.push(format!("{ascii}{piece}{}", "b".repeat(shift + 9)));
                keys.push(format!("{}{piece}", "\u{e9}".repeat(CHUNK / 2 + shift)));
            }
        }
        keys.push("a".repeat(3 * CHUNK + 1));
        keys.push("\u{e9}".repeat(CHUNK + 1));
        keys.push(format!("e{}", "\u{301}".repeat(CHUNK)));
        keys.push(format!("x{}", "\u{316}".repeat(CHUNK)));
        keys.push(format!("x{}", "\u{301}".repeat(CHUNK)));
        keys.push(format!("x{}\u{316}", "\u{301}".repeat(CHUNK)));
        let mut state = 0x6e66_635f_6b65_7973_u64;
        for _ in 0..24 {
            state = lcg(state);
            let target = CHUNK + (state >> 40) as usize % (2 * CHUNK);
            let mut key = String::new();
            while key.len() < target {
                state = lcg(state);
                let pick = (state >> 33) as usize;
                key.push_str(if pick.is_multiple_of(64) {
                    PIECES[pick / 64 % PIECES.len()]
                } else {
                    ["a", "\u{e9}", "\u{ac00}", "\u{316}"][pick % 4]
                });
            }
            keys.push(key);
        }
        keys
    }

    #[test]
    fn long_key_nfc_test_agrees_with_is_nfc_and_checks_every_chunk() {
        let options = OperationOptions::default();
        let mut answers = [0_usize; 4];
        for key in long_keys() {
            assert!(key.len() > CHUNK);
            let expected = is_nfc(&key);
            answers[usize::from(expected)] += 1;
            cancellation_hook::arm(None);
            assert_eq!(
                key_is_nfc(&key, &options),
                Ok(expected),
                "{} bytes",
                key.len()
            );
            let checks = cancellation_hook::checks();
            // An NFC key is read to its end, with a check at least every chunk.
            let minimum = if expected { key.len() / CHUNK } else { 1 };
            assert!(checks >= minimum, "{checks} checks, {} bytes", key.len());
            for at in [0, checks / 2, checks - 1] {
                cancellation_hook::arm(Some(at));
                assert_eq!(key_is_nfc(&key, &options), Err(Error::Cancelled));
            }
            // The quick check alone, as P7a and Phase Q use it.
            let quick = is_nfc_quick(key.chars()) == IsNormalized::Yes;
            answers[2 + usize::from(quick)] += 1;
            cancellation_hook::arm(None);
            assert_eq!(key_is_quick_nfc(&key, &options), Ok(quick));
            let checks = cancellation_hook::checks();
            let minimum = if quick { key.len() / CHUNK } else { 1 };
            assert!(checks >= minimum, "{checks} checks, {} bytes", key.len());
            for at in [0, checks / 2, checks - 1] {
                cancellation_hook::arm(Some(at));
                assert_eq!(key_is_quick_nfc(&key, &options), Err(Error::Cancelled));
            }
        }
        cancellation_hook::arm(None);
        assert!(answers.iter().all(|count| *count >= 20), "{answers:?}");
    }

    #[test]
    fn checked_chars_stop_at_a_failed_check_and_keep_the_error() {
        let options = OperationOptions::default();
        let text = "\u{e9}".repeat(CHUNK + 10);
        let failure = Cell::new(None);
        cancellation_hook::arm(None);
        let count = CheckedChars::new(&text, CHUNK, &options, &failure).count();
        assert_eq!(count, CHUNK + 10);
        assert_eq!(cancellation_hook::checks(), 2);
        assert_eq!(failure.take(), None);
        // The second check, at byte 2 * CHUNK, fails: the scalars before it are read.
        cancellation_hook::arm(Some(1));
        let mut scalars = CheckedChars::new(&text, CHUNK, &options, &failure);
        assert_eq!(scalars.by_ref().count(), CHUNK);
        assert_eq!(scalars.next(), None);
        assert_eq!(failure.take(), Some(Error::Cancelled));
        cancellation_hook::arm(None);
    }

    #[test]
    fn lowercase_test_agrees_with_to_lowercase() {
        let options = OperationOptions::default();
        for scalar in (0..=0x10_ffff_u32).filter_map(char::from_u32) {
            let text = scalar.to_string();
            assert_eq!(
                is_lowercase(&text, &options),
                Ok(text.to_lowercase() == text),
                "U+{:04X}",
                u32::from(scalar)
            );
        }
        for text in [
            "\u{3a3}",
            "a\u{3a3}",
            "\u{3a3}a",
            "a\u{3a3}b",
            "\u{3a3}\u{3a3}",
            "\u{3c3}\u{3c2}",
            "\u{130}",
            "i\u{307}",
            "\u{1c5}",
            "\u{1c6}",
            "\u{df}",
            "\u{1e9e}",
            "\u{2126}",
            "\u{3c9}",
        ] {
            assert_eq!(
                is_lowercase(text, &options),
                Ok(text.to_lowercase() == text),
                "{text}"
            );
        }
        let long = format!("{}\u{3a3}", "\u{e9}".repeat(CHUNK));
        cancellation_hook::arm(None);
        assert_eq!(is_lowercase(&long, &options), Ok(false));
        assert!(cancellation_hook::checks() >= 2);
        cancellation_hook::arm(Some(1));
        assert_eq!(is_lowercase(&long, &options), Err(Error::Cancelled));
        cancellation_hook::arm(None);
    }

    #[test]
    fn w2_checks_cancellation_between_short_keys_and_within_long_keys() {
        let options = OperationOptions::default();
        let short: BTreeMap<String, String> = (0..30_000)
            .map(|index| (format!("\u{e9}{index:06}"), String::new()))
            .collect();
        let long: BTreeMap<String, String> = (0..4)
            .map(|index| (format!("{index}{}", "\u{e9}".repeat(CHUNK)), String::new()))
            .collect();
        let mut equivalent = long.clone();
        for key in [
            format!("9e\u{301}{}", "\u{e9}".repeat(CHUNK)),
            format!("9\u{e9}{}", "\u{e9}".repeat(CHUNK)),
        ] {
            equivalent.insert(key, String::new());
        }
        for (map, expected) in [
            (&short, Ok(())),
            (&long, Ok(())),
            (&equivalent, Err(invalid(DETAIL_EQUIVALENT))),
        ] {
            let bytes: usize = map.keys().map(String::len).sum();
            cancellation_hook::arm(None);
            assert_eq!(reject_equivalent_keys(map, &options), expected);
            let checks = cancellation_hook::checks();
            assert!(
                checks >= bytes / CHUNK,
                "{checks} checks for {bytes} key bytes"
            );
            for at in [0, 1, checks / 3, checks / 2, checks - 1] {
                cancellation_hook::arm(Some(at));
                assert_eq!(
                    reject_equivalent_keys(map, &options),
                    Err(Error::Cancelled),
                    "check {at} of {checks}"
                );
            }
        }
        cancellation_hook::arm(None);
    }

    #[test]
    fn phase_s_checks_cancellation_within_long_keys_and_axes() {
        let options = OperationOptions::default();
        let limits = DocumentDecodeLimits::default();
        let long = format!("k{}", "\u{e9}".repeat(3 * CHUNK));
        let chunks = long.len() / CHUNK;
        let checks = |document: &Document| {
            let bytes = payload(document);
            cancellation_hook::arm(None);
            let decoded = read::<true>(&bytes, &limits, &options);
            assert_eq!(decoded, Ok(Some(document.clone())));
            let checks = cancellation_hook::checks();
            for at in [checks / 2, checks - 1] {
                cancellation_hook::arm(Some(at));
                assert_eq!(
                    read::<true>(&bytes, &limits, &options),
                    Err(Error::Cancelled)
                );
            }
            cancellation_hook::arm(None);
            checks
        };
        // The same bytes as a key and as a value: every pass is chunked alike, except the
        // NFC test of a key (and R9's lowercase test of an attribute key).
        let mut key = document(1, &[], "l");
        key.metadata.insert(long.clone(), "v".into());
        let mut value = document(1, &[], "l");
        value.metadata.insert("k".into(), long.clone());
        let (with_key, with_value) = (checks(&key), checks(&value));
        assert!(
            with_key >= with_value + chunks - 1,
            "{with_key} {with_value}"
        );
        let key = document(1, &[(&long, "v")], "l");
        let value = document(1, &[("k", &long)], "l");
        let (with_key, with_value) = (checks(&key), checks(&value));
        assert!(
            with_key >= with_value + 2 * chunks - 1,
            "{with_key} {with_value}"
        );
        // R2's lowercase test of a long axis, against the same bytes as a title.
        let axis = "\u{e9}".repeat(3 * CHUNK);
        let mut with_axis = document(1, &[], "l");
        with_axis.axis = axis.clone();
        let mut with_title = document(1, &[], "l");
        with_title.title = Some(axis);
        let (with_axis, with_title) = (checks(&with_axis), checks(&with_title));
        assert!(
            with_axis >= with_title + chunks - 1,
            "{with_axis} {with_title}"
        );
    }

    #[test]
    fn long_key_hashes_and_nfc_forms_check_cancellation_on_their_input() {
        let options = OperationOptions::default();
        let state = RandomState::new();
        let long = "\u{e9}".repeat(2 * CHUNK);
        let same: String = std::iter::repeat_n('\u{e9}', 2 * CHUNK).collect();
        cancellation_hook::arm(None);
        assert_eq!(
            hash_key(&state, &long, &options),
            hash_key(&state, &same, &options)
        );
        // Four chunks each, with a check between two chunks.
        assert_eq!(cancellation_hook::checks(), 6);
        assert_ne!(
            hash_key(&state, &long, &options),
            hash_key(&state, &long[2..], &options)
        );
        cancellation_hook::arm(Some(1));
        assert_eq!(hash_key(&state, &long, &options), Err(Error::Cancelled));
        // NFC reads a whole run of combining marks before it yields the run's first scalar,
        // so the input side checks while it reads: one check per chunk of input on top of the
        // checks every 4,096 output scalars.
        let run = format!("e{}", "\u{301}".repeat(4 * CHUNK));
        cancellation_hook::arm(None);
        let normalized = storage::normalized_key(&run, &options);
        assert_eq!(normalized, Ok(run.nfc().collect::<String>()));
        let checks = cancellation_hook::checks();
        let output_checks = (4 * CHUNK).div_ceil(4096) + 1;
        // A check at the first scalar at or past each further chunk of the input.
        let input_checks = run.len() / CHUNK - 1;
        assert!(checks >= output_checks + input_checks, "{checks}");
        cancellation_hook::arm(Some(0));
        assert_eq!(
            storage::normalized_key(&run, &options),
            Err(Error::Cancelled)
        );
        cancellation_hook::arm(None);
    }
}
