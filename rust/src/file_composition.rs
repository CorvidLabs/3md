//! Resolve explicitly supplied file bytes into a self-contained composition, without filesystem IO.
use crate::composition::{
    self, DocumentComposition, DocumentCompositionError, DocumentCompositionLimits, DocumentEntry,
    DocumentReference,
};
use crate::storage::{self, DocumentDecodeLimits, DocumentStorageError, OperationOptions};
use crate::Document;
use std::collections::{BTreeMap, BTreeSet};
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, Clone, PartialEq, Eq)]
/// Caller-supplied readable or supported binary bytes named relative to a project root.
pub struct DocumentFileSource {
    pub path: String,
    pub data: Vec<u8>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
/// A host-interpreted printable ASCII glyph and its containing-file-relative source name.
pub struct DocumentFileReference {
    pub glyph: String,
    pub source: String,
}
#[derive(Debug, Clone, PartialEq)]
/// A self-contained graph plus normalized mappings for its reachable supplied files.
pub struct DocumentFileCompositionResult {
    pub root_path: String,
    pub composition: DocumentComposition,
    pub file_root_ids: BTreeMap<String, String>,
    pub resolved_paths: Vec<String>,
}
#[derive(Debug, Clone, PartialEq)]
/// File intake failures; wrapped storage/composition failures retain their stable codes and causes.
pub enum DocumentFileCompositionError {
    InvalidPath(String),
    DuplicatePath(String),
    InvalidLedger(String),
    InvalidGlyph(String),
    MissingFile(String),
    InputLimit,
    Storage(DocumentStorageError),
    Composition(DocumentCompositionError),
}
impl DocumentFileCompositionError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidPath(_) => "invalidPath",
            Self::DuplicatePath(_) => "duplicatePath",
            Self::InvalidLedger(_) => "invalidLedger",
            Self::InvalidGlyph(_) => "invalidGlyph",
            Self::MissingFile(_) => "missingFile",
            Self::InputLimit => "inputLimit",
            Self::Storage(error) => error.code(),
            Self::Composition(error) => error.code(),
        }
    }
}
impl std::fmt::Display for DocumentFileCompositionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Storage(error) => write!(f, "{error}"),
            Self::Composition(error) => write!(f, "{error}"),
            Self::InvalidPath(path) => write!(f, "Invalid project-relative path: {path}"),
            Self::DuplicatePath(path) => write!(f, "Duplicate normalized supplied path: {path}"),
            Self::InvalidLedger(detail) => write!(f, "Invalid 3md-files ledger: {detail}"),
            Self::InvalidGlyph(glyph) => write!(f, "Invalid file binding glyph: {glyph}"),
            Self::MissingFile(path) => write!(f, "Missing supplied file: {path}"),
            Self::InputLimit => write!(f, "Supplied file composition exceeds its input policy."),
        }
    }
}
impl std::error::Error for DocumentFileCompositionError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Storage(error) => Some(error),
            Self::Composition(error) => Some(error),
            _ => None,
        }
    }
}
impl From<DocumentStorageError> for DocumentFileCompositionError {
    fn from(error: DocumentStorageError) -> Self {
        Self::Storage(error)
    }
}
impl From<DocumentCompositionError> for DocumentFileCompositionError {
    fn from(error: DocumentCompositionError) -> Self {
        Self::Composition(error)
    }
}
type Result<T> = std::result::Result<T, DocumentFileCompositionError>;

// Independent discovery safety ceiling, the standard maximum depth. Embedded disconnected entries
// do not extend the final root entry path; the caller's maximum_depth applies after remapping the
// complete entry graph.
fn maximum_file_discovery_depth() -> usize {
    DocumentCompositionLimits::default().maximum_depth
}

/// Read a strict glyph-to-filename ledger. Filenames are interpreted only during explicit resolution.
pub fn ledger(
    document: &Document,
    options: &OperationOptions,
) -> std::result::Result<Vec<DocumentFileReference>, DocumentFileCompositionError> {
    options.check()?;
    let Some(source) = document.metadata.get("3md-files") else {
        return Ok(Vec::new());
    };
    if source.len() > DocumentDecodeLimits::default().maximum_record_bytes {
        return Err(DocumentFileCompositionError::InputLimit);
    }
    let mut reader = LedgerReader {
        bytes: source.as_bytes(),
        index: 0,
        options,
    };
    let values = reader.object()?;
    let mut result = Vec::with_capacity(values.len());
    for (glyph, source) in values {
        options.check()?;
        result.push(DocumentFileReference { glyph, source });
    }
    Ok(result)
}

