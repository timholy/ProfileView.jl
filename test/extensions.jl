using ProfileView
using Cthulhu
if !isdefined(@__MODULE__, :fake_terminal)
    @eval (@__MODULE__) begin
        include(joinpath(pkgdir(Cthulhu), "test", "FakeTerminals.jl"))
        using .FakeTerminals
        macro with_try_stderr(out, expr)
            quote
                try
                    $(esc(expr))
                catch err
                    bt = catch_backtrace()
                    Base.display_error(stderr, err, bt)
                    #close($(esc(out)))
                end
            end
        end
    end
end
using Test

@testset "Extensions" begin
    @testset "Cthulhu" begin
        cread1(io) = readuntil(io, '↩'; keep=true)
        cread(io) = cread1(io) * cread1(io)

        # profile_test(1)   # defined in test/runtests.jl
        # @profile profile_test(10)
        _, bt = add2(Any[1,2])
        st = stacktrace(bt)
        ProfileView.clicked[] = st[1]
        fake_terminal() do term, in, out, _
            t = @async begin
                @with_try_stderr out descend_clicked(; interruptexc=false, terminal=term)
            end
            lines = cread(out)
            @test occursin("Select a call to descend into", lines)
            write(in, 'q')
            wait(t)
        end
        ProfileView.clicked_trace[] = st
        fake_terminal() do term, in, out, _
            t = @async begin
                @with_try_stderr out ascend_clicked(; interruptexc=false, terminal=term)
            end
            lines = readuntil(out, 'q'; keep=true)   # up to the "q to quit" prompt
            @test occursin("Choose a call for analysis", lines)
            write(in, 'q')
            write(in, 'q')
            wait(t)
        end
    end
end