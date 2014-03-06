*dk multigrid
	subroutine multigrid(u,f,nj,map,urot,ibc0,izerou,ireport)
!	This routine solves the elliptic equation  A*u = f  on an
!	icosahedral discretization of a spherical shell by means
!	of a spherical version of the multigrid algorithm FAPIN.
 
	include 'size.h'
	include 'pcom.h'
	include 'para.h'

	integer, parameter:: nxm=4000+(nt+1)**2*41

	common /mgwk/ w((nt+1)**2*nd*(nr+1),3), r(nv), z(nv)
	common /grid/ mxm(0:10), xm(nxm)
	common /radl/ rshl(nr+1), ird
	common /wght/ mrw(0:10), rw(nv*ndo/nd*7/5),
     &              mhw(0:10), hw(nv*ndo/nd*7/5)
	common /opwt/ wd, wm
	common /mgrd/ itlimit, convtol, itsolve
	common /nrms/ fnrm, rnrm, unrm, ekin
	common /clck/ itmng, sec(50)
	common /mesh/ xn

	integer ibc0, izerou, ireport
	integer map(0:nt,nt+1,nd)

	real u(*), f(*)
	integer mz(0:10), m(0:10), n(0:10)

	real xn((nt+1)**2*nd,3)
	real urot(3,pl_size)

	if(itmng==1) call mytime(tin)
 
	lvf = 1.45*log(real(mt))
	lvr = 1.45*log(real(nr))
	lvg = 1.45*log(real(mt/nt))
 
	mz(0) = 1
	do lv=0,lvf
		kr       = 2**max(0, lv - lvf + lvr)
		kt       = 2**max(0, lv - lvg)
		m(lv)    = kr
		n(lv)    = kt
		mz(lv+1) = mz(lv) + (kt+1)**2*nd*nj*(kr+1)
	enddo
 
!	impose boundary conditions on f (given by 'ibc0')
!	why on f???
	call vbcrdl(f,xm(mxm(lvf)),ibc0,nd,nr,nt)

!	Compute the rms norm of the right hand side field f.
	call norm3s(f,fnrm,nj,nd,nr,nt)

      if(ireport==1) call study3s('F     ',f,fnrm,nj,lvf,nd,nr,nt,0)
     
	rnrm=convtol*fnrm
	itsolve=0
	do while(itsolve<itlimit.and.rnrm>=convtol*fnrm)

		itsolve=itsolve+1
		lvproc = lvg
		mproc  = 2**(2*lvproc)
		
		if(mynum==0.and.ireport==1) write(222,10) itsolve
 10   format(20x,'FAPIN ITERATION ',i2)
 
!		Compute the residual r = f - A*u and its rms norm.  Use array w
!		to store r at the finest grid level.
		call scopy((nt+1)**2*nd*nj*(nr+1), f, 1, w, 1)

		! w and u are used and changed (w=w-Au) 
		if(izerou.ne.1.or.itsolve>1)
     &		call axu3s(w,u,nj,lvf,nd,nr,nt,map,urot,ibc0)
 
		call nospin(w)
 
      	call norm3s(w,rnrm,nj,nd,nr,nt)
      	
		if(ireport==1) call study3s('RESID ',w,rnrm,nj,lvf,nd,nr,nt,0)
 
!		Down project the residual r to level zero. 
		call proj3s(w,r(mz(lvf-1)),r(mz(lvf)),rw(mrw(lvf-1)),
     &            hw(mhw(lvf-1)),nj,nr,nt)
     
!		if(ireport==1) call study3s('PROJ  ',
!     &		r(mz(lvf-1)),rnorm,nj,lvf-1,nd,m(lvf-1),n(lvf-1),1)

		do lv=lvf-1,1,-1

		if(lv>lvg) then
				
			call proj3s(r(mz(lv)),r(mz(lv-1)),r(mz(lvf)),rw(mrw(lv-1)),
     &                  hw(mhw(lv-1)),nj,m(lv),n(lv))
     
!			if(ireport==1) call study3s('PROJ  ',
!     &         r(mz(lv-1)),rnorm,nj,lv-1,nd,m(lv-1),n(lv)/2,1)
		
		else
 
			if(mynum<2**(2*lv)*10/nd)
     & 	        call pcom1to4(w,r(mz(lv)),lv,m(lv),3)
 
			lvproc = lv - 1
			mproc  = 2**(2*lvproc)
 
			if(mynum<mproc*10/nd)
     &			call proj3s(w,r(mz(lv-1)),r(mz(lvf)),rw(mrw(lv-1)),
     &                     hw(mhw(lv-1)),nj,m(lv),2)
     
!			if(ireport==1) call study3s('PROJ  ',
!     &			r(mz(lv-1)),rnorm,nj,lv-1,nd,m(lv-1),1,1)

		endif
		enddo
 
!	Apply the pseudo-inverse to the residual to obtain the
!	correction field z at the coarsest (lv = 0) grid level.
		if(nd.ne.10.and.mynum<mproc*10/nd) then
 
			call pcomtozero(w,r,6)
			if(mynum==0) call pseu3s(w(1,2),w,3)
			call pcomfromzero(w(1,2),z,6)
 
		else if(nd==10.and.mynum==0) then
 
			call pseu3s(z,r,3)
 
		endif
 
!	Do the upward part of the V-cycle except for the last
!	interpolation step and correction at the finest level.
		do lv=1,lvf-1
 
!	Interpolate the correction field z from grid level lv-1
!	to grid level lv.
			msgnum = 1
 
			if(lv<=lvg) then
 
				if(mynum<mproc*10/nd)
     &         call inter3s(w,z(mz(lv-1)),rw(mrw(lv-1)),
     &                      hw(mhw(lv-1)),nj,m(lv),2)
 
				if(mynum<2**(2*lv)*10/nd)
     &         call pcom4to1(z(mz(lv)),w,lv,m(lv),3)
     
   		    call MPI_BARRIER(MPI_COMM_WORLD,ierror)
 
				lvproc = lv
				mproc  = 2**(2*lvproc)
				
!				if(ireport==1) call study3s('INTERP',
!     &         z(mz(lv)),znorm,nj,lv,nd,m(lv),1,1)
 
			else
 
				call inter3s(z(mz(lv)),z(mz(lv-1)),rw(mrw(lv-1)),
     &                   hw(mhw(lv-1)),nj,m(lv),n(lv))
     
!				if(ireport==1) call study3s('INTERP',
!     &         z(mz(lv)),znorm,nj,lv,nd,m(lv),n(lv),1)
			endif
 
!	The interpolated correction z at level lv can be improved.
!	To obtain this improvement, replace r by r = r - A*z and
!	then apply the approximate inverse with this new r to
!	compute a more accurate z.
			call apinv3s(z(mz(lv)),r(mz(lv)),nj,lv,nd,m(lv),
     &		n(lv),map,urot,ibc0)

!			if(ireport==1) call study3s('APINV ',
!     &      z(mz(lv)),znorm,nj,lv,nd,m(lv),n(lv),1)

		enddo
 
!	After interpolating z to the finest level lv=lvf, add this
!	interpolation to u as a correction.  Then compute a new
!	residual r and apply the approximate inverse to this new
!	r to obtain the improved solution u.
		call inter3s(w,z(mz(lvf-1)),rw(mrw(lvf-1)),hw(mhw(lvf-1)),
     &             nj,nr,nt)
	
!		if(ireport==1) call study3s('INTERP',w,wnorm,nj,lvf,nd,nr,nt,1)
 
		do ii=1,(nt+1)**2*nd*nj*(nr+1)
			u(ii) = u(ii) + w(ii,1)
		enddo
 
		call apinv3s(u,f,nj,lvf,nd,nr,nt,map,urot,ibc0)
		
!		if(ireport==1) call study3s('APINV ',u,unorm,nj,lvf,nd,nr,nt,1)

	enddo
	
	if(ireport==1) call study3s('U     ',u,unorm,nj,lvf,nd,nr,nt,1)

	if(itmng==1) then
		call mytime(tout)
		sec(6) = sec(6) + tout - tin
	endif

	end subroutine


