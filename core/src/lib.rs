use std::mem;

use emacs::{Env, Result, Value};

#[macro_use]
mod types;
mod error;
mod lang;
mod parser;
mod tree;
mod node;
mod cursor;
mod query;

mod buffer;

emacs::plugin_is_GPL_compatible! {}

#[emacs::module(name = "tsc-dyn", defun_prefix = "tsc", mod_in_name = false)]
fn init(env: &Env) -> Result<()> {
    env.call("set", (env.intern("tsc-dyn--version")?, option_env!("CARGO_PKG_VERSION")))?;

    let get_addr = env.call("symbol-function", [env.intern("ng-module-function-address")?])?;
    if get_addr.is_not_nil() {
        match get_addr.call(("ng_module_access_current_buffer_contents",))?.into_rust::<Option<Value>>()? {
            Some(addr) => {
                buffer::ng_module_access_current_buffer_contents.set(
                    unsafe { mem::transmute(addr.get_user_ptr()?) }
                ).unwrap();
                env.call("set", (env.intern("tsc--has-direct-buffer-access-p")?, true))?;
                env.call("message", ("Got ng_module_access_current_buffer_contents @ %s", addr))?;
            }
            None => (),
        }
    }
    Ok(())
}
