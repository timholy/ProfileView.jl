module ProfileViewCthulhuExt

using ProfileView
using Cthulhu: Cthulhu

function ProfileView.descend_clicked(; optimize=false, iswarn=true, hide_type_stable=true, kwargs...)
    st = ProfileView.clicked[]
    if st === nothing || st.linfo === nothing
        @warn "the bar you clicked on might have been inlined and unavailable for inspection. Click on a non-inlined bar to `descend`."
        return nothing
    end
    return Cthulhu.descend(st.linfo; optimize, iswarn, hide_type_stable, kwargs...)
end
function ProfileView.ascend_clicked(; hide_type_stable=true, terminal=Cthulhu.default_terminal(), kwargs...)
    st = ProfileView.clicked[]
    if st === nothing || st.linfo === nothing
        @warn "the bar you clicked on might have been inlined and unavailable for inspection. Click on a non-inlined bar to `descend`."
        return nothing
    end
    if hasmethod(Cthulhu.buildframes, Tuple{Vector{StackTraces.StackFrame}})
        return Cthulhu.ascend(terminal, ProfileView.clicked_trace[]; hide_type_stable, kwargs...)
    else
        return Cthulhu.ascend(terminal, st.linfo; hide_type_stable, kwargs...)
    end
end

end