*dk axu3s
	subroutine axu3s(v,u,nj,lv,kd,kr,kt,map,urot,ibc0)
!	This routine is a driver routine for performing the
!	calculation  v = v - A*u , where A is the Laplacian
!	operator.
 
	include 'size.h'
	include 'pcom.h'
	include 'para.h'

	integer, parameter:: nxm=4000+(nt+1)**2*41
	integer, parameter:: nopr=(nt/2+1)**2*ndo*189*(nr/2+1)*7/5+8000

	real v(*), u(*)

	common /vis0/ vb(nt+1), vv((nt+1)**2*nd*(nr+1),2), ve(nt+1)
	common /grid/ mxm(0:10), xm(nxm)
	common /fopr/ opr(nopr), oprd(nv*ndo/nd*9), b(nv*ndo/nd*18*5/4),
     &              mopr(0:10), mb(0:10)
	common /radl/ rshl(nr+1), ird                                         
	common /clck/ itmng, sec(50)
	common /mesh/ xn

	integer ibc0
	integer map(0:nt,nt+1,nd)
	real xn((nt+1)**2*nd,3)
	real urot(3,pl_size)

	if(itmng==1) call mytime(tin)
 
	lvf = 1.45*log(real(mt))
	lvr = 1.45*log(real(kr))

!	impose boundary conditions on u
	call vbcrdl(u,xm(mxm(lv)),ibc0,kd,kr,kt)

!	if ibc0==6 and we're on the right level, we impose
!	the given plate velocities on the uppermost layer 
	if(ibc0==6.and.kt==nt) then
		call platevelreplace(u,urot,xn,map)
		call uscale(u,1,0)
	endif
 
	if(lv==lvf) then
		call oprxuf(v,u,oprd)
	else
		kdo = ndo
		if(lv==0) kdo = 10
		call oprxuc(v,u,opr(mopr(lv)),kdo,kd,kr,kt)
	endif

!	impose boundary conditions on v
	call vbcrdl(v,xm(mxm(lv)),ibc0,kd,kr,kt)
 
	if(itmng==1) then
		call mytime(tout)
		sec(10) = sec(10) + tout - tin
	endif

	end subroutine


*dk apinv3s
	subroutine apinv3s(u,r,nj,lv,kd,kr,kt,map,urot,ibc0)
!	This routine computes  u = u + C*r, where C represents an
!	algebraic approximate inverse of the Laplacian operator.
 
	include 'size.h'
	include 'pcom.h'
	include 'para.h'

	integer, parameter:: nxm=4000+(nt+1)**2*41
	integer, parameter:: nopr=(nt/2+1)**2*ndo*189*(nr/2+1)*7/5+8000
 
	real u(*), r(*)

	common /vis0/ vb(nt+1), vv((nt+1)**2*nd*(nr+1),2), ve(nt+1)
	common /grid/ mxm(0:10), xm(nxm)
	common /fopr/ opr(nopr), oprd(nv*ndo/nd*9), b(nv*ndo/nd*18*5/4),
     &              mopr(0:10), mb(0:10)
	common /mgwk/ w(nv,5)
	common /radl/ rshl(nr+1), ird
	common /mesh/ xn

	integer ibc0
	integer map(0:nt,nt+1,nd)
	real xn((nt+1)**2*nd,3)
	real urot(3,pl_size)

	lvr = 1.45*log(real(kr))

	call jacobi(u,r,w,b(mb(lv)),lv,kd,kr,kt,map,urot,ibc0)

	if(nj==3) then

		call vbcrdl(u,xm(mxm(lv)),ibc0,kd,kr,kt)
 
		if(ibc0==6.and.kt==nt) then
			call platevelreplace(u,urot,xn,map)
			call uscale(u,1,0)
		endif

	endif
 
	end subroutine


*dk inter3s
	subroutine inter3s(zf,zc,rw,hw,nj,nrf,ntf)
!	This routine performs a linear interpolation of the nodal
!	field zc defined on a coarse mesh to yield the field zf
!	defined on a mesh one dyadic level finer.
 
      include 'size.h'
      real zf(0:ntf,ntf+1,nd,nj,*), zc(0:ntf/2,ntf/2+1,nd,nj,*)
      real rw(2,0:ntf,ntf+1,ndo,*), hw(2:7,0:ntf/2,ntf/2+1,ndo,*)
      common /clck/ itmng, sec(50)
      if(itmng.eq.1) call mytime(tin)
 
      ntc  = ntf/2
      nrc  = max(1, nrf/2)
 
c...  Interpolate in lateral directions.
 
      do ir=1,nrc+1
         do id=1,nd
            jd = min(ndo, id)
            do i2=1,ntc
               do i1=1,ntc
                  zf(i1+i1  ,i2+i2-1,id,1,ir) = zc(i1  ,i2  ,id,1,ir)
                  zf(i1+i1  ,i2+i2  ,id,1,ir) = zc(i1  ,i2  ,id,1,ir)
     &                                        * hw(3,i1  ,i2  ,jd,ir)
     &                                        + zc(i1  ,i2+1,id,1,ir)
     &                                        * hw(6,i1  ,i2+1,jd,ir)
                  zf(i1+i1-1,i2+i2  ,id,1,ir) = zc(i1  ,i2  ,id,1,ir)
     &                                        * hw(4,i1  ,i2  ,jd,ir)
     &                                        + zc(i1-1,i2+1,id,1,ir)
     &                                        * hw(7,i1-1,i2+1,jd,ir)
                  zf(i1+i1-1,i2+i2-1,id,1,ir) = zc(i1  ,i2  ,id,1,ir)
     &                                        * hw(5,i1  ,i2  ,jd,ir)
     &                                        + zc(i1-1,i2  ,id,1,ir)
     &                                        * hw(2,i1-1,i2  ,jd,ir)
                  zf(i1+i1  ,i2+i2-1,id,2,ir) = zc(i1  ,i2  ,id,2,ir)
                  zf(i1+i1  ,i2+i2  ,id,2,ir) = zc(i1  ,i2  ,id,2,ir)
     &                                        * hw(3,i1  ,i2  ,jd,ir)
     &                                        + zc(i1  ,i2+1,id,2,ir)
     &                                        * hw(6,i1  ,i2+1,jd,ir)
                  zf(i1+i1-1,i2+i2  ,id,2,ir) = zc(i1  ,i2  ,id,2,ir)
     &                                        * hw(4,i1  ,i2  ,jd,ir)
     &                                        + zc(i1-1,i2+1,id,2,ir)
     &                                        * hw(7,i1-1,i2+1,jd,ir)
                  zf(i1+i1-1,i2+i2-1,id,2,ir) = zc(i1  ,i2  ,id,2,ir)
     &                                        * hw(5,i1  ,i2  ,jd,ir)
     &                                        + zc(i1-1,i2  ,id,2,ir)
     &                                        * hw(2,i1-1,i2  ,jd,ir)
                  zf(i1+i1  ,i2+i2-1,id,3,ir) = zc(i1  ,i2  ,id,3,ir)
                  zf(i1+i1  ,i2+i2  ,id,3,ir) = zc(i1  ,i2  ,id,3,ir)
     &                                        * hw(3,i1  ,i2  ,jd,ir)
     &                                        + zc(i1  ,i2+1,id,3,ir)
     &                                        * hw(6,i1  ,i2+1,jd,ir)
                  zf(i1+i1-1,i2+i2  ,id,3,ir) = zc(i1  ,i2  ,id,3,ir)
     &                                        * hw(4,i1  ,i2  ,jd,ir)
     &                                        + zc(i1-1,i2+1,id,3,ir)
     &                                        * hw(7,i1-1,i2+1,jd,ir)
                  zf(i1+i1-1,i2+i2-1,id,3,ir) = zc(i1  ,i2  ,id,3,ir)
     &                                        * hw(5,i1  ,i2  ,jd,ir)
     &                                        + zc(i1-1,i2  ,id,3,ir)
     &                                        * hw(2,i1-1,i2  ,jd,ir)
               end do
            end do
 
