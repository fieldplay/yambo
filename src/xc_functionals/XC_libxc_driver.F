!
! Copyright (C) 2000-2010 M. Gruning and the YAMBO team 
!              http://www.yambo-code.org
! 
! This file is distributed under the terms of the GNU 
! General Public License. You can redistribute it and/or 
! modify it under the terms of the GNU General Public 
! License as published by the Free Software Foundation; 
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will 
! be useful, but WITHOUT ANY WARRANTY; without even the 
! implied warranty of MERCHANTABILITY or FITNESS FOR A 
! PARTICULAR PURPOSE.  See the GNU General Public License 
! for more details.
!
! You should have received a copy of the GNU General Public 
! License along with this program; if not, write to the Free 
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
subroutine XC_libxc_driver(en,Xk,KIND,FUNCTIONAL,ORDER)
 !
 ! In case yambo is linked with libxc, this routine use the libxc
 ! routine to evaluate the xc functional (28/02/2010: only LDA)
 !
 use pars,          ONLY:SP,DP,PI
 use R_lattice,     ONLY:bz_samp
 use D_lattice,     ONLY:DL_vol
 use com,           ONLY:msg,warning
 use electrons,     ONLY:levels,n_spin
 use FFT_m,         ONLY:fft_size
 use libxc_int,     ONLY:xc_fnctl_t,XC_y2libxc,xc_setup_fnctl
 use xc_functionals,ONLY:E_xc,F_xc,V_xc,two_spin_density,&
&                        xc_string,XC_LDA_C_KP,XC_FAMILY_LDA  
 implicit none
 type(levels) ::en
 type(bz_samp)::Xk
 integer      ::KIND,FUNCTIONAL,ORDER
 !
 ! Work Space
 !
 integer  :: i1,i2,ixc,LIBXC_FUNC
 !
 ! XC routines arrays
 !
 real(SP) :: rho_sp(fft_size,n_spin),rspts(fft_size)
 real(DP) :: tmp_rho(n_spin,fft_size)
 !
 ! note that multidimensional dvxc & vxc is allowed only in xcspol
 !
 real(DP) :: tmp_dvxc(fft_size),tmp_vxc(n_spin,fft_size),tmp_exc(fft_size)
 !
 ! Functional and Functional infos
 !
 type(xc_fnctl_t) :: fnctl(2) 
 !
 !=============================== 
 ! Convert and Initialize
 !===============================
 !
 tmp_exc=0._DP
 tmp_vxc=0._DP
 tmp_dvxc=0._DP
 !
 LIBXC_FUNC = XC_y2libxc(FUNCTIONAL,KIND)
 call xc_setup_fnctl(fnctl,LIBXC_FUNC,n_spin)
 !
 !===============================
 ! Electronic/spin density 
 !===============================
 !
 call el_density(en,Xk,rho_sp,.false.)
 !
 forall(i1=1:fft_size,i2=1:n_spin)  tmp_rho(i2,i1)=rho_sp(i1,i2)*real(fft_size,DP)/real(DL_vol,DP)
 !
 !===========================
 ! Evaluate the xc functional
 !===========================
 !
 if (order==0) E_xc=0.
 if (order==1) V_xc=0.
 if (order==2) F_xc=0.
 !
 !
 do ixc = 1,2
   if (fnctl(ixc)%id == 0) cycle
   if (fnctl(ixc)%family==XC_FAMILY_LDA) then 
     select case(ORDER)
       case(0)
         call xc_f90_lda_exc(fnctl(ixc)%conf, fft_size, tmp_rho(1,1), tmp_exc(1))
         E_xc = E_xc + tmp_exc    
       case(1)
         call xc_f90_lda_vxc(fnctl(ixc)%conf, fft_size, tmp_rho(1,1), tmp_vxc(1,1))
         forall(i1=1:fft_size,i2=1:n_spin) V_xc(i1,i2) = V_xc(i1,i2) + tmp_vxc(i2,i1)         
       case(2) 
         call xc_f90_lda_fxc(fnctl(ixc)%conf, fft_size, tmp_rho(1,1), tmp_dvxc(1))
         F_xc = F_xc + tmp_dvxc
     end select
   end if
 enddo
 !
end subroutine