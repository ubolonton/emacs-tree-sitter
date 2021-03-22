use std::cell::RefCell;

use emacs::{defun, Env, Error, GlobalRef, IntoLisp, Result, Value, Vector};
use tree_sitter::{Node, QueryCursor, QueryErrorKind};

use crate::{
    types::{BytePos, Point},
    lang::Language,
    node::RNode,
    error,
    buffer,
};

fn vec_to_vector<'e, T: IntoLisp<'e>>(env: &'e Env, vec: Vec<T>) -> Result<Vector<'e>> {
    let vector = env.make_vector(vec.len(), ())?;
    for (i, v) in vec.into_iter().enumerate() {
        vector.set(i, v)?;
    }
    Ok(vector)
}

// -------------------------------------------------------------------------------------------------
// Query

struct Query {
    pub(crate) raw: tree_sitter::Query,
    pub(crate) capture_tags: Vec<GlobalRef>,
}

impl_pred!(query_p, &RefCell<Query>);

/// Create a new query from a SOURCE containing one or more S-expression patterns.
///
/// The query is associated with LANGUAGE, and can only be run on syntax nodes
/// parsed with LANGUAGE.
///
/// TAG-ASSIGNER is a function that is called to determine how captures are tagged
/// in query results. It should take a capture name defined in SOURCE's patterns
/// (e.g. "function.builtin"), and return a tag value. If the return value is nil,
/// the associated capture name is disabled.
#[defun(user_ptr)]
fn _make_query(language: Language, source: String, tag_assigner: Value) -> Result<Query> {
    let mut raw = tree_sitter::Query::new(language.into(), &source).or_else(|err| {
        let symbol = match err.kind {
            QueryErrorKind::Syntax => error::tsc_query_invalid_syntax,
            QueryErrorKind::NodeType => error::tsc_query_invalid_node_type,
            QueryErrorKind::Field => error::tsc_query_invalid_field,
            QueryErrorKind::Capture => error::tsc_query_invalid_capture,
            QueryErrorKind::Predicate => error::tsc_query_invalid_predicate,
            QueryErrorKind::Structure => error::tsc_query_invalid_structure,
        };
        let byte_pos: BytePos = err.offset.into();
        let point: Point = tree_sitter::Point { row: err.row, column: err.column }.into();
        // TODO: Character position?
        // TODO: Convert named node types and field names to symbols and keywords?
        tag_assigner.env.signal(symbol, (err.message, point, byte_pos))
    })?;
    let capture_names = raw.capture_names().to_vec();
    let mut capture_tags = vec![];
    for name in &capture_names {
        let value = tag_assigner.call((name, ))?;
        if !value.is_not_nil() {
            raw.disable_capture(name);
        }
        capture_tags.push(value.make_global_ref())
    }
    Ok(Query { raw, capture_tags })
}

macro_rules! defun_query_methods {
    ($($(#[$meta:meta])* $($lisp_name:literal)? fn $name:ident $( ( $( $param:ident : $type:ty ),* ) )? -> $rtype:ty $(; $into:ident)? )*) => {
        $(
            #[defun$((name = $lisp_name))?]
            $(#[$meta])*
            fn $name(query: &Query, $( $( $param : $type ),* )? ) -> Result<$rtype> {
                Ok(query.raw.$name( $( $( $param ),* )? )$(.$into())?)
            }
        )*
    };
}

defun_query_methods! {
    /// Return the byte position where the NTH pattern starts in QUERY's source.
    "-query-start-byte-for-pattern" fn start_byte_for_pattern(nth: usize) -> BytePos; into

    /// Return the number of patterns in QUERY.
    "query-count-patterns" fn pattern_count -> usize
}

/// Return the names of the captures used in QUERY.
#[defun]
fn _query_capture_names(query: Value) -> Result<Vector> {
    let env = query.env;
    let query = query.into_ref::<Query>()?;
    let names = query.raw.capture_names();
    let vec = env.make_vector(names.len(), ())?;
    for (i, name) in names.iter().enumerate() {
        vec.set(i, name)?;
    }
    Ok(vec)
}

/// Return all of QUERY's available capture tags.
/// See `tsc-make-query' for an explanation of capture tagging.
#[defun(mod_in_name = true)]
fn capture_tags<'e>(env: &'e Env, query: &Query) -> Result<Vector<'e>> {
    let symbols = env.make_vector(query.capture_tags.len(), ())?;
    for (i, symbol) in query.capture_tags.iter().enumerate() {
        symbols.set(i, symbol)?;
    }
    Ok(symbols)
}

/// Disable a certain capture within QUERY, by specifying its NAME.
///
/// This prevents the capture from being returned in matches, and also avoids any
/// resource usage associated with recording the capture.
#[defun]
fn _disable_capture(query: &mut Query, name: String) -> Result<()> {
    query.raw.disable_capture(&name);
    Ok(())
}

// -------------------------------------------------------------------------------------------------
// QueryCursor

impl_pred!(query_cursor_p, &RefCell<QueryCursor>);

/// Create a new cursor for executing a given query.
///
/// The cursor stores the state that is needed to iteratively search for matches.
#[defun(user_ptr)]
fn make_query_cursor() -> Result<QueryCursor> {
    Ok(QueryCursor::new())
}

fn text_callback<'e>(
    text_function: Value<'e>,
    error: &'e RefCell<Option<Error>>,
) -> impl FnMut(Node<'e>) -> String + 'e {
    move |child| {
        let beg: BytePos = child.start_byte().into();
        let end: BytePos = child.end_byte().into();
        text_function.call((beg, end)).and_then(|v| v.into_rust()).unwrap_or_else(|e| {
            error.borrow_mut().replace(e);
            "".to_owned()
        })
    }
}

#[defun]
fn _query_cursor_matches<'e>(
    cursor: &mut QueryCursor,
    query: &Query,
    node: &RNode,
    text_function: Value<'e>,
) -> Result<Vector<'e>> {
    let raw = &query.raw;
    let error = RefCell::new(None);
    let matches = cursor.matches(
        raw,
        node.borrow().clone(),
        text_callback(text_function, &error),
    );
    let mut vec = vec![];
    let env = text_function.env;
    for m in matches {
        if let Some(error) = error.borrow_mut().take() {
            return Err(error);
        }
        let captures = env.make_vector(m.captures.len(), ())?;
        for (ci, c) in m.captures.iter().enumerate() {
            let captured_node = node.map(|_| c.node);
            let capture = env.cons(
                &query.capture_tags[c.index as usize],
                captured_node
            )?;
            captures.set(ci, capture)?;
        }
        let _match = env.cons(m.pattern_index, captures)?;
        vec.push(_match);
    }
    vec_to_vector(env, vec)
}

