using ProfileView
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

# These tests only ensure that code runs, and does not check the "output"

profile_test(1)
@profview profile_test(10)

using Profile

Profile.clear()
@profile profile_test(10)
ProfileView.view()
ProfileView.view(C=true)
ProfileView.view(fontsize=18)
ProfileView.view(windowname="ProfileWindow")

Profile.clear()
profile_unstable_test(1, 1)
@profile profile_unstable_test(10, 10^6)
ProfileView.view()

ProfileView.view(ProfileView.FlameGraphs.flamegraph())

data, lidict = Profile.retrieve()
ProfileView.view(data, lidict=lidict)


ProfileView.closeall()

# Test `warntype_last`
function add2(x)
    y = x[1] + x[2]
    return y, backtrace()
end
_, bt = add2(Any[1,2])
st = stacktrace(bt)
ProfileView.clicked[] = st[1]
io = IOBuffer()
warntype_last(io)
str = String(take!(io))
@test occursin("Base.getindex(x, 1)::ANY", str)
