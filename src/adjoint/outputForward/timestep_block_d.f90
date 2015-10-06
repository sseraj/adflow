!        generated by tapenade     (inria, tropics team)
!  tapenade 3.10 (r5363) -  9 sep 2014 09:53
!
!  differentiation of timestep_block in forward (tangent) mode (with options i4 dr8 r8):
!   variations   of useful results: *radi *radj *radk
!   with respect to varying inputs: gammainf rhoinf pinfcorr *p
!                *sfacei *sfacej *sfacek *w *si *sj *sk
!   plus diff mem management of: p:in sfacei:in sfacej:in sfacek:in
!                w:in si:in sj:in sk:in radi:in radj:in radk:in
!
!      ******************************************************************
!      *                                                                *
!      * file:          timestep.f90                                    *
!      * author:        edwin van der weide                             *
!      * starting date: 03-17-2003                                      *
!      * last modified: 06-28-2005                                      *
!      *                                                                *
!      ******************************************************************
!
subroutine timestep_block_d(onlyradii)
!
!      ******************************************************************
!      *                                                                *
!      * timestep computes the time step, or more precisely the time    *
!      * step divided by the volume per unit cfl, in the owned cells.   *
!      * however, for the artificial dissipation schemes, the spectral  *
!      * radii in the halo's are needed. therefore the loop is taken    *
!      * over the the first level of halo cells. the spectral radii are *
!      * stored and possibly modified for high aspect ratio cells.      *
!      *                                                                *
!      ******************************************************************
!
  use blockpointers
  use constants
  use flowvarrefstate
  use inputdiscretization
  use inputiteration
  use inputphysics
  use inputtimespectral
  use iteration
  use section
  implicit none
! the rest of this file can be skipped if only the spectral
! radii need to be computed.
!
!      subroutine argument.
!
  logical, intent(in) :: onlyradii
!
!      local parameters.
!
  real(kind=realtype), parameter :: b=2.0_realtype
!
!      local variables.
!
  integer(kind=inttype) :: i, j, k, ii
  real(kind=realtype) :: plim, rlim, clim2
  real(kind=realtype) :: clim2d
  real(kind=realtype) :: uux, uuy, uuz, cc2, qsi, qsj, qsk, sx, sy, sz, &
& rmu
  real(kind=realtype) :: uuxd, uuyd, uuzd, cc2d, qsid, qsjd, qskd, sxd, &
& syd, szd
  real(kind=realtype) :: ri, rj, rk, rij, rjk, rki
  real(kind=realtype) :: rid, rjd, rkd, rijd, rjkd, rkid
  real(kind=realtype) :: vsi, vsj, vsk, rfl, dpi, dpj, dpk
  real(kind=realtype) :: sface, tmp
  real(kind=realtype) :: sfaced
  logical :: radiineeded, doscaling
  intrinsic max
  intrinsic abs
  intrinsic sqrt
  real(kind=realtype) :: arg1
  real(kind=realtype) :: arg1d
  real(kind=realtype) :: result1
  real(kind=realtype) :: result1d
  real(kind=realtype) :: pwx1
  real(kind=realtype) :: pwx1d
  real(kind=realtype) :: abs1d
  real(kind=realtype) :: abs0d
  real(kind=realtype) :: abs2
  real(kind=realtype) :: abs2d
  real(kind=realtype) :: abs1
  real(kind=realtype) :: abs0
!
!      ******************************************************************
!      *                                                                *
!      * begin execution                                                *
!      *                                                                *
!      ******************************************************************
!
! determine whether or not the spectral radii are needed for the
! flux computation.
  radiineeded = radiineededcoarse
  if (currentlevel .le. groundlevel) radiineeded = radiineededfine
! return immediately if only the spectral radii must be computed
! and these are not needed for the flux computation.
  if (onlyradii .and. (.not.radiineeded)) then
    radid = 0.0_8
    radjd = 0.0_8
    radkd = 0.0_8
    return
  else
! set the value of plim. to be fully consistent this must have
! the dimension of a pressure. therefore a fraction of pinfcorr
! is used. idem for rlim; compute clim2 as well.
    plim = 0.001_realtype*pinfcorr
    rlim = 0.001_realtype*rhoinf
    clim2d = (0.000001_realtype*(gammainfd*pinfcorr+gammainf*pinfcorrd)*&
&     rhoinf-0.000001_realtype*gammainf*pinfcorr*rhoinfd)/rhoinf**2
    clim2 = 0.000001_realtype*gammainf*pinfcorr/rhoinf
    doscaling = dirscaling .and. currentlevel .le. groundlevel
! initialize sface to zero. this value will be used if the
! block is not moving.
    sface = zero
!
!          **************************************************************
!          *                                                            *
!          * inviscid contribution, depending on the preconditioner.    *
!          * compute the cell centered values of the spectral radii.    *
!          *                                                            *
!          **************************************************************
!
    select case  (precond) 
    case (noprecond) 
      radid = 0.0_8
      radjd = 0.0_8
      radkd = 0.0_8
      sfaced = 0.0_8
