function _precompile_()
    stackframe(func, file, line; C=false) = StackFrame(Symbol(func), Symbol(file), line, nothing, C, false, 0)
    backtraces = UInt64[0, 4, 3, 2, 1,   # order: calles then caller
                        0, 6, 5, 1,
                        0, 8, 7,
                        0, 4, 3, 2, 1,
                        0]
    if isdefined(Profile, :add_fake_meta)
        backtraces = Profile.add_fake_meta(backtraces)
    end
    lidict = Dict{UInt64,StackFrame}(1=>stackframe(:f1, :file1, 1),
                                     2=>stackframe(:f2, :file1, 5),
                                     3=>stackframe(:f3, :file2, 1),
                                     4=>stackframe(:f2, :file1, 15),
                                     5=>stackframe(:f4, :file1, 20),
                                     6=>stackframe(:f5, :file3, 1),
                                     7=>stackframe(:f1, :file1, 2),
                                     8=>stackframe(:f6, :file3, 10))
    g = flamegraph(backtraces; lidict=lidict)
    gdict = Dict(tabname_allthreads => Dict(tabname_alltasks => g))
    win, c, fdraw = viewgui(FlameGraphs.default_colors, gdict)
    for obs in c.preserved
        if isa(obs, Observable) || isa(obs, Observables.ObserverFunction)
            precompile(obs)
        end
    end
    precompile(fdraw)
    closeall()   # necessary to prevent serialization of stale references (including the internal `empty!`)
    precompile(viewprof_func, (FlameColors, GtkObservables.Canvas{GtkObservables.UserUnit}, FlameGraphs.LeftChildRightSiblingTrees.Node{FlameGraphs.NodeData}, Int))
    precompile(Tuple{typeof(save_as_cb),Ptr{GObject},Tuple{Gtk.GtkCanvas, Vector{UInt64}, Dict{UInt64, Vector{StackFrame}}}})   # time: 0.008177923
    precompile(Tuple{typeof(save_as_cb),Ptr{GObject},Tuple{Gtk.GtkCanvas, Nothing, Nothing}})
    precompile(warntype_last, ())
end
