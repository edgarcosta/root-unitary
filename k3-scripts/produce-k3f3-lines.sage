load("prescribed_roots.sage")
polRing.<x> = PolynomialRing(ZZ)
ans = [polRing(3)]
for i in range(1, 11):
    temp, count = roots_on_unit_circle(3*(x^(2*i)+1), 
                                       filter=no_roots_of_unity,
                                       num_threads=768)
    print len(temp)
    ans += temp
f = open("k3f3-lines.txt", "wb")
for i in ans:
    f.write(str(list(i)))
    f.write("\n")
f.close()