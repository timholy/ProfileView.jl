function profile_test(n)
    for i = 1:n
        A = randn(100,100,20)
        m = max(A)
        Afft = fft(A)
        Am = mapslices(sum, A, 2)
        B = A[:,:,5]
        Bsort = mapslices(sort, B, 1)
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

profile_test(1)
Profile.clear()
@profile profile_test(10)
ProfileView.view()