c...        Treat upper right edge of diamond.
 
            do i2=1,ntc
               zf(0,i2+i2-1,id,1,ir) = zc(0,i2  ,id,1,ir)
               zf(0,i2+i2  ,id,1,ir) = zc(0,i2  ,id,1,ir)
     &                               * hw(3,0,i2  ,jd,ir)
     &                               + zc(0,i2+1,id,1,ir)
     &                               * hw(6,0,i2+1,jd,ir)
               zf(0,i2+i2-1,id,2,ir) = zc(0,i2  ,id,2,ir)
               zf(0,i2+i2  ,id,2,ir) = zc(0,i2  ,id,2,ir)
     &                               * hw(3,0,i2  ,jd,ir)
     &                               + zc(0,i2+1,id,2,ir)
     &                               * hw(6,0,i2+1,jd,ir)
               zf(0,i2+i2-1,id,3,ir) = zc(0,i2  ,id,3,ir)
               zf(0,i2+i2  ,id,3,ir) = zc(0,i2  ,id,3,ir)
     &                               * hw(3,0,i2  ,jd,ir)
     &                               + zc(0,i2+1,id,3,ir)
     &                               * hw(6,0,i2+1,jd,ir)
            end do
 
c...        Treat lower right edge of diamond.
 
            do i1=1,ntc
               zf(i1+i1  ,ntf+1,id,1,ir) = zc(i1  ,ntc+1,id,1,ir)
               zf(i1+i1-1,ntf+1,id,1,ir) = zc(i1  ,ntc+1,id,1,ir)
     &                                   * hw(5,i1  ,ntc+1,jd,ir)
     &                                   + zc(i1-1,ntc+1,id,1,ir)
     &                                   * hw(2,i1-1,ntc+1,jd,ir)
               zf(i1+i1  ,ntf+1,id,2,ir) = zc(i1  ,ntc+1,id,2,ir)
               zf(i1+i1-1,ntf+1,id,2,ir) = zc(i1  ,ntc+1,id,2,ir)
     &                                   * hw(5,i1  ,ntc+1,jd,ir)
     &                                   + zc(i1-1,ntc+1,id,2,ir)
     &                                   * hw(2,i1-1,ntc+1,jd,ir)
               zf(i1+i1  ,ntf+1,id,3,ir) = zc(i1  ,ntc+1,id,3,ir)
               zf(i1+i1-1,ntf+1,id,3,ir) = zc(i1  ,ntc+1,id,3,ir)
     &                                   * hw(5,i1  ,ntc+1,jd,ir)
     &                                   + zc(i1-1,ntc+1,id,3,ir)
     &                                   * hw(2,i1-1,ntc+1,jd,ir)
            end do
 
c...        Treat right corner of diamond.
 
            zf(0,ntf+1,id,1,ir) = zc(0,ntc+1,id,1,ir)
            zf(0,ntf+1,id,2,ir) = zc(0,ntc+1,id,2,ir)
            zf(0,ntf+1,id,3,ir) = zc(0,ntc+1,id,3,ir)
 
         end do
      end do
 
      if(nrf. ge. 2) then
 
c...     Interpolate in radial direction.
 
         do ir=nrc,1,-1
            do id=1,nd
               jd = min(ndo, id)
               do i2=1,ntf+1
                  do i1=0,ntf
                     zf(i1,i2,id,1,ir+ir+1) = zf(i1,i2,id,1,ir+1)
                     zf(i1,i2,id,1,ir+ir  ) = zf(i1,i2,id,1,ir+1)
     &                                      * rw(1,i1,i2,jd,ir+1)
     &                                      + zf(i1,i2,id,1,ir)
     &                                      * rw(2,i1,i2,jd,ir)
                     zf(i1,i2,id,2,ir+ir+1) = zf(i1,i2,id,2,ir+1)
                     zf(i1,i2,id,2,ir+ir  ) = zf(i1,i2,id,2,ir+1)
     &                                      * rw(1,i1,i2,jd,ir+1)
     &                                      + zf(i1,i2,id,2,ir)
     &                                      * rw(2,i1,i2,jd,ir)
                     zf(i1,i2,id,3,ir+ir+1) = zf(i1,i2,id,3,ir+1)
                     zf(i1,i2,id,3,ir+ir  ) = zf(i1,i2,id,3,ir+1)
     &                                      * rw(1,i1,i2,jd,ir+1)
     &                                      + zf(i1,i2,id,3,ir)
     &                                      * rw(2,i1,i2,jd,ir)
                  end do
               end do
            end do
         end do
 
      endif
 
      if(itmng.eq.1) call mytime(tout)
      if(itmng.eq.1) sec(7) = sec(7) + tout - tin

	end subroutine


*dk jacobi
	subroutine jacobi(z,r,y,b,lv,kd,kr,kt,map,urot,ibc0)
!	This routine applies iterative line Jacobi smoothing in the
!	radial direction.

	include 'size.h'
	include 'pcom.h'
	include 'para.h'

	common /call/ ncall
	common /clck/ itmng, sec(50)

	real z(0:kt,kt+1,kd,3,kr+1)
	real r(0:kt,kt+1,kd,3,kr+1)
	real y(0:kt,kt+1,kd,3,kr+1)
	real b(6,3*(kr+1),0:kt,kt+1,ndo)
	real x(3*(nr+1))

	integer ibc0
	integer map(0:nt,nt+1,nd)
	real urot(3,pl_size)

	twothird = 2./3.
      n  = 3*(kr + 1)
 
      mu = 1
      if(ncall .le. 10) mu = 4
      if(lv    .le.  3) mu = 3
 
      do it=1,mu
 
         call scopy((kt+1)**2*kd*3*(kr+1),r,1,y,1)
 
         call axu3s(y,z,3,lv,kd,kr,kt,map,urot,ibc0)
 
         if(itmng.eq.1) call mytime(tin)
 
         call nuledge(z,kd,kr,kt,3)
 
         do id=1,kd
 
            jd = min(ndo, id)
 
            do i2=1,kt
 
               i1b = 1
               if(mod(mynum, mproc).eq.0 .and. mod(id,5).eq.1
     &                                   .and. i2.eq.1) i1b = 0
 
               do i1=i1b,kt
 
                  do ir=1,kr+1
                     x(3*ir-2) = y(i1,i2,id,1,ir)*twothird
                     x(3*ir-1) = y(i1,i2,id,2,ir)*twothird
                     x(3*ir  ) = y(i1,i2,id,3,ir)*twothird
                  end do
 
c                 First solve trans(r)*y = b.
 
                  do k=1,min(5, n)
                     do i=1,k-1
                        x(k) = x(k) - b(6-k+i,k,i1,i2,jd)*x(i)
                     end do
                     x(k) = x(k)*b(6,k,i1,i2,jd)
                  end do
 
                  do k=6,n
                     x(k) = (((((x(k) - b(1,k,i1,i2,jd)*x(k-5))
     &                                - b(2,k,i1,i2,jd)*x(k-4))
     &                                - b(3,k,i1,i2,jd)*x(k-3))
     &                                - b(4,k,i1,i2,jd)*x(k-2))
     &                                - b(5,k,i1,i2,jd)*x(k-1))
     &                                * b(6,k,i1,i2,jd)
                  end do
 
