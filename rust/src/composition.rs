//! Self-contained named document graphs and the strict `3md-composition-1` profile.
use crate::storage::{
    self, DocumentDecodeLimits, DocumentStorageError, DocumentStorageFormat, OperationOptions,
};
use crate::{Document, Plane};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentReference {
    pub target_id: String,
    pub attributes: BTreeMap<String, String>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct DocumentEntry {
    pub id: String,
    pub document: Document,
    pub references: Vec<DocumentReference>,
}

/// A graph validated at construction. Definitions are sorted by ASCII ID.
#[derive(Debug, Clone, PartialEq)]
pub struct DocumentComposition {
    root_id: String,
    entries: Vec<DocumentEntry>,
}
impl DocumentComposition {
    pub fn new(
        root_id: String,
        mut entries: Vec<DocumentEntry>,
        limits: &DocumentCompositionLimits,
        document_limits: &DocumentDecodeLimits,
        options: &OperationOptions,
    ) -> Result<Self, DocumentCompositionError> {
        validate_graph(&root_id, &entries, limits, document_limits, options)?;
        entries.sort_by(|a, b| a.id.cmp(&b.id));
        options.check()?;
        Ok(Self { root_id, entries })
    }
    pub fn root_id(&self) -> &str {
        &self.root_id
    }
    pub fn entries(&self) -> &[DocumentEntry] {
        &self.entries
    }
    pub fn entry(&self, id: &str) -> Option<&DocumentEntry> {
        self.entries.iter().find(|entry| entry.id == id)
    }
    pub fn root_entry(&self) -> &DocumentEntry {
        // Construction guarantees a root. Fields are private so callers cannot invalidate it.
        self.entry(&self.root_id)
            .expect("validated root definition")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentCompositionLimits {
    pub maximum_definitions: usize,
    pub maximum_references: usize,
    pub maximum_depth: usize,
    pub maximum_definition_bytes: usize,
    pub maximum_traversal_occurrences: usize,
    pub maximum_profile_bytes: usize,
    pub maximum_reference_attributes: usize,
    pub maximum_reference_attribute_bytes: usize,
}
impl Default for DocumentCompositionLimits {
    fn default() -> Self {
        Self {
            maximum_definitions: 1024,
            maximum_references: 16_384,
            maximum_depth: 64,
            maximum_definition_bytes: 16 * 1024 * 1024,
            maximum_traversal_occurrences: 1_000_000,
            maximum_profile_bytes: 20 * 1024 * 1024,
            maximum_reference_attributes: 64,
            maximum_reference_attribute_bytes: 16 * 1024,
        }
    }
}
impl DocumentCompositionLimits {
    pub fn validate(&self) -> Result<(), DocumentCompositionError> {
        for (name, value, min, max) in [
            ("maximumDefinitions", self.maximum_definitions, 1, 1024),
            ("maximumReferences", self.maximum_references, 0, 16_384),
            ("maximumDepth", self.maximum_depth, 1, 64),
            (
                "maximumDefinitionBytes",
                self.maximum_definition_bytes,
                1,
                16 * 1024 * 1024,
            ),
            (
                "maximumTraversalOccurrences",
                self.maximum_traversal_occurrences,
                1,
                1_000_000,
            ),
            (
                "maximumProfileBytes",
                self.maximum_profile_bytes,
                1,
                20 * 1024 * 1024,
            ),
            (
                "maximumReferenceAttributes",
                self.maximum_reference_attributes,
                0,
                64,
            ),
            (
                "maximumReferenceAttributeBytes",
                self.maximum_reference_attribute_bytes,
                0,
                16 * 1024,
            ),
        ] {
            if !(min..=max).contains(&value) {
                return Err(DocumentCompositionError::InvalidLimits(name.into()));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum DocumentCompositionError {
    InvalidLimits(String),
    InvalidId(String),
    DuplicateId(String),
    MissingRoot(String),
    MissingTarget { from: String, target: String },
    Cycle(String),
    TooManyDefinitions,
    TooManyReferences,
    DepthExceeded,
    DefinitionBytesExceeded,
    TraversalOccurrencesExceeded,
    ReferenceAttributesExceeded,
    ProfileBytesExceeded,
    InvalidProfile(String),
    UnsupportedProfile(String),
    Storage(DocumentStorageError),
}
impl DocumentCompositionError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidLimits(_) => "invalidLimits",
            Self::InvalidId(_) => "invalidID",
            Self::DuplicateId(_) => "duplicateID",
            Self::MissingRoot(_) => "missingRoot",
            Self::MissingTarget { .. } => "missingTarget",
            Self::Cycle(_) => "cycle",
            Self::TooManyDefinitions => "tooManyDefinitions",
            Self::TooManyReferences => "tooManyReferences",
            Self::DepthExceeded => "depthExceeded",
            Self::DefinitionBytesExceeded => "definitionBytesExceeded",
            Self::TraversalOccurrencesExceeded => "traversalOccurrencesExceeded",
            Self::ReferenceAttributesExceeded => "referenceAttributesExceeded",
            Self::ProfileBytesExceeded => "profileBytesExceeded",
            Self::InvalidProfile(_) => "invalidProfile",
            Self::UnsupportedProfile(_) => "unsupportedProfile",
            Self::Storage(error) => error.code(),
        }
    }
}
impl std::fmt::Display for DocumentCompositionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Storage(error) => write!(f, "{error}"),
            Self::InvalidProfile(detail) => write!(f, "Invalid composition profile: {detail}"),
            Self::MissingTarget { from, target } => {
                write!(f, "Definition {from} references missing target {target}.")
            }
            Self::MissingRoot(id) => write!(f, "The composition root {id} is missing."),
            Self::Cycle(id) => write!(
                f,
                "The composition contains a reference cycle through {id}."
            ),
            _ => write!(f, "Document composition failed: {}", self.code()),
        }
    }
}
impl std::error::Error for DocumentCompositionError {}
impl From<DocumentStorageError> for DocumentCompositionError {
    fn from(error: DocumentStorageError) -> Self {
        Self::Storage(error)
    }
}

pub fn is_valid_id(id: &str) -> bool {
    (1..=64).contains(&id.len())
        && id.as_bytes()[0].is_ascii_alphanumeric()
        && id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
}

pub(crate) fn validate_graph(
    root_id: &str,
    entries: &[DocumentEntry],
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<BTreeMap<String, Vec<u8>>, DocumentCompositionError> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if !is_valid_id(root_id) {
        return Err(DocumentCompositionError::InvalidId(root_id.into()));
    }
    if entries.len() > limits.maximum_definitions {
        return Err(DocumentCompositionError::TooManyDefinitions);
    }
    let mut indices = BTreeMap::new();
    let mut sources = BTreeMap::new();
    let (mut reference_count, mut source_bytes) = (0, 0);
    for (index, entry) in entries.iter().enumerate() {
        options.check()?;
        if !is_valid_id(&entry.id) {
            return Err(DocumentCompositionError::InvalidId(entry.id.clone()));
        }
        if indices.insert(entry.id.as_str(), index).is_some() {
            return Err(DocumentCompositionError::DuplicateId(entry.id.clone()));
        }
        if entry.references.len() > limits.maximum_references - reference_count {
            return Err(DocumentCompositionError::TooManyReferences);
        }
        reference_count += entry.references.len();
        for reference in &entry.references {
            options.check()?;
            if !is_valid_id(&reference.target_id) {
                return Err(DocumentCompositionError::InvalidId(
                    reference.target_id.clone(),
                ));
            }
            if reference.attributes.len() > limits.maximum_reference_attributes {
                return Err(DocumentCompositionError::ReferenceAttributesExceeded);
            }
            let mut bytes = 0;
            for (key, value) in &reference.attributes {
                for text in [key, value] {
                    if text.len() > limits.maximum_reference_attribute_bytes - bytes {
                        return Err(DocumentCompositionError::ReferenceAttributesExceeded);
                    }
                    bytes += text.len();
                }
            }
            storage::canonical_keys(&reference.attributes, options)?;
        }
        let remaining = limits.maximum_definition_bytes - source_bytes;
        if remaining == 0 {
            return Err(DocumentCompositionError::DefinitionBytesExceeded);
        }
        let child_limits = DocumentDecodeLimits {
            maximum_encoded_bytes: document_limits.maximum_encoded_bytes.min(remaining),
            maximum_decoded_bytes: document_limits.maximum_decoded_bytes.min(remaining),
            maximum_lines: document_limits.maximum_lines,
            maximum_planes: document_limits.maximum_planes,
            maximum_record_bytes: document_limits.maximum_record_bytes.min(remaining),
        };
        let source = storage::encode(
            &entry.document,
            DocumentStorageFormat::Text,
            &child_limits,
            options,
        )
        .map_err(|error| match error {
            DocumentStorageError::OversizedInput
                if remaining <= document_limits.maximum_encoded_bytes =>
            {
                DocumentCompositionError::DefinitionBytesExceeded
            }
            DocumentStorageError::OversizedOutput
                if remaining <= document_limits.maximum_decoded_bytes =>
            {
                DocumentCompositionError::DefinitionBytesExceeded
            }
            DocumentStorageError::OversizedRecord
                if remaining <= document_limits.maximum_record_bytes =>
            {
                DocumentCompositionError::DefinitionBytesExceeded
            }
            other => other.into(),
        })?;
        source_bytes += source.len();
        sources.insert(entry.id.clone(), source);
    }
    if !indices.contains_key(root_id) {
        return Err(DocumentCompositionError::MissingRoot(root_id.into()));
    }
    for entry in entries {
        for reference in &entry.references {
            options.check()?;
            if !indices.contains_key(reference.target_id.as_str()) {
                return Err(DocumentCompositionError::MissingTarget {
                    from: entry.id.clone(),
                    target: reference.target_id.clone(),
                });
            }
        }
    }
    let mut graph = Graph {
        entries,
        indices: &indices,
        limits,
        options,
        states: vec![0; entries.len()],
        depths: vec![0; entries.len()],
        occurrences: vec![0; entries.len()],
    };
    for index in 0..entries.len() {
        graph.visit(index, 0)?;
    }
    options.check()?;
    Ok(sources)
}
struct Graph<'a> {
    entries: &'a [DocumentEntry],
    indices: &'a BTreeMap<&'a str, usize>,
    limits: &'a DocumentCompositionLimits,
    options: &'a OperationOptions,
    states: Vec<u8>,
    depths: Vec<usize>,
    occurrences: Vec<usize>,
}
impl Graph<'_> {
    fn visit(&mut self, index: usize, active_depth: usize) -> Result<(), DocumentCompositionError> {
        self.options.check()?;
        if self.states[index] == 1 {
            return Err(DocumentCompositionError::Cycle(
                self.entries[index].id.clone(),
            ));
        }
        if self.states[index] == 2 {
            return Ok(());
        }
        if active_depth >= self.limits.maximum_depth {
            return Err(DocumentCompositionError::DepthExceeded);
        }
        self.states[index] = 1;
        let (mut depth, mut count) = (1, 1_usize);
        for reference in &self.entries[index].references {
            let target = self.indices[reference.target_id.as_str()];
            self.visit(target, active_depth + 1)?;
            depth = depth.max(self.depths[target] + 1);
            if depth > self.limits.maximum_depth {
                return Err(DocumentCompositionError::DepthExceeded);
            }
            count = count
                .checked_add(self.occurrences[target])
                .filter(|value| *value <= self.limits.maximum_traversal_occurrences)
                .ok_or(DocumentCompositionError::TraversalOccurrencesExceeded)?;
        }
        self.states[index] = 2;
        self.depths[index] = depth;
        self.occurrences[index] = count;
        Ok(())
    }
}

