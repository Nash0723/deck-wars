//! luaurun: runs a Luau script outside Roblox.
//!
//! Usage:
//!   luaurun [-D NAME=VALUE ...] <script.luau> [module dirs...]
//!   luaurun --check <file.luau> [more files...]
//!
//! - `require("Name")` loads `Name.luau` (or `Name.lua`) from the module dirs, then from the
//!   script's own folder. Each module runs once and its result is cached.
//! - `-D NAME=VALUE` sets a global before the script runs (numbers, true/false, nil, else a string),
//!   for example `-D SOAK_GAMES=12` or `-D BAL_GAMES=60`.
//! - `__readfile(path)` returns a file's text and `__loadchunk(src, name, env)` compiles a chunk
//!   with its own environment table (used by the mock Roblox harness).
//! - `--check` only compiles the files and reports syntax errors.

use mlua::{Function, Lua, Table, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::rc::Rc;

fn find_module(dirs: &[PathBuf], name: &str) -> Option<PathBuf> {
    for d in dirs {
        for ext in ["luau", "lua"] {
            let p = d.join(format!("{name}.{ext}"));
            if p.is_file() {
                return Some(p);
            }
        }
    }
    None
}

fn parse_value(lua: &Lua, s: &str) -> mlua::Result<Value> {
    Ok(match s {
        "true" => Value::Boolean(true),
        "false" => Value::Boolean(false),
        "nil" => Value::Nil,
        _ => match s.parse::<f64>() {
            Ok(n) => Value::Number(n),
            Err(_) => Value::String(lua.create_string(s)?),
        },
    })
}

fn run() -> Result<(), String> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let lua = Lua::new();

    if args.first().map(String::as_str) == Some("--check") {
        let mut bad = 0;
        for f in &args[1..] {
            let src = std::fs::read_to_string(f).map_err(|e| format!("{f}: {e}"))?;
            match lua.load(&src).set_name(f.as_str()).into_function() {
                Ok(_) => println!("ok   {f}"),
                Err(e) => {
                    bad += 1;
                    println!("FAIL {f}: {e}");
                }
            }
        }
        return if bad == 0 { Ok(()) } else { Err(format!("{bad} file(s) failed to compile")) };
    }

    let mut defines = Vec::new();
    while args.first().map(String::as_str) == Some("-D") {
        args.remove(0);
        if args.is_empty() {
            return Err("-D needs NAME=VALUE".into());
        }
        defines.push(args.remove(0));
    }
    let Some(script) = args.first().cloned() else {
        return Err("usage: luaurun [-D NAME=VALUE ...] <script.luau> [module dirs...]\n       luaurun --check <files...>".into());
    };
    let mut dirs: Vec<PathBuf> = args[1..].iter().map(PathBuf::from).collect();
    dirs.push(Path::new(&script).parent().map(Path::to_path_buf).unwrap_or_default());

    let g = lua.globals();
    let e = |x: mlua::Error| x.to_string();
    for d in &defines {
        let (k, v) = d.split_once('=').ok_or(format!("-D {d}: expected NAME=VALUE"))?;
        g.set(k, parse_value(&lua, v).map_err(e)?).map_err(e)?;
    }

    let cache: Rc<RefCell<HashMap<String, Value>>> = Rc::default();
    let require = lua
        .create_function(move |lua, name: String| {
            if let Some(v) = cache.borrow().get(&name) {
                return Ok(v.clone());
            }
            let path = find_module(&dirs, &name)
                .ok_or_else(|| mlua::Error::runtime(format!("module '{name}' not found")))?;
            let src = std::fs::read_to_string(&path).map_err(mlua::Error::external)?;
            let v: Value = lua.load(&src).set_name(path.to_string_lossy()).call(())?;
            let v = if v.is_nil() { Value::Boolean(true) } else { v };
            cache.borrow_mut().insert(name, v.clone());
            Ok(v)
        })
        .map_err(e)?;
    g.set("require", require).map_err(e)?;

    let readfile = lua
        .create_function(|_, path: String| std::fs::read_to_string(&path).map_err(|x| mlua::Error::runtime(format!("{path}: {x}"))))
        .map_err(e)?;
    g.set("__readfile", readfile).map_err(e)?;

    let loadchunk = lua
        .create_function(|lua, (src, name, env): (String, String, Option<Table>)| -> mlua::Result<Function> {
            let chunk = lua.load(&src).set_name(name);
            match env {
                Some(t) => chunk.set_environment(t).into_function(),
                None => chunk.into_function(),
            }
        })
        .map_err(e)?;
    g.set("__loadchunk", loadchunk).map_err(e)?;

    let src = std::fs::read_to_string(&script).map_err(|x| format!("{script}: {x}"))?;
    lua.load(&src).set_name(script.as_str()).exec().map_err(e)
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(m) => {
            eprintln!("{m}");
            ExitCode::FAILURE
        }
    }
}