c                 Now solve  r*x = y.
 
                  do k=n,6,-1
                     x(k)   =          x(k)*b(6,k,i1,i2,jd)
                     x(k-5) = x(k-5) - x(k)*b(1,k,i1,i2,jd)
                     x(k-4) = x(k-4) - x(k)*b(2,k,i1,i2,jd)
                     x(k-3) = x(k-3) - x(k)*b(3,k,i1,i2,jd)
                     x(k-2) = x(k-2) - x(k)*b(4,k,i1,i2,jd)
                     x(k-1) = x(k-1) - x(k)*b(5,k,i1,i2,jd)
                  end do
 
                  do k=min(5, n),1,-1
                     x(k) = x(k)*b(6,k,i1,i2,jd)
                     do i=1,k-1
                        x(i) = x(i) - x(k)*b(6-k+i,k,i1,i2,jd)
                     end do
                  end do
 
                  do ir=1,kr+1
                     z(i1,i2,id,1,ir) = z(i1,i2,id,1,ir) - x(3*ir-2)
                     z(i1,i2,id,2,ir) = z(i1,i2,id,2,ir) - x(3*ir-1)
                     z(i1,i2,id,3,ir) = z(i1,i2,id,3,ir) - x(3*ir)
                  end do
 
               end do
 
            end do
 
         end do
 
         call comm3s(z,kr,kt,3)
 
         if(itmng.eq.1) call mytime(tout)
         if(itmng.eq.1) sec(9) = sec(9) + tout - tin
 
      end do

	end subroutine


*dk massmtrx
	subroutine massmtrx(v,u)
!	This routine computes  v = M*u,  where M represents
!	the mass matrix.
 
      include 'size.h'
      common /oper/ ra(3,8,nr+1), alp(7,0:nt,nt+1,2),
     &              atn(4,7,(nt+1)**2,9)
      real v(0:nt,nt+1,nd,nr+1), u(0:nt,nt+1,nd,nr+1), w(0:nt,nr+1)
 
      do id=1,nd
         do i2=1,nt+1
 
            do ir=1,nr+1
               do i1=0,nt
                  w(i1,ir) = ((((((alp(1,i1,i2,2)*u(i1  ,i2  ,id,ir)
     &                           + alp(2,i1,i2,2)*u(i1+1,i2  ,id,ir))
     &                           + alp(3,i1,i2,2)*u(i1  ,i2+1,id,ir))
     &                           + alp(4,i1,i2,2)*u(i1-1,i2+1,id,ir))
     &                           + alp(5,i1,i2,2)*u(i1-1,i2  ,id,ir))
     &                           + alp(6,i1,i2,2)*u(i1  ,i2-1,id,ir))
     &                           + alp(7,i1,i2,2)*u(i1+1,i2-1,id,ir))
               end do
            end do
 
            do i1=0,nt
               v(i1,i2,id,1) = ra(2,7,1)*w(i1,1) + ra(3,7,1)*w(i1,2)
            end do
 
            do ir=2,nr
               do i1=0,nt
                  v(i1,i2,id,ir) = ((ra(1,7,ir)*w(i1,ir-1)
     &                             + ra(2,7,ir)*w(i1,ir))
     &                             + ra(3,7,ir)*w(i1,ir+1))
               end do
            end do
 
            do i1=0,nt
               v(i1,i2,id,nr+1) = ra(1,7,nr+1)*w(i1,nr)
     &                          + ra(2,7,nr+1)*w(i1,nr+1)
            end do
 
         end do
      end do
 
      call comm3s(v,nr,nt,1)

	end subroutine


*dk norm3s
	subroutine norm3s(r,rnorm,nj,nd,nr,nt)
	implicit none
!	This routine computes the l2 norm of r.

	include 'pcom.h'

	common /clck/ itmng, sec

	integer nj,ic,id,i1,i2
	integer nd,nr,nt,itmng
	real r(0:nt,nt+1,nd,nj*(nr+1))
	real rnorm, sum1, sec(50), tin, tout

	if(itmng==1) call mytime(tin)

	if(mynum<mproc*10/nd) then 

		sum1=0.0
 
		if(mynum==0.or.(mynum==mproc.and.nd<=5)) then
			do ic=1,nj*(nr+1)
				sum1 = sum1 + r(0,1,1,ic)**2
			enddo
		endif
 
		if(mynum==0.and.nd==10) then
			do ic=1,nj*(nr+1)
				sum1 = sum1 + r(0,1,6,ic)**2
			enddo
		endif
 
		do ic=1,nj*(nr+1)
			do id=1,nd
				do i2=1,nt
					do i1=1,nt
						sum1 = sum1 + r(i1,i2,id,ic)**2
					enddo
				enddo
			enddo
		enddo
 
		if(mproc*10/nd>1) call psum(sum1,1)
 
		rnorm = sqrt(sum1/((nt*nt*10*mproc+2)*(nr+1)))
 
		if(itmng==1) then
			call mytime(tout)
			sec(13) = sec(13) + tout - tin
		endif

	endif

	end subroutine

	
*dk nospin
	subroutine nospin(z)
 
!	This routine removes the rigid rotation from the vector field z
!	on the finest grid level.
 
      include 'size.h'
      include 'pcom.h'
      real z(0:nt,nt+1,nd,3,nr+1), s(6)
      common /mesh/ xn(0:nt,nt+1,nd,3)
 
      do ir=1,nr+1
 
         s(3) = 0.
         s(6) = 0.
 
         if(mynum.eq.0 .and. nd.eq.10) then
            s(1) =  2.
            s(2) =  2.
            s(4) =  z(0,1,1,2,ir) - z(0,1,6,2,ir)
            s(5) =  z(0,1,6,1,ir) - z(0,1,1,1,ir)
         elseif(mynum .eq. 0) then
            s(1) =  1.
            s(2) =  1.
            s(4) =  z(0,1,1,2,ir)
            s(5) = -z(0,1,1,1,ir)
         elseif(mynum.eq.mproc .and. nd.le.5) then
            s(1) =  1.
            s(2) =  1.
            s(4) = -z(0,1,1,2,ir)
            s(5) =  z(0,1,1,1,ir)
         else
            s(1) =  0.
            s(2) =  0.
            s(4) =  0.
            s(5) =  0.
         endif
 
         do id=1,nd
            do i2=1,nt
               do i1=1,nt
                  s(1) = s(1) + xn(i1,i2,id,3)**2
     &                        + xn(i1,i2,id,2)**2
                  s(2) = s(2) + xn(i1,i2,id,1)**2
     &                        + xn(i1,i2,id,3)**2
                  s(3) = s(3) + xn(i1,i2,id,2)**2
     &                        + xn(i1,i2,id,1)**2
                  s(4) = s(4) + z(i1,i2,id,2,ir)*xn(i1,i2,id,3)
     &                        - z(i1,i2,id,3,ir)*xn(i1,i2,id,2)
                  s(5) = s(5) + z(i1,i2,id,3,ir)*xn(i1,i2,id,1)
     &                        - z(i1,i2,id,1,ir)*xn(i1,i2,id,3)
                  s(6) = s(6) + z(i1,i2,id,1,ir)*xn(i1,i2,id,2)
     &                        - z(i1,i2,id,2,ir)*xn(i1,i2,id,1)
               end do
            end do
         end do
 
         if(nproc .gt. 1) then
            call psum(s,6)
         endif
 
         s(4) = s(4)/s(1)
         s(5) = s(5)/s(2)
         s(6) = s(6)/s(3)
 
         do id=1,nd
 
            if(mynum.eq.0 .or. (mynum.eq.mproc .and. nd.le.5)) then
               z(0,1,id,1,ir) = z(0,1,id,1,ir) + s(5)*xn(0,1,id,3)
               z(0,1,id,2,ir) = z(0,1,id,2,ir) - s(4)*xn(0,1,id,3)
            endif
 
            do i2=1,nt+1
               do i1=0,nt
                  z(i1,i2,id,1,ir) = z(i1,i2,id,1,ir)
     &              + s(5)*xn(i1,i2,id,3) - s(6)*xn(i1,i2,id,2)
                  z(i1,i2,id,2,ir) = z(i1,i2,id,2,ir)
     &              + s(6)*xn(i1,i2,id,1) - s(4)*xn(i1,i2,id,3)
                  z(i1,i2,id,3,ir) = z(i1,i2,id,3,ir)
     &              + s(4)*xn(i1,i2,id,2) - s(5)*xn(i1,i2,id,1)
               end do
            end do
 
         end do
 
	enddo

	end subroutine


