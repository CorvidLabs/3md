//! A faithful Rust implementation of the 3md format.
//!
//! 3md is Markdown extended along a single free Z axis: a document is a required
//! frontmatter block, an optional Markdown preamble, and zero or more planes
//! introduced by `@plane` directives. This crate mirrors the canonical Swift
//! implementation in `Sources/ThreeMD` and the TypeScript port in `js/src`,
//! including their error behavior. The cross-language conformance vectors in
//! `conformance/` pin that behavior down.
//!
//! # Example
//!
//! ```
//! let source = "---\n3md: 0.1\naxis: time\n---\n@plane z=0 label=\"Monday\"\n# Monday\n";
//! let document = threemd::parse(source).expect("valid document");
//! assert_eq!(document.version, "0.1");
//! assert_eq!(document.axis, "time");
//! assert_eq!(document.planes.len(), 1);
//! assert_eq!(document.planes[0].z, 0.0);
//! assert_eq!(document.planes[0].label.as_deref(), Some("Monday"));
//! ```

use std::collections::BTreeMap;

// MARK: - Types

/// Normalizes a raw axis identifier the way the Swift `Axis` type does: leading
/// and trailing whitespace is trimmed and the value is lowercased.
///
/// The axis label is metadata only; any string is permitted. Common values are
/// `time`, `depth`, `layer`, `frame`, and `space`.
///
/// # Example
///
/// ```
/// assert_eq!(threemd::axis("  Frame  "), "frame");
/// ```
#[must_use]
pub fn axis(raw: &str) -> String {
    raw.trim_matches([' ', '\t']).to_lowercase()
}

/// A single slice of a 3md document positioned along the Z axis.
///
/// `z` is required and orders planes along the document's axis. `x` and `y` are
/// optional in-plane offsets for spatial viewers. Any directive attributes other
/// than `z`, `x`, `y`, and `label` are preserved in [`attributes`](Plane::attributes).
#[derive(Debug, Clone, PartialEq)]
pub struct Plane {
    /// Position along the document's Z axis.
    pub z: f64,
    /// Optional human-readable label, or `None` when absent.
    pub label: Option<String>,
    /// Optional horizontal offset within the plane, or `None` when absent.
    pub x: Option<f64>,
    /// Optional vertical offset within the plane, or `None` when absent.
    pub y: Option<f64>,
    /// Extra directive attributes that are not `z`, `x`, `y`, or `label`.
    pub attributes: BTreeMap<String, String>,
    /// The Markdown content of this plane, with surrounding blank lines trimmed.
    pub body: String,
}

/// A parsed 3md document: Markdown extended along one free Z axis.
///
/// A document begins with a required frontmatter block declaring the format
/// version and what the Z axis means, followed by an optional Markdown preamble
/// and zero or more planes. A plain Markdown file with a 3md frontmatter header
/// and no `@plane` directives parses as a single plane at `z = 0`.
#[derive(Debug, Clone, PartialEq)]
pub struct Document {
    /// The declared 3md format version, for example `"0.1"`.
    pub version: String,
    /// What the Z axis represents in this document (trimmed, lowercased).
    pub axis: String,
    /// Optional document title from the frontmatter, or `None`.
    pub title: Option<String>,
    /// Any frontmatter keys other than `3md`, `axis`, and `title`.
    pub metadata: BTreeMap<String, String>,
    /// Markdown content after the frontmatter but before the first plane, or `None`.
    pub preamble: Option<String>,
    /// The document's planes, in source order.
    pub planes: Vec<Plane>,
}

/// A reference from one plane's Markdown body to another plane by its `z`
/// position, written `[[z=N]]` or `[[z=N|text]]`.
///
/// Cross-plane links live verbatim inside plane bodies; [`links`] extracts them
/// in document order. This mirrors the cross-language contract pinned by the
/// `links-*.json` conformance vectors.
#[derive(Debug, Clone, PartialEq)]
pub struct CrossPlaneLink {
    /// The `z` position of the plane whose body contains this link.
    pub source_z: f64,
    /// The `z` position the link points at, parsed as a finite decimal.
    pub target_z: f64,
    /// The optional link text: `None` when absent, `Some("")` when present but empty.
    pub text: Option<String>,
    /// Whether a plane with `z == target_z` exists in the document.
    pub target_exists: bool,
}

