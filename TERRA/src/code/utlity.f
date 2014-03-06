*DK arrcopy
      subroutine arrcopy(vout,vin,nn)
 
c...  This routine copies array vin into array vout.
 
      real vout(*), vin(*)
 
      do ii=1,nn-2,3
         vout(ii)   = vin(ii)
         vout(ii+1) = vin(ii+1)
         vout(ii+2) = vin(ii+2)
      end do
 
      do ii=3*(nn/3)+1,nn
         vout(ii)   = vin(ii)
      end do
 
      end
*dk dot
      function dot(p,x,y,z)
 
      real p(3)
 
      dot = p(1)*x + p(2)*y + p(3)*z
 
      end
*dk dot2
      function dot2(x,y)
 
      real x(2), y(2)
 
      dot2 = x(1)*y(1) + x(2)*y(2)
 
      end
*dk dotpr
      function dotpr(e,xn,i1,i2,id,nt)
 
c...  This routine computes the dot product of the vector e
c...  with the vertex coordinate array xn at vertex (i1,i2,id).
 
      real xn(0:nt,nt+1,10,3), e(3)
 
      dotpr = e(1)*xn(i1,i2,id,1) + e(2)*xn(i1,i2,id,2)
     &      + e(3)*xn(i1,i2,id,3)
 
      end
*dk dprd
      function dprd(x,y)
 
c...  This routine computes the dot product of the vectors x and y.
 
      real x(3), y(3)
 
      dprd = x(1)*y(1) + x(2)*y(2) + x(3)*y(3)
 
      end
*dk horizontvel
      subroutine horizontvel(f,u)
 
c...  This routines subtracts the radial
c...  vector component from vector field u.
 
      include 'size.h'
      include 'pcom.h'
      common /mesh/ xn((nt+1)**2*nd,3)
      real f((nt+1)**2*nd,3,nr+1), u((nt+1)**2*nd,3,nr+1)
 
      do ir=1,nr+1
         do ii=1,(nt+1)**2*nd
 
c...  Compute radial velocity component.
 
            u1 = u(ii,1,ir)*xn(ii,1)
            u2 = u(ii,2,ir)*xn(ii,2)
            u3 = u(ii,3,ir)*xn(ii,3)
 
c...  Subtract radial velocity component.
 
            f(ii,1,ir) = u(ii,1,ir) - u1
            f(ii,2,ir) = u(ii,2,ir) - u2
            f(ii,3,ir) = u(ii,3,ir) - u3
 
         end do
      end do
 
      end
*dk kenergy
      subroutine kenergy(ek,u)
 
c...  This routine computes the total kinetic energy due to
c...  fluid motion in the spherical shell.
 
      include 'size.h'
      include 'pcom.h'
      real u((nt+1)**2,nd,3,*)
      common /radl/ rshl(nr+1), ird
      common /volm/ vol((nt+1)**2,(nr+1)*2)
 
      ek  = 0.
 
      do ir=1,nr+1
 
c...     Weight square of velocity with nodal volume.
 
         do id=1,nd
            do ii=1,(nt+1)**2
               ek = ek + ((u(ii,id,1,ir)**2 + u(ii,id,2,ir)**2)
     &                   + u(ii,id,3,ir)**2)*vol(ii,ir)
            end do
         end do
 
      end do
 
c...  Do interprocessor sum.
 
      if(nproc .gt. 1) call psum(ek,1)
 
      ek = 0.5*ek
 
      end
*dk layrav
      subroutine layrav(v,vav)
 
c...  This routine computes the mean value of the nodal scalar
c...  field v for each radial nodal position.
 
      include 'size.h'
      include 'pcom.h'
      real v((nt+1)**2,nd,*), vav(nr+1)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      do ir=1,nr+1
 
         sum = 0.
 
         if(mynum .eq. 0) sum = v(1,1,ir)*arn(1)
         if(mynum .eq. 0 .and. nd .eq. 10)
     &                    sum = v(1,6,ir)*arn(1) + sum
         if(mynum .eq. mproc .and. nd .le. 5)
     &                    sum = v(1,1,ir)*arn(1)
 
         do id=1,nd
            do ii=2,(nt+1)**2
               sum =  sum + v(ii,id,ir)*arn(ii)
            end do
         end do
 
         vav(ir) = sum/(8.*asin(1.))
 
      end do
 
      if(nproc .gt. 1) call psum(vav,nr+1)
 
      end
*dk ltrfill
      subroutine ltrfill(a,n)
 
      real a(n,n)
 
      do i=2,n
         do j=1,i-1
            a(i,j) = a(j,i)
         end do
      end do
 
      end
*dk massflux
      subroutine massflux(lun)
 
c...  This routine calculates the radial mass flux.
 
      include 'size.h'
      include 'pcom.h'
      real totflux, drad, fact
      real variance(nr+1), skewness(nr+1)
      common /velo/ upb(nt+1), u((nt+1)**2,nd,3,nr+1),upe(nt+1)
      common /temp/ tpb(nt+1),temp((nt+1)**2,nd,nr+1),tpe(nt+1)
      common /pres/ ppb(nt+1),pres((nt+1)**2,nd,nr+1),ppe(nt+1)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)