*dk nospin0
	subroutine nospin0(z,xn)
!	This routine removes the rigid rotation from the vector field z
!	on the coarsest grid level.
 
      real z(0:1,2,10,3,2), xn(0:1,2,10,3)
 
      call nuledge(z,10,1,1,3)
 
      do ir=1,2
 
         sx = 2.
         sy = 2.
         sz = 0.
         rx = z(0,1,1,2,ir) - z(0,1,8,2,ir)
         ry = z(0,1,8,1,ir) - z(0,1,1,1,ir)
         rz = 0.
 
         do id=1,10
            sx = sx + xn(1,1,id,3)**2 + xn(1,1,id,2)**2
            sy = sy + xn(1,1,id,1)**2 + xn(1,1,id,3)**2
            sz = sz + xn(1,1,id,2)**2 + xn(1,1,id,1)**2
            rx = rx + z(1,1,id,2,ir)*xn(1,1,id,3)
     &              - z(1,1,id,3,ir)*xn(1,1,id,2)
            ry = ry + z(1,1,id,3,ir)*xn(1,1,id,1)
     &              - z(1,1,id,1,ir)*xn(1,1,id,3)
            rz = rz + z(1,1,id,1,ir)*xn(1,1,id,2)
     &              - z(1,1,id,2,ir)*xn(1,1,id,1)
         end do
 
         rx = rx/sx
         ry = ry/sy
         rz = rz/sz
 
         z(0,1,1,1,ir) = z(0,1,1,1,ir) + ry
         z(0,1,1,2,ir) = z(0,1,1,2,ir) - rx
         z(0,1,8,1,ir) = z(0,1,8,1,ir) - ry
         z(0,1,8,2,ir) = z(0,1,8,2,ir) + rx
 
         do id=1,10
            z(1,1,id,1,ir) = z(1,1,id,1,ir) + ry*xn(1,1,id,3)
     &                                      - rz*xn(1,1,id,2)
            z(1,1,id,2,ir) = z(1,1,id,2,ir) + rz*xn(1,1,id,1)
     &                                      - rx*xn(1,1,id,3)
            z(1,1,id,3,ir) = z(1,1,id,3,ir) + rx*xn(1,1,id,2)
     &                                      - ry*xn(1,1,id,1)
         end do
 
      end do
 
      call edgadd0(z,3,1,1,1)

	end subroutine


*dk oprxuf
	subroutine oprxuf(v,u,d)
!	This routine computes v = v - A*u, where A is a tensor operator.
 
      include 'size.h'
      real v(0:nt,nt+1,nd,3,nr+1), d(0:nt,nt+1,ndo,3,3,nr+1)
      real u(0:nt,nt+1,nd,3,nr+1), w(4,0:nt,nr+1,nd)
      common /oper/ ra(3,8,nr+1), alp(7,0:nt,nt+1,2),
     &              atn(4,7,0:nt,nt+1,3,3)
 
      call nuledge(v,nd,nr,nt,3)
 
      call rotate(u,nd,nr,nt,1)
      call rotate(v,nd,nr,nt,1)
 
      do i2=1,nt+1
 
         do j=1,3
 
            call nulvec(w, 4*(nt+1)*(nr+1)*nd)
 
            do i=1,3
               do ir=1,nr+1
                  do id=1,nd
                     do i1=0,nt
                        w(1,i1,ir,id) = w(1,i1,ir,id) + (((((((
     &                    atn(1,1,i1,i2,i,j)*u(i1  ,i2  ,id,i,ir))
     &                  + atn(1,2,i1,i2,i,j)*u(i1+1,i2  ,id,i,ir))
     &                  + atn(1,3,i1,i2,i,j)*u(i1  ,i2+1,id,i,ir))
     &                  + atn(1,4,i1,i2,i,j)*u(i1-1,i2+1,id,i,ir))
     &                  + atn(1,5,i1,i2,i,j)*u(i1-1,i2  ,id,i,ir))
     &                  + atn(1,6,i1,i2,i,j)*u(i1  ,i2-1,id,i,ir))
     &                  + atn(1,7,i1,i2,i,j)*u(i1+1,i2-1,id,i,ir))
                        w(2,i1,ir,id) = w(2,i1,ir,id) + (((((((
     &                    atn(2,1,i1,i2,i,j)*u(i1  ,i2  ,id,i,ir))
     &                  + atn(2,2,i1,i2,i,j)*u(i1+1,i2  ,id,i,ir))
     &                  + atn(2,3,i1,i2,i,j)*u(i1  ,i2+1,id,i,ir))
     &                  + atn(2,4,i1,i2,i,j)*u(i1-1,i2+1,id,i,ir))
     &                  + atn(2,5,i1,i2,i,j)*u(i1-1,i2  ,id,i,ir))
     &                  + atn(2,6,i1,i2,i,j)*u(i1  ,i2-1,id,i,ir))
     &                  + atn(2,7,i1,i2,i,j)*u(i1+1,i2-1,id,i,ir))
                        w(3,i1,ir,id) = w(3,i1,ir,id) + (((((((
     &                    atn(3,1,i1,i2,i,j)*u(i1  ,i2  ,id,i,ir))
     &                  + atn(3,2,i1,i2,i,j)*u(i1+1,i2  ,id,i,ir))
     &                  + atn(3,3,i1,i2,i,j)*u(i1  ,i2+1,id,i,ir))
     &                  + atn(3,4,i1,i2,i,j)*u(i1-1,i2+1,id,i,ir))
     &                  + atn(3,5,i1,i2,i,j)*u(i1-1,i2  ,id,i,ir))
     &                  + atn(3,6,i1,i2,i,j)*u(i1  ,i2-1,id,i,ir))
     &                  + atn(3,7,i1,i2,i,j)*u(i1+1,i2-1,id,i,ir))
                        w(4,i1,ir,id) = w(4,i1,ir,id) + (((((((
     &                    atn(4,1,i1,i2,i,j)*u(i1  ,i2  ,id,i,ir))
     &                  + atn(4,2,i1,i2,i,j)*u(i1+1,i2  ,id,i,ir))
     &                  + atn(4,3,i1,i2,i,j)*u(i1  ,i2+1,id,i,ir))
     &                  + atn(4,4,i1,i2,i,j)*u(i1-1,i2+1,id,i,ir))
     &                  + atn(4,5,i1,i2,i,j)*u(i1-1,i2  ,id,i,ir))
     &                  + atn(4,6,i1,i2,i,j)*u(i1  ,i2-1,id,i,ir))
     &                  + atn(4,7,i1,i2,i,j)*u(i1+1,i2-1,id,i,ir))
                     end do
                  end do
               end do
            end do
 
            do id=1,nd
 
               do i1=0,nt
                  v(i1,i2,id,j,1) = v(i1,i2,id,j,1) - ((((((((
     &              ra(2,1,1)*w(1,i1,1,id))
     &            + ra(2,2,1)*w(2,i1,1,id))
     &            + ra(2,3,1)*w(3,i1,1,id))
     &            + ra(2,4,1)*w(4,i1,1,id))
     &            + ra(3,1,1)*w(1,i1,2,id))
     &            + ra(3,2,1)*w(2,i1,2,id))
     &            + ra(3,3,1)*w(3,i1,2,id))
     &            + ra(3,4,1)*w(4,i1,2,id))
               end do
 
               do ir=2,nr
                  do i1=0,nt
                     v(i1,i2,id,j,ir) = v(i1,i2,id,j,ir) - ((((((((((((
     &                 ra(1,1,ir)*w(1,i1,ir-1,id))
     &               + ra(1,2,ir)*w(2,i1,ir-1,id))
     &               + ra(1,3,ir)*w(3,i1,ir-1,id))
     &               + ra(1,4,ir)*w(4,i1,ir-1,id))
     &               + ra(2,1,ir)*w(1,i1,ir  ,id))
     &               + ra(2,2,ir)*w(2,i1,ir  ,id))
     &               + ra(2,3,ir)*w(3,i1,ir  ,id))
     &               + ra(2,4,ir)*w(4,i1,ir  ,id))
     &               + ra(3,1,ir)*w(1,i1,ir+1,id))
     &               + ra(3,2,ir)*w(2,i1,ir+1,id))
     &               + ra(3,3,ir)*w(3,i1,ir+1,id))
     &               + ra(3,4,ir)*w(4,i1,ir+1,id))
                  end do
               end do
 
               do i1=0,nt
                  v(i1,i2,id,j,nr+1) = v(i1,i2,id,j,nr+1) - ((((((((
     &              ra(1,1,nr+1)*w(1,i1,nr,id))
     &            + ra(1,2,nr+1)*w(2,i1,nr,id))
     &            + ra(1,3,nr+1)*w(3,i1,nr,id))
     &            + ra(1,4,nr+1)*w(4,i1,nr,id))
     &            + ra(2,1,nr+1)*w(1,i1,nr+1,id))
     &            + ra(2,2,nr+1)*w(2,i1,nr+1,id))
     &            + ra(2,3,nr+1)*w(3,i1,nr+1,id))
     &            + ra(2,4,nr+1)*w(4,i1,nr+1,id))
               end do
 
            end do
 
         end do
 
      end do
 
      do ir=1,nr+1
         do id=1,nd
            jd = min(ndo, id)
            do i2=1,nt+1
               do i1=0,nt
                  v(i1,i2,id,1,ir) = v(i1,i2,id,1,ir) - (((
     &                 d(i1,i2,jd,1,1,ir)*u(i1,i2,id,1,ir))
     &               + d(i1,i2,jd,2,1,ir)*u(i1,i2,id,2,ir))
     &               + d(i1,i2,jd,3,1,ir)*u(i1,i2,id,3,ir))
                  v(i1,i2,id,2,ir) = v(i1,i2,id,2,ir) - (((
     &                 d(i1,i2,jd,1,2,ir)*u(i1,i2,id,1,ir))
     &               + d(i1,i2,jd,2,2,ir)*u(i1,i2,id,2,ir))
     &               + d(i1,i2,jd,3,2,ir)*u(i1,i2,id,3,ir))
                  v(i1,i2,id,3,ir) = v(i1,i2,id,3,ir) - (((
     &                 d(i1,i2,jd,1,3,ir)*u(i1,i2,id,1,ir))
     &               + d(i1,i2,jd,2,3,ir)*u(i1,i2,id,2,ir))
     &               + d(i1,i2,jd,3,3,ir)*u(i1,i2,id,3,ir))
               end do
            end do
         end do
      end do
 
      call rotate(u,nd,nr,nt,-1)
      call rotate(v,nd,nr,nt,-1)
 
      call comm3s(v,nr,nt,3)

	end subroutine


