//! Structured, bounded inspection evidence for text, document values and graphs.
use crate::composition::{
    DocumentComposition, DocumentCompositionError, DocumentCompositionLimits, DocumentEntry,
};
use crate::editing::{self, DocumentEditLimits, PayloadBudget};
use crate::storage::{self, DocumentDecodeLimits, DocumentStorageError, OperationOptions};
use crate::{Document, ParseError};
use std::collections::BTreeSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagnosticCode {
    InvalidIdentity,
    DuplicateIdentity,
    MissingIdentity,
    MissingTarget,
    IdentityChanged,
    StaleRevision,
    InvalidIndex,
    DuplicatePosition,
    InvalidDocument,
    InvalidComposition,
    OperationLimit,
    PayloadLimit,
    InvalidLimits,
    ParseFailure,
}
impl DiagnosticCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::InvalidIdentity => "invalidIdentity",
            Self::DuplicateIdentity => "duplicateIdentity",
            Self::MissingIdentity => "missingIdentity",
            Self::MissingTarget => "missingTarget",
            Self::IdentityChanged => "identityChanged",
            Self::StaleRevision => "staleRevision",
            Self::InvalidIndex => "invalidIndex",
            Self::DuplicatePosition => "duplicatePosition",
            Self::InvalidDocument => "invalidDocument",
            Self::InvalidComposition => "invalidComposition",
            Self::OperationLimit => "operationLimit",
            Self::PayloadLimit => "payloadLimit",
            Self::InvalidLimits => "invalidLimits",
            Self::ParseFailure => "parseFailure",
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagnosticSeverity {
    Error,
    Warning,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentDiagnostic {
    pub code: DiagnosticCode,
    pub message: String,
    pub severity: DiagnosticSeverity,
    pub source_line: Option<usize>,
    pub path: Option<String>,
}
impl DocumentDiagnostic {
    pub fn new(code: DiagnosticCode, message: impl Into<String>, path: Option<String>) -> Self {
        Self {
            code,
            message: message.into(),
            severity: DiagnosticSeverity::Error,
            source_line: None,
            path,
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentDiagnosticReport {
    pub diagnostics: Vec<DocumentDiagnostic>,
    pub is_truncated: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DocumentEditError {
    Diagnostic(DocumentDiagnostic),
    Cancelled,
}
impl DocumentEditError {
    pub fn diagnostic(&self) -> Option<&DocumentDiagnostic> {
        if let Self::Diagnostic(diagnostic) = self {
            Some(diagnostic)
        } else {
            None
        }
    }
    pub fn code(&self) -> &'static str {
        match self {
            Self::Diagnostic(diagnostic) => diagnostic.code.as_str(),
            Self::Cancelled => "cancelled",
        }
    }
    pub(crate) fn make(
        code: DiagnosticCode,
        message: impl Into<String>,
        path: Option<String>,
    ) -> Self {
        Self::Diagnostic(DocumentDiagnostic::new(code, message, path))
    }
}
impl std::fmt::Display for DocumentEditError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Diagnostic(diagnostic) => write!(f, "{}", diagnostic.message),
            Self::Cancelled => write!(f, "The operation was cancelled."),
        }
    }
}
impl std::error::Error for DocumentEditError {}
impl From<DocumentStorageError> for DocumentEditError {
    fn from(error: DocumentStorageError) -> Self {
        if error == DocumentStorageError::Cancelled {
            Self::Cancelled
        } else {
            Self::make(DiagnosticCode::InvalidDocument, error.to_string(), None)
        }
    }
}
impl From<DocumentCompositionError> for DocumentEditError {
    fn from(error: DocumentCompositionError) -> Self {
        if matches!(
            error,
            DocumentCompositionError::Storage(DocumentStorageError::Cancelled)
        ) {
            Self::Cancelled
        } else {
            Self::make(DiagnosticCode::InvalidComposition, error.to_string(), None)
        }
    }
}

pub fn parse_failure(error: &ParseError) -> DocumentDiagnostic {
    let mut diagnostic = DocumentDiagnostic::new(
        DiagnosticCode::ParseFailure,
        error.to_string(),
        Some("source".into()),
    );
    diagnostic.source_line = match error {
        ParseError::MissingPlanePosition { line }
        | ParseError::InvalidPlaneDirective { line, .. } => Some(*line),
        _ => None,
    };
    diagnostic
}

pub fn inspect_source(
    source: &str,
    limits: &DocumentEditLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentDiagnosticReport, DocumentEditError> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if source.len() > limits.maximum_diagnostic_bytes {
        return Err(DocumentEditError::make(
            DiagnosticCode::PayloadLimit,
            "Diagnostic source exceeds its byte budget.",
            Some("source".into()),
        ));
    }
    match storage::decode(source.as_bytes(), document_limits, options) {
        Ok(document) => inspect_document(&document, limits, document_limits, options),
        Err(DocumentStorageError::Cancelled) => Err(DocumentEditError::Cancelled),
        Err(DocumentStorageError::InvalidText(error)) => Ok(DocumentDiagnosticReport {
            diagnostics: vec![parse_failure(&error)],
            is_truncated: false,
        }),
        Err(error) => Ok(DocumentDiagnosticReport {
            diagnostics: vec![DocumentDiagnostic::new(
                DiagnosticCode::InvalidDocument,
                error.to_string(),
                Some("source".into()),
            )],
            is_truncated: false,
        }),
    }
}

pub fn inspect_document(
    document: &Document,
    limits: &DocumentEditLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentDiagnosticReport, DocumentEditError> {
    limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if document.planes.len() > document_limits.maximum_planes {
        return Err(DocumentEditError::make(
            DiagnosticCode::PayloadLimit,
            "Diagnostic plane count exceeds the document policy.",
            Some("planes".into()),
        ));
    }
    let mut budget = PayloadBudget::new(limits.maximum_diagnostic_bytes, options);
    budget.document(document)?;
    let (mut diagnostics, mut identities, mut positions) =
        (Vec::new(), BTreeSet::new(), BTreeSet::new());
    for (index, plane) in document.planes.iter().enumerate() {
        options.check()?;
        if diagnostics.len() == limits.maximum_diagnostics {
            return Ok(DocumentDiagnosticReport {
                diagnostics,
                is_truncated: true,
            });
        }
        if let Some(id) = plane.stable_id() {
            let path = Some(format!("planes[{index}].attributes[3md-id]"));
            if !editing::is_valid_identity(id) {
                diagnostics.push(DocumentDiagnostic::new(
                    DiagnosticCode::InvalidIdentity,
                    "Plane identity must be a safe nonempty ASCII ID.",
                    path,
                ));
            } else if !identities.insert(id) {
                diagnostics.push(DocumentDiagnostic::new(
                    DiagnosticCode::DuplicateIdentity,
                    "Plane identity is already used in this document.",
                    path,
                ));
            }
        }
        if diagnostics.len() == limits.maximum_diagnostics {
            return Ok(DocumentDiagnosticReport {
                diagnostics,
                is_truncated: true,
            });
        }
        if !plane.z.is_finite()
            || plane.x.is_some_and(|value| !value.is_finite())
            || plane.y.is_some_and(|value| !value.is_finite())
        {
            diagnostics.push(DocumentDiagnostic::new(
                DiagnosticCode::InvalidDocument,
                "Plane coordinates must be finite.",
                Some(format!("planes[{index}]")),
            ));
        } else if !positions.insert(storage::position_key(plane.z)) {
            diagnostics.push(DocumentDiagnostic::new(
                DiagnosticCode::DuplicatePosition,
                "Plane position is already used.",
                Some(format!("planes[{index}].z")),
            ));
        }
    }
    if diagnostics.len() == limits.maximum_diagnostics {
        return Ok(DocumentDiagnosticReport {
            diagnostics,
            is_truncated: true,
        });
    }
    if let Err(error) = storage::validate(document, document_limits, options) {
        if error == DocumentStorageError::Cancelled {
            return Err(DocumentEditError::Cancelled);
        }
        if !diagnostics.iter().any(|diagnostic| {
            matches!(
                diagnostic.code,
                DiagnosticCode::DuplicatePosition | DiagnosticCode::InvalidDocument
            )
        }) {
            diagnostics.push(DocumentDiagnostic::new(
                DiagnosticCode::InvalidDocument,
                error.to_string(),
                None,
            ));
        }
    }
    options.check()?;
    Ok(DocumentDiagnosticReport {
        diagnostics,
        is_truncated: false,
    })
}

pub fn inspect_composition(
    composition: &DocumentComposition,
    limits: &DocumentEditLimits,
    composition_limits: &DocumentCompositionLimits,
    document_limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<DocumentDiagnosticReport, DocumentEditError> {
    limits.validate()?;
    composition_limits.validate()?;
    document_limits.validate()?;
    options.check()?;
    if composition.entries().len() > composition_limits.maximum_definitions {
        return Err(DocumentCompositionError::TooManyDefinitions.into());
    }
    let mut budget = PayloadBudget::new(limits.maximum_diagnostic_bytes, options);
    budget.charge(composition.root_id())?;
    let mut reference_count = 0;
    for entry in composition.entries() {
        options.check()?;
        if entry.references.len() > composition_limits.maximum_references - reference_count {
            return Err(DocumentCompositionError::TooManyReferences.into());
        }
        reference_count += entry.references.len();
        if entry.document.planes.len() > document_limits.maximum_planes {
            return Err(DocumentStorageError::TooManyPlanes.into());
        }
        budget.charge(&entry.id)?;
        budget.document(&entry.document)?;
        for reference in &entry.references {
            budget.charge(&reference.target_id)?;
            budget.attributes(&reference.attributes)?;
        }
    }
    DocumentComposition::new(
        composition.root_id().into(),
        composition.entries().to_vec(),
        composition_limits,
        document_limits,
        options,
    )?;
    let mut diagnostics = Vec::new();
    for (entry_index, entry) in composition.entries().iter().enumerate() {
        options.check()?;
        let report = inspect_document(&entry.document, limits, document_limits, options)?;
        for mut diagnostic in report.diagnostics {
            if diagnostics.len() == limits.maximum_diagnostics {
                return Ok(DocumentDiagnosticReport {
                    diagnostics,
                    is_truncated: true,
                });
            }
            diagnostic.path = Some(format!(
                "entries[{entry_index}].document{}",
                diagnostic
                    .path
                    .map(|path| format!(".{path}"))
                    .unwrap_or_default()
            ));
            diagnostics.push(diagnostic);
        }
        if report.is_truncated {
            return Ok(DocumentDiagnosticReport {
                diagnostics,
                is_truncated: true,
            });
        }
        let mut identities = BTreeSet::new();
        for (index, reference) in entry.references.iter().enumerate() {
            options.check()?;
            if diagnostics.len() == limits.maximum_diagnostics {
                return Ok(DocumentDiagnosticReport {
                    diagnostics,
                    is_truncated: true,
                });
            }
            let Some(id) = reference.stable_id() else {
                continue;
            };
            let path = Some(format!(
                "entries[{entry_index}].references[{index}].attributes[3md-id]"
            ));
            if !editing::is_valid_identity(id) {
                diagnostics.push(DocumentDiagnostic::new(
                    DiagnosticCode::InvalidIdentity,
                    "Reference identity must be a safe nonempty ASCII ID.",
                    path,
                ));
            } else if !identities.insert(id) {
                diagnostics.push(DocumentDiagnostic::new(
                    DiagnosticCode::DuplicateIdentity,
                    "Reference identity is already used by this owner.",
                    path,
                ));
            }
        }
    }
    options.check()?;
    Ok(DocumentDiagnosticReport {
        diagnostics,
        is_truncated: false,
    })
}

pub(crate) fn composition_error(
    error: DocumentCompositionError,
    entries: &[DocumentEntry],
) -> DocumentEditError {
    if matches!(
        error,
        DocumentCompositionError::Storage(DocumentStorageError::Cancelled)
    ) {
        return DocumentEditError::Cancelled;
    }
    if let DocumentCompositionError::Storage(storage_error) = error {
        return DocumentEditError::make(
            DiagnosticCode::InvalidDocument,
            storage_error.to_string(),
            Some("entries".into()),
        );
    }
    let path = match &error {
        DocumentCompositionError::MissingRoot(_) => "rootID".into(),
        DocumentCompositionError::MissingTarget { from, target } => entries
            .iter()
            .position(|entry| entry.id == *from)
            .and_then(|entry_index| {
                entries[entry_index]
                    .references
                    .iter()
                    .position(|reference| reference.target_id == *target)
                    .map(|index| format!("entries[{entry_index}].references[{index}].targetID"))
            })
            .unwrap_or_else(|| "entries".into()),
        DocumentCompositionError::Cycle(id)
        | DocumentCompositionError::InvalidId(id)
        | DocumentCompositionError::DuplicateId(id) => entries
            .iter()
            .position(|entry| entry.id == *id)
            .map(|index| format!("entries[{index}]"))
            .unwrap_or_else(|| "rootID".into()),
        _ => "entries".into(),
    };
    DocumentEditError::make(
        DiagnosticCode::InvalidComposition,
        error.to_string(),
        Some(path),
    )
}
