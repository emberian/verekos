//! The Scope store control: EKOS's own `ScopedStore` over a real `Ledger`,
//! per panel item (exploration 03 §2.2 `scope.rs`, the leak-suite family).
//!
//! The decision panel (`scope_dump.rs`) answers `Compiled::visible` with no
//! store at all; these items replay the store tests of `scope.rs:1041` on;
//! each one names a world (the tests' `world()` fixture, built through
//! ekos_ledger's public API exactly as the tests build it: `KirObject::new`,
//! `append_object`/`append_evidence`/`append_relationship`), an initial scope
//! set, and the ordered steps of one test. The control line is
//! `{"item": ..., "results": [...]}` — one result per step.
//!
//! Results carry no random id and no timestamp, so two runs are
//! byte-identical: objects and relationships print as names (`from->to`),
//! counts and booleans print as themselves, and the ids `diff.touched`
//! carries are mapped back to the object's name.
//!
//! Item input shape:
//!
//! ```json
//! {"world": {"objects": [{"role","name","source"?,"file"?}],
//!            "relationships": [{"role","kind","from","to"}]},
//!  "scopes": ["<scope json text>", ...],
//!  "steps": [{"op": "...", ...}]}
//! ```
//!
//! Ops: is_restricted, fingerprint_empty, fingerprint_nonempty,
//! fingerprint_differs_from_last, all_objects, all_relationships,
//! all_objects_at, all_relationships_at, get_object, object_history,
//! object_at, fact, audit_trail, relationships_for, relationships_at,
//! get_relationship, relationship_history, get_evidence, find_objects,
//! retrieve, object_count, relationship_count, evidence_count, entry_count,
//! diff, append_object, append_evidence, append_relationship, vacuum_into,
//! get_event, set_scopes.

use std::collections::HashMap;

use chrono::{Duration, Utc};
use ekos_kir::{KirEvidence, KirId, KirObject, KirRelationship, ObjectKind, RelationshipKind, SourceLocation};
use ekos_ledger::scope::{ReadScope, ScopedStore};
use ekos_ledger::{KnowledgeStore, Ledger, LedgerError, RetrievalRequest};
use serde_json::{json, Value};

use crate::Item;

/// The id `get_event` is asked for: a fixed uuid, the same none-answer the
/// tests get from their random one.
const NO_EVENT: &str = "00000000-0000-5000-8000-0000000000ee";

struct World {
    store: ScopedStore,
    by_role: HashMap<String, KirId>,
    name_of: HashMap<String, String>,
    rel_ends: HashMap<String, (String, String)>,
    evidence_of: HashMap<String, KirId>,
    last_fingerprint: String,
}

