function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(prepare_image),Vector{Vector{UInt}},Vector{UInt},Vector{Int},Dict{UInt,Vector{Base.StackTraces.StackFrame}},Vector{Vector{Base.StackTraces.StackFrame}},Bool,Bool,Bool,Vector{Any}})
    precompile(Tuple{typeof(hcat),Vector{TagData},Vector{TagData},Vector{TagData},Vararg{Vector{TagData},N} where N})
end