// TODO: Make _query_cursor_captures accept a `capture_type` instead, e.g. node type, byte range.
#[defun]
fn _query_cursor_captures_1<'e>(
    cursor: &mut QueryCursor,
    query: Value<'e>,
    node: &RNode,
    text_function: Value<'e>,
) -> Result<Vector<'e>> {
    let query = query.into_rust::<&RefCell<Query>>()?.borrow();
    let raw = &query.raw;
    let error = RefCell::new(None);
    let captures = cursor.captures(
        raw,
        node.borrow().clone(),
        text_callback(text_function, &error),
    );
    let mut vec = vec![];
    let env = text_function.env;
    for (m, capture_index) in captures {
        if let Some(error) = error.borrow_mut().take() {
            return Err(error);
        }
        let c = m.captures[capture_index];
        let beg: BytePos = c.node.start_byte().into();
        let end: BytePos = c.node.end_byte().into();
        let capture = env.cons(
            &query.capture_tags[c.index as usize],
            env.cons(beg, end)?,
        )?;
        vec.push((m.pattern_index, capture));
    }
    // Prioritize captures from earlier patterns.
    vec.sort_unstable_by_key(|(i, _)| *i);
    let vector = env.make_vector(vec.len(), ())?;
    for (i, (_, v)) in vec.into_iter().enumerate() {
        vector.set(i, v)?;
    }
    Ok(vector)
}

