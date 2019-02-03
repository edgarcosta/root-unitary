#*****************************************************************************
#       Copyright (C) 2018 Kiran S. Kedlaya <kskedl@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#                  http://www.gnu.org/licenses/
#*****************************************************************************

#encoding=utf8
#distutils: language = c
#distutils: libraries = gomp
#distutils: sources = power_sums.c
#distutils: include_dirs = /home/kedlaya/sage/local/include/flint .
#distutils: extra_compile_args = -fopenmp

## TODO: remove hard-coding of include directory

r"""
Iterator for Weil polynomials.

For `q` a prime power, a `q`-Weil polynomial is a monic polynomial with integer
coefficients whose complex roots all have absolute value `sqrt(q)`. The class
WeilPolynomials provides an iterator over a space of polynomials of this type;
it is possible to relax the monic condition by specifying one (or more) leading
coefficients. One may also impose certain congruence conditions; this can be
used to limit the Newton polygons of the resulting polynomials, or to lift
a polynomial specified by a congruence to a Weil polynomial.

EXAMPLES::

<Lots and lots of examples>

AUTHOR:
  -- Kiran S. Kedlaya (2007-05-28): initial version
  -- (2015-08-29): switch from NTL to FLINT
  -- (2017-10-03): consolidate Sage layer into .pyx file
                   define WeilPolynomials iterator
                   reverse convention for polynomials
                   pass multiprecision integers to/from C
  -- (2019-02-02): update for Python3
                   improve parallel mode
"""

cimport cython
from cython.parallel import prange
from libc.stdlib cimport malloc, free

from time import time as clock
from sage.rings.rational_field import QQ
from sage.rings.polynomial.polynomial_ring_constructor import PolynomialRing
from sage.functions.generalized import sgn

from sage.rings.integer cimport Integer
from sage.libs.gmp.types cimport mpz_t
from sage.libs.gmp.mpz cimport mpz_set
from sage.libs.flint.fmpz cimport *
from sage.libs.flint.fmpz_vec cimport *
from cysignals.signals cimport sig_on, sig_off

cdef extern from "power_sums.h":
    ctypedef struct ps_static_data_t:
        pass

    ctypedef struct ps_dynamic_data_t:
        int flag        # State of the iterator (0 = inactive, 1 = running,
                        #                        2 = found a solution, -1 = too many nodes)
        long node_count # Number of terminal nodes encountered
        fmpz *sympol    # Return value (a polynomial)

    ps_static_data_t *ps_static_init(int d, fmpz_t q, int coeffsign, fmpz_t lead,
    		     		     int cofactor, fmpz *modlist, long node_limit,
                                     int force_squarefree)
    ps_dynamic_data_t *ps_dynamic_init(int d, fmpz_t q, fmpz *coefflist)
    void *ps_dynamic_split(ps_dynamic_data_t *dy_data, ps_dynamic_data_t *dy_data2) nogil
    void ps_static_clear(ps_static_data_t *st_data)
    void ps_dynamic_clear(ps_dynamic_data_t *dy_data)
    void next_pol(ps_static_data_t *st_data, ps_dynamic_data_t *dy_data, int max_steps) nogil