C     Common block has invalid length. Correcting length requires fixing the
C     coding of this sub-routine, however.
C     common /radl/ rshl(nr+2), ird
      common /radl/ rshl(nr+1), ird

      common /mesh/ xn((nt+1)**2,nd,3)
      common /prop/ ieos,  rho0, visc,  grav,  texpn, tcond,
     &              sheat, hgen, tb(2), cl410, cl660
      common /heat/ htop, hbot, hrad, heat, hshr, hvol, hnet, tnrm,
     &              tav(nr+1), qc(nr)
      common /eos1/ rhorf(nr+1), tmprf(nr+1), drhdp(nr+1), grv(nr+1)
      common /eos2/ rhocv(nr+1), gamma(nr+1), alpha(nr+1), prf(nr+1),
     &               cond(nr+1)
      common /mflx/ flux(nr+1)
      common /urut/ ur(nr+1), ut(nr+1)
 
      call nulvec(flux, nr+1)
      call nulvec(variance, nr+1)
      call nulvec(skewness, nr+1)
      totflux = 0.

C     See comment above for common block /radl/
      print *, 'STOP -- Subroutine massflux must be fixed before use!'
      stop
      
c...  Compute rms-norm of the surface velocity field.
      call uradtng
 
      do ir=1,nr
 
c...     Compute density parameters.
 
         a1     = -alpha(ir)*rhorf(ir)
         a2     =  drhdp(ir)
         tref   =  tmprf(ir)
         deltar =  rshl(ir)-rshl(ir+1)
         if(ieos/10 .eq. 0) tref = tnrm
 
c...     Compute finite element operator factors.
 
         jr     = ir + 1
         rm     = 0.5*(rshl(ir) + rshl(jr))
         r2     = rm**2
         ra     = r2 - 0.25*(rshl(jr) + rshl(jr+1))**2
         if(jr .eq. nr+1) ra  = r2 - rshl(nr+1)**2
 
         do id=1,nd
 
c...        Compute flux at cell boundaries.
 
            do ii=1,(nt+1)**2
 
               uf1 = 0.5*(u(ii,id,1,ir) + u(ii,id,1,jr))
               uf2 = 0.5*(u(ii,id,2,ir) + u(ii,id,2,jr))
               uf3 = 0.5*(u(ii,id,3,ir) + u(ii,id,3,jr))
               vfl = ((uf1*xn(ii,id,1)  + uf2*xn(ii,id,2))
     &               + uf3*xn(ii,id,3)) * arn(ii)
 
               tempmean = 0.5*(temp(ii,id,ir) + temp(ii,id,jr))
               presmean = 0.5*(pres(ii,id,ir) + pres(ii,id,jr))
               deltarho = a1*(tempmean - tref) + a2*presmean
 
c...           Sum flux across each layer.
 
               flux(ir) = flux(ir)+(rhorf(ir)+deltarho)*abs(vfl)*r2
            end do
         end do
 
c...     Sum flux across the shell.
         totflux = totflux + deltar*flux(ir)
 
      end do
 
c...  Obtain global sum.
 
      if(nproc .gt. 1) call psum(flux, nr+1)
      if(nproc .gt. 1) call psum(totflux, 1)
 
c...  Normalize layer flux by dividing by total flux.
 
      drad = rshl(1) - rshl(nr+1)
      fact = drad/totflux
      
c...  compute variance and skewness of the temperature field
      call varianz(temp,variance,skewness)

      if(mynum .eq. 0) then
 
         write(lun,'(/" time = ",1pe15.8/)') 0 !time
 
         write(lun,'(" ir    depth    avg temp   heat flux",
     &               "   hor vel    rad vel   mass flux ",
     &               "T-variance T-skewness")')
 
         do ir=1,nr+1
            write(lun,'(i3,1p9e11.3)') ir, 0.001*(rshl(1) - rshl(ir)),
     &      tav(ir)-tmprf(ir),qc(ir),3.1558e9*ut(ir),3.1558e9*ur(ir),
     &      flux(ir)*fact, variance(ir), skewness(ir) 
         end do
 
      endif
 
      end subroutine
      
     
*dk matmul
      subroutine matmul(z,a,r,n)
 
      real z(n), a(n,n), r(n)
 
      do i=1,n
         z(i) = 0.
         do j=1,n
            z(i) = z(i) + a(i,j)*r(j)
         end do
      end do
 
      end
*dk matprd1
      subroutine matprd1(a,b,c,n,m)
 
      real a(n,n), b(n,m), c(m,n)
 
      do i=1,n
         do j=1,n
            a(i,j) = 0.
            do k=1,m
               a(i,j) = a(i,j) + b(i,k)*c(k,j)
            end do
         end do
      end do
 
      end
*dk matprd2
      subroutine matprd2(a,b,c,n,m)
 
      real a(n,n), b(m,n), c(m,n)
 
      do i=1,n
         do j=1,n
            a(i,j) = 0.
            do k=1,m
               a(i,j) = a(i,j) + b(k,i)*c(k,j)
            end do
         end do
      end do
 
      end
