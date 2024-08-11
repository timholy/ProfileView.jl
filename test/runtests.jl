using Profile
using ProfileView
using GtkObservables
using Gtk4
using AbstractTrees
using Test

function profile_test(n)
    for i = 1:n
        A = randn(100,100,20)
        m = maximum(A)
        Am = mapslices(sum, A, dims = 2)
        B = A[:,:,5]
        Bsort = mapslices(sort, B, dims = 1)
        b = rand(100)
        C = B.*b
    end
end

unstable(x) = x > 0.5 ? true : 0.0

function profile_unstable_test(m, n)
    s = s2 = 0
    for i = 1:n
        for k = 1:m
            s += unstable(rand())
        end
        x = collect(1:20)
        s2 += sum(x)
    end
    s, s2
end

function add2(x)
    y = x[1] + x[2]
    return y, backtrace()
end

@testset "ProfileView" begin
    Gtk4.GLib.start_main_loop(true)  # the loop only starts automatically if isinteractive() == true
    @testset "windows" begin
        profile_test(1)
        @test isa(@profview(profile_test(10)), ProfileView.GtkWindow)
        data, lidict = Profile.retrieve()

        Profile.clear()
        @profile profile_test(10)
        @test isa(ProfileView.view(), ProfileView.GtkWindow)
        @test isa(ProfileView.view(C=true), ProfileView.GtkWindow)
        @test isa(ProfileView.view(fontsize=18), ProfileView.GtkWindow)
        @test isa(ProfileView.view(windowname="ProfileWindow"), ProfileView.GtkWindow)
        @test isa(ProfileView.view(graphtype=:icicle), ProfileView.GtkWindow)

        before = ProfileView._graphtype[]
        try
            @test_logs (:info, "Default graphtype set to :icicle") ProfileView.set_graphtype!(:icicle)
            @test isa(ProfileView.view(), ProfileView.GtkWindow)
            @test_logs (:info, "Default graphtype set to :flame") ProfileView.set_graphtype!(:flame)
            @test isa(ProfileView.view(), ProfileView.GtkWindow)
            @test_throws ArgumentError ProfileView.set_graphtype!(:other)
        finally
            @test_logs (:info, "Default graphtype set to $(repr(before))") ProfileView.set_graphtype!(before)
        end

        before = ProfileView._theme[]
        try
            @test_logs (:info, "Default theme set to :dark") ProfileView.set_theme!(:dark)
            @test isa(ProfileView.view(), ProfileView.GtkWindow)
            @test_logs (:info, "Default theme set to :light") ProfileView.set_theme!(:light)
            @test isa(ProfileView.view(), ProfileView.GtkWindow)
            @test_throws ArgumentError ProfileView.set_theme!(:other)
        finally
            @test_logs (:info, "Default theme set to $(repr(before))") ProfileView.set_theme!(before)
        end

        @test_throws ArgumentError ProfileView.view(graphtype = :other)

        Profile.clear()
        profile_unstable_test(1, 1)
        @profile profile_unstable_test(10, 10^6)
        @test isa(ProfileView.view(), ProfileView.GtkWindow)

        @test isa(ProfileView.view(ProfileView.FlameGraphs.flamegraph()), ProfileView.GtkWindow)
        @test isa(ProfileView.view(ProfileView.FlameGraphs.FlameColors()), ProfileView.GtkWindow)

        data, lidict = Profile.retrieve()
        @test isa(ProfileView.view(data, lidict=lidict), ProfileView.GtkWindow)

        @test isa(ProfileView.view(nothing), ProfileView.GtkWindow)

        # Interactivity
        stackframe(func, file, line; C=false) = ProfileView.StackFrame(Symbol(func), Symbol(file), line, nothing, C, false, 0)

        backtraces = UInt64[0, 4, 3, 2, 1,   # order: calles then caller
                            0, 6, 5, 1,
                            0, 8, 7,
                            0, 4, 3, 2, 1,
                            0]
        if isdefined(Profile, :add_fake_meta)
            backtraces = Profile.add_fake_meta(backtraces)
        end
        lidict = Dict{UInt64,Vector{ProfileView.StackFrame}}(
            1=>[stackframe(:f1, :file1, 1)],
            2=>[stackframe(:f2, :file1, 5)],
            3=>[stackframe(:f3, :file2, 1)],
            4=>[stackframe(:f2, :file1, 15)],
            5=>[stackframe(:f4, :file1, 20)],
            6=>[stackframe(:f5, :file3, 1)],
            7=>[stackframe(:f1, :file1, 2)],
            8=>[stackframe(:f6, :file3, 10)])
        g = ProfileView.flamegraph(backtraces; lidict=lidict)
        win, c, fdraw, (tb_open, tb_save_as) = ProfileView.viewgui(ProfileView.FlameGraphs.default_colors, g);
        ProfileView.Gtk4.show(win)
        sleep(1.0)
        @test c.widget.is_sized  # to ensure the motion test really runs
        btn = c.mouse.motion[]
        c.mouse.motion[] = MouseButton(XY{UserUnit}(2.8, 1.4), btn.button, btn.clicktype, btn.modifiers)
        # do it again to check the repair code
        c.mouse.motion[] = MouseButton(XY{UserUnit}(2.9, 1.4), btn.button, btn.clicktype, btn.modifiers)
        mktemp() do path, io
            redirect_stdout(io) do
                c.mouse.buttonpress[] = MouseButton(XY{UserUnit}(2.8, 1.4), 1, GtkObservables.BUTTON_PRESS, btn.modifiers)
            end
            flush(io)
            @test occursin("file3:1, f5 [inlined]", read(path, String))
        end
        fn = tempname()
        try
            tmp = Observable{typeof(g)}()
            ProfileView._save(fn, backtraces, lidict)
            ProfileView._open(tmp, fn)
            for (gn, sn) in zip(PreOrderDFS(g), PreOrderDFS(tmp[]))
                @test gn.data == sn.data
            end
            ProfileView._save(fn, g)
            ProfileView._open(tmp, fn)
            for (gn, sn) in zip(PreOrderDFS(g), PreOrderDFS(tmp[]))
                @test gn.data == sn.data
            end
        finally
            rm(fn)
        end

        # Also click on real stackframes
        Profile.clear()
        @profile profile_test(100)
        g = ProfileView.flamegraph()
        win, c, fdraw, (tb_open, tb_save_as) = ProfileView.viewgui(ProfileView.FlameGraphs.default_colors, g);
        ProfileView.Gtk4.show(win)
        while !isdefined(c.widget,:backcc)
            sleep(1.0)
        end
        sz = size(ProfileView.flamepixels(ProfileView.FlameGraphs.default_colors, g))
        mktemp() do path, io
            redirect_stdout(io) do
                for j in 1:sz[2], i in 1:sz[1]
                    c.mouse.buttonpress[] = MouseButton(XY{UserUnit}(j, i), 1, GtkObservables.BUTTON_PRESS, btn.modifiers)
                end
            end
            flush(io)
            @test occursin("MethodInstance", read(path, String))
        end


        ProfileView.closeall()
    end

    @testset "warntype_clicked" begin
        # Test `warntype_clicked`
        ProfileView.clicked[] = nothing
        @test_logs (:warn, "click on a non-inlined bar to see `code_warntype` info") warntype_clicked() === nothing
        _, bt = add2(Any[1,2])
        st = stacktrace(bt)
        ProfileView.clicked[] = st[1]
        io = IOBuffer()
        warntype_clicked(io)
        str = String(take!(io))
        @test occursin("Base.getindex(x, 1)::ANY", str)
        idx = findfirst(sf -> sf.inlined, st)
        ProfileView.clicked[] = st[idx]
        @test_logs (:warn, "click on a non-inlined bar to see `code_warntype` info") warntype_clicked(io) === nothing
    end
end
