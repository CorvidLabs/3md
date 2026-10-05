//! Stable identities and pure atomic document or composition transactions.
use crate::composition::{
    self, DocumentComposition, DocumentCompositionLimits, DocumentEntry, DocumentReference,
};
use crate::diagnostics::{composition_error, DiagnosticCode, DocumentEditError};
use crate::storage::{self, DocumentDecodeLimits, DocumentStorageFormat, OperationOptions};
use crate::{Document, Plane};
use std::collections::{BTreeMap, BTreeSet};

pub const IDENTITY_ATTRIBUTE_KEY: &str = "3md-id";
pub fn is_valid_identity(id: &str) -> bool {
    composition::is_valid_id(id)
}
impl Plane {
    pub fn stable_id(&self) -> Option<&str> {
        self.attributes
            .get(IDENTITY_ATTRIBUTE_KEY)
            .map(String::as_str)
    }
}
impl DocumentReference {
    pub fn stable_id(&self) -> Option<&str> {
        self.attributes
            .get(IDENTITY_ATTRIBUTE_KEY)
            .map(String::as_str)
    }
}

pub fn adopt_document(
    document: &Document,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Document, DocumentEditError> {
    storage::validate(document, document_limits, options)?;
    validate_identities(document, "", options)?;
    let mut ids: BTreeSet<String> = document
        .planes
        .iter()
        .filter_map(|plane| plane.stable_id().map(str::to_owned))
        .collect();
    let mut next = 1;
    let mut result = document.clone();
    for plane in &mut result.planes {
        options.check()?;
        if plane.stable_id().is_none() {
            plane.attributes.insert(
                IDENTITY_ATTRIBUTE_KEY.into(),
                next_identity("plane", &mut ids, &mut next),
            );
        }
    }
    storage::validate(&result, document_limits, options)?;
    Ok(result)
}
pub fn adopt_composition(
    composition: &DocumentComposition,
    limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentComposition, DocumentEditError> {
    limits.validate()?;
    document_limits.validate()?;
    composition::validate_graph(
        composition.root_id(),
        composition.entries(),
        limits,
        document_limits,
        options,
    )?;
    validate_composition_identities(composition, options)?;
    let mut entries = composition.entries().to_vec();
    for entry in &mut entries {
        options.check()?;
        entry.document = adopt_document(&entry.document, document_limits, options)?;
        let mut ids: BTreeSet<String> = entry
            .references
            .iter()
            .filter_map(|reference| reference.stable_id().map(str::to_owned))
            .collect();
        let mut next = 1;
        for reference in &mut entry.references {
            options.check()?;
            if reference.stable_id().is_none() {
                reference.attributes.insert(
                    IDENTITY_ATTRIBUTE_KEY.into(),
                    next_identity("reference", &mut ids, &mut next),
                );
            }
        }
    }
    DocumentComposition::new(
        composition.root_id().into(),
        entries,
        limits,
        document_limits,
        options,
    )
    .map_err(Into::into)
}
fn next_identity(prefix: &str, ids: &mut BTreeSet<String>, next: &mut usize) -> String {
    loop {
        let candidate = format!("{prefix}-{next}");
        *next += 1;
        if ids.insert(candidate.clone()) {
            return candidate;
        }
    }
}
fn validate_identities(
    document: &Document,
    prefix: &str,
    options: &OperationOptions,
) -> Result<(), DocumentEditError> {
    let mut ids = BTreeSet::new();
    for (index, plane) in document.planes.iter().enumerate() {
        options.check()?;
        let Some(id) = plane.stable_id() else {
            continue;
        };
        let path = Some(format!("{prefix}planes[{index}].attributes[3md-id]"));
        if !is_valid_identity(id) {
            return Err(DocumentEditError::make(
                DiagnosticCode::InvalidIdentity,
                "Plane identity must be a safe nonempty ASCII ID.",
                path,
            ));
        }
        if !ids.insert(id) {
            return Err(DocumentEditError::make(
                DiagnosticCode::DuplicateIdentity,
                "Plane identity is already used in this document.",
                path,
            ));
        }
    }
    Ok(())
}
fn validate_composition_identities(
    composition: &DocumentComposition,
    options: &OperationOptions,
) -> Result<(), DocumentEditError> {
    for (entry_index, entry) in composition.entries().iter().enumerate() {
        validate_identities(
            &entry.document,
            &format!("entries[{entry_index}].document."),
            options,
        )?;
        let mut ids = BTreeSet::new();
        for (index, reference) in entry.references.iter().enumerate() {
            options.check()?;
            let Some(id) = reference.stable_id() else {
                continue;
            };
            let path = Some(format!(
                "entries[{entry_index}].references[{index}].attributes[3md-id]"
            ));
            if !is_valid_identity(id) {
                return Err(DocumentEditError::make(
                    DiagnosticCode::InvalidIdentity,
                    "Reference identity must be a safe nonempty ASCII ID.",
                    path,
                ));
            }
            if !ids.insert(id) {
                return Err(DocumentEditError::make(
                    DiagnosticCode::DuplicateIdentity,
                    "Reference identity is already used by this owner.",
                    path,
                ));
            }
        }
    }
    Ok(())
}

/// Exact canonical UTF-8 content. Equality uses bytes, with no Unicode normalization.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct DocumentRevision {
    pub canonical_content: String,
}
#[derive(Debug, Clone, PartialEq)]
pub struct DocumentSnapshot {
    document: Document,
    revision: DocumentRevision,
}
impl DocumentSnapshot {
    pub fn new(
        document: Document,
        limits: &DocumentDecodeLimits,
        options: &OperationOptions,
    ) -> Result<Self, DocumentEditError> {
        let data = storage::encode(&document, DocumentStorageFormat::Text, limits, options)?;
        validate_identities(&document, "", options)?;
        let canonical_content = String::from_utf8(data).map_err(|_| {
            DocumentEditError::make(
                DiagnosticCode::InvalidDocument,
                "Canonical source is not UTF-8.",
                None,
            )
        })?;
        Ok(Self {
            document,
            revision: DocumentRevision { canonical_content },
        })
    }
    /// Rejects persisted snapshots whose expected revision differs from their value.
    pub fn from_parts(
        document: Document,
        revision: DocumentRevision,
        limits: &DocumentDecodeLimits,
        options: &OperationOptions,
    ) -> Result<Self, DocumentEditError> {
        if revision.canonical_content.len() > limits.maximum_decoded_bytes {
            return Err(DocumentEditError::make(
                DiagnosticCode::PayloadLimit,
                "The expected revision exceeds the document byte limit.",
                Some("revision".into()),
            ));
        }
        let snapshot = Self::new(document, limits, options)?;
        if snapshot.revision != revision {
            return Err(DocumentEditError::make(
                DiagnosticCode::StaleRevision,
                "Revision mismatch.",
                Some("revision".into()),
            ));
        }
        Ok(snapshot)
    }
    pub fn document(&self) -> &Document {
        &self.document
    }
    pub fn revision(&self) -> &DocumentRevision {
        &self.revision
    }
}
#[derive(Debug, Clone, PartialEq)]
pub struct DocumentCompositionSnapshot {
    composition: DocumentComposition,
    revision: DocumentRevision,
}
impl DocumentCompositionSnapshot {
    pub fn new(
        composition: DocumentComposition,
        limits: &DocumentCompositionLimits,
        document_limits: &DocumentDecodeLimits,
        options: &OperationOptions,
    ) -> Result<Self, DocumentEditError> {
        let data = composition::encode(&composition, limits, document_limits, options)?;
        validate_composition_identities(&composition, options)?;
        let canonical_content = String::from_utf8(data).map_err(|_| {
            DocumentEditError::make(
                DiagnosticCode::InvalidComposition,
                "Canonical profile is not UTF-8.",
                None,
            )
        })?;
        Ok(Self {
            composition,
            revision: DocumentRevision { canonical_content },
        })
    }
    pub fn from_parts(
        composition: DocumentComposition,
        revision: DocumentRevision,
        limits: &DocumentCompositionLimits,
        document_limits: &DocumentDecodeLimits,
        options: &OperationOptions,
    ) -> Result<Self, DocumentEditError> {
        if revision.canonical_content.len() > limits.maximum_profile_bytes {
            return Err(DocumentEditError::make(
                DiagnosticCode::PayloadLimit,
                "The expected graph revision exceeds its profile byte limit.",
                Some("revision".into()),
            ));
        }
        let snapshot = Self::new(composition, limits, document_limits, options)?;
        if snapshot.revision != revision {
            return Err(DocumentEditError::make(
                DiagnosticCode::StaleRevision,
                "Revision mismatch.",
                Some("revision".into()),
            ));
        }
        Ok(snapshot)
    }
    pub fn composition(&self) -> &DocumentComposition {
        &self.composition
    }
    pub fn revision(&self) -> &DocumentRevision {
        &self.revision
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentEditLimits {
    pub maximum_operations: usize,
    pub maximum_payload_bytes: usize,
    pub maximum_diagnostics: usize,
    pub maximum_diagnostic_bytes: usize,
}
impl Default for DocumentEditLimits {
    fn default() -> Self {
        Self {
            maximum_operations: 1024,
            maximum_payload_bytes: 16 * 1024 * 1024,
            maximum_diagnostics: 256,
            maximum_diagnostic_bytes: 64 * 1024 * 1024,
        }
    }
}
impl DocumentEditLimits {
    pub fn validate(&self) -> Result<(), DocumentEditError> {
        if self.maximum_operations > 4096
            || !(1..=64 * 1024 * 1024).contains(&self.maximum_payload_bytes)
            || !(1..=1024).contains(&self.maximum_diagnostics)
            || !(1..=64 * 1024 * 1024).contains(&self.maximum_diagnostic_bytes)
        {
            Err(DocumentEditError::make(
                DiagnosticCode::InvalidLimits,
                "Editing limits exceed their supported bounds.",
                None,
            ))
        } else {
            Ok(())
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentHeader {
    pub version: String,
    pub axis: String,
    pub title: Option<String>,
    pub metadata: BTreeMap<String, String>,
    pub preamble: Option<String>,
}
impl From<&Document> for DocumentHeader {
    fn from(document: &Document) -> Self {
        Self {
            version: document.version.clone(),
            axis: document.axis.clone(),
            title: document.title.clone(),
            metadata: document.metadata.clone(),
            preamble: document.preamble.clone(),
        }
    }
}
impl DocumentHeader {
    fn document(self, planes: Vec<Plane>) -> Document {
        Document {
            version: self.version,
            axis: self.axis,
            title: self.title,
            metadata: self.metadata,
            preamble: self.preamble,
            planes,
        }
    }
}
#[derive(Debug, Clone, PartialEq)]
pub enum DocumentEdit {
    Insert { plane: Plane, at: isize },
    Remove { id: String },
    Replace { id: String, plane: Plane },
    Move { id: String, to: isize },
    ReplaceHeader(DocumentHeader),
}
#[derive(Debug, Clone, PartialEq)]
pub struct DocumentPatch {
    pub expected_revision: DocumentRevision,
    pub operations: Vec<DocumentEdit>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum CompositionEdit {
    InsertEntry(DocumentEntry),
    RemoveEntry {
        id: String,
    },
    ReplaceEntry {
        id: String,
        entry: DocumentEntry,
    },
    SelectRoot {
        id: String,
    },
    InsertReference {
        owner_id: String,
        reference: DocumentReference,
        at: isize,
    },
    RemoveReference {
        owner_id: String,
        id: String,
    },
    ReplaceReference {
        owner_id: String,
        id: String,
        reference: DocumentReference,
    },
    MoveReference {
        owner_id: String,
        id: String,
        to: isize,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub struct CompositionPatch {
    pub expected_revision: DocumentRevision,
    pub operations: Vec<CompositionEdit>,
}

fn failure(code: DiagnosticCode, message: &str, path: &str) -> DocumentEditError {
    DocumentEditError::make(code, message, Some(path.into()))
}
fn target_id(id: &str, path: &str) -> Result<(), DocumentEditError> {
    if is_valid_identity(id) {
        Ok(())
    } else {
        Err(failure(
            DiagnosticCode::InvalidIdentity,
            "An edit target must be a safe nonempty ASCII ID.",
            path,
        ))
    }
}
fn plane_target(id: &str, planes: &[Plane], path: &str) -> Result<usize, DocumentEditError> {
    target_id(id, path)?;
    planes
        .iter()
        .position(|plane| plane.stable_id() == Some(id))
        .ok_or_else(|| {
            failure(
                DiagnosticCode::MissingTarget,
                "The target plane identity does not exist.",
                path,
            )
        })
}
fn owner_target(
    id: &str,
    entries: &[DocumentEntry],
    path: &str,
) -> Result<usize, DocumentEditError> {
    target_id(id, path)?;
    entries
        .iter()
        .position(|entry| entry.id == id)
        .ok_or_else(|| {
            failure(
                DiagnosticCode::MissingTarget,
                "The owning definition does not exist.",
                path,
            )
        })
}
fn reference_target(
    id: &str,
    references: &[DocumentReference],
    path: &str,
) -> Result<usize, DocumentEditError> {
    target_id(id, path)?;
    references
        .iter()
        .position(|reference| reference.stable_id() == Some(id))
        .ok_or_else(|| {
            failure(
                DiagnosticCode::MissingTarget,
                "The reference identity does not exist in this owner.",
                path,
            )
        })
}
fn valid_index(index: isize, count: usize, insertion: bool) -> bool {
    index >= 0
        && if insertion {
            index as usize <= count
        } else {
            (index as usize) < count
        }
}

pub fn apply_document_patch(
    patch: &DocumentPatch,
    snapshot: &DocumentSnapshot,
    limits: &DocumentEditLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentSnapshot, DocumentEditError> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if patch.operations.len() > limits.maximum_operations {
        return Err(failure(
            DiagnosticCode::OperationLimit,
            "The transaction exceeds its operation limit.",
            "operations",
        ));
    }
    if patch.expected_revision.canonical_content.len() > document_limits.maximum_decoded_bytes {
        return Err(failure(
            DiagnosticCode::PayloadLimit,
            "The expected revision exceeds the document byte limit.",
            "expectedRevision",
        ));
    }
    if patch.expected_revision != snapshot.revision {
        return Err(failure(
            DiagnosticCode::StaleRevision,
            "The document changed after this patch was prepared.",
            "expectedRevision",
        ));
    }
    storage::validate(&snapshot.document, document_limits, options)?;
    validate_identities(&snapshot.document, "", options)?;
    let mut budget = PayloadBudget::new(limits.maximum_payload_bytes, options);
    for operation in &patch.operations {
        match operation {
            DocumentEdit::Insert { plane, .. } => budget.plane(plane)?,
            DocumentEdit::Replace { id, plane } => {
                budget.charge(id)?;
                budget.plane(plane)?;
            }
            DocumentEdit::Remove { id } | DocumentEdit::Move { id, .. } => budget.charge(id)?,
            DocumentEdit::ReplaceHeader(header) => budget.header(header)?,
        }
    }
    let mut header = DocumentHeader::from(&snapshot.document);
    let mut planes = snapshot.document.planes.clone();
    for (index, operation) in patch.operations.iter().enumerate() {
        options.check()?;
        let path = format!("operations[{index}]");
        match operation {
            DocumentEdit::ReplaceHeader(replacement) => header = replacement.clone(),
            DocumentEdit::Insert { plane, at } => {
                if !valid_index(*at, planes.len(), true) {
                    return Err(failure(
                        DiagnosticCode::InvalidIndex,
                        "Insertion index is outside the source-order list.",
                        &path,
                    ));
                }
                let id = plane.stable_id().ok_or_else(|| {
                    failure(
                        DiagnosticCode::MissingIdentity,
                        "An inserted plane needs a stable identity.",
                        &path,
                    )
                })?;
                target_id(id, &path)?;
                if planes.iter().any(|plane| plane.stable_id() == Some(id)) {
                    return Err(failure(
                        DiagnosticCode::DuplicateIdentity,
                        "An inserted plane identity is already used.",
                        &path,
                    ));
                }
                if planes.len() >= document_limits.maximum_planes {
                    return Err(failure(
                        DiagnosticCode::PayloadLimit,
                        "The transaction exceeds the plane limit.",
                        &path,
                    ));
                }
                planes.insert(*at as usize, plane.clone());
            }
            DocumentEdit::Remove { id } => {
                let position = plane_target(id, &planes, &path)?;
                planes.remove(position);
            }
            DocumentEdit::Replace { id, plane } => {
                let position = plane_target(id, &planes, &path)?;
                if plane.stable_id() != Some(id) {
                    return Err(failure(
                        DiagnosticCode::IdentityChanged,
                        "Replacement must retain the target identity.",
                        &path,
                    ));
                }
                planes[position] = plane.clone();
            }
            DocumentEdit::Move { id, to } => {
                let position = plane_target(id, &planes, &path)?;
                if !valid_index(*to, planes.len(), false) {
                    return Err(failure(
                        DiagnosticCode::InvalidIndex,
                        "Move index is outside the final source-order list.",
                        &path,
                    ));
                }
                let plane = planes.remove(position);
                planes.insert(*to as usize, plane);
            }
        }
    }
    let result = header.document(planes);
    let mut coordinates = BTreeSet::new();
    for (index, plane) in result.planes.iter().enumerate() {
        options.check()?;
        if !plane.z.is_nan() && !coordinates.insert(storage::position_key(plane.z)) {
            return Err(failure(
                DiagnosticCode::DuplicatePosition,
                "Final plane positions must be unique.",
                &format!("planes[{index}].z"),
            ));
        }
    }
    DocumentSnapshot::new(result, document_limits, options)
}

pub fn apply_composition_patch(
    patch: &CompositionPatch,
    snapshot: &DocumentCompositionSnapshot,
    limits: &DocumentEditLimits,
    composition_limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentCompositionSnapshot, DocumentEditError> {
    limits.validate()?;
    composition_limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if patch.operations.len() > limits.maximum_operations {
        return Err(failure(
            DiagnosticCode::OperationLimit,
            "The graph transaction exceeds its operation limit.",
            "operations",
        ));
    }
    if patch.expected_revision.canonical_content.len() > composition_limits.maximum_profile_bytes {
        return Err(failure(
            DiagnosticCode::PayloadLimit,
            "The expected graph revision exceeds its profile byte limit.",
            "expectedRevision",
        ));
    }
    if patch.expected_revision != snapshot.revision {
        return Err(failure(
            DiagnosticCode::StaleRevision,
            "The composition changed after this patch was prepared.",
            "expectedRevision",
        ));
    }
    composition::encode(
        &snapshot.composition,
        composition_limits,
        document_limits,
        options,
    )?;
    validate_composition_identities(&snapshot.composition, options)?;
    let mut budget = PayloadBudget::new(limits.maximum_payload_bytes, options);
    for operation in &patch.operations {
        match operation {
            CompositionEdit::InsertEntry(entry) => budget.entry(entry)?,
            CompositionEdit::ReplaceEntry { id, entry } => {
                budget.charge(id)?;
                budget.entry(entry)?;
            }
            CompositionEdit::RemoveEntry { id } | CompositionEdit::SelectRoot { id } => {
                budget.charge(id)?
            }
            CompositionEdit::InsertReference {
                owner_id,
                reference,
                ..
            } => {
                budget.charge(owner_id)?;
                budget.charge(&reference.target_id)?;
                budget.attributes(&reference.attributes)?;
            }
            CompositionEdit::ReplaceReference {
                owner_id,
                id,
                reference,
            } => {
                budget.charge(owner_id)?;
                budget.charge(id)?;
                budget.charge(&reference.target_id)?;
                budget.attributes(&reference.attributes)?;
            }
            CompositionEdit::RemoveReference { owner_id, id }
            | CompositionEdit::MoveReference { owner_id, id, .. } => {
                budget.charge(owner_id)?;
                budget.charge(id)?;
            }
        }
    }
    let mut root_id = snapshot.composition.root_id().to_owned();
    let mut entries = snapshot.composition.entries().to_vec();
    for (index, operation) in patch.operations.iter().enumerate() {
        options.check()?;
        let path = format!("operations[{index}]");
        match operation {
            CompositionEdit::SelectRoot { id } => {
                target_id(id, &path)?;
                root_id = id.clone();
            }
            CompositionEdit::InsertEntry(entry) => {
                target_id(&entry.id, &path)?;
                if entries.iter().any(|existing| existing.id == entry.id) {
                    return Err(failure(
                        DiagnosticCode::DuplicateIdentity,
                        "The definition ID already exists.",
                        &path,
                    ));
                }
                if entries.len() >= composition_limits.maximum_definitions {
                    return Err(failure(
                        DiagnosticCode::PayloadLimit,
                        "The transaction exceeds its definition limit.",
                        &path,
                    ));
                }
                entries.push(entry.clone());
            }
            CompositionEdit::RemoveEntry { id } => {
                let position = owner_target(id, &entries, &path)?;
                entries.remove(position);
            }
            CompositionEdit::ReplaceEntry { id, entry } => {
                let position = owner_target(id, &entries, &path)?;
                if entry.id != *id {
                    return Err(failure(
                        DiagnosticCode::IdentityChanged,
                        "Replacement must retain its definition ID.",
                        &path,
                    ));
                }
                entries[position] = entry.clone();
            }
            CompositionEdit::InsertReference {
                owner_id,
                reference,
                at,
            } => {
                let position = owner_target(owner_id, &entries, &path)?;
                let references = &mut entries[position].references;
                if !valid_index(*at, references.len(), true) {
                    return Err(failure(
                        DiagnosticCode::InvalidIndex,
                        "Reference insertion index is outside its owner list.",
                        &path,
                    ));
                }
                let id = reference.stable_id().ok_or_else(|| {
                    failure(
                        DiagnosticCode::MissingIdentity,
                        "An inserted reference needs a stable identity.",
                        &path,
                    )
                })?;
                target_id(id, &path)?;
                if references
                    .iter()
                    .any(|reference| reference.stable_id() == Some(id))
                {
                    return Err(failure(
                        DiagnosticCode::DuplicateIdentity,
                        "The reference identity already exists in this owner.",
                        &path,
                    ));
                }
                if references.len() >= composition_limits.maximum_references {
                    return Err(failure(
                        DiagnosticCode::PayloadLimit,
                        "The owner exceeds the reference-record limit.",
                        &path,
                    ));
                }
                references.insert(*at as usize, reference.clone());
            }
            CompositionEdit::RemoveReference { owner_id, id } => {
                let position = owner_target(owner_id, &entries, &path)?;
                let references = &mut entries[position].references;
                let position = reference_target(id, references, &path)?;
                references.remove(position);
            }
            CompositionEdit::ReplaceReference {
                owner_id,
                id,
                reference,
            } => {
                let position = owner_target(owner_id, &entries, &path)?;
                let references = &mut entries[position].references;
                let position = reference_target(id, references, &path)?;
                if reference.stable_id() != Some(id) {
                    return Err(failure(
                        DiagnosticCode::IdentityChanged,
                        "Replacement must retain its reference identity.",
                        &path,
                    ));
                }
                references[position] = reference.clone();
            }
            CompositionEdit::MoveReference { owner_id, id, to } => {
                let position = owner_target(owner_id, &entries, &path)?;
                let references = &mut entries[position].references;
                let position = reference_target(id, references, &path)?;
                if !valid_index(*to, references.len(), false) {
                    return Err(failure(
                        DiagnosticCode::InvalidIndex,
                        "Reference move index is outside its final owner list.",
                        &path,
                    ));
                }
                let reference = references.remove(position);
                references.insert(*to as usize, reference);
            }
        }
    }
    let composition = DocumentComposition::new(
        root_id,
        entries.clone(),
        composition_limits,
        document_limits,
        options,
    )
    .map_err(|error| composition_error(error, &entries))?;
    DocumentCompositionSnapshot::new(composition, composition_limits, document_limits, options)
}

pub(crate) struct PayloadBudget<'a> {
    maximum: usize,
    used: usize,
    options: &'a OperationOptions,
}
impl<'a> PayloadBudget<'a> {
    pub(crate) fn new(maximum: usize, options: &'a OperationOptions) -> Self {
        Self {
            maximum,
            used: 0,
            options,
        }
    }
    pub(crate) fn charge(&mut self, text: &str) -> Result<(), DocumentEditError> {
        self.options.check()?;
        if text.len() >= self.maximum - self.used {
            return Err(DocumentEditError::make(
                DiagnosticCode::PayloadLimit,
                "The edit payload exceeds its UTF-8 byte budget.",
                None,
            ));
        }
        self.used += text.len() + 1;
        Ok(())
    }
    pub(crate) fn attributes(
        &mut self,
        attributes: &BTreeMap<String, String>,
    ) -> Result<(), DocumentEditError> {
        if attributes.len() > (self.maximum - self.used) / 2 {
            return Err(DocumentEditError::make(
                DiagnosticCode::PayloadLimit,
                "The edit attribute payload exceeds its byte budget.",
                None,
            ));
        }
        for (key, value) in attributes {
            self.charge(key)?;
            self.charge(value)?;
        }
        Ok(())
    }
    pub(crate) fn plane(&mut self, plane: &Plane) -> Result<(), DocumentEditError> {
        self.charge(&plane.body)?;
        if let Some(label) = &plane.label {
            self.charge(label)?;
        }
        self.attributes(&plane.attributes)?;
        self.charge(&swift_double(plane.z))?;
        if let Some(x) = plane.x {
            self.charge(&swift_double(x))?;
        }
        if let Some(y) = plane.y {
            self.charge(&swift_double(y))?;
        }
        Ok(())
    }
    pub(crate) fn header(&mut self, header: &DocumentHeader) -> Result<(), DocumentEditError> {
        self.charge(&header.version)?;
        self.charge(&header.axis)?;
        if let Some(title) = &header.title {
            self.charge(title)?;
        }
        if let Some(preamble) = &header.preamble {
            self.charge(preamble)?;
        }
        self.attributes(&header.metadata)
    }
    pub(crate) fn document(&mut self, document: &Document) -> Result<(), DocumentEditError> {
        self.charge(&document.version)?;
        self.charge(&document.axis)?;
        if let Some(title) = &document.title {
            self.charge(title)?;
        }
        if let Some(preamble) = &document.preamble {
            self.charge(preamble)?;
        }
        self.attributes(&document.metadata)?;
        if document.planes.len() > self.maximum - self.used {
            return Err(DocumentEditError::make(
                DiagnosticCode::PayloadLimit,
                "The edit plane payload exceeds its byte budget.",
                None,
            ));
        }
        for plane in &document.planes {
            self.plane(plane)?;
        }
        Ok(())
    }
    fn entry(&mut self, entry: &DocumentEntry) -> Result<(), DocumentEditError> {
        self.charge(&entry.id)?;
        self.document(&entry.document)?;
        if entry.references.len() > self.maximum - self.used {
            return Err(DocumentEditError::make(
                DiagnosticCode::PayloadLimit,
                "Reference payload exceeds the edit byte budget.",
                None,
            ));
        }
        for reference in &entry.references {
            self.charge(&reference.target_id)?;
            self.attributes(&reference.attributes)?;
        }
        Ok(())
    }
}
fn swift_double(value: f64) -> String {
    storage::swift_double(value)
}
