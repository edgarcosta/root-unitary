load("prescribed_roots.sage")
polRing.<x> = PolynomialRing(ZZ)
powRing.<y> = PowerSeriesRing(QQ)
l1 = []
for i in range(11):
    l1.append([])
f = open("k3-scripts/k3f1-lines.txt", "rb")
for i in f:
    j = eval(i)
    k = (len(j)-1)/2
    l1[k].append(polRing(j))
f.close()
print "Loaded", sum(len(i) for i in l1), "1-polynomials"
l2 = []
for i in range(11):
    l2.append([])
f = open("k3-scripts/k3f2-lines.txt", "rb")
for i in f:
    j = eval(i)
    k = (len(j)-1)/2
    l2[k].append(polRing(j))
f.close()
print "Loaded", sum(len(i) for i in l2), "2-polynomials"
l3 = []
for i in range(11):
    for j in l1[i]:
        for k in l2[10-i]:
	    l3.append(j*k)
print "Full set of products:", len(l3), "polynomials"
l4 = [i for i in l3 if ej_test(i)]
print "Satisfying Artin-Tate condition:", len(l4), "polynomials"
l5 = []
for i in l4:
    s = i[0].sign()
    m2 = log((powRing(s*i(2*x)//2)*(1-y)*(1-2*y)*(1-4*y)).inverse())
    if m2[1] >= 0 and m2[2]*2 >= m2[1] and m2[3]*3 >= m2[1] and m2[4]*4 >= m2[2]*2:
        l5.append(m)
print "Satisfying nonnegativity:", len(l5), "polynomials"
f = open("k3-scripts/k3f2-full-filtered.txt", "wb")
for i in l5:
    f.write(str(i.list()))
    f.write("\n")
f.close()



