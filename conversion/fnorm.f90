program fnorm
implicit none

include 'size.h'
include 'pcom.h'

integer xxx, psp, byebye, idump, pro, ir_beg, ir_end
integer i,j,k,ir, id, ii,locsize, maxls, tzt, nproc2
integer x,y,z, nbin, ibin, indx, ind(nr+1)

integer, parameter:: nn=(nt+1)**2*nd      
integer, parameter:: mm=(mt+1)**2*nd
integer, parameter:: lmax=50

real, parameter:: PI = 3.141592653589793
real, parameter:: RHOAV = 5514.3d0		 ! average density in the full Earth to normalize equation
real, parameter:: GRAV = 6.6723d-11		 ! gravitational constant

! all vectors are "real" because of the very large size
real rshl(nr+1)

real, allocatable:: s_ges(:,:), s1(:,:), s2(:,:), shar_T(:,:,:)
real vp(1,nn), vs(1,nn), rho(1,nn), depth_crit, depth_cut
real depth(nr+1), meantemp(129), meantemp_bs(129), mnb
real rmax(129), rmax_loop(129), rmax_loop_proc(129)
real val_pos, val_neg, val, R_min, R_max, quot
real T_norm, T_norm_loop, lbeg, lend, temp, rmean_T(nr+1)

 character*2 cstage1, cstage2, iter
 character*4 cname1, cname2, char1
 character*100 gpath1, gpath2
 character*14 fname1, fname2
 
! ################################################
! ################# MAIN PART #######################
! ################################################

common /mtemp/ meantemp, meantemp_bs
      
! Initialize parallel communications.
      
 CALL MPI_INIT(ierr)
 CALL MPI_COMM_RANK(MPI_COMM_WORLD, myid2, ierr)
 CALL MPI_COMM_SIZE(MPI_COMM_WORLD, nproc2, ierr)
nproc=(mt/nt)**2*10/nd
lvproc = 1.45*log(real(mt/nt))
mproc = 2**(2*lvproc)

ir=1
do while(ir==1)
ir=1
enddo
 
allocate(s1(nn*(nr+1),nproc/nproc2),s2(nn*(nr+1),nproc/nproc2))
allocate(s_ges(nn*(nr+1),nproc/nproc2))
allocate(shar_T(2,(lmax+1)*(lmax+2)/2,nr+1))

R_max=6370.0 
R_min=3480.0
ir_beg=1
ir_end=1

lbeg=0.0
lend=3000.0

do ir=1,nr+1
	rshl(ir)=6370.0-(R_min+(R_max-R_min)*real(nr+1-ir)/real(nr))
	if(lbeg-rshl(ir)>=0) ir_beg=ir
	if(lend-rshl(ir)>=0) ir_end=ir
enddo

if(myid2==0) write(*,*) ir_beg, ir_end

if(myid2==0) open(314,file='resid.dat',status='replace')
! multiple conversion

gpath2='/SCRATCH/horbach/TERRA0512_mt512/tomo/'
 cname2="tomo"
 cstage2="00"

do psp=3,3

if(psp==1) then
gpath1='../TERRA_TOMOBLANK/dat-files_BLANK/'
 cname1="0500"
 cstage1="10"
 byebye=14
 
else if(psp==2) then
gpath1='../TERRA_TOMOSHIFT/dat-files/'
 cname1="0500"
 cstage1="10"
byebye=8

else if(psp==3) then
gpath1='/SCRATCH/horbach/354/c-files/'
 cname1="c354"
 cstage1="20"
byebye=1

else if(psp==4) then
gpath1='../TERRA512_backw/c-files/'
 cname1="c125"
 cstage1="10"
 byebye=1
endif

do xxx=1,byebye
	
T_norm=0.0
T_norm_loop=0.0