! no preconditioner. simply the standard spectral radius.
! loop over the cells, including the first level halo.
      do k=1,ke
        do j=1,je
          do i=1,ie
! compute the velocities and speed of sound squared.
            uuxd = wd(i, j, k, ivx)
            uux = w(i, j, k, ivx)
            uuyd = wd(i, j, k, ivy)
            uuy = w(i, j, k, ivy)
            uuzd = wd(i, j, k, ivz)
            uuz = w(i, j, k, ivz)
            cc2d = (gamma(i, j, k)*pd(i, j, k)*w(i, j, k, irho)-gamma(i&
&             , j, k)*p(i, j, k)*wd(i, j, k, irho))/w(i, j, k, irho)**2
            cc2 = gamma(i, j, k)*p(i, j, k)/w(i, j, k, irho)
            if (cc2 .lt. clim2) then
              cc2d = clim2d
              cc2 = clim2
            else
              cc2 = cc2
            end if
! set the dot product of the grid velocity and the
! normal in i-direction for a moving face. to avoid
! a number of multiplications by 0.5 simply the sum
! is taken.
            if (addgridvelocities) then
              sfaced = sfaceid(i-1, j, k) + sfaceid(i, j, k)
              sface = sfacei(i-1, j, k) + sfacei(i, j, k)
            end if
! spectral radius in i-direction.
            sxd = sid(i-1, j, k, 1) + sid(i, j, k, 1)
            sx = si(i-1, j, k, 1) + si(i, j, k, 1)
            syd = sid(i-1, j, k, 2) + sid(i, j, k, 2)
            sy = si(i-1, j, k, 2) + si(i, j, k, 2)
            szd = sid(i-1, j, k, 3) + sid(i, j, k, 3)
            sz = si(i-1, j, k, 3) + si(i, j, k, 3)
            qsid = uuxd*sx + uux*sxd + uuyd*sy + uuy*syd + uuzd*sz + uuz&
&             *szd - sfaced
            qsi = uux*sx + uuy*sy + uuz*sz - sface
            if (qsi .ge. 0.) then
              abs0d = qsid
              abs0 = qsi
            else
              abs0d = -qsid
              abs0 = -qsi
            end if
            arg1d = cc2d*(sx**2+sy**2+sz**2) + cc2*(2*sx*sxd+2*sy*syd+2*&
&             sz*szd)
            arg1 = cc2*(sx**2+sy**2+sz**2)
            if (arg1 .eq. 0.0_8) then
              result1d = 0.0_8
            else
              result1d = arg1d/(2.0*sqrt(arg1))
            end if
            result1 = sqrt(arg1)
            radid(i, j, k) = half*(abs0d+result1d)
            radi(i, j, k) = half*(abs0+result1)
! the grid velocity in j-direction.
            if (addgridvelocities) then
              sfaced = sfacejd(i, j-1, k) + sfacejd(i, j, k)
              sface = sfacej(i, j-1, k) + sfacej(i, j, k)
            end if
! spectral radius in j-direction.
            sxd = sjd(i, j-1, k, 1) + sjd(i, j, k, 1)
            sx = sj(i, j-1, k, 1) + sj(i, j, k, 1)
            syd = sjd(i, j-1, k, 2) + sjd(i, j, k, 2)
            sy = sj(i, j-1, k, 2) + sj(i, j, k, 2)
            szd = sjd(i, j-1, k, 3) + sjd(i, j, k, 3)
            sz = sj(i, j-1, k, 3) + sj(i, j, k, 3)
            qsjd = uuxd*sx + uux*sxd + uuyd*sy + uuy*syd + uuzd*sz + uuz&
&             *szd - sfaced
            qsj = uux*sx + uuy*sy + uuz*sz - sface
            if (qsj .ge. 0.) then
              abs1d = qsjd
              abs1 = qsj
            else
              abs1d = -qsjd
              abs1 = -qsj
            end if
            arg1d = cc2d*(sx**2+sy**2+sz**2) + cc2*(2*sx*sxd+2*sy*syd+2*&
&             sz*szd)
            arg1 = cc2*(sx**2+sy**2+sz**2)
            if (arg1 .eq. 0.0_8) then
              result1d = 0.0_8
            else
              result1d = arg1d/(2.0*sqrt(arg1))
            end if
            result1 = sqrt(arg1)
            radjd(i, j, k) = half*(abs1d+result1d)
            radj(i, j, k) = half*(abs1+result1)
! the grid velocity in k-direction.
            if (addgridvelocities) then
              sfaced = sfacekd(i, j, k-1) + sfacekd(i, j, k)
              sface = sfacek(i, j, k-1) + sfacek(i, j, k)
            end if
! spectral radius in k-direction.
            sxd = skd(i, j, k-1, 1) + skd(i, j, k, 1)
            sx = sk(i, j, k-1, 1) + sk(i, j, k, 1)
            syd = skd(i, j, k-1, 2) + skd(i, j, k, 2)
            sy = sk(i, j, k-1, 2) + sk(i, j, k, 2)
            szd = skd(i, j, k-1, 3) + skd(i, j, k, 3)
            sz = sk(i, j, k-1, 3) + sk(i, j, k, 3)
            qskd = uuxd*sx + uux*sxd + uuyd*sy + uuy*syd + uuzd*sz + uuz&