fn profile_limits(limits: &DocumentCompositionLimits) -> DocumentDecodeLimits {
    DocumentDecodeLimits {
        maximum_encoded_bytes: limits.maximum_profile_bytes,
        maximum_decoded_bytes: limits.maximum_profile_bytes,
        maximum_planes: 1,
        maximum_record_bytes: limits.maximum_profile_bytes,
        ..DocumentDecodeLimits::default()
    }
}
fn profile_error(error: DocumentStorageError) -> DocumentCompositionError {
    match error {
        DocumentStorageError::OversizedInput
        | DocumentStorageError::OversizedOutput
        | DocumentStorageError::OversizedRecord => DocumentCompositionError::ProfileBytesExceeded,
        other => other.into(),
    }
}

pub fn document(
    composition: &DocumentComposition,
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Document, DocumentCompositionError> {
    let sources = validate_graph(
        &composition.root_id,
        &composition.entries,
        limits,
        document_limits,
        options,
    )?;
    let json = write_manifest(composition, &sources, limits.maximum_profile_bytes, options)?;
    let result = Document {
        version: "0.1".into(),
        axis: "layer".into(),
        title: None,
        metadata: BTreeMap::from([("profile".into(), "3md-composition-1".into())]),
        preamble: None,
        planes: vec![Plane {
            z: 0.0,
            label: Some("Composition".into()),
            x: None,
            y: None,
            attributes: BTreeMap::new(),
            body: format!("```json\n{json}\n```"),
        }],
    };
    storage::validate(&result, &profile_limits(limits), options).map_err(profile_error)?;
    Ok(result)
}
pub fn encode(
    composition: &DocumentComposition,
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Vec<u8>, DocumentCompositionError> {
    let document = document(composition, limits, document_limits, options)?;
    storage::encode(
        &document,
        DocumentStorageFormat::Text,
        &profile_limits(limits),
        options,
    )
    .map_err(profile_error)
}
pub fn is_composition(document: &Document) -> bool {
    document
        .metadata
        .get("profile")
        .is_some_and(|value| value == "3md-composition-1")
}
pub fn decode(
    data: &[u8],
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentComposition, DocumentCompositionError> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if data.len() > limits.maximum_profile_bytes {
        return Err(DocumentCompositionError::ProfileBytesExceeded);
    }
    let document =
        storage::decode(data, &profile_limits(limits), options).map_err(profile_error)?;
    decode_document(&document, limits, document_limits, options)
}
pub fn decode_document(
    document: &Document,
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentComposition, DocumentCompositionError> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    storage::validate(document, &profile_limits(limits), options).map_err(profile_error)?;
    if !is_composition(document) {
        return Err(DocumentCompositionError::UnsupportedProfile(
            document
                .metadata
                .get("profile")
                .cloned()
                .unwrap_or_else(|| "missing".into()),
        ));
    }
    let envelope_valid = document.version == "0.1"
        && document.axis == "layer"
        && document.title.is_none()
        && document.preamble.is_none()
        && document.metadata.len() == 1
        && document.planes.len() == 1;
    if !envelope_valid {
        return Err(invalid("unexpected composition envelope"));
    }
    let plane = &document.planes[0];
    if plane.z != 0.0
        || plane.label.as_deref() != Some("Composition")
        || plane.x.is_some()
        || plane.y.is_some()
        || !plane.attributes.is_empty()
        || !plane.body.starts_with("```json\n")
        || !plane.body.ends_with("\n```")
    {
        return Err(invalid("unexpected composition envelope"));
    }
    let json = &plane.body.as_bytes()[8..plane.body.len() - 4];
    let mut reader = JsonReader {
        bytes: json,
        index: 0,
        objects: 0,
        array_elements: 0,
        limits,
        options,
    };
    let value = reader.value(0)?;
    reader.whitespace()?;
    if reader.index != json.len() {
        return Err(invalid("trailing JSON input"));
    }
    let manifest = exact_object(value, &["schema", "rootID", "entries"])?;
    let schema = as_string(&manifest["schema"])?;
    if schema != "3md-composition-1" {
        return Err(DocumentCompositionError::UnsupportedProfile(schema.into()));
    }
    let root = as_string(&manifest["rootID"])?;
    let definitions = as_array(&manifest["entries"])?;
    if definitions.len() > limits.maximum_definitions {
        return Err(DocumentCompositionError::TooManyDefinitions);
    }
    let mut entries = Vec::with_capacity(definitions.len());
    let mut total_bytes = 0;
    for value in definitions {
        options.check()?;
        let entry = exact_object_ref(value, &["id", "source", "references"])?;
        let id = as_string(&entry["id"])?;
        let source = as_string(&entry["source"])?;
        if source.len() > limits.maximum_definition_bytes - total_bytes {
            return Err(DocumentCompositionError::DefinitionBytesExceeded);
        }
        total_bytes += source.len();
        if storage::is_binary(source.as_bytes()) {
            return Err(invalid("embedded definitions must be text 3md"));
        }
        let document = storage::decode(source.as_bytes(), document_limits, options)?;
        let mut references = Vec::new();
        for value in as_array(&entry["references"])? {
            options.check()?;
            let reference = exact_object_ref(value, &["targetID", "attributes"])?;
            let target_id = as_string(&reference["targetID"])?;
            let mut attributes = BTreeMap::new();
            for (key, value) in as_object(&reference["attributes"])? {
                attributes.insert(key.clone(), as_string(value)?.into());
            }
            references.push(DocumentReference {
                target_id: target_id.into(),
                attributes,
            });
        }
        entries.push(DocumentEntry {
            id: id.into(),
            document,
            references,
        });
    }
    DocumentComposition::new(root.into(), entries, limits, document_limits, options)
}

fn invalid(detail: &str) -> DocumentCompositionError {
    DocumentCompositionError::InvalidProfile(detail.into())
}
enum JsonValue {
    String(String),
    Object(BTreeMap<String, JsonValue>),
    Array(Vec<JsonValue>),
    Other,
}
fn as_string(value: &JsonValue) -> Result<&str, DocumentCompositionError> {
    if let JsonValue::String(text) = value {
        Ok(text)
    } else {
        Err(invalid("JSON fields have invalid types or values"))
    }
}
fn as_array(value: &JsonValue) -> Result<&[JsonValue], DocumentCompositionError> {
    if let JsonValue::Array(values) = value {
        Ok(values)
    } else {
        Err(invalid("JSON fields have invalid types or values"))
    }
}
fn as_object(value: &JsonValue) -> Result<&BTreeMap<String, JsonValue>, DocumentCompositionError> {
    if let JsonValue::Object(values) = value {
        Ok(values)
    } else {
        Err(invalid("JSON fields have invalid types or values"))
    }
}
fn exact_object(
    value: JsonValue,
    keys: &[&str],
) -> Result<BTreeMap<String, JsonValue>, DocumentCompositionError> {
    exact_object_ref(&value, keys)?;
    if let JsonValue::Object(values) = value {
        Ok(values)
    } else {
        Err(invalid("JSON fields have invalid types or values"))
    }
}
fn exact_object_ref<'a>(
    value: &'a JsonValue,
    keys: &[&str],
) -> Result<&'a BTreeMap<String, JsonValue>, DocumentCompositionError> {
    let object = as_object(value)?;
    if object.len() != keys.len() || keys.iter().any(|key| !object.contains_key(*key)) {
        return Err(invalid("missing or unknown JSON record keys"));
    }
    Ok(object)
}