*dk oprxuc
	subroutine oprxuc(v,u,a,ndo,nd,nr,nt)
!	This routine computes v = v - A*u, where A is a tensor operator.
 
      include 'pcom.h'
      real a(7,0:nt,nt+1,ndo,3,3,3*(nr+1))
      real v(0:nt,nt+1,nd,3,nr+1)
      real u(0:nt,nt+1,nd,3,nr+1)
 
      call nuledge(v,nd,nr,nt,3)
 
      call rotate(u,nd,nr,nt,1)
      call rotate(v,nd,nr,nt,1)
 
      do ir=1,nr+1
 
         k1 = 1
         k2 = 3
         if(ir .eq.    1) k1 = 2
         if(ir .eq. nr+1) k2 = 2
 
         do k=k1,k2
 
            jr =  ir + k - 2
            kr = (ir - 1)*3 + k
 
            do i=1,3
               do id=1,nd
                  jd = min(ndo, id)
                  do i2=1,nt+1
                     do i1=0,nt
                        v(i1,i2,id,1,ir) = v(i1,i2,id,1,ir) - (((((((
     &                    a(1,i1,i2,jd,i,1,kr)*u(i1  ,i2  ,id,i,jr))
     &                  + a(2,i1,i2,jd,i,1,kr)*u(i1+1,i2  ,id,i,jr))
     &                  + a(3,i1,i2,jd,i,1,kr)*u(i1  ,i2+1,id,i,jr))
     &                  + a(4,i1,i2,jd,i,1,kr)*u(i1-1,i2+1,id,i,jr))
     &                  + a(5,i1,i2,jd,i,1,kr)*u(i1-1,i2  ,id,i,jr))
     &                  + a(6,i1,i2,jd,i,1,kr)*u(i1  ,i2-1,id,i,jr))
     &                  + a(7,i1,i2,jd,i,1,kr)*u(i1+1,i2-1,id,i,jr))
                        v(i1,i2,id,2,ir) = v(i1,i2,id,2,ir) - (((((((
     &                    a(1,i1,i2,jd,i,2,kr)*u(i1  ,i2  ,id,i,jr))
     &                  + a(2,i1,i2,jd,i,2,kr)*u(i1+1,i2  ,id,i,jr))
     &                  + a(3,i1,i2,jd,i,2,kr)*u(i1  ,i2+1,id,i,jr))
     &                  + a(4,i1,i2,jd,i,2,kr)*u(i1-1,i2+1,id,i,jr))
     &                  + a(5,i1,i2,jd,i,2,kr)*u(i1-1,i2  ,id,i,jr))
     &                  + a(6,i1,i2,jd,i,2,kr)*u(i1  ,i2-1,id,i,jr))
     &                  + a(7,i1,i2,jd,i,2,kr)*u(i1+1,i2-1,id,i,jr))
                        v(i1,i2,id,3,ir) = v(i1,i2,id,3,ir) - (((((((
     &                    a(1,i1,i2,jd,i,3,kr)*u(i1  ,i2  ,id,i,jr))
     &                  + a(2,i1,i2,jd,i,3,kr)*u(i1+1,i2  ,id,i,jr))
     &                  + a(3,i1,i2,jd,i,3,kr)*u(i1  ,i2+1,id,i,jr))
     &                  + a(4,i1,i2,jd,i,3,kr)*u(i1-1,i2+1,id,i,jr))
     &                  + a(5,i1,i2,jd,i,3,kr)*u(i1-1,i2  ,id,i,jr))
     &                  + a(6,i1,i2,jd,i,3,kr)*u(i1  ,i2-1,id,i,jr))
     &                  + a(7,i1,i2,jd,i,3,kr)*u(i1+1,i2-1,id,i,jr))
                     end do
                  end do
               end do
            end do
 
         end do
 
      end do
 
      call rotate(u,nd,nr,nt,-1)
      call rotate(v,nd,nr,nt,-1)
 
      if(lvproc .eq. 0) then
         call edgadd0(v,3,nr,nt,1)
      else
         call comm3s(v,nr,nt,3)
      end if

	end subroutine