/// Resolve a relative filename against its containing file; no path is opened or percent-decoded.
pub fn resolve_path(
    source: &str,
    relative_to: &str,
    options: &OperationOptions,
) -> std::result::Result<String, DocumentFileCompositionError> {
    options.check()?;
    check_path_bytes(source, relative_to.len())?;
    let owner = normalize(relative_to, None, options)?;
    normalize(source, Some(&ContainingFile::new(&owner)), options)
}

/// A normalized containing filename whose directory boundaries are located once per discovered file.
struct ContainingFile<'a> {
    path: &'a str,
    /// The byte offset of every separator, which is also the end of each directory segment.
    directory_ends: Vec<usize>,
}
impl<'a> ContainingFile<'a> {
    fn new(path: &'a str) -> Self {
        Self {
            path,
            directory_ends: path.match_indices('/').map(|(index, _)| index).collect(),
        }
    }
}

/// The standalone record bound: the containing filename and reference together fit one record.
fn check_path_bytes(source: &str, containing_bytes: usize) -> Result<()> {
    let bound = DocumentDecodeLimits::default().maximum_record_bytes;
    if containing_bytes > bound || source.len() > bound - containing_bytes {
        return Err(DocumentFileCompositionError::InputLimit);
    }
    Ok(())
}

/// Resolve one ledger reference against an owner normalized once, with the same bound as resolve_path.
fn resolve_reference(
    source: &str,
    owner: &ContainingFile<'_>,
    options: &OperationOptions,
) -> Result<String> {
    options.check()?;
    check_path_bytes(source, owner.path.len())?;
    normalize(source, Some(owner), options)
}

fn normalize(
    path: &str,
    base: Option<&ContainingFile<'_>>,
    options: &OperationOptions,
) -> Result<String> {
    options.check()?;
    if path.is_empty() || path.starts_with('/') || path.ends_with('/') {
        return Err(DocumentFileCompositionError::InvalidPath(path.into()));
    }
    for (index, byte) in path.bytes().enumerate() {
        if index.is_multiple_of(1024) {
            options.check()?;
        }
        if byte.is_ascii_control() || byte == b'\\' || byte == b':' {
            return Err(DocumentFileCompositionError::InvalidPath(path.into()));
        }
    }
    let normalized = normalized_key(path, options)?;
    // One stack: the kept base directory segments followed by the source's own segments.
    let mut kept = base.map_or(0, |base| base.directory_ends.len());
    let mut segments: Vec<&str> = Vec::new();
    for segment in normalized.split('/') {
        options.check()?;
        match segment {
            "" => return Err(DocumentFileCompositionError::InvalidPath(path.into())),
            "." => {}
            ".." => {
                if segments.pop().is_none() {
                    if kept == 0 {
                        return Err(DocumentFileCompositionError::InvalidPath(path.into()));
                    }
                    kept -= 1;
                }
            }
            _ => segments.push(segment),
        }
    }
    let prefix = match base {
        Some(base) if kept > 0 => &base.path[..base.directory_ends[kept - 1]],
        _ => "",
    };
    if prefix.is_empty() && segments.is_empty() {
        return Err(DocumentFileCompositionError::InvalidPath(path.into()));
    }
    let mut result = String::with_capacity(prefix.len() + 1 + normalized.len());
    result.push_str(prefix);
    for segment in segments {
        if !result.is_empty() {
            result.push('/');
        }
        result.push_str(segment);
    }
    Ok(result)
}

fn normalized_key(value: &str, options: &OperationOptions) -> Result<String> {
    let mut stopped = false;
    let normalized = value
        .chars()
        .enumerate()
        .map_while(|(index, character)| {
            if index.is_multiple_of(256) && options.check().is_err() {
                stopped = true;
                None
            } else {
                Some(character)
            }
        })
        .nfc()
        .collect();
    if stopped {
        options.check()?;
    }
    options.check()?;
    Ok(normalized)
}

