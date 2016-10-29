
"""
Functions for generating the LMFDB data on isogeny classes of abelian varieties over FF_q

AUTHORS:
  -- (2016-05-11) Taylor Dupuy, Kiran S. Kedlaya, David Roe, Christelle Vincent


Fields we want to populate with an example

label: "2.9.ab_d"
polynomial: ["1","-1","3","-9","81"]
angle_numbers (doubles): [0.23756..., 0.69210...]
number_field: "4.0.213413.1"
p-rank: 1
slopes: ["0","1/2","1/2","1"]
A_counts: ["75", "7125"]
C_counts: ["9", "87"]
known_jacobian (0,1,-1): 1
decomposition: ["9.2.-1._3"]
pricipally_polarizable (0,1,-1): 1
Brauer Invariants: inv_v( End(A_{FFbar_q})_{QQ} )=(v(\pi)/v(q))*[QQ(pi)_{v}: QQ(pi): v\vert p place of QQ(\pi)], these are stored as elements of QQ.
Primitive models: 
"""

######################################################################################################

#for the make_label function
from sage.databases.cremona import cremona_letter_code
from sage.databases.cremona import class_to_int
import json, os, re
from collections import defaultdict

load("prescribed_roots.sage")
#this command should be replaced in the big list
#polyx =  x^4-x^3+3*x^2-9*x+81

#create p-adic and symbolic versions
#coeffs = poly.coefficients(sparse=False)
#polyt = polyx(t) #p-adic
#polyz = 0 #symbolic
#for i in range(2*g+1):
#    polyz = polyz + coeffs[i]*z^i

######################################################################################################

def newton_and_prank(p,r,poly_in_t):
    """
    before calling this function, first do:
    F = Qp(p)
    polyRingF.<t> = PolynomialRing(F)

    INPUT:
    - ``p`` -- a prime
    - ``r`` -- a positive integer, the abelian variety is defined over F_q for q = p^r
    - ``poly_in_t`` -- the characteristic polynomial whose Newton polygon and p-rank will be computed. This polynomial must be an element of Qp<t>

    OUTPUT:
     slopes -- the slopes of the Newton polygon
     p-rank -- the p-rank of the isogeny class of abelian varieties (the number of slopes equal to 0)

    This also works for the characteristic polynomial of a non-simple isogeny class.
    """
    d = poly_in_t.degree()
    mynp=poly_in_t.newton_polygon()
    slopes = []
    for i in range(d):
        rise = (-mynp(i+1) + mynp(i))/r
        slopes.append(rise)
    p_rank = slopes.count(0)
    return slopes,p_rank


def angles(poly_in_z):
    """
    INPUT:
    - ``poly_in_z`` -- a polynomial whose roots can be coerced to CC

    OUTPUT:
    a list whose elements are the arguments (angles) of the roots of the polynomial that are in the upper half plane, divided by pi, with multiplicity, coerced into RR

    This also works for the characteristic polynomial of a non-simple isogeny class.
    """
    roots = poly_in_z.roots(CC)
    return sum([[RR(root.arg()/pi)]*e for (root, e) in roots if root.imag() >= 0],[])


#def make_label(g,q,poly_in_x):
#    """
#    Needs: poly.<x> = PolynomialRing(ZZ)
#
#    we are going to replace the a_k label with our new labels
#        l_k = a_k - c_k/((-1)^k k) + q^k 2g/k/
#    What are these crazy numbers?
#    We are using Newton's identifies:
#        ka_k = \sum_{i=0}^k (-1)^{i-1} a_{k-1} s_i
#    we are which that a_k in an interval around some c_k of size the Lang-Weil bound (LW/k = q^{k/2
#    2g/k ) on the coefficients (also the trivial bound on the power sums s_k)
#        c_k = sum_{i=0}^{k-1} (-1)^{k-1} a_{k-i}s_i.
#    We then take all the integers in the interval |x - c_k| < LW and relabel them with element
#    [0,2*LW].
#    This is done by shifting a_k - c_k by LW/k.
#    """
#    a=poly_in_x.coefficients(sparse=False)
#    s=[2*g]+[0 for i in range(2*g)]
#    c =[0 for i in range(2*g)]
#    #computes the power sums
#    for i in range(1,2*g):
#        cilist = [ (-1)^(j+i)*a[i-j]*s[j] for j in range(1,i)]
#        c[i] = sum( cilist )
#        s[i] = ((-1)^(i)*i*a[i]-c[i])/a[0]
#    #computes the new labels
#    #TEST ME (in our test case we get 12,22)
#    l = [0 for i in range(0,g+1)]
#    for i in range(1,g+1):
#        l[i] = ceil(a[i] - (-1)^i*c[i]/i + q^(i/2+g)*(2*g)/i)
#    label = [l[i] for i in range(1,g+1)]
#    return a,s,c,label


