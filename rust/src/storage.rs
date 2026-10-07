//! Bounded canonical text and portable version 1 binary document storage.
use crate::{checksum, structured, Document, ParseError};
use std::cell::Cell;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use unicode_normalization::UnicodeNormalization;

/// A cloneable cancellation flag. Operations do not create threads or tasks.
#[derive(Debug, Clone, Default)]
pub struct CancellationToken(Arc<AtomicBool>);
impl CancellationToken {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Relaxed);
    }
    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }
}

/// Explicit operation context. A missing token disables cancellation checks.
#[derive(Debug, Clone, Default)]
pub struct OperationOptions {
    pub cancellation: Option<CancellationToken>,
}
impl OperationOptions {
    pub fn with_cancellation(token: CancellationToken) -> Self {
        Self {
            cancellation: Some(token),
        }
    }
    pub(crate) fn check(&self) -> Result<(), DocumentStorageError> {
        #[cfg(test)]
        if cancellation_hook::tick() {
            return Err(DocumentStorageError::Cancelled);
        }
        if self
            .cancellation
            .as_ref()
            .is_some_and(CancellationToken::is_cancelled)
        {
            Err(DocumentStorageError::Cancelled)
        } else {
            Ok(())
        }
    }
}

/// Deterministic cancellation for the crate's unit tests: counts the checks made on this
/// thread and reports cancellation from an armed check index on.
#[cfg(test)]
pub(crate) mod cancellation_hook {
    use std::cell::Cell;

    thread_local! {
        static CHECKS: Cell<usize> = const { Cell::new(0) };
        static CANCEL_AT: Cell<Option<usize>> = const { Cell::new(None) };
    }

    /// Resets the count and cancels at check `at` (0-based) and every later check.
    pub(crate) fn arm(at: Option<usize>) {
        CHECKS.with(|checks| checks.set(0));
        CANCEL_AT.with(|cancel| cancel.set(at));
    }

    /// The checks made since the last `arm`.
    pub(crate) fn checks() -> usize {
        CHECKS.with(Cell::get)
    }

    pub(super) fn tick() -> bool {
        let index = CHECKS.with(|checks| {
            let index = checks.get();
            checks.set(index + 1);
            index
        });
        CANCEL_AT.with(Cell::get).is_some_and(|at| index >= at)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DocumentCompression {
    None = 0,
    Lzfse = 1,
}
/// A storage writer format. Text remains the portable interchange format; `Binary` writes
/// the structured document payload (SPEC 11.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DocumentStorageFormat {
    /// Canonical readable 3md text.
    Text,
    /// The version 1 container with a structured document payload (payload kind 2) and the
    /// selected compression identifier. [`encode_text_container`] writes payload kind 1.
    Binary(DocumentCompression),
}

/// Storage bounds, independently validated at every public operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentDecodeLimits {
    pub maximum_encoded_bytes: usize,
    pub maximum_decoded_bytes: usize,
    pub maximum_lines: usize,
    pub maximum_planes: usize,
    pub maximum_record_bytes: usize,
}
impl Default for DocumentDecodeLimits {
    fn default() -> Self {
        Self {
            maximum_encoded_bytes: usize::MAX,
            maximum_decoded_bytes: usize::MAX,
            maximum_lines: usize::MAX,
            maximum_planes: usize::MAX,
            maximum_record_bytes: usize::MAX,
        }
    }
}
impl DocumentDecodeLimits {
    /// Every bound must be positive. There is no absolute ceiling: the default is `usize::MAX`.
    pub fn validate(&self) -> Result<(), DocumentStorageError> {
        if self.maximum_encoded_bytes == 0
            || self.maximum_decoded_bytes == 0
            || self.maximum_lines == 0
            || self.maximum_planes == 0
            || self.maximum_record_bytes == 0
        {
            Err(DocumentStorageError::InvalidLimits)
        } else {
            Ok(())
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum DocumentStorageError {
    InvalidLimits,
    OversizedInput,
    OversizedOutput,
    TooManyLines,
    TooManyPlanes,
    OversizedRecord,
    InvalidUtf8,
    InvalidText(ParseError),
    InvalidDocument(String),
    InvalidContainer,
    UnsupportedVersion(u16),
    UnsupportedPayloadKind(u8),
    UnsupportedCompression(u8),
    UnsupportedFlags(u32),
    NonzeroReserved,
    LengthMismatch,
    ChecksumMismatch,
    CompressionUnavailable(DocumentCompression),
    Cancelled,
}
impl DocumentStorageError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidLimits => "invalidLimits",
            Self::OversizedInput => "oversizedInput",
            Self::OversizedOutput => "oversizedOutput",
            Self::TooManyLines => "tooManyLines",
            Self::TooManyPlanes => "tooManyPlanes",
            Self::OversizedRecord => "oversizedRecord",
            Self::InvalidUtf8 => "invalidUTF8",
            Self::InvalidText(_) => "invalidText",
            Self::InvalidDocument(_) => "invalidDocument",
            Self::InvalidContainer => "invalidContainer",
            Self::UnsupportedVersion(_) => "unsupportedVersion",
            Self::UnsupportedPayloadKind(_) => "unsupportedPayloadKind",
            Self::UnsupportedCompression(_) => "unsupportedCompression",
            Self::UnsupportedFlags(_) => "unsupportedFlags",
            Self::NonzeroReserved => "nonzeroReserved",
            Self::LengthMismatch => "lengthMismatch",
            Self::ChecksumMismatch => "checksumMismatch",
            Self::CompressionUnavailable(_) => "compressionUnavailable",
            Self::Cancelled => "cancelled",
        }
    }
}
impl std::fmt::Display for DocumentStorageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidText(error) => write!(f, "{error}"),
            Self::InvalidDocument(detail) => {
                write!(f, "The document cannot be serialized faithfully: {detail}")
            }
            _ => write!(f, "Document storage failed: {}", self.code()),
        }
    }
}
impl std::error::Error for DocumentStorageError {}

