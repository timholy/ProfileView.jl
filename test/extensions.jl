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
        # profile_test(1)   # defined in test/runtests.jl
        # @profile profile_test(10)
        _, bt = add2(Any[1,2])
        st = stacktrace(bt)
        ProfileView.clicked[] = st[1]
        terminal = VirtualTerminal()
        harness = Testing.@run terminal descend_clicked(; terminal)
        Testing.wait_for(harness.task)
        lines = String(readavailable(harness.io))
        @test occursin("Select a call to descend into", lines)
        write(terminal, 'q')
        @test Testing.end_terminal_session(harness)
        terminal = VirtualTerminal()
        ProfileView.clicked_trace[] = st
        harness = Testing.@run terminal ascend_clicked(; terminal)
        Testing.wait_for(harness.task)
        lines = String(readavailable(harness.io))
        @test occursin("Choose a call for analysis", lines)
        write(terminal, 'q')
        @test Testing.end_terminal_session(harness)
    end
end