#[defun]
fn _query_cursor_captures_2<'e>(
    // env: &Env,
    cursor: &mut QueryCursor,
    query: Value<'e>,
    node: &RNode,
) -> Result<Vector<'e>> {
    use std::borrow::Cow;
    let env = query.env;
    let input = |node: Node| -> Cow<[u8]> {
        let (before_gap, after_gap) = unsafe { buffer::current_buffer_contents(env) };
        let range = node.byte_range();
        let beg = range.start;
        let end = range.end;
        let before_len = before_gap.len();
        if end < before_len {
            return Cow::Borrowed(&before_gap[beg..end])
        }
        if beg >= before_len {
            let rem_beg = beg - before_len;
            let rem_end = end - before_len;
            return Cow::Borrowed(&after_gap[rem_beg..rem_end])
        }
        Cow::Borrowed(&[])
    };
    let query = query.into_rust::<&RefCell<Query>>()?.borrow();
    let raw = &query.raw;

    let captures = cursor.captures(
        raw,
        node.borrow().clone(),
        input,
    );
    let mut vec = vec![];
    for (m, capture_index) in captures {
        let c = m.captures[capture_index];
        let beg: BytePos = c.node.start_byte().into();
        let end: BytePos = c.node.end_byte().into();
        let capture = env.cons(
            &query.capture_tags[c.index as usize],
            env.cons(beg, end)?,
        )?;
        vec.push((m.pattern_index, capture));
    }
    // Prioritize captures from earlier patterns.
    vec.sort_unstable_by_key(|(i, _)| *i);
    let vector = env.make_vector(vec.len(), ())?;
    for (i, (_, v)) in vec.into_iter().enumerate() {
        vector.set(i, v)?;
    }
    Ok(vector)
}

#[defun]
fn _query_cursor_captures<'e>(
    cursor: &mut QueryCursor,
    query: Value<'e>,
    node: &RNode,
    text_function: Value<'e>,
) -> Result<Vector<'e>> {
    let query = query.into_rust::<&RefCell<Query>>()?.borrow();
    let raw = &query.raw;
    let error = RefCell::new(None);
    let captures = cursor.captures(
        raw,
        node.borrow().clone(),
        text_callback(text_function, &error),
    );
    let mut vec = vec![];
    let env = text_function.env;
    for (m, capture_index) in captures {
        if let Some(error) = error.borrow_mut().take() {
            return Err(error);
        }
        let c = m.captures[capture_index];
        let captured_node = node.map(|_| c.node);
        let capture = env.cons(
            &query.capture_tags[c.index as usize],
            captured_node
        )?;
        vec.push(capture);
    }

    // XXX
    let vector = env.make_vector(vec.len(), ())?;
    for (i, v) in vec.into_iter().enumerate() {
        vector.set(i, v)?;
    }
    Ok(vector)
}

/// Limit CURSOR's query executions to the range of byte positions, from BEG to END.
#[defun]
fn _query_cursor_set_byte_range(cursor: &mut QueryCursor, beg: BytePos, end: BytePos) -> Result<()> {
    cursor.set_byte_range(beg.into(), end.into());
    Ok(())
}

/// Limit CURSOR's query executions to the point range, from BEG to END.
///
/// A "point" in this context is a (LINE-NUMBER . BYTE-COLUMN) pair. See
/// `tsc-parse-chunks' for a more detailed explanation.
#[defun]
fn _query_cursor_set_point_range(cursor: &mut QueryCursor, beg: Point, end: Point) -> Result<()> {
    cursor.set_point_range(beg.into(), end.into());
    Ok(())
}
