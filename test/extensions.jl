using ProfileView
using Cthulhu
using Cthulhu.Testing
# if !isdefined(@__MODULE__, Symbol("@with_try_stderr"))
#         macro with_try_stderr(out, expr)
#             quote
#                 try
#                     $(esc(expr))
#                 catch err
#                     bt = catch_backtrace()
#                     Base.display_error(stderr, err, bt)
#                 end
#             end
#         end
#     end
# end
using Test

@testset "Extensions" begin
    @testset "Cthulhu" begin
        println("starting Cthulhu extension tests")
        # profile_test(1)   # defined in test/runtests.jl
        # @profile profile_test(10)
        _, bt = add2(Any[1,2])
        st = stacktrace(bt)
        ProfileView.clicked[] = st[1]
        terminal = VirtualTerminal()
        harness = Testing.@run terminal descend_clicked(; terminal)
        displayed, text = Testing.read_next(harness)
        @test occursin("Select a call to descend into", text)
        @test Testing.end_terminal_session(harness)
        println("finished 1")
        terminal = VirtualTerminal()
        ProfileView.clicked_trace[] = st
        harness = Testing.@run terminal ascend_clicked(; terminal)
        # descend into something to generate a next "section" to read,
        # as VirtualTerminal is designed to read `descend` output
        write(terminal, :enter)
        displayed, text = Testing.read_next(harness)
        @test occursin("Choose a call for analysis", text)
        @test Testing.end_terminal_session(harness)
        println("finished 2")
    end
end