// MARK: - Errors

/// An error returned while parsing a 3md document.
///
/// Each variant maps one to one onto the canonical Swift `ParseError` case.
/// Use [`ParseError::code`] to obtain the canonical lower camel case name used
/// by the shared conformance vectors.
#[derive(Debug, Clone, PartialEq)]
pub enum ParseError {
    /// The document has no `---` frontmatter block.
    MissingFrontmatter,
    /// The frontmatter block is malformed or never closed.
    InvalidFrontmatter(String),
    /// The frontmatter is missing the required `3md` version key.
    MissingVersion,
    /// A `@plane` directive has no `z` position.
    MissingPlanePosition {
        /// The 1-based line number of the offending directive.
        line: usize,
    },
    /// A `@plane` directive is malformed (bad number, missing `=`, empty key,
    /// or unterminated quote).
    InvalidPlaneDirective {
        /// The 1-based line number of the offending directive.
        line: usize,
        /// A human-readable detail string.
        detail: String,
    },
    /// Two planes share the same `z` position.
    DuplicatePlane {
        /// The shared `z` position.
        z: f64,
    },
}

impl ParseError {
    /// Returns the canonical lower camel case name for this error, matching the
    /// case names used by the Swift and TypeScript implementations and the
    /// shared conformance vectors.
    ///
    /// # Example
    ///
    /// ```
    /// assert_eq!(threemd::ParseError::MissingVersion.code(), "missingVersion");
    /// ```
    #[must_use]
    pub fn code(&self) -> &'static str {
        match self {
            ParseError::MissingFrontmatter => "missingFrontmatter",
            ParseError::InvalidFrontmatter(_) => "invalidFrontmatter",
            ParseError::MissingVersion => "missingVersion",
            ParseError::MissingPlanePosition { .. } => "missingPlanePosition",
            ParseError::InvalidPlaneDirective { .. } => "invalidPlaneDirective",
            ParseError::DuplicatePlane { .. } => "duplicatePlane",
        }
    }
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::MissingFrontmatter => {
                write!(
                    formatter,
                    "3md documents must begin with a '---' frontmatter block."
                )
            }
            ParseError::InvalidFrontmatter(detail) => {
                write!(formatter, "Invalid frontmatter: {detail}")
            }
            ParseError::MissingVersion => {
                write!(
                    formatter,
                    "Frontmatter is missing the required '3md' version key."
                )
            }
            ParseError::MissingPlanePosition { line } => {
                write!(
                    formatter,
                    "The @plane directive on line {line} is missing a 'z' position."
                )
            }
            ParseError::InvalidPlaneDirective { line, detail } => {
                write!(
                    formatter,
                    "Invalid @plane directive on line {line}: {detail}"
                )
            }
            ParseError::DuplicatePlane { z } => {
                write!(formatter, "Two planes share the same z position: {z}")
            }
        }
    }
}

impl std::error::Error for ParseError {}

// MARK: - Lexing helpers

const RESERVED_PLANE_KEYS: [&str; 4] = ["z", "x", "y", "label"];

/// Trims leading and trailing space and tab characters, mirroring the Swift
/// `trimmingCharacters(in: .whitespaces)` used throughout the parser. Lines are
/// already split on newlines, so only horizontal whitespace is relevant.
fn trim_whitespace(value: &str) -> &str {
    value.trim_matches([' ', '\t'])
}

/// Returns the first space/tab-delimited token of a line, or the empty string.
fn first_token(line: &str) -> &str {
    line.split([' ', '\t'])
        .find(|token| !token.is_empty())
        .unwrap_or("")
}