&             *szd - sfaced
            qsk = uux*sx + uuy*sy + uuz*sz - sface
            if (qsk .ge. 0.) then
              abs2d = qskd
              abs2 = qsk
            else
              abs2d = -qskd
              abs2 = -qsk
            end if
            arg1d = cc2d*(sx**2+sy**2+sz**2) + cc2*(2*sx*sxd+2*sy*syd+2*&
&             sz*szd)
            arg1 = cc2*(sx**2+sy**2+sz**2)
            if (arg1 .eq. 0.0_8) then
              result1d = 0.0_8
            else
              result1d = arg1d/(2.0*sqrt(arg1))
            end if
            result1 = sqrt(arg1)
            radkd(i, j, k) = half*(abs2d+result1d)
            radk(i, j, k) = half*(abs2+result1)
! compute the inviscid contribution to the time step.
            dtl(i, j, k) = radi(i, j, k) + radj(i, j, k) + radk(i, j, k)
!
!          **************************************************************
!          *                                                            *
!          * adapt the spectral radii if directional scaling must be    *
!          * applied.                                                   *
!          *                                                            *
!          **************************************************************
!
            if (doscaling) then
              if (radi(i, j, k) .lt. eps) then
                ri = eps
                rid = 0.0_8
              else
                rid = radid(i, j, k)
                ri = radi(i, j, k)
              end if
              if (radj(i, j, k) .lt. eps) then
                rj = eps
                rjd = 0.0_8
              else
                rjd = radjd(i, j, k)
                rj = radj(i, j, k)
              end if
              if (radk(i, j, k) .lt. eps) then
                rk = eps
                rkd = 0.0_8
              else
                rkd = radkd(i, j, k)
                rk = radk(i, j, k)
              end if
! compute the scaling in the three coordinate
! directions.
              pwx1d = (rid*rj-ri*rjd)/rj**2
              pwx1 = ri/rj
              if (pwx1 .gt. 0.0_8 .or. (pwx1 .lt. 0.0_8 .and. adis .eq. &
&                 int(adis))) then
                rijd = adis*pwx1**(adis-1)*pwx1d
              else if (pwx1 .eq. 0.0_8 .and. adis .eq. 1.0) then
                rijd = pwx1d
              else
                rijd = 0.0_8
              end if
              rij = pwx1**adis
              pwx1d = (rjd*rk-rj*rkd)/rk**2
              pwx1 = rj/rk
              if (pwx1 .gt. 0.0_8 .or. (pwx1 .lt. 0.0_8 .and. adis .eq. &
&                 int(adis))) then
                rjkd = adis*pwx1**(adis-1)*pwx1d
              else if (pwx1 .eq. 0.0_8 .and. adis .eq. 1.0) then
                rjkd = pwx1d
              else
                rjkd = 0.0_8
              end if
              rjk = pwx1**adis
              pwx1d = (rkd*ri-rk*rid)/ri**2
              pwx1 = rk/ri
              if (pwx1 .gt. 0.0_8 .or. (pwx1 .lt. 0.0_8 .and. adis .eq. &
&                 int(adis))) then
                rkid = adis*pwx1**(adis-1)*pwx1d
              else if (pwx1 .eq. 0.0_8 .and. adis .eq. 1.0) then
                rkid = pwx1d
              else
                rkid = 0.0_8
              end if
              rki = pwx1**adis
! create the scaled versions of the aspect ratios.
! note that the multiplication is done with radi, radj
! and radk, such that the influence of the clipping
! is negligible.
              radid(i, j, k) = radid(i, j, k)*(one+one/rij+rki) + radi(i&
&               , j, k)*(rkid-one*rijd/rij**2)
              radi(i, j, k) = radi(i, j, k)*(one+one/rij+rki)
              radjd(i, j, k) = radjd(i, j, k)*(one+one/rjk+rij) + radj(i&
&               , j, k)*(rijd-one*rjkd/rjk**2)
              radj(i, j, k) = radj(i, j, k)*(one+one/rjk+rij)
              radkd(i, j, k) = radkd(i, j, k)*(one+one/rki+rjk) + radk(i&
&               , j, k)*(rjkd-one*rkid/rki**2)
              radk(i, j, k) = radk(i, j, k)*(one+one/rki+rjk)
            end if
          end do
        end do
      end do
    case (turkel) 
      call returnFail('timestep', &
&                 'turkel preconditioner not implemented yet')
      radid = 0.0_8
      radjd = 0.0_8
      radkd = 0.0_8
    case (choimerkle) 
      call returnFail('timestep', &
&                 'choi merkle preconditioner not implemented yet')
      radid = 0.0_8
      radjd = 0.0_8
      radkd = 0.0_8
    case default
      radid = 0.0_8
      radjd = 0.0_8
      radkd = 0.0_8
    end select
  end if
end subroutine timestep_block_d