*dk proj3s
	subroutine proj3s(rf,rc,w,rw,hw,nj,nrf,ntf)
 
	include 'size.h'
	include 'pcom.h'

	real rf(0:ntf,ntf+1,nd,nj,*), rc(0:ntf/2,ntf/2+1,nd,nj,*)
	real rw(2,0:ntf,ntf+1,ndo,*), hw(2:7,0:ntf/2,ntf/2+1,ndo,*)
	real w(7,0:ntf/2,ntf/2+1,3)

	common /ofst/ j1n(7), j2n(7), md(7)
	common /clck/ itmng, sec(50)

	if(itmng==1) call mytime(tin)
 
      iproc = mod(mynum, mproc)
      ntc   = ntf/2
      nrc   = max(1, nrf/2)
 
      do i2=1,ntc+1
         do i1=0,ntc
            w(1,i1,i2,1) = 1.
            w(2,i1,i2,1) = 1.
            w(3,i1,i2,1) = 1.
            w(4,i1,i2,1) = 1.
            w(5,i1,i2,1) = 1.
            w(6,i1,i2,1) = 1.
            w(7,i1,i2,1) = 1.
         end do
      end do
 
      call subarraybc1(w,ntc)
 
      do ir=1,nrc+1
 
         k1 = 1
         k2 = 3
         if(ir.eq.    1 .or. nrf.eq.1) k1 = 2
         if(ir.eq.nrc+1 .or. nrf.eq.1) k2 = 2
 
         do id=1,nd
 
            if(iproc.eq.0) then
               w(1,0,1,1) = 0.
               if(mod(id,5) .eq. 1) w(1,0,1,1) = 1.
            end if
 
            jr = ir + ir - 1
            if(nrf .eq. 1) jr = ir
            jd = min(ndo, id)
 
            do i2=1,ntc+1
               do i1=0,ntc
                  w(1,i1,i2,2) = w(1,i1,i2,1)
                  w(2,i1,i2,2) = w(2,i1,i2,1)*hw(2,i1,i2,jd,ir)
                  w(3,i1,i2,2) = w(3,i1,i2,1)*hw(3,i1,i2,jd,ir)
                  w(4,i1,i2,2) = w(4,i1,i2,1)*hw(4,i1,i2,jd,ir)
                  w(5,i1,i2,2) = w(5,i1,i2,1)*hw(5,i1,i2,jd,ir)
                  w(6,i1,i2,2) = w(6,i1,i2,1)*hw(6,i1,i2,jd,ir)
                  w(7,i1,i2,2) = w(7,i1,i2,1)*hw(7,i1,i2,jd,ir)
               end do
            end do
 
            do i2=1,ntc+1
               do i1=0,ntc
                  rc(i1,i2,id,1,ir) = ((((((
     &                 w(1,i1,i2,2)*rf(i1+i1  ,i2+i2-1,id,1,jr)
     &               + w(2,i1,i2,2)*rf(i1+i1+1,i2+i2-1,id,1,jr))
     &               + w(3,i1,i2,2)*rf(i1+i1  ,i2+i2  ,id,1,jr))
     &               + w(4,i1,i2,2)*rf(i1+i1-1,i2+i2  ,id,1,jr))
     &               + w(5,i1,i2,2)*rf(i1+i1-1,i2+i2-1,id,1,jr))
     &               + w(6,i1,i2,2)*rf(i1+i1  ,i2+i2-2,id,1,jr))
     &               + w(7,i1,i2,2)*rf(i1+i1+1,i2+i2-2,id,1,jr))
                  rc(i1,i2,id,2,ir) = ((((((
     &                 w(1,i1,i2,2)*rf(i1+i1  ,i2+i2-1,id,2,jr)
     &               + w(2,i1,i2,2)*rf(i1+i1+1,i2+i2-1,id,2,jr))
     &               + w(3,i1,i2,2)*rf(i1+i1  ,i2+i2  ,id,2,jr))
     &               + w(4,i1,i2,2)*rf(i1+i1-1,i2+i2  ,id,2,jr))
     &               + w(5,i1,i2,2)*rf(i1+i1-1,i2+i2-1,id,2,jr))
     &               + w(6,i1,i2,2)*rf(i1+i1  ,i2+i2-2,id,2,jr))
     &               + w(7,i1,i2,2)*rf(i1+i1+1,i2+i2-2,id,2,jr))
                  rc(i1,i2,id,3,ir) = ((((((
     &                 w(1,i1,i2,2)*rf(i1+i1  ,i2+i2-1,id,3,jr)
     &               + w(2,i1,i2,2)*rf(i1+i1+1,i2+i2-1,id,3,jr))
     &               + w(3,i1,i2,2)*rf(i1+i1  ,i2+i2  ,id,3,jr))
     &               + w(4,i1,i2,2)*rf(i1+i1-1,i2+i2  ,id,3,jr))
     &               + w(5,i1,i2,2)*rf(i1+i1-1,i2+i2-1,id,3,jr))
     &               + w(6,i1,i2,2)*rf(i1+i1  ,i2+i2-2,id,3,jr))
     &               + w(7,i1,i2,2)*rf(i1+i1+1,i2+i2-2,id,3,jr))
               end do
            end do
 
            do k=k1,k2
 
               kk = (k + 1)/2
               jr = ir + ir + k - 3
               if(nrf .eq. 1) jr = ir
 
               if(k .ne. 2) then
 
                  do i2=1,ntc+1
                     do i1=0,ntc
                        w(1,i1,i2,3) = w(1,i1,i2,2)
     &                               *rw(kk,i1+i1  ,i2+i2-1,jd,ir)
                        w(2,i1,i2,3) = w(2,i1,i2,2)
     &                               *rw(kk,i1+i1+1,i2+i2-1,jd,ir)
                        w(3,i1,i2,3) = w(3,i1,i2,2)
     &                               *rw(kk,i1+i1  ,i2+i2  ,jd,ir)
                        w(4,i1,i2,3) = w(4,i1,i2,2)
     &                               *rw(kk,i1+i1-1,i2+i2  ,jd,ir)
                        w(5,i1,i2,3) = w(5,i1,i2,2)
     &                               *rw(kk,i1+i1-1,i2+i2-1,jd,ir)
                        w(6,i1,i2,3) = w(6,i1,i2,2)
     &                               *rw(kk,i1+i1  ,i2+i2-2,jd,ir)
                        w(7,i1,i2,3) = w(7,i1,i2,2)
     &                               *rw(kk,i1+i1+1,i2+i2-2,jd,ir)
                     end do
                  end do
 
                  do i2=1,ntc+1
                     do i1=0,ntc
                        rc(i1,i2,id,1,ir) = (((((((rc(i1,i2,id,1,ir)
     &                     + w(1,i1,i2,3)*rf(i1+i1  ,i2+i2-1,id,1,jr))
     &                     + w(2,i1,i2,3)*rf(i1+i1+1,i2+i2-1,id,1,jr))
     &                     + w(3,i1,i2,3)*rf(i1+i1  ,i2+i2  ,id,1,jr))
     &                     + w(4,i1,i2,3)*rf(i1+i1-1,i2+i2  ,id,1,jr))
     &                     + w(5,i1,i2,3)*rf(i1+i1-1,i2+i2-1,id,1,jr))
     &                     + w(6,i1,i2,3)*rf(i1+i1  ,i2+i2-2,id,1,jr))
     &                     + w(7,i1,i2,3)*rf(i1+i1+1,i2+i2-2,id,1,jr))
                        rc(i1,i2,id,2,ir) = (((((((rc(i1,i2,id,2,ir)
     &                     + w(1,i1,i2,3)*rf(i1+i1  ,i2+i2-1,id,2,jr))
     &                     + w(2,i1,i2,3)*rf(i1+i1+1,i2+i2-1,id,2,jr))
     &                     + w(3,i1,i2,3)*rf(i1+i1  ,i2+i2  ,id,2,jr))
     &                     + w(4,i1,i2,3)*rf(i1+i1-1,i2+i2  ,id,2,jr))
     &                     + w(5,i1,i2,3)*rf(i1+i1-1,i2+i2-1,id,2,jr))
     &                     + w(6,i1,i2,3)*rf(i1+i1  ,i2+i2-2,id,2,jr))
     &                     + w(7,i1,i2,3)*rf(i1+i1+1,i2+i2-2,id,2,jr))
                        rc(i1,i2,id,3,ir) = (((((((rc(i1,i2,id,3,ir)
     &                     + w(1,i1,i2,3)*rf(i1+i1  ,i2+i2-1,id,3,jr))
     &                     + w(2,i1,i2,3)*rf(i1+i1+1,i2+i2-1,id,3,jr))
     &                     + w(3,i1,i2,3)*rf(i1+i1  ,i2+i2  ,id,3,jr))
     &                     + w(4,i1,i2,3)*rf(i1+i1-1,i2+i2  ,id,3,jr))
     &                     + w(5,i1,i2,3)*rf(i1+i1-1,i2+i2-1,id,3,jr))
     &                     + w(6,i1,i2,3)*rf(i1+i1  ,i2+i2-2,id,3,jr))
     &                     + w(7,i1,i2,3)*rf(i1+i1+1,i2+i2-2,id,3,jr))
                     end do
                  end do
 
               end if
 
            end do
 
         end do
 
      end do
 
	call comm3s(rc,nrc,ntc,nj)
 
	if(itmng==1) then
		call mytime(tout)
		sec(8) = sec(8) + tout - tin
	endif

	end subroutine