struct ImportedFile {
    root_id: String,
    entries: Vec<DocumentEntry>,
    ledgers: BTreeMap<String, Vec<DocumentFileReference>>,
    depth: usize,
}
struct Resolver<'a> {
    sources: BTreeMap<String, &'a DocumentFileSource>,
    files: BTreeMap<String, ImportedFile>,
    active: BTreeSet<String>,
    limits: &'a DocumentCompositionLimits,
    document_limits: &'a DocumentDecodeLimits,
    options: &'a OperationOptions,
    encoded_bytes: usize,
    definitions: usize,
    references: usize,
    maximum_discovery_depth: usize,
}
impl Resolver<'_> {
    fn visit(&mut self, path: &str, active_depth: usize) -> Result<usize> {
        self.options.check()?;
        if self.active.contains(path) {
            return Err(DocumentCompositionError::Cycle(path.into()).into());
        }
        if let Some(file) = self.files.get(path) {
            if active_depth >= self.maximum_discovery_depth
                || file.depth > self.maximum_discovery_depth - active_depth
            {
                return Err(DocumentCompositionError::DepthExceeded.into());
            }
            return Ok(file.depth);
        }
        if active_depth >= self.maximum_discovery_depth {
            return Err(DocumentCompositionError::DepthExceeded.into());
        }
        let source = self
            .sources
            .get(path)
            .ok_or_else(|| DocumentFileCompositionError::MissingFile(path.into()))?;
        if source.data.len() > self.limits.maximum_profile_bytes - self.encoded_bytes {
            return Err(DocumentFileCompositionError::InputLimit);
        }
        self.encoded_bytes += source.data.len();
        // Recognition must accommodate the larger outer profile record. Ordinary documents are
        // decoded again under the caller's child policy, including original byte/preflight bounds.
        let recognition_limits = DocumentDecodeLimits {
            maximum_encoded_bytes: self.limits.maximum_profile_bytes,
            maximum_decoded_bytes: self.limits.maximum_profile_bytes,
            maximum_record_bytes: self.limits.maximum_profile_bytes,
            ..DocumentDecodeLimits::default()
        };
        let document = storage::decode(&source.data, &recognition_limits, self.options)?;
        let (root_id, entries) = if composition::is_composition(&document) {
            let graph = composition::decode_document(
                &document,
                self.limits,
                self.document_limits,
                self.options,
            )?;
            (graph.root_id().to_owned(), graph.entries().to_vec())
        } else {
            let document = storage::decode(&source.data, self.document_limits, self.options)?;
            (
                "root".into(),
                vec![DocumentEntry {
                    id: "root".into(),
                    document,
                    references: Vec::new(),
                }],
            )
        };
        if entries.len() > self.limits.maximum_definitions - self.definitions {
            return Err(DocumentCompositionError::TooManyDefinitions.into());
        }
        self.definitions += entries.len();
        let mut ledgers = BTreeMap::new();
        self.active.insert(path.into());
        let mut depth = 1;
        let owner = ContainingFile::new(path);
        for entry in &entries {
            self.options.check()?;
            let mut values = ledger(&entry.document, self.options)?;
            let remaining = self.limits.maximum_references - self.references;
            if entry.references.len() > remaining
                || values.len() > remaining - entry.references.len()
            {
                return Err(DocumentCompositionError::TooManyReferences.into());
            }
            self.references += entry.references.len() + values.len();
            for reference in &mut values {
                reference.source = resolve_reference(&reference.source, &owner, self.options)?;
                // Match the other ports' immediate DFS in local-ID then glyph order.
                let child_depth = self.visit(&reference.source, active_depth + 1)?;
                depth = depth.max(child_depth + 1);
                if depth > self.maximum_discovery_depth {
                    return Err(DocumentCompositionError::DepthExceeded.into());
                }
            }
            ledgers.insert(entry.id.clone(), values);
        }
        self.active.remove(path);
        self.files.insert(
            path.into(),
            ImportedFile {
                root_id,
                entries,
                ledgers,
                depth,
            },
        );
        Ok(depth)
    }
}