/// Splits a directive remainder into tokens, keeping single- or double-quoted
/// spans intact. A backslash inside a quoted span escapes the next character, so
/// `\"` does not close a double-quoted value. Returns an error on an
/// unterminated quote.
fn tokenize(input: &str, line: usize) -> Result<Vec<String>, ParseError> {
    let mut tokens: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut active_quote: Option<char> = None;
    let mut escaped = false;

    for character in input.chars() {
        if let Some(quote) = active_quote {
            current.push(character);
            if escaped {
                escaped = false;
            } else if character == '\\' {
                escaped = true;
            } else if character == quote {
                active_quote = None;
            }
        } else if character == '"' || character == '\'' {
            active_quote = Some(character);
            current.push(character);
        } else if character == ' ' || character == '\t' {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
        } else {
            current.push(character);
        }
    }

    if active_quote.is_some() {
        return Err(ParseError::InvalidPlaneDirective {
            line,
            detail: format!("unterminated quote in '{input}'"),
        });
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    Ok(tokens)
}

/// Strips a single pair of matching surrounding quotes and reverses backslash
/// escaping (`\\` and `\"`). Mirrors the Swift `unquote(_:)` helper.
fn unquote(value: &str) -> String {
    let characters: Vec<char> = value.chars().collect();
    if characters.len() >= 2 {
        let first = characters[0];
        let last = characters[characters.len() - 1];
        if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
            let inner: String = characters[1..characters.len() - 1].iter().collect();
            return unescape(&inner);
        }
    }
    value.to_string()
}

/// Reverses the serializer's backslash escaping, so `\\` becomes `\` and `\"`
/// becomes `"`. Any other escaped character yields the character itself.
fn unescape(value: &str) -> String {
    let mut result = String::new();
    let mut escaping = false;
    for character in value.chars() {
        if escaping {
            result.push(character);
            escaping = false;
        } else if character == '\\' {
            escaping = true;
        } else {
            result.push(character);
        }
    }
    if escaping {
        result.push('\\');
    }
    result
}

/// Returns the fence character if a trimmed line opens a fenced code block
/// (three or more backticks or tildes), otherwise `None`.
fn fence_character(trimmed: &str) -> Option<char> {
    if trimmed.starts_with("```") {
        Some('`')
    } else if trimmed.starts_with("~~~") {
        Some('~')
    } else {
        None
    }
}

/// Joins body lines, dropping leading and trailing blank lines. Returns `None`
/// when nothing but whitespace remains.
fn collapse(lines: &[String]) -> Option<String> {
    let mut start = 0;
    let mut end = lines.len();
    while start < end && trim_whitespace(&lines[start]).is_empty() {
        start += 1;
    }
    while end > start && trim_whitespace(&lines[end - 1]).is_empty() {
        end -= 1;
    }
    if start >= end {
        return None;
    }
    Some(lines[start..end].join("\n"))
}

/// Parses a finite decimal number for `z`/`x`/`y`: optional sign, digits with an
/// optional fraction, and an optional exponent. Hex, `inf`, `nan`, and values
/// that overflow to infinity are rejected, so all implementations agree on the
/// numeric grammar.
///
/// This hand-rolls the grammar `^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$`, then
/// parses to `f64` and requires the result to be finite.
fn parse_finite_decimal(text: &str) -> Option<f64> {
    if !matches_decimal_grammar(text) {
        return None;
    }
    match text.parse::<f64>() {
        Ok(value) if value.is_finite() => Some(value),
        _ => None,
    }
}

/// Matches the regular expression `^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$`
/// without any regex dependency.
fn matches_decimal_grammar(text: &str) -> bool {
    let bytes = text.as_bytes();
    let length = bytes.len();
    let mut index = 0;

    // Optional sign.
    if index < length && (bytes[index] == b'+' || bytes[index] == b'-') {
        index += 1;
    }

    // Mantissa: either `digits[.digits?]` or `.digits`.
    if index < length && bytes[index] == b'.' {
        // `.\d+`
        index += 1;
        let fraction_start = index;
        while index < length && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if index == fraction_start {
            return false;
        }
    } else {
        // `\d+\.?\d*`
        let integer_start = index;
        while index < length && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if index == integer_start {
            return false;
        }
        if index < length && bytes[index] == b'.' {
            index += 1;
            while index < length && bytes[index].is_ascii_digit() {
                index += 1;
            }
        }
    }

    // Optional exponent: `[eE][+-]?\d+`.
    if index < length && (bytes[index] == b'e' || bytes[index] == b'E') {
        index += 1;
        if index < length && (bytes[index] == b'+' || bytes[index] == b'-') {
            index += 1;
        }
        let exponent_start = index;
        while index < length && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if index == exponent_start {
            return false;
        }
    }

    index == length
}

// MARK: - Parser internals

