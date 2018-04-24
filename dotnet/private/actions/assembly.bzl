load(
    "@io_bazel_rules_dotnet//dotnet/private:common.bzl",
    "as_iterable",
)

load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
)


def _map_dep(deps):
  return [d[DotnetLibrary].result for d in deps]


def _make_runner_arglist(dotnet, deps, output, executable):
  args = dotnet.actions.args()

  # /out:<file>
  args.add(format="/out:%s", value=output.path)

  if executable:
    target = "exe"
  else:
    target = "library"

  # /target (exe for binary, library for lib, module for module)
  args.add(format="/target:%s", value=target)

  args.add("/fullpaths")
  args.add("/noconfig")
  args.add("/nostdlib")

  # /warn
  #args.add(format="/warn:%s", value=str(ctx.attr.warn))

  # /nologo
  args.add("/nologo")

  # /modulename:<string> only used for modules
  #libdirs = _get_libdirs(depinfo.dlls)
  #libdirs = _get_libdirs(depinfo.transitive_dlls, libdirs)

  # /lib:dir1,[dir1]
  #if libdirs:
  #  args.add(format="/lib:%s", value=libdirs)

  # /reference:filename[,filename2]
  if deps and len(deps)>0:
    args.add(format="/reference:%s", value=deps, map_fn=_map_dep)

  args.add(format="/reference:%s", value=dotnet.stdlib)

  #if depinfo.refs or extra_refs:
  #  args.add(format="/reference:%s", value=depinfo.refs + extra_refs)
  #else:
  #  args.add(extra_refs)

  # /doc
  #if hasattr(ctx.outputs, "doc_xml"):
  #  args.add(format="/doc:%s", value=ctx.outputs.doc_xml.path)

  # /debug
  #debug = ctx.var.get("BINMODE", "") == "-dbg"
  #if debug:
  #  args.add("/debug")

  # /warnaserror
  # TODO(jeremy): /define:name[;name2]
  # TODO(jeremy): /resource:filename[,identifier[,accesibility-modifier]]

  # /main:class
  #if hasattr(ctx.attr, "main_class") and ctx.attr.main_class:
  #  args.add(format="/main:%s", value=ctx.attr.main_class)

  #args.add(format="/resource:%s", value=ctx.files.resources)

  # TODO(jwall): /parallel

  return args

def emit_assembly(dotnet,
    name = "",
    srcs = None,
    deps = None,
    out = None,
    executable = True):
  """See dotnet/toolchains.rst#binary for full documentation."""

  if name == "" and out == None:
    fail("either name or out must be set")

  if not out:
    if executable:
      extension = ".exe"
    else:
      extension = ".dll"
    result = dotnet.declare_file(dotnet, path=name+extension)
  else:
    result = dotnet.declare_file(dotnet, path=out)  
    
  runner_args = _make_runner_arglist(dotnet, deps, result, executable)

  attr_srcs = [f for t in srcs for f in as_iterable(t.files)]
  runner_args.add(attr_srcs)

  runner_args.set_param_file_format("multiline")

  # Use a "response file" to pass arguments to csc.
  # Windows has a max command-line length of around 32k bytes. The default for
  # Args is to spill to param files if the length of the executable, params
  # and spaces between them sum to that number. Unfortunately the math doesn't
  # work out exactly like that on Windows (e.g. there is also a null
  # terminator, escaping.) For now, setting use_always to True is the
  # conservative option. Long command lines are probable with C# due to
  # organizing files by namespace.
  paramfilepath = name+extension+".param"
  paramfile = dotnet.declare_file(dotnet, path=paramfilepath)

  dotnet.actions.write(output = paramfile, content = runner_args)

  dotnet.actions.run(
      inputs = attr_srcs + [paramfile] + _map_dep(deps) + [dotnet.stdlib],
      outputs = [result],
      executable = dotnet.runner,
      arguments = [dotnet.mcs.path, "@"+paramfile.path],
      progress_message = (
          "Compiling " + dotnet.label.package + ":" + dotnet.label.name))

  return dotnet.new_library(dotnet = dotnet, name = name, deps = deps, result = result)