/// Resolve only reachable supplied bytes and preserve imported nested bundles, including unused entries.
/// Discovery and remapping are private; errors or cancellation never return a partial composition.
/// Cancellation observed anywhere, including inside composition validation, is reported as
/// `Storage(DocumentStorageError::Cancelled)`.
pub fn resolve(
    root_path: &str,
    sources: &[DocumentFileSource],
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> std::result::Result<DocumentFileCompositionResult, DocumentFileCompositionError> {
    resolve_supplied(root_path, sources, limits, document_limits, options).map_err(|error| {
        if matches!(
            error,
            DocumentFileCompositionError::Composition(DocumentCompositionError::Storage(
                DocumentStorageError::Cancelled
            ))
        ) {
            DocumentFileCompositionError::Storage(DocumentStorageError::Cancelled)
        } else {
            error
        }
    })
}

fn resolve_supplied(
    root_path: &str,
    sources: &[DocumentFileSource],
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentFileCompositionResult> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if sources.len() > limits.maximum_definitions {
        return Err(DocumentFileCompositionError::InputLimit);
    }
    let mut path_bytes = root_path.len();
    if path_bytes > limits.maximum_profile_bytes {
        return Err(DocumentFileCompositionError::InputLimit);
    }
    for source in sources {
        options.check()?;
        if source.path.len() > limits.maximum_profile_bytes - path_bytes {
            return Err(DocumentFileCompositionError::InputLimit);
        }
        path_bytes += source.path.len();
    }
    let root_path = normalize(root_path, None, options)?;
    let mut indexed = BTreeMap::new();
    for source in sources {
        let path = normalize(&source.path, None, options)?;
        if indexed.insert(path.clone(), source).is_some() {
            return Err(DocumentFileCompositionError::DuplicatePath(path));
        }
    }
    let mut resolver = Resolver {
        sources: indexed,
        files: BTreeMap::new(),
        active: BTreeSet::new(),
        limits,
        document_limits,
        options,
        encoded_bytes: 0,
        definitions: 0,
        references: 0,
        maximum_discovery_depth: maximum_file_discovery_depth(),
    };
    resolver.visit(&root_path, 0)?;
    // UTF-8 lexicographic ordering is Unicode scalar ordering. Paths are already NFC-normalized.
    let resolved_paths: Vec<String> = resolver.files.keys().cloned().collect();
    // One map per file, keyed by local ID, so remapping never copies or compares a full path per reference.
    let mut assigned: Vec<BTreeMap<&str, String>> = Vec::with_capacity(resolver.files.len());
    let mut file_root_ids = BTreeMap::new();
    let mut ordinal = 0_usize;
    for (path, file) in &resolver.files {
        options.check()?;
        let mut ids = BTreeMap::new();
        for entry in &file.entries {
            ids.insert(entry.id.as_str(), format!("file-{ordinal:06}"));
            ordinal += 1;
        }
        file_root_ids.insert(path.clone(), ids[file.root_id.as_str()].clone());
        assigned.push(ids);
    }
    let mut entries = Vec::with_capacity(resolver.definitions);
    for (file, ids) in resolver.files.values().zip(&assigned) {
        for entry in &file.entries {
            options.check()?;
            let mut document = entry.document.clone();
            document.metadata.remove("3md-files");
            let mut references =
                Vec::with_capacity(entry.references.len() + file.ledgers[&entry.id].len());
            for reference in &entry.references {
                options.check()?;
                references.push(DocumentReference {
                    target_id: ids[reference.target_id.as_str()].clone(),
                    attributes: reference.attributes.clone(),
                });
            }
            for reference in &file.ledgers[&entry.id] {
                options.check()?;
                references.push(DocumentReference {
                    target_id: file_root_ids[&reference.source].clone(),
                    attributes: BTreeMap::from([
                        ("glyph".into(), reference.glyph.clone()),
                        ("source-file".into(), reference.source.clone()),
                    ]),
                });
            }
            entries.push(DocumentEntry {
                id: ids[entry.id.as_str()].clone(),
                document,
                references,
            });
        }
    }
    let composition = DocumentComposition::new(
        file_root_ids[&root_path].clone(),
        entries,
        limits,
        document_limits,
        options,
    )?;
    // Charge the complete escaped outer profile, not only its unique canonical child text.
    composition::encode(&composition, limits, document_limits, options)?;
    options.check()?;
    Ok(DocumentFileCompositionResult {
        root_path,
        composition,
        file_root_ids,
        resolved_paths,
    })
}

struct LedgerReader<'a> {
    bytes: &'a [u8],
    index: usize,
    options: &'a OperationOptions,
}
impl LedgerReader<'_> {
    fn invalid<T>(&self, detail: &str) -> Result<T> {
        Err(DocumentFileCompositionError::InvalidLedger(detail.into()))
    }
    fn whitespace(&mut self) -> Result<()> {
        while self
            .bytes
            .get(self.index)
            .is_some_and(|byte| matches!(byte, b' ' | b'\t' | b'\n' | b'\r'))
        {
            if self.index.is_multiple_of(1024) {
                self.options.check()?;
            }
            self.index += 1;
        }
        Ok(())
    }
    fn consume(&mut self, byte: u8) -> Result<bool> {
        self.whitespace()?;
        if self.bytes.get(self.index) == Some(&byte) {
            self.index += 1;
            Ok(true)
        } else {
            Ok(false)
        }
    }
    fn object(&mut self) -> Result<BTreeMap<String, String>> {
        if !self.consume(b'{')? {
            return self.invalid("ledger must be a JSON object");
        }
        let mut values = BTreeMap::new();
        if !self.consume(b'}')? {
            loop {
                self.options.check()?;
                let key = self.string()?;
                if key.len() != 1 || !(0x21..=0x7e).contains(&key.as_bytes()[0]) {
                    return Err(DocumentFileCompositionError::InvalidGlyph(key));
                }
                if values.contains_key(&key) {
                    return self.invalid("duplicate JSON object key");
                }
                if !self.consume(b':')? {
                    return self.invalid("missing JSON colon");
                }
                let value = self.string()?;
                values.insert(key, value);
                if self.consume(b'}')? {
                    break;
                }
                if !self.consume(b',')? {
                    return self.invalid("missing JSON comma");
                }
            }
        }
        self.whitespace()?;
        if self.index != self.bytes.len() {
            return self.invalid("trailing JSON input");
        }
        Ok(values)
    }
    fn string(&mut self) -> Result<String> {
        if !self.consume(b'"')? {
            return self.invalid("ledger fields must be strings");
        }
        let mut output = Vec::new();
        loop {
            if self.index.is_multiple_of(1024) {
                self.options.check()?;
            }
            let Some(&byte) = self.bytes.get(self.index) else {
                return self.invalid("unterminated JSON string");
            };
            self.index += 1;
            match byte {
                b'"' => {
                    return String::from_utf8(output).map_err(|_| {
                        DocumentFileCompositionError::InvalidLedger("invalid UTF-8 string".into())
                    })
                }
                0..=31 => return self.invalid("unescaped JSON control"),
                b'\\' => {
                    let Some(&escape) = self.bytes.get(self.index) else {
                        return self.invalid("truncated JSON escape");
                    };
                    self.index += 1;
                    match escape {
                        b'"' | b'\\' | b'/' => output.push(escape),
                        b'b' => output.push(8),
                        b'f' => output.push(12),
                        b'n' => output.push(10),
                        b'r' => output.push(13),
                        b't' => output.push(9),
                        b'u' => {
                            let first = self.hex_quad()?;
                            let scalar = if (0xd800..=0xdbff).contains(&first) {
                                if self.bytes.get(self.index..self.index + 2) != Some(b"\\u") {
                                    return self.invalid("unpaired JSON surrogate");
                                }
                                self.index += 2;
                                let second = self.hex_quad()?;
                                if !(0xdc00..=0xdfff).contains(&second) {
                                    return self.invalid("unpaired JSON surrogate");
                                }
                                0x10000 + ((u32::from(first) - 0xd800) << 10) + u32::from(second)
                                    - 0xdc00
                            } else {
                                u32::from(first)
                            };
                            let Some(character) = char::from_u32(scalar) else {
                                return self.invalid("invalid JSON scalar");
                            };
                            let mut encoded = [0; 4];
                            output
                                .extend_from_slice(character.encode_utf8(&mut encoded).as_bytes());
                        }
                        _ => return self.invalid("invalid JSON escape"),
                    }
                }
                _ => output.push(byte),
            }
        }
    }
    fn hex_quad(&mut self) -> Result<u16> {
        let mut value = 0_u16;
        for _ in 0..4 {
            let Some(&byte) = self.bytes.get(self.index) else {
                return self.invalid("truncated Unicode escape");
            };
            self.index += 1;
            let digit = match byte {
                b'0'..=b'9' => byte - b'0',
                b'a'..=b'f' => byte - b'a' + 10,
                b'A'..=b'F' => byte - b'A' + 10,
                _ => return self.invalid("invalid Unicode escape"),
            };
            value = value * 16 + u16::from(digit);
        }
        Ok(value)
    }
}