*dk matprd3
      subroutine matprd3(a,b,c,n,m)
 
      real a(n,n), b(n,m), c(n,m)
 
      do i=1,n
         do j=1,n
            a(i,j) = 0.
            do k=1,m
               a(i,j) = a(i,j) + b(i,k)*c(j,k)
            end do
         end do
      end do
 
      end
*dk midpt
      subroutine midpt(x,x1,x2,nn)
 
c...  This routine finds the midpoint x along the shorter great circle
c...  arc between points x1 and x2 on the unit sphere.
 
      real x(nn,3), x1(nn,3), x2(nn,3)
 
      do j=1,3
         x(1,j) = x1(1,j) + x2(1,j)
      end do
 
      xnorm = 1./sqrt(x(1,1)**2 + x(1,2)**2 + x(1,3)**2)
 
      do j=1,3
         x(1,j) = xnorm*x(1,j)
      end do
 
      end
*dk nulavrg
      subroutine nulavrg(v,nl)
 
c...  This routine, for each radial layer of nodes, subtracts the
c...  average value of the nodal scalar field v at that radius.
 
      include 'size.h'
      include 'pcom.h'
      real v((nt+1)**2,nd,nl), sum(nr+1)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      do ir=1,nl
 
         sum(ir) = 0.
 
         if(mynum .eq. 0) sum(ir) = v(1,1,ir)*arn(1)
         if(mynum .eq. 0 .and. nd .eq. 10)
     &                    sum(ir) = v(1,6,ir)*arn(1) + sum(ir)
         if(mynum .eq. mproc .and. nd .le. 5)
     &                    sum(ir) = v(1,1,ir)*arn(1)
 
         do id=1,nd
            do ii=2,(nt+1)**2
               sum(ir) = sum(ir) + v(ii,id,ir)*arn(ii)
            end do
         end do
 
         sum(ir) = sum(ir)/(8.*asin(1.))
 
      end do
 
      if(nproc .gt. 1) call psum(sum,nl)
 
      do ir=1,nl
         do id=1,nd
            do ii=1,(nt+1)**2
               v(ii,id,ir) = v(ii,id,ir) - sum(ir)
            end do
         end do
      end do
 
      end
*dk nuledge
      subroutine nuledge(u,nd,nr,nt,nj)
 
c...  This routine sets to zero the upper right and lower right
c...  diamonds edges.  It also sets to zero array elements at the
c...  poles in all diamonds except for diamonds 1 and 8.
 
      include 'pcom.h'
      real u(0:nt,nt+1,nd*nj*(nr+1))
 
      i0 = 0
      if(mynum.eq.0 .or. (mynum.eq.mproc .and. nd.le.5)) i0 = 1
 
      do i=i0,nt
         do kk=1,nd*nj*(nr+1)
            u(0, i+1,kk) = 0.
            u(i,nt+1,kk) = 0.
         end do
      end do
 
      if(mynum.eq.0 .or. (mynum.eq.mproc .and. nd.le.5)) then
 
         do id=1,nd
 
            jd = id
            if(nd.eq.5 .and. mynum.ge.mproc) jd = id + 5
            if(nd.eq.1) jd = mynum/mproc + 1
 
            if(.not.(jd.eq.1 .or. jd.eq.8)) then
               jj = id - 1
               do kk=1,nd*nj*(nr+1),nd
                  u(0,1,jj+kk) = 0.
               end do
            endif
 
         end do
 
      end if
 
      end
*dk nulmean
      subroutine nulmean(u,nj)
 
c...  This routine subtracts the mean value from the nodal field u.
 
      include 'size.h'
      include 'pcom.h'
      real u((nt+1)**2,nd,nj,*), umean(3)
      common /radl/ rshl(nr+1), ird
      common /volm/ vol((nt+1)**2,(nr+1)*2)
 
      umean(1) = 0.
      umean(2) = 0.
      umean(3) = 0.
 
      do ir=1,nr+1
 
         do j=1,nj
            do id=1,nd
               do ii=1,(nt+1)**2
                  umean(j) = umean(j) + u(ii,id,j,ir)*vol(ii,ir)
               end do
            end do
         end do
 
      end do
 
      if(nproc .gt. 1) call psum(umean,nj)
 
      rvol = 0.75/(2.*asin(1.)*(rshl(1)**3 - rshl(nr+1)**3))
 
      do j=1,nj
 
         umean(j) = rvol*umean(j)
 
         do ir=1,nr+1
            do id=1,nd
               do ii=1,(nt+1)**2
                  u(ii,id,j,ir) = u(ii,id,j,ir) - umean(j)
               end do
            end do
         end do
 
      end do
 
      end
*dk nulvec
      subroutine nulvec(v,nn)
 
      real v(*)
 
      do ii=1,nn
         v(ii) = 0.
      end do
 
      end
*dk profile
      subroutine profile
 