*dk pseu3s
	subroutine pseu3s(z,r,nj)
!	This routine multiplies the residual field r by the pseudo-
!	inverse matrix ainv to obtain the correction field z at the
!	coarsest grid level in the FAPIN multigrid solver.
 
      include 'size.h'
      parameter (nxm=4000+(nt+1)**2*41)
      real z(2,2,10,nj,2), r(2,2,10,nj,2), zz(72), rr(72)
      common /grid/ mxm(0:10), xm(nxm)
      common /pseu/ ainvd1(576), ainvm1(576), ainvd3(5184), ainvm3(5184)
      common /opwt/ wd, wm

!	We use our own version and not the Fortran90 one
      external matmul
 
      call vnn(rr,r,nj)
 
      if(nj.eq.1) then
         if(wd.ne.0.) then
            call matmul(zz,ainvd1,rr,24)
         else
            call matmul(zz,ainvm1,rr,24)
         endif
      else
         if(wd.ne.0.) then
            call matmul(zz,ainvd3,rr,72)
            call vscale(zz,zz,1.0/wd,72)
         else
            call matmul(zz,ainvm3,rr,72)
         endif
      endif
 
      call nulvec(z, 80*nj)
 
      i = 0
 
      do ir=1,2
         do j=1,nj
            i = i + 1
            z(1,1,1,j,ir) = zz(i)
         end do
      end do
 
      do id=1,10
         do ir=1,2
            do j=1,nj
               i = i + 1
               z(2,1,id,j,ir) = zz(i)
            end do
         end do
      end do
 
      do ir=1,2
         do j=1,nj
            i = i + 1
            z(1,1,6,j,ir) = zz(i)
         end do
      end do
 
      call edgadd0(z,nj,1,1,1)
 
      call nospin0(z,xm)

	end subroutine


*dk study3s
	subroutine study3s(name,r,rnorm,nj,lv,nd,nr,nt,inorm)
!	This routine obtains the l2 norm of field r and prints the
!	FAPIN grid level, the name assigned to the field, and its norm.
 
	include 'pcom.h'

	real r(*)
	character*6 name
 
	if(inorm==1) call norm3s(r,rnorm,nj,nd,nr,nt)
 
      if(mynum==0) write(222,10) lv, name, rnorm
 10   format(10x,'FAPIN LEVEL ',i1,':    NORM OF ',a6,1pe12.5)

	end subroutine


*dk subarraybc1
	subroutine subarraybc1(ap,kt)
!	This routine sets to zero the appropriate stencil components
!	along the sub-domain boundaries for the operator ap.  The flag
!	idiamond, when set to one, causes redundant components on the
!	diamond edges to be set to zero.
 
      include 'size.h'
      include 'pcom.h'
      real ap(7,kt+1,kt+1)
 
      k     = kt + 1
      iproc = mod(mynum, mproc)
      i0    = 1
      if(iproc .eq. 0) i0 = 2
 
      do i=i0,kt+1
 
c...     Treat upper right edge.
 
         ap(1,1,i) = 0.
         ap(3,1,i) = 0.
         ap(4,1,i) = 0.
         ap(5,1,i) = 0.
         ap(6,1,i) = 0.
 
c...     Treat upper left edge.
 
         ap(6,i,1) = 0.
         ap(7,i,1) = 0.
 
      end do
 
      do i=1,kt+1
 
c...     Treat lower left edge.
 
         ap(2,k,i) = 0.
         ap(7,k,i) = 0.
 
c...     Treat lower right edge.
 
         ap(1,i,k) = 0.
         ap(2,i,k) = 0.
         ap(3,i,k) = 0.
         ap(4,i,k) = 0.
         ap(5,i,k) = 0.
 
      end do
 
      if(iproc .eq. 0) then
 
         ap(3,1,1) = 0.
         ap(4,1,1) = 0.
         ap(5,1,1) = 0.
         ap(6,1,1) = 0.
         ap(7,1,1) = 0.
 
      end if

	end subroutine


*dk uscale
	subroutine uscale(u,iflag,kr)
!	This routine scales the vector field u by the square root of
!	viscosity variation vv.  iflag = 1 implies multiplication of u
!	by the square root of the viscosity variation, while iflag = 2
!	implies division of u by the square root of the viscosity
!	variation.  This accomplishes part of a preconditioning strategy
!	for the variable viscosity finite element operator.
 
	include 'size.h'

	real u((nt+1)**2*nd,3,nr+1)
	common /vis0/ vb(nt+1), vv((nt+1)**2*nd,nr+1,2), ve(nt+1)
 
	do ir=1,kr+1
		do ii=1,(nt+1)**2*nd
			u(ii,1,ir) = u(ii,1,ir)*vv(ii,ir,iflag)
			u(ii,2,ir) = u(ii,2,ir)*vv(ii,ir,iflag)
			u(ii,3,ir) = u(ii,3,ir)*vv(ii,ir,iflag)
		enddo
	enddo
	
	end subroutine


*dk vbcrdl
	subroutine vbcrdl(v,xn,ibc,nd,nr,nt)
!	This routine imposes boundary conditions on the vector field v
!	at the shell boundaries.  The parameter ibc specifies the
!	conditions as follows:
 
!	ibc = 0  implies both boundaries are free
!	ibc = 1  implies free slip on both boundaries
!	ibc = 2  implies free slip on the inner boundary
!			and the outer boundary free
!	ibc = 3  implies both boundaries are rigid
!	ibc = 5  implies free slip on the inner boundary
!			and the outer boundary rigid
!	ibc = 6  implies free slip on the inner boundary
!			and the outer boundary specified
 
	real v((nt+1)**2,nd,3,nr+1), xn((nt+1)**2,nd,3)

	common /clck/ itmng, sec(50)

	if(itmng==1) call mytime(tin)

	if(ibc==0) return
 
	if(ibc<0.or.ibc>6) then
		write(6,10) ibc 
 10      format(' INVALID VALUE FOR PARAMETER IBC: ',i5)
		stop
	endif
 
	ir1 = 1
	if(ibc==2) ir1 = nr + 1
 
	do id=1,nd
		do ir=ir1,nr+1,nr
 
			if(ibc<=2.or.((ibc==6.or.ibc==5)
     &                        .and.ir==nr+1)) then

				do ii=1,(nt+1)**2
					vn = ((v(ii,id,1,ir)*xn(ii,id,1)
     &				+ v(ii,id,2,ir)*xn(ii,id,2))
     &				+ v(ii,id,3,ir)*xn(ii,id,3))
					v(ii,id,1,ir) = v(ii,id,1,ir) - vn*xn(ii,id,1)
					v(ii,id,2,ir) = v(ii,id,2,ir) - vn*xn(ii,id,2)
					v(ii,id,3,ir) = v(ii,id,3,ir) - vn*xn(ii,id,3)
				enddo
 
			elseif(ibc>=3) then
 
				do ii=1,(nt+1)**2
					v(ii,id,1,ir) = 0.0
					v(ii,id,2,ir) = 0.0
					v(ii,id,3,ir) = 0.0
				enddo
	
			endif
 		enddo
	enddo
 
	if(itmng==1) then
		call mytime(tout)
		sec(11) = sec(11) + tout - tin
	endif

	end subroutine