do pro=1,nproc/nproc2
	
	myid=myid2*nproc/nproc2+pro-1
 	write(char1,'(I4.4)') myid
	
	idump=xxx-1
		
	write(iter,'(i2.2)') idump

      if(psp==1.or.psp==2) then
      
      	! read in sh coefficients of dat-files
      	fname1=cname1//'_50_'//iter//'.dat'
      
		open(120,file=trim(gpath1)//trim(fname1),status='unknown')
		
		read(120,*) temp
      	do i=1,(nr+1)*(2+(lmax+1)*(lmax+2)/2)
      		read(120,*) temp
      	enddo
		do i=1,nr+1
			read(120,*) rmean_T(i)
		enddo
		read(120,*) shar_T
		close(120)
	
		! generate T on TERRA grid from sh coefficients
		call MPI_BARRIER(MPI_COMM_WORLD,ierr)
		call gridinit
		call shtofe(s1(:,pro),shar_T,lmax)
		
		k=1
		do ir=1,nr+1
		do id=1,nd
		do ii=1,(nt+1)**2
			s1(k,pro)=(s1(k,pro)+1.0)*rmean_T(ir)
			k=k+1
		enddo
		enddo
		enddo
 
 	else
 	
 	if(xxx>410) then
      	fname1 = 'a'//cname1//'.'//char1//'.'//cstage2
      	open(188, file=trim(gpath1)//'/output/'//trim(fname1), form='unformatted', status='unknown')

     		call vecinunform44(s2(:,pro),188)
        else
         	fname1=cname1//'.'//char1//'.'//cstage1
         	
   	  	open(188, file=trim(gpath1)//trim(fname1)//'_'//iter, form='formatted', status='unknown')
    		call vecin11(s1(:,pro),188,1)
  
	endif
	endif
	
	fname2=cname2//'.'//char1//'.'//cstage2
	open(189, file=trim(gpath2)//trim(fname2), form='formatted', status='unknown')
	call vecin11(s2(:,pro),189,1)
	
	call MPI_BARRIER(MPI_COMM_WORLD,ierr)
	close(188)
	close(189)
	
	s_ges(:,pro)=s2(:,pro)-s1(:,pro)

	call MPI_BARRIER(MPI_COMM_WORLD,ierr)
	call sum_sqrt(s_ges(:,pro),T_norm_loop,ir_beg,ir_end)

	T_norm=T_norm+T_norm_loop

enddo !proc

T_norm=sqrt(T_norm)

 call MPI_BARRIER(MPI_COMM_WORLD,ierr)
 
if(myid2==0) then
	write(314,*) T_norm
	write(*,*) T_norm
endif  
	
enddo		! multiple
if(myid2==0) then
	write(314,*)
	write(*,*)
endif 
enddo		! conversion
 
! leave parallel communication before exiting
if(myid2== 0) then
	close(314)
	write(*,*)
	write(*,*) "Servus!"
endif
 call MPI_FINALIZE(ierr)

end program fnorm


! ########################################################
! ############# SUBROUTINES #################################
! ########################################################
  
subroutine sum_sqrt(s,sum_s,ir_beg,ir_end)
implicit none

include 'size.h'
include 'pcom.h'

integer k, ir, id, ii, ir_beg, ir_end
real s((nt+1)**2*nd*(nr+1))
real sum_s_pro, sum_s

k=(ir_beg-1)*nd*(nt+1)**2+1
sum_s=0.0
sum_s_pro=0.0

do ir=ir_beg,ir_end	
	do id=1,nd
		do ii=1,(nt+1)**2
			sum_s_pro=sum_s_pro+s(k)*s(k)
			k=k+1
		enddo
	enddo
enddo
	
sum_s_pro=sum_s_pro/((ir_end-ir_beg+1)*nproc*nd*(nt+1)**2)
	
 call MPI_BARRIER(MPI_COMM_WORLD,ierr)
 call MPI_REDUCE(sum_s_pro,sum_s,1,MPI_REAL8,MPI_SUM,0,MPI_COMM_WORLD,ierr)
 call MPI_BCAST(sum_s,1,MPI_REAL8,0,MPI_COMM_WORLD,ierr)
 call MPI_BARRIER(MPI_COMM_WORLD,ierr)

end subroutine sum_sqrt
	
	
! ########################################################
subroutine rad_mean(s,rm)
implicit none

include 'size.h'
include 'pcom.h'

integer k, ir, id, ii
real s((nt+1)**2*nd*(nr+1))
real rmean(nr+1), rm(nr+1)

k=1
rmean=0.0

do ir=1,nr+1	
	do id=1,nd
		do ii=1,(nt+1)**2
			rmean(ir)=rmean(ir)+s(k)
			k=k+1
		enddo
	enddo
enddo
	
rmean=rmean/nd/(nt+1)**2/nproc
	
 call MPI_BARRIER(MPI_COMM_WORLD,ierr)
 call MPI_REDUCE(rmean,rm,nr+1,MPI_REAL8,MPI_SUM,0,MPI_COMM_WORLD,ierr)
 call MPI_BCAST(rm,(nr+1),MPI_REAL8,0,MPI_COMM_WORLD,ierr)
 call MPI_BARRIER(MPI_COMM_WORLD,ierr)

end subroutine rad_mean


! ########################################################
subroutine vecinunform44(u,nf)
implicit none
!...  This routine reads the nodal field u from logical unit nf
!     using unformated I/O and without any additional information.
 
      include 'size.h'
      include 'pcom.h'
      
      integer i, nf
      real u((nt+1)**2*nd*(nr+1))
 	
	read(nf) (u(i),i=1,(nt+1)**2*nd*(nr+1))
 	
end subroutine vecinunform44
      
     
! ########################################################
subroutine vecin11(u,nf,nj)
implicit none
!...  This routine reads the nodal field u from logical unit nf
!...  using 1p,e10.3 format when ifmt = 0 and f10.3 when ifmt = 1.
 
      include 'size.h'
      include 'pcom.h'
      
      integer kr, kt, ii, nj, nf
      real u((nt+1)**2*nd*nj*(nr+1)), rshl(nr+1), propr(20)
      common /prty/ propr
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
 
      read(nf,30) (rshl(ii),ii=1,nr+1)
      read(nf,30) propr
 30   format(1p10e15.8)
 
         read(nf,50) (u(ii),ii=1,(nt+1)**2*nd*nj*(nr+1))
50      format(15f10.3)

end subroutine vecin11

 
! #####################################################
! ############# SUBROUTINE read_MP_DATA ###### ##############
! #####################################################
	subroutine read_MP_DATA
	implicit none

	include 'min.h'
	
      if(MP_TYP=='A') then
! Antonio`s MP dataset is used
      	call read_MP_DATA_Antonio
      elseif (MP_TYP=='S') then
! Lars Stixrude`s MP dataset is used
      	call read_MP_DATA_Stixrude
      else
      	write(*,*) "Desired mineralogical model not available!"
      	return
      endif

	end subroutine read_MP_DATA


! #####################################################
! ############# SUBROUTINE read_MP_DATA_Stixrude ##############
! #####################################################
	subroutine read_MP_DATA_Stixrude
	implicit none
	
	include 'min.h'
	
	integer i

	real ttt(nT_S), depth_S(nD_S), temp_S(nT_S), vs_S(nD_S, nT_S)
	real vsvprho_S(3,nD_S,nT_S), rho_S(nD_S, nT_S)
	real vp_S(nD_S, nT_S)

	character MP_dir*150
	
	common /mine_S/ depth_S, temp_S, vsvprho_S
		 
	if(comp=='PYROLITE') then
		MP_dir='../MP_DATA/MP_Stixrude/Pyrolite'
	elseif(comp=='PICLOGITE') then
		MP_dir='../MP_DATA/MP_Stixrude/Piclogite'
	else
		write(*,*) "Desired composition not available!"
		return
	endif

	open(unit=803,file=trim(MP_dir)//'/MP_Stixrude_Pyrolite_depth.dat',action='read',status='old')
	open(unit=804,file=trim(MP_dir)//'/MP_Stixrude_Pyrolite_T.dat',action='read',status='old')
	open(unit=805,file=trim(MP_dir)//'/MP_Stixrude_Pyrolite_vs.dat',action='read',status='old')
	open(unit=806,file=trim(MP_dir)//'/MP_Stixrude_Pyrolite_vp.dat',action='read',status='old')
	open(unit=807,file=trim(MP_dir)//'/MP_Stixrude_Pyrolite_rho.dat',action='read',status='old')

	read(804,*) temp_S

	do i=1,nD_S
		read(803,*) depth_S(i)
		read(805,*) ttt
	  	vs_S(i,:)=ttt
		read(806,*) ttt
	 	vp_S(i,:)=ttt
		read(807,*) ttt
	  	rho_S(i,:)=ttt 
	enddo

	 close(803)
	 close(804)
	 close(805)
	 close(806)
	 close(807)

	! convert km in m and km/s in m/s
	depth_S=depth_S*1e3
	vsvprho_S(1,:,:)=vp_S*1e3
	vsvprho_S(2,:,:)=vs_S*1e3
	vsvprho_S(3,:,:)=rho_S*1e3


	end subroutine read_MP_DATA_Stixrude


! #####################################################
! ############# SUBROUTINE read_MP_DATA_Antonio ###############
! #####################################################
	subroutine read_MP_DATA_Antonio
	implicit none

	include 'min.h'

      integer i,j

	real depth_A(nD_A), temp_A(nT_A), K_A(nD_A, nT_A)
	real vsvprho_A(3,nD_A,nT_A), rho_A(nD_A,nT_A)
	real xxx, G_A(nD_A, nT_A)
     
	common /mine_A/ depth_A, temp_A, vsvprho_A

	 character MP_dir*150

	if(comp=='PYROLITE') then
		MP_dir='../MP_DATA/MP_Antonio/Pyrolite'
	elseif(comp=='PICLOGITE') then
		MP_dir='../MP_DATA/MP_Antonio/Piclogite'
	else
		write(*,*) "Desired composition not available!"
		return
	endif

	open(unit=804,file=trim(MP_dir)//'/MP_Antonio_Pyrolite_Depth.dat',status='old')
	do i=1,nD_A
	read(804,*) depth_A(i)
	enddo
	close(unit=804)

	open(unit=804,file=trim(MP_dir)//'/MP_Antonio_Pyrolite_T.dat',status='old')
	read(804,*) (temp_A(i),i=1,nT_A)
	close(unit=804)

	open(unit=804,file=trim(MP_dir)//'/MP_Antonio_Pyrolite_G.dat',status='old')
	do j=1,nD_A
	read(804,*) (G_A(j,i),i=1,nT_A)
	enddo
	close(unit=804)

	open(unit=804,file=trim(MP_dir)//'/MP_Antonio_Pyrolite_K.dat',status='old')
	do j=1,nD_A
	read(804,*) (K_A(j,i),i=1,nT_A)
	enddo
	close(unit=804)

	open(unit=804,file=trim(MP_dir)//'/MP_Antonio_Pyrolite_rho.dat',status='old')
	do j=1,nD_A
	read(804,*) (rho_A(j,i),i=1,nT_A)
	enddo
	 close(unit=804)

	! convert km in m, GPa in Pa, 1e3 kg/m^3 in kg/m^3 and km/s in m/s
	depth_A=depth_A*1e3
	G_A=G_A*1e9
	K_A=K_A*1e9
	rho_A=rho_A/1e3

	do i=1,nD_A
	do j=1,nT_A

	xxx=G_A(i,j)/rho_A(i,j)
	if(xxx<0) xxx=0
	vsvprho_A(1,i,j)=sqrt((K_A(i,j) + 4./3.*G_A(i,j))/rho_A(i,j))
	vsvprho_A(2,i,j)=sqrt(xxx)
	vsvprho_A(3,i,j)=rho_A(i,j)

	enddo
	enddo

	end subroutine read_MP_DATA_Antonio


! #####################################################
! ################## SUBROUTINE convert_T ###################
! #####################################################
subroutine convert_T(dpth,size_D,temp_cv,size_T,vp_new,vs_new,rho_new)
! This routine converts temperatures stored in array temp_cv at given depths dpth
! into vp, vs and density.
	
	include 'min.h'
	
	common /mine_A/ depth_A(nD_A), temp_A(nT_A), vsvprho_A(3,nD_A,nT_A)
	common /mine_S/ depth_S(nD_S), temp_S(nT_S), vsvprho_S(3,nD_S,nT_S)
	
	integer i, size_D, size_T
	
	real dpth(size_D), temp_cv(size_T), rho_new(size_D,size_T)
	real vp_new(size_D,size_T), vs_new(size_D,size_T)
	
	real, allocatable:: mat_tmp(:,:)
	real mat_interpol(size_D, size_T)
	
	do i=1,3
		if(MP_TYP=='A') then
			allocate(mat_tmp(nD_A,nT_A))
			mat_tmp=vsvprho_A(i,:,:)
			call interp_2D(depth_A, nD_A, temp_A, nT_A, mat_tmp,dpth, size_D, temp_cv, size_T, mat_interpol)
    		else if(MP_TYP=='S') then
    			allocate(mat_tmp(nD_S,nT_S))
    			mat_tmp=vsvprho_S(i,:,:)
			call interp_2D(depth_S, nD_S, temp_S, nT_S, mat_tmp, dpth, size_D, temp_cv, size_T, mat_interpol)
     		endif
     		deallocate(mat_tmp)
		if(i==1) vp_new=mat_interpol/1000.0
		if(i==2) vs_new=mat_interpol/1000.0
		if(i==3) rho_new=mat_interpol/1000.0
	enddo

end subroutine convert_T


! #####################################################
! ################### SUBROUTINE interp_2D ##################
! #####################################################
	subroutine interp_2D(x_cur,nx,y_cur,ny,mat_cur, x_vec,nx_v,y_vec,ny_v,mat_new)
	implicit none	
	
	integer i,j
	integer nx, ny, nx_v, ny_v
	integer x1, x2, y1, y2
	
	real x_cur(nx), y_cur(ny), mat_cur(nx,ny)
	real x_vec(nx_v), y_vec(ny_v), mat_new(nx_v,ny_v)
	real f_x, f_y, frac
	
	do i=1,nx_v
		call hunt(x_cur,nx,x_vec(i),x1)
		if(x1==0.or.x1==nx) write(*,*) x_vec(i), x1, "X-PROBLEM!!!!!!!!"
		x2=x1+1
		frac=(x_vec(i)-x_cur(x1))/(x_cur(x2)-x_cur(x1))
		do j=1,ny_v
			call hunt(y_cur,ny,y_vec(j),y1)
			if(y1==0.or.y1==ny) write(*,*) y_vec(j), y1, "Y-PROBLEM!!!!!!!!"
			y2=y1+1
			
			f_x=mat_cur(x1,y1)+(mat_cur(x2,y1)-mat_cur(x1,y1))*frac
    			f_y=mat_cur(x1,y2)+(mat_cur(x2,y2)-mat_cur(x1,y2))*frac
  
     			mat_new(i,j)=f_x+(f_y-f_x)*(y_vec(j)-y_cur(y1))/(y_cur(y2)-y_cur(y1))
		enddo
	enddo

	end subroutine interp_2D


! #####################################################
! ################### SUBROUTINE hunt #####################
! #####################################################
	subroutine hunt(x_vec,n,x,jlo)
	implicit none
	
	integer n, jlo, jhi, jnew
	real x_vec(n), x
	
	jlo=1
	jhi=n
	if(x>x_vec(n)) then
		jlo=n
	else if(x<x_vec(1)) then
		jlo=0
	else
		do while(jhi-jlo>1)
			jnew=floor(real(jlo+jhi)/2.0)
			if(x<=x_vec(jnew)) then
				jhi=jnew
			else
				jlo=jnew
			endif
		enddo
	endif
	
	end subroutine hunt



subroutine fetosh(s_tmp,shar,lmax)
!implicit none

! This sub-routine computes the coefficients of the spherical harmonics
! expansion of a given 3D grid function. The expansion is performed for each
! layer of the radial discretisation.
! \param lun  Logical Unit Number for the output file to which the computed
!             coefficients will be appended. IO is only performed by the MPI
!             process with rank 0.
! \param s    Array containing the values of the scalar function for which the
!             expansion is to be computed
! \param shar used for storing the computed coefficients (work array, or
!             INTENTOUT?)
 
!...  This routine generates spherical harmonic coefficients
		
      include 'size.h'
      include 'pcom.h'
      integer lmax, ir, id, ii, k, l, m
      real s_tmp((nt+1)**2*nd*(nr+1)), smax, r4pi, a0, phi
      real s((nt+1)**2,nd,nr+1), shar(2,(lmax+1)*(lmax+2)/2,nr+1)
      real plm((lmax+1)*(lmax+2)), csm(0:128,2)
      real shar_tmp((lmax+1)*(lmax+2)*(nr+1))
      real shar_tmp2((lmax+1)*(lmax+2)*(nr+1))
      
      common /mesh/ xn((nt+1)**2,nd,3)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),&
     &              rarn((nt+1)**2), rarne((nt+1)**2)
 
      smax = 0.
      r4pi = 0.125/asin(1.)
 
      shar=0.0
      
      k=0
	do ir=1,nr+1
		do id=1,nd
			do ii=1,(nt+1)**2
				k=k+1
				s(ii,id,ir)=s_tmp(k)
			enddo
		enddo
	enddo

!     This 'hack' fixes a problem in the use of arn in the loop below.
!     The loop runs over all nodes in the local sub-domain. However, Terra
!     employs an element-oriented domain decomposition. Thus, nodes along the
!     subdomain edges belong to several subdomains. arn stores zeros along the
!     upper right and lower right edge. In this fashion we can avoid multiple
!     contributions from different subdomains from the loop below, when doing
!     psumlong in the end of this routine. However, those process(es) to whose
!     subdomain(s) the north and south poles belong stores the area associated
!     with those nodes. Thus, we get five contributions from these nodes.
!     We correct this by scaling the corresponding area value in arn.
!     The hack must be undone again before leaving the routine. Otherwise
!     inconsistencies might occur in other parts of the code.
if(myid==0.OR.(nd .EQ. 5 .AND. myid .EQ. nproc/2)) THEN
         arn(1) = arn(1) / 5.
endif
     
do ii=1,(nt+1)**2
         a0 = r4pi*arn(ii)
         do id=1,nd
            phi = atan2(xn(ii,id,2) + 1.e-30, xn(ii,id,1))
            do m=0,lmax
               csm(m,1) = cos(m*phi)
               csm(m,2) = sin(m*phi)
            enddo
 
            if(mod(id, 5) .eq. 1) call plmbar(plm,plm,lmax,xn(ii,id,3),0)
		k=0
            do l=0,lmax
               do m=0,l
                  k=k+1
                  do ir=1,nr+1
                     aa = a0*plm(k)*s(ii,id,ir)
                     shar(1,k,ir) = shar(1,k,ir) + aa*csm(m,1)
                     shar(2,k,ir) = shar(2,k,ir) + aa*csm(m,2)
                  enddo
                enddo
            enddo
	enddo
enddo

! Undo 'hack' by re-setting arn to original value
if(myid .EQ. 0 .OR. (nd .EQ. 5 .AND. myid .EQ. nproc/2)) THEN
         arn(1) = arn(1) * 5.
endif

k=0
do ir=1,nr+1
	do i=1,2
		kk=0
		do l=0,lmax
			do m=0,l
				k=k+1
				kk=kk+1
				shar_tmp(k)=shar(i,kk,ir)
			enddo
		enddo
	enddo
enddo

 call MPI_BARRIER(MPI_COMM_WORLD,ierr)
 call MPI_REDUCE(shar_tmp,shar_tmp2,(lmax+1)*(lmax+2)*(nr+1),MPI_REAL8,MPI_SUM,0,MPI_COMM_WORLD,ierr)
 call MPI_BARRIER(MPI_COMM_WORLD,ierr)
 
if(myid2==0) then
   k=0
	do ir=1,nr+1
		do i=1,2
			kk=0
			do l=0,lmax
				do m=0,l
					k=k+1
					kk=kk+1
					shar(i,kk,ir)=shar_tmp2(k)
				enddo
			enddo
		enddo
	enddo
endif

end subroutine


subroutine pbar(c,l,m,p)
 
!...  This routine calculates the value of the normalized associated
!...  Legendre function of the first kind of degree l and order m
!...  for the real argument c, for 0 .le. m .le. l.
 
      sqrt2 = 1.414213562373092
 
      if(m .ne. 0) then
         p = sqrt2
         s = sqrt(1. - c**2)
         do i=1,m
            p = sqrt(real(2*i + 1)/real(2*i))*s*p
         end do
      else
         p = 1.
      endif
 
      if(l .eq. m) return
 
      p1 = sqrt2
      do j=m+1,l
         p2 = p1
         p1 = p
         p  = 2.*sqrt((real(j**2) - 0.25)/real(j**2 - m**2))*c*p1&
     &         - sqrt (real((2*j + 1)*(j - m - 1)*(j + m - 1))&
     &                /real((2*j - 3)*(j - m)*(j + m)))*p2
      end do
 end


subroutine plmbar(p,dp,lmax,z,ideriv)
!    Evaluates normalized associated Legendre function P(l,m) as
!    function of z=cos(colatitude); also derivative dP/d(colatitude).
!    Uses recurrence relation starting with P(l,l) and then increasing
!    l keeping m fixed.  Normalization is:
!                  Integral(Y(l,m)*Y(l,m)) = 4.*pi,
!                  where Y(l,m) = P(l,m)*exp(i*m*longitude),
!    which is incorporated into the recurrence relation. p(k) contains
!    p(l,m) with k=(l+1)*l/2+m+1; i.e. m increments through range 0 to
!    l before incrementing l. Routine is stable in single and double
!    precision to l,m = 511 at least; timing is proportional to lmax**2
!    R.J.O'Connell 7 Sept. 1989; added dp(z) 10 Jan. 1990
!
!    Added precalculation and storage of square roots srl(k) 31 Dec 1992

	integer, parameter:: lmaxx=100
      dimension p(*),dp(*)
!     --dimensions must be p((lmax+1)*(lmax+2)/2) in calling program
 
      common /plm0/   f1((lmaxx+1)*(lmaxx+2)/2),&
     &                f2((lmaxx+1)*(lmaxx+2)/2),&
     &              fac1((lmaxx+1)*(lmaxx+2)/2),&
     &              fac2((lmaxx+1)*(lmaxx+2)/2), srt(2*lmaxx+2)
      data ifirst /1/
      save ifirst
 
      if (lmax.lt.0.or.abs(z).gt.1.) stop 'bad arguments'
!     --set up sqrt and factors on first pass
      if(ifirst.eq.1) then
          ifirst = 0
          do k=1,2*lmax+2
            srt(k) = sqrt(real(k))
         end do
 
         if (lmax .eq. 0) then
            p(1) = 1.0
            if(ideriv .ne. 0) dp(1) = 0.
            return
         end if

!        --case for m > 0
          kstart = 1
         do m=1,lmax
!        --case for P(m,m)
             kstart = kstart + m + 1
            if(m .ne. lmax) then

!              --case for P(m+1,m) 
               k = kstart + m + 1
 
!              --case for P(l,m) with l > m+1
               if(m .lt. lmax-1) then
                  do l=m+2,lmax
                     k = k + l
                     f1(k) =  srt(2*l+1)*srt(2*l-1)/(srt(l+m)*srt(l-m))
                     f2(k) = (srt(2*l+1)*srt(l-m-1)*srt(l+m-1))&
     &                      /(srt(2*l-3)*srt(l+m)*srt(l-m))
                  end do
               end if
            end if
         end do
 
         k = 3
 
         do l=2,lmax
            k = k + 1
            do m=1,l-1
               k = k + 1
               fac1(k) = srt(l-m)*srt(l+m+1)
               fac2(k) = srt(l+m)*srt(l-m+1)
               if(m .eq. 1) fac2(k) = fac2(k)*srt(2)
            end do
            k = k + 1
         end do
 
      end if
 
!     --start calculation of Plm, etc.
 
!     --case for P(l,0)
 
      pm2   = 1.
      p(1)  = 1.
      if(ideriv .ne. 0) dp(1) = 0.
 
      if(lmax .eq. 0) return
 
      pm1   = z
      p(2)  = srt(3)*pm1
      k     = 2
 
      do l=2,lmax
         k = k + l
         plm  = (real(2*l-1)*z*pm1 - real(l-1)*pm2)/real(l)
         p(k) =   srt(2*l+1)*plm
         pm2  =   pm1
         pm1  =   plm
      end do
 
!    --case for m > 0
 
      pmm    =  1.
      sintsq = (1.-z)*(1.+z)
      fnum   = -1.
      fden   =  0.
      kstart =  1
 
      do m=1,lmax
 
!        --case for P(m,m)
 
         kstart = kstart + m + 1
         fnum   = fnum + 2.
         fden   = fden + 2.0
         pmm    = pmm*sintsq*fnum/fden
         pm2    = sqrt(real(4*m+2)*pmm)
         p(kstart) = pm2
 
         if(m .ne. lmax) then
 
!           --case for P(m+1,m)
 
            pm1  = z*srt(2*m+3)*pm2
            k    = kstart + m + 1
            p(k) = pm1
 
!           --case for P(l,m) with l > m+1
 
            if(m .lt. lmax-1) then
 
               do l=m+2,lmax
                  k    = k + l
!                 f1   =  srt(2*l+1)*srt(2*l-1)/(srt(l+m)*srt(l-m))
!                 f2   = (srt(2*l+1)*srt(l-m-1)*srt(l+m-1))
!     &                 /(srt(2*l-3)*srt(l+m)*srt(l-m))
                  plm  = z*f1(k)*pm1 - f2(k)*pm2
                  p(k) = plm
                  pm2  = pm1
                  pm1  = plm
               end do
            endif
         endif
      end do
 
      if(ideriv .eq. 0) return
 
!     ---derivatives of P(z) wrt theta, where z=cos(theta)
      dp(2) = -p(3)
      dp(3) =  p(2)
      k     =  3
 
      do l=2,lmax
         k = k + 1

!        --treat m=0 and m=l separately
         dp(k)   = -srt(l)*srt(l+1)/srt(2)*p(k+1)
         dp(k+l) =  srt(l)/srt(2)*p(k+l-1)
 
            do m=1,l-1
               k     = k + 1
               dp(k) = 0.5*(fac2(k)*p(k-1) - fac1(k)*p(k+1))
            enddo
         k = k + 1
      end do
end
 
 
subroutine gridinit
!...  This routine initializes all arrays in common blocks /radl/,
!...  /mesh/, /ndar/, /volm/, and /xnex/.
 
      include 'size.h'
      include 'pcom.h'
      parameter (nxm=4000+(nt+1)**2*41)
      parameter (nopr=(nt/2+1)**2*ndo*189*(nr/2+1)*7/5+8000)
      common /fopr/ a(nopr+nv*ndo/nd*9+nv*ndo/nd*18*5/4),&
     &              mopr(0:10), mb(0:10)
      common /grid/ mxm(0:10), xm(nxm)
      common /mesh/ xn((nt+1)**2,nd,3)
      common /ndar/  arn((nt+1)**2),  arne((nt+1)**2),&
     &              rarn((nt+1)**2), rarne((nt+1)**2)
      common /radl/ rshl(nr+1), ird, ibc
      common /volm/ vol((nt+1)**2*(nr+1),2)
      common /xnex/ xne((nt+3)**2*nd*3)

!...  Generate nodal coordinate array xn for finest level. (This
!...  duplicates part of array xm, but is done for convenience
!...  because xn does not require use of a pointer.)
 
      mm = (mt + 1)**2
      m0 = mm*30 + 1
 
      call grdgen(a,mt)
 
      if(nproc .eq. 1) then
         call scopy((mt+1)**2*30, a, 1, xn, 1)
      else
         call subarray(a,xn,0,10,nd,mt,nt,3)
      endif
 
!...  Generate the nodal area arrays.
 
      call ndarea(a(m0),a(m0+mm),a(m0+2*mm),a(m0+3*mm),a(m0+4*mm),a,mt)
 
      if(nproc .eq. 1) then
         call scopy((mt+1)**2, a(m0), 1, arn, 1)
         call scopy((mt+1)**2, a(m0+mm), 1, arne, 1)
         call scopy((mt+1)**2, a(m0+2*mm), 1, rarn, 1)
         call scopy((mt+1)**2, a(m0+3*mm), 1, rarne, 1)
      else
         call subarray(a(m0),     arn,  1,1,1,mt,nt,1)
         call subarray(a(m0+mm),  arne, 0,1,1,mt,nt,1)
         call subarray(a(m0+2*mm),rarn, 1,1,1,mt,nt,1)
         call subarray(a(m0+3*mm),rarne,0,1,1,mt,nt,1)
      endif
 
 end

subroutine subarray(a,ap,ibctype,kd,kdp,kt,ktp,nc)
!...  This routine reads the appropriate portion of the global array
!...  a into the sub-array ap needed for process myid.  Array a has
!...  dimensions (kt+1,kt+1,kd,nc) and ibctype specifies the type of
!...  boundary conditions to be applied along subdomain edges.  For
!...  ibctype = 0, none of the edge elements are set to zero; for
!...  ibctype = 1, all of the edge elements are set to zero; and for
!...  ibctype = 2, array ap is treated as a 7-point stencil and edge
!...  node components outside the subdomain are set to zero.
 
      include 'size.h'
      include 'pcom.h'
      real a(kt+1,kt+1,kd,nc), ap(ktp+1,ktp+1,kdp,nc)
 
!...  Determine subdomain limits.
 
      npedg = 2**lvproc
      iproc = mod(myid, mproc)
      rnm   = 1./real(npedg)
      j0    = iproc*rnm
      i0    = (real(iproc)*rnm - j0)/rnm
 
      ibeg  = i0*ktp + 1
      jbeg  = j0*ktp + 1
      iend  = ibeg + ktp
      jend  = jbeg + ktp
 
!...  Load sub-array.
 
      do ic=1,nc
         do id=1,kdp
            jd = id
            if(kdp.eq.5 .and. myid.ge.mproc) jd = id + 5
            j = 0
            do jj=jbeg,jend
               j = j + 1
               i = 0
               do ii=ibeg,iend
                  i = i + 1
                  ap(i,j,id,ic) = a(ii,jj,jd,ic)
               enddo
            enddo
         enddo
      enddo
 
!...  Apply boundary conditions.
 
      if(ibctype .eq. 0) return
 
      if(ibctype .eq. 1) then
         k  = ktp + 1
         i1 = 1
         if(iproc .eq. 0) i1 = 2
 
         do ic=1,nc
            do id=1,kdp
               do i=i1,ktp+1
                  ap(1,i,id,ic) = 0.
                  ap(i,k,id,ic) = 0.
               end do
            end do
         end do
      elseif(ibctype .eq. 2) then
         call subarraybc(ap,nc/7,ktp)
      endif
end subroutine


subroutine subarraybc(ap,nc,kt)
!...  This routine sets to zero the appropriate stencil components
!...  along the sub-domain boundaries for the operator ap.  The flag
!...  idiamond, when set to one, causes redundant components on the
!...  diamond edges to be set to zero.
 
      include 'size.h'
      include 'pcom.h'
      real ap(kt+1,kt+1,7,nc)
 
      k     = kt + 1
      npedg = 2**lvproc
      iproc = mod(myid, mproc)
      i0    = 1
      if(iproc .eq. 0) i0 = 2
 
      do j=1,nc
         do i=i0,kt+1
 
!...        Treat upper right edge.
            ap(1,i,4,j) = 0.
            ap(1,i,5,j) = 0.
 
            if(mod(iproc, npedg) .ne. 0) then
               ap(1,i,1,j) = 0.
               ap(1,i,3,j) = 0.
               ap(1,i,6,j) = 0.
            endif
 
!...        Treat upper left edge.
            ap(i,1,6,j) = 0.
            ap(i,1,7,j) = 0.
         enddo
 
         do i=1,kt+1
 
!...        Treat lower left edge.
            ap(k,i,2,j) = 0.
            ap(k,i,7,j) = 0.
 
!...        Treat lower right edge.
            ap(i,k,3,j) = 0.
            ap(i,k,4,j) = 0.
 
            if(iproc .le. mproc-1-npedg) then
               ap(i,k,1,j) = 0.
               ap(i,k,2,j) = 0.
               ap(i,k,5,j) = 0.
            endif
 
         enddo
      enddo
 end
 
 
subroutine scopy(nn,vin,iin,vout,iout)
 
!     This routine copies array vin into array vout.
      real vout(*), vin(*)
 
      do 10 ii=1,nn-2,3
      vout(ii)   = vin(ii)
      vout(ii+1) = vin(ii+1)
      vout(ii+2) = vin(ii+2)
 10   continue
 
      do 20 ii=3*(nn/3)+1,nn
      vout(ii)   = vin(ii)
 20   continue
end


subroutine grdgen(xn,nt)
!...  This routine generates the nodal coordinates xn for an
!...  icosahedral grid on the unit sphere.  The grid resolution
!...  corresponds to a subdivision of the edges of the original
!...  icosahedral triangles into nt equal parts.
 	
      real xn(nt+1,nt+1,10,3)
 
      fifthpi = 0.4*asin(1.)
      w       = 2.0*acos(1./(2.*sin(fifthpi)))
      cosw    = cos(w)
      sinw    = sin(w)
      lvt     = 1.45*log(real(nt))
      nn      = (nt+1)**2*10
 
      do id=1,10
 
         sgn = 1.
         if(id .ge. 6) sgn = -1.
         phi = (2*mod(id, 5) - 3 + (id - 1)/5)*fifthpi
 
         xn(   1,   1,id,1) =  0.
         xn(   1,   1,id,2) =  0.
         xn(   1,   1,id,3) =  sgn
         xn(nt+1,   1,id,1) =  sinw*cos(phi)
         xn(nt+1,   1,id,2) =  sinw*sin(phi)
         xn(nt+1,   1,id,3) =  cosw*sgn
         xn(   1,nt+1,id,1) =  sinw*cos(phi + fifthpi + fifthpi)
         xn(   1,nt+1,id,2) =  sinw*sin(phi + fifthpi + fifthpi)
         xn(   1,nt+1,id,3) =  cosw*sgn
         xn(nt+1,nt+1,id,1) =  sinw*cos(phi + fifthpi)
         xn(nt+1,nt+1,id,2) =  sinw*sin(phi + fifthpi)
         xn(nt+1,nt+1,id,3) = -cosw*sgn
 
         do k=0,lvt-1
 
            m  = 2**k
            l  = nt/m
            l2 = l/2
 
!...        rows of diamond--
 
            do j1=1,m+1
               do j2=1,m
                     i1 = (j1-1)*l + 1
                     i2 = (j2-1)*l + l2 + 1
                     call midpt(xn(i1,i2,id,1),xn(i1,i2-l2,id,1),&
     &                          xn(i1,i2+l2,id,1),nn)
               end do
            end do
 
!...        columns of diamond--
 
            do j1=1,m+1
               do j2=1,m
                     i1 = (j2-1)*l + l2 + 1
                     i2 = (j1-1)*l + 1
                     call midpt(xn(i1,i2,id,1),xn(i1-l2,i2,id,1),&
     &                          xn(i1+l2,i2,id,1),nn)
               end do
            end do
 
!...        diagonals of diamond--
 
            do j1=1,m
               do j2=1,m
                     i1 = (j1-1)*l + l2 + 1
                     i2 = (j2-1)*l + l2 + 1
                     call midpt(xn(i1,i2,id,1),xn(i1-l2,i2+l2,id,1),&
     &                          xn(i1+l2,i2-l2,id,1),nn)
               end do
            enddo
         enddo
      end do
 end


subroutine midpt(x,x1,x2,nn)
!...  This routine finds the midpoint x along the shorter great circle
!...  arc between points x1 and x2 on the unit sphere.
 
      real x(nn,3), x1(nn,3), x2(nn,3)
 
      do j=1,3
         x(1,j) = x1(1,j) + x2(1,j)
      enddo
 
      xnorm = 1./sqrt(x(1,1)**2 + x(1,2)**2 + x(1,3)**2)
 
      do j=1,3
         x(1,j) = xnorm*x(1,j)
      enddo
end


subroutine ndarea(arn,arne,rarn,rarne,area,xn,nt)
!...  This routine computes the areas, arn, associated with the nodes
!...  on the unit sphere as well as the reciprocal areas, rarn.  These
!...  arrays have zero values along the upper right and lower right
!...  diamond edges.  Arrays arne and rarne are identical except they
!...  contain the actual areas and reciprocal areas, respectively, in
!...  these edge locations.
 
      real  arn(nt+1,nt+1),  rarn(nt+1,nt+1), area(nt+1,nt+1,2)
      real arne(nt+1,nt+1), rarne(nt+1,nt+1), xn(*)
 
      call areacalc(area,xn,nt)
      arn=0.0
      rarn=0.0

!...  Treat interior nodes.
      do i2=2,nt
         do i1=2,nt
            arn(  i1,i2) = (area(i1  ,i2  ,1) + area(i1  ,i2  ,2)&
     &                   +  area(i1+1,i2  ,1) + area(i1  ,i2-1,2)&
     &                   +  area(i1+1,i2-1,1) + area(i1+1,i2-1,2))/3.
            rarn( i1,i2) =  1./arn(i1,i2)
            arne( i1,i2) =     arn(i1,i2)
            rarne(i1,i2) =    rarn(i1,i2)
         end do
      end do
 
!...  Treat edge nodes.
      do i=2,nt
         arn(     i,1) = (area(   i,1  ,1) + area(i   ,1,2)&
     &                 +  area( i+1,1  ,1))/1.5
         arn(  nt+1,i) = (area(nt+1,i  ,1) + area(nt+1,i,2)&
     &                 +  area(nt+1,i-1,2))/1.5
         rarn(    i,1) =  1./arn(   i,1)
         rarn( nt+1,i) =  1./arn(nt+1,i)
         arne(    i,1) =     arn(   i,1)
         arne( nt+1,i) =     arn(nt+1,i)
         rarne(   i,1) =    rarn(   i,1)
         rarne(nt+1,i) =    rarn(nt+1,i)
         arne(    1,i) =     arn(   i,1)
         arne( i,nt+1) =     arn(nt+1,i)
         rarne(   1,i) =    rarn(   i,1)
         rarne(i,nt+1) =    rarn(nt+1,i)
      end do
 
!...  Treat pentagonal nodes.
      arn(     1,   1) = 5.*area(2,1,1)/3.
      arn(  nt+1,   1) =    arn(1,1)
      rarn(    1,   1) = 1./arn(1,1)
      rarn( nt+1,   1) =   rarn(1,1)
      arne(    1,   1) =    arn(1,1)
      arne( nt+1,   1) =    arn(1,1)
      arne(    1,nt+1) =    arn(1,1)
      arne( nt+1,nt+1) =    arn(1,1)
      rarne(   1,   1) =   rarn(1,1)
      rarne(nt+1,   1) =   rarn(1,1)
      rarne(   1,nt+1) =   rarn(1,1)
      rarne(nt+1,nt+1) =   rarn(1,1)
 end subroutine
 
subroutine areacalc(area,xn,nt)
!...  This routine computes the areas of the spherical triangles in
!...  a diamond on the unit sphere.
 
      real area(nt+1,nt+1,2), xn(nt+1,nt+1,10,3), xv(3,3)

      area=0.0
       
      do i2=1,nt
         do i1=2,nt+1
            xv(1,1) = xn(i1  ,i2  ,1,1)
            xv(1,2) = xn(i1  ,i2  ,1,2)
            xv(1,3) = xn(i1  ,i2  ,1,3)
            xv(2,1) = xn(i1-1,i2+1,1,1)
            xv(2,2) = xn(i1-1,i2+1,1,2)
            xv(2,3) = xn(i1-1,i2+1,1,3)
            xv(3,1) = xn(i1-1,i2  ,1,1)
            xv(3,2) = xn(i1-1,i2  ,1,2)
            xv(3,3) = xn(i1-1,i2  ,1,3)
            t1 = xv(1,1)*xv(2,1) + xv(1,2)*xv(2,2) + xv(1,3)*xv(2,3)
            t2 = xv(2,1)*xv(3,1) + xv(2,2)*xv(3,2) + xv(2,3)*xv(3,3)
            t3 = xv(3,1)*xv(1,1) + xv(3,2)*xv(1,2) + xv(3,3)*xv(1,3)
            t1 = 0.5*acos(t1)
            t2 = 0.5*acos(t2)
            t3 = 0.5*acos(t3)
            s  = 0.5*(t1 + t2 + t3)
            a  = tan(s)*tan(s-t1)*tan(s-t2)*tan(s-t3)
            area(i1,i2,1) = 4.*atan(sqrt(a))

            xv(1,1) = xn(i1  ,i2  ,1,1)
            xv(1,2) = xn(i1  ,i2  ,1,2)
            xv(1,3) = xn(i1  ,i2  ,1,3)
            xv(2,1) = xn(i1  ,i2+1,1,1)
            xv(2,2) = xn(i1  ,i2+1,1,2)
            xv(2,3) = xn(i1  ,i2+1,1,3)
            xv(3,1) = xn(i1-1,i2+1,1,1)
            xv(3,2) = xn(i1-1,i2+1,1,2)
            xv(3,3) = xn(i1-1,i2+1,1,3)
            t1 = xv(1,1)*xv(2,1) + xv(1,2)*xv(2,2) + xv(1,3)*xv(2,3)
            t2 = xv(2,1)*xv(3,1) + xv(2,2)*xv(3,2) + xv(2,3)*xv(3,3)
            t3 = xv(3,1)*xv(1,1) + xv(3,2)*xv(1,2) + xv(3,3)*xv(1,3)
            t1 = 0.5*acos(t1)
            t2 = 0.5*acos(t2)
            t3 = 0.5*acos(t3)
            s  = 0.5*(t1 + t2 + t3)
            a  = tan(s)*tan(s-t1)*tan(s-t2)*tan(s-t3)
            area(i1,i2,2) = 4.*atan(sqrt(a))

         enddo
      enddo
end subroutine

!> Generate a grid function from spherical harmonics coefficients
!>
!> The sub-routine generates a 3D grid function from the given coefficients of
!> the expansion of that function in terms of spherical harmonics on each
!> radial layer.
subroutine shtofe(s,shar,lmax)
 
      include 'size.h'
      include 'pcom.h'
      integer lmax, lmaximum
      real s((nt+1)**2,nd,nr+1), shar(2,(lmax+1)*(lmax+2)/2,nr+1)
      real plm((lmax+1)*(lmax+2)), csm(0:128,2)
      common /mesh/ xn((nt+1)**2,nd,3)
	
	lmaximum=lmax 
      s=0.0
 
      do ii=1,(nt+1)**2
         do id=1,nd
 
            phi = atan2(xn(ii,id,2) + 1.e-30, xn(ii,id,1))
 
            do m=0,lmaximum
               csm(m,1) = cos(m*phi)
               csm(m,2) = sin(m*phi)
            end do
 
            if(mod(id, 5) .eq. 1)&
     &         call plmbar(plm,plm,lmaximum,xn(ii,id,3),0)
 
            k = 0
 
            do l=0,lmaximum
               do m=0,l
                  k = k + 1
 
                  do ir=1,nr+1
                     s(ii,id,ir) = ((s(ii,id,ir)&
     &                           +  (plm(k)*csm(m,1))*shar(1,k,ir))&
     &                           +  (plm(k)*csm(m,2))*shar(2,k,ir))
                  end do
 
               end do
            end do
 
         end do
	enddo
end


blockdata bdconvect

	real meantemp(129), meantemp_bs(129)
      common /mtemp/ meantemp, meantemp_bs

!	Profile for nr = 128 resolution:
!     Mean temperature profile for strongly bottom heated model
!     Schuberth et al. gcube 2009

      data meantemp_bs/&
     & 3.0000000e+02, 7.2118800e+02, 1.0209510e+03, 1.2499570e+03,&
     & 1.4206910e+03, 1.5506250e+03, 1.6490020e+03, 1.7226340e+03,&
     & 1.7784700e+03, 1.8211660e+03, 1.8540640e+03, 1.8809900e+03,&
     & 1.9041580e+03, 1.9215510e+03, 1.9335260e+03, 1.9424690e+03,&
     & 1.9497720e+03, 1.9567120e+03, 1.9634020e+03, 1.9700150e+03,&
     & 1.9766080e+03, 1.9833160e+03, 1.9902840e+03, 1.9975780e+03,&
     & 2.0050360e+03, 2.0127050e+03, 2.0207260e+03, 2.0287030e+03,&
     & 2.0371460e+03, 2.0452620e+03, 2.0534720e+03, 2.0617110e+03,&
     & 2.0696770e+03, 2.0775040e+03, 2.0854490e+03, 2.0933810e+03,&
     & 2.1012680e+03, 2.1092260e+03, 2.1172470e+03, 2.1253440e+03,&
     & 2.1334370e+03, 2.1415970e+03, 2.1499480e+03, 2.1585630e+03,&
     & 2.1672930e+03, 2.1758500e+03, 2.1840060e+03, 2.1917910e+03,&
     & 2.1994580e+03, 2.2073450e+03, 2.2157030e+03, 2.2246140e+03,&
     & 2.2339600e+03, 2.2434830e+03, 2.2528890e+03, 2.2619630e+03,&
     & 2.2706260e+03, 2.2789390e+03, 2.2870550e+03, 2.2951410e+03,&
     & 2.3032670e+03, 2.3113570e+03, 2.3192350e+03, 2.3267530e+03,&
     & 2.3338810e+03, 2.3407070e+03, 2.3473300e+03, 2.3537710e+03,&
     & 2.3599610e+03, 2.3658010e+03, 2.3712310e+03, 2.3762530e+03,&
     & 2.3809140e+03, 2.3852620e+03, 2.3893430e+03, 2.3931860e+03,&
     & 2.3968060e+03, 2.4002120e+03, 2.4034520e+03, 2.4066350e+03,&
     & 2.4098850e+03, 2.4132350e+03, 2.4165720e+03, 2.4196820e+03,&
     & 2.4224000e+03, 2.4247260e+03, 2.4268280e+03, 2.4289490e+03,&
     & 2.4312780e+03, 2.4338770e+03, 2.4366870e+03, 2.4395810e+03,&
     & 2.4424480e+03, 2.4452080e+03, 2.4477990e+03, 2.4501290e+03,&
     & 2.4520790e+03, 2.4535320e+03, 2.4544260e+03, 2.4547630e+03,&
     & 2.4546100e+03, 2.4540690e+03, 2.4532190e+03, 2.4520610e+03,&
     & 2.4505210e+03, 2.4484910e+03, 2.4458500e+03, 2.4424470e+03,&
     & 2.4381390e+03, 2.4329080e+03, 2.4269790e+03, 2.4207860e+03,&
     & 2.4148000e+03, 2.4094040e+03, 2.4049250e+03, 2.4017200e+03,&
     & 2.4001760e+03, 2.4006700e+03, 2.4037220e+03, 2.4101750e+03,&
     & 2.4215510e+03, 2.4408650e+03, 2.4738140e+03, 2.5303970e+03,&
     & 2.6282240e+03, 2.7968510e+03, 3.0753860e+03, 3.4877340e+03,&
     & 4.2000000e+03/
     
!     new geotherm 200Ma forward simulation 08/11

      data meantemp/&
     & 300.0, 744.2, 1049.6, 1290.3, 1472.9, 1623.1, 1740.5, 1832.6, 1896.8,&
     & 1942.9, 1970.1, 1986.8, 1995.9, 2002.9, 2008.4, 2014.0, 2018.6,&
     & 2022.6, 2024.8, 2026.1, 2026.7, 2027.1, 2026.6, 2024.9, 2022.1,&
     & 2019.4, 2019.3, 2022.0, 2026.8, 2033.0, 2040.1, 2048.0, 2056.3,&
     & 2065.1, 2074.0, 2082.8, 2091.6, 2100.3, 2109.1, 2118.1, 2127.3,&
     & 2136.7, 2146.4, 2156.1, 2165.9, 2175.5, 2185.1, 2194.6, 2204.1,&
     & 2213.3, 2222.2, 2230.8, 2239.0, 2247.0, 2254.7, 2262.4, 2269.9,&
     & 2277.3, 2284.6, 2291.5, 2298.2, 2304.5, 2310.4, 2316.1, 2321.6,&
     & 2326.9, 2332.0, 2337.0, 2341.9, 2346.9, 2351.9, 2356.8, 2361.4,&
     & 2365.7, 2369.7, 2373.5, 2377.2, 2380.8, 2384.5, 2388.4, 2392.5,&
     & 2396.8, 2401.2, 2405.6, 2409.7, 2413.6, 2417.1, 2420.3, 2423.4,&
     & 2426.4, 2429.2, 2431.8, 2434.2, 2436.3, 2438.4, 2440.4, 2442.3,&
     & 2443.7, 2444.6, 2445.1, 2445.2, 2444.9, 2444.0, 2442.4, 2440.0,&
     & 2436.8, 2432.8, 2428.0, 2422.3, 2415.8, 2408.5, 2400.7, 2392.7,&
     & 2384.6, 2376.8, 2369.6, 2363.4, 2359.1, 2357.9, 2362.0, 2375.2,&
     & 2403.1, 2454.8, 2542.8, 2684.9, 2904.5, 3228.5, 3671.1, 4200.0/
   
   
   
end blockdata
    