c...  This routine outputs the timing information stored in
c...  common block /clck/.
 
      include 'pcom.h'
      common /clck/ itmng, sec(50)
 
c...  if(nproc .gt. 1) call psum(sec,50)
 
      if(mynum.eq.0) write(6,10) sec(3), sec(2), sec(1), sec(30)
 10   format(/11x,"CPU SECONDS USED"//
     &       10x,"TOTAL   ",f10.3/10x,"OPERGEN ",f10.3/
     &       10x,"OPINIT  ",f10.3/10x,"MOVIE   ",f10.3)
      if(mynum.eq.0) write(6,20) (1000.*sec(i),i=4,22)
 20   format(/6x,"MILLISECONDS PER TIME STEP"//
     &       10x,"ADVANCE ",f10.3/
     &       10x,"USOLVE  ",f10.3/10x,"MULTGRID",f10.3/
     &       10x,"INTER3S ",f10.3/10x,"PROJ3S  ",f10.3/
     &       10x,"JACOBI  ",f10.3/10x,"AXU     ",f10.3/
     &       10x,"VBCRDL  ",f10.3/10x,"ROTATE  ",f10.3/
     &       10x,"NORM3S  ",f10.3/10x,"COMM3S  ",f10.3/
     &       10x,"FORCES  ",f10.3/10x,"PLATES  ",f10.3/
     &       10x,"DIVERGNC",f10.3/10x,"VISCALC ",f10.3/
     &       10x,"GRADIENT",f10.3/10x,"ENERGY  ",f10.3/
     &       10x,"ADVECT  ",f10.3/10x,"SHRHEAT ",f10.3)
 
      end
*dk proprty
	subroutine proprty(iter)
!	This routine fills the array propr.
 
      include 'size.h'
		include 'para.h'

      common /prty/ propr(20)
      common /radl/ rshl(nr+1), ird
      common /heat/ htop, hbot, hrad, heat, hshr, hvol, hnet, tnrm,
     &              tav(nr+1), qc(nr)
      common /prop/ ieos,  rho0, visc,  grav,  texpn, tcond,
     &              sheat, hgen, tb(2), cl410, cl660
      common /vis1/ vscmax, rvscscl, tvscscl, pwrlawn, pwrlawsr, yldstrs
    
	integer iter
 
      propr(1)  = iter
      propr(2)  = 0	!time
      propr(3)  = ird
      propr(4)  = ibc
      propr(5)  = 0	!tstep
      propr(6)  = ieos
      propr(7)  = rho0
      propr(8)  = visc
      propr(9)  = grav
      propr(10) = texpn
      propr(11) = tcond
      propr(12) = sheat
      propr(13) = hgen
      propr(14) = tb(1)
      propr(15) = tb(2)
      propr(16) = htop
      propr(17) = hbot
      propr(18) = vscmax
      propr(19) = tvscscl
      propr(20) = buff
 
      end
*dk radcor
      subroutine radcor(temp,lun)
 
c...  This routine computes the radial correlation function R(r1,r2)
c...  according to (Puster et al, JGR 100, 6351, 1995) for the scalar
c...  field temp.
 
c...                    surfint(delT(r1,omega)*delT(r2,omega))
c...   R(r1,r2) = ----------------------------------------------------
c...                       sqrt(surfint(delT**2(r1,omega)))
c...                      *sqrt(surfint(delT**2(r2,omega)))
 
      include 'size.h'
      include 'pcom.h'
      real temp((nt+1)**2,nd,nr+1)
      real aver(nr+1),radialcor(nr+1,nr+1),sigma(nr+1)
      common /work/ wk((nt+1)**2*(nr+1)*2)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      call nulvec(aver,nr+1)
      call nulvec(radialcor,nr+1**2)
      call nulvec(sigma,nr+1)
 
      call layrav(temp,aver)
 
c...  Compute the surface integral of the temperature variation squared.
 
      do ir=1,nr+1
         do id=1,nd
            do ii=1,(nt+1)**2
               sigma(ir) = sigma(ir)
     &                   + arn(ii)*(temp(ii,id,ir) - aver(ir))**2
            end do
         end do
      end do
 
      if(nproc .gt. 1) call psum(sigma,nr+1)
 
      do ir=1,nr+1
         sigma(ir) = sqrt(sigma(ir))
      end do
 
c...  Compute radial correlation function.
 
      do jr=1,nr+1
         do ir=1,nr+1
            oneoversigma = 1./(sigma(ir)*sigma(jr))
            do id=1,nd
               do ii=1,(nt+1)**2
                  radialcor(jr,ir) = radialcor(jr,ir) +
     &               (arn(ii)*(temp(ii,id,ir) - aver(ir)) *
     &               (temp(ii,id,jr) - aver(jr))*oneoversigma)
               end do
            end do
         end do
      end do
 
      if(nproc.gt.1) call psumlong(radialcor,wk,(nr+1)**2)
 
      if(mynum .eq. 0) then
         do ir=1,nr+1,2
            write(lun,'(8(1x,f8.5))') (radialcor(jr,ir),jr=1,nr+1,2)
         end do
      endif
 
      end