struct ExtractedFrontmatter {
    fields: Vec<(String, String)>,
    /// 1-based line number of the first body line, after the closing `---`.
    body_start_line: usize,
    /// The remaining body lines after the closing fence.
    body: Vec<String>,
}

struct PendingPlane {
    line_number: usize,
    attributes: BTreeMap<String, String>,
    body_lines: Vec<String>,
}

fn extract_frontmatter(lines: &[String]) -> Result<ExtractedFrontmatter, ParseError> {
    let mut index = 0;
    while index < lines.len() && trim_whitespace(&lines[index]).is_empty() {
        index += 1;
    }
    if index >= lines.len() || trim_whitespace(&lines[index]) != "---" {
        return Err(ParseError::MissingFrontmatter);
    }

    index += 1;
    let mut fields: Vec<(String, String)> = Vec::new();

    while index < lines.len() {
        let trimmed = trim_whitespace(&lines[index]);
        if trimmed == "---" {
            let body_start = index + 1;
            let body = if body_start < lines.len() {
                lines[body_start..].to_vec()
            } else {
                Vec::new()
            };
            return Ok(ExtractedFrontmatter {
                fields,
                body_start_line: index + 2,
                body,
            });
        }
        if !trimmed.is_empty() && !trimmed.starts_with('#') {
            match trimmed.find(':') {
                None => {
                    return Err(ParseError::InvalidFrontmatter(format!(
                        "expected 'key: value', found '{trimmed}'"
                    )));
                }
                Some(separator) => {
                    let key = trim_whitespace(&trimmed[..separator]).to_string();
                    let raw = trim_whitespace(&trimmed[separator + 1..]);
                    fields.push((key, unquote(raw)));
                }
            }
        }
        index += 1;
    }

    Err(ParseError::InvalidFrontmatter(
        "frontmatter block was not closed with '---'".to_string(),
    ))
}

struct InterpretedFrontmatter {
    version: String,
    axis: String,
    title: Option<String>,
    metadata: BTreeMap<String, String>,
}

fn interpret_frontmatter(
    fields: &[(String, String)],
) -> Result<InterpretedFrontmatter, ParseError> {
    let mut version: Option<String> = None;
    let mut axis_value = String::from("layer");
    let mut title: Option<String> = None;
    let mut metadata: BTreeMap<String, String> = BTreeMap::new();

    for (key, value) in fields {
        match key.to_lowercase().as_str() {
            "3md" => version = Some(value.clone()),
            "axis" => axis_value = axis(value),
            "title" => title = Some(value.clone()),
            _ => {
                metadata.insert(key.clone(), value.clone());
            }
        }
    }

    match version {
        Some(resolved) if !resolved.is_empty() => Ok(InterpretedFrontmatter {
            version: resolved,
            axis: axis_value,
            title,
            metadata,
        }),
        _ => Err(ParseError::MissingVersion),
    }
}

fn parse_directive(trimmed: &str, line: usize) -> Result<BTreeMap<String, String>, ParseError> {
    let remainder = trim_whitespace(&trimmed["@plane".len()..]);
    let mut result: BTreeMap<String, String> = BTreeMap::new();

    for token in tokenize(remainder, line)? {
        match token.find('=') {
            None => {
                return Err(ParseError::InvalidPlaneDirective {
                    line,
                    detail: format!("expected key=value, found '{token}'"),
                });
            }
            Some(separator) => {
                let key = trim_whitespace(&token[..separator]).to_lowercase();
                let value = unquote(trim_whitespace(&token[separator + 1..]));
                if key.is_empty() {
                    return Err(ParseError::InvalidPlaneDirective {
                        line,
                        detail: format!("empty attribute key in '{token}'"),
                    });
                }
                result.insert(key, value);
            }
        }
    }

    Ok(result)
}

fn optional_double(
    value: Option<&String>,
    key: &str,
    line: usize,
) -> Result<Option<f64>, ParseError> {
    match value {
        None => Ok(None),
        Some(raw) => match parse_finite_decimal(raw) {
            Some(number) => Ok(Some(number)),
            None => Err(ParseError::InvalidPlaneDirective {
                line,
                detail: format!("{key} must be a finite decimal number, found '{raw}'"),
            }),
        },
    }
}