impl World {
    /// `object()` + `world()` + `scoped()` of the tests (scope.rs:1041-1101):
    /// build the ledger with one handle, then wrap a second in the store.
    fn build(input: &Value, dir: &std::path::Path) -> Result<Self, String> {
        let path = dir.join("ledger.db");
        let ledger = Ledger::open(&path).map_err(|e| format!("open: {e}"))?;
        let mut by_role = HashMap::new();
        let mut name_of = HashMap::new();
        let mut evidence_of: HashMap<String, KirId> = HashMap::new();
        for spec in input["world"]["objects"]
            .as_array()
            .ok_or("world.objects is not a list")?
        {
            let role = spec["role"].as_str().ok_or("object.role")?.to_string();
            let name = spec["name"].as_str().ok_or("object.name")?.to_string();
            let mut obj = KirObject::new(&name, ObjectKind::Table);
            if let Some(source) = spec["source"].as_str() {
                obj.properties.insert("source".into(), json!(source));
                obj.properties.insert("sources".into(), json!([source]));
            }
            if let Some(file) = spec["file"].as_str() {
                let ev = KirEvidence::new(SourceLocation::file(file), format!("text of {name}"));
                ledger.append_evidence(&ev).map_err(|e| format!("append_evidence: {e}"))?;
                obj.evidence.push(ev.id);
                evidence_of.insert(role.clone(), ev.id);
            }
            ledger.append_object(&obj).map_err(|e| format!("append_object: {e}"))?;
            name_of.insert(obj.id.0.to_string(), name.clone());
            by_role.insert(role, obj.id);
        }
        let mut rel_ends = HashMap::new();
        for spec in input["world"]["relationships"]
            .as_array()
            .ok_or("world.relationships is not a list")?
        {
            let role = spec["role"].as_str().ok_or("relationship.role")?.to_string();
            let kind = spec["kind"].as_str().unwrap_or("DependsOn");
            let from = by_role
                .get(spec["from"].as_str().ok_or("relationship.from")?)
                .ok_or("relationship.from names no object")?
                .clone();
            let to = by_role
                .get(spec["to"].as_str().ok_or("relationship.to")?)
                .ok_or("relationship.to names no object")?
                .clone();
            let rel = KirRelationship::new(kind_of(kind)?, from, to);
            ledger.append_relationship(&rel).map_err(|e| format!("append_relationship: {e}"))?;
            by_role.insert(role.clone(), rel.id);
            rel_ends.insert(
                rel.id.0.to_string(),
                (name_of[&from.0.to_string()].clone(), name_of[&to.0.to_string()].clone()),
            );
        }
        let scopes = parse_scopes(&input["scopes"])?;
        let inner: Box<dyn KnowledgeStore> = Box::new(
            Ledger::open(&path).map_err(|e| format!("re-open: {e}"))?,
        );
        let store = ScopedStore::with_scopes(inner, &scopes)
            .map_err(|e| format!("with_scopes: {e}"))?;
        Ok(Self {
            last_fingerprint: store.scope_fingerprint(),
            store,
            by_role,
            name_of,
            rel_ends,
            evidence_of,
        })
    }

    fn id(&self, role: &Value, what: &str) -> Result<KirId, String> {
        self.by_role
            .get(role.as_str().ok_or_else(|| format!("{what} is not a string"))?)
            .copied()
            .ok_or_else(|| format!("{what} names nothing: {role}"))
    }

    /// `from_name->to_name`, or `null`-shaped absence handled by the caller.
    fn rel_name(&self, rel: &KirRelationship) -> Value {
        match self.rel_ends.get(&rel.id.0.to_string()) {
            Some((from, to)) => json!(format!("{from}->{to}")),
            // A relationship this run appended (never in these items): ends by name.
            None => json!(format!(
                "{}->{}",
                self.name_of.get(&rel.from.0.to_string()).cloned().unwrap_or_default(),
                self.name_of.get(&rel.to.0.to_string()).cloned().unwrap_or_default(),
            )),
        }
    }

    fn sorted_names(&self, objects: &[KirObject]) -> Value {
        let mut names: Vec<String> = objects.iter().map(|o| o.name.clone()).collect();
        names.sort();
        json!(names)
    }

    fn sorted_rels(&self, rels: &[KirRelationship]) -> Value {
        let mut pairs: Vec<String> = rels.iter().map(|r| self.rel_name(r).as_str().unwrap_or_default().to_string()).collect();
        pairs.sort();
        json!(pairs)
    }

    fn refuse_kind(err: &LedgerError) -> Value {
        match err {
            LedgerError::ReadScope(_) => json!("read_scope"),
            other => json!(format!("error:{other}")),
        }
    }