*dk randomnum
      function randomnum(iseed)
 
c...  This function returns a uniform random diviate between 0.0 and
c...  1.0.  To initialize or reinitialize the sequence, set iseed to
c...  to any negative integer.  This function is adapted from p. 197
c...  of Numerical Recipes by Press et al, 1989.
 
      parameter (m=714025, ia=1366, ic=150889, rm=1./m)
      common /rndm/ ir(97), ix, iy
 
      if(iseed .lt. 0) then
 
         ix = mod(ic-iseed, m)
 
         do j=1,97
            ix    = mod(ia*ix+ic, m)
            ir(j) = ix
         end do
 
         ix = mod(ia*ix+ic, m)
         iy = ix
 
      end if
 
      j = 1 + (97*iy)/m
 
      if(j.gt.97 .or. j.lt.1) stop
 
      iy    = ir(j)
      ix    = mod(ia*ix+ic, m)
      ir(j) = ix
 
      randomnum = iy*rm
 
      end
*dk rmslayer
      subroutine rmslayer(rms,s,ir)
 
c...  This routine computes the rms value of the nodal scalar
c...  field s for radial layer ir.
 
      include 'size.h'
      include 'pcom.h'
      real s((nt+1)**2,nd,*)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      rms = 0.
 
      if(mynum .eq. 0) rms = s(1,1,ir)**2
      if(mynum .eq. 0 .and. nd .eq. 10)
     &                 rms = s(1,6,ir)**2 + rms
      if(mynum .eq. mproc .and. nd .le. 5)
     &                 rms = s(1,1,ir)**2
 
      do id=1,nd
         do ii=2,(nt+1)**2
            if(arn(ii) .ne. 0.) rms =  rms + s(ii,id,ir)**2
         end do
      end do
 
      if(nproc .gt. 1) call psum(rms,1)
 
      rms = sqrt(rms/(10*nt**2+2))
 
      end
*dk rotate
      subroutine rotate(v,nd,nr,nt,irot)
 
c...  This routine performs rotations on the vector field v to align
c...  all diamonds with diamond one when irot=1.  When irot=-1, the
c...  inverse rotations are performed.
 
      include 'pcom.h'
      real v((nt+1)**2,nd,3,nr+1), t(2,2)
      common /rttn/ phi(10), trtn(3,3,10)
      common /clck/ itmng, sec(50)
      if(itmng.eq.1) call mytime(tin)
 
      if(trtn(1,1,1) .eq. 0.) then
 
         do id=1,10
 
            trtn(1,1,id) =  cos(phi(id))
            trtn(1,2,id) = -sin(phi(id))
            trtn(3,3,id) =  1.0
 
            if(id .ge. 6) then
               trtn(1,1,id) = -trtn(1,1,id)
               trtn(1,2,id) = -trtn(1,2,id)
               trtn(3,3,id) = -1.0
            endif
 
            trtn(2,2,id) =  trtn(1,1,id)
            trtn(2,1,id) = -trtn(1,2,id)
 
         end do
 
      endif
 
      do ir=1,nr+1
         do id=1,nd
 
            jd = id
            if(nd.eq.5 .and. mynum.ge.mproc) jd = id + 5
            if(nd.eq.1) jd = mynum/mproc + 1
 
            if(jd .ge. 2) then
 
               t(1,1) = trtn(1,1,jd)
               t(1,2) = trtn(1,2,jd)
               t(2,1) = trtn(2,1,jd)
               t(2,2) = trtn(2,2,jd)
 
               if(irot .eq. 1) then
                  t(1,2) = trtn(2,1,jd)
                  t(2,1) = trtn(1,2,jd)
               endif
 
               do ii=1,(nt+1)**2
                  v1 = v(ii,id,1,ir)
                  v(ii,id,1,ir) = t(1,1)*v1 + t(1,2)*v(ii,id,2,ir)
                  v(ii,id,2,ir) = t(2,1)*v1 + t(2,2)*v(ii,id,2,ir)
               end do
 
               if(jd .ge. 6) then
                  do ii=1,(nt+1)**2
                     v(ii,id,3,ir) = -v(ii,id,3,ir)
                  end do
               endif
 
            endif
 
         end do
      end do
 
      if(itmng.eq.1) call mytime(tout)
      if(itmng.eq.1) sec(12) = sec(12) + tout - tin
      end
*dk sample
      subroutine sample(vc,vf,nj,nrf,ntf)
 
c...  This routine loads into array vc a sampled version of array vf
c...  one grid level coarser than that of vf.
 
      include 'size.h'
      real vc(0:ntf/2,ntf/2+1,nd,nj,nrf/2+1)
      real vf(0:ntf,  ntf+1,  nd,nj,nrf+1)
 
      do ir=1,nrf/2+1
         jr = ir + ir - 1
         do j=1,nj
            do id=1,nd
               do i2=1,ntf/2+1
                  j2 = i2 + i2 -1
                  do i1=0,ntf/2
                     vc(i1,i2,id,j,ir) = vf(i1+i1,j2,id,j,jr)
                  end do
               end do
            end do
         end do
      end do
 
      end