fn make_plane(pending: PendingPlane) -> Result<Plane, ParseError> {
    let attributes = pending.attributes;
    let line = pending.line_number;

    let z_raw = attributes
        .get("z")
        .ok_or(ParseError::MissingPlanePosition { line })?;
    let z = parse_finite_decimal(z_raw).ok_or_else(|| ParseError::InvalidPlaneDirective {
        line,
        detail: format!("z must be a finite decimal number, found '{z_raw}'"),
    })?;

    let x = optional_double(attributes.get("x"), "x", line)?;
    let y = optional_double(attributes.get("y"), "y", line)?;
    let label = attributes.get("label").cloned();

    let mut extras: BTreeMap<String, String> = BTreeMap::new();
    for (key, value) in &attributes {
        if !RESERVED_PLANE_KEYS.contains(&key.as_str()) {
            extras.insert(key.clone(), value.clone());
        }
    }

    let body = collapse(&pending.body_lines).unwrap_or_default();
    Ok(Plane {
        z,
        label,
        x,
        y,
        attributes: extras,
        body,
    })
}

struct ParsedBody {
    preamble: Option<String>,
    planes: Vec<Plane>,
}

fn parse_body(lines: &[String], body_start_line: usize) -> Result<ParsedBody, ParseError> {
    let mut seen_z: Vec<f64> = Vec::new();
    let mut planes: Vec<Plane> = Vec::new();
    let mut pending: Option<PendingPlane> = None;
    let mut preamble_lines: Vec<String> = Vec::new();
    let mut fence: Option<char> = None;

    for (offset, raw) in lines.iter().enumerate() {
        let line_number = body_start_line + offset;
        let trimmed = trim_whitespace(raw);

        // A directive must begin at column 0 and sit outside a fenced code
        // block, so a `@plane` line inside ``` or ~~~ (or indented as a code
        // block) is body text, not a new plane.
        let mut is_directive = false;
        if let Some(open) = fence {
            let closing: String = [open, open, open].iter().collect();
            if trimmed.starts_with(&closing) {
                fence = None;
            }
        } else if let Some(opened) = fence_character(trimmed) {
            fence = Some(opened);
        } else if !raw.starts_with(' ') && !raw.starts_with('\t') && first_token(raw) == "@plane" {
            is_directive = true;
        }

        if !is_directive {
            match pending.as_mut() {
                Some(current) => current.body_lines.push(raw.clone()),
                None => preamble_lines.push(raw.clone()),
            }
            continue;
        }

        if let Some(flushed) = pending.take() {
            flush_pending(flushed, &mut seen_z, &mut planes)?;
        }

        let attributes = parse_directive(trimmed, line_number)?;
        pending = Some(PendingPlane {
            line_number,
            attributes,
            body_lines: Vec::new(),
        });
    }

    if let Some(flushed) = pending.take() {
        flush_pending(flushed, &mut seen_z, &mut planes)?;
    }

    let preamble = collapse(&preamble_lines);

    if planes.is_empty() {
        return match preamble {
            None => Ok(ParsedBody {
                preamble: None,
                planes: Vec::new(),
            }),
            Some(content) => Ok(ParsedBody {
                preamble: None,
                planes: vec![Plane {
                    z: 0.0,
                    label: None,
                    x: None,
                    y: None,
                    attributes: BTreeMap::new(),
                    body: content,
                }],
            }),
        };
    }

    Ok(ParsedBody { preamble, planes })
}

fn flush_pending(
    pending: PendingPlane,
    seen_z: &mut Vec<f64>,
    planes: &mut Vec<Plane>,
) -> Result<(), ParseError> {
    let plane = make_plane(pending)?;
    if seen_z.contains(&plane.z) {
        return Err(ParseError::DuplicatePlane { z: plane.z });
    }
    seen_z.push(plane.z);
    planes.push(plane);
    Ok(())
}

// MARK: - Public API