# Data structure to manage parallel depth-first search.
cdef class dfs_manager:
    cdef public long count
    cdef int d
    cdef int num_processes
    cdef long node_limit
    cdef ps_static_data_t *ps_st_data
    cdef ps_dynamic_data_t **dy_data_buf

    def __cinit__(self, int d, q, coefflist, modlist, int sign, int cofactor,
                        long node_limit, int parallel, int force_squarefree):
        cdef fmpz_t temp_lead
        cdef fmpz_t temp_q
        cdef fmpz *temp_array
        cdef int i = 509 if parallel else 1

        self.count = 0
        self.d = d
        self.dy_data_buf = <ps_dynamic_data_t **>malloc(i*cython.sizeof(cython.pointer(ps_dynamic_data_t)))
        self.num_processes = i
        self.node_limit = node_limit
        fmpz_init(temp_lead)
        fmpz_set_mpz(temp_lead, Integer(coefflist[-1]).value)
        fmpz_init(temp_q)
        fmpz_set_mpz(temp_q, Integer(q).value)
        temp_array = _fmpz_vec_init(d+1)
        for i in range(d+1):
            fmpz_set_mpz(temp_array+i, Integer(modlist[i]).value)
        self.ps_st_data = ps_static_init(d, temp_q, sign, temp_lead, cofactor,
                                         temp_array, node_limit, force_squarefree)

        # Initialize processes, but assign work to only one process.
        # Other processes will get initialized later via work-stealing.
        for i in range(d+1):
            fmpz_set_mpz(temp_array+i, Integer(coefflist[i]).value)
        self.dy_data_buf[0] = ps_dynamic_init(d, temp_q, temp_array)
        for i in range(1, self.num_processes):
            self.dy_data_buf[i] = ps_dynamic_init(d, temp_q, NULL)

        fmpz_clear(temp_lead)
        fmpz_clear(temp_q)
        _fmpz_vec_clear(temp_array, d+1)

    def __init__(self, d, q, coefflist, modlist, sign, cofactor,
                        node_limit, parallel, force_squarefree):
        pass

    def __dealloc__(self):
        ps_static_clear(self.ps_st_data)
        self.ps_st_data = NULL
        if self.dy_data_buf != NULL:
            for i in range(self.num_processes):
                ps_dynamic_clear(self.dy_data_buf[i])
            free(self.dy_data_buf)
            self.dy_data_buf = NULL

    cpdef object advance_exhaust(self):
        """
        Advance the tree exhaustion.
        """
        cdef int i, j, k, d = self.d, t=1, np = self.num_processes, max_steps=1000
        cdef long ans_count = 100*np
        cdef mpz_t z
        cdef Integer temp
        ans = []

        k=1
        time1 = 0
        time2 = 0
        while (t and len(ans) < ans_count):
            t = 0
            time1 -= clock()
            if np == 1: # Serial mode
                next_pol(self.ps_st_data, self.dy_data_buf[0], max_steps)
                t = self.dy_data_buf[0].flag
                if not t: 
                    self.count += self.dy_data_buf[0].node_count
                    self.dy_data_buf[0].node_count = 0
            else: # Parallel mode
                k = (k<<1) %np
                with nogil:
                    sig_on()
                    for i in prange(np, schedule='dynamic'):
                        next_pol(self.ps_st_data, self.dy_data_buf[i], max_steps)
                    for i in prange(np, schedule='static'):
                        if self.dy_data_buf[i].flag>0: t += 1
                        if not self.dy_data_buf[i].flag: # Steal work
                            self.count += self.dy_data_buf[i].node_count
                            self.dy_data_buf[i].node_count = 0
                            j = (i-k) % np
                            ps_dynamic_split(self.dy_data_buf[j], self.dy_data_buf[i])
                    sig_off()
            time1 += clock()
            time2 -= clock()
            for i in range(np):
                if self.dy_data_buf[i].flag == -1:
                    raise RuntimeError("Node limit ({0:%d}) exceeded".format(self.node_limit))
                if self.dy_data_buf[i].flag == 2: # Extract a solution
                    l = []
                    # Convert a vector of fmpz's into mpz's, then Integers.
                    for j in range(2*d+3):
                        flint_mpz_init_set_readonly(z, &self.dy_data_buf[i].sympol[j])
                        temp = Integer()
                        mpz_set(temp.value, z)
                        l.append(temp)
                        flint_mpz_clear_readonly(z)
                    ans.append(l)
            time2 += clock()
        print(time1, time2)
        return ans