*dk sclrsum
      function sclrsum(s)
 
c...  This routine sums the elements if the scalar field s.
 
      include 'size.h'
      include 'pcom.h'
      real s(0:nt,nt+1,nd,nr+1)
 
      sclrsum = 0.
 
      do ir=1,nr+1
 
         if(mynum .eq. 0) sclrsum = sclrsum + s(0,1,1,ir)
         if(mynum .eq. 0 .and. nd .eq. 10)
     &                    sclrsum = sclrsum + s(0,1,6,ir)
         if(mynum .eq. mproc .and. nd .le. 5)
     &                    sclrsum = sclrsum + s(0,1,1,ir)
 
         do id=1,nd
            do i2=1,nt
               do i1=1,nt
                  sclrsum = sclrsum + s(i1,i2,id,ir)
               end do
            end do
         end do
 
      end do
 
      if(nproc .gt. 1) call psum(sclrsum,1)
 
      end
*dk smean
      function smean(s)
 
c...  This routine computes the volume-weighted average of the
c...  scalar field s.
 
      include 'size.h'
      include 'pcom.h'
      real s((nt+1)**2,nd,nr+1)
      common /radl/ rshl(nr+1), ird
      common /volm/ vol((nt+1)**2,(nr+1)*2)
 
      smean = 0.
 
      do ir=1,nr+1
 
         do id=1,nd
            do ii=1,(nt+1)**2
               smean = smean + s(ii,id,ir)*vol(ii,ir)
            end do
         end do
 
      end do
 
      smean  = smean*0.75/(2.*asin(1.)*(rshl(1)**3 - rshl(nr+1)**3))
 
      if(nproc .gt. 1) call psum(smean,1)
 
      end
*dk surfvel
      subroutine surfvel(us,u)
 
c...  This routine calculates the RMS velocity on the outer
c...  boundary of the spherical shell.
 
      include 'size.h'
      include 'pcom.h'
      real u((nt+1)**2,nd,3,*)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      us = 0.
 
      if(mynum .eq. 0) us =
     &   (u(1,1,1,1)**2 + u(1,1,2,1)**2 + u(1,1,3,1)**2)*arn(1)
      if(mynum .eq. 0 .and. nd .eq. 10) us = us +
     &   (u(1,6,1,1)**2 + u(1,6,2,1)**2 + u(1,6,3,1)**2)*arn(1)
      if(mynum .eq. mproc .and. nd .le. 5) us =
     &   (u(1,1,1,1)**2 + u(1,1,2,1)**2 + u(1,1,3,1)**2)*arn(1)
 
      do id=1,nd
         do ii=2,(nt+1)**2
            us = us + (u(ii,id,1,1)**2 + u(ii,id,2,1)**2
     &              +  u(ii,id,3,1)**2)*arn(ii)
         end do
      end do
 
      if(nproc .gt. 1) call psum(us,1)
 
      us = sqrt(us/(8.*asin(1.)))
 
      end
*dk upsv
      subroutine upsv(u,s,v,nn)
 
      real u(*), v(*)
 
      do ii=1,nn
         u(ii) = u(ii) + s*v(ii)
      end do
 
      end
*dk uradtng
      subroutine uradtng
 
c     This routine computes the spherically-averaged radial and
c     tangential velocities by nodal layer.
 
      include 'size.h'
      include 'pcom.h'
      common /urut/ ur(nr+1), ut(nr+1)
      common /velo/ upb(nt+1), u((nt+1)**2,nd,3,nr+1),  upe(nt+1)
      common /mesh/ xn((nt+1)**2,nd,3)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      do ir=1,nr+1
 
         ur(ir) = 0.
         ut(ir) = 0.
 
         if(mod(mynum, mproc) .eq. 0) then
            ur(ir) =  u(1,1,3,ir)**2*arn(1)
            ut(ir) = (u(1,1,1,ir)**2 + u(1,1,2,ir)**2)*arn(1)
         endif
         if(mynum.eq.0 .and. nd.eq.10) then
            ur(ir) =  u(1,6,3,ir)**2*arn(1) + ur(ir)
            ut(ir) = (u(1,6,1,ir)**2 + u(1,6,2,ir)**2)*arn(1) + ut(ir)
         endif
 
         do id=1,nd
            do ii=1,(nt+1)**2
               r      =  u(ii,id,1,ir)*xn(ii,id,1)
     &                +  u(ii,id,2,ir)*xn(ii,id,2)
     &                +  u(ii,id,3,ir)*xn(ii,id,3)
               t      = (u(ii,id,1,ir) - r*xn(ii,id,1))**2
     &                + (u(ii,id,2,ir) - r*xn(ii,id,2))**2
     &                + (u(ii,id,3,ir) - r*xn(ii,id,3))**2
               ur(ir) =  ur(ir) + arn(ii)*r*r
               ut(ir) =  ut(ir) + arn(ii)*t
            end do
         end do
 
         if(nproc .gt. 1) then
            call psum(ur(ir),1)
            call psum(ut(ir),1)
         endif
 
         ur(ir) = sqrt(ur(ir)/(8.*asin(1.)))
         ut(ir) = sqrt(ut(ir)/(8.*asin(1.)))
 
      end do
 
      end