/// The reader bounds nesting and record allocations before inserting decoded keys.
/// This preserves duplicate-key evidence that generic JSON map decoders discard.
struct JsonReader<'a> {
    bytes: &'a [u8],
    index: usize,
    objects: usize,
    array_elements: usize,
    limits: &'a DocumentCompositionLimits,
    options: &'a OperationOptions,
}
impl JsonReader<'_> {
    fn value(&mut self, depth: usize) -> Result<JsonValue, DocumentCompositionError> {
        self.options.check()?;
        if depth > 12 {
            return Err(invalid("excessive JSON nesting"));
        }
        self.whitespace()?;
        match self.bytes.get(self.index) {
            Some(b'{') => self.object(depth + 1),
            Some(b'[') => self.array(depth + 1),
            Some(b'"') => self.string(false).map(JsonValue::String),
            Some(b't') => {
                self.literal(b"true")?;
                Ok(JsonValue::Other)
            }
            Some(b'f') => {
                self.literal(b"false")?;
                Ok(JsonValue::Other)
            }
            Some(b'n') => {
                self.literal(b"null")?;
                Ok(JsonValue::Other)
            }
            Some(b'-' | b'0'..=b'9') => {
                Err(invalid("numeric JSON fields are not part of this profile"))
            }
            None => Err(invalid("truncated JSON")),
            _ => Err(invalid("invalid JSON value")),
        }
    }
    fn object(&mut self, depth: usize) -> Result<JsonValue, DocumentCompositionError> {
        self.objects += 1;
        if self.objects > 1 + self.limits.maximum_definitions + 2 * self.limits.maximum_references {
            return Err(invalid("too many JSON records"));
        }
        self.index += 1;
        self.whitespace()?;
        let mut object = BTreeMap::new();
        if self.consume(b'}') {
            return Ok(JsonValue::Object(object));
        }
        let mut keys = BTreeSet::new();
        loop {
            self.options.check()?;
            let key = self.string(true)?;
            if !keys.insert(storage::normalized_key(&key, self.options)?) {
                return Err(invalid("duplicate JSON object key"));
            }
            if keys.len() > self.limits.maximum_reference_attributes.max(3) {
                return Err(DocumentCompositionError::ReferenceAttributesExceeded);
            }
            self.whitespace()?;
            if !self.consume(b':') {
                return Err(invalid("missing JSON colon"));
            }
            let value = self.value(depth)?;
            object.insert(key, value);
            self.whitespace()?;
            if self.consume(b'}') {
                return Ok(JsonValue::Object(object));
            }
            if !self.consume(b',') {
                return Err(invalid("missing JSON comma"));
            }
            self.whitespace()?;
        }
    }
    fn array(&mut self, depth: usize) -> Result<JsonValue, DocumentCompositionError> {
        self.index += 1;
        self.whitespace()?;
        let mut values = Vec::new();
        if self.consume(b']') {
            return Ok(JsonValue::Array(values));
        }
        loop {
            self.array_elements += 1;
            if self.array_elements
                > self.limits.maximum_definitions + self.limits.maximum_references
            {
                return Err(invalid("too many JSON array elements"));
            }
            values.push(self.value(depth)?);
            self.whitespace()?;
            if self.consume(b']') {
                return Ok(JsonValue::Array(values));
            }
            if !self.consume(b',') {
                return Err(invalid("missing JSON comma"));
            }
            self.whitespace()?;
        }
    }
    fn string(&mut self, is_key: bool) -> Result<String, DocumentCompositionError> {
        if !self.consume(b'"') {
            return Err(invalid("JSON key must be a string"));
        }
        let start = self.index - 1;
        let mut text = String::new();
        let mut run = self.index;
        while self.index < self.bytes.len() {
            if self.index.is_multiple_of(4096) {
                self.options.check()?;
            }
            if is_key
                && self.index - start > 6 * self.limits.maximum_reference_attribute_bytes + 256
            {
                return Err(DocumentCompositionError::ReferenceAttributesExceeded);
            }
            let byte = self.bytes[self.index];
            self.index += 1;
            if byte == b'"' || byte == b'\\' {
                let raw = std::str::from_utf8(&self.bytes[run..self.index - 1])
                    .map_err(|_| invalid("invalid JSON UTF-8"))?;
                text.push_str(raw);
                if byte == b'"' {
                    return Ok(text);
                }
                let escaped = *self
                    .bytes
                    .get(self.index)
                    .ok_or_else(|| invalid("truncated JSON escape"))?;
                self.index += 1;
                match escaped {
                    b'"' => text.push('"'),
                    b'\\' => text.push('\\'),
                    b'/' => text.push('/'),
                    b'b' => text.push('\u{8}'),
                    b'f' => text.push('\u{c}'),
                    b'n' => text.push('\n'),
                    b'r' => text.push('\r'),
                    b't' => text.push('\t'),
                    b'u' => {
                        let first = self.unicode_quad()?;
                        let scalar = if (0xd800..=0xdbff).contains(&first) {
                            if !self.consume(b'\\') || !self.consume(b'u') {
                                return Err(invalid("invalid Unicode surrogate pair"));
                            }
                            let second = self.unicode_quad()?;
                            if !(0xdc00..=0xdfff).contains(&second) {
                                return Err(invalid("invalid Unicode surrogate pair"));
                            }
                            0x10000
                                + ((u32::from(first) - 0xd800) << 10)
                                + (u32::from(second) - 0xdc00)
                        } else {
                            u32::from(first)
                        };
                        text.push(
                            char::from_u32(scalar)
                                .ok_or_else(|| invalid("invalid Unicode escape"))?,
                        );
                    }
                    _ => return Err(invalid("invalid JSON escape")),
                }
                run = self.index;
            } else if byte < 32 {
                return Err(invalid("unescaped JSON control character"));
            }
        }
        Err(invalid("unterminated JSON string"))
    }
    fn unicode_quad(&mut self) -> Result<u16, DocumentCompositionError> {
        if self.bytes.len() - self.index < 4 {
            return Err(invalid("truncated Unicode escape"));
        }
        let mut value = 0_u16;
        for byte in &self.bytes[self.index..self.index + 4] {
            let digit = match byte {
                b'0'..=b'9' => byte - b'0',
                b'a'..=b'f' => byte - b'a' + 10,
                b'A'..=b'F' => byte - b'A' + 10,
                _ => return Err(invalid("invalid Unicode escape")),
            };
            value = (value << 4) | u16::from(digit);
        }
        self.index += 4;
        Ok(value)
    }
    fn literal(&mut self, literal: &[u8]) -> Result<(), DocumentCompositionError> {
        if !self.bytes[self.index..].starts_with(literal) {
            return Err(invalid("invalid JSON literal"));
        }
        self.index += literal.len();
        Ok(())
    }
    fn whitespace(&mut self) -> Result<(), DocumentCompositionError> {
        while self
            .bytes
            .get(self.index)
            .is_some_and(|byte| b" \t\n\r".contains(byte))
        {
            if self.index.is_multiple_of(4096) {
                self.options.check()?;
            }
            self.index += 1;
        }
        Ok(())
    }
    fn consume(&mut self, byte: u8) -> bool {
        if self.bytes.get(self.index) == Some(&byte) {
            self.index += 1;
            true
        } else {
            false
        }
    }
}