/// Parses 3md source text into a [`Document`].
///
/// Frontmatter is required and must declare a `3md` version key (the format's
/// magic marker). Planes are introduced by `@plane` directives carrying
/// `key=value` attributes; the text between directives is plain Markdown. A
/// document with no directives parses as a single plane at `z = 0`.
///
/// A leading UTF-8 byte order mark is stripped and CRLF line endings are
/// normalized to LF before parsing.
///
/// # Errors
///
/// Returns a [`ParseError`] when the source is malformed. Use
/// [`ParseError::code`] to get the canonical case name (`missingFrontmatter`,
/// `invalidFrontmatter`, `missingVersion`, `missingPlanePosition`,
/// `invalidPlaneDirective`, or `duplicatePlane`).
pub fn parse(source: &str) -> Result<Document, ParseError> {
    let mut normalized = source.replace("\r\n", "\n");
    if let Some(stripped) = normalized.strip_prefix('\u{FEFF}') {
        normalized = stripped.to_string();
    }
    let lines: Vec<String> = normalized.split('\n').map(str::to_string).collect();

    let frontmatter = extract_frontmatter(&lines)?;
    let interpreted = interpret_frontmatter(&frontmatter.fields)?;
    let parsed_body = parse_body(&frontmatter.body, frontmatter.body_start_line)?;

    Ok(Document {
        version: interpreted.version,
        axis: interpreted.axis,
        title: interpreted.title,
        metadata: interpreted.metadata,
        preamble: parsed_body.preamble,
        planes: parsed_body.planes,
    })
}

/// Extracts every cross-plane link from a [`Document`]'s plane bodies.
///
/// A cross-plane link matches the regular expression
/// `\[\[z=([^\]|]+)(?:\|([^\]]*))?\]\]`. The captured target is validated as a
/// finite decimal with the same grammar as the `z` attribute; if it is not a
/// finite decimal, the sequence is not a link and is ignored. The optional
/// second group is the link text: `None` when absent, `Some(value)` (which may
/// be `Some("")`) when present.
///
/// Links are returned in document order: planes in source order, then links
/// left to right within each body. [`CrossPlaneLink::target_exists`] reports
/// whether any plane in the document has a `z` equal to the link's target,
/// using the same numeric equality as duplicate detection.
#[must_use]
pub fn links(document: &Document) -> Vec<CrossPlaneLink> {
    let known_z: Vec<f64> = document.planes.iter().map(|plane| plane.z).collect();
    let mut result: Vec<CrossPlaneLink> = Vec::new();

    for plane in &document.planes {
        extract_links(&plane.body, plane.z, &known_z, &mut result);
    }

    result
}

impl Document {
    /// Extracts every cross-plane link from this document's plane bodies, in
    /// document order. See the free function [`links`] for the full contract.
    #[must_use]
    pub fn links(&self) -> Vec<CrossPlaneLink> {
        links(self)
    }
}

/// Scans a single body string for `[[z=...]]` patterns, equivalent to the regex
/// `\[\[z=([^\]|]+)(?:\|([^\]]*))?\]\]`, and appends one record per valid link.
fn extract_links(body: &str, source_z: f64, known_z: &[f64], result: &mut Vec<CrossPlaneLink>) {
    if body.is_empty() {
        return;
    }

    let characters: Vec<char> = body.chars().collect();
    let length = characters.len();
    let mut index = 0;

    while index < length {
        // Look for the literal opener `[[z=`.
        if index + 4 <= length
            && characters[index] == '['
            && characters[index + 1] == '['
            && characters[index + 2] == 'z'
            && characters[index + 3] == '='
        {
            if let Some((link, next)) = scan_link(&characters, index + 4, source_z, known_z) {
                if let Some(found) = link {
                    result.push(found);
                }
                index = next;
                continue;
            }
        }
        index += 1;
    }
}

