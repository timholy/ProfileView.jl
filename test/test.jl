using Profile
using ProfileView

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

function profile_simple_test(n)
    for i = 1:n
        A = randn(100,100,20)
        m = max(A)
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

profile_test(1)
Profile.clear()
@profile profile_test(10)
ProfileView.view()

profile_unstable_test(1, 1)
Profile.clear()
@profile profile_unstable_test(10, 10^6)
ProfileView.view()

mktemp() do filename, io
    ProfileView.svgwrite(io)
end