class WeilPolynomials_iter():
    r"""
    Iterator created by WeilPolynomials.

    EXAMPLES::
        sage: w = WeilPolynomials(10,1,sign=1,lead=[3,1,1])
        sage: it = iter(w)
        sage: next(it)
        3*x^10 + x^9 + x^8 - x^7 + 4*x^6 + 2*x^5 + 4*x^4 - x^3 + x^2 + x + 3
        sage: w = WeilPolynomials(10,1,sign=-1,lead=[3,1,1])
        sage: it = iter(w)
        sage: next(it)
        3*x^10 + x^9 + x^8 + x^7 + 3*x^6 - 3*x^4 - x^3 - x^2 - x - 3
    """
    def __init__(self, d, q, sign, lead, node_limit, parallel, squarefree):
        self.pol = PolynomialRing(QQ, name='x')
        x = self.pol.gen()
        d = Integer(d)
        if sign != 1 and sign != -1:
            return ValueError("Invalid sign")
        if not q.is_integer() or q<=0:
            return ValueError("q must be a positive integer")
        if d%2==0:
            if sign==1:
                d2 = d//2
                num_cofactor = 0
            else:
                d2 = d//2 - 1
                num_cofactor = 3
        else:
            if not q.is_square():
                return ValueError("Degree must be even if q is not a square")
            d2 = d//2
            if sign==1: num_cofactor = 1
            else: num_cofactor = 2
        try:
            leadlist = list(lead)
        except TypeError:
            leadlist = [(lead, 0)]
        coefflist = []
        modlist = []
        for i in leadlist:
            try:
                (j,k) = i
            except TypeError:
                (j,k) = (i,0)
            j = Integer(j)
            k = Integer(k)
            if len(modlist) == 0 and k != 0:
                raise ValueError("Leading coefficient must be specified exactly")
            if len(modlist) > 0 and ((k != 0 and modlist[-1]%k != 0) or (k == 0 and modlist[-1] != 0)):
                raise ValueError("Invalid moduli")
            coefflist.append(j)
            modlist.append(k)
        # Remove cofactor from initial coefficients
        if num_cofactor == 1: #cofactor x + sqrt(q)
            for i in range(1, len(coefflist)):
                coefflist[i] -= coefflist[i-1]*q.sqrt()
        elif num_cofactor == 2: #cofactor x + sqrt(q)
            for i in range(1, len(coefflist)):
                coefflist[i] += coefflist[i-1]*q.sqrt()
        elif num_cofactor == 3: #cofactor x^2 - q
            for i in range(2, len(coefflist)):
                coefflist[i] += coefflist[i-2]*q
        # Asymmetrize initial coefficients
        for i in range(len(coefflist)):
            for j in range(1, (len(coefflist)-i+1)//2):
                coefflist[i+2*j] -= (d2-i).binomial(j)*coefflist[i]
        for _ in range(d2+1-len(coefflist)):
            coefflist.append(0)
            modlist.append(1)
        coeffsign = sgn(coefflist[0])
        coefflist = [x*coeffsign for x in reversed(coefflist)]
        if node_limit is None:
            node_limit = -1
        force_squarefree = Integer(squarefree)
        self.process = dfs_manager(d2, q, coefflist, modlist, coeffsign,
                                   num_cofactor, node_limit, parallel,
                                   force_squarefree)
        self.q = q
        self.squarefree = squarefree
        self.ans = []

    def __iter__(self):
        return(self)

    def __next__(self):
        if self.process is None:
            raise StopIteration
        if len(self.ans) == 0:
            self.ans = self.process.advance_exhaust()
            if len(self.ans) == 0:
                self.count = self.process.count
                self.process = None
                raise StopIteration
        return self.pol(self.ans.pop())

    def next(self):
        return self.__next__()

    def node_count(self):
        r"""
        Return the number of terminal nodes found in the tree, excluding 
        actual solutions.
        """
        if self.process is None:
            return self.count
        return self.process.count

class WeilPolynomials():
    r"""
    Iterable for Weil polynomials, i.e., integer polynomials with all complex 
    roots having a particular absolute value.

    If parallel is True, then the order of values is not specified.

    EXAMPLES:

    By Kronecker's theorem, a monic integer polynomial has all roots of absolute
    value 1 if and only if it is a product of cyclotomic polynomials. For such a
    product to have positive sign of the functional equation, the factors `x-1`
    and `x+1` must each occur with even multiplicity. This code confirms 
    Kronecker's theorem for polynomials of degree 6::
        sage: P.<x> = PolynomialRing(ZZ)
        sage: d = 6
        sage: ans1 = list(WeilPolynomials(d, 1, 1))
        sage: ans1.sort()
        sage: l = [(x-1)^2, (x+1)^2] + [cyclotomic_polynomial(n,x) 
        ....:     for n in range(3, 2*d*d) if euler_phi(n) <= d]
        sage: w = WeightedIntegerVectors(d, [i.degree() for i in l])
        sage: ans2 = [prod(l[i]^v[i] for i in range(len(l))) for v in w]
        sage: ans2.sort()
        sage: print(ans1 == ans2)
        True

    Generating Weil polynomials with prescribed initial coefficients::
        sage: w = WeilPolynomials(10,1,sign=1,lead=[3,1,1])
        sage: it = iter(w)
        sage: next(it)
        3*x^10 + x^9 + x^8 - x^7 + 4*x^6 + 2*x^5 + 4*x^4 - x^3 + x^2 + x + 3
        sage: w = WeilPolynomials(10,1,sign=-1,lead=[3,1,1])
        sage: it = iter(w)
        sage: next(it)
        3*x^10 + x^9 + x^8 + x^7 + 3*x^6 - 3*x^4 - x^3 - x^2 - x - 3
    """
    def __init__(self, d, q, sign=1, lead=1, node_limit=None, parallel=False, squarefree=False):
        self.data = (d,q,sign,lead,node_limit,parallel,squarefree)

    def __iter__(self):
        w = WeilPolynomials_iter(*self.data)
        self.w = w
        return w

    def node_count(self):
        r"""
        Return the number of terminal nodes found in the tree, excluding 
        actual solutions.
        """
        return self.w.node_count()
    