struct JsonWriter<'a> {
    text: String,
    maximum: usize,
    options: &'a OperationOptions,
}
impl JsonWriter<'_> {
    fn append(&mut self, value: &str) -> Result<(), DocumentCompositionError> {
        self.options.check()?;
        if value.len() > self.maximum - self.text.len() {
            return Err(DocumentCompositionError::ProfileBytesExceeded);
        }
        self.text.push_str(value);
        Ok(())
    }
    fn string(&mut self, value: &str) -> Result<(), DocumentCompositionError> {
        self.append("\"")?;
        let mut run = 0;
        for (index, byte) in value.bytes().enumerate() {
            if index % 4096 == 0 {
                self.options.check()?;
            }
            let escape = match byte {
                34 => Some("\\\"".into()),
                92 => Some("\\\\".into()),
                8 => Some("\\b".into()),
                9 => Some("\\t".into()),
                10 => Some("\\n".into()),
                12 => Some("\\f".into()),
                13 => Some("\\r".into()),
                0..=31 => Some(format!("\\u{byte:04x}")),
                _ => None,
            };
            if let Some(escape) = escape {
                self.append(&value[run..index])?;
                self.append(&escape)?;
                run = index + 1;
            }
        }
        self.append(&value[run..])?;
        self.append("\"")
    }
}
fn write_manifest(
    composition: &DocumentComposition,
    sources: &BTreeMap<String, Vec<u8>>,
    maximum: usize,
    options: &OperationOptions,
) -> Result<String, DocumentCompositionError> {
    let mut writer = JsonWriter {
        text: String::new(),
        maximum,
        options,
    };
    writer.append("{\n  \"entries\": [")?;
    for (index, entry) in composition.entries.iter().enumerate() {
        writer.append(if index == 0 { "\n" } else { ",\n" })?;
        writer.append("    {\n      \"id\": ")?;
        writer.string(&entry.id)?;
        writer.append(",\n      \"references\": [")?;
        for (index, reference) in entry.references.iter().enumerate() {
            writer.append(if index == 0 { "\n" } else { ",\n" })?;
            writer.append("        {\"attributes\": {")?;
            for (index, key) in storage::canonical_keys(&reference.attributes, options)?
                .into_iter()
                .enumerate()
            {
                let value = &reference.attributes[key];
                writer.append(if index == 0 { "" } else { ", " })?;
                writer.string(key)?;
                writer.append(": ")?;
                writer.string(value)?;
            }
            writer.append("}, \"targetID\": ")?;
            writer.string(&reference.target_id)?;
            writer.append("}")?;
        }
        writer.append(if entry.references.is_empty() {
            "],\n      \"source\": "
        } else {
            "\n      ],\n      \"source\": "
        })?;
        let source = std::str::from_utf8(&sources[&entry.id])
            .map_err(|_| invalid("definition source missing"))?;
        writer.string(source)?;
        writer.append("\n    }")?;
    }
    writer.append("\n  ],\n  \"rootID\": ")?;
    writer.string(&composition.root_id)?;
    writer.append(",\n  \"schema\": \"3md-composition-1\"\n}")?;
    options.check()?;
    Ok(writer.text)
}