    fn step(&mut self, step: &Value, dir: &std::path::Path) -> Result<Value, String> {
        let op = step["op"].as_str().ok_or("step.op")?;
        let s = &self.store;
        Ok(match op {
            "is_restricted" => json!(s.is_restricted()),
            "fingerprint_empty" => json!(s.scope_fingerprint().is_empty()),
            "fingerprint_nonempty" => json!(!s.scope_fingerprint().is_empty()),
            "fingerprint_differs_from_last" => {
                let now = s.scope_fingerprint();
                let differs = now != self.last_fingerprint;
                self.last_fingerprint = now;
                json!(differs)
            }
            "all_objects" => self.sorted_names(&s.all_objects().map_err(err_of)?),
            "all_relationships" => self.sorted_rels(&s.all_relationships().map_err(err_of)?),
            "all_objects_at" => self.sorted_names(&s.all_objects_at(Utc::now()).map_err(err_of)?),
            "all_relationships_at" => {
                self.sorted_rels(&s.all_relationships_at(Utc::now()).map_err(err_of)?)
            }
            "get_object" => match s.get_object(&self.id(&step["role"], "role")?).map_err(err_of)? {
                Some(o) => json!(o.name),
                None => Value::Null,
            },
            "object_history" => self.sorted_names(&s.object_history(&self.id(&step["role"], "role")?).map_err(err_of)?),
            "object_at" => match s.object_at(&self.id(&step["role"], "role")?, Utc::now()).map_err(err_of)? {
                Some(o) => json!(o.name),
                None => Value::Null,
            },
            "fact" => s
                .fact(&self.id(&step["role"], "role")?, step["attr"].as_str().unwrap_or("name"))
                .map_err(err_of)?
                .unwrap_or(Value::Null),
            "audit_trail" => json!(s.audit_trail(&self.id(&step["role"], "role")?).map_err(err_of)?.len()),
            "relationships_for" => self.sorted_rels(&s.relationships_for(&self.id(&step["role"], "role")?).map_err(err_of)?),
            "relationships_at" => self.sorted_rels(&s.relationships_at(&self.id(&step["role"], "role")?, Utc::now()).map_err(err_of)?),
            "get_relationship" => match s.get_relationship(&self.id(&step["rel"], "rel")?).map_err(err_of)? {
                Some(r) => self.rel_name(&r),
                None => Value::Null,
            },
            "relationship_history" => json!(s.relationship_history(&self.id(&step["rel"], "rel")?).map_err(err_of)?.len()),
            "get_evidence" => {
                let id = self.evidence_id(&step["role"])?;
                json!(s.get_evidence(&id).map_err(err_of)?.is_some())
            }
            "find_objects" => {
                let query = step["query"].as_str().ok_or("find_objects.query")?;
                let mut names: Vec<String> = s
                    .find_objects(query)
                    .map_err(err_of)?
                    .iter()
                    .map(|(id, _)| {
                        self.name_of.get(&id.0.to_string()).cloned().unwrap_or_default()
                    })
                    .collect();
                names.sort();
                json!(names)
            }
            "retrieve" => {
                let query = step["query"].as_str().ok_or("retrieve.query")?;
                json!(s.retrieve(&RetrievalRequest::lexical(query)).map_err(err_of)?.hits.len())
            }
            "object_count" => json!(s.object_count().map_err(err_of)?),
            "relationship_count" => json!(s.relationship_count().map_err(err_of)?),
            "evidence_count" => json!(s.evidence_count().map_err(err_of)?),
            "entry_count" => json!(s.entry_count().map_err(err_of)?),
            "diff" => {
                let d = s.diff(Utc::now() - Duration::hours(1), Utc::now()).map_err(err_of)?;
                let touched: Vec<String> = d
                    .touched
                    .iter()
                    .map(|id| self.name_of.get(id).cloned().unwrap_or_else(|| id.clone()))
                    .collect();
                json!({"touched": touched, "added": d.added.len()})
            }
            "append_object" => {
                let name = step["name"].as_str().unwrap_or("new");
                match s.append_object(&KirObject::new(name, ObjectKind::Table)) {
                    Ok(inserted) => json!(inserted),
                    Err(e) => Self::refuse_kind(&e),
                }
            }
            "append_evidence" => {
                let ev = KirEvidence::new(SourceLocation::file("a"), "t");
                match s.append_evidence(&ev) {
                    Ok(()) => json!("ok"),
                    Err(e) => Self::refuse_kind(&e),
                }
            }
            "append_relationship" => {
                let from = self.id(&step["frm"], "frm")?;
                let to = self.id(&step["to"], "to")?;
                match s.append_relationship(&KirRelationship::new(RelationshipKind::DependsOn, from, to)) {
                    Ok(inserted) => json!(inserted),
                    Err(e) => Self::refuse_kind(&e),
                }
            }
            "vacuum_into" => {
                let dest = dir.join("copy.db");
                match s.vacuum_into(&dest) {
                    Ok(()) => json!("ok"),
                    Err(e) => Self::refuse_kind(&e),
                }
            }
            "get_event" => {
                let id: KirId = NO_EVENT.parse().map_err(|e| format!("no_event id: {e}"))?;
                json!(s.get_event(&id).map_err(err_of)?.is_none())
            }
            "set_scopes" => {
                // `last_fingerprint` is deliberately NOT updated here: the
                // tests capture the fingerprint before a scope change and
                // compare across it (`assert_ne!`), so "last" means "at the
                // last fingerprint observation", not "after the last change".
                let scopes = parse_scopes(&step["scopes"])?;
                s.set_scopes(&scopes).map_err(|e| format!("set_scopes: {e}"))?;
                json!("ok")
            }
            other => return Err(format!("unknown op {other}")),
        })
    }