pub const CONTAINER_VERSION: u16 = 1;
pub const HEADER_BYTE_COUNT: usize = 40;
pub(crate) const MAGIC: &[u8; 8] = b"3mdbin\r\n";

/// Payload kind 1: canonical UTF-8 text behind the binary header (ThreeMD 2.0, SPEC 11.1).
pub const PAYLOAD_KIND_CANONICAL_TEXT: u8 = 1;
/// Payload kind 2: structured document records (ThreeMD 2.1, SPEC 11.3).
pub const PAYLOAD_KIND_STRUCTURED_DOCUMENT: u8 = 2;
/// The payload kinds this release decodes.
pub const SUPPORTED_PAYLOAD_KINDS: [u8; 2] = [
    PAYLOAD_KIND_CANONICAL_TEXT,
    PAYLOAD_KIND_STRUCTURED_DOCUMENT,
];

/// Raw fixed header fields of a binary container, reported without validation.
///
/// # Example
///
/// ```
/// use threemd::storage::{self, DocumentCompression, DocumentDecodeLimits, DocumentStorageFormat};
///
/// let document = threemd::parse("---\n3md: 1\naxis: layer\n---\n@plane z=0\nBody\n").unwrap();
/// let bytes = storage::encode(
///     &document,
///     DocumentStorageFormat::Binary(DocumentCompression::None),
///     &DocumentDecodeLimits::default(),
///     &Default::default(),
/// )
/// .unwrap();
/// let info = storage::container_info(&bytes).unwrap().unwrap();
/// assert_eq!(info.payload_kind, storage::PAYLOAD_KIND_STRUCTURED_DOCUMENT);
/// assert_eq!(info.decoded_payload_byte_count, bytes.len() as u64 - 40);
/// assert_eq!(storage::container_info(b"---\n3md: 1\n---\n"), Ok(None));
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub struct DocumentContainerInfo {
    /// The independent container version; 1 for every payload kind in ThreeMD 2.1.
    pub container_version: u16,
    /// The payload kind byte.
    pub payload_kind: u8,
    /// The raw compression identifier.
    pub compression: u8,
    /// The raw feature flags.
    pub flags: u32,
    /// The raw reserved field.
    pub reserved: u32,
    /// The declared encoded payload byte count.
    pub encoded_payload_byte_count: u64,
    /// The declared decoded (uncompressed) payload byte count.
    pub decoded_payload_byte_count: u64,
    /// The declared CRC-32/ISO-HDLC value.
    pub checksum: u32,
}

/// Recognizes the full magic prefix only. It does not validate a container.
pub fn is_binary(data: &[u8]) -> bool {
    data.starts_with(MAGIC)
}