*dk uthetaphi
      subroutine uthetaphi(f,u,xn)
 
c...  This routine computes the theta and phi component of
c...  the horizontal velocity field u at each radial level.
 
      include 'size.h'
      real f((nt+1)**2,nd,2,nr+1),u((nt+1)**2,nd,3,nr+1)
      real xn((nt+1)**2,nd,3), length, fract, pi, phi, theta
 
      pi  = 3.141592653589793
 
c...  Compute phi and theta components from Cartesian components.
 
      do id=1,nd
         do ii=1,(nt+1)**2
 
            phi    = atan2(xn(ii,id,2)+1.e-30, xn(ii,id,1))
            length = sqrt(xn(ii,id,1)**2  + xn(ii,id,2)**2)
            fract  = ((length+1.e-30)/(xn(ii,id,3)+1.e-30))
            theta  = atan(fract)
            if(theta .lt. 0.) theta = pi + theta
 
            do ir=1,nr+1
 
c...           uphi component (sine and cosine of x/y component):
 
               f(ii,id,1,ir) =  - sin(phi)   * u(ii,id,1,ir)
     &                          + cos(phi)   * u(ii,id,2,ir)
 
c...           utheta component:
 
               f(ii,id,2,ir) =  -cos(theta)  *
     &                          ( cos(phi)   * u(ii,id,1,ir)
     &                          + sin(phi)   * u(ii,id,2,ir))
     &                          + sin(theta) * u(ii,id,3,ir)
 
            end do
         end do
      end do
 
      end
*dk varianz
      subroutine varianz(s,u1,u2)

c...  This routine computes the variance (u1) and the
c     skewness (u2) of the nodal scalar field s at all
c     radial levels. 

      include 'size.h'
      include 'pcom.h'
      real s((nt+1)**2,nd,nr+1), u1(nr+1), u2(nr+1)
      real sav(nr+1), fact
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
     &              rarn((nt+1)**2), rarne((nt+1)**2)

      call nulvec(u1, nr+1)
      call nulvec(u2, nr+1)
      call nulvec(sav,nr+1)

c...  compute layer-average
      call layrav(s,sav)

c...  compute variance (u1) of scalar field s.
      fact = 1./( (10*(mt+1)**2)-1 )
      do ir=1,nr+1
         do id=1,nd
            do ii=1,(nt+1)**2
               u1(ir) = u1(ir) + ((s(ii,id,ir) - sav(ir))**2)
            end do
         end do
         u1(ir) = u1(ir)*fact
      end do

      if(nproc .gt. 1) call psum(u1,nr+1)

c...  compute skewness (u2) of scalar field s.
      fact = 1./(10*(mt+1)**2)
      do ir=1,nr+1
         do id=1,nd
            do ii=1,(nt+1)**2
               u2(ir) = u2(ir) + 
     &         (( (s(ii,id,ir) - sav(ir)) / sqrt(u1(ir)) )**3)
            end do
         end do
         u2(ir) = u2(ir) * fact
      end do

      if(nproc .gt. 1) call psum(u1,nr+1)

      end
*dk vecin
      subroutine vecin(u,titl,rshl,nj,mr,nf,ifmt)
 
c...  This routine reads the nodal field u from logical unit nf
c...  using 1pe10.3 format when ifmt = 0 and f10.3 when ifmt = 1.
 
      include 'size.h'
      real u(*), rshl(*)
      common /prty/ propr(20)
      character*8 titl(4,4)
 
      read(nf,10) kr, kt
 10   format(2i5)
 
      if(kr.ne.nr .or. kt.ne.nt) then
         print *,'Array dimensions of data file and size.h inconsistent'
         ! LMU BS BS begin section added
         print *,'kr = ',kr,' and nr = ',nr
         print *,'kt = ',kt,' and nt = ',nt
         ! LMU BS BS end section added
         stop
      end if
 
      read(nf,20) titl
 20   format(4a8)
 
      read(nf,30) (rshl(i),i=1,nr+1)
      read(nf,30) propr
 30   format(1p10e15.8)
 
      kr = mr
      if(mr .lt. 0) kr = nr
 
      if(ifmt .eq. 0) then
 
         read(nf,40) (u(ii),ii=1,(nt+1)**2*nd*nj*(kr+1))
 40      format(1p15e10.3)
 
      elseif(ifmt .eq. 1) then
 
         read(nf,50) (u(ii),ii=1,(nt+1)**2*nd*nj*(kr+1))
 50      format(15f10.3)
 
      endif

	end subroutine


! LMU BS BS begin
*dk vecin2
	subroutine vecin2(u,titl,rshl,nf,ifmt)
	implicit none

	include 'size.h'

	common /prty/ propr

	integer tmp, i, ii, nf, ifmt
	real u((mt+1)**2*10)
	real rshl(nr+1), propr(20)

	character*8 titl(4,4)

	read(nf,10) tmp, tmp
 10   format(2i5)
 