    /// The first evidence id of the role's object, as the tests ask for
    /// `w.<role>.evidence[0]`.
    fn evidence_id(&self, role: &Value) -> Result<KirId, String> {
        let obj_role = role.as_str().ok_or("role is not a string")?;
        self.evidence_of
            .get(obj_role)
            .copied()
            .ok_or_else(|| format!("object {obj_role} carries no evidence"))
    }
}

fn err_of(e: LedgerError) -> String {
    format!("store: {e}")
}

fn kind_of(name: &str) -> Result<RelationshipKind, String> {
    match name {
        "DependsOn" => Ok(RelationshipKind::DependsOn),
        other => Err(format!("unknown relationship kind {other}")),
    }
}

fn parse_scopes(v: &Value) -> Result<Vec<ReadScope>, String> {
    let list = v.as_array().ok_or("scopes is not a list")?;
    list.iter()
        .map(|text| {
            text.as_str()
                .ok_or_else(|| "scope is not a string".to_string())
                .and_then(|t| ReadScope::from_json(t).map_err(|e| format!("scope {t}: {e}")))
        })
        .collect()
}

pub fn control_for(item: &Item) -> Value {
    let run = || -> Result<Value, String> {
        let dir = std::env::temp_dir().join(format!("verekos-scope-store-{}", std::process::id()));
        std::fs::create_dir_all(&dir).map_err(|e| format!("tempdir: {e}"))?;
        let result = (|| {
            let mut world = World::build(&item.input, &dir)?;
            let mut results = Vec::new();
            for step in item.input["steps"].as_array().ok_or("steps is not a list")? {
                results.push(world.step(step, &dir)?);
            }
            Ok(json!({"item": item.item, "results": results}))
        })();
        let _ = std::fs::remove_dir_all(&dir);
        result
    };
    match run() {
        Ok(v) => v,
        Err(e) => json!({"item": item.item, "error": e}),
    }
}

/// The expected file carries `{"results": [...]}`: the control's whole result
/// list must equal it element for element, in step order.
pub fn check_assert(control: &Value, assert: &Value) -> Vec<String> {
    let mut failures = Vec::new();
    match (control.get("results"), assert.get("results")) {
        (Some(Value::Array(got)), Some(Value::Array(want))) => {
            if got.len() != want.len() {
                failures.push(format!("results: control has {} steps, expected {}", got.len(), want.len()));
            }
            for (i, (g, w)) in got.iter().zip(want.iter()).enumerate() {
                if g != w {
                    failures.push(format!("step {i}: control {g} != expected {w}"));
                }
            }
        }
        (None, _) => failures.push("control has no results (item errored?)".into()),
        _ => failures.push("assert.results is not a list".into()),
    }
    failures
}