/// Reads the 40-byte header without validating it, the payload or the checksum.
///
/// Returns `Ok(None)` when the input does not begin with the binary magic, and
/// `Err(InvalidContainer)` when the magic is present but fewer than 40 bytes exist.
/// At most the first 40 bytes are read.
pub fn container_info(data: &[u8]) -> Result<Option<DocumentContainerInfo>, DocumentStorageError> {
    if !is_binary(data) {
        return Ok(None);
    }
    if data.len() < HEADER_BYTE_COUNT {
        return Err(DocumentStorageError::InvalidContainer);
    }
    Ok(Some(DocumentContainerInfo {
        container_version: u16::from_le_bytes([data[8], data[9]]),
        payload_kind: data[10],
        compression: data[11],
        flags: read_u32(data, 12),
        reserved: read_u32(data, 16),
        encoded_payload_byte_count: read_u64(data, 20),
        decoded_payload_byte_count: read_u64(data, 28),
        checksum: read_u32(data, 36),
    }))
}

pub fn validate(
    document: &Document,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<(), DocumentStorageError> {
    canonical_data(document, limits, options).map(|_| ())
}

/// Produces canonical readable text, or the version 1 binary container with a
/// structured document payload (payload kind 2, SPEC 11.3). Use
/// [`encode_text_container`] for files that ThreeMD 2.0 must read.
pub fn encode(
    document: &Document,
    format: DocumentStorageFormat,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Vec<u8>, DocumentStorageError> {
    match format {
        DocumentStorageFormat::Text => {
            let source = canonical_data(document, limits, options)?;
            if source.len() > limits.maximum_encoded_bytes {
                return Err(DocumentStorageError::OversizedInput);
            }
            options.check()?;
            Ok(source)
        }
        DocumentStorageFormat::Binary(compression) => {
            structured::encode(document, compression, limits, options)
        }
    }
}

/// Writes payload kind 1, byte-identical to ThreeMD 2.0 `encode(.., Binary(c), ..)`, for
/// files that ThreeMD 2.0.x must read. Errors are exactly those of the 2.0 binary writer.
///
/// [`encode`] with [`DocumentStorageFormat::Binary`] writes the structured payload, which
/// is smaller and decodes several times faster.
pub fn encode_text_container(
    document: &Document,
    compression: DocumentCompression,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Vec<u8>, DocumentStorageError> {
    let source = canonical_data(document, limits, options)?;
    if limits.maximum_encoded_bytes < HEADER_BYTE_COUNT {
        return Err(DocumentStorageError::OversizedInput);
    }
    if compression == DocumentCompression::Lzfse {
        return Err(DocumentStorageError::CompressionUnavailable(compression));
    }
    if source.len() > limits.maximum_encoded_bytes - HEADER_BYTE_COUNT {
        return Err(DocumentStorageError::OversizedInput);
    }
    let mut result = Vec::with_capacity(HEADER_BYTE_COUNT + source.len());
    result.extend_from_slice(MAGIC);
    result.extend_from_slice(&CONTAINER_VERSION.to_le_bytes());
    result.extend_from_slice(&[PAYLOAD_KIND_CANONICAL_TEXT, compression as u8]);
    result.extend_from_slice(&0_u32.to_le_bytes());
    result.extend_from_slice(&0_u32.to_le_bytes());
    result.extend_from_slice(&(source.len() as u64).to_le_bytes());
    result.extend_from_slice(&(source.len() as u64).to_le_bytes());
    let checksum = checksum::container(&result, &source, options)?;
    result.extend_from_slice(&checksum.to_le_bytes());
    result.extend_from_slice(&source);
    options.check()?;
    Ok(result)
}

/// Decodes canonical or legacy text, or a version 1 binary container. Payload
/// kinds 1 and 2 are accepted; other kinds return `UnsupportedPayloadKind`.
pub fn decode(
    data: &[u8],
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Document, DocumentStorageError> {
    limits.validate()?;
    options.check()?;
    if data.len() > limits.maximum_encoded_bytes {
        return Err(DocumentStorageError::OversizedInput);
    }
    if !is_binary(data) {
        return parse_data(data, limits, options);
    }
    if data.len() < HEADER_BYTE_COUNT {
        return Err(DocumentStorageError::InvalidContainer);
    }
    let version = u16::from_le_bytes([data[8], data[9]]);
    if version != CONTAINER_VERSION {
        return Err(DocumentStorageError::UnsupportedVersion(version));
    }
    let kind = data[10];
    if !SUPPORTED_PAYLOAD_KINDS.contains(&kind) {
        return Err(DocumentStorageError::UnsupportedPayloadKind(kind));
    }
    let compression = match data[11] {
        0 => DocumentCompression::None,
        1 => DocumentCompression::Lzfse,
        other => return Err(DocumentStorageError::UnsupportedCompression(other)),
    };
    let flags = read_u32(data, 12);
    if flags != 0 {
        return Err(DocumentStorageError::UnsupportedFlags(flags));
    }
    if read_u32(data, 16) != 0 {
        return Err(DocumentStorageError::NonzeroReserved);
    }
    let encoded = read_u64(data, 20);
    let decoded = read_u64(data, 28);
    // D10: kind 1 decodes to at most Dmax text bytes; a kind-2 payload is at most
    // twice its canonical text and its uncompressed container must fit Emax.
    let bound = if kind == PAYLOAD_KIND_CANONICAL_TEXT {
        limits.maximum_decoded_bytes
    } else {
        limits
            .maximum_encoded_bytes
            .saturating_sub(HEADER_BYTE_COUNT)
            .min(limits.maximum_decoded_bytes.saturating_mul(2))
    };
    if decoded > bound as u64 {
        return Err(DocumentStorageError::OversizedOutput);
    }
    if encoded == 0
        || decoded == 0
        || encoded != (data.len() - HEADER_BYTE_COUNT) as u64
        || (compression == DocumentCompression::None && encoded != decoded)
    {
        return Err(DocumentStorageError::LengthMismatch);
    }
    let payload = &data[HEADER_BYTE_COUNT..];
    if checksum::container(&data[..36], payload, options)? != read_u32(data, 36) {
        return Err(DocumentStorageError::ChecksumMismatch);
    }
    if compression == DocumentCompression::Lzfse {
        return Err(DocumentStorageError::CompressionUnavailable(compression));
    }
    if kind == PAYLOAD_KIND_CANONICAL_TEXT {
        parse_data(payload, limits, options)
    } else {
        structured::decode(payload, limits, options)
    }
}

fn read_u32(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([
        data[offset],
        data[offset + 1],
        data[offset + 2],
        data[offset + 3],
    ])
}
fn read_u64(data: &[u8], offset: usize) -> u64 {
    let mut bytes = [0; 8];
    bytes.copy_from_slice(&data[offset..offset + 8]);
    u64::from_le_bytes(bytes)
}
pub(crate) fn parse_data(
    data: &[u8],
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Document, DocumentStorageError> {
    options.check()?;
    if data.len() > limits.maximum_decoded_bytes {
        return Err(DocumentStorageError::OversizedOutput);
    }
    let mut lines = 1;
    let mut record = 0;
    for (index, byte) in data.iter().enumerate() {
        if index % 65_536 == 0 {
            options.check()?;
        }
        if *byte == 10 {
            lines += 1;
            record = 0;
            if lines > limits.maximum_lines {
                return Err(DocumentStorageError::TooManyLines);
            }
        } else {
            record += 1;
            if record > limits.maximum_record_bytes {
                return Err(DocumentStorageError::OversizedRecord);
            }
        }
    }
    let source = std::str::from_utf8(data).map_err(|_| DocumentStorageError::InvalidUtf8)?;
    preflight_planes(source, limits, options)?;
    let document = crate::parse_with_options(source, options)?;
    validate_records(&document, limits, options)?;
    Ok(document)
}

fn preflight_planes(
    source: &str,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<(), DocumentStorageError> {
    let normalized = source.replace("\r\n", "\n");
    let normalized = normalized.strip_prefix('\u{feff}').unwrap_or(&normalized);
    let (mut started, mut body, mut fence, mut planes, mut record_bytes) =
        (false, false, None, 0, 0);
    for raw in normalized.split('\n') {
        options.check()?;
        let trimmed = crate::trim_whitespace(raw);
        if !started {
            if trimmed == "---" {
                started = true;
            }
            continue;
        }
        if !body {
            if trimmed == "---" {
                body = true;
            }
            continue;
        }
        let mut directive = false;
        if let Some(open) = fence {
            if (open == '`' && trimmed.starts_with("```"))
                || (open == '~' && trimmed.starts_with("~~~"))
            {
                fence = None;
            }
        } else if trimmed.starts_with("```") {
            fence = Some('`');
        } else if trimmed.starts_with("~~~") {
            fence = Some('~');
        } else if raw == "@plane" || raw.starts_with("@plane ") || raw.starts_with("@plane\t") {
            directive = true;
        }
        if directive {
            planes += 1;
            record_bytes = 0;
            if planes > limits.maximum_planes {
                return Err(DocumentStorageError::TooManyPlanes);
            }
        } else {
            if raw.len() > limits.maximum_record_bytes - record_bytes {
                return Err(DocumentStorageError::OversizedRecord);
            }
            record_bytes += raw.len();
            if record_bytes < limits.maximum_record_bytes {
                record_bytes += 1;
            }
        }
    }
    Ok(())
}

fn validate_records(
    document: &Document,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<(), DocumentStorageError> {
    if document.planes.len() > limits.maximum_planes {
        return Err(DocumentStorageError::TooManyPlanes);
    }
    let mut total = 0;
    let mut charge = |value: &str, scalar: bool| -> Result<(), DocumentStorageError> {
        options.check()?;
        if value.len() > limits.maximum_record_bytes {
            return Err(DocumentStorageError::OversizedRecord);
        }
        if scalar && value.contains(['\n', '\r']) {
            return Err(DocumentStorageError::InvalidDocument(
                "Scalar fields cannot contain physical line breaks.".into(),
            ));
        }
        if value.len() >= limits.maximum_decoded_bytes - total {
            return Err(DocumentStorageError::OversizedOutput);
        }
        total += value.len() + 1;
        Ok(())
    };
    charge(&document.version, true)?;
    charge(&document.axis, true)?;
    if let Some(title) = &document.title {
        charge(title, true)?;
    }
    for (key, value) in &document.metadata {
        charge(key, true)?;
        charge(value, true)?;
    }
    if let Some(preamble) = &document.preamble {
        charge(preamble, false)?;
    }
    for plane in &document.planes {
        charge(&plane.body, false)?;
        if let Some(label) = &plane.label {
            charge(label, true)?;
        }
        for (key, value) in &plane.attributes {
            charge(key, true)?;
            charge(value, true)?;
        }
    }
    Ok(())
}

pub(crate) fn position_key(value: f64) -> u64 {
    if value == 0.0 {
        0
    } else {
        value.to_bits()
    }
}

/// Input bytes a [`CheckedChars`] reads between two cancellation checks (SPEC 11.3.13).
pub(crate) const CHECKED_CHARS_STEP: usize = 65_536;

/// A string's scalars with a cancellation check whenever `step` more bytes have been read.
/// A failed check ends the iteration early and is kept in `failure` for the caller to
/// report, so a consumer that cannot fail (such as `nfc()` or `is_nfc_quick`) still stops.
pub(crate) struct CheckedChars<'a, 'o> {
    chars: std::str::CharIndices<'a>,
    next_check: usize,
    step: usize,
    options: &'o OperationOptions,
    failure: &'o Cell<Option<DocumentStorageError>>,
}

impl<'a, 'o> CheckedChars<'a, 'o> {
    pub(crate) fn new(
        text: &'a str,
        step: usize,
        options: &'o OperationOptions,
        failure: &'o Cell<Option<DocumentStorageError>>,
    ) -> Self {
        Self {
            chars: text.char_indices(),
            next_check: step,
            step,
            options,
            failure,
        }
    }
}

impl Iterator for CheckedChars<'_, '_> {
    type Item = char;

    #[inline]
    fn next(&mut self) -> Option<char> {
        let (index, character) = self.chars.next()?;
        if index >= self.next_check {
            if let Err(error) = self.options.check() {
                self.failure.set(Some(error));
                self.chars = "".char_indices();
                return None;
            }
            self.next_check = index.saturating_add(self.step);
        }
        Some(character)
    }
}

/// Swift String keys compare canonically equivalent Unicode sequences as equal.
/// Keep original spelling while sorting their NFC Unicode scalar sequences.
///
/// Cancellation is checked on both sides: every 4,096 output scalars, and every
/// [`CHECKED_CHARS_STEP`] input bytes, because NFC reads a whole run of combining marks
/// before it yields the first scalar of that run.
pub(crate) fn normalized_key(
    key: &str,
    options: &OperationOptions,
) -> Result<String, DocumentStorageError> {
    let failure = Cell::new(None);
    let mut normalized = String::new();
    let input = CheckedChars::new(key, CHECKED_CHARS_STEP, options, &failure);
    for (index, character) in input.nfc().enumerate() {
        if index.is_multiple_of(4096) {
            options.check()?;
        }
        normalized.push(character);
    }
    if let Some(error) = failure.take() {
        return Err(error);
    }
    options.check()?;
    Ok(normalized)
}

pub(crate) fn canonical_keys<'a>(
    map: &'a BTreeMap<String, String>,
    options: &OperationOptions,
) -> Result<Vec<&'a String>, DocumentStorageError> {
    let mut keys = BTreeMap::new();
    for key in map.keys() {
        options.check()?;
        if keys.insert(normalized_key(key, options)?, key).is_some() {
            return Err(DocumentStorageError::InvalidDocument(
                "Canonically equivalent dictionary keys cannot be represented faithfully.".into(),
            ));
        }
    }
    Ok(keys.into_values().collect())
}

/// Storage-only shortest decimal spelling, leaving the legacy serializer unchanged.
pub(crate) fn canonical_number(value: f64) -> String {
    if value == value.round() && value.abs() < 1e15 {
        return (value as i64).to_string();
    }
    swift_double(value)
}

/// Swift's shortest round-trip spelling: scientific notation below 1e-4 and
/// immediately above the exact integer range (rather than Rust Debug's 1e16
/// boundary), with an explicit exponent sign and at least two exponent digits;
/// decimal notation otherwise.
///
/// `{:e}` and `{:?}` choose the shortest digits but round an exact decimal tie
/// away from zero. The explicitly rounded spelling with the same digit count
/// rounds ties to even, as Swift and JavaScript do, and is used only when it
/// still parses back to the same value; otherwise the shortest spelling stands.
pub(crate) fn swift_double(value: f64) -> String {
    if value.is_nan() {
        return "nan".into();
    }
    if value.is_infinite() {
        return if value > 0.0 { "inf" } else { "-inf" }.into();
    }
    let magnitude = value.abs();
    if magnitude != 0.0 && !(1e-4..=9_007_199_254_740_992.0).contains(&magnitude) {
        let shortest = format!("{value:e}");
        let precision = shortest
            .split_once('e')
            .map_or(shortest.as_str(), |(mantissa, _)| mantissa)
            .split_once('.')
            .map_or(0, |(_, fraction)| fraction.len());
        let rounded = format!("{value:.precision$e}");
        let chosen = if rounded.parse::<f64>() == Ok(value) {
            rounded
        } else {
            shortest
        };
        let (mantissa, exponent) = chosen.split_once('e').unwrap_or((&chosen, "0"));
        let exponent = exponent.parse::<i32>().unwrap_or(0);
        return format!(
            "{mantissa}e{}{exponent:02}",
            if exponent < 0 { "-" } else { "+" },
            exponent = exponent.unsigned_abs()
        );
    }
    let shortest = format!("{value:?}");
    if let Some((_, fraction)) = shortest.split_once('.') {
        let precision = fraction.len();
        let rounded = format!("{value:.precision$}");
        if rounded.parse::<f64>() == Ok(value) {
            return rounded;
        }
    }
    shortest
}

pub(crate) fn canonical_data(
    document: &Document,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Vec<u8>, DocumentStorageError> {
    limits.validate()?;
    options.check()?;
    validate_records(document, limits, options)?;
    if document.version.is_empty() {
        return Err(DocumentStorageError::InvalidDocument(
            "The version must be nonempty.".into(),
        ));
    }
    let mut seen = BTreeSet::new();
    for plane in &document.planes {
        options.check()?;
        if !plane.z.is_finite()
            || plane.x.is_some_and(|v| !v.is_finite())
            || plane.y.is_some_and(|v| !v.is_finite())
        {
            return Err(DocumentStorageError::InvalidDocument(
                "Plane coordinates must be finite.".into(),
            ));
        }
        if !seen.insert(position_key(plane.z)) {
            return Err(DocumentStorageError::InvalidDocument(
                "Plane positions must be unique.".into(),
            ));
        }
    }
    let mut writer = BoundedWriter::new(limits.maximum_decoded_bytes, options);
    writer.line("---")?;
    writer.append("3md: ")?;
    writer.quoted(&document.version)?;
    writer.line("")?;
    writer.append("axis: ")?;
    writer.quoted(&document.axis)?;
    writer.line("")?;
    if let Some(title) = &document.title {
        writer.append("title: ")?;
        writer.quoted(title)?;
        writer.line("")?;
    }
    for key in canonical_keys(&document.metadata, options)? {
        let value = &document.metadata[key];
        let lowered = key.to_lowercase();
        if ["3md", "axis", "title"].contains(&lowered.as_str())
            || key.contains(':')
            || crate::trim_whitespace(key).starts_with('#')
        {
            return Err(DocumentStorageError::InvalidDocument(
                "Metadata keys cannot shadow reserved fields or comments.".into(),
            ));
        }
        writer.append(key)?;
        writer.append(": ")?;
        writer.quoted(value)?;
        writer.line("")?;
    }
    writer.line("---")?;
    if let Some(preamble) = &document.preamble {
        writer.line("")?;
        writer.line(preamble)?;
    }
    for plane in &document.planes {
        writer.line("")?;
        writer.append("@plane z=")?;
        writer.append(&canonical_number(plane.z))?;
        if let Some(label) = &plane.label {
            writer.append(" label=")?;
            writer.quoted(label)?;
        }
        if let Some(x) = plane.x {
            writer.append(" x=")?;
            writer.append(&canonical_number(x))?;
        }
        if let Some(y) = plane.y {
            writer.append(" y=")?;
            writer.append(&canonical_number(y))?;
        }
        for key in canonical_keys(&plane.attributes, options)? {
            let value = &plane.attributes[key];
            let lowered = key.to_lowercase();
            if ["z", "x", "y", "label"].contains(&lowered.as_str())
                || *key != lowered
                || key.contains('=')
            {
                return Err(DocumentStorageError::InvalidDocument(
                    "Attribute keys must be lowercase and cannot shadow coordinates or labels."
                        .into(),
                ));
            }
            writer.append(" ")?;
            writer.append(key)?;
            writer.append("=")?;
            writer.quoted(value)?;
        }
        writer.line("")?;
        if !plane.body.is_empty() {
            writer.line(&plane.body)?;
        }
    }
    let data = writer.data;
    let restored = parse_data(&data, limits, options).map_err(|error| match error {
        DocumentStorageError::InvalidText(parse_error) => {
            DocumentStorageError::InvalidDocument(parse_error.to_string())
        }
        other => other,
    })?;
    if restored != *document {
        return Err(DocumentStorageError::InvalidDocument(
            "Text serialization would change metadata, whitespace, fences or planes.".into(),
        ));
    }
    options.check()?;
    Ok(data)
}

struct BoundedWriter<'a> {
    data: Vec<u8>,
    maximum: usize,
    options: &'a OperationOptions,
}
impl<'a> BoundedWriter<'a> {
    fn new(maximum: usize, options: &'a OperationOptions) -> Self {
        Self {
            data: Vec::new(),
            maximum,
            options,
        }
    }
    fn append(&mut self, text: &str) -> Result<(), DocumentStorageError> {
        self.options.check()?;
        if text.len() > self.maximum - self.data.len() {
            return Err(DocumentStorageError::OversizedOutput);
        }
        self.data.extend_from_slice(text.as_bytes());
        Ok(())
    }
    fn line(&mut self, text: &str) -> Result<(), DocumentStorageError> {
        self.append(text)?;
        self.append("\n")
    }
    fn quoted(&mut self, text: &str) -> Result<(), DocumentStorageError> {
        self.append("\"")?;
        for (index, byte) in text.bytes().enumerate() {
            if index % 65_536 == 0 {
                self.options.check()?;
            }
            let count = if byte == b'"' || byte == b'\\' { 2 } else { 1 };
            if count > self.maximum - self.data.len() {
                return Err(DocumentStorageError::OversizedOutput);
            }
            if count == 2 {
                self.data.push(b'\\');
            }
            self.data.push(byte);
        }
        self.append("\"")
    }
}