/// Scans a candidate link starting just after `[[z=`. Returns the parsed link
/// (or `None` when the target is not a finite decimal but the `]]` closer was
/// still found) together with the index just past the closing `]]`, or `None`
/// when no closing `]]` is present, mirroring the regex semantics.
fn scan_link(
    characters: &[char],
    start: usize,
    source_z: f64,
    known_z: &[f64],
) -> Option<(Option<CrossPlaneLink>, usize)> {
    let length = characters.len();

    // Target group: `[^\]|]+` (one or more characters that are not `]` or `|`).
    let mut index = start;
    let target_start = index;
    while index < length && characters[index] != ']' && characters[index] != '|' {
        index += 1;
    }
    if index == target_start {
        // Empty target: `[^\]|]+` requires at least one character.
        return None;
    }
    let target: String = characters[target_start..index].iter().collect();

    // Optional text group: `(?:\|([^\]]*))?`.
    let mut text: Option<String> = None;
    if index < length && characters[index] == '|' {
        index += 1;
        let text_start = index;
        while index < length && characters[index] != ']' {
            index += 1;
        }
        text = Some(characters[text_start..index].iter().collect());
    }

    // Closer: `]]`.
    if index + 2 > length || characters[index] != ']' || characters[index + 1] != ']' {
        return None;
    }
    let after = index + 2;

    match parse_finite_decimal(&target) {
        Some(target_z) => {
            let target_exists = known_z.contains(&target_z);
            Some((
                Some(CrossPlaneLink {
                    source_z,
                    target_z,
                    text,
                    target_exists,
                }),
                after,
            ))
        }
        None => Some((None, after)),
    }
}

// MARK: - Serializer

/// Formats a number as an integer string when it is whole and within a safe
/// range, falling back to the default decimal representation otherwise. Mirrors
/// the Swift `formatted3MD()` helper and the TypeScript `formatNumber`.
fn format_number(value: f64) -> String {
    if value == value.round() && value.abs() < 1e15 {
        format!("{}", value as i64)
    } else {
        let mut text = format!("{value}");
        if !text.contains('.') && !text.contains('e') && !text.contains('E') && value.is_finite() {
            text.push_str(".0");
        }
        text
    }
}

/// Wraps a value in double quotes when it contains whitespace, a quote, a
/// backslash, or is empty (or when `force_quote` is `true`). Backslashes and
/// double-quotes are escaped so the value round-trips through [`parse`].
fn quote_if_needed(value: &str, force_quote: bool) -> String {
    let needs_quote = force_quote
        || value.contains(' ')
        || value.contains('\t')
        || value.contains('"')
        || value.contains('\\')
        || value.is_empty();
    if !needs_quote {
        return value.to_string();
    }
    let escaped = value.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{escaped}\"")
}

fn frontmatter_lines(document: &Document) -> Vec<String> {
    let mut lines = vec![
        "---".to_string(),
        format!("3md: {}", document.version),
        format!("axis: {}", document.axis),
    ];

    if let Some(title) = &document.title {
        lines.push(format!("title: {}", quote_if_needed(title, false)));
    }

    // BTreeMap iterates in sorted key order, matching the Swift/TS sort.
    for (key, value) in &document.metadata {
        lines.push(format!("{key}: {}", quote_if_needed(value, false)));
    }
    lines.push("---".to_string());

    lines
}

fn directive_line(plane: &Plane) -> String {
    let mut parts = vec![
        "@plane".to_string(),
        format!("z={}", format_number(plane.z)),
    ];

    if let Some(label) = &plane.label {
        parts.push(format!("label={}", quote_if_needed(label, true)));
    }
    if let Some(x) = plane.x {
        parts.push(format!("x={}", format_number(x)));
    }
    if let Some(y) = plane.y {
        parts.push(format!("y={}", format_number(y)));
    }

    for (key, value) in &plane.attributes {
        parts.push(format!("{key}={}", quote_if_needed(value, true)));
    }

    parts.join(" ")
}

/// Renders a [`Document`] back into 3md source text.
///
/// The output round-trips through [`parse`]: parsing serialized text yields an
/// equivalent document. Quoted values are escaped on the way out and unescaped
/// on the way in, so values containing spaces, quotes, or backslashes
/// round-trip exactly. Mirrors the Swift `Serializer`.
#[must_use]
pub fn serialize(document: &Document) -> String {
    let mut lines = frontmatter_lines(document);

    if let Some(preamble) = &document.preamble {
        lines.push(String::new());
        lines.push(preamble.clone());
    }

    for plane in &document.planes {
        lines.push(String::new());
        lines.push(directive_line(plane));
        if !plane.body.is_empty() {
            lines.push(plane.body.clone());
        }
    }

    let mut output = lines.join("\n");
    output.push('\n');
    output
}

impl Document {
    /// Renders this document back into 3md source text. See the free function
    /// [`serialize`] for the full contract.
    #[must_use]
    pub fn serialize(&self) -> String {
        serialize(self)
    }
}
