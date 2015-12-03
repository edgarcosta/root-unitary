polRing.<x> = PolynomialRing(ZZ)

t = True
CF = ComplexField(53)
for p in primes(25):
    print(p)
    l = []
    for i in range(1,5):
        ans, count = roots_on_unit_circle(1 + (p*x^2)^i)
        l.append(ans)
        for i in ans:
            for j in i.roots(CF):
                if (abs(p*abs(j[0])^2 - 1) > 0.01):
                    t = False
                    print "Error:", i
    for i in range(1,3):
        for j in range(i,4-i):
            for t1 in l[i-1]:
                for t2 in l[j-1]:
                    if not (t1*t2 in l[i+j-1]):
                        t = False
                        print "Error: ", t1, t2
                    
if t: print("All tests passed")