!      if(kr.ne.nr .or. kt.ne.it) then
!			write(6,*) mynum, kr, kt
!			write(6,*) nr, it
!        print *,'Array dimensions of data file and size.h inconsistent'
!       stop
!      end if

	read(nf,20) titl
 20   format(4a8)
 
	read(nf,30) (rshl(i),i=1,nr+1)
	read(nf,30) propr
 30   format(1p10e15.8)

	if(ifmt==0) then 
		read(nf,40) (u(ii),ii=1,(mt+1)**2*10)
 40      format(1p15e10.3)
 
	elseif(ifmt==1) then
		read(nf,50) (u(ii),ii=1,(mt+1)**2*10)
 50      format(15f10.3)

	endif
 
	end subroutine


*dk vecset
      subroutine vecset(v,value,nn)
 
      real v(*)
 
      do ii=1,nn
         v(ii) = value
      end do
 
      end
*dk volume
      subroutine volume(vol,invrs,ibrdr)
 
c...  This routine computes the volumes associated with the nodal
c...  basis (tent) functions.  When invrs=1, the reciprocal volumes
c...  are computed.  When ibrdr=1, the upper right and lower right
c...  diamond edges are evaluated; otherwise they are set to zero.
 
      include 'size.h'
      real vol((nt+1)**2,nr+1)
      common /radl/ rshl(nr+1), ird
c     common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),
c    &              rarn((nt+1)**2), rarne((nt+1)**2)

c     We split the common block into two arrays:
c
c       tarn  combining  arn and  arne
c       trarn combining rarn and rarne
c
c     thus we can keep the elegant code below which uses the kk index
c     offset, but do not produce out of bounds errors with arn and rarn
      common /ndar/ tarn(2*(nt+1)**2), trarn(2*(nt+1)**2)
 
      kk  = 0
      if(ibrdr .eq. 1) kk = (nt+1)**2
 
      call nulvec(vol,(nt+1)**2*(nr+1))
 
      do ir=1,nr+1
 
         rm = rshl(ir)
 
         if(ir .gt. 1) then
            ru = rshl(ir-1)
            qu = (4.*ru*(ru**3 - rm**3) - 3.*(ru**4 - rm**4))
     &            /(12.*(ru - rm))
         endif
 
         if(ir .le. nr) then
            rl = rshl(ir+1)
            ql = (3.*(rm**4 - rl**4) - 4.*rl*(rm**3 - rl**3))
     &            /(12.*(rm - rl))
         endif
 
         if(ir .eq. 1) then
            r3 = ql
         elseif(ir .eq. nr+1) then
            r3 = qu
         else
            r3 = ql + qu
         endif
 
         if(invrs .ne. 1) then
 
            do ii=1,(nt+1)**2
                  vol(ii,ir) = r3 * tarn(ii+kk)
            end do
 
            if(ibrdr .eq. 0) vol(1,ir) = 0.2*vol(1,ir)
 
         else
 
            r3 = 1./r3
            do ii=1,(nt+1)**2
                  vol(ii,ir) = r3 * trarn(ii+kk)
            end do
 
         endif
 
      end do
 
      end

*dk vscale
      subroutine vscale(v,u,scale,nn)
 
c...  This routine multiplies the field u by the factor scale
c...  and loads the result in v.
 
      real v(*), u(*)
 
      do ii=1,nn
         v(ii) = scale*u(ii)
      end do
 
      end
*dk xntolatlong
      subroutine xntolatlong(f,xn)
 
c...  This routine converts xyz values of array xn to
c...  lat/long values for each node on the unit-sphere.
c...  Note: If alpha is the angular value in radians,
c...  then the angular value beta in degrees is alpha*(180/pi).
 
      include 'size.h'
      real f((nt+1)**2,nd,2), xn((nt+1)**2,nd,3)
      real pi, convert
 
      pi      = 3.141592653589793
      convert = 180./pi
 
      do id=1,nd
         do ii=1,(nt+1)**2
c...        LATITUDE:
            f(ii,id,1) = convert*asin(xn(ii,id,3))
c...        LONGITUDE:
            f(ii,id,2) = convert*atan(xn(ii,id,2)
     &                              /(xn(ii,id,1) + 1.e-20))
         end do
      end do
 
      end

c =============================================================================

      blockdata bdutlity
 
      common /rttn/ phi(10), trtn(3,3,10)
      data phi/ 0.0,
     &  1.2566370614359173, 2.5132741228718346,-2.5132741228718346,
     & -1.2566370614359173,-2.5132741228718346,-1.2566370614359173,
     &                 0.0, 1.2566370614359173, 2.5132741228718346/
      data trtn/90*0./
 
      end blockdata

c =============================================================================
c Timing routine
c =============================================================================

*dk mytime
      subroutine mytime( time )

      real time
      real*4 etime, tin(2)

      time = etime(tin)

      end subroutine