def abelian_counts(g,p,r,L):
    """
    INPUT:
    - ``g`` -- the dimension of the abelian variety
    - ``p`` -- a prime
    - ``r`` -- a positive integer, the abelian variety is defined over F_q for q = p^r
    - ``L`` -- the L-polynomial of the isogeny class of abelian varieties

    OUPUT:
    for prec = max(g,10), a list containing the number of points of the abelian variety defined over F_q^i, for i = 1 to prec

    This also works for the characteristic polynomial of a non-simple isogeny class.
    """
    prec = max([g,10])
    x = L.parent().gen()
    return [L.resultant(x^i-1) for i in range(1,prec+1)]

def curve_counts(g,q,L):
    """
    INPUT:
    - ``g`` -- the dimension of the abelian variety
    - ``q`` -- the abelian variety is defined over F_q
    - ``L`` -- the L-polynomial of the isogeny class of abelian varieties

    OUTPUT:
    for prec = max(g,10), a list containing the number of points of the curve whose jacobian this abelian variety could be that are defined over F_q^i, for i = 1 to prec    
    """
    prec = max([g,10])
    S = PowerSeriesRing(QQ, 'x', prec+2)
    x = S.gen()
    f = S(L)/((1-x)*(1-q*x))
    return f.log().derivative().coefficients()[:prec]

def alternating(pol, m):
    """
    This appears to take forever but there is a precomputed version elsewhere.
    """
    d = pol.degree()
    pl = pol.list()
    e = SymmetricFunctions(QQ).e()
    dm = binomial(d, m)
    l = [(-1)^i*e[i](e[m]).restrict_parts(d) for i in range(dm+1)]
    P = pol.parent()
    R = P.base_ring()
    ans = []
    for i in range(dm,-1,-1):
        s = R.zero()
        u = tuple(l[i])
        for j, c in u:
            s += R(c) * prod(pl[d-k] for k in j)
        ans.append(s)
    return P(ans)

def find_invs_and_slopes(p,r,P):
    #We only want to run this one at a time.
    poly = P.change_ring(QQ)
    K.<a> = NumberField(poly)
    l = K.primes_above(p)
    invs = []
    slopes = []
    for v in l:
        vslope = a.valuation(v)/K(p^r).valuation(v)
        slopes.append(vslope)
        vdeg = v.residue_class_degree()*v.ramification_index()
        invs.append(vslope*vdeg)
    return invs,slopes

def make_label(g,q,Lpoly):
    #this works for one and just write it on each factors.
    label = '%s.%s.' % (g,q)
    for i in range(1,g+1):
        if i > 1: label += '_'
        c = Lpoly[i]
        if sign(c) == -1:
            label += 'a' + cremona_letter_code((-1)*c)
        else:
            label += cremona_letter_code(c)
    return label
    
def angle_rank(u,p):
    """
    There are two methods for computing this.
    The first method is to use S-units in sage where S = primes in Q(pi) dividing p.
    The second method is to use lindep in pari.
    """
    
    """
    K.<a> = u.splitting_field()
    l = [p] + [i[0] for i in u.roots(K)]
    S = K.primes_above(p)
    UGS = UnitGroup(K, S = tuple(S), proof=False)
    ## Even with proof=False, it is guaranteed to obtain independent S-units; just maybe not the fully saturated group.
    d = K.number_of_roots_of_unity()
    gs = [K(i) for i in UGS.gens()]
    l2 = [UGS(i^d).exponents() for i in l] #For x = a^1b^2c^3 exponents are (1,2,3)
    for i in range(len(l)):
        assert(l[i]^d == prod(gs[j]^l2[i][j] for j in range(len(l2[i]))))
    M = Matrix(l2)
    return M.rank()-1
    """

def quote_me(word):
    """
    INPUT:
    - ``word`` -- anything

    OUTPUT:
    a string containing the word with " around it
    """
    return '"'+ str(word) + '"'

oldmatcher = re.compile(r"weil-(\d+)-(\d+)\.txt")
gmatcher = re.compile(r"weil-simple-g(\d+)-q(\d+)\.txt")
allmatcher = re.compile(r"weil-all-g(\d+)-q(\d+)\.txt")
def load_previous_polys(q = None, g = None, rootdir=None, all = False):
#needs the fields to have the proper quotations/other Json formatting.
    if rootdir is None:
        rootdir = os.path.abspath(os.curdir)
    if all:
        matcher = allmatcher
    else:
        matcher = gmatcher
    D = defaultdict(list)
    R = PolynomialRing(QQ,'x')
    def update_dict(D, filename):
        with open(filename) as F:
            for line in F.readlines():
                data = json.loads(line)
                label, g, q, polynomial = data[:4]
                D[g,q].append((label, R(polynomial)))
    if q is not None and g is not None:
        filename = "weil-simple-g%s-q%s.txt"%(g, q)
        update_dict(D, filename)
    else:
        for filename in os.listdir(rootdir):
            match = matcher.match(filename)
            if match:
                gf, qf = map(int,match.groups())
                if q is not None and qf != q:
                    continue
                if g is not None and gf != g:
                    continue
                update_dict(D, os.path.join(rootdir, filename))
    return D
